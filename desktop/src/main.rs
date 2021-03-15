mod window_state;
mod background;
mod desktop_item;
mod constants;
mod desktop_manager;
mod styles;
mod configs;
mod errors;
mod gui;

use gui::{Desktop, ContextMenu};
use window_state::WindowState;

use std::collections::HashMap;
use iced_wgpu::{wgpu, Settings};
use iced_winit::{conversion, futures, program, winit, Debug, Clipboard};
use futures::task::SpawnExt;
use winit::{
    dpi::{PhysicalPosition, PhysicalSize},
    event::{Event, ModifiersState, WindowEvent, MouseButton, KeyboardInput, ElementState, VirtualKeyCode},
    event_loop::{ControlFlow, EventLoop},
    platform::unix::{WindowBuilderExtUnix, XWindowType},
    window::WindowBuilder,
};

fn main() {
    let event_loop = EventLoop::new();
    let mut window_states = HashMap::new();
    let mut cursor_position = PhysicalPosition::new(-1.0, -1.0);
    let mut modifiers = ModifiersState::default();
    let mut debug = Debug::new();
    let mut staging_belt = wgpu::util::StagingBelt::new(5 * 1024);
    let mut local_pool = futures::executor::LocalPool::new();

    let desktop_window = WindowBuilder::new()
        .with_x11_window_type(vec![XWindowType::Desktop])
        .build(&event_loop)
        .unwrap();
    if let Some(monitor) = desktop_window.primary_monitor() {
        desktop_window.set_inner_size(monitor.size());
        desktop_window.set_outer_position(monitor.position());
    }
    let mut clipboard = Clipboard::connect(&desktop_window);
    let settings = Settings {
        default_text_size: 13,
        ..Settings::default()
    };
    let mut desktop_window_state = futures::executor::block_on(WindowState::new(desktop_window, Some(&settings)));

    match Desktop::new(desktop_window_state.window.inner_size().height) {
        Ok(desktop) => {
            let mut desktop_program_state = program::State::new(
                desktop,
                desktop_window_state.viewport.logical_size(),
                conversion::cursor_position(cursor_position, desktop_window_state.viewport.scale_factor()),
                &mut desktop_window_state.renderer,
                &mut debug,
            );

            event_loop.run(move |event, event_loop, control_flow| {
                *control_flow = ControlFlow::Wait;

                match event {
                    Event::WindowEvent { event, window_id } => if !desktop_window_state.input(&event) {
                        match event {
                            WindowEvent::CloseRequested => *control_flow = ControlFlow::Exit,
                            WindowEvent::KeyboardInput { input, .. } => match input {
                                KeyboardInput {
                                    state: ElementState::Pressed,
                                    virtual_keycode: Some(VirtualKeyCode::Escape),
                                    ..
                                } => if !window_states.is_empty() {
                                    window_states.remove(&window_id);
                                },
                                _ => {}
                            },
                            WindowEvent::CursorMoved { position, .. } => cursor_position = position,
                            WindowEvent::ModifiersChanged(modi) => modifiers = modi,
                            WindowEvent::Resized(new_size) => desktop_window_state.resize(new_size, None),
                            // WindowEvent::ScaleFactorChanged { new_inner_size, scale_factor } => {
                            //     desktop_window_state.resize(*new_inner_size, Some(scale_factor));
                            // }
                            WindowEvent::MouseInput {
                                button: MouseButton::Right,
                                ..
                            } => {
                                let context_menu_window = WindowBuilder::new()
                                    .with_inner_size(PhysicalSize::new(300, 500))
                                    .with_decorations(false)
                                    .with_resizable(false)
                                    .with_x11_window_type(vec![XWindowType::PopupMenu, XWindowType::Dock])
                                    .build(&event_loop).unwrap();
                                context_menu_window.set_outer_position(cursor_position);
                                let context_menu = ContextMenu::new();

                                let mut context_menu_window_state = futures::executor::block_on(WindowState::new(context_menu_window, Some(&settings)));
                                let context_menu_program_state = program::State::new(
                                    context_menu,
                                    context_menu_window_state.viewport.logical_size(),
                                    conversion::cursor_position(cursor_position, context_menu_window_state.viewport.scale_factor()),
                                    &mut context_menu_window_state.renderer,
                                    &mut debug,
                                );

                                window_states.insert(context_menu_window_state.window.id(), (context_menu_window_state, context_menu_program_state));
                            }
                            _ => {}
                        }

                        if let Some(event) = conversion::window_event(
                            &event,
                            desktop_window_state.viewport.scale_factor(),
                            modifiers
                        ) {
                            desktop_program_state.queue_event(event);
                        }

                        if !window_states.is_empty() {
                            if let Some((window_state, program_state)) = window_states.get_mut(&window_id) {
                                if let Some(event) = conversion::window_event(
                                    &event,
                                    window_state.viewport.scale_factor(),
                                    modifiers,
                                ) {
                                    program_state.queue_event(event);
                                }
                            }
                        }
                    },
                    Event::MainEventsCleared => {
                        if !desktop_program_state.is_queue_empty() {
                            // We update iced
                            let _ = desktop_program_state.update(
                                desktop_window_state.viewport.logical_size(),
                                conversion::cursor_position(cursor_position, desktop_window_state.viewport.scale_factor()),
                                &mut desktop_window_state.renderer,
                                &mut clipboard,
                                &mut debug,
                            );

                            desktop_window_state.window.request_redraw();
                        }

                        if !window_states.is_empty() {
                            window_states.iter_mut().for_each(|(_, (win_state, prog_state))| {
                                if !prog_state.is_queue_empty() {
                                    // We update iced
                                    let _ = prog_state.update(
                                        win_state.viewport.logical_size(),
                                        conversion::cursor_position(cursor_position, win_state.viewport.scale_factor()),
                                        &mut win_state.renderer,
                                        &mut clipboard,
                                        &mut debug,
                                    );

                                    win_state.window.request_redraw();
                                }
                            });
                        }
                    },
                    Event::RedrawRequested(window_id) => {
                        println!("redrawn: {:?}", window_id);

                        desktop_window_state.update();
                        match desktop_window_state.render(desktop_program_state.primitive(), &mut staging_belt, &debug) {
                            Ok(()) => {},
                            Err(wgpu::SwapChainError::Lost) => {
                                let size = desktop_window_state.viewport.physical_size();
                                desktop_window_state.resize(PhysicalSize::new(size.width, size.height), None);
                            },
                            // The system is out of memory, we should probably quit
                            Err(wgpu::SwapChainError::OutOfMemory) => *control_flow = ControlFlow::Exit,
                            // All other errors (Outdated, Timeout) should be resolved by the next frame
                            Err(e) => eprintln!("{:?}", e),
                        }

                        if !window_states.is_empty() {
                            if let Some((win_state, prog_state)) = window_states.get_mut(&window_id) {
                                win_state.update();
                                match win_state.render(prog_state.primitive(), &mut staging_belt, &debug) {
                                    Ok(()) => {},
                                    Err(wgpu::SwapChainError::Lost) => {
                                        let size = win_state.viewport.physical_size();
                                        win_state.resize(PhysicalSize::new(size.width, size.height), None);
                                    },
                                    // The system is out of memory, we should probably quit
                                    Err(wgpu::SwapChainError::OutOfMemory) => *control_flow = ControlFlow::Exit,
                                    // All other errors (Outdated, Timeout) should be resolved by the next frame
                                    Err(e) => eprintln!("{:?}", e),
                                }
                            }
                        }
                        
                        // And recall staging buffers
                        local_pool
                            .spawner()
                            .spawn(staging_belt.recall())
                            .expect("Recall staging buffers");
                        local_pool.run_until_stalled();
                    }
                    _ => (),
                }
            });
        },
        Err(err) => eprintln!("{:?}", err)
    }
}
