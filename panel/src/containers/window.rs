use super::mainloop::run;
use iced_wgpu::wgpu;
use iced_wgpu::Viewport;
use iced_wgpu::{Backend, Renderer, Settings};
use iced_winit::winit::{
    dpi::{PhysicalPosition, PhysicalSize},
    event_loop::EventLoop,
    platform::unix::{WindowBuilderExtUnix, XWindowStrut, XWindowType},
    window::WindowBuilder,
};
use iced_winit::{conversion, futures, program, winit, Debug, Program, Size};
pub fn runner() {
    let event_loop = EventLoop::new();

    let mut viewports = Vec::with_capacity(2);
    let main_window = WindowBuilder::new()
        .with_x11_window_type(vec![XWindowType::Dock])
        .with_inner_size(PhysicalSize::new(1920, 40))
        .with_x11_window_strut(vec![XWindowStrut::Strut([0, 0, 40, 0])])
        .build(&event_loop)
        .unwrap();
    let display = WindowBuilder::new()
        .with_inner_size(PhysicalSize::new(400, 400))
        .with_x11_window_type(vec![XWindowType::Dock])
        .build(&event_loop)
        .unwrap();
    // let wm_strut_str = CString::new("_NET_WM_STRUT").unwrap();
    // let wm_strut_partial_str = CString::new("_NET_WM_STRUT_PARTIAL").unwrap();
    // let wm_cardinal = CString::new("CARDINAL").unwrap();
    // let display = main_window.xlib_display().unwrap() as *mut Display;

    // let (wm_strut_pro, strut_partial, cardinal) = unsafe {
    //     let strut = XInternAtom(display, wm_strut_str.as_ptr(), xlib::False);
    //     let card = XInternAtom(display, wm_cardinal.as_ptr(), xlib::False);
    //     let strut_partial = XInternAtom(display, wm_strut_partial_str.as_ptr(), xlib::False);
    //     (strut, strut_partial, card)
    // };
    // let xwindow = main_window.xlib_window().unwrap();
    // unsafe {
    //     XChangeProperty(
    //         display,
    //         xwindow,
    //         wm_strut_pro,
    //         cardinal,
    //         32 as c_int,
    //         PropModeReplace,
    //         [0, 0, 32, 0].as_ptr() as *const c_uchar,
    //         4,
    //     );
    //
    // let mut renderer = Renderer::new(Backend::new(&mut device, Settings::default()));
    main_window.set_outer_position(PhysicalPosition::new(0, 0));
    viewports.push((
        main_window,
        wgpu::Color {
            r: 255.0,
            g: 255.0,
            b: 255.0,
            a: 1.0,
        },
    ));
    // viewports.push((
    //     display,
    //     wgpu::Color {
    //         r: 255.0,
    //         g: 255.0,
    //         b: 255.0,
    //         a: 1.0,
    //     },
    // ));

    wgpu_subscriber::initialize_default_subscriber(None);
    // Temporarily avoid srgb formats for the swapchain on the web
    run(event_loop, viewports)
}
