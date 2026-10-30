#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod app;
mod ffmpeg;
mod format;
mod icons;
mod media;
mod theme;
mod timeline;
mod update;

fn main() -> iced::Result {
    iced::application(app::App::new, app::App::update, app::App::view)
        .title("ReVideo")
        .theme(|_: &app::App| theme::theme())
        .subscription(app::App::subscription)
        .font(include_bytes!("../assets/fonts/Inter-Regular.ttf").as_slice())
        .font(include_bytes!("../assets/fonts/Inter-SemiBold.ttf").as_slice())
        .font(include_bytes!("../assets/fonts/JetBrainsMono-Regular.ttf").as_slice())
        .default_font(theme::FONT)
        .window(iced::window::Settings {
            size: iced::Size::new(1280.0, 800.0),
            min_size: Some(iced::Size::new(960.0, 600.0)),
            icon: iced::window::icon::from_file_data(
                include_bytes!("../assets/icon-128.png"),
                None,
            )
            .ok(),
            platform_specific: iced::window::settings::PlatformSpecific {
                #[cfg(target_os = "linux")]
                application_id: "de.retrydev.ReVideo".into(),
                ..Default::default()
            },
            ..Default::default()
        })
        .run()
}
