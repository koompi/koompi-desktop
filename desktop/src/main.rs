mod window_state;
mod background;
mod desktop_item;
mod constants;
mod desktop_manager;
mod configs;
mod errors;
mod gui;
mod proxy_message;

use configs::PersistentData;
use proxy_message::ProxyMessage;
use window_state::WindowState;
use desktop_manager::DesktopManager;
use gui::{
    Desktop, ContextMenu, DesktopConfigUI, BackgroundConfigUI, ContextMsg, 
};

use std::{cell::RefCell, rc::Rc};
use std::collections::HashMap;
use iced::executor;
use iced_wgpu::{wgpu, Settings};
use iced_winit::{
    futures, winit, Debug, Application, Runtime, Proxy, Executor,
};
use futures::{
    channel::mpsc, task
};
use winit::{
    dpi::{PhysicalPosition, PhysicalSize},
    event::{Event, WindowEvent, MouseButton, KeyboardInput, ElementState, VirtualKeyCode},
    event_loop::{ControlFlow, EventLoop},
    platform::unix::{WindowBuilderExtUnix, XWindowType},
    window::WindowBuilder, 
};
use tauri_dialog::{DialogBuilder, DialogButtons, DialogStyle, DialogSelection};

fn main() {
    std::env::set_var("WINIT_X11_SCALE_FACTOR", "1.25");
    match DesktopManager::new() {
        Ok(desktop_manager) => {
            let mut old_desktop_conf = desktop_manager.config().to_owned();
            let desktop_conf = Rc::new(RefCell::new(desktop_manager.config().to_owned()));
            let desktop_items = desktop_manager.desktop_items().to_owned();
            let wallpaper_items = desktop_manager.wallpaper_items().to_owned();

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
            let mut debug = Debug::new();

            // Desktop Init Section
            let desktop_state = {
                let (desktop, init_cmd) = {
                    runtime.enter(|| Desktop::new((monitor_size.height, Rc::clone(&desktop_conf), desktop_items.to_owned())))
                };
                let desktop_window = WindowBuilder::new()
                    .with_x11_window_type(vec![XWindowType::Desktop])
                    .with_position(monitor_position)
                    .with_title(desktop.title())
                    .with_inner_size(monitor_size)
                    .with_visible(false)
                    .build(&event_loop).unwrap();

                let subscription = desktop.subscription();
                runtime.spawn(init_cmd.map(Into::into));
                runtime.track(subscription.map(Into::into));
                futures::executor::block_on(WindowState::new(&instance, desktop_window, desktop, true, Some(&settings)))
            };

            // Context Menu Init Section
            let context_menu_size = PhysicalSize::new(300.0, 210.0);
            let (context_menu, _) = ContextMenu::new(event_loop.create_proxy());
            let context_menu_state = {
                let context_menu_window = WindowBuilder::new()
                    .with_x11_window_type(vec![XWindowType::Desktop, XWindowType::PopupMenu])
                    .with_title(context_menu.title())
                    .with_inner_size(context_menu_size)
                    .with_decorations(false)
                    .with_resizable(false)
                    .with_maximized(false)
                    .with_visible(false)
                    .build(&event_loop).unwrap();
                futures::executor::block_on(WindowState::new(&instance, context_menu_window, context_menu, false, Some(&settings)))
            };

            let mut run_instance = Box::pin(
                run_instance::<executor::Default>(
                    desktop_state, context_menu_state, runtime, receiver, context_menu_size, monitor_size,
                )
            );
            let mut context = task::Context::from_waker(task::noop_waker_ref());

            event_loop.run(move |event, event_loop, control_flow| {
                *control_flow = ControlFlow::Wait;

                if let Some(event) = event.to_static() {
                    match event.clone() {
                        Event::UserEvent(ProxyMessage::ContextMenu(msg)) => match msg {
                            ContextMsg::ChangeBG => {
                                // Background Config Init Section
                                let (bg_config, _) = BackgroundConfigUI::new((Rc::clone(&desktop_conf), wallpaper_items.to_owned()));
                                let bg_config_window = WindowBuilder::new()
                                    .with_x11_window_type(vec![XWindowType::Desktop, XWindowType::Utility])
                                    .with_title(bg_config.title())
                                    .with_visible(false)
                                    .build(&event_loop).unwrap();
                                windows.insert(bg_config_window.id(), DynWinState::BgConfig(futures::executor::block_on(WindowState::new(&instance, bg_config_window, bg_config, true, Some(&settings)))));
                            },
                            ContextMsg::DesktopView => {
                                // Desktop Config Init Section
                                let (desktop_config, _) = DesktopConfigUI::new(Rc::clone(&desktop_conf));
                                let desktop_config_window = WindowBuilder::new()
                                    .with_x11_window_type(vec![XWindowType::Desktop, XWindowType::Utility])
                                    .with_inner_size(PhysicalSize::new(250, 350))
                                    .with_title(desktop_config.title())
                                    .with_resizable(false)
                                    .with_maximized(false)
                                    .with_visible(false)
                                    .build(&event_loop).unwrap();
                                windows.insert(desktop_config_window.id(), DynWinState::DesktopConfig(futures::executor::block_on(WindowState::new(&instance, desktop_config_window, desktop_config, true, Some(&settings)))));
                            },
                            _ => {}
                        },
                        Event::WindowEvent { ref event, window_id } => {
                            use DynWinState::*;

                            if let WindowEvent::CursorMoved { position, .. } = event {
                                cursor_position = *position;
                            } 

                            let mut handle_exit = |has_changed: bool| -> bool {
                                let mut is_close = true;

                                if has_changed {
                                    match DialogBuilder::new().title("Configuration")
                                        .message("Do you want to save the configuration?")
                                        .buttons(DialogButtons::YesNo)
                                        .style(DialogStyle::Question)
                                        .build().show() {
                                        DialogSelection::Yes => {
                                            let desktop_conf = desktop_conf.borrow();
                                            let _ = desktop_conf.save();
                                            old_desktop_conf = desktop_conf.to_owned();
                                        },
                                        DialogSelection::No => {
                                            let mut desktop_conf = desktop_conf.borrow_mut();
                                            *desktop_conf = old_desktop_conf.to_owned();
                                        },
                                        _ => is_close = false
                                    }
                                } else {
                                    let desktop_conf = desktop_conf.borrow();
                                    old_desktop_conf = desktop_conf.to_owned();
                                }

                                is_close
                            };

                            if let Some(window) = windows.get_mut(&window_id) {
                                match window {
                                    DesktopConfig(state) => {
                                        if state.window_event_request_exit(&event, &mut debug) {
                                            if handle_exit(state.has_changed()) {
                                                windows.remove(&window_id);
                                            }
                                        }
                                    },
                                    BgConfig(state) => {
                                        if state.window_event_request_exit(&event, &mut debug) {
                                            if handle_exit(state.has_changed()) {
                                                windows.remove(&window_id);
                                            }
                                        } 
                                    },
                                }
                            }
                        },
                        Event::MainEventsCleared => {
                            windows.iter_mut().for_each(|(_, state)| {
                                match state {
                                    DynWinState::DesktopConfig(state) => {
                                        state.update_frame::<executor::Default>(None, cursor_position, &mut debug);
                                        state.window.request_redraw();
                                    },
                                    DynWinState::BgConfig(state) => {
                                        state.update_frame::<executor::Default>(None, cursor_position, &mut debug);
                                        state.window.request_redraw();
                                    },
                                }
                            });
                        },
                        Event::RedrawRequested(window_id) => {
                            let is_success = if let Some(state) = windows.get_mut(&window_id) {
                                Some(match state {
                                    DynWinState::DesktopConfig(prog_state) => prog_state.redraw(cursor_position, &mut debug),
                                    DynWinState::BgConfig(prog_state) => prog_state.redraw(cursor_position, &mut debug),
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

                    use futures::Future;
                    sender.start_send(event.into()).expect("Send event");
                    let poll = run_instance.as_mut().poll(&mut context);

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
    let mut is_context_shown = false;

    while let Some(event) = receiver.next().await {
        match event {
            Event::UserEvent(ProxyMessage::Desktop(msg) ) => desktop_state.map_message(msg),
            Event::WindowEvent { ref event, window_id } => {
                match event {
                    WindowEvent::CursorMoved { position, .. } => cursor_position = *position,
                    WindowEvent::KeyboardInput { input, .. } => match input {
                        KeyboardInput {
                            state: ElementState::Pressed,
                            virtual_keycode: Some(VirtualKeyCode::Escape),
                            ..
                        } => is_context_shown = false,
                        _ => {}
                    },
                    WindowEvent::MouseInput { state: ElementState::Pressed, button, .. } => if desktop_state.window.id() == window_id {
                        match button {
                            MouseButton::Right => {
                                context_menu_state.window.set_outer_position(get_prefered_position(cursor_position, context_menu_size, monitor_size));
                                is_context_shown = true;
                            },
                            _ => is_context_shown = false,
                        }
                    }
                    _ => {}
                }

                if context_menu_state.window.id() == window_id {
                    if context_menu_state.window_event_request_exit(&event, &mut debug) {
                        is_context_shown = false;
                    }
                } else  if desktop_state.window.id() == window_id {
                    if desktop_state.window_event_request_exit(&event, &mut debug) {
                        break;
                    }
                }
                context_menu_state.window.set_visible(is_context_shown);
            },
            Event::MainEventsCleared => {
                if let Some(cmd) = desktop_state.update_frame(Some(&mut runtime), cursor_position, &mut debug){
                    runtime.spawn(cmd.map(Into::into));
                    runtime.track(desktop_state.subscription().map(Into::into));
                    desktop_state.window.request_redraw();
                }

                context_menu_state.update_frame::<executor::Default>(None, cursor_position, &mut debug);
                context_menu_state.window.request_redraw();
            },
            Event::RedrawRequested(window_id) => {
                let is_success = if context_menu_state.window.id() == window_id {
                    context_menu_state.redraw(cursor_position, &mut debug)
                } else {
                    desktop_state.redraw(cursor_position, &mut debug)
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