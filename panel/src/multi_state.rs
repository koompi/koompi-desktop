use super::controls::Controls;
use super::panel_viewport::{PanelViewport, ViewportDesc};
use super::sound::Sound;
use super::state::{Common, MultiState};
use super::strut::{StrutArea, StrutPartialArea};
use crate::state::CommonState;
use futures::task::SpawnExt;
use iced_wgpu::{wgpu, Backend, Renderer, Settings, Viewport};
use iced_winit::{conversion, futures, program, winit, Debug, Program, Size};
use std::collections::HashMap;
use winit::{
    dpi::{PhysicalPosition, PhysicalSize},
    event::{Event, ModifiersState, WindowEvent},
    event_loop::{ControlFlow, EventLoop},
    platform::unix::{WindowBuilderExtUnix, XWindowStrut, XWindowType},
    window::WindowId,
};

pub fn run() {
    env_logger::init();

    // Initialize winit
    let event_loop = EventLoop::new();
    let instance = wgpu::Instance::new(wgpu::BackendBit::PRIMARY);
    // let monitor_handle = MonitorHandle { inner:  };
    let mut strut_area = StrutArea::new();
    strut_area.set_top(32);
    let mut strut_partial = StrutPartialArea::new();
    strut_partial.set_top(32);
    let window = winit::window::WindowBuilder::new()
        // .with_inner_size(PhysicalSize::new(1920, 30))
        // .with_fullscreen(Some(Fullscreen::Borderless(Some(monitor_handle))))
        .with_decorations(false)
        .with_x11_window_type(vec![XWindowType::Dock])
        .with_x11_window_strut(vec![
            XWindowStrut::Strut(strut_area.list_props()),
            XWindowStrut::StrutPartial([0, 0, 32, 0, 0, 0, 0, 0, 0, 1920, 0, 0]),
        ])
        .build(&event_loop)
        .unwrap();
    match window.primary_monitor() {
        Some(monitor) => window.set_inner_size(PhysicalSize::new(monitor.size().width, 32)),
        None => {}
    }
    let menu = winit::window::WindowBuilder::new()
        .with_decorations(false)
        .with_inner_size(PhysicalSize::new(400, 500))
        .with_x11_window_type(vec![XWindowType::Menu])
        .build(&event_loop)
        .unwrap();
    // menu.set_outer_position(PhysicalPosition::new(33, 1000));
    // menu.set_visible(true);
    let key = menu.id();
    // let mut hash_win = HashMap::new();
    window.set_outer_position(PhysicalPosition::new(0, 0));
    let physical_size = window.inner_size();
    let viewport = Viewport::with_physical_size(
        Size::new(physical_size.width, physical_size.height),
        window.scale_factor(),
    );
    let mut viewports = Vec::with_capacity(2);
    viewports.push((
        window,
        wgpu::Color {
            r: 255.0,
            g: 255.0,
            b: 255.0,
            a: 1.0,
        },
    ));
    viewports.push((
        menu,
        wgpu::Color {
            r: 255.0,
            g: 255.0,
            b: 255.0,
            a: 1.0,
        },
    ));
    let viewports: Vec<_> = viewports
        .into_iter()
        .map(|(window, color)| ViewportDesc::new(window, color, &instance))
        .collect();
    let mut cursor_position = PhysicalPosition::new(-1.0, -1.0);
    let mut modifiers = ModifiersState::default();
    // Initialize wgpucontrols
    // let surface = unsafe { instance.create_surface(&window) };
    let (adapter, (mut device, queue)) = futures::executor::block_on(async {
        let adapter = instance
            .request_adapter(&wgpu::RequestAdapterOptions {
                power_preference: wgpu::PowerPreference::Default,
                compatible_surface: viewports.first().map(|desc| &desc.surface),
            })
            .await
            .expect("Request adapter");

        let device_queue = adapter
            .request_device(
                &wgpu::DeviceDescriptor {
                    features: wgpu::Features::empty(),
                    limits: wgpu::Limits::default(),
                    shader_validation: false,
                },
                None,
            )
            .await
            .expect("Request device");
        (adapter, device_queue)
    });
    // Initialize iced
    // Initialize scene and GUI controls
    // let scene = Scene::new(&mut device);
    let controls = Controls::new();
    let sound = Sound::new();
    let mut debug = Debug::new();
    let mut renderer = Renderer::new(Backend::new(&mut device, Settings::default()));

    let mut state = program::State::new(
        controls,
        viewports
            .first()
            .map(|desc| &desc.viewport)
            .unwrap()
            .logical_size(),
        conversion::cursor_position(
            cursor_position,
            viewports
                .first()
                .map(|desc| &desc.viewport)
                .unwrap()
                .scale_factor(),
        ),
        &mut renderer,
        &mut debug,
    );
    let mut state_sound = program::State::new(
        sound,
        viewports
            .last()
            .map(|des| &des.viewport)
            .unwrap()
            .logical_size(),
        conversion::cursor_position(
            cursor_position,
            viewports
                .last()
                .map(|des| &des.viewport)
                .unwrap()
                .scale_factor(),
        ),
        &mut renderer,
        &mut debug,
    );

    let mut viewports: HashMap<WindowId, PanelViewport> = viewports
        .into_iter()
        .map(|desc| (desc.window.id(), desc.build(&adapter, &device)))
        .collect();
    // let mut swap_chain = {
    //     let size = window.firstinner_size();

    //     device.create_swap_chain(
    //         &viewports.surface,
    //         &wgpu::SwapChainDescriptor {
    //             usage: wgpu::TextureUsage::OUTPUT_ATTACHMENT,
    //             format: format,
    //             width: size.width,
    //             height: size.height,
    //             present_mode: wgpu::PresentMode::Mailbox,
    //         },
    //     )
    // };
    let mut resized = false;

    // Initialize staging belt and local pool
    let mut staging_belt = wgpu::util::StagingBelt::new(5 * 1024);
    let mut local_pool = futures::executor::LocalPool::new();

    // hash_win.insert(window.id(), window);
    // Run event loop
    let mut counter: usize = 0;
    event_loop.run(move |event, _loop_event, control_flow| {
        // You should change this if you want to render continuosly
        *control_flow = ControlFlow::Wait;
        match event {
            Event::WindowEvent { window_id, event } => {
                match event {
                    WindowEvent::CursorMoved { position, .. } => {
                        cursor_position = position;
                    }
                    WindowEvent::ModifiersChanged(new_modifiers) => {
                        modifiers = new_modifiers;
                    }
                    WindowEvent::Resized(new_size) => {
                        if let Some(view_port) = viewports.get_mut(&window_id) {
                            view_port.desc.viewport = Viewport::with_physical_size(
                                Size::new(new_size.width, new_size.height),
                                view_port.desc.window.scale_factor(),
                            );
                        }

                        resized = true;
                    }
                    WindowEvent::CloseRequested => {
                        *control_flow = ControlFlow::Exit;
                    }
                    _ => {}
                }
                if let Some(view_port) = viewports.get_mut(&window_id) {
                    // Map window event to iced event
                    if let Some(event) = iced_winit::conversion::window_event(
                        &event,
                        view_port.desc.window.scale_factor(),
                        modifiers,
                    ) {
                        let clone_event = event.clone();
                        state.queue_event(clone_event);
                        state_sound.queue_event(event);
                    }
                }
            }
            Event::MainEventsCleared => {
                // If there are events pending
                viewports.iter_mut().for_each(|(&window_id, view_port)| {
                    if !state.is_queue_empty() {
                        // We update iced
                        let _ = state.update(
                            view_port.desc.viewport.logical_size(),
                            conversion::cursor_position(
                                cursor_position,
                                view_port.desc.viewport.scale_factor(),
                            ),
                            None,
                            &mut renderer,
                            &mut debug,
                        );
                        // view_port.desc.window.request_redraw();
                        // and request a redraw
                        view_port.desc.window.request_redraw();
                    }
                    if !state_sound.is_queue_empty() {
                        let _ = state_sound.update(
                            view_port.desc.viewport.logical_size(),
                            conversion::cursor_position(
                                cursor_position,
                                view_port.desc.viewport.scale_factor(),
                            ),
                            None,
                            &mut renderer,
                            &mut debug,
                        );

                        view_port.desc.window.request_redraw();
                    }
                    // if !state_sound.is_queue_empty() {}
                });
            }
            Event::RedrawRequested(window_id) => {
                counter += 1;
                let program = state.program();
                if let Some(menu_window) = viewports.get_mut(&key) {
                    if program.is_shown() {
                        menu_window.desc.window.set_visible(true);
                        menu_window
                            .desc
                            .window
                            .set_outer_position(PhysicalPosition::new(1520, 40));
                    } else {
                        menu_window.desc.window.set_visible(false);
                    }
                }
                if let Some(viewport) = viewports.get_mut(&window_id) {
                    if program.is_quit() {
                        *control_flow = ControlFlow::Exit;
                    } else {
                        {}
                    }
                    let frame = viewport.get_current_frame();
                    let mut encoder = device
                        .create_command_encoder(&wgpu::CommandEncoderDescriptor { label: None });
                    {
                        let _rpass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                            color_attachments: &[wgpu::RenderPassColorAttachmentDescriptor {
                                attachment: &frame.view,
                                resolve_target: None,
                                ops: wgpu::Operations {
                                    load: wgpu::LoadOp::Clear(viewport.desc.background),
                                    store: true,
                                },
                            }],
                            depth_stencil_attachment: None,
                        });
                    }
                    if window_id == key {
                        let mouse_interaction = renderer.backend_mut().draw(
                            &mut device,
                            &mut staging_belt,
                            &mut encoder,
                            &frame.view,
                            &viewport.desc.viewport,
                            state_sound.primitive(),
                            &debug.overlay(),
                        );
                        // Then we submit the work
                        staging_belt.finish();
                        queue.submit(Some(encoder.finish()));
                        // Update the mouse cursor
                        viewport.desc.window.set_cursor_icon(
                            iced_winit::conversion::mouse_interaction(mouse_interaction),
                        );
                    } else {
                        let mouse_interaction = renderer.backend_mut().draw(
                            &mut device,
                            &mut staging_belt,
                            &mut encoder,
                            &frame.view,
                            &viewport.desc.viewport,
                            state.primitive(),
                            &debug.overlay(),
                        );
                        // Then we submit the work
                        staging_belt.finish();
                        queue.submit(Some(encoder.finish()));
                        // Update the mouse cursor
                        viewport.desc.window.set_cursor_icon(
                            iced_winit::conversion::mouse_interaction(mouse_interaction),
                        );
                    }
                }
                // And recall staging buffers
                local_pool
                    .spawner()
                    .spawn(staging_belt.recall())
                    .expect("Recall staging buffers");

                local_pool.run_until_stalled();
            }
            _ => {}
        }
        println!("counter: {}", counter);
    })
}
