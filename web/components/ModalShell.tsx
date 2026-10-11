"use client";
import type { ReactNode } from "react";
import { X } from "lucide-react";

interface Props {
  title: string;
  subtitle?: string;
  icon?: ReactNode;
  maxWidth?: number;
  onClose: () => void;
  children: ReactNode;
  footer?: ReactNode;
}

/** Khung hộp thoại dùng chung (dùng lớp .modal-overlay / .modal-content của globals.css) */
export default function ModalShell({ title, subtitle, icon, maxWidth = 460, onClose, children, footer }: Props) {
  return (
    <div className="modal-overlay" style={{ zIndex: 1100 }} onClick={onClose}>
      <div className="modal-content" role="dialog" aria-modal="true" aria-label={title} style={{ maxWidth }} onClick={(e) => e.stopPropagation()}>
        <div style={{ padding: "20px 24px 0", display: "flex", justifyContent: "space-between", gap: 12 }}>
          <div>
            <h2 style={{ fontSize: 17, fontWeight: 800, color: "var(--text)", display: "flex", alignItems: "center", gap: 8, margin: 0 }}>
              {icon} {title}
            </h2>
            {subtitle && <div style={{ fontSize: 12, color: "var(--subtext)", marginTop: 2 }}>{subtitle}</div>}
          </div>
          <button type="button" aria-label="Đóng" onClick={onClose} style={{ background: "none", border: "none", color: "var(--subtext)", cursor: "pointer" }}>
            <X size={18} />
          </button>
        </div>
        <div style={{ padding: "16px 24px" }}>{children}</div>
        {footer && <div style={{ padding: "0 24px 20px", display: "flex", justifyContent: "flex-end", gap: 10 }}>{footer}</div>}
      </div>
    </div>
  );
}

export const fieldLabel = { fontSize: 13, fontWeight: 700, color: "var(--text)", display: "block", marginBottom: 6 } as const;
export const fieldInput = {
  width: "100%",
  padding: "10px 12px",
  borderRadius: 8,
  border: "1px solid var(--border)",
  background: "var(--bg)",
  color: "var(--text)",
  fontSize: 14,
} as const;
export const btnPrimary = { padding: "9px 18px", background: "var(--primary)", color: "#fff", border: "none", borderRadius: 8, fontSize: 13, fontWeight: 600, cursor: "pointer" } as const;
export const btnGhost = { padding: "9px 16px", background: "var(--surface-muted)", color: "var(--text)", border: "none", borderRadius: 8, fontSize: 13, fontWeight: 600, cursor: "pointer" } as const;
export const errorBox = { padding: "8px 12px", background: "var(--danger-bg, #FDECEA)", color: "var(--danger, #B3261E)", borderRadius: 8, fontSize: 13, marginBottom: 12 } as const;
