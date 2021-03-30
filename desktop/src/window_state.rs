use std::mem::ManuallyDrop;
use iced_wgpu::{
    wgpu, Renderer, Backend, Settings
};
use iced_winit::{
    winit, conversion, application, Size, Clipboard, Debug, Application, Program, Cache, UserInterface, Event, Executor, Runtime, Proxy, Command, Subscription,
};
use wgpu::util::StagingBelt;
use winit::{
    window::Window,
    event::{WindowEvent, ModifiersState},
    dpi::PhysicalPosition,
};
use super::proxy_message::ProxyMessage;
use super::gui::HasChanged;

pub struct WindowState<A: Application<Renderer = Renderer>> {
    pub window: Window,
    application: A,
    state: application::State<A>,
    surface: wgpu::Surface,
    device: wgpu::Device,
    queue: wgpu::Queue,
    sc_desc: wgpu::SwapChainDescriptor,
    swap_chain: wgpu::SwapChain,
    renderer: Renderer,
    clipboard: Clipboard,
    staging_belt: StagingBelt,
    events: Vec<Event>,
    messages: Vec<A::Message>,
    viewport_version: usize,
}

impl<A: Application<Renderer=Renderer>> WindowState<A> {
    // Creating some of the wgpu types requires async code
    pub async fn new(
        instance: &wgpu::Instance, 
        window: Window, 
        application: A, 
        visible: bool, 
        settings: Option<&Settings>,
    ) -> Self {
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
        let renderer = Renderer::new(Backend::new(&mut device, settings.map(ToOwned::to_owned).unwrap_or_default()));
        let state = application::State::new(&application, &window);
        if visible {
            window.set_visible(visible);
        }
        let clipboard = Clipboard::connect(&window);
        let viewport_version = state.viewport_version();
        let staging_belt = StagingBelt::new(10 * 1024);

        WindowState {
            window,
            application,
            state,
            surface,
            device,
            queue,
            sc_desc,
            swap_chain,
            renderer,
            clipboard,
            staging_belt,
            events: Vec::new(),
            messages: Vec::new(),
            viewport_version,
        }
    }

    pub fn window_event_request_exit(&mut self, event: &WindowEvent<'_>, debug: &mut Debug) -> bool {
        let is_close = requests_exit(&event, self.state.modifiers());
        self.state.update(&self.window, &event, debug);
        if let Some(event) =
            conversion::window_event(&event, self.state.scale_factor(), self.state.modifiers())
        {
            self.events.push(event);
        }
        is_close
    }

    pub fn render(&mut self, cursor_position: PhysicalPosition<f64>, debug: &mut Debug) -> Result<(), wgpu::SwapChainError> {
        debug.render_started();
        let mut user_interface = build_user_interface(
            &mut self.application,
            Cache::default(),
            &mut self.renderer,
            self.state.logical_size(),
            debug,
        );

        if self.viewport_version != self.state.viewport_version() {
            debug.layout_started();
            user_interface = user_interface.relayout(self.state.logical_size(), &mut self.renderer);
            debug.layout_finished();

            self.sc_desc.height = self.state.physical_size().height;
            self.sc_desc.width = self.state.physical_size().width;
            self.swap_chain = self.device.create_swap_chain(&self.surface, &self.sc_desc);

            self.viewport_version = self.state.viewport_version();
        }

        debug.draw_started();
        let primitive = user_interface
            .draw(&mut self.renderer, conversion::cursor_position(cursor_position, self.state.scale_factor()),);
        debug.draw_finished();

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
                                let [r, g, b, a] = self.state.background_color().into_linear();

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
            &mut self.staging_belt,
            &mut encoder,
            &frame.view,
            &self.state.viewport(),
            &primitive,
            &debug.overlay(),
        );
        debug.render_finished();

        // Then we submit the work
        self.staging_belt.finish();
        self.queue.submit(Some(encoder.finish()));

