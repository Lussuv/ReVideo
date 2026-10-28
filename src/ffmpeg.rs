use serde::Deserialize;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;

/// Builds a command for a bundled tool: next to the executable (Windows
/// installer), otherwise from PATH (Flatpak puts it in /app/bin).
fn tool(name: &str) -> Command {
    let file = format!("{name}{}", std::env::consts::EXE_SUFFIX);
    let program = std::env::current_exe()
        .ok()
        .and_then(|exe| exe.parent().map(|dir| dir.join(&file)))
        .filter(|p| p.is_file())
        .unwrap_or_else(|| PathBuf::from(&file));

    let mut cmd = Command::new(program);
    cmd.stdin(Stdio::null()).kill_on_drop(true);
    #[cfg(windows)]
    cmd.creation_flags(0x0800_0000); // CREATE_NO_WINDOW
    cmd
}

async fn run(name: &str, args: &[String]) -> Result<String, String> {
    let out = tool(name)
        .args(args)
        .output()
        .await
        .map_err(|e| format!("{name} konnte nicht gestartet werden: {e}"))?;
    if !out.status.success() {
        return Err(format!(
            "{name} beendet mit {}: {}",
            out.status,
            String::from_utf8_lossy(&out.stderr).trim()
        ));
    }
    Ok(String::from_utf8_lossy(&out.stdout).into_owned())
}

pub async fn probe(path: &Path) -> Result<ProbeResult, String> {
    let args = [
        "-v",
        "error",
        "-print_format",
        "json",
        "-show_format",
        "-show_streams",
    ]
    .map(String::from)
    .into_iter()
    .chain([path.to_string_lossy().into_owned()])
    .collect::<Vec<_>>();
    let json = run("ffprobe", &args).await?;
    serde_json::from_str(&json).map_err(|e| format!("ffprobe lieferte ungültiges JSON: {e}"))
}

pub async fn run_ffmpeg(args: Vec<String>) -> Result<(), String> {
    run("ffmpeg", &args).await.map(|_| ())
}

/// Runs ffmpeg with `-progress pipe:1` and calls `on_tick(out_time_us, speed)`
/// for every progress block it emits.
pub async fn run_ffmpeg_streaming(
    args: Vec<String>,
    mut on_tick: impl FnMut(u64, &str),
) -> Result<(), String> {
    let mut child = tool("ffmpeg")
        .args(["-progress", "pipe:1", "-nostats"])
        .args(&args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("ffmpeg konnte nicht gestartet werden: {e}"))?;

    // Drained concurrently so a chatty ffmpeg never blocks on a full stderr pipe.
    let mut stderr = child.stderr.take().expect("piped");
    let stderr_task = tokio::spawn(async move {
        let mut buf = String::new();
        let _ = tokio::io::AsyncReadExt::read_to_string(&mut stderr, &mut buf).await;
        buf
    });

    let mut lines = BufReader::new(child.stdout.take().expect("piped")).lines();
    let mut out_time_us = 0;
    let mut speed = String::new();
    while let Ok(Some(line)) = lines.next_line().await {
        match line.split_once('=') {
            // Older builds wrote microseconds under out_time_ms too — accept both.
            Some(("out_time_us" | "out_time_ms", v)) => {
                if let Ok(n) = v.trim().parse() {
                    out_time_us = n;
                }
            }
            Some(("speed", v)) => speed = v.trim().to_string(),
            Some(("progress", _)) => on_tick(out_time_us, &speed),
            _ => {}
        }
    }

    let status = child.wait().await.map_err(|e| e.to_string())?;
    let stderr = stderr_task.await.unwrap_or_default();
    if !status.success() {
        return Err(format!("ffmpeg beendet mit {status}: {}", stderr.trim()));
    }
    Ok(())
}

/// Writable directory under the OS temp for thumbnail and pass-log output.
pub fn temp_subdir(name: &str) -> std::io::Result<PathBuf> {
    let dir = std::env::temp_dir().join("revideo").join(name);
    std::fs::create_dir_all(&dir)?;
    Ok(dir)
}

#[derive(Debug, Deserialize)]
pub struct ProbeResult {
    pub format: ProbeFormat,
    pub streams: Vec<ProbeStream>,
}

#[derive(Debug, Deserialize)]
pub struct ProbeFormat {
    #[serde(default)]
    pub duration: Option<String>,
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
    pub fn duration(&self) -> f64 {
        self.format
            .duration
            .as_deref()
            .and_then(|s| s.parse().ok())
            .unwrap_or(0.0)
    }
}

pub fn parse_fps(rate: &str) -> f32 {
    let (num, den) = rate.split_once('/').unwrap_or((rate, "1"));
    let n: f32 = num.parse().unwrap_or(0.0);
    let d: f32 = den.parse().unwrap_or(1.0);
    if d == 0.0 {
        0.0
    } else {
        n / d
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fps_parsing() {
        assert_eq!(parse_fps("30/1"), 30.0);
        assert!((parse_fps("30000/1001") - 29.97).abs() < 0.01);
        assert_eq!(parse_fps("0/0"), 0.0);
        assert_eq!(parse_fps("25"), 25.0);
    }
}
