use crate::format::{aspect_ratio, format_bytes, format_time, parse_time};
use crate::icons::{icon, Icon};
use crate::media::{self, ExportPreset, Progress, VideoInfo};
use crate::theme::{self, *};
use crate::timeline::{Timeline, TimelineEvent, TrimRange, HANDLE_W, TICKS_H};
use crate::update::{self, Update};
use iced::keyboard::{self, key::Named, Key};
use iced::widget::{
    button, canvas, center, column, container, image, mouse_area, opaque, row, sensor, slider,
    space, stack, text, text_input, tooltip,
};
use iced::{window, Alignment, Element, Length, Subscription, Task};
use iced_video_player::{Video, VideoPlayer};
use std::collections::HashSet;
use std::path::PathBuf;
use std::time::{Duration, Instant};

const THUMB_COUNT: u32 = 12;
const CONTROLS_HIDE_AFTER: Duration = Duration::from_millis(1800);
const TRIM_PANEL_H: f32 = 164.0;

#[derive(Debug, Clone)]
pub enum Message {
    OpenFile,
    Load(PathBuf),
    Opened(u64, Result<(VideoInfo, media::Opened), String>),
    Thumbnails(u64, Vec<PathBuf>),
    NewFrame,
    EndOfStream,
    TogglePlay,
    Skip(f64),
    StepFrame(i8),
    SeekDrag(f64),
    SeekRelease,
    Volume(f64),
    ToggleMute,
    ToggleFullscreen,
    StageHover,
    ControlsHover(bool),
    Tick,
    ToggleTrim,
    ToggleInfo,
    InfoAnchor(iced::Size),
    Navigate(i32),
    Timeline(TimelineEvent),
    StartText(String),
    EndText(String),
    CommitStart,
    CommitEnd,
    ToggleExportMenu,
    SelectPreset(ExportPreset),
    Export,
    ExportTo(Option<PathBuf>),
    ExportProgress(Result<Progress, String>),
    ExportDone,
    SaveFrame,
    SaveFrameTo(f64, Option<PathBuf>),
    SaveFrameDone(Result<(), String>),
    AskDelete,
    DeleteChoice(DeleteChoice),
    ConfirmDelete,
    CancelDelete,
    DismissError,
    UpdateFound(Option<Update>),
    InstallUpdate,
    UpdateStarted(Result<(), String>),
    Key(keyboard::Event),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DeleteChoice {
    Delete,
    Cancel,
}

pub struct App {
    info: Option<VideoInfo>,
    video: Option<Video>,
    seeker: Option<media::Seeker>,
    load_id: u64,
    loading: bool,
    thumbnails: Vec<image::Handle>,
    /// Thumbnails are only generated once the trim panel is opened.
    thumbs_requested: bool,
    position: f64,
    seeking: bool,
    seeked_since_pause: bool,
    /// Playhead position before a trim handle drag; restored on release.
    trim_drag_origin: Option<f64>,
    volume: f64,
    muted: bool,
    fullscreen: bool,
    controls_until: Instant,
    controls_hovered: bool,

    trim_open: bool,
    info_open: bool,
    /// Width of the topbar items left of the Info button; positions the popover under it.
    info_anchor: f32,
    trim: TrimRange,
    start_text: Option<String>,
    end_text: Option<String>,

    export_menu: bool,
    preset: ExportPreset,
    exporting: Option<Progress>,

    delete_dialog: Option<DeleteChoice>,
    error: Option<String>,

    update: Option<Update>,
    updating: bool,
}

impl App {
    pub fn new() -> (Self, Task<Message>) {
        let app = Self {
            info: None,
            video: None,
            seeker: None,
            load_id: 0,
            loading: false,
            thumbnails: Vec::new(),
            thumbs_requested: false,
            position: 0.0,
            seeking: false,
            seeked_since_pause: false,
            trim_drag_origin: None,
            volume: 0.8,
            muted: false,
            fullscreen: false,
            controls_until: Instant::now(),
            controls_hovered: false,
            trim_open: false,
            info_open: false,
            info_anchor: 0.0,
            trim: TrimRange {
                start: 0.0,
                end: 0.0,
            },
            start_text: None,
            end_text: None,
            export_menu: false,
            preset: ExportPreset::Original,
            exporting: None,
            delete_dialog: None,
            error: None,
            update: None,
            updating: false,
        };
        let task = media::launch_file().map_or_else(Task::none, |p| Task::done(Message::Load(p)));
        let check = Task::perform(update::check(), Message::UpdateFound);
        (app, Task::batch([task, check]))
    }

    pub fn subscription(&self) -> Subscription<Message> {
        let keys = keyboard::listen().map(Message::Key);
        // Only needed to hide the controls again once the pointer rests.
        if self.video.is_some() && Instant::now() < self.controls_until {
            Subscription::batch([
                keys,
                iced::time::every(Duration::from_millis(250)).map(|_| Message::Tick),
            ])
        } else {
            keys
        }
    }

    fn duration(&self) -> f64 {
        self.info.as_ref().map_or(0.0, |i| i.duration_sec)
    }

