mod background;
mod configs;
mod constants;
mod desktop_item;
mod desktop_manager;
mod errors;
mod gui;
mod proxy_message;
mod window_state;
use background::WallpaperItem;
use configs::PersistentData;
use desktop_item::DesktopItem;
use desktop_manager::DesktopManager;
use tauri_dialog::{DialogBuilder, DialogButtons, DialogSelection, DialogStyle};

use gui::{
    BackgroundConfMsg, BackgroundConfigUI, ContextMenu, ContextMsg, Desktop, DesktopConfigMsg,
    DesktopConfigUI,
};
use proxy_message::ProxyMessage;
use std::{cell::RefCell, rc::Rc};
use window_state::WindowState;

use futures::{channel::mpsc, task};
use iced::executor;
use iced_wgpu::{wgpu, Settings};
use iced_winit::{button, futures, winit, Application, Debug, Executor, Proxy, Runtime};
use std::collections::HashMap;
use winit::{
    dpi::{PhysicalPosition, PhysicalSize},
    event::{ElementState, Event, KeyboardInput, MouseButton, VirtualKeyCode, WindowEvent},
    event_loop::{ControlFlow, EventLoop},
    platform::unix::{WindowBuilderExtUnix, XWindowType},
    window::WindowBuilder,
};

fn main() {
    std::env::set_var("WINIT_X11_SCALE_FACTOR", "1.25");
    match DesktopManager::new() {
        Ok(mut desktop_manager) => {
            let mut old_desktop_conf = desktop_manager.config().to_owned();
            let desktop_conf = Rc::new(RefCell::new(desktop_manager.config().to_owned()));
            let desktop_items = Rc::new(RefCell::new(desktop_manager.desktop_items().to_owned()));
            let wallpaper_items =
                Rc::new(RefCell::new(desktop_manager.wallpaper_items().to_owned()));
            // .into_iter().map(|item| (button::State::new(), item.to_owned())).collect::<Vec<(button::State, DesktopItem)>>()

            // Instance
            let mut windows = HashMap::new();
            let event_loop = EventLoop::with_user_event();
            let event_proxy = event_loop.create_proxy();
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
            let (monitor_size, monitor_position) = event_loop
                .primary_monitor()
                .map(|m| (m.size(), m.position()))
                .unwrap_or((PhysicalSize::new(1920, 1080), PhysicalPosition::new(0, 0)));
            let mut cursor_position = PhysicalPosition::new(-1.0, -1.0);
            let mut debug = Debug::new();

            // Desktop Init Section
            let desktop_state = {
                let (desktop, init_cmd) = {
                    runtime.enter(|| {
                        Desktop::new((
                            (monitor_size.width, monitor_size.height),
                            Rc::clone(&desktop_conf),
                            desktop_items.borrow().len(),
                            Rc::clone(&desktop_items),
                        ))
                    })
                };
                let desktop_window = WindowBuilder::new()
                    .with_x11_window_type(vec![XWindowType::Desktop])
                    .with_position(monitor_position)
                    .with_title(desktop.title())
                    .with_inner_size(monitor_size)
                    .with_visible(false)
                    .build(&event_loop)
                    .unwrap();

                let subscription = desktop.subscription();
                runtime.spawn(init_cmd.map(Into::into));
                runtime.track(subscription.map(Into::into));
                futures::executor::block_on(WindowState::new(
                    &instance,
                    desktop_window,
                    desktop,
                    true,
                    Some(&settings),
                    None,
                ))
            };

            // Context Menu Init Section
            let context_menu_size = PhysicalSize::new(300.0, 210.0);
            let context_menu_state = {
                let (context_menu, _) = ContextMenu::new(event_proxy.to_owned());
                let context_menu_window = WindowBuilder::new()
                    .with_x11_window_type(vec![XWindowType::Desktop, XWindowType::PopupMenu])
                    .with_position(cursor_position)
                    .with_title(context_menu.title())
                    .with_inner_size(context_menu_size)
                    .with_resizable(false)
                    .with_maximized(false)
                    .with_visible(false)
                    .build(&event_loop)
                    .unwrap();
                futures::executor::block_on(WindowState::new(
                    &instance,
                    context_menu_window,
                    context_menu,
                    false,
                    Some(&settings),
                    None,
                ))
            };

            let mut run_instance = Box::pin(run_instance::<executor::Default>(
                desktop_state,
                context_menu_state,
                runtime,
                receiver,
                context_menu_size,
                monitor_size,
            ));
            let mut context = task::Context::from_waker(task::noop_waker_ref());

            event_loop.run(move |event, event_loop, control_flow| {
                *control_flow = ControlFlow::Wait;

                if let Some(event) = event.to_static() {
                    match event.clone() {
                        Event::UserEvent(custom_event) => match custom_event {
                            ProxyMessage::DesktopConf(DesktopConfigMsg::SortingChanged(_))
                            | ProxyMessage::DesktopConf(DesktopConfigMsg::SortDescToggled(_)) => {
                                let desktop_conf = desktop_conf.borrow();
                                desktop_manager.sort_desktop_items(
                                    desktop_conf.desktop_item_conf.sorting,
                                    desktop_conf.desktop_item_conf.sort_descending,
                                );
                                let mut desktop_items = desktop_items.borrow_mut();
                                *desktop_items = desktop_manager.desktop_items().to_owned();
                            }
                            ProxyMessage::Bg(BackgroundConfMsg::AddWallpaperClicked) => {
                                if let nfd2::Response::Okay(file_path) =
                                    nfd2::open_file_dialog(Some("png,jpg"), None).expect("oh no")
                                {
                                    match desktop_manager.add_wallpaper(file_path) {
                                        Ok((conf, items)) => {
                                            let mut desktop_conf = desktop_conf.borrow_mut();
                                            *desktop_conf = conf;
                                            let mut wallpaper_items = wallpaper_items.borrow_mut();
                                            *wallpaper_items = items;
                                            // .into_iter().map(|item| (button::State::new(), item)).collect();
                                            let _ = desktop_conf.save();
                                            old_desktop_conf = desktop_conf.to_owned();
                                        }
                                        Err(err) => {
                                            let _ = DialogBuilder::new()
                                                .title("Error")
                                                .message(&format!("{}", err))
                                                .style(DialogStyle::Error)
                                                .build()
                                                .show();
                                        }
                                    }
                                }
                            }
                            ProxyMessage::ContextMenu(msg) => match msg {
                                ContextMsg::NewFolder => {
                                    match desktop_manager.create_new_folder() {
                                        Ok(items) => {
                                            let mut desktop_items = desktop_items.borrow_mut();
                                            *desktop_items = items;
                                            // .into_iter().map(|item| (button::State::new(), item)).collect();
                                        }
                                        Err(err) => {
                                            let _ = DialogBuilder::new()
                                                .title("Error")
                                                .message(&format!("{}", err))
                                                .style(DialogStyle::Error)
                                                .build()
                                                .show();
                                        }
                                    }
                                }
                                ContextMsg::ChangeBG => {
                                    // Background Config Init Section
                                    let (bg_config, _) = BackgroundConfigUI::new((
                                        event_proxy.to_owned(),
                                        Rc::clone(&desktop_conf),
                                        (monitor_size.width, monitor_size.height),
                                        wallpaper_items.borrow().len(),
                                        Rc::clone(&wallpaper_items),
                                        desktop_manager.wallpaper_items().iter().position(|item| {
                                            old_desktop_conf
                                                .background_conf
                                                .wallpaper_conf
                                                .wallpaper_path
                                                == item.path
                                        }),
                                    ));
                                    let bg_config_window = WindowBuilder::new()
                                        .with_x11_window_type(vec![
                                            XWindowType::Normal,
                                            XWindowType::Utility,
                                        ])
                                        .with_title(bg_config.title())
                                        .with_resizable(false)
                                        .with_maximized(false)
                                        .with_visible(false)
                                        .build(&event_loop)
                                        .unwrap();
                                    windows.insert(
                                        bg_config_window.id(),
                                        DynWinState::BgConfig(futures::executor::block_on(
                                            WindowState::new(
                                                &instance,
                                                bg_config_window,
                                                bg_config,
                                                true,
                                                Some(&settings),
                                                Some(20 * 1024),
                                            ),
                                        )),
                                    );
                                }
                                ContextMsg::DesktopView => {
                                    // Desktop Config Init Section
                                    let (desktop_config, _) = DesktopConfigUI::new((
                                        event_proxy.to_owned(),
                                        Rc::clone(&desktop_conf),
                                    ));
                                    let desktop_config_window = WindowBuilder::new()
                                        .with_x11_window_type(vec![
                                            XWindowType::Normal,
                                            XWindowType::Utility,
                                        ])
                                        .with_inner_size(PhysicalSize::new(250, 400))
                                        .with_title(desktop_config.title())
                                        .with_resizable(false)
                                        .with_maximized(false)
                                        .with_visible(false)
                                        .build(&event_loop)
                                        .unwrap();
                                    windows.insert(
                                        desktop_config_window.id(),
                                        DynWinState::DesktopConfig(futures::executor::block_on(
                                            WindowState::new(
                                                &instance,
                                                desktop_config_window,
                                                desktop_config,
                                                true,
                                                Some(&settings),
                                                None,
                                            ),
                                        )),
                                    );
                                }
                                _ => {}
                            },
                            _ => {}
                        },
                        Event::WindowEvent {
                            ref event,
                            window_id,
                        } => {
                            use DynWinState::*;

                            if let WindowEvent::CursorMoved { position, .. } = event {
                                cursor_position = *position;
                            }

                            let mut handle_exit = |has_changed: bool| -> bool {
                                let mut is_close = true;

                                if has_changed {
                                    match DialogBuilder::new()
                                        .title("Configuration")
                                        .message("Do you want to save the configuration?")
                                        .buttons(DialogButtons::YesNo)
                                        .style(DialogStyle::Question)
                                        .build()
                                        .show()
                                    {
                                        DialogSelection::Yes => {
                                            let desktop_conf = desktop_conf.borrow();
                                            let _ = desktop_conf.save();
                                            old_desktop_conf = desktop_conf.to_owned();
                                        }
                                        DialogSelection::No => {
                                            let mut desktop_conf = desktop_conf.borrow_mut();
                                            *desktop_conf = old_desktop_conf.to_owned();
                                        }
                                        _ => is_close = false,
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
                                    }
                                    BgConfig(state) => {
                                        if state.window_event_request_exit(&event, &mut debug) {
                                            if handle_exit(state.has_changed()) {
                                                windows.remove(&window_id);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        Event::MainEventsCleared => {
                            windows.iter_mut().for_each(|(_, state)| match state {
                                DynWinState::DesktopConfig(state) => {
                                    state.update_frame::<executor::Default>(
                                        None,
                                        cursor_position,
                                        &mut debug,
                                    );
                                    state.window.request_redraw();
                                }
                                DynWinState::BgConfig(state) => {
                                    state.update_frame::<executor::Default>(
                                        None,
                                        cursor_position,
                                        &mut debug,
                                    );
                                    state.window.request_redraw();
                                }
                            });
                        }
                        Event::RedrawRequested(window_id) => {
                            let is_success = if let Some(state) = windows.get_mut(&window_id) {
                                Some(match state {
                                    DynWinState::DesktopConfig(prog_state) => {
                                        prog_state.redraw(cursor_position, &mut debug)
                                    }
                                    DynWinState::BgConfig(prog_state) => {
                                        prog_state.redraw(cursor_position, &mut debug)
                                    }
                                })
                            } else {
                                None
                            };
                            if let Some(is_success) = is_success {
                                if !is_success {
                                    *control_flow = ControlFlow::Exit;
                                }
                            }
                        }
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
        }
        Err(err) => eprintln!("{:?}", err),
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
            Event::UserEvent(ProxyMessage::Desktop(msg)) => desktop_state.map_message(msg),
            Event::WindowEvent {
                ref event,
                window_id,
            } => {
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
                    WindowEvent::MouseInput {
                        state: ElementState::Pressed,
                        button,
                        ..
                    } => {
                        if desktop_state.window.id() == window_id {
                            match button {
                                MouseButton::Right => {
                                    context_menu_state.window.set_outer_position(
                                        get_prefered_position(
                                            cursor_position,
                                            context_menu_size,
                                            monitor_size,
                                        ),
                                    );
                                    is_context_shown = true;
                                }
                                _ => is_context_shown = false,
                            }
                        }
                    }
                    _ => {}
                }

                if context_menu_state.window.id() == window_id {
                    if context_menu_state.window_event_request_exit(&event, &mut debug) {
                        is_context_shown = false;
                    }
                } else if desktop_state.window.id() == window_id {
                    desktop_state.window_event_request_exit(&event, &mut debug);
                }
                context_menu_state.window.set_visible(is_context_shown);
            }
            Event::MainEventsCleared => {
                if let Some(cmd) =
                    desktop_state.update_frame(Some(&mut runtime), cursor_position, &mut debug)
                {
                    runtime.spawn(cmd.map(Into::into));
                    runtime.track(desktop_state.subscription().map(Into::into));
                    desktop_state.window.request_redraw();
                }

                context_menu_state.update_frame::<executor::Default>(
                    None,
                    cursor_position,
                    &mut debug,
                );
                context_menu_state.window.request_redraw();
            }
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

fn get_prefered_position(
    cursor_position: PhysicalPosition<f64>,
    window_size: PhysicalSize<f64>,
    monitor_size: PhysicalSize<u32>,
) -> PhysicalPosition<f64> {
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
