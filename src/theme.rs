//! Retry-Design 4.0 tokens and widget styles.
use iced::widget::{button, container, slider, text_input};
use iced::{border, color, Background, Border, Color, Font, Shadow, Theme, Vector};

pub const BG: Color = color!(0x14161C);
pub const BG_2: Color = color!(0x1C1F27);
pub const SF: Color = color!(0x272B36);
pub const SF_2: Color = color!(0x363C4A);
pub const SF_3: Color = color!(0x474E60);
pub const SF_4: Color = color!(0x596177);

pub const LN_SOFT: Color = Color::from_rgba(1.0, 1.0, 1.0, 0.12);
pub const LN: Color = Color::from_rgba(1.0, 1.0, 1.0, 0.18);
pub const LN_STRONG: Color = Color::from_rgba(1.0, 1.0, 1.0, 0.30);

pub const A_FILL: Color = color!(0x0E7A3C);
pub const A_HI: Color = color!(0x0F8241);
pub const A_TEXT: Color = color!(0x45D67C);
pub const A_RING: Color = Color::from_rgba(48.0 / 255.0, 209.0 / 255.0, 88.0 / 255.0, 0.42);

pub const TX: Color = color!(0xF2F3F7);
pub const TX_2: Color = color!(0xA8ACBA);
pub const TX_3: Color = color!(0x9398A8);

pub const ERR: Color = color!(0xFF6961);
pub const SCRIM: Color = Color::from_rgba(0.0, 0.0, 0.0, 0.32);

pub const R_1: f32 = 8.0;
pub const R_2: f32 = 12.0;
pub const R_4: f32 = 22.0;

pub const FONT: Font = Font::with_name("Inter");
pub const SEMIBOLD: Font = Font {
    weight: iced::font::Weight::Semibold,
    ..FONT
};
pub const MONO: Font = Font::with_name("JetBrains Mono");

pub fn theme() -> Theme {
    Theme::custom(
        "Retry".to_string(),
        iced::theme::Palette {
            background: BG,
            text: TX,
            primary: A_FILL,
            success: A_TEXT,
            warning: color!(0xFFB340),
            danger: ERR,
        },
    )
}

fn sh(level: u8) -> Shadow {
    let (y, blur, a) = match level {
        1 => (1.0, 3.0, 0.30),
        2 => (6.0, 18.0, 0.34),
        _ => (16.0, 48.0, 0.42),
    };
    Shadow {
        color: Color::from_rgba(0.0, 0.0, 0.0, a),
        offset: Vector::new(0.0, y),
        blur_radius: blur,
    }
}

pub fn topbar(_: &Theme) -> container::Style {
    container::Style {
        background: Some(BG_2.into()),
        border: Border {
            color: LN_SOFT,
            width: 0.0,
            radius: 0.0.into(),
        },
        ..Default::default()
    }
}

pub fn page(_: &Theme) -> container::Style {
    container::Style {
        background: Some(BG.into()),
        text_color: Some(TX),
        ..Default::default()
    }
}

/// Floating surface: popover, dialog, control bar.
pub fn sheet(_: &Theme) -> container::Style {
    container::Style {
        background: Some(SF_2.into()),
        border: Border {
            color: LN,
            width: 1.0,
            radius: R_2.into(),
        },
        shadow: sh(3),
        text_color: Some(TX),
        ..Default::default()
    }
}

pub fn panel(_: &Theme) -> container::Style {
    container::Style {
        background: Some(BG_2.into()),
        border: Border {
            color: LN_SOFT,
            width: 1.0,
            radius: R_4.into(),
        },
        shadow: sh(2),
        ..Default::default()
    }
}

pub fn controls(_: &Theme) -> container::Style {
    container::Style {
        background: Some(Color { a: 0.92, ..BG_2 }.into()),
        border: Border {
            color: LN_SOFT,
            width: 1.0,
            radius: R_2.into(),
        },
        shadow: sh(2),
        ..Default::default()
    }
}

pub fn scrim(_: &Theme) -> container::Style {
    container::Style {
        background: Some(SCRIM.into()),
        ..Default::default()
    }
}

pub fn toast(_: &Theme) -> container::Style {
    container::Style {
        background: Some(SF_2.into()),
        border: Border {
            color: ERR,
            width: 1.0,
            radius: R_2.into(),
        },
        shadow: sh(3),
        text_color: Some(TX),
        ..Default::default()
    }
}

/// Topbar tab: grey offer, green underline-free active state via surface step.
pub fn tab(active: bool) -> impl Fn(&Theme, button::Status) -> button::Style {
    move |_, status| {
        let (bg, fg) = match status {
            button::Status::Disabled => (None, TX_3.scale_alpha(0.55)),
            button::Status::Hovered | button::Status::Pressed => (Some(SF), TX),
            _ if active => (Some(SF), TX),
            _ => (None, TX_2),
        };
        button::Style {
            background: bg.map(Background::Color),
            text_color: fg,
            border: border::rounded(R_1),
            ..Default::default()
        }
    }
}