        // Update the mouse cursor
        self.window.set_cursor_icon(conversion::mouse_interaction(mouse_interaction));
        Ok(())
    }

    pub fn map_message(&mut self, message: A::Message) {
        self.messages.push(message);
    }

    pub fn subscription(&self) -> Subscription<A::Message> {
        self.application.subscription()
    }

    pub fn update_frame<E>(&mut self, runtime: Option<&mut Runtime<E, Proxy<ProxyMessage>, ProxyMessage>>, cursor_position: PhysicalPosition<f64>, debug: &mut Debug) -> Option<Command<A::Message>>
    where 
        E: Executor + 'static,
    {
        let Self {
            application,
            renderer,
            clipboard,
            ..
        } = self;

        let mut commands = None;

        if !(self.events.is_empty() && self.messages.is_empty()) {
            // self.state.update(
            //     self.viewport.logical_size(),
            //     conversion::cursor_position(cursor_pos, self.viewport.scale_factor()),
            //     &mut self.renderer,
            //     &mut self.clipboard,
            //     debug,
            // )

            let mut user_interface = ManuallyDrop::new(build_user_interface(
                application,
                Cache::default(),
                renderer,
                self.state.logical_size(),
                debug,
            ));
    
            debug.event_processing_started();
    
            let mut messages = Vec::new();
            let statuses = user_interface.update(
                &self.events,
                conversion::cursor_position(cursor_position, self.state.scale_factor()),
                renderer,
                clipboard,
                &mut messages,
            );
            messages.extend(self.messages.drain(..));

            if let Some(runtime) = runtime {
                for event in self.events.drain(..).zip(statuses.into_iter()) {
                    runtime.broadcast(event);
                }

                if !messages.is_empty() {
                    commands = Some(Command::batch(messages.into_iter().map(|message| {
                        debug.log_message(&message);
                
                        debug.update_started();
                        let command = runtime.enter(|| self.application.update(message, &mut self.clipboard));
                        debug.update_finished();
                        command
                    })))
                }
            } else {
                self.events.clear();

                if !messages.is_empty() {
                    commands = Some(Command::batch(messages.into_iter().map(|message| {
                        debug.log_message(&message);
                
                        debug.update_started();
                        let command = self.application.update(message, &mut self.clipboard);
                        debug.update_finished();
                        command
                    })))
                }
            }

            self.state.synchronize(&self.application, &self.window);
        }

        commands
    }

    pub fn redraw(&mut self, cursor_position: PhysicalPosition<f64>, debug: &mut Debug) -> bool {
        match self.render(cursor_position, debug) {
            Ok(()) => true,
            Err(wgpu::SwapChainError::Lost) => {
                self.swap_chain = self.device.create_swap_chain(&self.surface, &self.sc_desc);
                true
            },
            // The system is out of memory, we should probably quit
            Err(wgpu::SwapChainError::OutOfMemory) => false,
            // All other errors (Outdated, Timeout) should be resolved by the next frame
            Err(e) => {
                eprintln!("{:?}", e);
                true
            },
        }
    }

    pub fn has_changed(&self) -> bool 
    where A: HasChanged {
        self.application.has_changed()
    }
}

fn build_user_interface<'a, P: Program>(
    program: &'a mut P,
    cache: Cache,
    renderer: &mut P::Renderer,
    size: Size,
    debug: &mut Debug,
) -> UserInterface<'a, P::Message, P::Renderer> {
    debug.view_started();
    let view = program.view();
    debug.view_finished();

    debug.layout_started();
    let user_interface = UserInterface::build(view, size, cache, renderer);
    debug.layout_finished();

    user_interface
}

pub fn requests_exit(
    event: &WindowEvent<'_>,
    _modifiers: ModifiersState,
) -> bool {
    match event {
        WindowEvent::CloseRequested => true,
        #[cfg(target_os = "macos")]
        WindowEvent::KeyboardInput {
            input:
                KeyboardInput {
                    virtual_keycode: Some(winit::event::VirtualKeyCode::Q),
                    state: ElementState::Pressed,
                    ..
                },
            ..
        } if _modifiers.logo() => true,
        _ => false,
    }
}