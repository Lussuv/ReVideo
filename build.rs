fn main() {
    // Embeds the app icon into ReVideo.exe; host-independent so cross-builds from Linux get it too.
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        winresource::WindowsResource::new()
            .set_icon("assets/icon.ico")
            .compile()
            .expect("failed to embed Windows resources");
    }
}
