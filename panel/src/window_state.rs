use futures::executor::LocalPool;
use futures::task::SpawnExt;
use iced_wgpu::{wgpu, Backend, Renderer, Settings, Viewport};
use iced_winit::winit;
use iced_winit::{conversion, program, Debug, Program, Size};
use winit::{
    dpi::PhysicalPosition,
    event::{ModifiersState, WindowEvent},
    window::Window,
};
pub struct State<T: 'static + Program> {
    pub window: Window,
    pub surface: wgpu::Surface,
    pub device: wgpu::Device,
    pub queue: wgpu::Queue,
    sc_desc: wgpu::SwapChainDescriptor,
    swap_chain: wgpu::SwapChain,
    pub size: winit::dpi::PhysicalSize<u32>,
    pub render: Renderer,
    pub viewport: iced_wgpu::Viewport,
    local_pool: LocalPool,
    staging_belt: wgpu::util::StagingBelt,
    pub modifiers: ModifiersState,
    pub win_state: program::State<T>,
    pub is_cursor_left: Option<bool>,
    pub is_visible: bool,
}
impl<T> State<T>
where
    T: 'static + Program<Renderer = Renderer>,
{
    pub async fn new(
        window: Window,
        program: T,
        settings: Option<&Settings>,
        cursor_pos: PhysicalPosition<f64>,
        debug: &mut Debug,
        instance: &wgpu::Instance,
    ) -> Self {
        let size = window.inner_size();

        // The instance is a handle to our GPU
        // BackendBit::PRIMARY => Vulkan + Metal + DX12 + Browser WebGPU
        // let instance = wgpu::Instance::new(wgpu::BackendBit::PRIMARY);
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
        let local_pool = LocalPool::new();
        let mut render = Renderer::new(Backend::new(
            &mut device,
            settings.map(ToOwned::to_owned).unwrap_or_default(),
        ));
        let staging_belt = wgpu::util::StagingBelt::new(4 * 1024);
        let modifiers = ModifiersState::default();
        let win_state = program::State::new(
            program,
            viewport.logical_size(),
            conversion::cursor_position(cursor_pos, viewport.scale_factor()),
            &mut render,
            debug,
        );
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
            local_pool,
            staging_belt,
            modifiers,
            win_state,
            is_cursor_left: Some(false),
            is_visible: false,
        }
    }

    pub fn resize(&mut self, new_size: winit::dpi::PhysicalSize<u32>) {
        self.size = new_size;
        self.sc_desc.width = new_size.width;
        self.sc_desc.height = new_size.height;
        self.swap_chain = self.device.create_swap_chain(&self.surface, &self.sc_desc);
    }

    pub fn update(&mut self) {}

    pub fn input(&mut self, event: &WindowEvent) -> bool {
        true
    }
    pub fn render(&mut self, debug: &Debug) -> Result<(), wgpu::SwapChainError> {
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
            &mut self.staging_belt,
            &mut encoder,
            &frame.view,
            &self.viewport,
            self.win_state.primitive(),
            &debug.overlay(),
        );
        // // Then we submit the work
        self.staging_belt.finish();
        // Update the mouse cursor
        self.window
            .set_cursor_icon(conversion::mouse_interaction(mouse_interaction));
        self.queue.submit(std::iter::once(encoder.finish()));
        self.local_pool
            .spawner()
            .spawn(self.staging_belt.recall())
            .expect("Recall staging buffers");

        self.local_pool.run_until_stalled();
        Ok(())
    }

    pub fn map_event(&mut self, modifier: &ModifiersState, event: &winit::event::WindowEvent) {
        if let Some(event) =
            conversion::window_event(&event, self.viewport.scale_factor(), *modifier)
        {
            self.win_state.queue_event(event);
        }
    }
    pub fn redraw(&mut self, debug: &Debug) {
        match self.render(&debug) {
            Ok(_) => {}
            // Recreate the swap_chain if lost
            Err(wgpu::SwapChainError::Lost) => self.resize(self.size),
            // The system is out of memory, we should probably quit
            Err(wgpu::SwapChainError::OutOfMemory) => {}
            // All other errors (Outdated, Timeout) should be resolved by the next frame
            Err(e) => {}
        }
    }
    pub fn update_frame(&mut self, cursor_pos: PhysicalPosition<f64>, debug: &mut Debug) {
        if !self.win_state.is_queue_empty() {
            let _ = self.win_state.update(
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
