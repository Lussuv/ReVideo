import { useCallback, useEffect, useRef, useState } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { TopBar } from "./components/TopBar";
import { VideoStage } from "./components/VideoStage";
import { TrimPanel } from "./components/TrimPanel";
import { InfoPopover } from "./components/InfoPopover";
import { EmptyState } from "./components/EmptyState";
import { usePlayer } from "./hooks/usePlayer";
import {
  deleteVideoFile, ensurePlayable, exportClip, fileUrl, generateThumbnails, getAdjacentVideo, getLaunchFile, getVideoInfo,
  onFfProgress, pickExportDestination, pickVideoFile, quitApp,
} from "./lib/tauri";
import type { ExportPreset, ProgressPayload, TrimRange, VideoInfo } from "./types";

type DeleteAction = "delete" | "cancel";

const DELETE_RETRY_DELAYS_MS = [200, 350, 500, 750, 1000, 1400, 1800, 2400, 3000];
const CLOSE_DELETE_GRACE_MS = 30_000;

function delay(ms: number) {
  return new Promise((resolve) => window.setTimeout(resolve, ms));
}

async function deleteVideoFileWithRetries(path: string) {
  let lastError: unknown = null;
  for (const waitMs of DELETE_RETRY_DELAYS_MS) {
    await delay(waitMs);
    try {
      await deleteVideoFile(path);
      return;
    } catch (err) {
      lastError = err;
    }
  }
  throw lastError;
}

