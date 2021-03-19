use iced_wgpu::{wgpu, Viewport, Primitive, Renderer, Backend, Settings};
use iced_winit::{winit, conversion, mouse, Size, Color};
use wgpu::util::StagingBelt;
use winit::{
    window::Window,
    event::WindowEvent,
    dpi::PhysicalSize,
};

pub struct WindowState {
    pub window: Window,
    pub surface: wgpu::Surface,
    pub device: wgpu::Device,
    pub queue: wgpu::Queue,
    pub sc_desc: wgpu::SwapChainDescriptor,
    pub swap_chain: wgpu::SwapChain,
    pub viewport: Viewport,
    pub renderer: Renderer,
}

impl WindowState {
    // Creating some of the wgpu types requires async code
    pub async fn new(instance: &wgpu::Instance, window: Window, settings: Option<&Settings>) -> Self {
        let size = window.inner_size();

        // The instance is a handle to our GPU
        // BackendBit::PRIMARY => Vulkan + Metal + DX12 + Browser WebGPU
        let surface = unsafe { instance.create_surface(&window) };
        let adapter = instance.request_adapter(
            &wgpu::RequestAdapterOptions {
                power_preference: wgpu::PowerPreference::default(),
                compatible_surface: Some(&surface),
            },
        ).await.unwrap();

        let (mut device, queue) = adapter.request_device(
            &wgpu::DeviceDescriptor {
                features: wgpu::Features::empty(),
                limits: wgpu::Limits::default(),
                label: None,
            },
            None, // Trace path
        ).await.unwrap();

        let sc_desc = wgpu::SwapChainDescriptor {
            usage: wgpu::TextureUsage::RENDER_ATTACHMENT,
            format: adapter.get_swap_chain_preferred_format(&surface),
            width: size.width,
            height: size.height,
            present_mode: wgpu::PresentMode::Mailbox,
        };
        let swap_chain = device.create_swap_chain(&surface, &sc_desc);
        let viewport = Viewport::with_physical_size(Size::new(size.width, size.height), window.scale_factor());
        let renderer = Renderer::new(Backend::new(&mut device, settings.map(ToOwned::to_owned).unwrap_or_default()));

        Self {
            window,
            surface,
            device,
            queue,
            sc_desc,
            swap_chain,
            viewport,
            renderer,
        }
    }

    pub fn resize(&mut self, new_size: PhysicalSize<u32>, scale_factor: Option<f64>) {
        self.viewport = Viewport::with_physical_size(Size::new(new_size.width, new_size.height), scale_factor.unwrap_or(self.viewport.scale_factor()));
        self.sc_desc.height = new_size.height;
        self.sc_desc.width = new_size.width;
        self.swap_chain = self.device.create_swap_chain(&self.surface, &self.sc_desc);
    }

    pub fn input(&mut self, _event: &WindowEvent) -> bool {
        false
    }

    pub fn update(&mut self) {
        
    }

    pub fn render(&mut self, output: &(Primitive, mouse::Interaction), staging_belt: &mut StagingBelt, overlay: &[String], bg_color: Color) -> Result<(), wgpu::SwapChainError> {
        let frame = self.swap_chain.get_current_frame()?.output;
        let mut encoder = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: None,
        });
        {
            let _render_pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: None,
                color_attachments: &[
                    wgpu::RenderPassColorAttachmentDescriptor {
                        attachment: &frame.view,
                        resolve_target: None,
                        ops: wgpu::Operations {
                            load: wgpu::LoadOp::Clear({
                                let [r, g, b, a] = bg_color.into_linear();

                                wgpu::Color {
                                    r: r as f64,
                                    g: g as f64,
                                    b: b as f64,
                                    a: a as f64,
                                }
                            }),
                            store: true,
                        }
                    }
                ],
                depth_stencil_attachment: None,
            });
        }
        
        let mouse_interaction = self.renderer.backend_mut().draw(
            &mut self.device,
            staging_belt,
            &mut encoder,
            &frame.view,
            &self.viewport,
            output,
            overlay,
        );

        // Then we submit the work
        staging_belt.finish();
        self.queue.submit(Some(encoder.finish()));

        // Update the mouse cursor
        self.window.set_cursor_icon(conversion::mouse_interaction(mouse_interaction));
        Ok(())
    }
}