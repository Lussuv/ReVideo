import { useCallback, useEffect, useRef, useState } from "react";
import { TopBar } from "./components/TopBar";
import { VideoStage } from "./components/VideoStage";
import { TrimPanel } from "./components/TrimPanel";
import { InfoPopover } from "./components/InfoPopover";
import { EmptyState } from "./components/EmptyState";
import { usePlayer } from "./hooks/usePlayer";
import {
  ensurePlayable, exportClip, fileUrl, generateThumbnails, getLaunchFile, getVideoInfo,
  onFfProgress, pickExportDestination, pickVideoFile,
} from "./lib/tauri";
import type { ExportPreset, ProgressPayload, TrimRange, VideoInfo } from "./types";

export default function App() {
  const [info, setInfo] = useState<VideoInfo | null>(null);
  const [src, setSrc] = useState<string | null>(null);
  const [srcMode, setSrcMode] = useState<"original" | "proxy" | null>(null);
  const [thumbnails, setThumbnails] = useState<string[]>([]);
  const [trim, setTrim] = useState<TrimRange>({ startSec: 0, endSec: 0 });
  const [checkingLaunchFile, setCheckingLaunchFile] = useState(true);
  const [loadingLaunchFile, setLoadingLaunchFile] = useState(false);

  const [trimOpen, setTrimOpen] = useState(false);
  const [infoOpen, setInfoOpen] = useState(false);
  const [infoAnchor, setInfoAnchor] = useState<HTMLButtonElement | null>(null);

  const [preset, setPreset] = useState<ExportPreset>("original");
  const [exporting, setExporting] = useState(false);
  const [exportProgress, setExportProgress] = useState<ProgressPayload | null>(null);
  const [proxying, setProxying] = useState(false);
  const [proxyProgress, setProxyProgress] = useState<ProgressPayload | null>(null);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [pendingAutoplay, setPendingAutoplay] = useState(false);

  const player = usePlayer(info?.fps ?? 30);
  const loadIdRef = useRef(0);

  useEffect(() => {
    let unlisten: (() => void) | null = null;
    onFfProgress((p) => {
      if (p.phase === "export") setExportProgress(p);
      else if (p.phase === "proxy") setProxyProgress(p);
    }).then((fn) => { unlisten = fn; });
    return () => { unlisten?.(); };
  }, []);

  const startProxy = useCallback(async (path: string, loadId = loadIdRef.current) => {
    setSrc(null);
    setSrcMode(null);
    setProxying(true);
    setProxyProgress({ phase: "proxy", percent: 0, speed: "", etaSec: 0 });
    setPendingAutoplay(true);

    try {
      const playable = await ensurePlayable(path, true);
      if (loadId !== loadIdRef.current) return;
      setSrcMode("proxy");
      setSrc(fileUrl(playable.path));
    } catch (err) {
      if (loadId !== loadIdRef.current) return;
      setErrorMsg(String(err));
    } finally {
      if (loadId === loadIdRef.current) {
        setProxying(false);
        setProxyProgress(null);
      }
    }
  }, []);

  const loadVideo = useCallback(async (path: string) => {
    const loadId = ++loadIdRef.current;
    try {
      setErrorMsg(null);
      setProxying(false);
      setProxyProgress(null);
      setSrc(null);
      setSrcMode(null);
      setThumbnails([]);

      const meta = await getVideoInfo(path);
      if (loadId !== loadIdRef.current) return;

      setInfo(meta);
      setTrim({ startSec: 0, endSec: meta.durationSec });
      setPendingAutoplay(true);
      setSrcMode("original");
      setSrc(fileUrl(path));

      generateThumbnails(path, 12)
        .then((paths) => {
          if (loadId === loadIdRef.current) setThumbnails(paths.map(fileUrl));
        })
        .catch(() => {
          if (loadId === loadIdRef.current) setThumbnails([]);
        });
    } catch (err) {
      if (loadId !== loadIdRef.current) return;
      setProxying(false);
      setProxyProgress(null);
      setErrorMsg(String(err));
    }
  }, []);

  const handlePlaybackError = useCallback(() => {
    if (!info || proxying || srcMode !== "original") return;
    void startProxy(info.path);
  }, [info, proxying, srcMode, startProxy]);

  const openFile = useCallback(async () => {
    const path = await pickVideoFile();
    if (!path) return;
    await loadVideo(path);
  }, [loadVideo]);

  useEffect(() => {
    let cancelled = false;
    const loadLaunchFile = async () => {
      try {
        const path = await getLaunchFile();
        if (cancelled) return;

        if (path) {
          setLoadingLaunchFile(true);
          await loadVideo(path);
        }
      } catch {
        // Launch-file detection should never block the normal empty state.
      } finally {
        if (!cancelled) {
          setLoadingLaunchFile(false);
          setCheckingLaunchFile(false);
        }
      }
    };

    void loadLaunchFile();

    return () => { cancelled = true; };
  }, [loadVideo]);

  useEffect(() => {
    if (!pendingAutoplay || !src || !player.videoEl || proxying) return;

    const video = player.videoEl;
    const play = () => {
      void video.play().catch(() => {});
      setPendingAutoplay(false);
    };

    if (video.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA) {
      play();
      return;
    }

    video.addEventListener("loadeddata", play, { once: true });
    return () => video.removeEventListener("loadeddata", play);
  }, [pendingAutoplay, src, proxying, player.videoEl]);

  const doExport = useCallback(async () => {
    if (!info) return;
    const suffixMap: Record<ExportPreset, string> = {
      original: "_trimmed",
      discord_non_nitro: "_discord",
    };
    const ext = preset === "original" ? (info.containerExt || "mp4") : "mp4";
    const base = info.fileName.replace(/\.[^.]+$/, "");
    const suggested = `${base}${suffixMap[preset]}.${ext}`;
    const dest = await pickExportDestination(suggested, ext);
    if (!dest) return;
    try {
      setExporting(true);
      setExportProgress({ phase: "export", percent: 0, speed: "", etaSec: 0 });
      setErrorMsg(null);
      await exportClip({
        inputPath: info.path,
        outputPath: dest,
        startSec: trim.startSec,
        endSec: trim.endSec,
        preset,
      });
    } catch (err) {
      setErrorMsg(String(err));
    } finally {
      setExporting(false);
      setExportProgress(null);
    }
  }, [info, preset, trim]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement) return;
      if (e.code === "Space") { e.preventDefault(); player.toggle(); }
      else if (e.code === "ArrowLeft") player.skip(-5);
      else if (e.code === "ArrowRight") player.skip(5);
      else if (e.code === "Comma") player.stepFrame(-1);
      else if (e.code === "Period") player.stepFrame(1);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [player]);

  // Loop playback within the trimmed range while trim mode is active.
  useEffect(() => {
    if (!trimOpen || !player.playing) return;
    if (player.currentTime >= trim.endSec - 0.02) {
      player.seek(trim.startSec);
    } else if (player.currentTime < trim.startSec - 0.05) {
      player.seek(trim.startSec);
    }
  }, [trimOpen, player.playing, player.currentTime, trim.startSec, trim.endSec, player.seek]);

  const hasVideo = info !== null;
  const showVideo = src !== null || proxying;
  const showLaunchLoading = !hasVideo && (checkingLaunchFile || loadingLaunchFile);

  return (
    <div className="app">
      <TopBar
        hasVideo={hasVideo}
        trimOpen={trimOpen}
        infoOpen={infoOpen}
        onOpenFile={openFile}
        onToggleTrim={() => setTrimOpen((v) => !v)}
        onToggleInfo={() => setInfoOpen((v) => !v)}
        onInfoButtonMount={setInfoAnchor}
      />

      <main className="content">
        {showVideo && info ? (
          <>
            <VideoStage
              src={src ?? ""}
              player={player}
              proxying={proxying}
              proxyProgress={proxyProgress}
              onPlaybackError={handlePlaybackError}
            />
            {trimOpen && (
              <TrimPanel
                duration={info.durationSec}
                trim={trim}
                onTrimChange={setTrim}
                currentTime={player.currentTime}
                onSeek={player.seek}
                thumbnails={thumbnails}
                preset={preset}
                onPresetChange={setPreset}
                onExport={doExport}
                exporting={exporting}
                exportProgress={exportProgress}
              />
            )}
          </>
        ) : showLaunchLoading ? (
          <div className="launch-loading" role="status" aria-label="Opening video">
            <div className="proxy-spinner" />
          </div>
        ) : (
          <EmptyState onOpenFile={openFile} />
        )}

        {infoOpen && info && (
          <InfoPopover
            info={info}
            anchor={infoAnchor}
            onClose={() => setInfoOpen(false)}
          />
        )}
      </main>

      {errorMsg && (
        <div className="error-toast" role="alert" onClick={() => setErrorMsg(null)}>
          {errorMsg}
        </div>
      )}
    </div>
  );
}
