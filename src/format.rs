pub fn format_time(sec: f64, with_ms: bool) -> String {
    let sec = if sec.is_finite() && sec > 0.0 {
        sec
    } else {
        0.0
    };
    let total_ms = (sec * 1000.0).floor() as u64;
    let (h, m, s, ms) = (
        total_ms / 3_600_000,
        total_ms / 60_000 % 60,
        total_ms / 1000 % 60,
        total_ms % 1000,
    );
    if with_ms {
        format!("{h:02}:{m:02}:{s:02}.{ms:03}")
    } else {
        format!("{h:02}:{m:02}:{s:02}")
    }
}

/// Accepts HH:MM:SS, HH:MM:SS.mmm, MM:SS, MM:SS.mmm or raw seconds.
pub fn parse_time(input: &str) -> Option<f64> {
    let input = input.trim();
    if let Ok(v) = input.parse::<f64>() {
        return (v >= 0.0).then_some(v);
    }
    let (clock, ms) = match input.split_once('.') {
        Some((c, ms)) if (1..=3).contains(&ms.len()) && ms.bytes().all(|b| b.is_ascii_digit()) => {
            (c, format!("{ms:0<3}").parse::<f64>().ok()? / 1000.0)
        }
        Some(_) => return None,
        None => (input, 0.0),
    };
    let parts: Vec<u64> = clock
        .split(':')
        .map(|p| p.parse().ok())
        .collect::<Option<_>>()?;
    let (h, m, s) = match parts[..] {
        [m, s] => (0, m, s),
        [h, m, s] => (h, m, s),
        _ => return None,
    };
    (m < 60 && s < 60).then(|| (h * 3600 + m * 60 + s) as f64 + ms)
}

pub fn format_bytes(bytes: u64) -> String {
    if bytes == 0 {
        return "0 B".into();
    }
    let units = ["B", "KB", "MB", "GB", "TB"];
    let i = ((bytes as f64).ln() / 1024f64.ln()).floor().min(4.0) as usize;
    let v = bytes as f64 / 1024f64.powi(i as i32);
    if i == 0 {
        format!("{v:.0} {}", units[i])
    } else {
        format!("{v:.2} {}", units[i])
    }
}

pub fn aspect_ratio(w: u32, h: u32) -> String {
    fn gcd(a: u32, b: u32) -> u32 {
        if b == 0 {
            a
        } else {
            gcd(b, a % b)
        }
    }
    let g = gcd(w, h).max(1);
    format!("{}:{}", w / g, h / g)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn time_roundtrip() {
        assert_eq!(format_time(3725.5, true), "01:02:05.500");
        assert_eq!(format_time(f64::NAN, false), "00:00:00");
        assert_eq!(parse_time("01:02:05.5"), Some(3725.5));
        assert_eq!(parse_time("2:05"), Some(125.0));
        assert_eq!(parse_time("12.25"), Some(12.25));
        assert_eq!(parse_time("1:75"), None);
        assert_eq!(parse_time("abc"), None);
    }

    #[test]
    fn bytes_and_aspect() {
        assert_eq!(format_bytes(1536), "1.50 KB");
        assert_eq!(format_bytes(512), "512 B");
        assert_eq!(aspect_ratio(1920, 1080), "16:9");
    }
}