    fn frame(&self) -> f64 {
        let fps = self.info.as_ref().map_or(0.0, |i| i.fps as f64);
        1.0 / if fps > 0.0 { fps } else { 30.0 }
    }

    /// Rounds to the start of the nearest frame; cuts between frames would
    /// leave a shortened (broken) frame at the edge of an export.
    fn snap(&self, sec: f64) -> f64 {
        snap_to_frame(sec, self.frame())
    }

    fn set_trim(&mut self, start: f64, end: f64) {
        let (frame, duration) = (self.frame(), self.duration());
        let end = self.snap(end).clamp(frame, duration);
        let start = self.snap(start).clamp(0.0, end - frame);
        self.trim = TrimRange { start, end };
    }

    /// Seeks to the frame at `sec`; with the trim panel open the playhead
    /// stays between the trim start and the last frame before the trim end.
    fn seek(&mut self, sec: f64) {
        let mut sec = self.snap(sec).clamp(0.0, self.duration());
        if self.trim_open {
            sec = sec.clamp(
                self.trim.start,
                (self.trim.end - self.frame()).max(self.trim.start),
            );
        }
        if let Some(seeker) = &self.seeker {
            // Aim at the middle of the frame: the exact start, rounded down to whole
            // nanoseconds, lies just before it and shows the previous frame.
            seeker.seek(sec + self.frame() / 2.0);
        }
        self.seeked_since_pause = true;
        self.position = sec;
    }

    fn pause(&mut self) {
        if let Some(video) = &mut self.video {
            if !video.paused() {
                video.set_paused(true);
                self.seeked_since_pause = false;
            }
        }
    }

    /// Time of the frame a step starts from. Right after pausing the pipeline still
    /// delivers one more frame and `position` lags; read the shown frame then. After a
    /// seek, `position` holds its target, which the screen may not show yet.
    fn step_origin(&self) -> f64 {
        match &self.video {
            Some(video) if video.paused() && !self.seeked_since_pause => video
                .frame_position()
                .map_or(self.position, |t| self.snap(t.as_secs_f64())),
            _ => self.position,
        }
    }

    fn show_controls(&mut self) {
        self.controls_until = Instant::now() + CONTROLS_HIDE_AFTER;
    }

    fn clear_video(&mut self) {
        self.load_id += 1;
        media::cancel_thumbnails();
        self.video = None;
        self.seeker = None;
        self.info = None;
        self.thumbnails.clear();
        self.thumbs_requested = false;
        self.position = 0.0;
        self.trim_open = false;
        self.info_open = false;
        self.export_menu = false;
    }

