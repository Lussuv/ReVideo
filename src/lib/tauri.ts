import { invoke } from "@tauri-apps/api/core";
import { convertFileSrc } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import { open as openDialog, save as saveDialog } from "@tauri-apps/plugin-dialog";
import type { ExportPreset, PlayableSource, ProgressPayload, VideoInfo } from "../types";

const VIDEO_EXTS = [
  "mp4", "mkv", "mov", "avi", "webm", "flv", "wmv", "m4v", "mpg", "mpeg", "ts", "3gp"
];

export async function pickVideoFile(): Promise<string | null> {
  const result = await openDialog({
    multiple: false,
    directory: false,
    filters: [{ name: "Video", extensions: VIDEO_EXTS }],
  });
  if (Array.isArray(result)) return result[0] ?? null;
  return result ?? null;
}

export async function pickExportDestination(suggestedName: string, ext: string): Promise<string | null> {
  return await saveDialog({
    defaultPath: suggestedName,
    filters: [{ name: ext.toUpperCase(), extensions: [ext] }],
  });
}

export function fileUrl(path: string): string {
  return convertFileSrc(path);
}

export async function getVideoInfo(path: string): Promise<VideoInfo> {
  return await invoke<VideoInfo>("get_video_info", { path });
}

export async function ensurePlayable(path: string, forceProxy = false): Promise<PlayableSource> {
  return await invoke<PlayableSource>("ensure_playable", { path, forceProxy });
}

export async function getLaunchFile(): Promise<string | null> {
  return await invoke<string | null>("get_launch_file");
}

export interface ExportArgs {
  inputPath: string;
  outputPath: string;
  startSec: number;
  endSec: number;
  preset: ExportPreset;
}

export async function exportClip(args: ExportArgs): Promise<void> {
  await invoke("export_clip", { ...args });
}

export async function generateThumbnails(path: string, count: number): Promise<string[]> {
  return await invoke<string[]>("generate_thumbnails", { path, count });
}

/// Subscribe to ffmpeg progress ticks. Returns an unsubscribe function.
export async function onFfProgress(
  cb: (payload: ProgressPayload) => void,
): Promise<UnlistenFn> {
  return await listen<ProgressPayload>("ff-progress", (e) => cb(e.payload));
}
