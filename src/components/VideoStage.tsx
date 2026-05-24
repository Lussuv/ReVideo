import { useEffect, useRef, useState } from "react";
import { FullscreenIcon, MuteIcon, PauseIcon, PlayIcon, SkipBackIcon, SkipFwdIcon, VolumeIcon } from "./Icons";
import { formatTime } from "../lib/format";
import type { usePlayer } from "../hooks/usePlayer";
import type { ProgressPayload } from "../types";

interface Props {
  src: string;
  player: ReturnType<typeof usePlayer>;
  proxying?: boolean;
  proxyProgress?: ProgressPayload | null;
  onPlaybackError?: () => void;
}

export function VideoStage({ src, player, proxying, proxyProgress, onPlaybackError }: Props) {
  const { videoRef, playing, currentTime, duration, volume, muted, toggle, skip, stepFrame, seek, setVolume, setMuted } = player;
  const [controlsVisible, setControlsVisible] = useState(true);
  const stageRef = useRef<HTMLDivElement | null>(null);
  const hideTimerRef = useRef<number | null>(null);
  const pointerOverControlsRef = useRef(false);

  const seekPct = duration > 0 ? (currentTime / duration) * 100 : 0;
  const volPct = (muted ? 0 : volume) * 100;

  const scheduleControlsHide = () => {
    if (pointerOverControlsRef.current) return;
    if (hideTimerRef.current !== null) window.clearTimeout(hideTimerRef.current);
    hideTimerRef.current = window.setTimeout(() => {
      if (pointerOverControlsRef.current) return;
      setControlsVisible(false);
      hideTimerRef.current = null;
    }, 1800);
  };

  const showControls = () => {
    setControlsVisible(true);
    scheduleControlsHide();
  };

  const keepControlsVisible = () => {
    pointerOverControlsRef.current = true;
    if (hideTimerRef.current !== null) {
      window.clearTimeout(hideTimerRef.current);
      hideTimerRef.current = null;
    }
    setControlsVisible(true);
  };

  const releaseControls = () => {
    pointerOverControlsRef.current = false;
    scheduleControlsHide();
  };

  const hideControls = () => {
    pointerOverControlsRef.current = false;
    if (hideTimerRef.current !== null) {
      window.clearTimeout(hideTimerRef.current);
      hideTimerRef.current = null;
    }
    setControlsVisible(false);
  };

  const toggleFullscreen = async () => {
    const stage = stageRef.current;
    if (!stage) return;

    try {
      if (document.fullscreenElement) {
        await document.exitFullscreen();
      } else {
        await stage.requestFullscreen();
      }
    } catch {
      // Some WebView environments can deny fullscreen without a user gesture.
    }
  };

  useEffect(() => {
    setControlsVisible(true);
    scheduleControlsHide();
    return () => {
      if (hideTimerRef.current !== null) window.clearTimeout(hideTimerRef.current);
    };
  }, [src]);

  return (
    <div
      ref={stageRef}
      className={`stage ${controlsVisible ? "controls-visible" : ""}`}
      onMouseMove={showControls}
      onMouseLeave={hideControls}
    >
      {src && (
        <video
          ref={videoRef}
          src={src}
          className="video-el"
          onClick={toggle}
          onError={onPlaybackError}
          preload="metadata"
        />
      )}

      {proxying && (
        <div className="proxy-overlay">
          <div className="proxy-spinner" />
          <div className="proxy-label">Bereite Preview vor…</div>
          <div className="proxy-sub">
            Format ist nicht direkt abspielbar — transkodiere in einen H.264-Proxy
          </div>
          <div className="proxy-bar">
            <div className="proxy-bar-fill" style={{ width: `${proxyProgress?.percent ?? 0}%` }} />
          </div>
          <div className="proxy-meta">
            {proxyProgress
              ? `${proxyProgress.percent.toFixed(0)}% · ${proxyProgress.speed || "—"}`
              : "Starte…"}
          </div>
        </div>
      )}

      <div
        className="controls-bar"
        onMouseEnter={keepControlsVisible}
        onMouseLeave={releaseControls}
      >
        <div className="seek-row">
          <input
            type="range"
            className="seek-slider"
            min={0}
            max={duration || 100}
            step={0.01}
            value={currentTime}
            style={{ "--pct": `${seekPct}%` } as React.CSSProperties}
            onChange={(e) => seek(parseFloat(e.target.value))}
          />
        </div>

        <div className="controls-row">
          <div className="controls-left" />

          <div className="controls-center">
            <button className="ctrl-btn ctrl-frame" onClick={() => stepFrame(-1)} title="Vorheriger Frame (,)">
              ⏮
            </button>
            <button className="ctrl-btn" onClick={() => skip(-5)} title="−5s (←)">
              <SkipBackIcon size={18} />
            </button>
            <button className="ctrl-btn ctrl-play" onClick={toggle} title="Play/Pause (Space)">
              {playing ? <PauseIcon size={22} /> : <PlayIcon size={22} />}
            </button>
            <button className="ctrl-btn" onClick={() => skip(5)} title="+5s (→)">
              <SkipFwdIcon size={18} />
            </button>
            <button className="ctrl-btn ctrl-frame" onClick={() => stepFrame(1)} title="Nächster Frame (.)">
              ⏭
            </button>
          </div>

          <div className="controls-right">
            <div className="time-readout">
              <span className="time-current">{formatTime(currentTime)}</span>
              <span className="time-sep"> / </span>
              <span className="time-total">{formatTime(duration)}</span>
            </div>

            <div className="controls-actions">
              <div className="volume-group">
                <button className="ctrl-btn ctrl-mute" onClick={() => setMuted(!muted)} title="Stumm">
                  {muted || volume === 0 ? <MuteIcon size={18} /> : <VolumeIcon size={18} />}
                </button>
                <input
                  type="range"
                  className="volume-slider"
                  min={0}
                  max={1}
                  step={0.01}
                  value={muted ? 0 : volume}
                  style={{ "--pct": `${volPct}%` } as React.CSSProperties}
                  onChange={(e) => {
                    const v = parseFloat(e.target.value);
                    setVolume(v);
                    if (v > 0 && muted) setMuted(false);
                  }}
                />
              </div>

              <button className="ctrl-btn" onClick={toggleFullscreen} title="Vollbild">
                <FullscreenIcon size={18} />
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
