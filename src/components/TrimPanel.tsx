import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { formatTime, parseTime } from "../lib/format";
import { UploadIcon } from "./Icons";
import type { ExportPreset, ProgressPayload, TrimRange } from "../types";

interface Props {
  duration: number;
  trim: TrimRange;
  onTrimChange: (r: TrimRange) => void;
  currentTime: number;
  onSeek: (sec: number) => void;
  thumbnails: string[];

  preset: ExportPreset;
  onPresetChange: (p: ExportPreset) => void;
  onExport: () => void;
  exporting: boolean;
  exportProgress: ProgressPayload | null;
}

const PRESETS: { value: ExportPreset; label: string; description: string }[] = [
  {
    value: "original",
    label: "Original",
    description: "Quell-Codec & Container, verlustfreier Schnell-Trim",
  },
  {
    value: "discord_non_nitro",
    label: "Discord (≤ 10 MB)",
    description: "Max. Qualität unter 10 MB · 1080p · 30fps · 2-Pass",
  },
];

type DragKind = "start" | "end" | "playhead" | null;

export function TrimPanel({
  duration, trim, onTrimChange, currentTime, onSeek, thumbnails,
  preset, onPresetChange, onExport, exporting, exportProgress,
}: Props) {
  const trackRef = useRef<HTMLDivElement>(null);
  const [drag, setDrag] = useState<DragKind>(null);
  const [exportMenu, setExportMenu] = useState(false);
  const exportAnchorRef = useRef<HTMLDivElement>(null);
  const wasExportingRef = useRef(false);

  const pct = useCallback((sec: number) => {
    if (!duration) return 0;
    return Math.max(0, Math.min(100, (sec / duration) * 100));
  }, [duration]);

  const positionFromClient = useCallback((clientX: number): number => {
    const el = trackRef.current;
    if (!el) return 0;
    const rect = el.getBoundingClientRect();
    const ratio = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width));
    return ratio * duration;
  }, [duration]);

  useEffect(() => {
    if (!drag) return;
    const onMove = (e: PointerEvent) => {
      const t = positionFromClient(e.clientX);
      if (drag === "start") onTrimChange({ startSec: Math.min(t, trim.endSec - 0.05), endSec: trim.endSec });
      else if (drag === "end") onTrimChange({ startSec: trim.startSec, endSec: Math.max(t, trim.startSec + 0.05) });
      else if (drag === "playhead") onSeek(t);
    };
    const onUp = () => setDrag(null);
    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp);
    return () => {
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
    };
  }, [drag, trim, onTrimChange, onSeek, positionFromClient]);

  useEffect(() => {
    if (!exportMenu) return;
    const onDown = (e: MouseEvent) => {
      if (!exportAnchorRef.current?.contains(e.target as Node)) setExportMenu(false);
    };
    window.addEventListener("mousedown", onDown);
    return () => window.removeEventListener("mousedown", onDown);
  }, [exportMenu]);

  useEffect(() => {
    if (wasExportingRef.current && !exporting) {
      setExportMenu(false);
    }
    wasExportingRef.current = exporting;
  }, [exporting]);

  const ticks = useMemo(() => {
    const out: { label: string; left: number }[] = [];
    if (!duration) return out;
    const step = pickStep(duration);
    for (let s = 0; s <= duration + 0.001; s += step) {
      out.push({ label: formatTime(s), left: pct(s) });
    }
    return out;
  }, [duration, pct]);

  const onTrackPointerDown = (e: React.PointerEvent) => {
    const t = positionFromClient(e.clientX);
    onSeek(t);
    setDrag("playhead");
  };

  const pctExport = exportProgress?.percent ?? 0;

  return (
    <div className="trim-panel">
      <div className="trim-header-row">
        <div className="trim-header">TRIM TIMELINE</div>

        <div className="trim-pills">
          <TimePill
            value={trim.startSec}
            max={trim.endSec - 0.05}
            onChange={(v) => onTrimChange({ startSec: v, endSec: trim.endSec })}
          />
          <span className="pill-arrow">→</span>
          <TimePill
            value={trim.endSec}
            min={trim.startSec + 0.05}
            max={duration}
            onChange={(v) => onTrimChange({ startSec: trim.startSec, endSec: v })}
          />
          <span className="pill-sep">·</span>
          <span className="trim-range-info">
            {formatTime(trim.endSec - trim.startSec)} <span>Länge</span>
          </span>
        </div>

        <div className="export-anchor" ref={exportAnchorRef}>
          <button
            className="btn-primary btn-export-inline"
            onClick={() => setExportMenu((v) => !v)}
            disabled={exporting}
          >
            <UploadIcon size={16} />
            {exporting ? `Exporting… ${pctExport.toFixed(0)}%` : "Export"}
          </button>

          {exportMenu && (
            <div className="popover popover-export" onMouseDown={(e) => e.stopPropagation()}>
              <div className="popover-title">EXPORT VORLAGE</div>

              <div className="preset-list">
                {PRESETS.map(({ value, label, description }) => (
                  <button
                    key={value}
                    type="button"
                    className={`preset-option ${preset === value ? "preset-option-active" : ""}`}
                    onClick={() => onPresetChange(value)}
                    disabled={exporting}
                  >
                    <div className="preset-radio">
                      <div className="preset-radio-dot" />
                    </div>
                    <div className="preset-text">
                      <div className="preset-label">{label}</div>
                      <div className="preset-desc">{description}</div>
                    </div>
                  </button>
                ))}
              </div>

              {exporting && (
                <div className="export-progress">
                  <div className="export-progress-bar">
                    <div className="export-progress-fill" style={{ width: `${pctExport}%` }} />
                  </div>
                  <div className="export-progress-meta">
                    <span>{pctExport.toFixed(0)}%</span>
                    {exportProgress?.speed && <span>{exportProgress.speed}</span>}
                    {exportProgress && exportProgress.etaSec > 0 && (
                      <span>ETA {formatTime(exportProgress.etaSec)}</span>
                    )}
                  </div>
                </div>
              )}

              <button className="btn-primary" disabled={exporting} onClick={onExport}>
                <UploadIcon size={16} />
                {exporting ? "Exporting…" : "Exportieren"}
              </button>
            </div>
          )}
        </div>
      </div>

      <div className="trim-ticks">
        {ticks.map((t, i) => (
          <span key={i} className="trim-tick" style={{ left: `${t.left}%` }}>{t.label}</span>
        ))}
      </div>

      <div ref={trackRef} className="trim-track" onPointerDown={onTrackPointerDown}>
        <div className="thumb-strip" aria-hidden>
          {thumbnails.length > 0
            ? thumbnails.map((url, i) => (<img key={i} src={url} alt="" draggable={false} />))
            : Array.from({ length: 12 }).map((_, i) => <div key={i} className="thumb-placeholder" />)}
        </div>

        <div className="trim-shadow trim-shadow-left" style={{ width: `${pct(trim.startSec)}%` }} />
        <div className="trim-shadow trim-shadow-right" style={{ width: `${100 - pct(trim.endSec)}%` }} />

        <div
          className="trim-handle trim-handle-start"
          style={{ left: `${pct(trim.startSec)}%` }}
          onPointerDown={(e) => { e.stopPropagation(); setDrag("start"); }}
        />
        <div
          className="trim-handle trim-handle-end"
          style={{ left: `${pct(trim.endSec)}%` }}
          onPointerDown={(e) => { e.stopPropagation(); setDrag("end"); }}
        />

        <div className="trim-playhead" style={{ left: `${pct(currentTime)}%` }} />
      </div>
    </div>
  );
}

function pickStep(dur: number): number {
  if (dur <= 30) return 5;
  if (dur <= 120) return 15;
  if (dur <= 600) return 60;
  if (dur <= 3600) return 300;
  return 600;
}

function TimePill({
  value, onChange, min = 0, max = Infinity,
}: {
  value: number; onChange: (v: number) => void; min?: number; max?: number;
}) {
  const [text, setText] = useState(formatTime(value, true));
  const [editing, setEditing] = useState(false);

  useEffect(() => {
    if (!editing) setText(formatTime(value, true));
  }, [value, editing]);

  const commit = () => {
    const parsed = parseTime(text);
    if (parsed == null) { setText(formatTime(value, true)); setEditing(false); return; }
    const clamped = Math.max(min, Math.min(max, parsed));
    onChange(clamped);
    setText(formatTime(clamped, true));
    setEditing(false);
  };

  return (
    <input
      type="text"
      className="time-pill"
      value={text}
      onFocus={() => setEditing(true)}
      onChange={(e) => setText(e.target.value)}
      onBlur={commit}
      onKeyDown={(e) => { if (e.key === "Enter") (e.target as HTMLInputElement).blur(); }}
    />
  );
}
