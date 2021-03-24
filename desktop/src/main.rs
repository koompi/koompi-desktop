mod window_state;
mod background;
mod desktop_item;
mod constants;
mod desktop_manager;
mod configs;
mod errors;
mod gui;
mod proxy_message;

use gui::{
    Desktop, ContextMenu, DesktopConfigUI, BackgroundConfigUI, ContextMsg,
};
use proxy_message::ProxyMessage;
use window_state::WindowState;
use desktop_manager::DesktopManager;

use std::collections::HashMap;
use iced_wgpu::{wgpu, Settings};
use iced_winit::{
    futures, winit, event, conversion, Debug, Application, Runtime, Proxy, 
};
use iced::executor::{self, Executor};
use futures::{
    channel::mpsc, task
};
use winit::{
    dpi::{PhysicalPosition, PhysicalSize},
    event::{Event, ModifiersState, WindowEvent, MouseButton, KeyboardInput, ElementState, VirtualKeyCode},
    event_loop::{ControlFlow, EventLoop},
    platform::unix::{WindowBuilderExtUnix, XWindowType},
    window::WindowBuilder, 
};
const DESKTOP_CONF: &str = "desktop/desktop.toml";

fn main() {
    match DesktopManager::new(dirs_next::config_dir().unwrap().join(DESKTOP_CONF)) {
        Ok(desktop_manager) => {
            let desktop_conf = desktop_manager.config().to_owned();
            let desktop_items = desktop_manager.desktop_items();

            // Instance
            let mut windows = HashMap::new();
            let event_loop = EventLoop::with_user_event();
            let instance = wgpu::Instance::new(wgpu::BackendBit::PRIMARY);
            let mut runtime = {
                let proxy = Proxy::new(event_loop.create_proxy());
                let executor = executor::Default::new().expect("Failed to create executor");
                Runtime::new(executor, proxy)
            };
            let (mut sender, receiver) = mpsc::unbounded();

            // Other 
            let settings = Settings {
                default_text_size: 13,
                ..Settings::default()
            };
            let (monitor_size, monitor_position) = event_loop.primary_monitor().map(|m| (m.size(), m.position())).unwrap_or((PhysicalSize::new(1920, 1080), PhysicalPosition::new(0, 0)));
            let mut cursor_position = PhysicalPosition::new(-1.0, -1.0);
            let mut modifiers = ModifiersState::default();
            // let mut staging_belt = wgpu::util::StagingBelt::new(10 * 1024);
            let mut debug = Debug::new();

            // Desktop Init Section
            let desktop_state = {
                let desktop_window = WindowBuilder::new()
                    .with_x11_window_type(vec![XWindowType::Desktop])
                    .with_inner_size(monitor_size)
                    .with_visible(false)
                    .build(&event_loop).unwrap();
                desktop_window.set_outer_position(monitor_position);
                let (desktop, init_cmd) = {
                    runtime.enter(|| Desktop::new((monitor_size.height, desktop_conf.to_owned(), desktop_items.to_owned())))
                };
                let subscription = desktop.subscription();
                runtime.spawn(init_cmd.map(Into::into));
                runtime.track(subscription.map(Into::into));
                futures::executor::block_on(WindowState::new(&instance, desktop_window, true, desktop, cursor_position, &mut debug, Some(&settings)))
            };

            // Context Menu Init Section
            let context_menu_size = PhysicalSize::new(300.0, 210.0);
            let context_menu_state = {
                let context_menu_window = WindowBuilder::new()
                    .with_x11_window_type(vec![XWindowType::Desktop, XWindowType::PopupMenu])
                    .with_inner_size(context_menu_size)
                    .with_visible(false)
                    .build(&event_loop).unwrap();
                let (context_menu, _) = ContextMenu::new(event_loop.create_proxy());
                futures::executor::block_on(WindowState::new(&instance, context_menu_window, false, context_menu, cursor_position, &mut debug, Some(&settings)))
            };

            let mut run = Box::pin(
                run_instance::<executor::Default>(
                    desktop_state, context_menu_state, runtime, receiver, context_menu_size, monitor_size,
                )
            );
            let mut context = task::Context::from_waker(task::noop_waker_ref());

            event_loop.run(move |event, event_loop, control_flow| {
                *control_flow = ControlFlow::Wait;

                if let Some(event) = event.to_static() {
                    use futures::Future;

                    match event {
                        Event::UserEvent(ProxyMessage::ContextMenu(msg)) => match msg {
                            ContextMsg::ChangeBG => {
                                // Background Config Init Section
                                let (bg_config, _) = BackgroundConfigUI::new((desktop_conf.background_conf().to_owned(), desktop_manager.wallpaper_items().to_owned()));
                                let bg_config_window = WindowBuilder::new()
                                    // .with_x11_window_type(vec![XWindowType::Utility])
                                    .with_title(bg_config.title())
                                    .with_visible(false)
                                    .build(&event_loop).unwrap();
                                windows.insert(bg_config_window.id(), DynWinState::BgConfig(futures::executor::block_on(WindowState::new(&instance, bg_config_window, true, bg_config, cursor_position, &mut debug, Some(&settings)))));
                            },
                            ContextMsg::DesktopView => {
                                // Desktop Config Init Section
                                let (desktop_config, _) = DesktopConfigUI::new(desktop_conf.desktop_item_conf().to_owned());
                                let desktop_config_window = WindowBuilder::new()
                                    // .with_x11_window_type(vec![XWindowType::Utility])
                                    .with_inner_size(PhysicalSize::new(250, 350))
                                    .with_title(desktop_config.title())
                                    .with_resizable(false)
                                    .with_maximized(false)
                                    .with_visible(false)
                                    .build(&event_loop).unwrap();
                                windows.insert(desktop_config_window.id(), DynWinState::DesktopConfig(futures::executor::block_on(WindowState::new(&instance, desktop_config_window, true, desktop_config, cursor_position, &mut debug, Some(&settings)))));
                            },
                            _ => {}
                        },
                        Event::WindowEvent { ref event, window_id } => {
                            use DynWinState::*;
                            match event {
                                WindowEvent::CloseRequested => {
                                    windows.remove(&window_id);
                                },
                                WindowEvent::CursorMoved { position, .. } => cursor_position = *position,
                                WindowEvent::ModifiersChanged(state) => modifiers = *state,
                                WindowEvent::Resized(new_size) => if let Some(window) = windows.get_mut(&window_id) {
                                    match window {
                                        DesktopConfig(state) => state.resize(*new_size, None),
                                        BgConfig(state) => state.resize(*new_size, None),
                                    }
                                }
                                WindowEvent::ScaleFactorChanged { new_inner_size, scale_factor} => if let Some(window) = windows.get_mut(&window_id) {
                                    match window {
                                        DesktopConfig(state) => state.resize(**new_inner_size, Some(*scale_factor)),
                                        BgConfig(state) => state.resize(**new_inner_size, Some(*scale_factor)),
                                    }
                                },
                                _ => {}
                            }

                            if let Some(state) = windows.get_mut(&window_id) {
                                match state {
                                    DesktopConfig(prog_state) => prog_state.map_event(event, modifiers),
                                    BgConfig(prog_state) => prog_state.map_event(event, modifiers),
                                }
                            }
                        },
                        Event::MainEventsCleared => {
                            windows.iter_mut().for_each(|(_, state)| {
                                match state {
                                    DynWinState::DesktopConfig(prog_state) => {
                                        prog_state.update_frame(cursor_position, &mut debug);
                                        prog_state.window.request_redraw();
                                    },
                                    DynWinState::BgConfig(prog_state) => {
                                        prog_state.update_frame(cursor_position, &mut debug);
                                        prog_state.window.request_redraw();
                                    },
                                }
                            });
                        },
                        Event::RedrawRequested(window_id) => {
                            let is_success = if let Some(state) = windows.get_mut(&window_id) {
                                Some(match state {
                                    DynWinState::DesktopConfig(prog_state) => prog_state.redraw(&debug.overlay()),
                                    DynWinState::BgConfig(prog_state) => prog_state.redraw(&debug.overlay()),
                                })
                            } else {
                                None
                            };
            
                            if let Some(is_success) = is_success {
                                if !is_success {
                                    *control_flow = ControlFlow::Exit;
                                }
                            }
                        },
                        _ => {}
                    }

                    sender.start_send(event.into()).expect("Send event");

                    let poll = run.as_mut().poll(&mut context);

                    *control_flow = match poll {
                        task::Poll::Pending => ControlFlow::Wait,
                        task::Poll::Ready(_) => ControlFlow::Exit,
                    };
                }

            });
        },
        Err(err) => eprintln!("{}", err)
    }
}

