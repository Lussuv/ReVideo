use crate::ffmpeg;
use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

pub const VIDEO_EXTS: &[&str] = &[
    "mp4", "mkv", "mov", "avi", "webm", "flv", "wmv", "m4v", "mpg", "mpeg", "ts", "3gp",
];

#[derive(Debug, Clone)]
pub struct VideoInfo {
    pub path: PathBuf,
    pub file_name: String,
    pub duration_sec: f64,
    pub width: u32,
    pub height: u32,
    pub size_bytes: u64,
    pub fps: f32,
    pub has_audio: bool,
    pub codec: String,
    pub container_ext: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExportPreset {
    Original,
    DiscordNonNitro,
}

#[derive(Debug, Clone, Default)]
pub struct Progress {
    pub percent: f64,
    pub speed: String,
    pub eta_sec: f64,
}

pub async fn video_info(path: PathBuf) -> Result<VideoInfo, String> {
    let probe = ffmpeg::probe(&path).await?;
    let video = probe.video_stream().ok_or("keine Videospur gefunden")?;
    let fps_str = video
        .avg_frame_rate
        .as_deref()
        .or(video.r_frame_rate.as_deref())
        .unwrap_or("30/1");

    Ok(VideoInfo {
        file_name: path
            .file_name()
            .map(|s| s.to_string_lossy().into_owned())
            .unwrap_or_default(),
        duration_sec: probe.duration(),
        width: video.width.unwrap_or(0),
        height: video.height.unwrap_or(0),
        size_bytes: std::fs::metadata(&path).map(|m| m.len()).unwrap_or(0),
        fps: ffmpeg::parse_fps(fps_str),
        has_audio: probe.has_audio(),
        codec: video.codec_name.clone().unwrap_or_else(|| "unknown".into()),
        container_ext: extension(&path),
        path,
    })
}

pub fn extension(path: &Path) -> String {
    path.extension()
        .and_then(|s| s.to_str())
        .map(str::to_lowercase)
        .unwrap_or_default()
}

pub fn is_video_file(path: &Path) -> bool {
    VIDEO_EXTS.contains(&extension(path).as_str())
}

/// First video file passed on the command line (file association / "Open with").
pub fn launch_file() -> Option<PathBuf> {
    std::env::args_os()
        .skip(1)
        .map(PathBuf::from)
        .find(|p| p.is_file() && is_video_file(p))
}

/// Next/previous video in the same folder (alphabetical, wrapping), skipping `excluded`.
pub fn adjacent_video(
    current: &Path,
    direction: i32,
    excluded: &HashSet<PathBuf>,
) -> Option<PathBuf> {
    let dir = current.parent()?;
    let mut videos: Vec<PathBuf> = std::fs::read_dir(dir)
        .ok()?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.is_file() && is_video_file(p))
        .collect();
    videos.sort_by_key(|p| {
        p.file_name()
            .map(|n| n.to_string_lossy().to_lowercase())
            .unwrap_or_default()
    });

    let canon = |p: &Path| p.canonicalize().unwrap_or_else(|_| p.to_path_buf());
    let current = canon(current);
    let index = videos.iter().position(|p| canon(p) == current)?;
    let len = videos.len();
    (1..len)
        .map(|offset| {
            if direction < 0 {
                (index + len - offset) % len
            } else {
                (index + offset) % len
            }
        })
        .map(|i| &videos[i])
        .find(|p| !excluded.contains(&canon(p)))
        .cloned()
}

