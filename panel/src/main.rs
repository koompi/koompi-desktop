const WINDOW_HEIGHT: u32 = 32;
const RESERVE_SIZE: [u64; 4] = [0, 0, 32, 0];
const MENU_WIDTH: u16 = 400;
const MENU_HEIGHT: u16 = MENU_WIDTH;
mod proxy_message;
mod styles;
mod task_manager;
mod views;
use proxy_message::ProxyMessage;
use views::{
    applets::{Applets, AppletsMsg, ControlType},
    panel::{DesktopPanel, Message},
};
use winit::{
    dpi::{PhysicalPosition, PhysicalSize},
    platform::unix::{WindowBuilderExtUnix, XWindowStrut, XWindowType},
    window::{Window, WindowBuilder},
};
mod window_state;
use futures::executor::block_on;
use futures::{channel::mpsc, task};
use iced_wgpu::wgpu;
use iced_wgpu::Settings;
use iced_winit::{button, futures, winit, Application, Debug, Executor, Program, Proxy, Runtime};

use window_state::State;
use winit::{
    event::{
        DeviceEvent, ElementState, Event, KeyboardInput, ModifiersState, MouseButton, StartCause,
        VirtualKeyCode, WindowEvent,
    },
    event_loop::{ControlFlow, EventLoop},
};
fn main() {
    std::env::set_var("WINIT_X11_SCALE_FACTOR", "1.25");

    let event_loop = EventLoop::with_user_event();
    // uncomment to be able to test task manager.
    // let task_manager = task_manager::taskmanager::TaskManager::new();
    // match task_manager {
    //     Ok(()) => {}
    //     Err(e) => println!("Error: {:?}", e),
    // }
    let instance = wgpu::Instance::new(wgpu::BackendBit::PRIMARY);
    let window = WindowBuilder::new()
        .with_x11_window_strut(vec![XWindowStrut::Strut(RESERVE_SIZE)])
        .with_x11_window_type(vec![XWindowType::Dock])
        .build(&event_loop)
        .unwrap();

    let popup_menu = WindowBuilder::new()
        .with_x11_window_type(vec![XWindowType::PopupMenu, XWindowType::Menu])
        .with_decorations(false)
        .with_always_on_top(true)
        .with_inner_size(PhysicalSize::new(MENU_WIDTH, MENU_HEIGHT))
        .with_visible(false)
        .build(&event_loop)
        .unwrap();
    let mut popup_x = 0;
    let (mut cursor_position, mut debug, mut modifiers) = (
        PhysicalPosition::new(-1.0, -1.0),
        Debug::new(),
        ModifiersState::default(),
    );
    handle_window(&window, &mut popup_x);
    // Since main can't be async, we're going to need to block
    let event_battery_proxy = event_loop.create_proxy();
    let (sound, _) = Applets::new(event_battery_proxy);
    let mut menu_state = block_on(State::new(
        popup_menu,
        sound,
        Some(&setttings(16)),
        cursor_position,
        &mut debug,
        &instance,
    ));

    let event_send_proxy = event_loop.create_proxy();
    let (panel, _) = DesktopPanel::new(event_send_proxy);
    let mut control_state = block_on(State::new(
        window,
        panel,
        Some(&setttings(16)),
        cursor_position,
        &mut debug,
        &instance,
    ));
    let event_loop_proxy = event_loop.create_proxy();
    use std::time::Instant;
    let timer_length = std::time::Duration::new(1, 0);
    let mut coutner: usize = 0;
    event_loop.run(move |event, _, control_flow| {
        match event {
            Event::NewEvents(StartCause::Init) => {
                *control_flow = ControlFlow::WaitUntil(Instant::now() + timer_length);
            }
            // When the timer expires, dispatch a timer event and queue a new timer.
            Event::NewEvents(StartCause::ResumeTimeReached { .. }) => {
                event_loop_proxy.send_event(Message::Timer).ok();

                *control_flow = ControlFlow::WaitUntil(Instant::now() + timer_length);
            }
            Event::DeviceEvent { device_id, event } => match event {
                DeviceEvent::Button { .. } => {
                    let kind = menu_state.win_state.program().kind;
                    if menu_state.is_cursor_left.unwrap() && menu_state.is_visible {
                        match kind {
                            ControlType::Battery => {
                                control_state
                                    .win_state
                                    .queue_message(Message::Battery(false));
                            }
                            ControlType::Monitor => {
                                control_state
                                    .win_state
                                    .queue_message(Message::MonitorShow(false));
                            }
                            ControlType::Sound => {
                                control_state
                                    .win_state
                                    .queue_message(Message::SoundShow(false));
                            }
                            ControlType::Wifi => {
                                control_state
                                    .win_state
                                    .queue_message(Message::WifiShow(false));
                            }
                            _ => {}
                        }
                    } else {
                        {}
                    }
                }
                _ => {}
            },
            Event::UserEvent(event) => match event {
                Message::Timer => {
                    control_state.win_state.queue_message(Message::Timer);
                    if coutner == 30 {
                        menu_state.win_state.queue_message(AppletsMsg::BatteryTimer);
                        control_state
                            .win_state
                            .queue_message(Message::BatteryUpdate(
                                menu_state
                                    .win_state
                                    .program()
                                    .battery
                                    .battery_state
                                    .current_battery,
                            ));

                        coutner = 0;
                    } else {
                        coutner += 1;
                    }
                }
                Message::ShowMenu => {}
                Message::MonitorShow(is_visible) => {
                    handle_visible_pos(&mut menu_state, ControlType::Monitor, is_visible, popup_x);
                    menu_state.is_visible = is_visible;
                }
                Message::SoundShow(is_visible) => {
                    handle_visible_pos(&mut menu_state, ControlType::Sound, is_visible, popup_x);
                    menu_state.is_visible = is_visible;
                }
                Message::WifiShow(is_visible) => {
                    handle_visible_pos(&mut menu_state, ControlType::Wifi, is_visible, popup_x);
                    menu_state.is_visible = is_visible;
                }
                Message::Battery(is_visible) => {
                    handle_visible_pos(&mut menu_state, ControlType::Battery, is_visible, popup_x);
                    menu_state.is_visible = is_visible;
                }
                _ => {}
            },
            Event::WindowEvent {
                window_id,
                ref event,
            } => {
                // UPDATED!
                match event {
                    WindowEvent::CloseRequested => *control_flow = ControlFlow::Exit,
                    WindowEvent::KeyboardInput {
                        input,
                        is_synthetic,
                        ..
                    } => match input {
                        KeyboardInput {
                            state: ElementState::Pressed,
                            virtual_keycode: Some(VirtualKeyCode::Escape),
                            ..
                        } => *control_flow = ControlFlow::Exit,
                        _ => {
                            println!("Is synthetic: {:?}", is_synthetic);
                        }
                    },
                    WindowEvent::Focused(is_focus) => {
                        println!("Is focus: {:?}", is_focus);
                    }
                    WindowEvent::CursorLeft { device_id } => {
                        println!("Cursor left: {:?}", device_id);
                        menu_state.is_cursor_left = Some(true);
                    }
                    WindowEvent::CursorEntered { device_id } => {
                        println!("Cursor Enter: {:?}", device_id);
                        menu_state.is_cursor_left = Some(false);
                    }
                    WindowEvent::MouseInput {
                        device_id: _,
                        state: _,
                        ..
                    } => {}
                    WindowEvent::Resized(physical_size) => {
                        if control_state.window.id() == window_id {
                            control_state.resize(*physical_size);
                        } else if menu_state.window.id() == window_id {
                            menu_state.resize(*physical_size);
                        }
                    }
                    WindowEvent::CursorMoved { position, .. } => {
                        cursor_position = *position;
                    }
                    WindowEvent::ModifiersChanged(modi) => modifiers = *modi,
                    WindowEvent::ScaleFactorChanged {
                        scale_factor: _,
                        new_inner_size,
                    } => {
                        if control_state.window.id() == window_id {
                            control_state.resize(**new_inner_size);
                        } else if menu_state.window.id() == window_id {
                            menu_state.resize(**new_inner_size);
                        }
                    }
                    _ => {}
                }
                if window_id == control_state.window.id() {
                    control_state.map_event(&modifiers, &event);
                } else if window_id == menu_state.window.id() {
                    menu_state.map_event(&modifiers, &event);
                } else {
                    {}
                }
            }
            Event::MainEventsCleared => {
                control_state.update_frame(cursor_position, &mut debug);
                menu_state.update_frame(cursor_position, &mut debug);
            }
            Event::RedrawRequested(window_id) => {
                if control_state.window.id() == window_id {
                    control_state.redraw(&debug);
                } else if menu_state.window.id() == window_id {
                    menu_state.redraw(&debug);
                } else {
                }
            }

            _ => {}
        }
    });
}
pub fn setttings(text_size: u16) -> Settings {
    Settings {
        default_text_size: text_size,
        ..Settings::default()
    }
}
pub fn handle_window(win: &Window, pos: &mut u32) {
    if let Some(display) = win.primary_monitor() {
        let width = display.size().width;
        win.set_inner_size(PhysicalSize::new(width, WINDOW_HEIGHT));
        *pos = width - 400;
    }
    win.set_outer_position(PhysicalPosition::new(0, 0));
}

