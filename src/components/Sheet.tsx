import { useEffect, useRef, type ReactNode } from "react";

/**
 * Bottom sheet on phones, centred dialog from 768px up. Built on the native <dialog>
 * (focus trap, Esc to close, backdrop) so it needs no extra UI library.
 */
export function Sheet({ open, onClose, title, children, footer }: {
  open: boolean; onClose: () => void; title: string; children: ReactNode; footer?: ReactNode;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const d = ref.current;
    if (!d) return;
    if (open && !d.open) d.showModal();
    if (!open && d.open) d.close();
  }, [open]);
  return (
    <dialog
      ref={ref}
      aria-label={title}
      onCancel={(e) => { e.preventDefault(); onClose(); }}
      onClick={(e) => { if (e.target === ref.current) onClose(); }}
      className="m-0 mt-auto w-full max-w-none rounded-t-3xl border border-line bg-surface p-0 text-fg backdrop:bg-black/50
                 md:m-auto md:max-w-lg md:rounded-3xl"
      style={{ maxHeight: "92dvh" }}
    >
      {open && (
        <div className="flex max-h-[92dvh] flex-col">
          <div className="flex items-center gap-3 border-b border-line px-4 py-3">
            <h2 className="h-display flex-1 text-2xl">{title}</h2>
            <button type="button" className="btn min-h-[44px] min-w-[44px] px-0" onClick={onClose} aria-label="Close">✕</button>
          </div>
          <div className="flex-1 overflow-y-auto px-4 py-4">{children}</div>
          {footer && <div className="border-t border-line px-4 py-3" style={{ paddingBottom: "max(12px, env(safe-area-inset-bottom))" }}>{footer}</div>}
        </div>
      )}
    </dialog>
  );
}

export function ConfirmDialog({ open, title, body, confirmLabel, busy, onConfirm, onClose }: {
  open: boolean; title: string; body: ReactNode; confirmLabel: string; busy?: boolean; onConfirm: () => void; onClose: () => void;
}) {
  return (
    <Sheet open={open} onClose={onClose} title={title}
      footer={
        <div className="flex gap-2">
          <button type="button" className="btn flex-1" onClick={onClose} disabled={busy}>Cancel</button>
          <button type="button" className="btn flex-1 !border-transparent !bg-[rgb(var(--nonveg))] !text-white" onClick={onConfirm} disabled={busy}>
            {busy ? "Working…" : confirmLabel}
          </button>
        </div>
      }>
      <div className="text-muted">{body}</div>
    </Sheet>
  );
}
