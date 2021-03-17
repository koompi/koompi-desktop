use iced_wgpu::{wgpu, Viewport};
use iced_winit::{winit, Size};
use winit::window::Window;

pub struct ViewportDesc {
    pub window: Window,
    pub background: wgpu::Color,
    pub surface: wgpu::Surface,
    pub viewport: Viewport,
}

pub struct PanelViewport {
    pub desc: ViewportDesc,
    pub sc_desc: wgpu::SwapChainDescriptor,
    pub swap_chain: wgpu::SwapChain,
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

    pub fn build(self, adapter: &wgpu::Adapter, device: &wgpu::Device) -> PanelViewport {
        let size = self.window.inner_size();

        let sc_desc = wgpu::SwapChainDescriptor {
            usage: wgpu::TextureUsage::OUTPUT_ATTACHMENT,
            format: wgpu::TextureFormat::Bgra8UnormSrgb,
            width: size.width,
            height: size.height,
            present_mode: wgpu::PresentMode::Mailbox,
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
