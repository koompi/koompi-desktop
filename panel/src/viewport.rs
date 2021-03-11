use iced_wgpu::{wgpu, Viewport};
use iced_winit::{program, winit, Program, Size};

use winit::{dpi::PhysicalSize, window::Window};

pub struct ViewportDesc {
    pub window: Window,
    pub surface: wgpu::Surface,
    pub viewport: Viewport,
}

pub struct WindowPanel<P: 'static + Program> {
    pub desc: ViewportDesc,
    pub sc_decs: wgpu::SwapChainDescriptor,
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
        adapter: &wgpu::Adapter,
        device: &wgpu::Device,
        state: program::State<P>,
    ) -> WindowPanel<P> {
        let size = self.window.inner_size();
        let sc_decs = wgpu::SwapChainDescriptor {
            usage: wgpu::TextureUsage::RENDER_ATTACHMENT,
            format: wgpu::TextureFormat::Bgra8UnormSrgb,
            width: size.width,
            height: size.height,
            present_mode: wgpu::PresentMode::Mailbox,
        };

        let swap_chain = device.create_swap_chain(&self.surface, &sc_decs);
        WindowPanel {
            desc: self,
            sc_decs,
            swap_chain,
            state,
        }
    }
}

impl<P> WindowPanel<P>
where
    P: 'static + Program,
{
    pub fn resize(&mut self, device: &wgpu::Device, size: PhysicalSize<u32>) {
        self.sc_decs.width = size.width;
        self.sc_decs.height = size.height;
        self.swap_chain = device.create_swap_chain(&self.desc.surface, &self.sc_decs);
    }
    pub fn get_current_frame(&mut self) -> wgpu::SwapChainTexture {
        self.swap_chain
            .get_current_frame()
            .expect("Failed to acquired next swap chain texture")
            .output
    }
}
