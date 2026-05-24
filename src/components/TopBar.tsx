import { getCurrentWindow } from "@tauri-apps/api/window";
import { CloseIcon, FolderIcon, InfoIcon, MaxIcon, MinIcon, ScissorsIcon } from "./Icons";
import logoUrl from "../../src-tauri/icons/icon.png";

interface Props {
  hasVideo: boolean;
  trimOpen: boolean;
  infoOpen: boolean;
  onOpenFile: () => void;
  onToggleTrim: () => void;
  onToggleInfo: () => void;
  onInfoButtonMount?: (el: HTMLButtonElement | null) => void;
}

export function TopBar({
  hasVideo, trimOpen, infoOpen,
  onOpenFile, onToggleTrim, onToggleInfo, onInfoButtonMount,
}: Props) {
  const win = () => { try { return getCurrentWindow(); } catch { return null; } };

  return (
    <header className="topbar" data-tauri-drag-region>
      <div className="brand" data-tauri-drag-region>
        <Logo />
        <span className="brand-name">
          <span className="brand-name-re">Re</span>
          <span className="brand-name-video">Video</span>
        </span>
      </div>

      <nav className="tabs" data-tauri-drag-region>
        <button className="tab" onClick={onOpenFile}>
          <FolderIcon size={16} />
          <span>Open File</span>
        </button>
        <button
          className={`tab ${trimOpen ? "tab-active" : ""}`}
          onClick={onToggleTrim}
          disabled={!hasVideo}
        >
          <ScissorsIcon size={16} />
          <span>Trim</span>
        </button>
        <button
          ref={onInfoButtonMount}
          className={`tab ${infoOpen ? "tab-active" : ""}`}
          onClick={onToggleInfo}
          disabled={!hasVideo}
        >
          <InfoIcon size={16} />
          <span>Info</span>
        </button>
      </nav>

      <div className="window-controls">
        <button className="wc-btn" onClick={() => win()?.minimize()}><MinIcon size={14} /></button>
        <button className="wc-btn" onClick={() => win()?.toggleMaximize()}><MaxIcon size={12} /></button>
        <button className="wc-btn wc-close" onClick={() => win()?.close()}><CloseIcon size={14} /></button>
      </div>
    </header>
  );
}

function Logo() {
  return (
    <div className="logo">
      <img src={logoUrl} alt="ReVideo" width={28} height={28} />
    </div>
  );
}