pub fn tab_danger(_: &Theme, status: button::Status) -> button::Style {
    let fg = match status {
        button::Status::Hovered | button::Status::Pressed => ERR,
        button::Status::Disabled => TX_3.scale_alpha(0.55),
        _ => TX_2,
    };
    let bg = matches!(status, button::Status::Hovered | button::Status::Pressed)
        .then_some(Background::Color(SF));
    button::Style {
        background: bg,
        text_color: fg,
        border: border::rounded(R_1),
        ..Default::default()
    }
}

pub fn primary(_: &Theme, status: button::Status) -> button::Style {
    let bg = match status {
        button::Status::Hovered => A_HI,
        button::Status::Disabled => SF_2,
        _ => A_FILL,
    };
    let fg = if status == button::Status::Disabled {
        TX_3
    } else {
        Color::WHITE
    };
    button::Style {
        background: Some(bg.into()),
        text_color: fg,
        border: border::rounded(R_1),
        shadow: sh(1),
        ..Default::default()
    }
}

pub fn secondary(selected: bool) -> impl Fn(&Theme, button::Status) -> button::Style {
    move |_, status| {
        let hover = matches!(status, button::Status::Hovered | button::Status::Pressed);
        button::Style {
            background: Some(if hover || selected { SF_3 } else { SF_2 }.into()),
            text_color: TX,
            border: Border {
                color: if selected {
                    TX_2
                } else if hover {
                    LN_STRONG
                } else {
                    LN
                },
                width: if selected { 2.0 } else { 1.0 },
                radius: R_1.into(),
            },
            shadow: sh(1),
            ..Default::default()
        }
    }
}

pub fn danger(selected: bool) -> impl Fn(&Theme, button::Status) -> button::Style {
    move |_, status| {
        let hover = matches!(status, button::Status::Hovered | button::Status::Pressed);
        button::Style {
            background: Some(
                if hover || selected {
                    ERR.scale_alpha(0.28)
                } else {
                    ERR.scale_alpha(0.16)
                }
                .into(),
            ),
            text_color: ERR,
            border: Border {
                color: if selected { ERR } else { ERR.scale_alpha(0.5) },
                width: if selected { 2.0 } else { 1.0 },
                radius: R_1.into(),
            },
            ..Default::default()
        }
    }
}

/// Borderless icon button on the player controls.
pub fn ghost(_: &Theme, status: button::Status) -> button::Style {
    let hover = matches!(status, button::Status::Hovered | button::Status::Pressed);
    button::Style {
        background: hover.then_some(Background::Color(SF_2)),
        text_color: if hover { TX } else { TX_2 },
        border: border::rounded(R_1),
        ..Default::default()
    }
}

/// Selectable row in the export preset list; the active row carries the right-edge marker.
pub fn preset_row(active: bool) -> impl Fn(&Theme, button::Status) -> button::Style {
    move |_, status| {
        let hover = matches!(status, button::Status::Hovered | button::Status::Pressed);
        button::Style {
            background: (hover || active).then_some(Background::Color(SF_3)),
            text_color: TX,
            border: Border {
                color: if active { A_FILL } else { Color::TRANSPARENT },
                width: if active { 1.0 } else { 0.0 },
                radius: R_2.into(),
            },
            ..Default::default()
        }
    }
}

pub fn seek_slider(_: &Theme, status: slider::Status) -> slider::Style {
    let hover = !matches!(status, slider::Status::Active);
    slider::Style {
        rail: slider::Rail {
            backgrounds: (A_FILL.into(), SF_3.into()),
            width: 4.0,
            border: border::rounded(2.0),
        },
        handle: slider::Handle {
            shape: slider::HandleShape::Circle {
                radius: if hover { 7.0 } else { 5.0 },
            },
            background: TX.into(),
            border_width: 0.0,
            border_color: Color::TRANSPARENT,
        },
    }
}

pub fn time_input(_: &Theme, status: text_input::Status) -> text_input::Style {
    let focused = matches!(status, text_input::Status::Focused { .. });
    text_input::Style {
        background: SF.into(),
        border: Border {
            color: if focused { A_RING } else { LN },
            width: if focused { 2.0 } else { 1.0 },
            radius: R_1.into(),
        },
        icon: TX_2,
        placeholder: TX_3,
        value: TX,
        selection: A_RING,
    }
}

pub fn tooltip(_: &Theme) -> container::Style {
    container::Style {
        background: Some(SF_4.into()),
        border: border::rounded(R_1),
        shadow: sh(2),
        text_color: Some(TX),
        ..Default::default()
    }
}