/// Opens `path` for playback. Without a usable audio device (no output on
/// Windows, sandbox without PulseAudio) playbin refuses to start, so the same
/// pipeline is retried with a silent audio sink; the bool reports that fallback.
pub fn open_video(path: &Path) -> Result<(iced_video_player::Video, bool), String> {
    use gstreamer::prelude::*;
    let url = url::Url::from_file_path(path).map_err(|()| "Ungültiger Dateipfad".to_string())?;
    let first_err = match iced_video_player::Video::new(&url) {
        Ok(video) => return Ok((video, false)),
        Err(e) => e.to_string(),
    };

    let silent = || -> Result<iced_video_player::Video, Box<dyn std::error::Error>> {
        // Same pipeline as `Video::new`, plus `audio-sink=fakesink`.
        let pipeline = gstreamer::parse::launch(&format!(
            "playbin uri=\"{url}\" audio-sink=\"fakesink sync=true\" video-sink=\"videoscale ! videoconvert ! appsink name=iced_video drop=true caps=video/x-raw,format=NV12,pixel-aspect-ratio=1/1\""
        ))?
        .downcast::<gstreamer::Pipeline>()
        .map_err(|_| "kein Pipeline-Element")?;
        let sink_bin = pipeline
            .property::<gstreamer::Element>("video-sink")
            .downcast::<gstreamer::Bin>()
            .map_err(|_| "kein Bin")?;
        let sink = sink_bin
            .by_name("iced_video")
            .ok_or("appsink fehlt")?
            .downcast::<gstreamer_app::AppSink>()
            .map_err(|_| "kein AppSink")?;
        Ok(iced_video_player::Video::from_gst_pipeline(
            pipeline, sink, None,
        )?)
    };
    silent()
        .map(|v| (v, true))
        .map_err(|_| format!("Wiedergabe nicht möglich: {first_err}"))
}

/// On Linux the file dialog runs through xdg-desktop-portal on the session bus.
#[cfg(target_os = "linux")]
pub fn check_file_dialog() -> Result<(), String> {
    const PORTAL: &str = "org.freedesktop.portal.Desktop";
    let available = || -> zbus::Result<bool> {
        let conn = zbus::blocking::Connection::session()?;
        let dbus = zbus::blocking::fdo::DBusProxy::new(&conn)?;
        Ok(dbus.name_has_owner(PORTAL.try_into()?)?
            || dbus
                .list_activatable_names()?
                .iter()
                .any(|n| n.as_str() == PORTAL))
    };
    match available() {
        Ok(true) => Ok(()),
        _ => Err("Kein Datei-Dialog verfügbar: xdg-desktop-portal läuft nicht.".into()),
    }
}

#[cfg(not(target_os = "linux"))]
pub fn check_file_dialog() -> Result<(), String> {
    Ok(())
}

/// Seeks on a background thread. A flushing, frame-accurate seek blocks until
/// the decoder has reached the target; doing that on the UI thread made
/// dragging stutter. Targets that pile up meanwhile are skipped, only the
/// newest one is executed.
pub struct Seeker(std::sync::mpsc::Sender<f64>);

impl Seeker {
    pub fn new(pipeline: gstreamer::Pipeline) -> Self {
        use gstreamer::prelude::*;
        let (tx, rx) = std::sync::mpsc::channel::<f64>();
        std::thread::spawn(move || {
            while let Ok(mut target) = rx.recv() {
                while let Ok(newer) = rx.try_recv() {
                    target = newer;
                }
                let _ = pipeline.seek_simple(
                    gstreamer::SeekFlags::FLUSH | gstreamer::SeekFlags::ACCURATE,
                    gstreamer::ClockTime::from_nseconds((target * 1e9) as u64),
                );
            }
        });
        Self(tx)
    }

    pub fn seek(&self, sec: f64) {
        let _ = self.0.send(sec);
    }
}

pub fn move_to_trash(path: &Path) -> Result<(), String> {
    #[cfg(target_os = "linux")]
    if Path::new("/.flatpak-info").exists() {
        // Inside the sandbox XDG_DATA_HOME points into ~/.var/app, so the trash
        // crate would hide files in a private trash; the portal uses the real one.
        return portal_trash(path).map_err(|e| format!("Papierkorb fehlgeschlagen: {e}"));
    }
    trash::delete(path).map_err(|e| format!("Papierkorb fehlgeschlagen: {e}"))
}

