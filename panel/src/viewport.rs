use super::controls::Controls;
use iced_wgpu::wgpu;
use iced_wgpu::{Backend, Renderer, Settings, Viewport};
use iced_winit::winit::{
    event::{Event, WindowEvent},
    event_loop::{ControlFlow, EventLoop},
    platform::unix::{WindowBuilderExtUnix, XWindowType},
    window::{Window, WindowId},
};
use std::collections::HashMap;
const WINDOW_SIZE: u32 = 128;
const WINDOW_PADDING: u32 = 16;
const WINDOW_TITLEBAR: u32 = 32;
const WINDOW_OFFSET: u32 = WINDOW_SIZE + WINDOW_PADDING;
const ROWS: u32 = 4;
const COLUMNS: u32 = 4;

pub struct ViewportDesc {
    window: Window,
    background: iced_wgpu::wgpu::Color,
    surface: iced_wgpu::wgpu::Surface,
}

pub struct ViewportPanel {
    desc: ViewportDesc,
    sc_desc: wgpu::SwapChainDescriptor,
    swap_chain: wgpu::SwapChain,
}

impl ViewportDesc {
    fn new(window: Window, background: wgpu::Color, instance: &iced_wgpu::wgpu::Instance) -> Self {
        let surface = unsafe { instance.create_surface(&window) };
        Self {
            window,
            background,
            surface,
        }
    }

    fn build(self, adapter: &wgpu::Adapter, device: &wgpu::Device) -> ViewportPanel {
        let size = self.window.inner_size();
        let format = wgpu::TextureFormat::Bgra8UnormSrgb;
        let sc_desc = wgpu::SwapChainDescriptor {
            usage: wgpu::TextureUsage::OUTPUT_ATTACHMENT,
            format: format,
            width: size.width,
            height: size.height,
            present_mode: wgpu::PresentMode::Fifo,
        };
        let swap_chain = device.create_swap_chain(&self.surface, &sc_desc);
        ViewportPanel {
            desc: self,
            sc_desc,
            swap_chain,
        }
    }
}
impl ViewportPanel {
    fn resize(&mut self, device: &wgpu::Device, size: iced_winit::winit::dpi::PhysicalSize<u32>) {
        self.sc_desc.width = size.width;
        self.sc_desc.height = size.height;
        self.swap_chain = device.create_swap_chain(&self.desc.surface, &self.sc_desc);
    }
    fn get_current_frame(&mut self) -> wgpu::SwapChainTexture {
        self.swap_chain
            .get_current_frame()
            .expect("Failed to acqured next swap chain texture")
            .output
    }
}

async fn run(event_loop: EventLoop<()>, viewports: Vec<(Window, wgpu::Color)>) {
    let instance = wgpu::Instance::new(wgpu::BackendBit::PRIMARY);
    let viewports: Vec<_> = viewports
        .into_iter()
        .map(|(window, color)| ViewportDesc::new(window, color, &instance))
        .collect();
    let adapter = instance
        .request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::default(),
            // Request an adapter which can render to our surface
            compatible_surface: viewports.first().map(|desc| &desc.surface),
        })
        .await
        .expect("Failed to find an appropriate adapter");

    // Create the logical device and command queue
    let (device, queue) = adapter
        .request_device(
            &wgpu::DeviceDescriptor {
                features: wgpu::Features::empty(),
                limits: wgpu::Limits::default(),
                shader_validation: false,
            },
            None,
        )
        .await
        .expect("Failed to create device");
    let mut viewports: HashMap<WindowId, ViewportPanel> = viewports
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
            Event::WindowEvent {
                window_id,
                event: WindowEvent::Resized(size),
                ..
            } => {
                // Recreate the swap chain with the new size
                if let Some(viewport) = viewports.get_mut(&window_id) {
                    viewport.resize(&device, size);
                }
            }
            Event::MainEventsCleared => {}
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

                    queue.submit(Some(encoder.finish()));
                }
            }
            Event::WindowEvent {
                window_id,
                event: WindowEvent::CloseRequested,
                ..
            } => {
                viewports.remove(&window_id);
                if viewports.is_empty() {
                    *control_flow = ControlFlow::Exit
                }
            }
            _ => {}
        }
    });
}
use iced_winit::futures;
use iced_winit::winit::dpi::PhysicalPosition;
pub fn init_ui() {
    let event_loop = EventLoop::new();
    let mut viewports = Vec::with_capacity(4);
    // for col in 0..COLUMNS {
    let window = iced_winit::winit::window::WindowBuilder::new()
        .with_x11_window_type(vec![XWindowType::PopupMenu, XWindowType::Menu])
        .build(&event_loop)
        .unwrap();
    window.set_outer_position(PhysicalPosition::new(0, 100));

    viewports.push((
        window,
        wgpu::Color {
            r: 255.0,
            g: 255.0,
            b: 255.0,
            a: 0.2,
        },
    ));
    // }
    futures::executor::block_on(async {
        run(event_loop, viewports).await;
    })
}
