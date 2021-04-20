fn main() {
    cc::Build::new()
        .file("library/win_type.c")
        .static_flag(true)
        .compile("win_type.a");
    println!("cargo:rustc-link-lib=X11");
}
