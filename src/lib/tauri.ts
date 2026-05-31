import { invoke } from "@tauri-apps/api/core";
import { convertFileSrc } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import { open as openDialog, save as saveDialog } from "@tauri-apps/plugin-dialog";
import { writeFile } from "@tauri-apps/plugin-fs";
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

export async function getAdjacentVideo(
  path: string,
  direction: -1 | 1,
  excludedPaths: string[] = [],
): Promise<string | null> {
  return await invoke<string | null>("get_adjacent_video", { path, direction, excludedPaths });
}

export async function deleteVideoFile(path: string): Promise<void> {
  await invoke("delete_video_file", { path });
}

export async function quitApp(): Promise<void> {
  await invoke("quit_app");
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

export async function saveImageFile(path: string, base64DataUrl: string): Promise<void> {
  const base64Data = base64DataUrl.replace(/^data:image\/\w+;base64,/, "");
  const binaryString = atob(base64Data);
  const len = binaryString.length;
  const bytes = new Uint8Array(len);
  for (let i = 0; i < len; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  await writeFile(path, bytes);
}
