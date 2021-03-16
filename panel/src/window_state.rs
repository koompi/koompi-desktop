use iced_wgpu::{wgpu, Backend, Primitive, Renderer, Settings, Viewport};
use iced_winit::winit;
use iced_winit::{conversion, mouse, program, Debug, Program, Size};
use wgpu::util::StagingBelt;

use winit::{
    dpi::PhysicalPosition,
    event::{ModifiersState, WindowEvent},
    window::Window,
};
#[derive(Debug)]
pub struct State {
    pub window: Window,
    pub surface: wgpu::Surface,
    pub device: wgpu::Device,
    pub queue: wgpu::Queue,
    sc_desc: wgpu::SwapChainDescriptor,
    swap_chain: wgpu::SwapChain,
    pub size: winit::dpi::PhysicalSize<u32>,
    pub render: Renderer,
    pub viewport: iced_wgpu::Viewport,
}

impl State {
    pub async fn new(window: Window, settings: Option<&Settings>) -> Self {
        let size = window.inner_size();

        // The instance is a handle to our GPU
        // BackendBit::PRIMARY => Vulkan + Metal + DX12 + Browser WebGPU
        let instance = wgpu::Instance::new(wgpu::BackendBit::PRIMARY);
        let surface = unsafe { instance.create_surface(&window) };
        let adapter = instance
            .request_adapter(&wgpu::RequestAdapterOptions {
                power_preference: wgpu::PowerPreference::default(),
                compatible_surface: Some(&surface),
            })
            .await
            .unwrap();

        let (mut device, queue) = adapter
            .request_device(
                &wgpu::DeviceDescriptor {
                    label: None,
                    features: wgpu::Features::empty(),
                    limits: wgpu::Limits::default(),
                },
                None, // Trace path
            )
            .await
            .unwrap();

        let sc_desc = wgpu::SwapChainDescriptor {
            usage: wgpu::TextureUsage::RENDER_ATTACHMENT,
            format: adapter.get_swap_chain_preferred_format(&surface),
            width: size.width,
            height: size.height,
            present_mode: wgpu::PresentMode::Fifo,
        };
        let swap_chain = device.create_swap_chain(&surface, &sc_desc);
        let viewport =
            Viewport::with_physical_size(Size::new(size.width, size.height), window.scale_factor());

        let render = Renderer::new(Backend::new(
            &mut device,
            settings.map(ToOwned::to_owned).unwrap_or_default(),
        ));
        Self {
            window,
            surface,
            device,
            queue,
            sc_desc,
            swap_chain,
            size,
            viewport,
            render,
        }
    }

    pub fn resize(&mut self, new_size: winit::dpi::PhysicalSize<u32>) {
        self.size = new_size;
        self.sc_desc.width = new_size.width;
        self.sc_desc.height = new_size.height;
        self.swap_chain = self.device.create_swap_chain(&self.surface, &self.sc_desc);
    }

    pub fn input(&mut self, _event: &WindowEvent) -> bool {
        false
    }

    pub fn update(&mut self) {}

    pub fn render(
        &mut self,
        primitive: &(Primitive, mouse::Interaction),
        stage: &mut StagingBelt,
        debug: &Debug,
    ) -> Result<(), wgpu::SwapChainError> {
        let frame = self.swap_chain.get_current_frame()?.output;

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("Render Encoder"),
            });

        {
            let _render_pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("Render Pass"),
                color_attachments: &[wgpu::RenderPassColorAttachmentDescriptor {
                    attachment: &frame.view,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color::WHITE),
                        store: true,
                    },
                }],
                depth_stencil_attachment: None,
            });
        }
        // Draw iced on top
        let mouse_interaction = self.render.backend_mut().draw(
            &mut self.device,
            stage,
            &mut encoder,
            &frame.view,
            &self.viewport,
            primitive,
            &debug.overlay(),
        );
        // // Then we submit the work
        stage.finish();
        // Update the mouse cursor
        self.window
            .set_cursor_icon(conversion::mouse_interaction(mouse_interaction));
        self.queue.submit(std::iter::once(encoder.finish()));

        Ok(())
    }

    pub fn map_event<T: Program + 'static>(
        &mut self,
        state: &mut program::State<T>,
        modifier: &ModifiersState,
        event: &winit::event::WindowEvent,
    ) {
        if let Some(event) =
            conversion::window_event(&event, self.viewport.scale_factor(), *modifier)
        {
            state.queue_event(event);
        }
    }
    pub fn update_frame<
        P: Program<Renderer = iced_graphics::Renderer<iced_wgpu::Backend>> + 'static,
    >(
        &mut self,
        state: &mut program::State<P>,
        cursor_pos: PhysicalPosition<f64>,
        debug: &mut Debug,
    ) {
        if !state.is_queue_empty() {
            let _ = state.update(
                self.viewport.logical_size(),
                conversion::cursor_position(cursor_pos, self.viewport.scale_factor()),
                None,
                &mut self.render,
                debug,
            );
        }
        self.window.request_redraw();
    }
}
