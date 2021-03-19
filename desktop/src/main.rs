mod window_state;
mod background;
mod desktop_item;
mod constants;
mod desktop_manager;
mod configs;
mod errors;
mod gui;

use gui::{Desktop, ContextMenu, DesktopConfigUI, BackgroundConfigUI};
use window_state::WindowState;
use desktop_manager::DesktopManager;

use iced_wgpu::{wgpu, Settings};
use iced_winit::{conversion, futures, program, winit, mouse::{self, click}, Debug, Clipboard, Application};
use futures::task::SpawnExt;
use winit::{
    dpi::{PhysicalPosition, PhysicalSize},
    event::{Event, ModifiersState, WindowEvent, MouseButton, KeyboardInput, ElementState, VirtualKeyCode},
    event_loop::{ControlFlow, EventLoop},
    platform::unix::{WindowBuilderExtUnix, XWindowType},
    window::WindowBuilder, 
};
const DESKTOP_CONF: &str = "desktop/desktop.toml";

enum ProgramState {
    ContextMenu(program::State<ContextMenu>),
    DesktopConfig(program::State<DesktopConfigUI>),
    BackgroundConfig(program::State<BackgroundConfigUI>),
}

fn main() {
    match DesktopManager::new(dirs_next::config_dir().unwrap().join(DESKTOP_CONF)) {
        Ok(desktop_manager) => {
            let event_loop = EventLoop::new();
            let instance = wgpu::Instance::new(wgpu::BackendBit::PRIMARY);
            let mut cursor_position = PhysicalPosition::new(-1.0, -1.0);
            let mut modifiers = ModifiersState::default();
            let mut debug = Debug::new();
            let mut staging_belt = wgpu::util::StagingBelt::new(10 * 1024);
            // let mut local_pool = futures::executor::LocalPool::new();
            let mut dyn_window = None;
            let mut is_unfocus = false;
            let mut last_click = None;
            let settings = Settings {
                default_text_size: 13,
                ..Settings::default()
            };
        
            let (size, position) = event_loop.primary_monitor().map(|m| (m.size(), m.position())).unwrap_or((PhysicalSize::new(1920, 1080), PhysicalPosition::new(0, 0)));
            let desktop_window = WindowBuilder::new()
                .with_inner_size(size)
                .with_x11_window_type(vec![XWindowType::Desktop])
                .build(&event_loop)
                .unwrap();
            desktop_window.set_outer_position(position);
            let mut clipboard = Clipboard::connect(&desktop_window);
            let mut desktop_window_state = futures::executor::block_on(WindowState::new(&instance, desktop_window, Some(&settings)));

            let desktop_conf = desktop_manager.config().to_owned();
            let desktop_items = desktop_manager.desktop_items();
            let (desktop, _) = Desktop::new((desktop_window_state.window.inner_size().height, desktop_conf.to_owned(), desktop_items.to_owned()));
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
                    Event::WindowEvent { ref event, window_id } => {
                        match event {
                            WindowEvent::CloseRequested => if window_id == desktop_window_state.window.id() {
                                *control_flow = ControlFlow::Exit
                            } else {
                                dyn_window = None;
                            },
                            WindowEvent::KeyboardInput { input, .. } => match input {
                                KeyboardInput {
                                    state: ElementState::Pressed,
                                    virtual_keycode: Some(VirtualKeyCode::Escape),
                                    ..
                                } => if dyn_window.is_some() {
                                    dyn_window = None;
                                },
                                _ => {}
                            },
                            WindowEvent::CursorMoved { position, .. } => cursor_position = *position,
                            WindowEvent::ModifiersChanged(modi) => modifiers = *modi,
                            WindowEvent::Resized(new_size) => {
                                desktop_window_state.resize(*new_size, None);
                            },
                            WindowEvent::ScaleFactorChanged { new_inner_size, scale_factor} => {
                                desktop_window_state.resize(**new_inner_size, Some(*scale_factor));
                            }
                            WindowEvent::MouseInput {
                                state: ElementState::Pressed,
                                button,
                                ..
                            } => match button {
                                MouseButton::Right => if desktop_window_state.window.id() == window_id {
                                    is_unfocus = false;
                                    let context_menu_size = PhysicalSize::new(300.0, 210.0);
                                    let context_menu_window = WindowBuilder::new()
                                        .with_inner_size(context_menu_size)
                                        .with_x11_window_type(vec![XWindowType::Desktop, XWindowType::PopupMenu])
                                        .build(&event_loop).unwrap();
                                    if let Some(monitor) = context_menu_window.primary_monitor() {
                                        let prefered_x = if context_menu_size.width + cursor_position.x > monitor.size().width as f64 {
                                            cursor_position.x - context_menu_size.width
                                        } else {
                                            cursor_position.x
                                        };
                                        let prefered_y = if context_menu_size.height + cursor_position.y > monitor.size().height as f64 {
                                            cursor_position.y - context_menu_size.height
                                        } else {
                                            cursor_position.y
                                        };

                                        context_menu_window.set_outer_position(PhysicalPosition::new(prefered_x, prefered_y));
                                    }
                                    let (context_menu_gui, _) = ContextMenu::new(());

                                    let mut context_menu_window_state = futures::executor::block_on(WindowState::new(&instance, context_menu_window, Some(&settings)));
                                    let context_menu_program_state = program::State::new(
                                        context_menu_gui,
                                        context_menu_window_state.viewport.logical_size(),
                                        conversion::cursor_position(cursor_position, context_menu_window_state.viewport.scale_factor()),
                                        &mut context_menu_window_state.renderer,
                                        &mut debug,
                                    );
                                    dyn_window = Some((context_menu_window_state, ProgramState::ContextMenu(context_menu_program_state)));
                                },
                                MouseButton::Left => {
                                    let click = mouse::Click::new(
                                        conversion::cursor_position(cursor_position, desktop_window_state.viewport.scale_factor()),
                                        last_click,
                                    );
                
                                    match click.kind() {
                                        // click::Kind::Double => {
                                        //     println!("handled double clicked");
                                        //     let (desktop_config_ui, _) = DesktopConfigUI::new(desktop_conf.desktop_item_conf().to_owned());
                                        //     let desktop_config_window = WindowBuilder::new()
                                        //         .with_title(desktop_config_ui.title())
                                        //         .with_resizable(false)
                                        //         .build(&event_loop).unwrap();

                                        //     let mut desktop_config_window_state = futures::executor::block_on(WindowState::new(&instance, desktop_config_window, Some(&settings)));
                                        //     let desktop_config_program_state = program::State::new(
                                        //         desktop_config_ui,
                                        //         desktop_config_window_state.viewport.logical_size(),
                                        //         conversion::cursor_position(cursor_position, desktop_config_window_state.viewport.scale_factor()),
                                        //         &mut desktop_config_window_state.renderer,
                                        //         &mut debug,
                                        //     );
                                        //     dyn_window = Some((desktop_config_window_state, ProgramState::DesktopConfig(desktop_config_program_state)));
                                        // }
                                        click::Kind::Triple => {
                                            println!("handled triple clicked");
                                            let bg_config_window = WindowBuilder::new().build(&event_loop).unwrap();
                                            let (bg_config_ui, _) = BackgroundConfigUI::new((desktop_conf.background_conf().to_owned(), desktop_manager.wallpaper_items().to_owned()));

                                            let mut bg_config_window_state = futures::executor::block_on(WindowState::new(&instance, bg_config_window, Some(&settings)));
                                            let bg_config_program_state = program::State::new(
                                                bg_config_ui,
                                                bg_config_window_state.viewport.logical_size(),
                                                conversion::cursor_position(cursor_position, bg_config_window_state.viewport.scale_factor()),
                                                &mut bg_config_window_state.renderer,
                                                &mut debug,
                                            );
                                            dyn_window = Some((bg_config_window_state, ProgramState::BackgroundConfig(bg_config_program_state)));
                                        }
                                        _ => {}
                                    }
                
                                    last_click = Some(click);
                                }
                                _ => {}
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

                        if let Some((win_state, prog_state)) = &mut dyn_window {
                            if let Some(event) = conversion::window_event(
                                &event,
                                win_state.viewport.scale_factor(),
                                modifiers,
                            ) {
                                match prog_state {
                                    ProgramState::ContextMenu(prog_state) => prog_state.queue_event(event),
                                    ProgramState::DesktopConfig(prog_state) => prog_state.queue_event(event),
                                    ProgramState::BackgroundConfig(prog_state) => prog_state.queue_event(event),
                                }
                            }
                        }

                        // if is_unfocus {
                        //     context_menu = None;
                        // }
                    },
                    Event::MainEventsCleared => { 
                        if let Some((win_state, prog_state)) = &mut dyn_window {
                            match prog_state {
                                ProgramState::ContextMenu(prog_state) => if !prog_state.is_queue_empty() {
                                    // We update iced
                                    let _ = prog_state.update(
                                        win_state.viewport.logical_size(),
                                        conversion::cursor_position(cursor_position, win_state.viewport.scale_factor()),
                                        &mut win_state.renderer,
                                        &mut clipboard,
                                        &mut debug,
                                    );
                                },
                                ProgramState::DesktopConfig(prog_state) => if !prog_state.is_queue_empty() {
                                    // We update iced
                                    let _ = prog_state.update(
                                        win_state.viewport.logical_size(),
                                        conversion::cursor_position(cursor_position, win_state.viewport.scale_factor()),
                                        &mut win_state.renderer,
                                        &mut clipboard,
                                        &mut debug,
                                    );
                                },
                                ProgramState::BackgroundConfig(prog_state) => if !prog_state.is_queue_empty() {
                                    // We update iced
                                    let _ = prog_state.update(
                                        win_state.viewport.logical_size(),
                                        conversion::cursor_position(cursor_position, win_state.viewport.scale_factor()),
                                        &mut win_state.renderer,
                                        &mut clipboard,
                                        &mut debug,
                                    );
                                },  
                            }
    
                            win_state.window.request_redraw();
                        } else {
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
                        }
                    },
                    Event::RedrawRequested(_) => {
                        if let Some((win_state, prog_state)) = &mut dyn_window {
                            win_state.update();
                            let (bg_color, primitive) = match prog_state {
                                ProgramState::ContextMenu(state) => (state.program().background_color(), state.primitive()),
                                ProgramState::DesktopConfig(state) => (state.program().background_color(), state.primitive()),
                                ProgramState::BackgroundConfig(state) => (state.program().background_color(), state.primitive()),
                            };
                            match win_state.render(primitive, &mut staging_belt, &debug.overlay(), bg_color) {
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
                        } else {
                            desktop_window_state.update();
                            let bg_color = desktop_program_state.program().background_color();
                            let primitive = desktop_program_state.primitive();
                            match desktop_window_state.render(primitive, &mut staging_belt, &debug.overlay(), bg_color) {
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
                        }


                        // And recall staging buffers
                        // local_pool.spawner()
                        //     .spawn(staging_belt.recall())
                        //     .expect("Recall staging buffers");
                        // local_pool.run_until_stalled();
                    }
                    _ => (),
                }
            });
        },
        Err(err) => eprintln!("{:?}", err)
    }
}