#[cfg(target_os = "linux")]
fn portal_trash(path: &Path) -> Result<(), Box<dyn std::error::Error>> {
    use std::os::fd::AsFd;
    let file = std::fs::File::open(path)?;
    let conn = zbus::blocking::Connection::session()?;
    let reply = conn.call_method(
        Some("org.freedesktop.portal.Desktop"),
        "/org/freedesktop/portal/desktop",
        Some("org.freedesktop.portal.Trash"),
        "TrashFile",
        &(zbus::zvariant::Fd::from(file.as_fd()),),
    )?;
    match reply.body().deserialize::<u32>()? {
        1 => Ok(()),
        _ => Err("Portal hat abgelehnt".into()),
    }
}

pub fn export(
    input: PathBuf,
    output: PathBuf,
    start_sec: f64,
    end_sec: f64,
    preset: ExportPreset,
) -> impl iced::futures::Stream<Item = Result<Progress, String>> {
    iced::stream::try_channel(64, async move |mut tx| {
        if end_sec <= start_sec {
            return Err("Ende muss nach dem Start liegen".to_string());
        }
        let duration = end_sec - start_sec;
        let duration_us = (duration * 1_000_000.0) as u64;
        let report = |offset: f64, scale: f64| {
            let mut tx = tx.clone();
            move |out_us, speed: &str| {
                let _ = tx.try_send(progress(out_us, speed, duration_us, offset, scale));
            }
        };
        match preset {
            ExportPreset::Original => {
                run_original(&input, &output, start_sec, duration, report(0.0, 100.0)).await?
            }
            ExportPreset::DiscordNonNitro => {
                run_discord(
                    &input,
                    &output,
                    start_sec,
                    duration,
                    report(0.0, 50.0),
                    report(50.0, 50.0),
                )
                .await?
            }
        }
        let _ = tx.try_send(Progress {
            percent: 100.0,
            ..Default::default()
        });
        Ok(())
    })
}

/// Maps one ffmpeg run's 0..100% onto the slice `offset..offset+scale` (used for 2-pass).
fn progress(out_us: u64, speed: &str, duration_us: u64, offset: f64, scale: f64) -> Progress {
    let raw = if duration_us == 0 {
        0.0
    } else {
        (out_us as f64 / duration_us as f64 * 100.0).clamp(0.0, 100.0)
    };
    let factor: f64 = speed
        .trim_end_matches('x')
        .trim()
        .parse()
        .unwrap_or(1.0_f64)
        .max(0.05);
    Progress {
        percent: (offset + raw * scale / 100.0).clamp(0.0, 99.5),
        speed: speed.to_string(),
        eta_sec: duration_us.saturating_sub(out_us) as f64 / 1_000_000.0 / factor,
    }
}

fn secs(v: f64) -> String {
    format!("{v:.3}")
}
fn path_arg(p: &Path) -> String {
    p.to_string_lossy().into_owned()
}

/// Stream-copy trim — keeps original codecs and container, very fast, lossless.
/// Trim points snap to nearest preceding keyframe (small inaccuracy at start).
async fn run_original(
    input: &Path,
    output: &Path,
    start: f64,
    duration: f64,
    on_tick: impl FnMut(u64, &str),
) -> Result<(), String> {
    let args = vec![
        "-y".into(),
        "-ss".into(),
        secs(start),
        "-i".into(),
        path_arg(input),
        "-t".into(),
        secs(duration),
        "-c".into(),
        "copy".into(),
        "-avoid_negative_ts".into(),
        "make_zero".into(),
        path_arg(output),
    ];
    ffmpeg::run_ffmpeg_streaming(args, on_tick).await
}

