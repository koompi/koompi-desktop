mod desktop;
mod window_viewport;
// mod desktop_item;

use desktop::Desktop;
use iced_wgpu::{wgpu, Backend, Renderer, Settings};
use iced_winit::{conversion, futures, program, winit, Debug};
use window_viewport::ViewportDesc;

use futures::task::SpawnExt;
use winit::{
    dpi::{PhysicalPosition, PhysicalSize, Position},
    event::{Event, ModifiersState, WindowEvent},
    event_loop::{ControlFlow, EventLoop},
    platform::unix::{WindowBuilderExtUnix, XWindowType},
    window::WindowBuilder,
};

fn main() {
    let event_loop = EventLoop::new();
    let instance = wgpu::Instance::new(wgpu::BackendBit::PRIMARY);

    // Template Window
    // let window_clus = |wtype, size, on_top| {
    //    let win_builder = WindowBuilder::new()
    //       .with_inner_size(size)
    //       .with_decorations(false)
    //       .with_resizable(false)
    //       .with_always_on_top(on_top)
    //       .with_x11_window_type(wtype);
    //    win_builder.build(&event_loop).unwrap()
    // };

    let mut cursor_position = PhysicalPosition::new(-1.0, -1.0);
    let mut modifiers = ModifiersState::default();

    // Initialize staging belt and local pool
    let mut staging_belt = wgpu::util::StagingBelt::new(5 * 1024);
    let mut local_pool = futures::executor::LocalPool::new();

    let window = WindowBuilder::new()
        .with_x11_window_type(vec![XWindowType::Desktop])
        .build(&event_loop)
        .unwrap();
    if let Some(monitor) = window.primary_monitor() {
        window.set_inner_size(monitor.size());
        window.set_outer_position(monitor.position());
    }

    let desktop = Desktop::new();
    let viewport_desc = ViewportDesc::new(&instance, window);

    let (adapter, (mut device, queue)) = futures::executor::block_on(async {
        let adapter = instance
            .request_adapter(&wgpu::RequestAdapterOptions {
                power_preference: wgpu::PowerPreference::HighPerformance,
                compatible_surface: Some(&viewport_desc.surface),
            })
            .await
            .expect("Request adapter");

        let dev_queue = adapter
            .request_device(
                &wgpu::DeviceDescriptor {
                    shader_validation: false,
                    features: wgpu::Features::empty(),
                    limits: wgpu::Limits::default(),
                },
                None,
            )
            .await
            .expect("Request device");
        // let format = adapter.get_swap_chain_preferred_format(&surface);

        (adapter, dev_queue)
    });

    let mut debug = Debug::new();
    let mut renderer = Renderer::new(Backend::new(&mut device, Settings::default()));
    let state = program::State::new(
        desktop,
        viewport_desc.viewport.logical_size(),
        conversion::cursor_position(cursor_position, viewport_desc.viewport.scale_factor()),
        &mut renderer,
        &mut debug,
    );
    let mut viewport = viewport_desc.build(&adapter, &device, state);

    event_loop.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::Wait;

        match event {
            Event::WindowEvent { event, .. } => {
                match event {
                    WindowEvent::CloseRequested => *control_flow = ControlFlow::Exit,
                    WindowEvent::CursorMoved { position, .. } => cursor_position = position,
                    WindowEvent::ModifiersChanged(modi) => modifiers = modi,
                    WindowEvent::Resized(new_size) => viewport.resize(&device, new_size),
                    _ => {}
                }

                if let Some(event) = iced_winit::conversion::window_event(
                    &event,
                    viewport.desc.viewport.scale_factor(),
                    modifiers,
                ) {
                    viewport.state.queue_event(event);
                }
            }
            Event::MainEventsCleared => {
                if !viewport.state.is_queue_empty() {
                    let viewport_wgpu = viewport.desc.viewport.clone();
                    // We update iced
                    let _ = viewport.state.update(
                        viewport_wgpu.logical_size(),
                        conversion::cursor_position(cursor_position, viewport_wgpu.scale_factor()),
                        None,
                        &mut renderer,
                        &mut debug,
                    );

                    viewport.desc.window.request_redraw();
                    // panel.request_redraw();
                    // dock.request_redraw();
                }
            }
            Event::RedrawRequested(_) => {
                let frame = viewport.get_current_frame();
                let mut encoder =
                    device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: None });
                let program = viewport.state.program();

                {
                    let _rpass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                        color_attachments: &[wgpu::RenderPassColorAttachmentDescriptor {
                            attachment: &frame.view,
                            resolve_target: None,
                            ops: wgpu::Operations {
                                load: wgpu::LoadOp::Clear({
                                    let [r, g, b, a] = program.background_color().into_linear();

                                    wgpu::Color {
                                        r: r as f64,
                                        g: g as f64,
                                        b: b as f64,
                                        a: a as f64,
                                    }
                                }),
                                store: true,
                            },
                        }],
                        depth_stencil_attachment: None,
                    });
                }

                let mouse_interaction = renderer.backend_mut().draw(
                    &mut device,
                    &mut staging_belt,
                    &mut encoder,
                    &frame.view,
                    &viewport.desc.viewport,
                    viewport.state.primitive(),
                    &debug.overlay(),
                );
                // Update the mouse cursor
                viewport
                    .desc
                    .window
                    .set_cursor_icon(iced_winit::conversion::mouse_interaction(mouse_interaction));
                staging_belt.finish();
                queue.submit(Some(encoder.finish()));

                // And recall staging buffers
                local_pool
                    .spawner()
                    .spawn(staging_belt.recall())
                    .expect("Recall staging buffers");
                local_pool.run_until_stalled();
            }
            _ => (),
        }
    });
}
