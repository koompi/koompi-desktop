mod window_viewport;
mod background;
mod desktop_item;
mod constants;
mod desktop_manager;
mod styles;
mod configs;
mod errors;
mod gui;

use gui::{Desktop, ContextMenu};
use window_viewport::ViewportDesc;

use std::collections::HashMap;
use iced_wgpu::{wgpu, Backend, Renderer, Settings};
use iced_winit::{conversion, futures, program, winit, Debug, Clipboard};
use futures::task::SpawnExt;
use winit::{
    dpi::{PhysicalPosition, PhysicalSize},
    event::{Event, ModifiersState, WindowEvent, MouseButton},
    event_loop::{ControlFlow, EventLoop},
    platform::unix::{WindowBuilderExtUnix, XWindowType},
    window::WindowBuilder,
};

fn main() {
    let event_loop = EventLoop::new();
    let instance = wgpu::Instance::new(wgpu::BackendBit::PRIMARY);
    let mut viewports = HashMap::new();

    let window = WindowBuilder::new()
        .with_inner_size(PhysicalSize::new(1920, 1080))
        .with_x11_window_type(vec![XWindowType::Desktop])
        .build(&event_loop)
        .unwrap();
    if let Some(monitor) = window.primary_monitor() {
        // !Problem scaled screen
        // window.set_inner_size(monitor.size());
        window.set_outer_position(monitor.position());
    }

    let mut cursor_position = PhysicalPosition::new(-1.0, -1.0);
    let mut modifiers = ModifiersState::default();
    let mut clipboard = Clipboard::connect(&window);

    match Desktop::new(window.inner_size().height) {
        Ok(desktop) => {
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
                            label: None,
                            features: wgpu::Features::empty(),
                            limits: wgpu::Limits::default(),
                        },
                        None,
                    )
                    .await
                    .expect("Request device");

                (adapter, dev_queue)
            });

            let mut debug = Debug::new();
            let mut renderer = Renderer::new(Backend::new(&mut device, Settings {
                default_text_size: 13,
                ..Settings::default()
            }));
            let state = program::State::new(
                desktop,
                viewport_desc.viewport.logical_size(),
                conversion::cursor_position(cursor_position, viewport_desc.viewport.scale_factor()),
                &mut renderer,
                &mut debug,
            );
            let mut desktop_view = viewport_desc.build(&adapter, &device, state);
            // viewports.insert(viewport_desc.window.id(), );

            // Initialize staging belt and local pool
            let mut staging_belt = wgpu::util::StagingBelt::new(5 * 1024);
            let mut local_pool = futures::executor::LocalPool::new();
            
            event_loop.run(move |event, event_loop, control_flow| {
                *control_flow = ControlFlow::Wait;

                match event {
                    Event::WindowEvent { event, window_id } => {
                        match event {
                            WindowEvent::CloseRequested => {
                                viewports.remove(&window_id);

                                if viewports.is_empty() {
                                    *control_flow = ControlFlow::Exit;
                                }
                            },
                            WindowEvent::CursorMoved { position, .. } => cursor_position = position,
                            WindowEvent::ModifiersChanged(modi) => modifiers = modi,
                            WindowEvent::Resized(new_size) => desktop_view.resize(&device, new_size),
                            WindowEvent::MouseInput {
                                button: MouseButton::Right,
                                ..
                            } => {
                                let context_menu_window = WindowBuilder::new()
                                    .with_decorations(false)
                                    .with_resizable(false)
                                    .with_inner_size(PhysicalSize::new(300, 500))
                                    .with_x11_window_type(vec![XWindowType::PopupMenu])
                                    .build(&event_loop).unwrap();
                                // if let Some(monitor) = context_menu_window.primary_monitor() {
                                    context_menu_window.set_outer_position(cursor_position);
                                // }
                                let context_menu = ContextMenu::new();
                                let context_desc = ViewportDesc::new(&instance, context_menu_window);

                                let menu_state = program::State::new(
                                    context_menu,
                                    context_desc.viewport.logical_size(),
                                    conversion::cursor_position(cursor_position, context_desc.viewport.scale_factor()),
                                    &mut renderer,
                                    &mut debug,
                                );
                                viewports.insert(context_desc.window.id(), context_desc.build(&adapter, &device, menu_state));
                            }
                            _ => {}
                        }

                        if let Some(viewport) = viewports.get_mut(&window_id) {
                            if let Some(event) = iced_winit::conversion::window_event(
                                &event,
                                viewport.desc.viewport.scale_factor(),
                                modifiers,
                            ) {
                                viewport.state.queue_event(event);
                            }
                        }
                        
                        if let Some(event) = iced_winit::conversion::window_event(
                            &event,
                            desktop_view.desc.viewport.scale_factor(),
                            modifiers,
                        ) {
                            desktop_view.state.queue_event(event);
                        }
                    }
                    Event::MainEventsCleared => {
                        viewports.iter_mut().for_each(|(_, viewport)| {
                            if !viewport.state.is_queue_empty() {
                                let viewport_wgpu = viewport.desc.viewport.clone();
                                // We update iced
                                let _ = viewport.state.update(
                                    viewport_wgpu.logical_size(),
                                    conversion::cursor_position(cursor_position, viewport_wgpu.scale_factor()),
                                    &mut renderer,
                                    &mut clipboard,
                                    &mut debug,
                                );

                                viewport.desc.window.request_redraw();
                            }
                        });

                        if !desktop_view.state.is_queue_empty() {
                            let viewport_wgpu = desktop_view.desc.viewport.clone();
                            // We update iced
                            let _ = desktop_view.state.update(
                                viewport_wgpu.logical_size(),
                                conversion::cursor_position(cursor_position, viewport_wgpu.scale_factor()),
                                &mut renderer,
                                &mut clipboard,
                                &mut debug,
                            );

                            desktop_view.desc.window.request_redraw();
                        }
                    }
                    Event::RedrawRequested(window_id) => {
                        let mut encoder =
                            device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: None });
                        let (frame, viewport, primitive, window) = if let Some(viewport) = viewports.get_mut(&window_id) {
                            let frame = viewport.get_current_frame();
                            let primitive = viewport.state.primitive();
                            (frame, &viewport.desc.viewport, primitive, &viewport.desc.window)
                        } else {
                            let frame = desktop_view.get_current_frame();
                            let primitive = desktop_view.state.primitive();
                            (frame, &desktop_view.desc.viewport, primitive, &desktop_view.desc.window)
                        };

                        let _ = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                            label: None,
                            color_attachments: &[
                                wgpu::RenderPassColorAttachmentDescriptor {
                                    attachment: &frame.view,
                                    resolve_target: None,
                                    ops: wgpu::Operations {
                                        load: wgpu::LoadOp::default(),
                                        store: true,
                                    },
                                },
                            ],
                            depth_stencil_attachment: None,
                        });

                        let mouse_interaction = renderer.backend_mut().draw(
                            &mut device,
                            &mut staging_belt,
                            &mut encoder,
                            &frame.view,
                            &viewport,
                            primitive,
                            &debug.overlay(),
                        );

                            // Update the mouse cursor
                        window.set_cursor_icon(iced_winit::conversion::mouse_interaction(mouse_interaction));

                        staging_belt.finish();
                        queue.submit(vec!(encoder.finish()));
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
        },
        Err(err) => eprintln!("{:?}", err)
    }
}