async fn run_instance<E>(
    mut desktop_state: WindowState<Desktop>,
    mut context_menu_state: WindowState<ContextMenu>,
    mut runtime: Runtime<E, Proxy<ProxyMessage>, ProxyMessage>,
    mut receiver: mpsc::UnboundedReceiver<winit::event::Event<'_, ProxyMessage>>,
    context_menu_size: PhysicalSize<f64>,
    monitor_size: PhysicalSize<u32>,
) where
    E: Executor + 'static,
{
    use futures::stream::StreamExt;

    // Other
    let mut debug = Debug::new();
    let mut cursor_position = PhysicalPosition::new(-1.0, -1.0);
    let mut modifiers = ModifiersState::default();
    let mut is_context_shown = false;
    let mut events = Vec::new();

    while let Some(event) = receiver.next().await {
        match event {
            Event::UserEvent(ProxyMessage::Desktop(msg) ) => desktop_state.map_message(msg),
            Event::WindowEvent { ref event, window_id } => {
                match event {
                    WindowEvent::CloseRequested => {
                        if desktop_state.window.id() == window_id {
                            break;
                        }
                    },
                    WindowEvent::KeyboardInput { input, .. } => match input {
                        KeyboardInput {
                            state: ElementState::Pressed,
                            virtual_keycode: Some(VirtualKeyCode::Escape),
                            ..
                        } => is_context_shown = false,
                        _ => {}
                    },
                    WindowEvent::CursorMoved { position, .. } => cursor_position = *position,
                    WindowEvent::ModifiersChanged(state) => modifiers = *state,
                    WindowEvent::Resized(new_size) => if desktop_state.window.id() == window_id {
                        desktop_state.resize(*new_size, None);
                    },
                    WindowEvent::ScaleFactorChanged { new_inner_size, scale_factor} => if desktop_state.window.id() == window_id {
                        desktop_state.resize(**new_inner_size, Some(*scale_factor));
                    } else if context_menu_state.window.id() == window_id {
                        context_menu_state.resize(**new_inner_size, Some(*scale_factor));
                    },
                    WindowEvent::MouseInput { state: ElementState::Pressed, button, .. } => {
                        match button {
                            MouseButton::Right => {
                                context_menu_state.window.set_outer_position(get_prefered_position(cursor_position, context_menu_size, monitor_size));
                                is_context_shown = !is_context_shown;
                            },
                            _ => if desktop_state.window.id() == window_id {
                                is_context_shown = false;
                            },
                        }
                    }
                    _ => {}
                }

                if desktop_state.window.id() == window_id {
                    desktop_state.map_event(event, modifiers);
                    if let Some(event) = conversion::window_event(&event, desktop_state.viewport.scale_factor(), modifiers) {
                        events.push(event);
                    }
                } else if context_menu_state.window.id() == window_id {
                    context_menu_state.map_event(event, modifiers);
                    if let Some(event) = conversion::window_event(&event, context_menu_state.viewport.scale_factor(), modifiers) {
                        events.push(event);
                    }
                }
            },
            Event::MainEventsCleared => {
                for event in events.drain(..) {
                    runtime.broadcast((event, event::Status::Captured));
                } 

                if let Some(cmd) = desktop_state.update_frame(cursor_position, &mut debug).map(|cmd| cmd.map(Into::into)) {
                    runtime.spawn(cmd);
                }
                runtime.track(desktop_state.subscription().map(Into::into));
                desktop_state.window.request_redraw();

                if is_context_shown {
                    context_menu_state.update_frame(cursor_position, &mut debug);
                    context_menu_state.window.request_redraw();
                }
            },
            Event::RedrawRequested(window_id) => {
                context_menu_state.window.set_visible(is_context_shown);

                let is_success = if context_menu_state.window.id() == window_id {
                    context_menu_state.redraw(&debug.overlay())
                } else {
                    desktop_state.redraw(&debug.overlay())
                };

                if !is_success {
                    break;
                }
            }
            _ => (),
        }
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

enum DynWinState {
    DesktopConfig(WindowState<DesktopConfigUI>),
    BgConfig(WindowState<BackgroundConfigUI>),
}