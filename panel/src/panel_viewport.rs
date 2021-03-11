use super::controls::Controls;
use iced_wgpu::{wgpu, Backend, Renderer, Settings, Viewport};
use iced_winit::{
    conversion, futures, futures::task::SpawnExt, program, winit, Clipboard, Debug, Program, Size,
};
use std::collections::HashMap;
use winit::{
    dpi::{PhysicalPosition, PhysicalSize},
    event::{Event, ModifiersState, WindowEvent},
    event_loop::{ControlFlow, EventLoop},
    platform::unix::{WindowBuilderExtUnix, XWindowStrut, XWindowType},
    window::{Window, WindowBuilder, WindowId},
};

struct ViewportDesc {
    window: Window,
    background: wgpu::Color,
    surface: wgpu::Surface,
    viewport: Viewport,
}

struct PanelViewport {
    desc: ViewportDesc,
    sc_desc: wgpu::SwapChainDescriptor,
    swap_chain: wgpu::SwapChain,
}

impl ViewportDesc {
    fn new(window: Window, background: wgpu::Color, instance: &wgpu::Instance) -> Self {
        let surface = unsafe { instance.create_surface(&window) };
        let size = window.inner_size();
        let viewport =
            Viewport::with_physical_size(Size::new(size.width, size.height), window.scale_factor());
        Self {
            window,
            background,
            surface,
            viewport,
        }
    }

    fn build(self, _adapter: &wgpu::Adapter, device: &wgpu::Device) -> PanelViewport {
        let size = self.window.inner_size();

        let sc_desc = wgpu::SwapChainDescriptor {
            usage: wgpu::TextureUsage::OUTPUT_ATTACHMENT,
            format: wgpu::TextureFormat::Bgra8UnormSrgb,
            width: size.width,
            height: size.height,
            present_mode: wgpu::PresentMode::Fifo,
        };

        let swap_chain = device.create_swap_chain(&self.surface, &sc_desc);

        PanelViewport {
            desc: self,
            sc_desc,
            swap_chain,
        }
    }
}

impl PanelViewport {
    fn resize(&mut self, device: &wgpu::Device, size: winit::dpi::PhysicalSize<u32>) {
        self.sc_desc.width = size.width;
        self.sc_desc.height = size.height;
        self.swap_chain = device.create_swap_chain(&self.desc.surface, &self.sc_desc);
    }
    fn get_current_frame(&mut self) -> wgpu::SwapChainTexture {
        self.swap_chain
            .get_current_frame()
            .expect("Failed to acquire next swap chain texture")
            .output
    }
}
pub fn run(event_loop: EventLoop<()>, viewports: Vec<(Window, wgpu::Color)>) {
    let instance = wgpu::Instance::new(wgpu::BackendBit::PRIMARY);
    let viewports: Vec<_> = viewports
        .into_iter()
        .map(|(window, color)| ViewportDesc::new(window, color, &instance))
        .collect();
    let key = viewports.get(0).unwrap().window.id();
    let mut cursor_position = PhysicalPosition::new(-1.0, -1.0);
    let mut modifiers = ModifiersState::default();
    let mut staging_belt = wgpu::util::StagingBelt::new(5 * 1024);
    let mut local_pool = futures::executor::LocalPool::new();
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
        let device_queue = adapter
            .request_device(
                &wgpu::DeviceDescriptor {
                    shader_validation: false,
                    features: wgpu::Features::empty(),
                    limits: wgpu::Limits::default(),
                },
                None,
            )
            .await
            .expect("Failed to create device");
        (adapter, device_queue)
    });
    let mut viewports: HashMap<WindowId, PanelViewport> = viewports
        .into_iter()
        .map(|desc| (desc.window.id(), desc.build(&adapter, &device)))
        .collect();
    let panel = Controls::new();
    let mut debug = Debug::new();
    let mut renderer = Renderer::new(Backend::new(&mut device, Settings::default()));
    let view_port = &viewports.get(&key).unwrap().desc.viewport;
    let mut state = program::State::new(
        panel,
        view_port.logical_size(),
        conversion::cursor_position(cursor_position, view_port.scale_factor()),
        &mut renderer,
        &mut debug,
    );
    event_loop.run(move |event, _, control_flow| {
        // Have the closure take ownership of the resources.
        // `event_loop.run` never returns, therefore we must do this to ensure
        // the resources are properly cleaned up.
        let _ = (&instance, &adapter);

        *control_flow = ControlFlow::Wait;
        match event {
            Event::WindowEvent {
                window_id, event, ..
            } => {
                match event {
                    WindowEvent::CloseRequested => {
                        viewports.remove(&window_id);
                        if viewports.is_empty() {
                            *control_flow = ControlFlow::Exit
                        }
                    }
                    WindowEvent::CursorMoved { position, .. } => cursor_position = position,
                    WindowEvent::ModifiersChanged(modi) => modifiers = modi,
                    WindowEvent::Resized(size) => {
                        // Recreate the swap chain with the new size
                        if let Some(viewport) = viewports.get_mut(&window_id) {
                            viewport.resize(&device, size);
                        }
                    }
                    _ => {}
                }
                if let Some(viewport) = viewports.get_mut(&window_id) {
                    if let Some(event) = iced_winit::conversion::window_event(
                        &event,
                        viewport.desc.viewport.scale_factor(),
                        modifiers,
                    ) {
                        state.queue_event(event);
                    }
                }
            }
            Event::MainEventsCleared => {
                viewports.iter_mut().for_each(|(_window_id, viewport)| {
                    if state.is_queue_empty() {
                        let viewport_wgpu = viewport.desc.viewport.clone();
                        // We update iced
                        let _ = state.update(
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
                    let mouse_interaction = renderer.backend_mut().draw(
                        &mut device,
                        &mut staging_belt,
                        &mut encoder,
                        &frame.view,
                        &viewport.desc.viewport,
                        state.primitive(),
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
            _ => {}
        }
    });
}

pub fn init_ui() {
    let event_loop = EventLoop::new();
    let mut viewports = Vec::with_capacity(2);
    let main_window = WindowBuilder::new()
        .with_x11_window_type(vec![XWindowType::Dock])
        .with_x11_window_strut(vec![XWindowStrut::Strut([0, 0, 40, 0])])
        .build(&event_loop)
        .unwrap();
    if let Some(monitor) = main_window.primary_monitor() {
        main_window.set_inner_size(PhysicalSize::new(monitor.size().width, 32));
        main_window.set_outer_position(PhysicalPosition::new(0, 0));
    }
    let menu = WindowBuilder::new()
        .with_x11_window_type(vec![XWindowType::Menu])
        .build(&event_loop)
        .unwrap();
    viewports.push((
        main_window,
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
    // wgpu_subscriber::initialize_default_subscriber(None);
    run(event_loop, viewports);
}
