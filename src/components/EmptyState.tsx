import { FolderIcon } from "./Icons";

export function EmptyState({ onOpenFile }: { onOpenFile: () => void }) {
  return (
    <div className="empty-state">
      <h2 className="empty-title">Nichts geladen.</h2>
      <p className="empty-sub">Video öffnen, um zu starten.</p>
      <button className="btn-primary btn-empty-open" onClick={onOpenFile}>
        <FolderIcon size={18} />
        Open File
      </button>
    </div>
  );
}
