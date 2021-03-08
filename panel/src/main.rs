mod controls;
mod panelwin;
mod strut;
mod styles;
mod viewport;
// use controls::Controls;

use iced_winit::{conversion, futures, futures::task::SpawnExt, program, winit, Debug, Size};
// use super::scene::Scene;
use iced_wgpu::{wgpu, Backend, Renderer, Settings, Viewport};

use winit::{
    dpi::PhysicalPosition,
    event::{Event, ModifiersState, WindowEvent},
    event_loop::{ControlFlow, EventLoop},
    platform::unix::{WindowBuilderExtUnix, XWindowStrut, XWindowType},
    window::WindowBuilder,
};

fn main() {
    // let mut cursor_position = PhysicalPosition::new(-1.0, -1.0);
    // let mut modifiers = ModifiersState::default();

    // let event_loop = EventLoop::new();
    // let mut strut_size = strut::StrutArea::new();
    // let mut strut_partial = strut::StrutPartialArea::new();
    // strut_size.set_top(32);
    // strut_partial.set_top(32);
    // strut_partial.set_top_end_x(1920);
    // let window = WindowBuilder::new()
    //     .with_x11_window_type(vec![XWindowType::Dock])
    //     .with_x11_window_strut(vec![
    //         XWindowStrut::Strut(strut_size.list_props()),
    //         XWindowStrut::StrutPartial(strut_partial.list_props()),
    //     ])
    //     .build(&event_loop)
    //     .unwrap();
    // let mut panel_win = panelwin::WindowPanel::new(window);
    // panel_win.set_deafult_size();
    // panel_win.set_outer_position();
    // let physical_size = panel_win.window.inner_size();
    // let mut viewport = panel_win.get_viewport(physical_size);
    // // Initialize wgpu
    // let instance = wgpu::Instance::new(wgpu::BackendBit::PRIMARY);
    // let surface = unsafe { instance.create_surface(&panel_win.window) };

    // let (mut device, queue) = futures::executor::block_on(async {
    //     let adapter = instance
    //         .request_adapter(&wgpu::RequestAdapterOptions {
    //             power_preference: wgpu::PowerPreference::Default,
    //             compatible_surface: Some(&surface),
    //         })
    //         .await
    //         .expect("Request adapter");

    //     adapter
    //         .request_device(
    //             &wgpu::DeviceDescriptor {
    //                 features: wgpu::Features::empty(),
    //                 limits: wgpu::Limits::default(),
    //                 shader_validation: false,
    //             },
    //             None,
    //         )
    //         .await
    //         .expect("Request device")
    // });

    // let format = wgpu::TextureFormat::Bgra8UnormSrgb;

    // let mut swap_chain = {
    //     let size = panel_win.window.inner_size();

    //     device.create_swap_chain(
    //         &surface,
    //         &wgpu::SwapChainDescriptor {
    //             usage: wgpu::TextureUsage::OUTPUT_ATTACHMENT,
    //             format: format,
    //             width: size.width,
    //             height: size.height,
    //             present_mode: wgpu::PresentMode::Mailbox,
    //         },
    //     )
    // };
    // let mut resized = false;

    // // Initialize staging belt and local pool
    // let mut staging_belt = wgpu::util::StagingBelt::new(5 * 1024);
    // let mut local_pool = futures::executor::LocalPool::new();

    // // Initialize scene and GUI controls

    // // Initialize iced
    // let mut debug = Debug::new();
    // let mut renderer = Renderer::new(Backend::new(&mut device, Settings::default()));
    // let controls = Controls::new();
    // let mut state = program::State::new(
    //     controls,
    //     viewport.logical_size(),
    //     conversion::cursor_position(cursor_position, viewport.scale_factor()),
    //     &mut renderer,
    //     &mut debug,
    // );

    // // Run event loop
    // event_loop.run(move |event, _, control_flow| {
    //     // You should change this if you want to render continuosly
    //     *control_flow = ControlFlow::Wait;
    //     match event {
    //         Event::WindowEvent { event, .. } => {
    //             match event {
    //                 WindowEvent::CursorMoved { position, .. } => {
    //                     cursor_position = position;
    //                 }
    //                 WindowEvent::ModifiersChanged(new_modifiers) => {
    //                     modifiers = new_modifiers;
    //                 }
    //                 WindowEvent::Resized(new_size) => {
    //                     viewport = Viewport::with_physical_size(
    //                         Size::new(new_size.width, new_size.height),
    //                         panel_win.window.scale_factor(),
    //                     );

    //                     resized = true;
    //                 }
    //                 WindowEvent::CloseRequested => {
    //                     *control_flow = ControlFlow::Exit;
    //                 }
    //                 _ => {}
    //             }

    //             // Map window event to iced event
    //             if let Some(event) = iced_winit::conversion::window_event(
    //                 &event,
    //                 panel_win.window.scale_factor(),
    //                 modifiers,
    //             ) {
    //                 state.queue_event(event);
    //             }
    //         }
    //         Event::MainEventsCleared => {
    //             // If there are events pending
    //             if !state.is_queue_empty() {
    //                 // We update iced
    //                 let _ = state.update(
    //                     viewport.logical_size(),
    //                     conversion::cursor_position(cursor_position, viewport.scale_factor()),
    //                     None,
    //                     &mut renderer,
    //                     &mut debug,
    //                 );

    //                 // and request a redraw
    //                 panel_win.window.request_redraw();
    //             }
    //         }
    //         Event::RedrawRequested(_) => {
    //             if resized {
    //                 let size = panel_win.window.inner_size();

    //                 swap_chain = device.create_swap_chain(
    //                     &surface,
    //                     &wgpu::SwapChainDescriptor {
    //                         usage: wgpu::TextureUsage::OUTPUT_ATTACHMENT,
    //                         format: format,
    //                         width: size.width,
    //                         height: size.height,
    //                         present_mode: wgpu::PresentMode::Mailbox,
    //                     },
    //                 );

    //                 resized = false;
    //             }

    //             let frame = swap_chain.get_current_frame().expect("Next frame");

    //             let mut encoder =
    //                 device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: None });

    //             // let program = state.program();

    //             // {
    //             //     // We clear the frame
    //             //     let mut render_pass =
    //             //         scene.clear(&frame.output.view, &mut encoder, program.background_color());

    //             //     // Draw the scene
    //             //     scene.draw(&mut render_pass);
    //             // }
    //             let program = state.program();
    //             println!("Program: {:?}", program.is_quit());
    //             if program.is_quit() {
    //                 *control_flow = ControlFlow::Exit;
    //             } else {
    //                 {}
    //             }
    //             // And then iced on top
    //             let mouse_interaction = renderer.backend_mut().draw(
    //                 &mut device,
    //                 &mut staging_belt,
    //                 &mut encoder,
    //                 &frame.output.view,
    //                 &viewport,
    //                 state.primitive(),
    //                 &debug.overlay(),
    //             );

    //             // Then we submit the work
    //             staging_belt.finish();
    //             queue.submit(Some(encoder.finish()));

    //             // Update the mouse cursor
    //             panel_win
    //                 .window
    //                 .set_cursor_icon(iced_winit::conversion::mouse_interaction(mouse_interaction));

    //             // And recall staging buffers
    //             local_pool
    //                 .spawner()
    //                 .spawn(staging_belt.recall())
    //                 .expect("Recall staging buffers");

    //             local_pool.run_until_stalled();
    //         }
    //         _ => {}
    //     }
    // })
    viewport::init_ui();
}
