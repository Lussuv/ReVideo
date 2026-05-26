use crate::ffmpeg::{self, is_browser_playable, parse_fps, FfError, FfTick};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::path::{Path, PathBuf};
use tauri::{AppHandle, Emitter};

const VIDEO_EXTS: &[&str] = &[
    "mp4", "mkv", "mov", "avi", "webm", "flv", "wmv", "m4v", "mpg", "mpeg", "ts", "3gp",
];

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct VideoInfo {
    pub path: String,
    pub file_name: String,
    pub duration_sec: f64,
    pub width: u32,
    pub height: u32,
    pub size_bytes: u64,
    pub fps: f32,
    pub has_audio: bool,
    pub codec: String,
    pub container_ext: String,
    pub browser_playable: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlayableSource {
    pub path: String,
    pub is_proxy: bool,
}

#[derive(Debug, Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct ProgressPayload {
    pub phase: String,
    pub percent: f64,
    pub speed: String,
    pub eta_sec: f64,
}

#[derive(Debug, Deserialize)]
pub enum ExportPreset {
    #[serde(rename = "original")]
    Original,
    #[serde(rename = "discord_non_nitro")]
    DiscordNonNitro,
}

fn to_cmd_error(e: impl std::fmt::Display) -> String { e.to_string() }

#[tauri::command]
pub fn get_launch_file() -> Option<String> {
    std::env::args_os()
        .skip(1)
        .find_map(|arg| {
            let path = PathBuf::from(arg);
            let ext = path.extension()?.to_str()?.to_lowercase();
            if path.is_file() && VIDEO_EXTS.contains(&ext.as_str()) {
                Some(path.to_string_lossy().to_string())
            } else {
                None
            }
        })
}

#[tauri::command]
pub fn quit_app(app: AppHandle) {
    app.exit(0);
}

#[tauri::command]
pub fn get_adjacent_video(
    path: String,
    direction: i32,
    excluded_paths: Option<Vec<String>>,
) -> Result<Option<String>, String> {
    let current = PathBuf::from(&path);
    let dir = current.parent().ok_or_else(|| "video has no parent directory".to_string())?;
    let videos = video_files_in_dir(dir).map_err(to_cmd_error)?;
    if videos.len() <= 1 {
        return Ok(None);
    }

    let excluded: HashSet<PathBuf> = excluded_paths
        .unwrap_or_default()
        .into_iter()
        .map(PathBuf::from)
        .map(normalized_path)
        .collect();

    let current_canon = normalized_path(current);
    let index = videos
        .iter()
        .position(|p| normalized_path(p.clone()) == current_canon)
        .ok_or_else(|| "current video was not found in its folder".to_string())?;

    for offset in 1..videos.len() {
        let next_index = if direction < 0 {
            (index + videos.len() - offset) % videos.len()
        } else {
            (index + offset) % videos.len()
        };
        let candidate = &videos[next_index];
        if !excluded.contains(&normalized_path(candidate.clone())) {
            return Ok(Some(candidate.to_string_lossy().to_string()));
        }
    }

    Ok(None)
}

#[tauri::command]
pub fn delete_video_file(path: String) -> Result<(), String> {
    let path = PathBuf::from(path);
    if !path.is_file() {
        return Err("video file does not exist".into());
    }
    if !is_video_file(&path) {
        return Err("not a supported video file".into());
    }

    move_file_to_trash(&path)
}

#[tauri::command]
pub async fn get_video_info(app: AppHandle, path: String) -> Result<VideoInfo, String> {
    let probe = ffmpeg::probe(&app, &path).await.map_err(to_cmd_error)?;
    let video = probe.video_stream().ok_or_else(|| "no video stream".to_string())?;

    let duration = probe.format.duration
        .as_deref()
        .and_then(|s| s.parse::<f64>().ok())
        .unwrap_or(0.0);

    let size = std::fs::metadata(&path).map(|m| m.len()).unwrap_or(0);

    let file_name = Path::new(&path)
        .file_name()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_else(|| path.clone());

    let ext = Path::new(&path)
        .extension()
        .and_then(|s| s.to_str())
        .map(|s| s.to_lowercase())
        .unwrap_or_default();

    let fps_str = video.avg_frame_rate.as_deref()
        .or(video.r_frame_rate.as_deref())
        .unwrap_or("30/1");

    let playable = is_browser_playable(&probe, &path);

    Ok(VideoInfo {
        path: path.clone(),
        file_name,
        duration_sec: duration,
        width: video.width.unwrap_or(0),
        height: video.height.unwrap_or(0),
        size_bytes: size,
        fps: parse_fps(fps_str),
        has_audio: probe.has_audio(),
        codec: video.codec_name.clone().unwrap_or_else(|| "unknown".to_string()),
        container_ext: ext,
        browser_playable: playable,
    })
}

