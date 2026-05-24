import { FolderIcon } from "./Icons";

export function EmptyState({ onOpenFile }: { onOpenFile: () => void }) {
  return (
    <div className="empty-state">
      <button className="btn-primary btn-empty-open" onClick={onOpenFile}>
        <FolderIcon size={18} />
        Open File
      </button>
    </div>
  );
}
