use iced_wgpu::{wgpu, Viewport};
use iced_winit::{program, winit, Program, Size};
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
            usage: wgpu::TextureUsage::OUTPUT_ATTACHMENT,
            format: wgpu::TextureFormat::Bgra8UnormSrgb,
            // format: adapter.get_swap_chain_preferred_format(&surface)
            width: size.width,
            height: size.height,
            present_mode: wgpu::PresentMode::Fifo,
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
