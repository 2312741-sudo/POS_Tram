"use client";
import { useMemo, useState, type CSSProperties } from "react";
import { Minus, Plus, Percent, ShieldCheck, X } from "lucide-react";
import {
  applyLineDiscount,
  computeLineDiscount,
  lineDiscountLabel,
  lineDiscountTotal,
  lineDiscountedQuantity,
  lineQuantity,
  lineUnitPrice,
  type RawOrderLine,
} from "@/lib/order-math";
import type { ManagerApproval } from "@/lib/manager-approval";

type Mode = "PERCENT" | "AMOUNT";

const fmtVND = (n: number) => `${new Intl.NumberFormat("vi-VN").format(n)}đ`;

interface Props {
  line: RawOrderLine & { name?: unknown };
  saving?: boolean;
  error?: string;
  /** Lần duyệt PIN của Quản lý (khi người dùng không có quyền DISCOUNT_ITEM) */
  approval?: ManagerApproval | null;
  onCancel: () => void;
  /** Dòng mới đã ghi đủ lineDiscountTotal / discountAmount / discountedQuantity */
  onSave: (next: RawOrderLine) => void;
}

/**
 * Hộp thoại giảm giá theo dòng món: chọn % hoặc đ/phần, giá trị, số phần được giảm
 * (mặc định tất cả), xem trước ngay. Logic tính dùng applyLineDiscount (khớp Flutter).
 */