/// Two-pass H.264 encoding targeting ≤ 10 MB output. Caps at 1080p / 30fps.
async fn run_discord(
    input: &Path,
    output: &Path,
    start: f64,
    duration: f64,
    on_tick_1: impl FnMut(u64, &str),
    on_tick_2: impl FnMut(u64, &str),
) -> Result<(), String> {
    let has_audio = ffmpeg::probe(input).await?.has_audio();

    // Target 9.3 MB so AAC headers / MP4 moov atom never push us over 10.
    let target_total_bits = 9_300_000.0 * 8.0;
    let audio_kbps = if has_audio { 96.0 } else { 0.0 };
    let video_bits = (target_total_bits - audio_kbps * 1000.0 * duration).max(50_000.0);
    let video_kbps = (video_bits / duration / 1000.0).max(50.0).floor() as u64;

    let video_filter =
        "scale='min(1920,iw)':'min(1080,ih)':force_original_aspect_ratio=decrease,fps=30";
    let passlog = ffmpeg::temp_subdir("2pass")
        .map_err(|e| e.to_string())?
        .join(format!("p-{}", stable_hash(&path_arg(input))));

    let common = |pass: &str| -> Vec<String> {
        vec![
            "-y".into(),
            "-ss".into(),
            secs(start),
            "-i".into(),
            path_arg(input),
            "-t".into(),
            secs(duration),
            "-c:v".into(),
            "libx264".into(),
            "-b:v".into(),
            format!("{video_kbps}k"),
            "-vf".into(),
            video_filter.into(),
            "-passlogfile".into(),
            path_arg(&passlog),
            "-pass".into(),
            pass.into(),
        ]
    };

    let mut pass1 = common("1");
    pass1.extend([
        "-an".into(),
        "-f".into(),
        "mp4".into(),
        if cfg!(windows) { "NUL" } else { "/dev/null" }.into(),
    ]);
    ffmpeg::run_ffmpeg_streaming(pass1, on_tick_1).await?;

    let mut pass2 = common("2");
    pass2.extend(["-pix_fmt".into(), "yuv420p".into()]);
    if has_audio {
        pass2.extend([
            "-c:a".into(),
            "aac".into(),
            "-b:a".into(),
            format!("{}k", audio_kbps as u64),
        ]);
    } else {
        pass2.push("-an".into());
    }
    pass2.extend(["-movflags".into(), "+faststart".into(), path_arg(output)]);
    ffmpeg::run_ffmpeg_streaming(pass2, on_tick_2).await?;

    // x264 writes <passlogfile>-0.log and -0.log.mbtree.
    let base = path_arg(&passlog);
    let _ = std::fs::remove_file(format!("{base}-0.log"));
    let _ = std::fs::remove_file(format!("{base}-0.log.mbtree"));
    Ok(())
}

/// Bumped by every thumbnail request. A running job compares its own id
/// against this between frames and bails out once a newer request arrives —
/// otherwise paging through a folder leaves one ffmpeg per visited file running.
static THUMB_GEN: AtomicU64 = AtomicU64::new(0);

pub fn cancel_thumbnails() {
    THUMB_GEN.fetch_add(1, Ordering::SeqCst);
}

pub async fn thumbnails(path: PathBuf, duration: f64, count: u32) -> Vec<PathBuf> {
    let generation = THUMB_GEN.fetch_add(1, Ordering::SeqCst) + 1;
    let id = stable_hash(&format!("{}|{}", path.display(), file_mtime(&path)));
    let Ok(dir) = ffmpeg::temp_subdir(&format!("thumbs-{id}")) else {
        return vec![];
    };

    let mut out = Vec::new();
    for i in 0..count {
        if THUMB_GEN.load(Ordering::SeqCst) != generation {
            return vec![];
        }
        let target = dir.join(format!("thumb_{:03}.jpg", i + 1));
        if !target.exists() {
            // `-ss` before `-i` seeks to the nearest keyframe instead of
            // decoding the whole file up to each thumbnail.
            let ts = duration * (i as f64 + 0.5) / count as f64;
            let args = vec![
                "-y".into(),
                "-v".into(),
                "error".into(),
                "-ss".into(),
                secs(ts),
                "-i".into(),
                path_arg(&path),
                "-frames:v".into(),
                "1".into(),
                "-vf".into(),
                "scale=160:-2".into(),
                "-q:v".into(),
                "5".into(),
                "-an".into(),
                "-sn".into(),
                path_arg(&target),
            ];
            // A seek past the last decodable frame yields nothing; skip that slot.
            if ffmpeg::run_ffmpeg(args).await.is_err() {
                continue;
            }
        }
        if target.exists() {
            out.push(target);
        }
    }
    out
}