    pub fn update(&mut self, message: Message) -> Task<Message> {
        // rfd reports a missing portal as "cancelled", so check before opening a dialog.
        if matches!(
            message,
            Message::OpenFile | Message::Export | Message::SaveFrame
        ) {
            if let Err(e) = media::check_file_dialog() {
                self.error = Some(e);
                return Task::none();
            }
        }
        match message {
            Message::OpenFile => {
                return Task::perform(
                    rfd::AsyncFileDialog::new()
                        .add_filter("Video", media::VIDEO_EXTS)
                        .pick_file(),
                    |f| f.map_or(Message::Tick, |f| Message::Load(f.path().to_path_buf())),
                );
            }
            Message::Load(path) => {
                self.clear_video();
                self.loading = true;
                self.error = None;
                let id = self.load_id;
                return Task::perform(media::open(path), move |r| Message::Opened(id, r));
            }
            Message::Opened(id, result) if id == self.load_id => {
                self.loading = false;
                let (info, opened) = match result {
                    Ok(r) => r,
                    Err(e) => {
                        self.error = Some(e);
                        return Task::none();
                    }
                };
                match opened
                    .take()
                    .ok_or_else(|| "Video bereits übernommen".to_string())
                {
                    Ok((mut video, silent)) => {
                        if silent {
                            self.error =
                                Some("Keine Audioausgabe verfügbar. Wiedergabe ohne Ton.".into());
                        } else {
                            video.set_volume(self.volume);
                            video.set_muted(self.muted);
                        }
                        video.set_paused(false);
                        self.seeker = Some(media::Seeker::new(video.pipeline()));
                        self.video = Some(video);
                    }
                    Err(e) => {
                        self.error = Some(e);
                        return Task::none();
                    }
                }
                self.trim = TrimRange {
                    start: 0.0,
                    end: info.duration_sec,
                };
                self.show_controls();
                self.info = Some(info);
            }
            Message::Opened(..) => {}
            Message::Thumbnails(id, paths) if id == self.load_id => {
                self.thumbnails = paths.into_iter().map(image::Handle::from_path).collect();
            }
            Message::Thumbnails(..) => {}
            Message::NewFrame => {
                if let Some(video) = &self.video {
                    if !self.seeking {
                        self.position = video.position().as_secs_f64();
                    }
                }
                // Loop playback within the trimmed range while trim mode is active.
                if self.trim_open
                    && !self.seeking
                    && (self.position >= self.trim.end - 0.02
                        || self.position < self.trim.start - 0.05)
                {
                    let start = self.trim.start;
                    self.seek(start);
                }
            }
            Message::EndOfStream => {
                if let Some(video) = &mut self.video {
                    video.set_paused(true);
                }
                self.show_controls();
            }
            Message::TogglePlay => {
                if let Some(video) = &mut self.video {
                    if video.eos() {
                        // restart_stream clears the end-of-stream state but jumps to 0;
                        // continue from where the playhead was moved to instead.
                        let _ = video.restart_stream();
                        let pos = self.position;
                        if pos < self.duration() - self.frame() {
                            self.seek(pos);
                        }
                    } else if video.paused() {
                        video.set_paused(false);
                    } else {
                        self.pause();
                    }
                }
                self.show_controls();
            }
            Message::Skip(delta) => {
                let target = self.position + delta;
                self.seek(target);
                self.show_controls();
            }
            Message::StepFrame(dir) => {
                self.pause();
                let target = self.step_origin() + dir as f64 * self.frame();
                self.seek(target);
            }
            // Seeks on every move so the picture follows the handle.
            Message::SeekDrag(sec) => {
                self.seeking = true;
                self.seek(sec);
            }
            Message::SeekRelease => self.seeking = false,
            Message::Volume(v) => {
                self.volume = v;
                if v > 0.0 {
                    self.muted = false;
                }
                if let Some(video) = &mut self.video {
                    video.set_volume(v);
                    video.set_muted(self.muted);
                }
            }
            Message::ToggleMute => {
                self.muted = !self.muted;
                if let Some(video) = &mut self.video {
                    video.set_muted(self.muted);
                }
            }
            Message::ToggleFullscreen => {
                self.fullscreen = !self.fullscreen;
                let mode = if self.fullscreen {
                    window::Mode::Fullscreen
                } else {
                    window::Mode::Windowed
                };
                return window::latest().and_then(move |id| window::set_mode(id, mode));
            }
            Message::StageHover => self.show_controls(),
            Message::ControlsHover(h) => {
                self.controls_hovered = h;
                self.show_controls();
            }
            Message::Tick => {}
            Message::ToggleTrim => {
                self.trim_open = !self.trim_open;
                if let Some(info) = self
                    .info
                    .as_ref()
                    .filter(|_| self.trim_open && !self.thumbs_requested)
                {
                    self.thumbs_requested = true;
                    let id = self.load_id;
                    let thumbs =
                        media::thumbnails(info.path.clone(), info.duration_sec, THUMB_COUNT);
                    return Task::perform(thumbs, move |t| Message::Thumbnails(id, t));
                }
            }
            Message::ToggleInfo => self.info_open = !self.info_open,
            Message::InfoAnchor(size) => self.info_anchor = size.width,
            Message::Navigate(dir) => {
                let next = self
                    .info
                    .as_ref()
                    .and_then(|i| media::adjacent_video(&i.path, dir, &HashSet::new()));
                if let Some(path) = next {
                    return Task::done(Message::Load(path));
                }
            }
            // Show the frame under the dragged handle: the first frame for the
            // start, the last frame inside the range for the end.
            Message::Timeline(TimelineEvent::Trim(t)) => {
                self.trim_drag_origin.get_or_insert(self.position);
                self.seeking = true;
                let start_moved = t.start != self.trim.start;
                self.set_trim(t.start, t.end);
                let target = if start_moved {
                    self.trim.start
                } else {
                    self.trim.end - self.frame()
                };
                self.seek(target);
            }
            Message::Timeline(TimelineEvent::Seek(t)) => {
                self.seeking = true;
                self.seek(t);
            }
            // seek() clamps into the new range: an origin outside of it lands on
            // the first or last frame.
            Message::Timeline(TimelineEvent::Release) => {
                self.seeking = false;
                if let Some(origin) = self.trim_drag_origin.take() {
                    self.seek(origin);
                }
            }
            Message::StartText(s) => self.start_text = Some(s),
            Message::EndText(s) => self.end_text = Some(s),
            Message::CommitStart => {
                if let Some(v) = self.start_text.take().as_deref().and_then(parse_time) {
                    self.set_trim(v, self.trim.end);
                    self.seek(self.trim.start);
                }
            }
            Message::CommitEnd => {
                if let Some(v) = self.end_text.take().as_deref().and_then(parse_time) {
                    self.set_trim(self.trim.start, v);
                    self.seek(self.trim.end - self.frame());
                }
            }
            Message::ToggleExportMenu => self.export_menu = !self.export_menu,
            Message::SelectPreset(p) => self.preset = p,
            Message::Export => {
                let Some(info) = &self.info else {
                    return Task::none();
                };
                let (suffix, ext) = match self.preset {
                    ExportPreset::Original => (
                        "_trimmed",
                        if info.container_ext.is_empty() {
                            "mp4".into()
                        } else {
                            info.container_ext.clone()
                        },
                    ),
                    ExportPreset::DiscordNonNitro => ("_discord", "mp4".to_string()),
                };
                let stem = info
                    .path
                    .file_stem()
                    .map(|s| s.to_string_lossy().into_owned())
                    .unwrap_or_default();
                let mut dialog = rfd::AsyncFileDialog::new()
                    .set_file_name(format!("{stem}{suffix}.{ext}"))
                    .add_filter(ext.to_uppercase(), &[ext.as_str()]);
                if let Some(dir) = info.path.parent() {
                    dialog = dialog.set_directory(dir);
                }
                return Task::perform(dialog.save_file(), |f| {
                    Message::ExportTo(f.map(|f| f.path().to_path_buf()))
                });
            }
            Message::ExportTo(Some(dest)) => {
                let Some(info) = &self.info else {
                    return Task::none();
                };
                self.exporting = Some(Progress::default());
                self.error = None;
                let stream = media::export(
                    info.path.clone(),
                    dest,
                    self.trim.start,
                    self.trim.end,
                    self.preset,
                );
                return Task::run(stream, Message::ExportProgress)
                    .chain(Task::done(Message::ExportDone));
            }
            Message::ExportTo(None) => {}
            Message::ExportProgress(Ok(p)) => self.exporting = Some(p),
            Message::ExportProgress(Err(e)) => {
                self.error = Some(e);
                self.exporting = None;
            }
            Message::ExportDone => {
                if self.exporting.take().is_some() {
                    self.export_menu = false;
                }
            }
            Message::SaveFrame => {
                let Some(info) = &self.info else {
                    return Task::none();
                };
                let stem = info
                    .path
                    .file_stem()
                    .map(|s| s.to_string_lossy().into_owned())
                    .unwrap_or_default();
                let mut dialog = rfd::AsyncFileDialog::new()
                    .set_file_name(format!("{stem}_frame.png"))
                    .add_filter("PNG", &["png"]);
                if let Some(dir) = info.path.parent() {
                    dialog = dialog.set_directory(dir);
                }
                let at = self.position;
                return Task::perform(dialog.save_file(), move |f| {
                    Message::SaveFrameTo(at, f.map(|f| f.path().to_path_buf()))
                });
            }
            Message::SaveFrameTo(at, Some(dest)) => {
                let Some(info) = &self.info else {
                    return Task::none();
                };
                return Task::perform(
                    media::save_frame(info.path.clone(), at, dest),
                    Message::SaveFrameDone,
                );
            }
            Message::SaveFrameTo(_, None) | Message::SaveFrameDone(Ok(())) => {}
            Message::SaveFrameDone(Err(e)) => self.error = Some(e),
            Message::AskDelete => {
                if self.info.is_some() && self.exporting.is_none() {
                    self.delete_dialog = Some(DeleteChoice::Delete);
                }
            }
            Message::DeleteChoice(c) => self.delete_dialog = Some(c),
            Message::CancelDelete => self.delete_dialog = None,
            Message::ConfirmDelete => {
                self.delete_dialog = None;
                let Some(path) = self.info.as_ref().map(|i| i.path.clone()) else {
                    return Task::none();
                };
                let next = media::adjacent_video(
                    &path,
                    1,
                    &HashSet::from([path.canonicalize().unwrap_or(path.clone())]),
                );
                // Dropping the pipeline releases the file handle (required on Windows).
                self.clear_video();
                if let Err(e) = media::move_to_trash(&path) {
                    self.error = Some(e);
                    return Task::done(Message::Load(path));
                }
                if let Some(next) = next {
                    return Task::done(Message::Load(next));
                }
            }
            Message::DismissError => self.error = None,
            Message::UpdateFound(found) => self.update = found,
            Message::InstallUpdate => {
                let Some(up) = &self.update else {
                    return Task::none();
                };
                match up.installer.clone() {
                    Some((url, sha256)) if !self.updating => {
                        self.updating = true;
                        return Task::perform(update::install(url, sha256), Message::UpdateStarted);
                    }
                    Some(_) => {}
                    None => {
                        if let Err(e) = update::open_page(&up.page) {
                            self.error = Some(e);
                        }
                    }
                }
            }
            // The installer replaces the files, so this instance has to go.
            Message::UpdateStarted(Ok(())) => return iced::exit(),
            Message::UpdateStarted(Err(e)) => {
                self.updating = false;
                self.error = Some(e);
            }
            Message::Key(event) => return self.on_key(event),
        }
        Task::none()
    }

