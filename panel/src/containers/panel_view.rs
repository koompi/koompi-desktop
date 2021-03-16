use iced_wgpu::wgpu;
use iced_wgpu::Viewport;
use iced_winit::winit::window::{Window, WindowId};
use iced_winit::{winit, Size};
pub struct ViewportDesc {
    pub window: Window,
    pub background: wgpu::Color,
    pub surface: wgpu::Surface,
    pub viewport: Viewport,
}

pub struct ViewPort {
    pub desc: ViewportDesc,
    sc_desc: wgpu::SwapChainDescriptor,
    swap_chain: wgpu::SwapChain,
}

impl ViewportDesc {
    pub fn new(window: Window, background: wgpu::Color, instance: &wgpu::Instance) -> Self {
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

    pub fn build(self, adapter: &wgpu::Adapter, device: &wgpu::Device) -> ViewPort {
        let size = self.window.inner_size();

        let sc_desc = wgpu::SwapChainDescriptor {
            usage: wgpu::TextureUsage::RENDER_ATTACHMENT,
            format: adapter.get_swap_chain_preferred_format(&self.surface),
            width: size.width,
            height: size.height,
            present_mode: wgpu::PresentMode::Fifo,
        };

        let swap_chain = device.create_swap_chain(&self.surface, &sc_desc);

        ViewPort {
            desc: self,
            sc_desc,
            swap_chain,
        }
    }
}

impl ViewPort {
    pub fn resize(&mut self, device: &wgpu::Device, size: winit::dpi::PhysicalSize<u32>) {
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
