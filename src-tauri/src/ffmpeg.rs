use serde::Deserialize;
use std::path::{Path, PathBuf};
use tauri::AppHandle;
use tauri_plugin_shell::{process::CommandEvent, ShellExt};

#[derive(Debug, thiserror::Error)]
pub enum FfError {
    #[error("sidecar not found or failed to start: {0}")]
    Sidecar(String),
    #[error("ffmpeg exited with code {0}: {1}")]
    NonZero(i32, String),
    #[error("ffprobe returned malformed JSON: {0}")]
    Parse(String),
    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
}

/// Run ffprobe and return parsed JSON metadata.
pub async fn probe(app: &AppHandle, path: &str) -> Result<ProbeResult, FfError> {
    let args = vec![
        "-v".to_string(), "error".to_string(),
        "-print_format".to_string(), "json".to_string(),
        "-show_format".to_string(),
        "-show_streams".to_string(),
        path.to_string(),
    ];

    let (stdout, stderr, code) = run_sidecar(app, "ffprobe", args).await?;
    if code != 0 {
        return Err(FfError::NonZero(code, stderr));
    }
    serde_json::from_str::<ProbeResult>(&stdout).map_err(|e| FfError::Parse(e.to_string()))
}

/// Run ffmpeg without progress reporting (one-shot, fire-and-forget).
pub async fn run_ffmpeg(app: &AppHandle, args: Vec<String>) -> Result<(), FfError> {
    let (_out, stderr, code) = run_sidecar(app, "ffmpeg", args).await?;
    if code != 0 {
        return Err(FfError::NonZero(code, stderr));
    }
    Ok(())
}

/// Single progress snapshot from `-progress pipe:1`.
#[derive(Debug, Clone, Default)]
pub struct FfTick {
    pub out_time_us: u64,
    pub speed: String,
}

/// Run ffmpeg with progress reporting. Caller passes a closure that fires
/// every time ffmpeg emits a `progress=continue` block on stdout.
/// Total duration is needed to compute percent on the consumer side.
pub async fn run_ffmpeg_streaming<F>(
    app: &AppHandle,
    mut args: Vec<String>,
    mut on_tick: F,
) -> Result<(), FfError>
where
    F: FnMut(FfTick),
{
    // Force structured progress output to stdout.
    // Must be inserted before the input/output args; ffmpeg accepts -progress anywhere
    // but it's tidier at the front.
    args.insert(0, "-progress".to_string());
    args.insert(1, "pipe:1".to_string());
    args.insert(2, "-nostats".to_string());

    let shell = app.shell();
    let cmd = shell
        .sidecar("ffmpeg")
        .map_err(|e| FfError::Sidecar(e.to_string()))?;
    let (mut rx, _child) = cmd
        .args(args)
        .spawn()
        .map_err(|e| FfError::Sidecar(e.to_string()))?;

    let mut stderr_buf = String::new();
    let mut stdout_buf = String::new();
    let mut code: i32 = -1;
    let mut current = FfTick::default();

    while let Some(event) = rx.recv().await {
        match event {
            CommandEvent::Stdout(bytes) => {
                stdout_buf.push_str(&String::from_utf8_lossy(&bytes));
                while let Some(newline) = stdout_buf.find('\n') {
                    let line = stdout_buf[..newline].trim().to_string();
                    stdout_buf.drain(..=newline);
                    if let Some((k, v)) = line.split_once('=') {
                        match k.trim() {
                            "out_time_us" | "out_time_ms" => {
                                // FFmpeg uses out_time_us (microseconds).
                                // Older builds wrote microseconds under out_time_ms too — accept both.
                                if let Ok(n) = v.trim().parse::<u64>() { current.out_time_us = n; }
                            }
                            "speed" => current.speed = v.trim().to_string(),
                            "progress" => {
                                on_tick(current.clone());
                                if v.trim() == "end" { /* loop will exit on Terminated */ }
                            }
                            _ => {}
                        }
                    }
                }
            }
            CommandEvent::Stderr(bytes) => stderr_buf.push_str(&String::from_utf8_lossy(&bytes)),
            CommandEvent::Terminated(payload) => code = payload.code.unwrap_or(-1),
            _ => {}
        }
    }

    if code != 0 {
        return Err(FfError::NonZero(code, stderr_buf));
    }
    Ok(())
}