    fn on_key(&mut self, event: keyboard::Event) -> Task<Message> {
        let keyboard::Event::KeyPressed { key, .. } = event else {
            return Task::none();
        };
        let msg = if let Some(choice) = self.delete_dialog {
            match key.as_ref() {
                Key::Named(Named::Escape) => Message::CancelDelete,
                Key::Named(Named::ArrowLeft) => Message::DeleteChoice(DeleteChoice::Cancel),
                Key::Named(Named::ArrowRight) => Message::DeleteChoice(DeleteChoice::Delete),
                Key::Named(Named::Enter) if choice == DeleteChoice::Delete => {
                    Message::ConfirmDelete
                }
                Key::Named(Named::Enter) => Message::CancelDelete,
                _ => return Task::none(),
            }
        } else {
            match key.as_ref() {
                Key::Named(Named::Space) => Message::TogglePlay,
                Key::Named(Named::ArrowLeft) => Message::Skip(-5.0),
                Key::Named(Named::ArrowRight) => Message::Skip(5.0),
                Key::Character(",") => Message::StepFrame(-1),
                Key::Character(".") => Message::StepFrame(1),
                Key::Named(Named::Delete) => Message::AskDelete,
                Key::Named(Named::Escape) if self.fullscreen => Message::ToggleFullscreen,
                Key::Named(Named::F11) => Message::ToggleFullscreen,
                _ => return Task::none(),
            }
        };
        self.update(msg)
    }