/// Writes the frame at `time_sec` as PNG (input seeking is frame-accurate when re-encoding).
pub async fn save_frame(input: PathBuf, time_sec: f64, output: PathBuf) -> Result<(), String> {
    let args = vec![
        "-y".into(),
        "-v".into(),
        "error".into(),
        "-ss".into(),
        secs(time_sec),
        "-i".into(),
        path_arg(&input),
        "-frames:v".into(),
        "1".into(),
        "-update".into(),
        "1".into(),
        path_arg(&output),
    ];
    ffmpeg::run_ffmpeg(args).await
}

fn file_mtime(path: &Path) -> u64 {
    std::fs::metadata(path)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map_or(0, |d| d.as_secs())
}

fn stable_hash(s: &str) -> String {
    use std::hash::{DefaultHasher, Hash, Hasher};
    let mut h = DefaultHasher::new();
    s.hash(&mut h);
    format!("{:x}", h.finish())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn adjacent_wraps_and_skips_excluded() {
        let dir = std::env::temp_dir().join(format!("revideo-test-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        for name in ["a.mp4", "b.MKV", "c.txt", "d.webm"] {
            std::fs::write(dir.join(name), b"").unwrap();
        }
        let a = dir.join("a.mp4");
        let none = HashSet::new();
        assert_eq!(adjacent_video(&a, 1, &none), Some(dir.join("b.MKV")));
        assert_eq!(adjacent_video(&a, -1, &none), Some(dir.join("d.webm")));
        let excluded = HashSet::from([dir.join("b.MKV").canonicalize().unwrap()]);
        assert_eq!(adjacent_video(&a, 1, &excluded), Some(dir.join("d.webm")));
        std::fs::remove_dir_all(&dir).unwrap();
    }

    /// Needs ffmpeg/ffprobe on PATH: `cargo test -- --ignored`.
    #[test]
    #[ignore]
    fn export_presets_produce_files() {
        use iced::futures::StreamExt;
        let dir = std::env::temp_dir().join(format!("revideo-export-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let src = dir.join("src.mp4");
        let ok = std::process::Command::new("ffmpeg")
            .args([
                "-v",
                "error",
                "-y",
                "-f",
                "lavfi",
                "-i",
                "testsrc2=size=1920x1080:rate=60",
                "-f",
                "lavfi",
                "-i",
                "sine",
                "-t",
                "12",
            ])
            .args([
                "-c:v",
                "libx264",
                "-preset",
                "ultrafast",
                "-qp",
                "0",
                "-g",
                "30",
                "-c:a",
                "aac",
            ])
            .arg(&src)
            .status()
            .unwrap();
        assert!(ok.success());

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        for (preset, name) in [
            (ExportPreset::Original, "orig.mp4"),
            (ExportPreset::DiscordNonNitro, "discord.mp4"),
        ] {
            let out = dir.join(name);
            let items: Vec<_> =
                rt.block_on(export(src.clone(), out.clone(), 2.0, 10.0, preset).collect());
            assert!(items.iter().all(Result::is_ok), "{items:?}");
            assert_eq!(items.last().unwrap().as_ref().unwrap().percent, 100.0);
            let info = rt.block_on(video_info(out.clone())).unwrap();
            assert!(
                (info.duration_sec - 8.0).abs() < 0.6,
                "{name}: {}",
                info.duration_sec
            );
            if preset == ExportPreset::DiscordNonNitro {
                assert!(info.size_bytes <= 10_000_000, "{}", info.size_bytes);
                assert!(info.height <= 1080 && (info.fps - 30.0).abs() < 0.1);
            }
        }
        assert!(
            std::fs::metadata(&src).unwrap().len() > 10_000_000,
            "source must exceed the Discord limit"
        );
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn two_pass_progress_mapping() {
        assert_eq!(progress(500_000, "1x", 1_000_000, 0.0, 50.0).percent, 25.0);
        assert_eq!(progress(500_000, "1x", 1_000_000, 50.0, 50.0).percent, 75.0);
        assert_eq!(
            progress(2_000_000, "2x", 1_000_000, 50.0, 50.0).percent,
            99.5
        );
    }
}
