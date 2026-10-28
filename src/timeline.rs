use crate::format::format_time;
use crate::theme::*;
use iced::mouse::{self, Cursor};
use iced::widget::canvas::{self, Action, Event, Frame, Geometry, Path, Text};
use iced::{Color, Point, Rectangle, Renderer, Size, Theme};

/// The thumbnail strip underneath the canvas must use the same insets.
pub const TICKS_H: f32 = 20.0;
pub const HANDLE_W: f32 = 10.0;
const GRAB: f32 = 12.0;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct TrimRange {
    pub start: f64,
    pub end: f64,
}

#[derive(Debug, Clone)]
pub enum TimelineEvent {
    Trim(TrimRange),
    Seek(f64),
}

pub struct Timeline {
    pub duration: f64,
    pub trim: TrimRange,
    pub position: f64,
}

#[derive(Default)]
pub enum Drag {
    #[default]
    None,
    Start,
    End,
    Playhead,
}

impl Timeline {
    fn x(&self, sec: f64, track: Rectangle) -> f32 {
        let ratio = if self.duration > 0.0 {
            (sec / self.duration).clamp(0.0, 1.0)
        } else {
            0.0
        };
        track.x + ratio as f32 * track.width
    }

    fn time(&self, x: f32, track: Rectangle) -> f64 {
        ((x - track.x) / track.width).clamp(0.0, 1.0) as f64 * self.duration
    }

    fn track(bounds: Rectangle) -> Rectangle {
        Rectangle {
            x: HANDLE_W,
            y: TICKS_H,
            width: bounds.width - 2.0 * HANDLE_W,
            height: bounds.height - TICKS_H,
        }
    }

    fn apply(&self, drag: &Drag, t: f64) -> Option<TimelineEvent> {
        match drag {
            Drag::Start => Some(TimelineEvent::Trim(TrimRange {
                start: t.min(self.trim.end - 0.05).max(0.0),
                end: self.trim.end,
            })),
            Drag::End => Some(TimelineEvent::Trim(TrimRange {
                start: self.trim.start,
                end: t.max(self.trim.start + 0.05),
            })),
            Drag::Playhead => Some(TimelineEvent::Seek(t)),
            Drag::None => None,
        }
    }
}

impl canvas::Program<TimelineEvent> for Timeline {
    type State = Drag;

    fn update(
        &self,
        drag: &mut Drag,
        event: &Event,
        bounds: Rectangle,
        cursor: Cursor,
    ) -> Option<Action<TimelineEvent>> {
        let track = Self::track(bounds);
        match event {
            Event::Mouse(mouse::Event::ButtonPressed(mouse::Button::Left)) => {
                let p = cursor.position_in(bounds)?;
                let (sx, ex) = (self.x(self.trim.start, track), self.x(self.trim.end, track));
                *drag = if (p.x - sx).abs() <= GRAB && p.x <= ex {
                    Drag::Start
                } else if (p.x - ex).abs() <= GRAB {
                    Drag::End
                } else {
                    Drag::Playhead
                };
                let t = self.time(p.x, track);
                Some(
                    self.apply(drag, t)
                        .map_or_else(Action::capture, Action::publish)
                        .and_capture(),
                )
            }
            Event::Mouse(mouse::Event::CursorMoved { .. }) if !matches!(drag, Drag::None) => {
                let p = cursor.position()?;
                let t = self.time(p.x - bounds.x, track);
                self.apply(drag, t)
                    .map(|e| Action::publish(e).and_capture())
            }
            Event::Mouse(mouse::Event::ButtonReleased(mouse::Button::Left))
                if !matches!(drag, Drag::None) =>
            {
                *drag = Drag::None;
                Some(Action::capture())
            }
            _ => None,
        }
    }

    fn draw(
        &self,
        _: &Drag,
        renderer: &Renderer,
        _: &Theme,
        bounds: Rectangle,
        _: Cursor,
    ) -> Vec<Geometry> {
        let mut f = Frame::new(renderer, bounds.size());
        let track = Self::track(bounds);

        // Tick labels
        let step = pick_step(self.duration);
        let mut s = 0.0;
        while self.duration > 0.0 && s <= self.duration + 0.001 {
            f.fill_text(Text {
                content: format_time(s, false),
                position: Point::new(
                    self.x(s, track)
                        .clamp(track.x + 28.0, track.x + track.width - 28.0),
                    2.0,
                ),
                color: TX_3,
                size: 11.0.into(),
                font: MONO,
                align_x: iced::alignment::Horizontal::Center.into(),
                ..Text::default()
            });
            s += step;
        }

        // Shade outside the trim range
        let (sx, ex) = (self.x(self.trim.start, track), self.x(self.trim.end, track));
        let shade = Color::from_rgba(0.0, 0.0, 0.0, 0.62);
        f.fill_rectangle(
            track.position(),
            Size::new(sx - track.x, track.height),
            shade,
        );
        f.fill_rectangle(
            Point::new(ex, track.y),
            Size::new(track.x + track.width - ex, track.height),
            shade,
        );

        // Selected range: top/bottom edges + handles
        f.fill_rectangle(Point::new(sx, track.y), Size::new(ex - sx, 2.0), A_TEXT);
        f.fill_rectangle(
            Point::new(sx, track.y + track.height - 2.0),
            Size::new(ex - sx, 2.0),
            A_TEXT,
        );
        for (x, left) in [(sx, true), (ex, false)] {
            let hx = if left { x - HANDLE_W } else { x };
            f.fill(
                &Path::rounded_rectangle(
                    Point::new(hx, track.y),
                    Size::new(HANDLE_W, track.height),
                    3.0.into(),
                ),
                A_FILL,
            );
            f.fill_rectangle(
                Point::new(
                    hx + HANDLE_W / 2.0 - 1.0,
                    track.y + track.height / 2.0 - 8.0,
                ),
                Size::new(2.0, 16.0),
                Color::WHITE,
            );
        }

        // Playhead
        let px = self.x(self.position, track);
        f.fill_rectangle(
            Point::new(px - 1.0, track.y - 4.0),
            Size::new(2.0, track.height + 8.0),
            TX,
        );

        vec![f.into_geometry()]
    }

    fn mouse_interaction(
        &self,
        drag: &Drag,
        bounds: Rectangle,
        cursor: Cursor,
    ) -> mouse::Interaction {
        let track = Self::track(bounds);
        match drag {
            Drag::Start | Drag::End => mouse::Interaction::ResizingHorizontally,
            Drag::Playhead => mouse::Interaction::Grabbing,
            Drag::None => match cursor.position_in(bounds) {
                Some(p)
                    if (p.x - self.x(self.trim.start, track)).abs() <= GRAB
                        || (p.x - self.x(self.trim.end, track)).abs() <= GRAB =>
                {
                    mouse::Interaction::ResizingHorizontally
                }
                Some(_) => mouse::Interaction::Pointer,
                None => mouse::Interaction::default(),
            },
        }
    }
}

fn pick_step(dur: f64) -> f64 {
    match dur {
        d if d <= 30.0 => 5.0,
        d if d <= 120.0 => 15.0,
        d if d <= 600.0 => 60.0,
        d if d <= 3600.0 => 300.0,
        _ => 600.0,
    }
}