#[tauri::command]
pub async fn ensure_playable(
    app: AppHandle,
    path: String,
    force_proxy: Option<bool>,
) -> Result<PlayableSource, String> {
    let probe = ffmpeg::probe(&app, &path).await.map_err(to_cmd_error)?;
    if !force_proxy.unwrap_or(false) && is_browser_playable(&probe, &path) {
        return Ok(PlayableSource { path, is_proxy: false });
    }

    let duration_us: u64 = probe.format.duration
        .as_deref()
        .and_then(|s| s.parse::<f64>().ok())
        .map(|d| (d * 1_000_000.0) as u64)
        .unwrap_or(0);

    let proxy_path = proxy_path_for(&path).map_err(to_cmd_error)?;
    if proxy_path.exists() {
        return Ok(PlayableSource {
            path: proxy_path.to_string_lossy().to_string(),
            is_proxy: true,
        });
    }

    let tmp_path = proxy_path.with_extension("mp4.tmp");
    let args: Vec<String> = vec![
        "-y".into(),
        "-i".into(), path.clone(),
        "-c:v".into(), "libx264".into(),
        "-preset".into(), "veryfast".into(),
        "-crf".into(), "26".into(),
        "-pix_fmt".into(), "yuv420p".into(),
        "-c:a".into(), "aac".into(),
        "-b:a".into(), "128k".into(),
        "-movflags".into(), "+faststart".into(),
        "-f".into(), "mp4".into(),
        tmp_path.to_string_lossy().to_string(),
    ];

    let app_clone = app.clone();
    ffmpeg::run_ffmpeg_streaming(&app, args, move |tick: FfTick| {
        emit_progress(&app_clone, "proxy", &tick, duration_us, 0.0, 100.0);
    })
    .await
    .map_err(to_cmd_error)?;

    std::fs::rename(&tmp_path, &proxy_path).map_err(to_cmd_error)?;

    let _ = app.emit(
        "ff-progress",
        ProgressPayload { phase: "proxy".into(), percent: 100.0, speed: "—".into(), eta_sec: 0.0 },
    );

    Ok(PlayableSource {
        path: proxy_path.to_string_lossy().to_string(),
        is_proxy: true,
    })
}

#[tauri::command]
pub async fn export_clip(
    app: AppHandle,
    input_path: String,
    output_path: String,
    start_sec: f64,
    end_sec: f64,
    preset: ExportPreset,
) -> Result<(), String> {
    if end_sec <= start_sec {
        return Err("end must be greater than start".into());
    }

    let duration = end_sec - start_sec;
    let duration_us = (duration * 1_000_000.0) as u64;

    match preset {
        ExportPreset::Original => run_original(&app, &input_path, &output_path, start_sec, duration, duration_us).await?,
        ExportPreset::DiscordNonNitro => run_discord(&app, &input_path, &output_path, start_sec, duration, duration_us).await?,
    }

    let _ = app.emit(
        "ff-progress",
        ProgressPayload { phase: "export".into(), percent: 100.0, speed: "—".into(), eta_sec: 0.0 },
    );
    Ok(())
}

/// Stream-copy trim — keeps original codecs and container, very fast, lossless.
/// Trim points snap to nearest preceding keyframe (small inaccuracy at start).
async fn run_original(
    app: &AppHandle,
    input: &str,
    output: &str,
    start_sec: f64,
    duration: f64,
    duration_us: u64,
) -> Result<(), String> {
    let args: Vec<String> = vec![
        "-y".into(),
        "-ss".into(), format!("{:.3}", start_sec),
        "-i".into(), input.into(),
        "-t".into(), format!("{:.3}", duration),
        "-c".into(), "copy".into(),
        "-avoid_negative_ts".into(), "make_zero".into(),
        output.into(),
    ];

    let app_clone = app.clone();
    ffmpeg::run_ffmpeg_streaming(app, args, move |tick: FfTick| {
        emit_progress(&app_clone, "export", &tick, duration_us, 0.0, 100.0);
    })
    .await
    .map_err(to_cmd_error)
}

