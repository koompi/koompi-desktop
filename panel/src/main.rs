mod views;
// mod strut;
mod styles;

use futures::task::SpawnExt;
use views::{
    applets::{Applets, ControlType},
    context_menu::ContexMenu,
    controls::Controls,
};
mod window_state;
use window_state::State;
// mod viewport;
use futures::executor::block_on;
use iced::Sandbox;
use iced_wgpu::wgpu;
use iced_wgpu::Settings;
use iced_winit::{application, program, winit, Application, Program};
use iced_winit::{conversion, futures, Debug};
use winit::{
    dpi::{PhysicalPosition, PhysicalSize},
    event::{
        ElementState, Event, KeyboardInput, ModifiersState, MouseButton, StartCause,
        VirtualKeyCode, WindowEvent,
    },
    event_loop::{ControlFlow, EventLoop},
    platform::unix::{WindowBuilderExtUnix, XWindowStrut, XWindowType},
    window::WindowBuilder,
};

fn main() {
    env_logger::init();
    let event_loop = EventLoop::new();
    let window = WindowBuilder::new()
        .with_x11_window_strut(vec![XWindowStrut::Strut([0, 0, 32, 0])])
        // .with_x11_window_strut(vec![XWindowStrut::StrutPartial([
        //     0, 0, 32, 0, 0, 0, 0, 0, 0, 1920, 0, 0,
        // ])])
        .with_x11_window_type(vec![XWindowType::Dock])
        .build(&event_loop)
        .unwrap();
    let popup_menu = WindowBuilder::new()
        .with_x11_window_type(vec![XWindowType::Dock])
        .with_inner_size(PhysicalSize::new(400, 400))
        .build(&event_loop)
        .unwrap();
    popup_menu.set_visible(false);
    let context_menu = WindowBuilder::new()
        .with_x11_window_type(vec![XWindowType::Dock])
        .with_inner_size(PhysicalSize::new(400, 200))
        .build(&event_loop)
        .unwrap();
    context_menu.set_visible(false);
    let (mut cursor_position, mut debug, mut staging_belt, mut modifiers) = graphics_props();
    let mut context_state = block_on(State::new(context_menu, Some(&setttings(20))));
    let (context_instance, _) = ContexMenu::new(());

    let mut context_state_app = create_state(
        context_instance,
        &mut context_state,
        &mut debug,
        cursor_position,
    );
    let mut popup_x = 0;
    if let Some(display) = window.primary_monitor() {
        let width = display.size().width;
        window.set_inner_size(PhysicalSize::new(width, 32));
        popup_x = width - 400;
        popup_menu.set_outer_position(PhysicalPosition::new(popup_x, 32));
    }
    window.set_outer_position(PhysicalPosition::new(0, 0));
    // Since main can't be async, we're going to need to block
    let mut menu_state = block_on(State::new(popup_menu, Some(&setttings(16))));
    let sound = Applets::new();
    let mut state: State = block_on(State::new(window, Some(&setttings(16))));
    let mut sound_state = create_state(sound, &mut menu_state, &mut debug, cursor_position);
    let (panel, _) = Controls::new(());
    let mut panel_state = create_state(panel, &mut state, &mut debug, cursor_position);
    let event_loop_proxy = event_loop.create_proxy();
    use std::time::Instant;
    let timer_length = std::time::Duration::new(1, 0);
    #[derive(Debug, Clone, Copy)]
    enum CustomEvent {
        Timer,
    }
    event_loop.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::Wait;
        match event {
            Event::NewEvents(StartCause::Init) => {
                *control_flow = ControlFlow::WaitUntil(Instant::now() + timer_length);
            }
            // When the timer expires, dispatch a timer event and queue a new timer.
            Event::NewEvents(StartCause::ResumeTimeReached { .. }) => {
                event_loop_proxy.send_event(()).ok();
                *control_flow = ControlFlow::WaitUntil(Instant::now() + timer_length);
            }
            Event::UserEvent(event) => println!("user event: {:?}", event),
            Event::WindowEvent { ref event, .. } => {
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
                    WindowEvent::CursorMoved { position, .. } => cursor_position = *position,
                    WindowEvent::ModifiersChanged(modi) => modifiers = *modi,
                    WindowEvent::ScaleFactorChanged { new_inner_size, .. } => {
                        // new_inner_size is &&mut so w have to dereference it twice
                        state.resize(**new_inner_size);
                        // menu_state.resize(**new_inner_size);
                    }
                    _ => {}
                }
                state.map_event(&mut panel_state, &modifiers, &event);
                menu_state.map_event(&mut sound_state, &modifiers, &event);
                context_state.map_event(&mut context_state_app, &modifiers, &event);
            }
            Event::MainEventsCleared => {
                // RedrawRequested will only trigger once, unless we manually
                // request it.
                state.update_frame(&mut panel_state, cursor_position, &mut debug);
                menu_state.update_frame(&mut sound_state, cursor_position, &mut debug);
                context_state.update_frame(&mut context_state_app, cursor_position, &mut debug);
            }
            Event::RedrawRequested(_) => {
                let views::applets::Applets { kind, .. } = sound_state.program();
                let program = panel_state.program();
                context_state.window.set_outer_position(cursor_position);
                if program.is_exit {
                    *control_flow = ControlFlow::Exit;
                } else {
                }
                if program.is_shown {
                    program.subscription();
                    kind.replace(program.get_kind());
                    // kind = RefCell::new(ControlType::Sound);
                    menu_state.window.set_visible(true);
                    menu_state
                        .window
                        .set_outer_position(PhysicalPosition::new(popup_x, 32));
                } else {
                    menu_state.window.set_visible(false);
                }
                state.update();
                match state.render(panel_state.primitive(), &mut staging_belt, &debug) {
                    Ok(_) => {}
                    // Recreate the swap_chain if lost
                    Err(wgpu::SwapChainError::Lost) => state.resize(state.size),
                    // The system is out of memory, we should probably quit
                    Err(wgpu::SwapChainError::OutOfMemory) => *control_flow = ControlFlow::Exit,
                    // All other errors (Outdated, Timeout) should be resolved by the next frame
                    Err(e) => eprintln!("{:?}", e),
                }
                match menu_state.render(sound_state.primitive(), &mut staging_belt, &debug) {
                    Ok(_) => {}
                    // Recreate the swap_chain if lost
                    Err(wgpu::SwapChainError::Lost) => menu_state.resize(menu_state.size),
                    // The system is out of memory, we should probably quit
                    Err(wgpu::SwapChainError::OutOfMemory) => *control_flow = ControlFlow::Exit,
                    // All other errors (Outdated, Timeout) should be resolved by the next frame
                    Err(e) => eprintln!("{:?}", e),
                }
                match context_state.render(context_state_app.primitive(), &mut staging_belt, &debug)
                {
                    Ok(_) => {}
                    // Recreate the swap_chain if lost
                    Err(wgpu::SwapChainError::Lost) => menu_state.resize(menu_state.size),
                    // The system is out of memory, we should probably quit
                    Err(wgpu::SwapChainError::OutOfMemory) => *control_flow = ControlFlow::Exit,
                    // All other errors (Outdated, Timeout) should be resolved by the next frame
                    Err(e) => eprintln!("{:?}", e),
                }
            }

            _ => {}
        }
    });
}

pub fn graphics_props() -> (
    PhysicalPosition<f64>,
    Debug,
    wgpu::util::StagingBelt,
    ModifiersState,
) {
    let cursor_position = PhysicalPosition::new(-1.0, -1.0);
    let debug = Debug::new();
    let staging_belt = wgpu::util::StagingBelt::new(10 * 1024);
    // let mut local_pool = futures::executor::LocalPool::new();
    let modifiers = ModifiersState::default();
    (cursor_position, debug, staging_belt, modifiers)
}

pub fn setttings(text_size: u16) -> Settings {
    Settings {
        default_text_size: text_size,
        ..Settings::default()
    }
}

pub fn create_state<T: Program<Renderer = iced_graphics::Renderer<iced_wgpu::Backend>>>(
    program: T,
    state: &mut State,
    debug: &mut Debug,
    cursor_pos: PhysicalPosition<f64>,
) -> program::State<T> {
    program::State::new(
        program,
        state.viewport.logical_size(),
        conversion::cursor_position(cursor_pos, state.viewport.scale_factor()),
        &mut state.render,
        debug,
    )
}
