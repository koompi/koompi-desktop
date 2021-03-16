mod controls;
// mod iced_panel;
// mod multi_state;
// mod panel_viewport;
// mod panelwin;
mod sound;
mod state;
// mod strut;
// mod styles;

use controls::Controls;
use sound::{ControlType, Sound};
mod window_state;
use std::cell::RefCell;
use std::convert::AsMut;
use window_state::State;
// mod viewport;
use futures::executor::block_on;
use iced_wgpu::wgpu;
use iced_wgpu::Settings;
use iced_winit::{conversion, futures, Debug};
use iced_winit::{program, winit, Program};
use winit::{
    dpi::{PhysicalPosition, PhysicalSize},
    event::{ElementState, Event, KeyboardInput, ModifiersState, VirtualKeyCode, WindowEvent},
    event_loop::{ControlFlow, EventLoop},
    platform::unix::{WindowBuilderExtUnix, XWindowStrut, XWindowType},
    window::WindowBuilder,
};
fn main() {
    env_logger::init();
    let event_loop = EventLoop::new();
    let popup_menu = WindowBuilder::new()
        .with_x11_window_type(vec![XWindowType::Dock])
        .with_inner_size(PhysicalSize::new(400, 400))
        .build(&event_loop)
        .unwrap();
    popup_menu.set_visible(false);
    let window = WindowBuilder::new()
        .with_x11_window_strut(vec![XWindowStrut::Strut([0, 0, 50, 0])])
        .with_x11_window_type(vec![XWindowType::Dock])
        .build(&event_loop)
        .unwrap();
    let mut popup_x = 0;
    if let Some(display) = window.primary_monitor() {
        let width = display.size().width;
        window.set_inner_size(PhysicalSize::new(width, 50));
        popup_x = width - 400;
        popup_menu.set_outer_position(PhysicalPosition::new(popup_x, 50));
    }
    window.set_outer_position(PhysicalPosition::new(0, 0));
    let (mut cursor_position, mut debug, mut staging_belt, mut modifiers) = graphics_props();
    // Since main can't be async, we're going to need to block
    let mut menu_state = block_on(State::new(popup_menu, Some(&setttings(20))));
    let sound = Sound::new();
    let mut state: State = block_on(State::new(window, Some(&setttings(16))));
    let mut sound_state = program::State::new(
        sound,
        menu_state.viewport.logical_size(),
        conversion::cursor_position(cursor_position, menu_state.viewport.scale_factor()),
        &mut menu_state.render,
        &mut debug,
    );
    let panel = Controls::new();
    let mut panel_state = program::State::new(
        panel,
        state.viewport.logical_size(),
        conversion::cursor_position(cursor_position, state.viewport.scale_factor()),
        &mut state.render,
        &mut debug,
    );
    event_loop.run(move |event, _, control_flow| {
        match event {
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
                    WindowEvent::Resized(physical_size) => {
                        state.resize(*physical_size);
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
                if let Some(event) =
                    conversion::window_event(&event, state.viewport.scale_factor(), modifiers)
                {
                    panel_state.queue_event(event);
                }
                state.map_event(&mut panel_state, &modifiers, &event);
                menu_state.map_event(&mut sound_state, &modifiers, &event);
            }
            Event::MainEventsCleared => {
                // RedrawRequested will only trigger once, unless we manually
                // request it.
                state.update_frame(&mut panel_state, cursor_position, &mut debug);
                menu_state.update_frame(&mut sound_state, cursor_position, &mut debug);
            }
            Event::RedrawRequested(_) => {
                let sound::Sound { kind, .. } = sound_state.program();
                let program = panel_state.program();
                if program.is_shwon {
                    kind.replace(program.get_kind());
                    // kind = RefCell::new(ControlType::Sound);
                    menu_state.window.set_visible(true);
                    menu_state
                        .window
                        .set_outer_position(PhysicalPosition::new(popup_x, 50));
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
