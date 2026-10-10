"use client";
import { useState } from "react";
import { ChefHat, Minus, Plus, Trash2, X } from "lucide-react";
import { lineQuantity, lineUnitPrice, type RawOrderLine } from "@/lib/order-math";
import { DELETION_REASONS, OTHER_REASON, deletedAmountOf, resolveDeletionReason } from "@/lib/item-deletion";

const fmtVND = (n: number) => `${new Intl.NumberFormat("vi-VN").format(n)}đ`;

interface Props {
  line: RawOrderLine & { name?: unknown };
  tableName: string;
  /** Số phần đề xuất xóa (1 khi bấm "−", toàn bộ khi bấm thùng rác) */
  initialQty: number;
  saving?: boolean;
  error?: string;
  /** Món đã gửi bếp và người dùng thiếu quyền → sau bước này cần Quản lý duyệt PIN */
  needsPin?: boolean;
  onCancel: () => void;
  onConfirm: (removeQty: number, reason: string) => void;
}

/**
 * Hộp thoại xóa món / giảm số lượng món đã lưu trên bàn: bắt buộc chọn lý do
 * (hợp đồng chung với Flutter); "Khác" bắt buộc nhập nội dung.
 */
export default function DeleteItemDialog({ line, tableName, initialQty, saving, error, needsPin, onCancel, onConfirm }: Props) {
  const qty = lineQuantity(line);
  const [removeQty, setRemoveQty] = useState(Math.min(Math.max(1, initialQty), qty));
  const [choice, setChoice] = useState<string>("");
  const [other, setOther] = useState("");
  const [localError, setLocalError] = useState("");
  const sent = line.isSentKitchen === true;
  const amount = deletedAmountOf(line, removeQty);
  const removesLine = removeQty >= qty;

  const submit = () => {
    const r = resolveDeletionReason(choice, other);
    if (r.error || !r.reason) {
      setLocalError(r.error || "Vui lòng chọn lý do.");
      return;
    }
    setLocalError("");
    onConfirm(removeQty, r.reason);
  };

  const stepBtn = {
    width: "36px",
    height: "36px",
    borderRadius: "8px",
    border: "1px solid var(--border)",
    background: "var(--surface-muted)",
    color: "var(--text)",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    cursor: "pointer",
  } as const;

  const shownError = localError || error;

  return (
    <div className="modal-overlay" style={{ zIndex: 1100 }} onClick={onCancel}>
      <div
        className="modal-content"
        role="dialog"
        aria-modal="true"
        aria-labelledby="delete-item-title"
        style={{ maxWidth: "440px" }}
        onClick={(e) => e.stopPropagation()}
      >
        <div style={{ padding: "20px 24px 0", display: "flex", alignItems: "center", justifyContent: "space-between", gap: "12px" }}>
          <div>
            <h2 id="delete-item-title" style={{ fontSize: "17px", fontWeight: 800, color: "var(--text)", display: "flex", alignItems: "center", gap: "8px" }}>
              <Trash2 size={18} color="var(--danger)" /> {removesLine ? "Xóa món" : "Giảm số lượng món"}
            </h2>
            <div style={{ fontSize: "12px", color: "var(--subtext)", marginTop: "2px" }}>
              {String(line.name ?? "")} • {fmtVND(lineUnitPrice(line))} × {qty} • {tableName}
            </div>
          </div>
          <button type="button" aria-label="Đóng" onClick={onCancel} style={{ background: "none", border: "none", color: "var(--subtext)", cursor: "pointer" }}>
            <X size={20} />
          </button>
        </div>

        <div style={{ padding: "16px 24px 24px", display: "flex", flexDirection: "column", gap: "14px" }}>
          {sent && (
            <div
              role="status"
              style={{ display: "flex", alignItems: "center", gap: "8px", background: "var(--warning-bg)", color: "var(--warning)", borderRadius: "10px", padding: "8px 12px", fontSize: "12px", fontWeight: 600 }}
            >
              <ChefHat size={16} />
              Món đã gửi bếp{needsPin ? " — cần Quản lý duyệt bằng PIN sau bước này" : ""}
            </div>
          )}

          <div>
            <div style={{ fontSize: "13px", fontWeight: 700, color: "var(--text)", marginBottom: "6px" }}>Số phần xóa</div>
            <div style={{ display: "flex", alignItems: "center", gap: "10px", flexWrap: "wrap" }}>
              <button type="button" aria-label="Bớt số phần xóa" style={stepBtn} disabled={removeQty <= 1} onClick={() => setRemoveQty((q) => Math.max(1, q - 1))}>
                <Minus size={16} />
              </button>
              <span aria-live="polite" style={{ minWidth: "56px", textAlign: "center", fontWeight: 800, fontSize: "16px", color: "var(--text)" }}>
                {removeQty}/{qty}
              </span>
              <button type="button" aria-label="Thêm số phần xóa" style={stepBtn} disabled={removeQty >= qty} onClick={() => setRemoveQty((q) => Math.min(qty, q + 1))}>
                <Plus size={16} />
              </button>
              <span style={{ marginLeft: "auto", fontWeight: 800, color: "var(--danger)" }}>-{fmtVND(amount)}</span>
            </div>
          </div>

          <fieldset style={{ border: "none", padding: 0, margin: 0 }}>
            <legend style={{ fontSize: "13px", fontWeight: 700, color: "var(--text)", marginBottom: "6px" }}>
              Lý do xóa <span style={{ color: "var(--danger)" }}>*</span>
            </legend>
            <div style={{ display: "flex", flexDirection: "column", gap: "6px" }}>
              {DELETION_REASONS.map((r) => (
                <label
                  key={r}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: "10px",
                    padding: "9px 12px",
                    borderRadius: "10px",
                    border: choice === r ? "2px solid var(--primary)" : "1px solid var(--border)",
                    background: choice === r ? "var(--primary-light)" : "var(--surface)",
                    cursor: "pointer",
                    fontSize: "13px",
                    color: "var(--text)",
                    fontWeight: choice === r ? 700 : 500,
                  }}
                >
                  <input type="radio" name="delete-reason" value={r} checked={choice === r} onChange={() => setChoice(r)} />
                  {r}
                </label>
              ))}
            </div>
            {choice === OTHER_REASON && (
              <input
                className="input-field"
                autoFocus
                aria-label="Lý do cụ thể"
                placeholder="Nhập lý do cụ thể (bắt buộc)"
                value={other}
                onChange={(e) => setOther(e.target.value)}
                style={{ marginTop: "8px" }}
              />
            )}
          </fieldset>

          {shownError && (
            <div role="alert" style={{ background: "var(--danger-bg)", color: "var(--danger)", borderRadius: "8px", padding: "10px 12px", fontSize: "13px" }}>
              {shownError}
            </div>
          )}

          <div style={{ display: "flex", gap: "10px", flexWrap: "wrap" }}>
            <button type="button" className="btn-secondary" disabled={saving} onClick={onCancel} style={{ flex: 1, justifyContent: "center" }}>
              Hủy
            </button>
            <button
              type="button"
              className="btn-primary"
              disabled={saving}
              onClick={submit}
              style={{ flex: 1.4, justifyContent: "center", background: "var(--danger)", opacity: saving ? 0.7 : 1 }}
            >
              {saving ? "Đang lưu..." : removesLine ? "Xóa món" : `Xóa ${removeQty} phần`}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