    // ---------- View ----------

    pub fn view(&self) -> Element<'_, Message> {
        let body: Element<_> = match (&self.video, &self.info) {
            (Some(video), Some(info)) => {
                // The video runs edge to edge; only the trim panel keeps a margin.
                let mut col = column![self.stage(video)];
                if self.trim_open && !self.fullscreen {
                    col = col.push(container(self.trim_panel(info)).padding(16));
                }
                col.into()
            }
            _ if self.loading => center(text("Video wird geöffnet …").size(15).color(TX_3)).into(),
            _ => self.empty_state(),
        };

        let mut layers = stack![container(body).width(Length::Fill).height(Length::Fill)];
        // Popovers close on any click outside of them, like the old web UI.
        let dismiss =
            |msg| mouse_area(space().width(Length::Fill).height(Length::Fill)).on_press(msg);
        if self.info_open && !self.fullscreen {
            if let Some(info) = &self.info {
                layers = layers.push(dismiss(Message::ToggleInfo));
                // 16 = topbar padding, 2 = row spacing before the Info button.
                let under_button = iced::Padding {
                    top: 4.0,
                    left: 16.0 + self.info_anchor + 2.0,
                    ..Default::default()
                };
                layers = layers.push(container(info_popover(info)).padding(under_button));
            }
        }
        if self.export_menu && self.trim_open && !self.fullscreen {
            layers = layers.push(dismiss(Message::ToggleExportMenu));
            let above_panel = iced::Padding {
                right: 32.0,
                bottom: 16.0 + TRIM_PANEL_H + 8.0,
                ..Default::default()
            };
            layers = layers.push(
                container(opaque(self.export_menu_view()))
                    .align_right(Length::Fill)
                    .align_bottom(Length::Fill)
                    .padding(above_panel),
            );
        }
        if let Some(err) = &self.error {
            let t = button(text(err).size(14))
                .on_press(Message::DismissError)
                .padding([12, 16])
                .style(|_, _| button::Style {
                    text_color: TX,
                    ..Default::default()
                });
            layers = layers.push(
                container(container(t).style(theme::toast).max_width(640))
                    .center_x(Length::Fill)
                    .padding(24),
            );
        }

        let page = if self.fullscreen {
            column![layers]
        } else {
            column![self.topbar(), layers]
        };
        let mut root = stack![container(page)
            .style(theme::page)
            .width(Length::Fill)
            .height(Length::Fill)];
        if let (Some(choice), Some(info)) = (self.delete_dialog, &self.info) {
            root = root.push(delete_dialog(choice, &info.file_name));
        }
        root.into()
    }