/// Two-pass H.264 encoding targeting ≤ 10 MB output. Caps at 1080p / 30fps.
/// Calculates bitrate from trim duration; aims for 9.5 MB to leave safety margin
/// for container overhead.
async fn run_discord(
    app: &AppHandle,
    input: &str,
    output: &str,
    start_sec: f64,
    duration: f64,
    duration_us: u64,
) -> Result<(), String> {
    let probe = ffmpeg::probe(app, input).await.map_err(to_cmd_error)?;
    let has_audio = probe.has_audio();

    // Target 9.3 MB so AAC headers / MP4 moov atom never push us over 10.
    let target_total_bits: f64 = 9_300_000.0 * 8.0;
    let audio_kbps: f64 = if has_audio { 96.0 } else { 0.0 };
    let audio_bits = audio_kbps * 1000.0 * duration;
    let video_bits = (target_total_bits - audio_bits).max(50_000.0);
    let video_kbps = ((video_bits / duration) / 1000.0).max(50.0).floor() as u64;

    let video_filter = "scale='min(1920,iw)':'min(1080,ih)':force_original_aspect_ratio=decrease,fps=30";

    let passlog_dir = ffmpeg::temp_subdir("2pass").map_err(to_cmd_error)?;
    let passlog = passlog_dir.join(format!("p-{}", stable_hash(input)));
    let passlog_str = passlog.to_string_lossy().to_string();

    // ---- Pass 1: analyze, no output ----
    let pass1: Vec<String> = vec![
        "-y".into(),
        "-ss".into(), format!("{:.3}", start_sec),
        "-i".into(), input.into(),
        "-t".into(), format!("{:.3}", duration),
        "-c:v".into(), "libx264".into(),
        "-b:v".into(), format!("{}k", video_kbps),
        "-vf".into(), video_filter.into(),
        "-passlogfile".into(), passlog_str.clone(),
        "-pass".into(), "1".into(),
        "-an".into(),
        "-f".into(), "mp4".into(),
        if cfg!(windows) { "NUL".into() } else { "/dev/null".into() },
    ];

    let app_p1 = app.clone();
    ffmpeg::run_ffmpeg_streaming(app, pass1, move |tick: FfTick| {
        // Map pass 1 to 0..50%
        emit_progress(&app_p1, "export", &tick, duration_us, 0.0, 50.0);
    })
    .await
    .map_err(to_cmd_error)?;

    // ---- Pass 2: encode with stats from pass 1 ----
    let mut pass2: Vec<String> = vec![
        "-y".into(),
        "-ss".into(), format!("{:.3}", start_sec),
        "-i".into(), input.into(),
        "-t".into(), format!("{:.3}", duration),
        "-c:v".into(), "libx264".into(),
        "-b:v".into(), format!("{}k", video_kbps),
        "-vf".into(), video_filter.into(),
        "-passlogfile".into(), passlog_str,
        "-pass".into(), "2".into(),
        "-pix_fmt".into(), "yuv420p".into(),
    ];
    if has_audio {
        pass2.extend([
            "-c:a".into(), "aac".into(),
            "-b:a".into(), format!("{}k", audio_kbps as u64),
        ]);
    } else {
        pass2.push("-an".into());
    }
    pass2.extend([
        "-movflags".into(), "+faststart".into(),
        output.into(),
    ]);

    let app_p2 = app.clone();
    ffmpeg::run_ffmpeg_streaming(app, pass2, move |tick: FfTick| {
        // Map pass 2 to 50..100%
        emit_progress(&app_p2, "export", &tick, duration_us, 50.0, 50.0);
    })
    .await
    .map_err(to_cmd_error)?;

    // Cleanup pass log files (x264 writes <passlogfile>-0.log and -0.log.mbtree).
    let base = passlog.to_string_lossy().to_string();
    let _ = std::fs::remove_file(format!("{}-0.log", base));
    let _ = std::fs::remove_file(format!("{}-0.log.mbtree", base));

    Ok(())
}

/// Emit a progress event with optional offset/scale (used for 2-pass).
/// `offset` is added after scaling, `scale` is the percentage span this run
/// represents (e.g. 50.0 means this ffmpeg call maps its 0..100% to a 50% slice).
fn emit_progress(
    app: &AppHandle,
    phase: &str,
    tick: &FfTick,
    duration_us: u64,
    offset: f64,
    scale: f64,
) {
    let raw = if duration_us == 0 {
        0.0
    } else {
        (tick.out_time_us as f64 / duration_us as f64 * 100.0).clamp(0.0, 100.0)
    };
    let percent = (offset + raw * (scale / 100.0)).clamp(0.0, 99.5);
    let eta = parse_eta(&tick.speed, duration_us, tick.out_time_us);
    let _ = app.emit(
        "ff-progress",
        ProgressPayload {
            phase: phase.to_string(),
            percent,
            speed: tick.speed.clone(),
            eta_sec: eta,
        },
    );
}

fn parse_eta(speed_str: &str, total_us: u64, done_us: u64) -> f64 {
    if total_us == 0 || done_us >= total_us { return 0.0; }
    let remaining_us = (total_us - done_us) as f64;
    let factor: f64 = speed_str.trim_end_matches('x').trim().parse::<f64>().unwrap_or(1.0).max(0.05);
    (remaining_us / 1_000_000.0) / factor
}

