use super::controls::Controls;
use futures::task::SpawnExt;
use iced_wgpu::Viewport;
use iced_wgpu::{wgpu, Backend, Renderer, Settings};
use iced_winit::{conversion, futures, program, winit, Debug};
use iced_winit::{Program, Size};
use std::collections::HashMap;
use winit::{
    dpi::PhysicalPosition,
    event::{Event, ModifiersState, WindowEvent},
    event_loop::{ControlFlow, EventLoop},
    platform::unix::{WindowBuilderExtUnix, XWindowType},
    window::WindowBuilder,
};
use winit::{dpi::PhysicalSize, window::Window};
pub struct ViewportDesc {
    pub window: Window,
    pub surface: wgpu::Surface,
    pub viewport: Viewport,
}

pub struct WindowViewport<P: 'static + Program> {
    pub desc: ViewportDesc,
    pub sc_desc: wgpu::SwapChainDescriptor,
    pub swap_chain: wgpu::SwapChain,
    pub state: program::State<P>,
}

impl ViewportDesc {
    pub fn new(instance: &wgpu::Instance, window: Window) -> Self {
        let surface = unsafe { instance.create_surface(&window) };
        let size = window.inner_size();
        let viewport =
            Viewport::with_physical_size(Size::new(size.width, size.height), window.scale_factor());

        Self {
            window,
            surface,
            viewport,
        }
    }

    pub fn build<P: 'static + Program>(
        self,
        _adapter: &wgpu::Adapter,
        device: &wgpu::Device,
        state: program::State<P>,
    ) -> WindowViewport<P> {
        let size = self.window.inner_size();

        let sc_desc = wgpu::SwapChainDescriptor {
            usage: wgpu::TextureUsage::RENDER_ATTACHMENT,
            format: wgpu::TextureFormat::Bgra8UnormSrgb,
            width: size.width,
            height: size.height,
            present_mode: wgpu::PresentMode::Mailbox,
        };

        let swap_chain = device.create_swap_chain(&self.surface, &sc_desc);

        WindowViewport {
            desc: self,
            sc_desc,
            swap_chain,
            state,
        }
    }
}

impl<P> WindowViewport<P>
where
    P: 'static + Program,
{
    pub fn resize(&mut self, device: &wgpu::Device, size: PhysicalSize<u32>) {
        self.sc_desc.width = size.width;
        self.sc_desc.height = size.height;
        self.swap_chain = device.create_swap_chain(&self.desc.surface, &self.sc_desc);
    }
    pub fn get_current_frame(&mut self) -> wgpu::SwapChainTexture {
        self.swap_chain
            .get_current_frame()
            .expect("Failed to acquire next swap chain texture")
            .output
    }
}

pub fn run() {
    let event_loop = EventLoop::new();
    let instance = wgpu::Instance::new(wgpu::BackendBit::PRIMARY);
    let mut viewports = HashMap::new();

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
    let desktop = Controls::new();
    let mut debug = Debug::new();
    let mut renderer = Renderer::new(Backend::new(&mut device, Settings::default()));
    let state = program::State::new(
        desktop,
        viewport_desc.viewport.logical_size(),
        conversion::cursor_position(cursor_position, viewport_desc.viewport.scale_factor()),
        &mut renderer,
        &mut debug,
    );
    viewports.insert(
        viewport_desc.window.id(),
        viewport_desc.build(&adapter, &device, state),
    );

    event_loop.run(move |event, _, control_flow| {
        let _ = (&instance, &adapter);

        *control_flow = ControlFlow::Wait;
        match event {
            Event::WindowEvent { event, window_id } => {
                match event {
                    WindowEvent::CloseRequested => {
                        viewports.remove(&window_id);

                        if viewports.is_empty() {
                            *control_flow = ControlFlow::Exit;
                        }
                    }
                    WindowEvent::CursorMoved { position, .. } => cursor_position = position,
                    WindowEvent::ModifiersChanged(modi) => modifiers = modi,
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
            }
            Event::MainEventsCleared => {
                viewports.iter_mut().for_each(|(window_id, viewport)| {
                    if !viewport.state.is_queue_empty() {
                        let viewport_wgpu = viewport.desc.viewport.clone();
                        // We update iced
                        let _ = viewport.state.update(
                            viewport_wgpu.logical_size(),
                            conversion::cursor_position(
                                cursor_position,
                                viewport_wgpu.scale_factor(),
                            ),
                            None,
                            &mut renderer,
                            &mut debug,
                        );

                        viewport.desc.window.request_redraw();
                    }
                });
            }
            Event::RedrawRequested(window_id) => {
                if let Some(viewport) = viewports.get_mut(&window_id) {
                    let frame = viewport.get_current_frame();
                    let mut encoder = device
                        .create_command_encoder(&wgpu::CommandEncoderDescriptor { label: None });
                    let program = viewport.state.program();

                    {
                        let _rpass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                            label: None,
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
                    viewport.desc.window.set_cursor_icon(
                        iced_winit::conversion::mouse_interaction(mouse_interaction),
                    );
                    staging_belt.finish();
                    queue.submit(Some(encoder.finish()));
                }

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
