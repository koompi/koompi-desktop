use super::panel_view::{ViewPort, ViewportDesc};
use crate::controls::Controls;
use futures::task::SpawnExt;
use iced_wgpu::{wgpu, Backend, Renderer, Settings, Viewport};
use iced_winit::futures;
use iced_winit::winit::{
    dpi::{PhysicalPosition, PhysicalSize},
    event::{Event, ModifiersState, WindowEvent},
    event_loop::{ControlFlow, EventLoop},
    window::{Window, WindowId},
};
use iced_winit::{conversion, program, Debug};
use std::collections::HashMap;
pub fn run(event_loop: EventLoop<()>, viewports: Vec<(Window, wgpu::Color)>) {
    let instance = wgpu::Instance::new(wgpu::BackendBit::PRIMARY);
    let cursor_position = PhysicalPosition::new(-1.0, -1.0);
    let modifiers = ModifiersState::default();
    let mut staging_belt = wgpu::util::StagingBelt::new(5 * 1024);
    let mut local_pool = futures::executor::LocalPool::new();
    let viewports: Vec<_> = viewports
        .into_iter()
        .map(|(window, color)| ViewportDesc::new(window, color, &instance))
        .collect();
    let (adapter, (mut device, queue)) = futures::executor::block_on(async {
        let adapter = instance
            .request_adapter(&wgpu::RequestAdapterOptions {
                power_preference: wgpu::PowerPreference::default(),
                // Request an adapter which can render to our surface
                compatible_surface: viewports.first().map(|desc| &desc.surface),
            })
            .await
            .expect("Failed to find an appropriate adapter");

        // Create the logical device and command queue
        let device_adapter = adapter
            .request_device(
                &wgpu::DeviceDescriptor {
                    label: None,
                    features: wgpu::Features::empty(),
                    limits: wgpu::Limits::default(),
                },
                None,
            )
            .await
            .expect("Failed to create device");
        (adapter, (device_adapter))
    });
    let mut debug = Debug::new();
    let controls = Controls::new();
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
    let mut viewports: HashMap<WindowId, ViewPort> = viewports
        .into_iter()
        .map(|desc| (desc.window.id(), desc.build(&adapter, &device)))
        .collect();

    event_loop.run(move |event, _, control_flow| {
        // Have the closure take ownership of the resources.
        // `event_loop.run` never returns, therefore we must do this to ensure
        // the resources are properly cleaned up.
        let _ = (&instance, &adapter);

        *control_flow = ControlFlow::Wait;
        match event {
            Event::WindowEvent { window_id, event } => {
                match event {
                    WindowEvent::Resized(size) => {
                        // Recreate the swap chain with the new size
                        if let Some(viewport) = viewports.get_mut(&window_id) {
                            viewport.resize(&device, size);
                        }
                    }
                    WindowEvent::CloseRequested => {
                        viewports.remove(&window_id);
                        if viewports.is_empty() {
                            *control_flow = ControlFlow::Exit
                        }
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
                    }
                }
            }
            Event::MainEventsCleared => {
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
                    // if !state_sound.is_queue_empty() {
                    //     let _ = state_sound.update(
                    //         view_port.desc.viewport.logical_size(),
                    //         conversion::cursor_position(
                    //             cursor_position,
                    //             view_port.desc.viewport.scale_factor(),
                    //         ),
                    //         None,
                    //         &mut renderer,
                    //         &mut debug,
                    //     );

                    //     view_port.desc.window.request_redraw();
                    // }
                    // if !state_sound.is_queue_empty() {}
                });
            }
            Event::RedrawRequested(window_id) => {
                if let Some(viewport) = viewports.get_mut(&window_id) {
                    // viewport
                    //     .desc
                    //     .window
                    //     .set_inner_size(PhysicalSize::new(1920, 40));
                    let frame = viewport.get_current_frame();
                    let mut encoder = device
                        .create_command_encoder(&wgpu::CommandEncoderDescriptor { label: None });
                    {
                        let _rpass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                            label: None,
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
                    let mouse_interaction = renderer.backend_mut().draw(
                        &mut device,
                        &mut staging_belt,
                        &mut encoder,
                        &frame.view,
                        &viewport.desc.viewport,
                        state.primitive(),
                        &debug.overlay(),
                    );
                    viewport.desc.window.set_cursor_icon(
                        iced_winit::conversion::mouse_interaction(mouse_interaction),
                    );
                    // Then we submit the work
                    staging_belt.finish();
                    // Update the mouse cursor
                    queue.submit(Some(encoder.finish()));
                    local_pool
                        .spawner()
                        .spawn(staging_belt.recall())
                        .expect("Recall staging buffers");
                    local_pool.run_until_stalled();
                }
            }
            _ => {}
        }
    });
}