export default function LineDiscountDialog({ line, saving, error, approval, onCancel, onSave }: Props) {
  const qty = lineQuantity(line);
  const unitPrice = lineUnitPrice(line);
  const existingPct = Number(line.discountPercent) || 0;
  const existingUnit = Number(line.discountUnitAmount) || 0;
  const existingTotal = lineDiscountTotal(line);

  const [mode, setMode] = useState<Mode>(existingUnit > 0 && existingPct <= 0 ? "AMOUNT" : "PERCENT");
  const [valueText, setValueText] = useState<string>(
    existingPct > 0 ? String(existingPct) : existingUnit > 0 ? String(existingUnit) : ""
  );
  const [units, setUnits] = useState<number>(existingTotal > 0 ? Math.max(1, lineDiscountedQuantity(line)) : qty);
  const [reason, setReason] = useState<string>(typeof line.discountReason === "string" ? line.discountReason : "");

  const rawValue = Math.max(0, Math.trunc(Number(valueText.replace(/[^\d]/g, "")) || 0));
  const value = mode === "PERCENT" ? Math.min(rawValue, 100) : Math.min(rawValue, unitPrice);

  const preview = useMemo(() => {
    const opts = mode === "PERCENT" ? { percent: value } : { unitAmount: value };
    const total = computeLineDiscount({ unitPrice, quantity: qty, discountedQuantity: units, ...opts });
    const next = applyLineDiscount(line, { ...opts, discountedQuantity: units });
    return { total, next, label: lineDiscountLabel(next, fmtVND) };
  }, [mode, value, units, unitPrice, qty, line]);

  const gross = unitPrice * qty;

  const save = () => {
    const next: RawOrderLine = { ...preview.next };
    const r = reason.trim();
    if (preview.total > 0 && r) next.discountReason = r;
    else delete next.discountReason;
    onSave(next);
  };

  const removeDiscount = () => {
    const next: RawOrderLine = applyLineDiscount(line, { percent: 0, unitAmount: 0, discountedQuantity: 0 });
    delete next.discountReason;
    onSave(next);
  };

  const segBtn = (active: boolean): CSSProperties => ({
    flex: 1,
    minHeight: "40px",
    borderRadius: "10px",
    border: active ? "2px solid var(--primary)" : "1px solid var(--border)",
    background: active ? "var(--primary-light)" : "var(--surface)",
    color: active ? "var(--primary)" : "var(--subtext)",
    fontWeight: active ? 700 : 500,
    fontSize: "13px",
    cursor: "pointer",
  });

  const stepBtn: CSSProperties = {
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
  };

  return (
    <div className="modal-overlay" style={{ zIndex: 1100 }} onClick={onCancel}>
      <div
        className="modal-content"
        role="dialog"
        aria-modal="true"
        aria-labelledby="line-discount-title"
        style={{ maxWidth: "420px" }}
        onClick={(e) => e.stopPropagation()}
      >
        <div style={{ padding: "20px 24px 0", display: "flex", alignItems: "center", justifyContent: "space-between", gap: "12px" }}>
          <div>
            <h2 id="line-discount-title" style={{ fontSize: "17px", fontWeight: 800, color: "var(--text)", display: "flex", alignItems: "center", gap: "8px" }}>
              <Percent size={18} color="var(--primary)" /> Giảm giá món
            </h2>
            <div style={{ fontSize: "12px", color: "var(--subtext)", marginTop: "2px" }}>
              {String(line.name ?? "")} • {fmtVND(unitPrice)} × {qty}
            </div>
          </div>
          <button type="button" aria-label="Đóng" onClick={onCancel} style={{ background: "none", border: "none", color: "var(--subtext)", cursor: "pointer" }}>
            <X size={20} />
          </button>
        </div>

        <div style={{ padding: "16px 24px 24px", display: "flex", flexDirection: "column", gap: "14px" }}>
          {approval && (
            <div
              role="status"
              style={{
                display: "flex",
                alignItems: "center",
                gap: "8px",
                background: "var(--success-bg)",
                color: "var(--success)",
                borderRadius: "10px",
                padding: "8px 12px",
                fontSize: "12px",
                fontWeight: 600,
              }}
            >
              <ShieldCheck size={16} />
              Được duyệt bởi {approval.approverName} (PIN) — hiệu lực đến{" "}
              {new Date(approval.expiresAt).toLocaleTimeString("vi-VN", { hour: "2-digit", minute: "2-digit" })}
            </div>
          )}
          <div style={{ display: "flex", gap: "8px" }}>
            <button type="button" aria-pressed={mode === "PERCENT"} style={segBtn(mode === "PERCENT")} onClick={() => setMode("PERCENT")}>
              Theo %
            </button>
            <button type="button" aria-pressed={mode === "AMOUNT"} style={segBtn(mode === "AMOUNT")} onClick={() => setMode("AMOUNT")}>
              Theo đ / phần
            </button>
          </div>

          <div>
            <label htmlFor="line-discount-value" style={{ display: "block", fontSize: "13px", fontWeight: 700, color: "var(--text)", marginBottom: "6px" }}>
              {mode === "PERCENT" ? "Phần trăm giảm (0–100%)" : `Số tiền giảm mỗi phần (tối đa ${fmtVND(unitPrice)})`}
            </label>
            <input
              id="line-discount-value"
              className="input-field"
              inputMode="numeric"
              autoFocus
              placeholder={mode === "PERCENT" ? "VD: 10" : "VD: 5000"}
              value={valueText}
              onChange={(e) => setValueText(e.target.value.replace(/[^\d]/g, ""))}
            />
            {rawValue !== value && (
              <div style={{ fontSize: "11px", color: "var(--warning)", marginTop: "4px" }}>
                Đã giới hạn ở {mode === "PERCENT" ? `${value}%` : fmtVND(value)}
              </div>
            )}
          </div>

          <div>
            <div style={{ fontSize: "13px", fontWeight: 700, color: "var(--text)", marginBottom: "6px" }}>Số phần được giảm</div>
            <div style={{ display: "flex", alignItems: "center", gap: "10px", flexWrap: "wrap" }}>
              <button type="button" aria-label="Giảm số phần" style={stepBtn} disabled={units <= 1} onClick={() => setUnits((u) => Math.max(1, u - 1))}>
                <Minus size={16} />
              </button>
              <span aria-live="polite" style={{ minWidth: "56px", textAlign: "center", fontWeight: 800, fontSize: "16px", color: "var(--text)" }}>
                {units}/{qty}
              </span>
              <button type="button" aria-label="Tăng số phần" style={stepBtn} disabled={units >= qty} onClick={() => setUnits((u) => Math.min(qty, u + 1))}>
                <Plus size={16} />
              </button>
              <button
                type="button"
                className="btn-secondary"
                disabled={units === qty}
                onClick={() => setUnits(qty)}
                style={{ padding: "6px 12px", fontSize: "12px" }}
              >
                Giảm tất cả các phần
              </button>
            </div>
          </div>

          <div>
            <label htmlFor="line-discount-reason" style={{ display: "block", fontSize: "13px", fontWeight: 700, color: "var(--text)", marginBottom: "6px" }}>
              Lý do (không bắt buộc)
            </label>
            <input
              id="line-discount-reason"
              className="input-field"
              placeholder="VD: Khách quen, món ra chậm..."
              value={reason}
              onChange={(e) => setReason(e.target.value)}
            />
          </div>

          <div
            style={{
              background: "var(--surface-muted)",
              border: "1px dashed var(--border-strong)",
              borderRadius: "12px",
              padding: "12px 14px",
              fontSize: "13px",
              display: "flex",
              flexDirection: "column",
              gap: "4px",
            }}
          >
            <div style={{ fontWeight: 700, color: preview.total > 0 ? "var(--danger)" : "var(--subtext)" }}>
              {preview.label || "Chưa có giảm giá"}
            </div>
            <div style={{ display: "flex", justifyContent: "space-between", color: "var(--subtext)" }}>
              <span>Tiền gốc</span>
              <span>{fmtVND(gross)}</span>
            </div>
            <div style={{ display: "flex", justifyContent: "space-between", color: "var(--danger)" }}>
              <span>Giảm</span>
              <span>-{fmtVND(preview.total)}</span>
            </div>
            <div style={{ display: "flex", justifyContent: "space-between", fontWeight: 800, color: "var(--primary)" }}>
              <span>Thành tiền</span>
              <span>{fmtVND(Math.max(0, gross - preview.total))}</span>
            </div>
          </div>

          {error && (
            <div role="alert" style={{ background: "var(--danger-bg)", color: "var(--danger)", borderRadius: "8px", padding: "10px 12px", fontSize: "13px" }}>
              {error}
            </div>
          )}

          <div style={{ display: "flex", gap: "10px", flexWrap: "wrap" }}>
            {existingTotal > 0 && (
              <button type="button" className="btn-secondary" disabled={saving} onClick={removeDiscount} style={{ flex: 1, justifyContent: "center", color: "var(--danger)" }}>
                Bỏ giảm giá
              </button>
            )}
            <button type="button" className="btn-secondary" disabled={saving} onClick={onCancel} style={{ flex: 1, justifyContent: "center" }}>
              Hủy
            </button>
            <button type="button" className="btn-primary" disabled={saving} onClick={save} style={{ flex: 1.4, justifyContent: "center", opacity: saving ? 0.7 : 1 }}>
              {saving ? "Đang lưu..." : "Áp dụng"}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
