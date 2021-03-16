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
use futures::task::SpawnExt;
use sound::Sound;
mod window_state;
use window_state::State;
// mod viewport;
use iced_wgpu::wgpu;
use iced_wgpu::Settings;
use iced_winit::{conversion, futures, Clipboard, Debug};
use iced_winit::{program, winit};
use winit::{
    dpi::{PhysicalPosition, PhysicalSize},
    event::{ElementState, Event, KeyboardInput, ModifiersState, VirtualKeyCode, WindowEvent},
    event_loop::{ControlFlow, EventLoop},
    platform::unix::{WindowBuilderExtUnix, XWindowStrut, XWindowType},
    window::{Window, WindowBuilder},
};
fn main() {
    env_logger::init();
    let event_loop = EventLoop::new();
    let menu = Window::new(&event_loop).unwrap();
    let window = WindowBuilder::new()
        .with_inner_size(PhysicalSize::new(1920, 40))
        .with_x11_window_strut(vec![XWindowStrut::Strut([0, 0, 40, 0])])
        .with_x11_window_type(vec![XWindowType::Dock])
        .build(&event_loop)
        .unwrap();
    window.set_outer_position(PhysicalPosition::new(0, 0));
    let mut cursor_position = PhysicalPosition::new(-1.0, -1.0);
    let mut debug = Debug::new();
    let mut staging_belt = wgpu::util::StagingBelt::new(5 * 1024);
    // let mut local_pool = futures::executor::LocalPool::new();
    let mut modifiers = ModifiersState::default();
    use futures::executor::block_on;
    // let mut clipboard = Clipboard::new(&window);
    // Since main can't be async, we're going to need to block
    let settings = Settings {
        default_text_size: 12,
        ..Settings::default()
    };
    let mut menu_state = block_on(State::new(menu, Some(&settings)));
    let sound = Sound::new();
    let mut state: State = block_on(State::new(window, Some(&settings)));
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
            Event::WindowEvent {
                ref event,
                window_id,
            } => {
                if !state.input(event) {
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
                    if let Some(event) = conversion::window_event(
                        &event,
                        menu_state.viewport.scale_factor(),
                        modifiers,
                    ) {
                        sound_state.queue_event(event);
                    }
                }
            }
            Event::MainEventsCleared => {
                if !panel_state.is_queue_empty() {
                    let _ = panel_state.update(
                        state.viewport.logical_size(),
                        conversion::cursor_position(cursor_position, state.viewport.scale_factor()),
                        None,
                        &mut state.render,
                        &mut debug,
                    );
                    state.window.request_redraw();
                }
                if !sound_state.is_queue_empty() {
                    let _ = sound_state.update(
                        menu_state.viewport.logical_size(),
                        conversion::cursor_position(
                            cursor_position,
                            menu_state.viewport.scale_factor(),
                        ),
                        None,
                        &mut menu_state.render,
                        &mut debug,
                    );
                }
                // RedrawRequested will only trigger once, unless we manually
                // request it.
            }
            Event::RedrawRequested(window_id) => {
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
                // local_pool
                //     .spawner()
                //     .spawn(staging_belt.recall())
                //     .expect("Recall staging buffers");
                // local_pool.run_until_stalled();
            }

            _ => {}
        }
    });
}
