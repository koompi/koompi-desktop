const STRUT_HEIGHT: u64 = 32;
const WINDOW_HEIGHT: u32 = 32;
const MENU_POS: u32 = 32;
mod create_window;
mod styles;
mod views;
use views::{
    applets::{Applets, AppletsMsg, ControlType},
    context_menu::ContexMenu,
    panel::{Controls, Message},
};

mod window_state;
use create_window::{NewWindow, WinType};
use futures::executor::block_on;
use iced_wgpu::wgpu;
use iced_wgpu::Settings;
use iced_winit::{futures, Debug};
use iced_winit::{winit, Application, Program};
use window_state::State;
use winit::{
    dpi::{PhysicalPosition, PhysicalSize},
    event::{
        DeviceEvent, ElementState, Event, KeyboardInput, ModifiersState, MouseButton, StartCause,
        VirtualKeyCode, WindowEvent,
    },
    event_loop::{ControlFlow, EventLoop},
    window::Window,
};
fn main() {
    std::env::set_var("WINIT_X11_SCALE_FACTOR", "1.25");
    env_logger::init();
    let event_loop = EventLoop::<Message>::with_user_event();
    let winodw_new = NewWindow::new(
        &event_loop,
        WinType::Panel(([0, 0, STRUT_HEIGHT, 0], Some((0, 0)))),
    );
    let instance = wgpu::Instance::new(wgpu::BackendBit::PRIMARY);
    let window = winodw_new.instance();
    let popup_new = NewWindow::new(&event_loop, WinType::Menu(Some((400, 400))));
    let popup_menu = popup_new.instance();
    let context_menu_new = NewWindow::new(&event_loop, WinType::Dock(Some((200, 200))));
    let context_menu = context_menu_new.instance();
    let mut popup_x = 0;
    let (mut cursor_position, mut debug, mut modifiers) = (
        PhysicalPosition::new(-1.0, -1.0),
        Debug::new(),
        ModifiersState::default(),
    );
    let (context_instance, _) = ContexMenu::new(());
    let mut context_state = block_on(State::new(
        context_menu,
        context_instance,
        Some(&setttings(20)),
        cursor_position,
        &mut debug,
        &instance,
    ));
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
    let (panel, _) = Controls::new(event_send_proxy);
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
                DeviceEvent::Button { button, state } => {
                    let kind = menu_state.win_state.program().kind;
                    if menu_state.is_cursor_left.unwrap() && menu_state.is_visible {
                        match kind {
                            ControlType::Battery => {
                                println!("Battery");
                                control_state
                                    .win_state
                                    .queue_message(Message::Battery(false));
                            }
                            ControlType::Monitor => {
                                control_state
                                    .win_state
                                    .queue_message(Message::MonitorShow(false));
                                println!("Monitor");
                            }
                            ControlType::Sound => {
                                control_state
                                    .win_state
                                    .queue_message(Message::SoundShow(false));
                                println!("Sound");
                            }
                            ControlType::Wifi => {
                                control_state
                                    .win_state
                                    .queue_message(Message::WifiShow(false));
                                println!("Wifi");
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
                    println!("Counter: {}", coutner);
                }
                Message::ShowMenu => {
                    *control_flow = ControlFlow::Exit;
                }
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
                    WindowEvent::KeyboardInput { input, .. } => match input {
                        KeyboardInput {
                            state: ElementState::Pressed,
                            virtual_keycode: Some(VirtualKeyCode::Escape),
                            ..
                        } => *control_flow = ControlFlow::Exit,
                        _ => {}
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
                        button,
                        modifiers: _,
                    } => match button {
                        MouseButton::Right => {
                            context_state.window.set_visible(true);
                        }
                        MouseButton::Left => {
                            context_state.window.set_visible(false);
                        }
                        _ => {}
                    },
                    WindowEvent::Resized(physical_size) => {
                        if control_state.window.id() == window_id {
                            control_state.resize(*physical_size);
                        } else if menu_state.window.id() == window_id {
                            menu_state.resize(*physical_size);
                        } else {
                            context_state.resize(*physical_size);
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
                        } else if context_state.window.id() == window_id {
                            context_state.resize(**new_inner_size);
                        } else {
                        }
                    }
                    _ => {}
                }
                if window_id == control_state.window.id() {
                    control_state.map_event(&modifiers, &event);
                } else if window_id == menu_state.window.id() {
                    menu_state.map_event(&modifiers, &event);
                } else if window_id == context_state.window.id() {
                    context_state.map_event(&modifiers, &event);
                } else {
                    {}
                }
            }
            Event::MainEventsCleared => {
                control_state.update_frame(cursor_position, &mut debug);
                menu_state.update_frame(cursor_position, &mut debug);
                context_state.update_frame(cursor_position, &mut debug);
            }
            Event::RedrawRequested(window_id) => {
                if control_state.window.id() == window_id {
                    control_state.redraw(&debug);
                } else if menu_state.window.id() == window_id {
                    menu_state.redraw(&debug);
                } else if context_state.window.id() == window_id {
                    context_state.redraw(&debug);
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
    } else {
        win.window.set_visible(false);
        win.win_state
            .queue_message(AppletsMsg::SwitchView(ControlType::Default));
    }
    win.window
        .set_outer_position(PhysicalPosition::new(pos, 32));
}