pub fn handle_visible_pos(win: &mut State<Applets>, kind: ControlType, is_visible: bool, pos: u32) {
    win.win_state.queue_message(AppletsMsg::SwitchView(kind));
    if is_visible {
        win.window.set_visible(true);
        win.window.set_always_on_top(true);
    } else {
        win.window.set_visible(false);
        win.win_state
            .queue_message(AppletsMsg::SwitchView(ControlType::Default));
    }
    win.window
        .set_outer_position(PhysicalPosition::new(pos, 32));
}

// async fn run_instance<E>(
//     mut desktop_state: State<DesktopPanel>,
//     mut context_menu_state: State<Applets>,
//     mut runtime: Runtime<E, Proxy<ProxyMessage>, ProxyMessage>,
//     mut receiver: mpsc::UnboundedReceiver<winit::event::Event<'_, ProxyMessage>>,
//     context_menu_size: PhysicalSize<f64>,
//     monitor_size: PhysicalSize<u32>,
// ) where
//     E: Executor + 'static,
// {
//     use futures::stream::StreamExt;

//     // Other
//     let mut debug = Debug::new();
//     let mut cursor_position = PhysicalPosition::new(-1.0, -1.0);
//     let mut is_context_shown = false;

//     while let Some(event) = receiver.next().await {
//         match event {
//             Event::UserEvent(ProxyMessage::DesktopPanel(msg)) => desktop_state.map_message(msg),
//             Event::WindowEvent {
//                 ref event,
//                 window_id,
//             } => {
//                 match event {
//                     WindowEvent::CursorMoved { position, .. } => cursor_position = *position,
//                     WindowEvent::KeyboardInput { input, .. } => match input {
//                         KeyboardInput {
//                             state: ElementState::Pressed,
//                             virtual_keycode: Some(VirtualKeyCode::Escape),
//                             ..
//                         } => is_context_shown = false,
//                         _ => {}
//                     },
//                     WindowEvent::MouseInput {
//                         state: ElementState::Pressed,
//                         button,
//                         ..
//                     } => {
//                         if desktop_state.window.id() == window_id {
//                             match button {
//                                 MouseButton::Right => {
//                                     context_menu_state.window.set_outer_position(
//                                         get_prefered_position(
//                                             cursor_position,
//                                             context_menu_size,
//                                             monitor_size,
//                                         ),
//                                     );
//                                     is_context_shown = true;
//                                 }
//                                 _ => is_context_shown = false,
//                             }
//                         }
//                     }
//                     _ => {}
//                 }