    fn topbar(&self) -> Element<'_, Message> {
        let has = self.info.is_some();
        let tab = |ic: Icon, label: &'static str, active: bool, msg: Message, enabled: bool| {
            let color = if !enabled {
                TX_3.scale_alpha(0.55)
            } else if active {
                TX
            } else {
                TX_2
            };
            let content = row![icon(ic, 16.0, color), text(label).size(14)]
                .spacing(8)
                .align_y(Alignment::Center);
            button(content)
                .padding([7, 12])
                .style(theme::tab(active))
                .on_press_maybe(enabled.then_some(msg))
        };
        let icon_tab = |ic: Icon, label: &'static str, msg: Message, danger: bool| {
            let color = if has { TX_2 } else { TX_3.scale_alpha(0.55) };
            let b = button(icon(ic, 16.0, color))
                .padding(8)
                .on_press_maybe(has.then_some(msg));
            let b = if danger {
                b.style(theme::tab_danger)
            } else {
                b.style(theme::tab(false))
            };
            tip(b, label, tooltip::Position::Bottom)
        };

        let brand = row![
            text("Re").size(17).font(SEMIBOLD).color(TX),
            text("Video").size(17).font(SEMIBOLD).color(A_FILL)
        ];

        let before_info = row![
            brand,
            space::horizontal().width(12),
            tab(Icon::Folder, "Datei öffnen", false, Message::OpenFile, true),
            tab(
                Icon::Scissors,
                "Trim",
                self.trim_open,
                Message::ToggleTrim,
                has
            ),
        ]
        .spacing(2)
        .align_y(Alignment::Center);

        let bar = row![
            sensor(before_info)
                .on_show(Message::InfoAnchor)
                .on_resize(Message::InfoAnchor),
            tab(Icon::Info, "Info", self.info_open, Message::ToggleInfo, has),
            tab(
                Icon::Camera,
                "Frame speichern",
                false,
                Message::SaveFrame,
                has
            ),
            icon_tab(
                Icon::SkipBack,
                "Vorheriges Video",
                Message::Navigate(-1),
                false
            ),
            icon_tab(Icon::SkipFwd, "Nächstes Video", Message::Navigate(1), false),
            icon_tab(
                Icon::Trash,
                "Video löschen (Entf)",
                Message::AskDelete,
                true
            ),
            space::horizontal(),
        ]
        .spacing(2)
        .align_y(Alignment::Center);
        let bar = match &self.update {
            Some(up) => {
                let (label, hint) = match (&up.installer, self.updating) {
                    (Some(_), true) => (
                        "Update wird geladen …".to_string(),
                        "ReVideo startet danach neu",
                    ),
                    (Some(_), false) => (
                        format!("Update {}", up.version),
                        "Herunterladen und installieren",
                    ),
                    (None, _) => (format!("Update {}", up.version), "Download-Seite öffnen"),
                };
                let b = button(text(label).size(14))
                    .padding([6, 14])
                    .style(theme::primary)
                    .on_press_maybe((!self.updating).then_some(Message::InstallUpdate));
                bar.push(tip(b, hint, tooltip::Position::Bottom))
            }
            None => bar,
        };

        container(bar)
            .padding([8, 16])
            .width(Length::Fill)
            .style(theme::topbar)
            .into()
    }

    fn stage<'a>(&'a self, video: &'a Video) -> Element<'a, Message> {
        let player = VideoPlayer::new(video)
            .width(Length::Fill)
            .height(Length::Fill)
            .content_fit(iced::ContentFit::Contain)
            .on_new_frame(Message::NewFrame)
            .on_end_of_stream(Message::EndOfStream);

        let player = mouse_area(
            // No backdrop: letterbox space shows the page surface instead of black
            // bars. Only fullscreen keeps black, as players usually do.
            container(player)
                .width(Length::Fill)
                .height(Length::Fill)
                .style(|_| container::Style {
                    background: self.fullscreen.then_some(iced::Color::BLACK.into()),
                    ..Default::default()
                }),
        )
        .on_press(Message::TogglePlay)
        .on_double_click(Message::ToggleFullscreen)
        .on_move(|_| Message::StageHover);

        let visible =
            self.controls_hovered || video.paused() || Instant::now() < self.controls_until;
        let mut layers = stack![player];
        if visible {
            // opaque: clicks on the bar's background must not reach the video (play/pause).
            let bar = opaque(
                mouse_area(self.controls(video))
                    .on_enter(Message::ControlsHover(true))
                    .on_exit(Message::ControlsHover(false)),
            );
            layers = layers.push(container(bar).align_bottom(Length::Fill).padding(16));
        }
        layers.into()
    }

    fn controls<'a>(&'a self, video: &'a Video) -> Element<'a, Message> {
        let ctrl = |ic: Icon, label: &'static str, msg: Message| {
            let b = button(icon(ic, 18.0, TX))
                .padding(8)
                .style(theme::ghost)
                .on_press(msg);
            tip(b, label, tooltip::Position::Top)
        };
        // While trimming the bar spans only the trim range, stretched to full width.
        let (from, to) = if self.trim_open {
            (self.trim.start, self.trim.end)
        } else {
            (0.0, self.duration())
        };
        let to = to.max(from + 0.01);

        let seek = slider(from..=to, self.position.clamp(from, to), Message::SeekDrag)
            .step(0.001)
            .on_release(Message::SeekRelease)
            .style(theme::seek_slider);

        let play_icon = if video.paused() || video.eos() {
            Icon::Play
        } else {
            Icon::Pause
        };
        let play = button(icon(play_icon, 20.0, iced::Color::WHITE))
            .padding(10)
            .style(theme::primary)
            .on_press(Message::TogglePlay);

        let center_group = row![
            ctrl(
                Icon::FrameBack,
                "Vorheriger Frame (,)",
                Message::StepFrame(-1)
            ),
            ctrl(Icon::SkipBack, "5 s zurück (←)", Message::Skip(-5.0)),
            play,
            ctrl(Icon::SkipFwd, "5 s vor (→)", Message::Skip(5.0)),
            ctrl(Icon::FrameFwd, "Nächster Frame (.)", Message::StepFrame(1)),
        ]
        .spacing(4)
        .align_y(Alignment::Center);

        let time = row![
            text(format_time(self.position, self.trim_open))
                .font(MONO)
                .size(13)
                .color(TX),
            text(" / ").font(MONO).size(13).color(TX_3),
            text(format_time(to, self.trim_open))
                .font(MONO)
                .size(13)
                .color(TX_3),
        ];
        let mute_icon = if self.muted || self.volume == 0.0 {
            Icon::Mute
        } else {
            Icon::Volume
        };
        let volume = slider(
            0.0..=1.0,
            if self.muted { 0.0 } else { self.volume },
            Message::Volume,
        )
        .step(0.01)
        .width(96)
        .style(theme::seek_slider);

        let right = row![
            time,
            space::horizontal().width(8),
            ctrl(mute_icon, "Ton an/aus", Message::ToggleMute),
            volume,
            ctrl(
                Icon::Fullscreen,
                "Vollbild (F11)",
                Message::ToggleFullscreen
            ),
        ]
        .spacing(6)
        .align_y(Alignment::Center);

        let controls_row = row![
            space::horizontal().width(Length::FillPortion(1)),
            center_group,
            container(right).align_right(Length::FillPortion(1)),
        ]
        .align_y(Alignment::Center);

        container(column![seek, controls_row].spacing(6))
            .padding([10, 14])
            .style(theme::controls)
            .into()
    }

    fn trim_panel<'a>(&'a self, info: &'a VideoInfo) -> Element<'a, Message> {
        let pill = |value: &Option<String>,
                    sec: f64,
                    on_input: fn(String) -> Message,
                    on_submit: Message| {
            let shown = value.clone().unwrap_or_else(|| format_time(sec, true));
            text_input("", &shown)
                .on_input(on_input)
                .on_submit(on_submit)
                .font(MONO)
                .size(13)
                .width(120)
                .padding([5, 10])
                .style(theme::time_input)
        };

        let pct = self.exporting.as_ref().map_or(0.0, |p| p.percent);
        let export_label = if self.exporting.is_some() {
            format!("Exportiere … {pct:.0} %")
        } else {
            "Export".into()
        };
        let export_btn = button(
            row![icon(Icon::Upload, 16.0, TX), text(export_label).size(14)]
                .spacing(8)
                .align_y(Alignment::Center),
        )
        .padding([7, 14])
        .style(theme::secondary(false))
        .on_press(Message::ToggleExportMenu);

        let header = row![
            text("Trim").size(15).font(SEMIBOLD).color(TX),
            space::horizontal().width(16),
            pill(
                &self.start_text,
                self.trim.start,
                Message::StartText,
                Message::CommitStart
            ),
            text("→").color(TX_3),
            pill(
                &self.end_text,
                self.trim.end,
                Message::EndText,
                Message::CommitEnd
            ),
            text("•").size(15).color(TX_3),
            text(format_time(self.trim.end - self.trim.start, true))
                .font(MONO)
                .size(13)
                .color(TX),
            text("Länge").size(13).color(TX_3),
            space::horizontal(),
            export_btn,
        ]
        .spacing(10)
        .align_y(Alignment::Center);

        let timeline = canvas(Timeline {
            duration: info.duration_sec,
            trim: self.trim,
            position: self.position,
        })
        .width(Length::Fill)
        .height(84);

        // Separate stack layer: within one layer iced draws images above the
        // canvas geometry, which would hide the shading and handles.
        let strip = row(self.thumbnails.iter().map(|h| {
            image(h.clone())
                .width(Length::Fill)
                .height(Length::Fill)
                .content_fit(iced::ContentFit::Cover)
                .into()
        }));
        let strip = container(
            container(strip)
                .width(Length::Fill)
                .height(Length::Fill)
                .clip(true)
                .style(|_| container::Style {
                    background: Some(SF.into()),
                    border: iced::border::rounded(R_1),
                    ..Default::default()
                }),
        )
        .padding(iced::Padding {
            top: TICKS_H,
            left: HANDLE_W,
            right: HANDLE_W,
            bottom: 0.0,
        })
        .height(84);
        let track = stack![strip, iced::Element::from(timeline).map(Message::Timeline)];

        container(column![header, track].spacing(12))
            .padding(16)
            .height(TRIM_PANEL_H)
            .style(theme::panel)
            .into()
    }

    fn export_menu_view(&self) -> Element<'_, Message> {
        let busy = self.exporting.is_some();
        let option = |preset: ExportPreset, label: &'static str, desc: &'static str| {
            let active = self.preset == preset;
            button(
                column![
                    text(label).size(14).font(SEMIBOLD).color(TX),
                    text(desc).size(12.5).color(TX_3)
                ]
                .spacing(2),
            )
            .width(Length::Fill)
            .padding([9, 12])
            .style(theme::preset_row(active))
            .on_press_maybe((!busy).then_some(Message::SelectPreset(preset)))
        };

        let mut col = column![
            text("Export-Vorlage").size(13).font(SEMIBOLD).color(TX_2),
            option(
                ExportPreset::Original,
                "Original",
                "Quell-Codec & Container, verlustfreier Schnell-Trim"
            ),
            option(
                ExportPreset::DiscordNonNitro,
                "Discord (≤ 10 MB)",
                "Max. Qualität unter 10 MB • 1080p • 30 fps • 2-Pass"
            ),
        ]
        .spacing(6)
        .width(340);

        if let Some(p) = &self.exporting {
            let mut meta = row![text(format!("{:.0} %", p.percent))
                .font(MONO)
                .size(12)
                .color(TX_2)]
            .spacing(12);
            if !p.speed.is_empty() {
                meta = meta.push(text(p.speed.clone()).font(MONO).size(12).color(TX_3));
            }
            if p.eta_sec > 0.0 {
                meta = meta.push(
                    text(format!("ETA {}", format_time(p.eta_sec, false)))
                        .font(MONO)
                        .size(12)
                        .color(TX_3),
                );
            }
            col = col.push(
                column![
                    iced::widget::progress_bar(0.0..=100.0, p.percent as f32)
                        .girth(6)
                        .style(|_| iced::widget::progress_bar::Style {
                            background: SF.into(),
                            bar: A_FILL.into(),
                            border: iced::border::rounded(3.0),
                        }),
                    meta
                ]
                .spacing(6),
            );
        }

        let label = if busy {
            "Exportiere …"
        } else {
            "Exportieren"
        };
        col = col.push(
            button(
                row![
                    icon(Icon::Upload, 16.0, iced::Color::WHITE),
                    text(label).size(14)
                ]
                .spacing(8)
                .align_y(Alignment::Center),
            )
            .width(Length::Fill)
            .padding([8, 14])
            .style(theme::primary)
            .on_press_maybe((!busy).then_some(Message::Export)),
        );
        container(col).padding(14).style(theme::sheet).into()
    }

    fn empty_state(&self) -> Element<'_, Message> {
        let open = button(
            row![
                icon(Icon::Folder, 18.0, iced::Color::WHITE),
                text("Datei öffnen").size(15)
            ]
            .spacing(8)
            .align_y(Alignment::Center),
        )
        .padding([10, 18])
        .style(theme::primary)
        .on_press(Message::OpenFile);
        center(
            column![
                text("Nichts geladen.").size(32).font(SEMIBOLD).color(TX),
                text("Video öffnen, um zu starten.").size(17).color(TX_2),
                space::vertical().height(12),
                open,
            ]
            .spacing(6)
            .align_x(Alignment::Center),
        )
        .into()
    }
}

