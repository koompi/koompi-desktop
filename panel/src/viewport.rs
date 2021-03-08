use super::controls::Controls;
use crate::ModifiersState;
use iced_wgpu::wgpu;
use iced_wgpu::{Backend, Renderer, Settings, Viewport};
use iced_winit::winit::{
    dpi::{PhysicalPosition, PhysicalSize},
    event::{Event, WindowEvent},
    event_loop::{ControlFlow, EventLoop},
    platform::unix::{WindowBuilderExtUnix, XWindowStrut, XWindowType},
    window::{Window, WindowId},
};
use iced_winit::Debug;
use iced_winit::Size;
use iced_winit::{conversion, futures::task::SpawnExt, program};
use std::collections::HashMap;
// const WINDOW_SIZE: u32 = 128;
// const WINDOW_PADDING: u32 = 16;
// const WINDOW_TITLEBAR: u32 = 32;
// const WINDOW_OFFSET: u32 = WINDOW_SIZE + WINDOW_PADDING;
// const ROWS: u32 = 4;
// const COLUMNS: u32 = 4;

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

    fn build(self, _adapter: &wgpu::Adapter, device: &wgpu::Device) -> ViewportPanel {
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
    let cursor_position = PhysicalPosition::new(-1.0, -1.0);
    let modifiers = ModifiersState::default();
    let viewports: Vec<_> = viewports
        .into_iter()
        .map(|(window, color)| ViewportDesc::new(window, color, &instance))
        .collect();
    let key = viewports[0].window.id();
    let adapter = instance
        .request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::default(),
            // Request an adapter which can render to our surface
            compatible_surface: viewports.first().map(|desc| &desc.surface),
        })
        .await
        .expect("Failed to find an appropriate adapter");

    // Create the logical device and command queue
    let (mut device, queue) = adapter
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
    let win_size = viewports.get(&key).unwrap().desc.window.inner_size();
    let scale_factor = viewports.get(&key).unwrap().desc.window.scale_factor();
    let viewport_opt =
        Viewport::with_physical_size(Size::new(win_size.width, win_size.height), scale_factor);
    let mut debug = Debug::new();
    let mut renderer = Renderer::new(Backend::new(&mut device, Settings::default()));
    let controls = Controls::new();
    let mut state = program::State::new(
        controls,
        viewport_opt.logical_size(),
        conversion::cursor_position(cursor_position, viewport_opt.scale_factor()),
        &mut renderer,
        &mut debug,
    );
    // // Initialize staging belt and local pool
    let mut staging_belt = wgpu::util::StagingBelt::new(5 * 1024);
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
                    WindowEvent::Resized(size) => {
                        // Recreate the swap chain with the new size
                        if let Some(viewport) = viewports.get_mut(&window_id) {
                            viewport.resize(&device, size);
                        }
                    }
                    // WindowEvent::CursorEntered { device_id } => {
                    //     println!("Cursor enter: {:?}", device_id);
                    // }
                    WindowEvent::CloseRequested => {
                        viewports.remove(&window_id);
                        if viewports.is_empty() {
                            *control_flow = ControlFlow::Exit
                        }
                    }
                    _ => {}
                }

                //             // Map window event to iced event
                match &viewports.get(&window_id) {
                    Some(panel_win) => {
                        if let Some(event) = iced_winit::conversion::window_event(
                            &event,
                            panel_win.desc.window.scale_factor(),
                            modifiers,
                        ) {
                            state.queue_event(event);
                        }
                    }
                    None => {}
                }
            }
            Event::MainEventsCleared => {
                match viewports.get_mut(&key) {
                    Some(view_port_desc) => {
                        // If there are events pending
                        if !state.is_queue_empty() {
                            // We update iced
                            let _ = state.update(
                                viewport_opt.logical_size(),
                                conversion::cursor_position(
                                    cursor_position,
                                    viewport_opt.scale_factor(),
                                ),
                                None,
                                &mut renderer,
                                &mut debug,
                            );
                            // and request a redraw
                            view_port_desc.desc.window.request_redraw();
                        };
                    }
                    None => {}
                };
            }
            Event::RedrawRequested(window_id) => {
                if controls.is_quit() {
                    println!("Is quit");
                } else {
                }
                if let Some(viewport) = viewports.get_mut(&window_id) {
                    let frame = viewport.get_current_frame();
                    let mut encoder = device
                        .create_command_encoder(&wgpu::CommandEncoderDescriptor { label: None });
                    {
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
                    }
                    let mouse_interaction = renderer.backend_mut().draw(
                        &mut device,
                        &mut staging_belt,
                        &mut encoder,
                        &frame.view,
                        &viewport_opt,
                        state.primitive(),
                        &debug.overlay(),
                    );
                    viewport.desc.window.set_cursor_icon(
                        iced_winit::conversion::mouse_interaction(mouse_interaction),
                    );
                    //             // And then iced on top
                    staging_belt.finish();
                    queue.submit(Some(encoder.finish()));
                }
            }
            _ => {}
        }
    });
}
use iced_winit::futures;
use iced_winit::winit::window::WindowBuilder;
pub fn init_ui() {
    let event_loop = EventLoop::new();
    let mut viewports = Vec::with_capacity(4);
    // for col in 0..COLUMNS {
    let window = WindowBuilder::new()
        .with_x11_window_type(vec![XWindowType::PopupMenu, XWindowType::Dock])
        .with_x11_window_strut(vec![XWindowStrut::Strut([0, 0, 32, 0])])
        .with_inner_size(PhysicalSize::new(1920, 32))
        .build(&event_loop)
        .unwrap();
    window.set_outer_position(PhysicalPosition::new(0, 0));
    let menu = WindowBuilder::new()
        .with_inner_size(PhysicalSize::new(200, 400))
        .with_x11_window_type(vec![XWindowType::Menu])
        .build(&event_loop)
        .unwrap();
    menu.set_outer_position(PhysicalPosition::new(1820, 33));
    menu.set_visible(true);
    viewports.push((
        window,
        wgpu::Color {
            r: 255.0,
            g: 255.0,
            b: 255.0,
            a: 0.2,
        },
    ));
    viewports.push((
        menu,
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
