export type ExportPreset = "original" | "discord_non_nitro";

export interface VideoInfo {
  path: string;
  fileName: string;
  durationSec: number;
  width: number;
  height: number;
  sizeBytes: number;
  fps: number;
  hasAudio: boolean;
  codec: string;
  containerExt: string;
  browserPlayable: boolean;
}

export interface PlayableSource {
  path: string;
  isProxy: boolean;
}

export interface ProgressPayload {
  phase: "export" | "proxy";
  percent: number;
  speed: string;
  etaSec: number;
}

export interface TrimRange {
  startSec: number;
  endSec: number;
}