fn info_popover(info: &VideoInfo) -> Element<'_, Message> {
    let line = |ic: Icon, value: String| {
        row![icon(ic, 16.0, TX_3), text(value).size(14).color(TX)]
            .spacing(10)
            .align_y(Alignment::Center)
    };
    let kv = |k: &'static str, v: String| {
        row![
            text(k).size(13).color(TX_3),
            space::horizontal(),
            text(v).size(13).font(MONO).color(TX)
        ]
    };
    let col = column![
        row![
            text("Videodetails").size(13).font(SEMIBOLD).color(TX_2),
            space::horizontal(),
            button(icon(Icon::Close, 14.0, TX_2))
                .padding(4)
                .style(theme::ghost)
                .on_press(Message::ToggleInfo),
        ]
        .align_y(Alignment::Center),
        line(Icon::File, info.file_name.clone()),
        line(
            Icon::Frame,
            format!(
                "{} × {} ({})",
                info.width,
                info.height,
                aspect_ratio(info.width, info.height)
            )
        ),
        line(Icon::Clock, format_time(info.duration_sec, false)),
        line(Icon::Drive, format_bytes(info.size_bytes)),
        iced::widget::rule::horizontal(1).style(|_| iced::widget::rule::Style {
            color: LN_SOFT,
            radius: 0.0.into(),
            fill_mode: iced::widget::rule::FillMode::Full,
            snap: true
        }),
        kv("Codec", info.codec.to_uppercase()),
        kv("Container", format!(".{}", info.container_ext)),
        kv("Framerate", format!("{:.2} fps", info.fps)),
        kv("Audio", if info.has_audio { "Ja" } else { "Nein" }.into()),
    ]
    .spacing(10)
    .width(320);
    opaque(container(col).padding(16).style(theme::sheet))
}

