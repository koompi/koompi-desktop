mod background;
mod configs;
mod constants;
mod desktop_item;
mod desktop_manager;
mod errors;
mod gui;
mod styles;
mod window_state;

use desktop_manager::DesktopManager;
use gui::{ContextMenu, Desktop};
use window_state::WindowState;

use iced_wgpu::{wgpu, Settings};
use iced_winit::{conversion, futures, program, winit, Application, Clipboard, Debug};
use winit::{
    dpi::{PhysicalPosition, PhysicalSize},
    event::{
        ElementState, Event, KeyboardInput, ModifiersState, MouseButton, VirtualKeyCode,
        WindowEvent,
    },
    event_loop::{ControlFlow, EventLoop},
    platform::unix::{WindowBuilderExtUnix, XWindowType},
    window::WindowBuilder,
};
const DESKTOP_CONF: &str = "desktop/desktop.toml";

fn main() {
    match DesktopManager::new(dirs_next::config_dir().unwrap().join(DESKTOP_CONF)) {
        Ok(desktop_manager) => {
            let event_loop = EventLoop::new();
            let mut cursor_position = PhysicalPosition::new(-1.0, -1.0);
            let mut modifiers = ModifiersState::default();
            let mut debug = Debug::new();
            let mut context_menu = None;
            let settings = Settings {
                default_text_size: 13,
                ..Settings::default()
            };

            let (size, position) = event_loop
                .primary_monitor()
                .map(|m| (m.size(), m.position()))
                .unwrap_or((PhysicalSize::new(1920, 1080), PhysicalPosition::new(0, 0)));
            let desktop_window = WindowBuilder::new()
                .with_inner_size(size)
                .with_x11_window_type(vec![XWindowType::Desktop])
                .build(&event_loop)
                .unwrap();
            desktop_window.set_outer_position(position);
            let mut clipboard = Clipboard::connect(&desktop_window);
            let mut desktop_window_state =
                futures::executor::block_on(WindowState::new(desktop_window, Some(&settings)));

            let desktop_conf = desktop_manager.config();
            let desktop_items = desktop_manager.desktop_items();
            let (desktop, _) = Desktop::new((
                desktop_window_state.window.inner_size().height,
                desktop_conf.to_owned(),
                desktop_items.to_owned(),
            ));
            let mut desktop_program_state = program::State::new(
                desktop,
                desktop_window_state.viewport.logical_size(),
                conversion::cursor_position(
                    cursor_position,
                    desktop_window_state.viewport.scale_factor(),
                ),
                &mut desktop_window_state.renderer,
                &mut debug,
            );

            event_loop.run(move |event, event_loop, control_flow| {
                *control_flow = ControlFlow::Wait;

                match event {
                    Event::WindowEvent { ref event, .. } => {
                        match event {
                            WindowEvent::CloseRequested => *control_flow = ControlFlow::Exit,
                            WindowEvent::KeyboardInput { input, .. } => match input {
                                KeyboardInput {
                                    state: ElementState::Pressed,
                                    virtual_keycode: Some(VirtualKeyCode::Escape),
                                    ..
                                } => {
                                    if context_menu.is_some() {
                                        context_menu = None;
                                    }
                                }
                                _ => {}
                            },
                            WindowEvent::CursorMoved { position, .. } => {
                                cursor_position = *position
                            }
                            WindowEvent::ModifiersChanged(modi) => modifiers = *modi,
                            WindowEvent::Resized(new_size) => {
                                desktop_window_state.resize(*new_size, None);
                            }
                            WindowEvent::ScaleFactorChanged {
                                new_inner_size,
                                scale_factor,
                            } => {
                                desktop_window_state.resize(**new_inner_size, Some(*scale_factor));
                            }
                            WindowEvent::MouseInput {
                                state: ElementState::Pressed,
                                button,
                                ..
                            } => match button {
                                MouseButton::Right => {
                                    let context_menu_size = PhysicalSize::new(300.0, 210.0);
                                    let context_menu_window = WindowBuilder::new()
                                        .with_inner_size(context_menu_size)
                                        .with_x11_window_type(vec![
                                            XWindowType::Desktop,
                                            XWindowType::PopupMenu,
                                        ])
                                        .build(&event_loop)
                                        .unwrap();
                                    if let Some(monitor) = context_menu_window.primary_monitor() {
                                        let prefered_x = if context_menu_size.width
                                            + cursor_position.x
                                            > monitor.size().width as f64
                                        {
                                            cursor_position.x - context_menu_size.width
                                        } else {
                                            cursor_position.x
                                        };
                                        let prefered_y = if context_menu_size.height
                                            + cursor_position.y
                                            > monitor.size().height as f64
                                        {
                                            cursor_position.y - context_menu_size.height
                                        } else {
                                            cursor_position.y
                                        };

                                        context_menu_window.set_outer_position(
                                            PhysicalPosition::new(prefered_x, prefered_y),
                                        );
                                    }
                                    let context_menu_gui = ContextMenu::new();

                                    let mut context_menu_window_state = futures::executor::block_on(
                                        WindowState::new(context_menu_window, Some(&settings)),
                                    );
                                    let context_menu_program_state = program::State::new(
                                        context_menu_gui,
                                        context_menu_window_state.viewport.logical_size(),
                                        conversion::cursor_position(
                                            cursor_position,
                                            context_menu_window_state.viewport.scale_factor(),
                                        ),
                                        &mut context_menu_window_state.renderer,
                                        &mut debug,
                                    );
                                    let _ = context_menu_window;
                                    context_menu = Some((
                                        context_menu_window_state,
                                        context_menu_program_state,
                                    ));
                                }
                                _ => context_menu = None,
                            },
                            _ => {}
                        }

                        if let Some(event) = conversion::window_event(
                            &event,
                            desktop_window_state.viewport.scale_factor(),
                            modifiers,
                        ) {
                            desktop_program_state.queue_event(event);
                        }

                        if let Some((win_state, prog_state)) = &mut context_menu {
                            if let Some(event) = conversion::window_event(
                                &event,
                                win_state.viewport.scale_factor(),
                                modifiers,
                            ) {
                                prog_state.queue_event(event);
                            }
                        }
                    }
                    Event::MainEventsCleared => {
                        if let Some((win_state, prog_state)) = &mut context_menu {
                            if !prog_state.is_queue_empty() {
                                // We update iced
                                let _ = prog_state.update(
                                    win_state.viewport.logical_size(),
                                    conversion::cursor_position(
                                        cursor_position,
                                        win_state.viewport.scale_factor(),
                                    ),
                                    &mut win_state.renderer,
                                    &mut clipboard,
                                    &mut debug,
                                );

                                win_state.window.request_redraw();
                            }
                        } else {
                            if !desktop_program_state.is_queue_empty() {
                                // We update iced
                                let _ = desktop_program_state.update(
                                    desktop_window_state.viewport.logical_size(),
                                    conversion::cursor_position(
                                        cursor_position,
                                        desktop_window_state.viewport.scale_factor(),
                                    ),
                                    &mut desktop_window_state.renderer,
                                    &mut clipboard,
                                    &mut debug,
                                );

                                desktop_window_state.window.request_redraw();
                            }
                        }
                    }
                    Event::RedrawRequested(_) => {
                        if let Some((win_state, prog_state)) = &mut context_menu {
                            win_state.update();
                            match win_state.render(prog_state.primitive(), &debug.overlay()) {
                                Ok(()) => {}
                                Err(wgpu::SwapChainError::Lost) => {
                                    let size = win_state.viewport.physical_size();
                                    win_state
                                        .resize(PhysicalSize::new(size.width, size.height), None);
                                }
                                // The system is out of memory, we should probably quit
                                Err(wgpu::SwapChainError::OutOfMemory) => {
                                    *control_flow = ControlFlow::Exit
                                }
                                // All other errors (Outdated, Timeout) should be resolved by the next frame
                                Err(e) => eprintln!("{:?}", e),
                            }
                        } else {
                            desktop_window_state.update();
                            match desktop_window_state
                                .render(desktop_program_state.primitive(), &debug.overlay())
                            {
                                Ok(()) => {}
                                Err(wgpu::SwapChainError::Lost) => {
                                    let size = desktop_window_state.viewport.physical_size();
                                    desktop_window_state
                                        .resize(PhysicalSize::new(size.width, size.height), None);
                                }
                                // The system is out of memory, we should probably quit
                                Err(wgpu::SwapChainError::OutOfMemory) => {
                                    *control_flow = ControlFlow::Exit
                                }
                                // All other errors (Outdated, Timeout) should be resolved by the next frame
                                Err(e) => eprintln!("{:?}", e),
                            }
                        }
                    }
                    _ => (),
                }
            });
        }
        Err(err) => eprintln!("{:?}", err),
    }
}