async fn run_sidecar(
    app: &AppHandle,
    sidecar: &str,
    args: Vec<String>,
) -> Result<(String, String, i32), FfError> {
    let shell = app.shell();
    let cmd = shell.sidecar(sidecar).map_err(|e| FfError::Sidecar(e.to_string()))?;
    let (mut rx, _child) = cmd
        .args(args)
        .spawn()
        .map_err(|e| FfError::Sidecar(e.to_string()))?;

    let mut stdout = String::new();
    let mut stderr = String::new();
    let mut code: i32 = -1;

    while let Some(event) = rx.recv().await {
        match event {
            CommandEvent::Stdout(bytes) => stdout.push_str(&String::from_utf8_lossy(&bytes)),
            CommandEvent::Stderr(bytes) => stderr.push_str(&String::from_utf8_lossy(&bytes)),
            CommandEvent::Terminated(payload) => {
                code = payload.code.unwrap_or(-1);
            }
            _ => {}
        }
    }

    Ok((stdout, stderr, code))
}

/// Pick a writable directory under the OS temp for proxy/thumbnail output.
pub fn temp_subdir(name: &str) -> Result<PathBuf, std::io::Error> {
    let mut dir = std::env::temp_dir();
    dir.push("retry-player");
    dir.push(name);
    std::fs::create_dir_all(&dir)?;
    Ok(dir)
}

/// Determines whether a video can be played directly in the WebView (no proxy needed).
/// Rule: container must be one of MP4/WebM/MOV and codec one of h264/vp8/vp9/av1.
pub fn is_browser_playable(probe: &ProbeResult, path: &str) -> bool {
    let ext = Path::new(path)
        .extension()
        .and_then(|s| s.to_str())
        .map(|s| s.to_lowercase())
        .unwrap_or_default();
    let container_ok = matches!(ext.as_str(), "mp4" | "m4v" | "webm" | "mov");
    if !container_ok { return false; }

    let codec_ok = probe
        .video_stream()
        .and_then(|s| s.codec_name.as_deref())
        .map(|c| matches!(c, "h264" | "avc1" | "vp8" | "vp9" | "av1"))
        .unwrap_or(false);

    container_ok && codec_ok
}

// ---------- ffprobe parsing ----------

#[derive(Debug, Deserialize)]
pub struct ProbeResult {
    pub format: ProbeFormat,
    pub streams: Vec<ProbeStream>,
}

#[derive(Debug, Deserialize)]
pub struct ProbeFormat {
    #[serde(default)]
    pub duration: Option<String>,
    #[allow(dead_code)]
    #[serde(default)]
    pub size: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct ProbeStream {
    pub codec_type: String,
    #[serde(default)]
    pub codec_name: Option<String>,
    #[serde(default)]
    pub width: Option<u32>,
    #[serde(default)]
    pub height: Option<u32>,
    #[serde(default)]
    pub r_frame_rate: Option<String>,
    #[serde(default)]
    pub avg_frame_rate: Option<String>,
}

impl ProbeResult {
    pub fn video_stream(&self) -> Option<&ProbeStream> {
        self.streams.iter().find(|s| s.codec_type == "video")
    }
    pub fn has_audio(&self) -> bool {
        self.streams.iter().any(|s| s.codec_type == "audio")
    }
}

pub fn parse_fps(rate: &str) -> f32 {
    let (num, den) = rate.split_once('/').unwrap_or((rate, "1"));
    let n: f32 = num.parse().unwrap_or(0.0);
    let d: f32 = den.parse().unwrap_or(1.0);
    if d == 0.0 { 0.0 } else { n / d }
}