fn snap_to_frame(sec: f64, frame: f64) -> f64 {
    (sec / frame).round() * frame
}

fn tip<'a>(
    content: impl Into<Element<'a, Message>>,
    label: &'a str,
    position: tooltip::Position,
) -> Element<'a, Message> {
    let bubble = container(text(label).size(13).color(TX))
        .padding([4, 8])
        .style(theme::tooltip);
    tooltip(content, bubble, position).gap(6).into()
}

fn delete_dialog(choice: DeleteChoice, file_name: &str) -> Element<'_, Message> {
    let del = button(text("Löschen").size(14))
        .padding([8, 18])
        .style(theme::danger(choice == DeleteChoice::Delete))
        .on_press(Message::ConfirmDelete);
    let cancel = button(text("Abbrechen").size(14))
        .padding([8, 18])
        .style(theme::secondary(choice == DeleteChoice::Cancel))
        .on_press(Message::CancelDelete);
    let dialog = container(
        column![
            text("Video löschen?").size(19).font(SEMIBOLD).color(TX),
            text(format!("„{file_name}“ in den Papierkorb verschieben?"))
                .size(15)
                .color(TX_2),
            space::vertical().height(8),
            row![space::horizontal(), cancel, del].spacing(10),
        ]
        .spacing(8)
        .width(420),
    )
    .padding(22)
    .style(theme::sheet);

    opaque(mouse_area(center(opaque(dialog)).style(theme::scrim)).on_press(Message::CancelDelete))
}

#[cfg(test)]
mod tests {
    use super::snap_to_frame;

    #[test]
    fn snaps_to_nearest_frame_start() {
        let frame = 1.0 / 30.0;
        assert!((snap_to_frame(0.222, frame) - 7.0 * frame).abs() < 1e-9);
        assert!((snap_to_frame(0.856, frame) - 26.0 * frame).abs() < 1e-9);
        assert_eq!(snap_to_frame(0.0, frame), 0.0);
        let ntsc = 1001.0 / 30000.0;
        assert!((snap_to_frame(10.0, ntsc) - 300.0 * ntsc).abs() < 1e-9);
    }
}