export default function App() {
  const [info, setInfo] = useState<VideoInfo | null>(null);
  const [src, setSrc] = useState<string | null>(null);
  const [srcMode, setSrcMode] = useState<"original" | "proxy" | null>(null);
  const [thumbnails, setThumbnails] = useState<string[]>([]);
  const [trim, setTrim] = useState<TrimRange>({ startSec: 0, endSec: 0 });
  const [checkingLaunchFile, setCheckingLaunchFile] = useState(true);
  const [loadingLaunchFile, setLoadingLaunchFile] = useState(false);
  const [loadingVideo, setLoadingVideo] = useState(false);

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
  const [deleteCandidate, setDeleteCandidate] = useState<VideoInfo | null>(null);
  const [deleteAction, setDeleteAction] = useState<DeleteAction>("delete");
  const [deleting, setDeleting] = useState(false);

  const player = usePlayer(info?.fps ?? 30);
  const loadIdRef = useRef(0);
  const deleteButtonRef = useRef<HTMLButtonElement | null>(null);
  const cancelButtonRef = useRef<HTMLButtonElement | null>(null);
  const pendingDeletePathsRef = useRef<Set<string>>(new Set());
  const activeDeleteJobsRef = useRef<Set<Promise<void>>>(new Set());
  const finishingDeletesOnCloseRef = useRef(false);

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
    setLoadingVideo(true);
    try {
      setErrorMsg(null);
      setProxying(false);
      setProxyProgress(null);
      setSrc(null);
      setSrcMode(null);
      setInfo(null);
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
    } finally {
      if (loadId === loadIdRef.current) setLoadingVideo(false);
    }
  }, []);

  const clearVideo = useCallback(() => {
    loadIdRef.current += 1;
    player.pause();
    setInfo(null);
    setSrc(null);
    setSrcMode(null);
    setThumbnails([]);
    setTrim({ startSec: 0, endSec: 0 });
    setTrimOpen(false);
    setInfoOpen(false);
    setProxying(false);
    setProxyProgress(null);
    setLoadingVideo(false);
    setPendingAutoplay(false);
  }, [player]);

  const handlePlaybackError = useCallback(() => {
    if (!info || proxying || srcMode !== "original") return;
    void startProxy(info.path);
  }, [info, proxying, srcMode, startProxy]);

  const navigateVideo = useCallback(async (direction: -1 | 1) => {
    if (!info) return;
    try {
      const path = await getAdjacentVideo(info.path, direction, [...pendingDeletePathsRef.current]);
      if (path) await loadVideo(path);
    } catch (err) {
      setErrorMsg(String(err));
    }
  }, [info, loadVideo]);

  const deleteCurrentVideo = useCallback(() => {
    if (!info || exporting || proxying || deleting) return;
    setDeleteAction("delete");
    setDeleteCandidate(info);
  }, [deleting, exporting, info, proxying]);

  const closeDeleteDialog = useCallback(() => {
    setDeleteCandidate(null);
    setDeleteAction("delete");
  }, []);

  const startBackgroundDelete = useCallback((path: string) => {
    const pending = pendingDeletePathsRef.current;
    if (pending.has(path)) return Promise.resolve();
    pending.add(path);

    const job = deleteVideoFileWithRetries(path)
      .finally(() => {
        pending.delete(path);
        activeDeleteJobsRef.current.delete(job);
      });

    activeDeleteJobsRef.current.add(job);
    return job;
  }, []);

  const waitForActiveDeletes = useCallback(async () => {
    while (activeDeleteJobsRef.current.size > 0) {
      await Promise.allSettled([...activeDeleteJobsRef.current]);
    }
  }, []);

  const finishDeletesThenClose = useCallback(async () => {
    const win = getCurrentWindow();
    if (finishingDeletesOnCloseRef.current) return;
    finishingDeletesOnCloseRef.current = true;

    if (activeDeleteJobsRef.current.size > 0) {
      try {
        await win.hide();
      } catch {
        // The app should still be able to quit if hiding the window fails.
      }
      await Promise.race([
        waitForActiveDeletes(),
        delay(CLOSE_DELETE_GRACE_MS),
      ]);
    }

    await quitApp();
  }, [waitForActiveDeletes]);

  useEffect(() => {
    let unlisten: (() => void) | null = null;
    getCurrentWindow().onCloseRequested((event) => {
      event.preventDefault();
      void finishDeletesThenClose();
    }).then((fn) => { unlisten = fn; });

    return () => { unlisten?.(); };
  }, [finishDeletesThenClose]);

  const confirmDeleteCurrentVideo = useCallback(async () => {
    if (!deleteCandidate || deleting) return;

    const targetPath = deleteCandidate.path;
    setDeleting(true);
    closeDeleteDialog();
    setLoadingVideo(true);

    try {
      const excludedPaths = [...pendingDeletePathsRef.current, targetPath];
      const nextPath = await getAdjacentVideo(targetPath, 1, excludedPaths).catch(() => null);
      player.pause();
      if (player.videoEl) {
        player.videoEl.pause();
        player.videoEl.removeAttribute("src");
        player.videoEl.load();
      }
      setSrc(null);
      setSrcMode(null);
      await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));

      const deletePromise = startBackgroundDelete(targetPath);

      if (nextPath) {
        await loadVideo(nextPath);
        setDeleting(false);
      } else {
        await deletePromise;
        clearVideo();
      }

      if (nextPath) {
        deletePromise.catch((err) => setErrorMsg(String(err)));
        return;
      }
    } catch (err) {
      setErrorMsg(String(err));
      setLoadingVideo(false);
    } finally {
      setDeleting(false);
    }
  }, [clearVideo, closeDeleteDialog, deleteCandidate, deleting, loadVideo, player, startBackgroundDelete]);

  const runSelectedDeleteAction = useCallback(() => {
    if (deleteAction === "delete") void confirmDeleteCurrentVideo();
    else closeDeleteDialog();
  }, [closeDeleteDialog, confirmDeleteCurrentVideo, deleteAction]);

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
      if (deleteCandidate) {
        if (e.code === "Escape") {
          e.preventDefault();
          closeDeleteDialog();
        } else if (e.code === "ArrowLeft") {
          e.preventDefault();
          setDeleteAction("delete");
          deleteButtonRef.current?.focus();
        } else if (e.code === "ArrowRight") {
          e.preventDefault();
          setDeleteAction("cancel");
          cancelButtonRef.current?.focus();
        } else if (e.code === "Enter") {
          e.preventDefault();
          runSelectedDeleteAction();
        }
        return;
      }
      if (e.code === "Space") { e.preventDefault(); player.toggle(); }
      else if (e.code === "ArrowLeft") player.skip(-5);
      else if (e.code === "ArrowRight") player.skip(5);
      else if (e.code === "Comma") player.stepFrame(-1);
      else if (e.code === "Period") player.stepFrame(1);
      else if (e.code === "Delete") void deleteCurrentVideo();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [closeDeleteDialog, deleteCandidate, deleteCurrentVideo, player, runSelectedDeleteAction]);

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
  const showLoading = loadingVideo || deleting || (!hasVideo && (checkingLaunchFile || loadingLaunchFile));

  return (
    <div className="app">
      <TopBar
        hasVideo={hasVideo}
        trimOpen={trimOpen}
        infoOpen={infoOpen}
        onOpenFile={openFile}
        onToggleTrim={() => setTrimOpen((v) => !v)}
        onToggleInfo={() => setInfoOpen((v) => !v)}
        onPreviousVideo={() => void navigateVideo(-1)}
        onNextVideo={() => void navigateVideo(1)}
        onDeleteVideo={() => void deleteCurrentVideo()}
        onClose={() => void finishDeletesThenClose()}
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
        ) : showLoading ? (
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

      {deleteCandidate && (
        <div className="confirm-backdrop" role="presentation" onMouseDown={closeDeleteDialog}>
          <div
            className="confirm-dialog"
            role="dialog"
            aria-modal="true"
            aria-labelledby="delete-video-title"
            onMouseDown={(e) => e.stopPropagation()}
          >
            <div className="confirm-title" id="delete-video-title">Video löschen?</div>
            <div className="confirm-text">
              "{deleteCandidate.fileName}" in den Papierkorb verschieben?
            </div>
            <div className="confirm-actions">
              <button
                ref={deleteButtonRef}
                className={`btn-danger ${deleteAction === "delete" ? "btn-selected" : ""}`}
                onClick={() => void confirmDeleteCurrentVideo()}
                onFocus={() => setDeleteAction("delete")}
                onMouseEnter={() => setDeleteAction("delete")}
                disabled={deleting}
                autoFocus
              >
                Löschen
              </button>
              <button
                ref={cancelButtonRef}
                className={`btn-secondary ${deleteAction === "cancel" ? "btn-selected" : ""}`}
                onClick={closeDeleteDialog}
                onFocus={() => setDeleteAction("cancel")}
                onMouseEnter={() => setDeleteAction("cancel")}
                disabled={deleting}
              >
                Abbrechen
              </button>
            </div>
          </div>
        </div>
      )}

      {errorMsg && (
        <div className="error-toast" role="alert" onClick={() => setErrorMsg(null)}>
          {errorMsg}
        </div>
      )}
    </div>
  );
}
