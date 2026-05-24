import { useEffect, useRef } from "react";
import { aspectRatioLabel, formatBytes, formatTime } from "../lib/format";
import { ClockIcon, CloseIcon, DriveIcon, FileIcon, FrameIcon } from "./Icons";
import type { VideoInfo } from "../types";

interface Props {
  info: VideoInfo;
  anchor: HTMLButtonElement | null;
  onClose: () => void;
}

export function InfoPopover({ info, anchor, onClose }: Props) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const onDown = (e: MouseEvent) => {
      if (ref.current?.contains(e.target as Node)) return;
      if (anchor?.contains(e.target as Node)) return;
      onClose();
    };
    window.addEventListener("mousedown", onDown);
    return () => window.removeEventListener("mousedown", onDown);
  }, [anchor, onClose]);

  // Anchor to button: align popover's right edge to the right edge of the button.
  const style: React.CSSProperties = {};
  if (anchor) {
    const rect = anchor.getBoundingClientRect();
    style.top = rect.bottom + 8;
    style.right = window.innerWidth - rect.right;
  }

  return (
    <div ref={ref} className="popover popover-info" style={style}>
      <div className="popover-head">
        <span className="popover-title">VIDEO DETAILS</span>
        <button className="popover-close" onClick={onClose}><CloseIcon size={14} /></button>
      </div>
      <ul className="detail-list">
        <Row icon={<FileIcon size={16} />} value={info.fileName} />
        <Row
          icon={<FrameIcon size={16} />}
          value={`${info.width} × ${info.height} (${aspectRatioLabel(info.width, info.height)})`}
        />
        <Row icon={<ClockIcon size={16} />} value={formatTime(info.durationSec)} />
        <Row icon={<DriveIcon size={16} />} value={formatBytes(info.sizeBytes)} />
      </ul>

      <div className="detail-extra">
        <div><span>Codec</span><span>{info.codec.toUpperCase()}</span></div>
        <div><span>Container</span><span>.{info.containerExt}</span></div>
        <div><span>Framerate</span><span>{info.fps.toFixed(2)} fps</span></div>
        <div><span>Audio</span><span>{info.hasAudio ? "Ja" : "Nein"}</span></div>
        {!info.browserPlayable && (
          <div className="detail-note">Proxy-Wiedergabe aktiv (Original-Codec nicht browserkompatibel)</div>
        )}
      </div>
    </div>
  );
}

function Row({ icon, value }: { icon: React.ReactNode; value: string }) {
  return (
    <li className="detail-row">
      <span className="detail-icon">{icon}</span>
      <span className="detail-value">{value}</span>
    </li>
  );
}
