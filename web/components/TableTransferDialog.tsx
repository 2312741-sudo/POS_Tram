"use client";
import { useState } from "react";
import { ArrowRightLeft, GitMerge, X } from "lucide-react";
import { tableItems, type TableNode } from "@/lib/table-ops";

interface TableLike extends TableNode {
  id: string;
  name: string;
  zone: string;
}

interface Props<T extends TableLike> {
  kind: "TRANSFER" | "MERGE";
  source: T;
  /** Bàn ứng viên (đã lọc: chuyển → bàn trống chưa đặt; gộp → bàn đang có khách) */
  candidates: T[];
  busy?: boolean;
  error?: string;
  onPick: (target: T) => void;
  onCancel: () => void;
}

/** Chọn bàn đích để Chuyển bàn / Gộp bàn (khớp hộp thoại Flutter table_list_screen) */
export default function TableTransferDialog<T extends TableLike>({ kind, source, candidates, busy, error, onPick, onCancel }: Props<T>) {
  const [q, setQ] = useState("");
  const isTransfer = kind === "TRANSFER";
  const list = candidates.filter(
    (t) => !q || t.name.toLowerCase().includes(q.toLowerCase()) || (t.zone || "").toLowerCase().includes(q.toLowerCase())
  );

  return (
    <div className="modal-overlay" style={{ zIndex: 1100 }} onClick={busy ? undefined : onCancel}>
      <div
        className="modal-content"
        role="dialog"
        aria-modal="true"
        aria-labelledby="table-op-title"
        style={{ maxWidth: "420px" }}
        onClick={(e) => e.stopPropagation()}
      >
        <div style={{ padding: "20px 24px 0", display: "flex", alignItems: "center", justifyContent: "space-between", gap: "12px" }}>
          <div>
            <h2 id="table-op-title" style={{ fontSize: "17px", fontWeight: 800, color: "var(--text)", display: "flex", alignItems: "center", gap: "8px" }}>
              {isTransfer ? <ArrowRightLeft size={18} color="var(--primary)" /> : <GitMerge size={18} color="var(--warning)" />}
              {isTransfer ? "Chuyển bàn" : "Gộp bàn"}: {source.name}
            </h2>
            <div style={{ fontSize: "12px", color: "var(--subtext)", marginTop: "2px" }}>
              {isTransfer
                ? "Chọn bàn trống muốn chuyển toàn bộ đơn đến."
                : `Chọn bàn đang có khách để gộp chung hóa đơn — ${source.name} sẽ được trả về trống.`}
            </div>
          </div>
          <button type="button" aria-label="Đóng" disabled={busy} onClick={onCancel} style={{ background: "none", border: "none", color: "var(--subtext)", cursor: "pointer" }}>
            <X size={20} />
          </button>
        </div>
        <div style={{ padding: "16px 24px 24px", display: "flex", flexDirection: "column", gap: "12px" }}>
          {candidates.length > 6 && (
            <input className="input-field" placeholder="Tìm bàn / khu vực..." aria-label="Tìm bàn" value={q} onChange={(e) => setQ(e.target.value)} />
          )}
          {candidates.length === 0 ? (
            <div style={{ padding: "24px", textAlign: "center", color: "var(--subtext)", background: "var(--bg)", borderRadius: "12px", fontSize: "13px" }}>
              {isTransfer ? "Hiện không còn bàn trống nào để chuyển!" : "Không có bàn đang có khách khác để gộp!"}
            </div>
          ) : (
            <ul style={{ listStyle: "none", margin: 0, padding: 0, maxHeight: "50vh", overflowY: "auto", display: "flex", flexDirection: "column", gap: "6px" }}>
              {list.map((t) => (
                <li key={t.id}>
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => onPick(t)}
                    style={{
                      width: "100%",
                      display: "flex",
                      justifyContent: "space-between",
                      alignItems: "center",
                      gap: "10px",
                      padding: "10px 14px",
                      borderRadius: "10px",
                      border: "1px solid var(--border)",
                      background: "var(--surface)",
                      color: "var(--text)",
                      cursor: busy ? "wait" : "pointer",
                      textAlign: "left",
                    }}
                  >
                    <span>
                      <span style={{ fontWeight: 700 }}>{t.name}</span>
                      <span style={{ fontSize: "12px", color: "var(--subtext)" }}>
                        {" "}• {t.zone || "—"}
                        {!isTransfer ? ` • ${tableItems(t).length} món` : ""}
                      </span>
                    </span>
                    {isTransfer ? <ArrowRightLeft size={14} color="var(--subtext)" /> : <GitMerge size={14} color="var(--subtext)" />}
                  </button>
                </li>
              ))}
            </ul>
          )}
          {error && (
            <div role="alert" style={{ background: "var(--danger-bg)", color: "var(--danger)", borderRadius: "8px", padding: "10px 12px", fontSize: "13px" }}>
              {error}
            </div>
          )}
          <button type="button" className="btn-secondary" disabled={busy} onClick={onCancel} style={{ justifyContent: "center" }}>
            {busy ? "Đang xử lý..." : "Hủy"}
          </button>
        </div>
      </div>
    </div>
  );
}