#[tauri::command]
pub async fn generate_thumbnails(
    app: AppHandle,
    path: String,
    count: u32,
) -> Result<Vec<String>, String> {
    let probe = ffmpeg::probe(&app, &path).await.map_err(to_cmd_error)?;
    let duration = probe.format.duration
        .as_deref()
        .and_then(|s| s.parse::<f64>().ok())
        .unwrap_or(0.0);
    if duration <= 0.0 || count == 0 { return Ok(vec![]); }

    let dir = ffmpeg::temp_subdir(&job_id(&path)).map_err(to_cmd_error)?;

    let fps = (count as f64) / duration;
    let pattern = dir.join("thumb_%03d.jpg");
    let pattern_str = pattern.to_string_lossy().to_string();

    let args = vec![
        "-y".into(),
        "-i".into(), path.clone(),
        "-vf".into(), format!("fps={:.6},scale=160:-2", fps.max(0.0001)),
        "-frames:v".into(), count.to_string(),
        "-q:v".into(), "5".into(),
        pattern_str,
    ];
    ffmpeg::run_ffmpeg(&app, args).await.map_err(to_cmd_error)?;

    let mut out = Vec::new();
    for i in 1..=count {
        let p = dir.join(format!("thumb_{:03}.jpg", i));
        if p.exists() { out.push(p.to_string_lossy().to_string()); }
    }
    Ok(out)
}

fn proxy_path_for(input: &str) -> Result<PathBuf, std::io::Error> {
    let mtime = std::fs::metadata(input)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let id = stable_hash(&format!("{input}|{mtime}"));
    let mut dir = ffmpeg::temp_subdir("proxies")?;
    dir.push(format!("{id}.mp4"));
    Ok(dir)
}

fn video_files_in_dir(dir: &Path) -> Result<Vec<PathBuf>, std::io::Error> {
    let mut videos = Vec::new();
    for entry in std::fs::read_dir(dir)? {
        let path = entry?.path();
        if path.is_file() && is_video_file(&path) {
            videos.push(path);
        }
    }
    videos.sort_by_key(|path| {
        path.file_name()
            .map(|name| name.to_string_lossy().to_lowercase())
            .unwrap_or_default()
    });
    Ok(videos)
}

fn is_video_file(path: &Path) -> bool {
    path.extension()
        .and_then(|ext| ext.to_str())
        .map(|ext| VIDEO_EXTS.contains(&ext.to_lowercase().as_str()))
        .unwrap_or(false)
}

fn normalized_path(path: PathBuf) -> PathBuf {
    path.canonicalize().unwrap_or(path)
}

#[cfg(windows)]
fn move_file_to_trash(path: &Path) -> Result<(), String> {
    use std::ffi::c_void;
    use std::os::windows::ffi::OsStrExt;

    const FO_DELETE: u32 = 0x0003;
    const FOF_ALLOWUNDO: u16 = 0x0040;
    const FOF_NOCONFIRMATION: u16 = 0x0010;
    const FOF_NOERRORUI: u16 = 0x0400;
    const FOF_SILENT: u16 = 0x0004;

    #[repr(C)]
    struct ShFileOpStructW {
        hwnd: *mut c_void,
        w_func: u32,
        p_from: *const u16,
        p_to: *const u16,
        f_flags: u16,
        f_any_operations_aborted: i32,
        h_name_mappings: *mut c_void,
        lpsz_progress_title: *const u16,
    }

    #[link(name = "Shell32")]
    extern "system" {
        fn SHFileOperationW(file_op: *mut ShFileOpStructW) -> i32;
    }

    let mut from: Vec<u16> = path.as_os_str().encode_wide().collect();
    from.push(0);
    from.push(0);

    let mut op = ShFileOpStructW {
        hwnd: std::ptr::null_mut(),
        w_func: FO_DELETE,
        p_from: from.as_ptr(),
        p_to: std::ptr::null(),
        f_flags: FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_NOERRORUI | FOF_SILENT,
        f_any_operations_aborted: 0,
        h_name_mappings: std::ptr::null_mut(),
        lpsz_progress_title: std::ptr::null(),
    };

    let result = unsafe { SHFileOperationW(&mut op) };
    if result == 0 && op.f_any_operations_aborted == 0 {
        Ok(())
    } else {
        Err(format!("failed to move video to recycle bin: error code {result}"))
    }
}

#[cfg(not(windows))]
fn move_file_to_trash(path: &Path) -> Result<(), String> {
    std::fs::remove_file(path).map_err(to_cmd_error)
}

fn job_id(path: &str) -> String {
    format!("thumbs-{}", stable_hash(path))
}

fn stable_hash(s: &str) -> String {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    let mut h = DefaultHasher::new();
    s.hash(&mut h);
    format!("{:x}", h.finish())
}

impl From<FfError> for String {
    fn from(e: FfError) -> Self { e.to_string() }
}