//                 if context_menu_state.window.id() == window_id {
//                     if context_menu_state.window_event_request_exit(&event, &mut debug) {
//                         is_context_shown = false;
//                     }
//                 } else if desktop_state.window.id() == window_id {
//                     desktop_state.window_event_request_exit(&event, &mut debug);
//                 }
//                 context_menu_state.window.set_visible(is_context_shown);
//             }
//             Event::MainEventsCleared => {
//                 if let Some(cmd) =
//                     desktop_state.update_frame(Some(&mut runtime), cursor_position, &mut debug)
//                 {
//                     runtime.spawn(cmd.map(Into::into));
//                     runtime.track(desktop_state.subscription().map(Into::into));
//                     desktop_state.window.request_redraw();
//                 }

//                 context_menu_state.update_frame::<executor::Default>(
//                     None,
//                     cursor_position,
//                     &mut debug,
//                 );
//                 context_menu_state.window.request_redraw();
//             }
//             Event::RedrawRequested(window_id) => {
//                 let is_success = if context_menu_state.window.id() == window_id {
//                     context_menu_state.redraw(cursor_position, &mut debug)
//                 } else {
//                     desktop_state.redraw(cursor_position, &mut debug)
//                 };

//                 if !is_success {
//                     break;
//                 }
//             }
//             _ => (),
//         }
//     }
// }
