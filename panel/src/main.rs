mod views;
// mod strut;
mod create_window;
mod styles;
use views::{
    applets::Applets,
    context_menu::ContexMenu,
    controls::{Controls, Message},
};

mod window_state;
use window_state::State;
// mod viewport;
use create_window::{CustomEvent, NewWindow, WinType};
use futures::executor::block_on;
use iced_wgpu::wgpu;
use iced_wgpu::Settings;
use iced_winit::{futures, Debug};
use iced_winit::{winit, Application};
use winit::{
    dpi::{PhysicalPosition, PhysicalSize},
    event::{
        ElementState, Event, KeyboardInput, ModifiersState, MouseButton, StartCause,
        VirtualKeyCode, WindowEvent,
    },
    event_loop::{ControlFlow, EventLoop},
};
fn main() {
    env_logger::init();
    let event_loop = EventLoop::<Message>::with_user_event();
    let winodw_new = NewWindow::new(&event_loop, WinType::Panel(([0, 0, 32, 0], Some((0, 0)))));
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
    ));

    if let Some(display) = window.primary_monitor() {
        let width = display.size().width;
        window.set_inner_size(PhysicalSize::new(width, 32));
        popup_x = width - 400;
        popup_menu.set_outer_position(PhysicalPosition::new(popup_x, 32));
    }
    window.set_outer_position(PhysicalPosition::new(0, 0));
    // Since main can't be async, we're going to need to block
    let sound = Applets::new();
    let mut menu_state = block_on(State::new(
        popup_menu,
        sound,
        Some(&setttings(16)),
        cursor_position,
        &mut debug,
    ));
    let (panel, _) = Controls::new(());
    let mut state = block_on(State::new(
        window,
        panel,
        Some(&setttings(16)),
        cursor_position,
        &mut debug,
    ));
    let event_loop_proxy = event_loop.create_proxy();
    use std::time::Instant;
    let timer_length = std::time::Duration::new(1, 0);
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
            Event::UserEvent(event) => match event {
                Message::Timer => {
                    println!("timer event: {:?}", event);
                    state.win_state.queue_message(Message::Timer);
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
                    WindowEvent::MouseInput {
                        device_id: _,
                        state: _,
                        button,
                        modifiers: _,
                    } => match button {
                        MouseButton::Right => {
                            println!("Left click mouse: position: {:?}", cursor_position);
                            context_state.window.set_visible(true);
                        }
                        MouseButton::Left => {
                            context_state.window.set_visible(false);
                        }
                        _ => {}
                    },
                    WindowEvent::Resized(physical_size) => {
                        state.resize(*physical_size);
                        // context_state.resize(*physical_size);
                        // menu_state.resize(*physical_size);
                    }
                    WindowEvent::CursorMoved { position, .. } => {
                        cursor_position = *position;
                    }
                    WindowEvent::ModifiersChanged(modi) => modifiers = *modi,
                    WindowEvent::ScaleFactorChanged { new_inner_size, .. } => {
                        if state.window.id() == window_id {
                            state.resize(**new_inner_size);
                        } else if menu_state.window.id() == window_id {
                            menu_state.resize(**new_inner_size);
                        } else if context_state.window.id() == window_id {
                            context_state.resize(**new_inner_size);
                        } else {
                        }
                    }
                    _ => {}
                }
                if window_id == state.window.id() {
                    state.map_event(&modifiers, &event);
                    println!("Panel State");
                } else if window_id == menu_state.window.id() {
                    menu_state.map_event(&modifiers, &event);
                    println!("Menu state");
                } else if window_id == context_state.window.id() {
                    context_state.map_event(&modifiers, &event);
                    println!("Context state");
                } else {
                    {}
                }
            }
            Event::MainEventsCleared => {
                state.update_frame(cursor_position, &mut debug);
                menu_state.update_frame(cursor_position, &mut debug);
                context_state.update_frame(cursor_position, &mut debug);
            }
            Event::RedrawRequested(window_id) => {
                if state.window.id() == window_id {
                    state.redraw(&debug);
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
