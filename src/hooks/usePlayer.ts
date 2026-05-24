import { useCallback, useEffect, useState } from "react";

const ASSUMED_FPS = 30;

/// Callback-ref-based player hook.
/// React calls `videoRef(element)` whenever the <video> mounts/unmounts —
/// we track it in state so the effect that attaches listeners actually fires
/// after the element exists in the DOM.
export function usePlayer(fps: number = ASSUMED_FPS) {
  const [videoEl, setVideoEl] = useState<HTMLVideoElement | null>(null);
  const [playing, setPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [volume, setVolume] = useState(0.8);
  const [muted, setMuted] = useState(false);

  // Sync volume/muted to element
  useEffect(() => {
    if (!videoEl) return;
    videoEl.volume = volume;
    videoEl.muted = muted;
  }, [videoEl, volume, muted]);

  // Attach event listeners whenever the element changes
  useEffect(() => {
    if (!videoEl) return;
    const onPlay = () => setPlaying(true);
    const onPause = () => setPlaying(false);
    const onTime = () => setCurrentTime(videoEl.currentTime);
    const onMeta = () => setDuration(videoEl.duration || 0);

    videoEl.addEventListener("play", onPlay);
    videoEl.addEventListener("pause", onPause);
    videoEl.addEventListener("timeupdate", onTime);
    videoEl.addEventListener("loadedmetadata", onMeta);
    videoEl.addEventListener("durationchange", onMeta);
    videoEl.addEventListener("seeked", onTime);

    // Push initial state
    setPlaying(!videoEl.paused);
    setCurrentTime(videoEl.currentTime);
    setDuration(videoEl.duration || 0);

    return () => {
      videoEl.removeEventListener("play", onPlay);
      videoEl.removeEventListener("pause", onPause);
      videoEl.removeEventListener("timeupdate", onTime);
      videoEl.removeEventListener("loadedmetadata", onMeta);
      videoEl.removeEventListener("durationchange", onMeta);
      videoEl.removeEventListener("seeked", onTime);
    };
  }, [videoEl]);

  // High-frequency playhead updates while playing — timeupdate only fires every ~250ms.
  useEffect(() => {
    if (!videoEl || !playing) return;
    let raf = 0;
    const tick = () => {
      setCurrentTime(videoEl.currentTime);
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [videoEl, playing]);

  const toggle = useCallback(() => {
    if (!videoEl) return;
    if (videoEl.paused) videoEl.play();
    else videoEl.pause();
  }, [videoEl]);

  const seek = useCallback((sec: number) => {
    if (!videoEl) return;
    const clamped = Math.max(0, Math.min(sec, videoEl.duration || sec));
    videoEl.currentTime = clamped;
    setCurrentTime(clamped);
  }, [videoEl]);

  const skip = useCallback((deltaSec: number) => {
    if (!videoEl) return;
    const target = Math.max(0, Math.min(videoEl.currentTime + deltaSec, videoEl.duration || 0));
    videoEl.currentTime = target;
    setCurrentTime(target);
  }, [videoEl]);

  const stepFrame = useCallback((direction: 1 | -1) => {
    if (!videoEl) return;
    videoEl.pause();
    const target = Math.max(0, videoEl.currentTime + direction * (1 / fps));
    videoEl.currentTime = target;
    setCurrentTime(target);
  }, [videoEl, fps]);

  const play = useCallback(() => {
    if (!videoEl) return;
    void videoEl.play();
  }, [videoEl]);

  const pause = useCallback(() => {
    if (!videoEl) return;
    videoEl.pause();
  }, [videoEl]);

  return {
    videoRef: setVideoEl,  // callback ref
    videoEl,
    playing,
    currentTime,
    duration,
    volume,
    muted,
    toggle,
    play,
    pause,
    seek,
    skip,
    stepFrame,
    setVolume,
    setMuted,
  };
}
