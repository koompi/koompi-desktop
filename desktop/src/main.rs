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

use std::collections::HashMap;
use iced_wgpu::{wgpu, Settings};
use iced_winit::{futures, winit, Debug, Clipboard, Application};
use winit::{
    dpi::{PhysicalPosition, PhysicalSize},
    event::{Event, ModifiersState, WindowEvent, MouseButton, KeyboardInput, ElementState, VirtualKeyCode},
    event_loop::{ControlFlow, EventLoop},
    platform::unix::{WindowBuilderExtUnix, XWindowType},
    window::WindowBuilder, 
};
const DESKTOP_CONF: &str = "desktop/desktop.toml";

enum DynWinState {
    Context(WindowState<ContextMenu>),
    DesktopConfig(WindowState<DesktopConfigUI>),
    BgConfig(WindowState<BackgroundConfigUI>),
}

fn main() {
    match DesktopManager::new(dirs_next::config_dir().unwrap().join(DESKTOP_CONF)) {
        Ok(desktop_manager) => {
            let desktop_conf = desktop_manager.config().to_owned();
            let desktop_items = desktop_manager.desktop_items();

            // Instance
            let event_loop = EventLoop::new();
            let instance = wgpu::Instance::new(wgpu::BackendBit::PRIMARY);
            let mut windows = HashMap::new();

            // Other
            let (monitor_size, monitor_position) = event_loop.primary_monitor().map(|m| (m.size(), m.position())).unwrap_or((PhysicalSize::new(1920, 1080), PhysicalPosition::new(0, 0)));
            let mut cursor_position = PhysicalPosition::new(-1.0, -1.0);
            let mut modifiers = ModifiersState::default();
            let mut debug = Debug::new();
            let mut staging_belt = wgpu::util::StagingBelt::new(10 * 1024);
            let settings = Settings {
                default_text_size: 13,
                ..Settings::default()
            };

            // Desktop Init Section
            let desktop_window = WindowBuilder::new()
                .with_x11_window_type(vec![XWindowType::Desktop])
                .with_inner_size(monitor_size)
                .with_visible(false)
                .build(&event_loop).unwrap();
            desktop_window.set_outer_position(monitor_position);
            let mut clipboard = Clipboard::connect(&desktop_window);
            let (desktop, _) = Desktop::new((monitor_size.height, desktop_conf.to_owned(), desktop_items.to_owned()));
            let mut desktop_state = futures::executor::block_on(WindowState::new(&instance, desktop_window, desktop, cursor_position, &mut debug, Some(&settings)));

            event_loop.run(move |event, event_loop, control_flow| {
                *control_flow = ControlFlow::Wait;

                match event {
                    Event::WindowEvent { ref event, window_id } => {
                        match event {
                            WindowEvent::CloseRequested => {
                                windows.remove(&window_id);
                                if desktop_state.window.id() == window_id {
                                    *control_flow = ControlFlow::Exit
                                }
                            },
                            WindowEvent::KeyboardInput { input, .. } => match input {
                                KeyboardInput {
                                    state: ElementState::Pressed,
                                    virtual_keycode: Some(VirtualKeyCode::Escape),
                                    ..
                                } => {
                                    // if desktop_state.window.id() == window_id {
                                    //     windows.
                                    // }
                                    windows.remove(&window_id);
                                },
                                _ => {}
                            },
                            WindowEvent::CursorMoved { position, .. } => cursor_position = *position,
                            WindowEvent::ModifiersChanged(modi) => modifiers = *modi,
                            WindowEvent::Resized(new_size) => if desktop_state.window.id() == window_id {
                                desktop_state.resize(*new_size, None);
                            } else if let Some(window) = windows.get_mut(&window_id) {
                                use DynWinState::*;
                                match window {
                                    Context(state) => state.resize(*new_size, None),
                                    DesktopConfig(state) => state.resize(*new_size, None),
                                    BgConfig(state) => state.resize(*new_size, None),
                                }
                            }
                            WindowEvent::ScaleFactorChanged { new_inner_size, scale_factor} => if desktop_state.window.id() == window_id {
                                desktop_state.resize(**new_inner_size, Some(*scale_factor));
                            } else if let Some(window) = windows.get_mut(&window_id) {
                                use DynWinState::*;
                                match window {
                                    Context(state) => state.resize(**new_inner_size, Some(*scale_factor)),
                                    DesktopConfig(state) => state.resize(**new_inner_size, Some(*scale_factor)),
                                    BgConfig(state) => state.resize(**new_inner_size, Some(*scale_factor)),
                                }
                            },
                            WindowEvent::MouseInput { state: ElementState::Pressed, button, .. } => match button {
                                MouseButton::Right => if desktop_state.window.id() == window_id {
                                    if modifiers.is_empty() {
                                        // Context Menu Init Section
                                        let context_menu_size = PhysicalSize::new(300.0, 210.0);
                                        let context_menu_window = WindowBuilder::new()
                                            .with_x11_window_type(vec![XWindowType::Desktop, XWindowType::PopupMenu])
                                            .with_inner_size(context_menu_size)
                                            .with_visible(false)
                                            .build(&event_loop).unwrap();
                                        context_menu_window.set_outer_position(get_prefered_position(cursor_position, context_menu_size, monitor_size));
                                        let (context_menu, _) = ContextMenu::new(());
                                        windows.insert(context_menu_window.id(), DynWinState::Context(futures::executor::block_on(WindowState::new(&instance, context_menu_window, context_menu, cursor_position, &mut debug, Some(&settings)))));
                                    } else if modifiers.ctrl() && modifiers.shift() {
                                        // Background Config Init Section
                                        let (bg_config, _) = BackgroundConfigUI::new((desktop_conf.background_conf().to_owned(), desktop_manager.wallpaper_items().to_owned()));
                                        let bg_config_window = WindowBuilder::new()
                                            // .with_x11_window_type(vec![XWindowType::Desktop])
                                            .with_title(bg_config.title())
                                            .with_visible(false)
                                            .build(&event_loop).unwrap();
                                        windows.insert(bg_config_window.id(), DynWinState::BgConfig(futures::executor::block_on(WindowState::new(&instance, bg_config_window, bg_config, cursor_position, &mut debug, Some(&settings)))));
                                    } else if modifiers.ctrl() {
                                        // Desktop Config Init Section
                                        let (desktop_config, _) = DesktopConfigUI::new(desktop_conf.desktop_item_conf().to_owned());
                                        let desktop_config_window = WindowBuilder::new()
                                            // .with_x11_window_type(vec![XWindowType::Desktop])
                                            .with_inner_size(PhysicalSize::new(250, 350))
                                            .with_title(desktop_config.title())
                                            .with_resizable(false)
                                            .with_maximized(false)
                                            .with_visible(false)
                                            .build(&event_loop).unwrap();
                                        windows.insert(desktop_config_window.id(), DynWinState::DesktopConfig(futures::executor::block_on(WindowState::new(&instance, desktop_config_window, desktop_config, cursor_position, &mut debug, Some(&settings)))));
                                    }
                                },
                                _ => {}
                            }
                            _ => {}
                        }

                        if desktop_state.window.id() == window_id {
                            desktop_state.map_event(event, modifiers);
                        } else if let Some(state) = windows.get_mut(&window_id) {
                            match state {
                                DynWinState::Context(prog_state) => prog_state.map_event(event, modifiers),
                                DynWinState::DesktopConfig(prog_state) => prog_state.map_event(event, modifiers),
                                DynWinState::BgConfig(prog_state) => prog_state.map_event(event, modifiers),
                            }
                        }
                    },
                    Event::MainEventsCleared => { 
                        desktop_state.update_frame(cursor_position, &mut clipboard, &mut debug);
                        windows.iter_mut().for_each(|(_, state)| {
                            match state {
                                DynWinState::Context(prog_state) => prog_state.update_frame(cursor_position, &mut clipboard, &mut debug),
                                DynWinState::DesktopConfig(prog_state) => prog_state.update_frame(cursor_position, &mut clipboard, &mut debug),
                                DynWinState::BgConfig(prog_state) => prog_state.update_frame(cursor_position, &mut clipboard, &mut debug),
                            }
                        });
                    },
                    Event::RedrawRequested(window_id) => {
                        let is_success = if let Some(state) = windows.get_mut(&window_id) {
                            match state {
                                DynWinState::Context(state) => state.redraw(&mut staging_belt, &debug.overlay()),
                                DynWinState::DesktopConfig(state) => state.redraw(&mut staging_belt, &debug.overlay()),
                                DynWinState::BgConfig(state) => state.redraw(&mut staging_belt, &debug.overlay()),
                            }
                        } else {
                            desktop_state.redraw(&mut staging_belt, &debug.overlay())
                        };

                        if !is_success {
                            *control_flow = ControlFlow::Exit;
                        }
                    }
                    _ => (),
                }
            });
        },
        Err(err) => eprintln!("{:?}", err)
    }
}

fn get_prefered_position(cursor_position: PhysicalPosition<f64>, window_size: PhysicalSize<f64>, monitor_size: PhysicalSize<u32>) -> PhysicalPosition<f64> {
    let prefered_x = if window_size.width + cursor_position.x > monitor_size.width as f64 {
        cursor_position.x - window_size.width
    } else {
        cursor_position.x
    };
    let prefered_y = if window_size.height + cursor_position.y > monitor_size.height as f64 {
        cursor_position.y - window_size.height
    } else {
        cursor_position.y
    };

    PhysicalPosition::new(prefered_x, prefered_y)
}