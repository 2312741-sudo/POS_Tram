"use client";
import { useState } from "react";
import { Coins } from "lucide-react";
import ModalShell, { btnGhost, btnPrimary, errorBox, fieldInput, fieldLabel } from "./ModalShell";
import type { AdjustMode } from "@/lib/loyalty";
import type { StoreCustomer } from "@/lib/customers";

interface Props {
  customer: StoreCustomer;
  saving?: boolean;
  error?: string;
  onCancel: () => void;
  onSave: (mode: AdjustMode, value: number, reason: string) => void;
}

const MODES: { id: AdjustMode; label: string }[] = [
  { id: "ADD", label: "Cộng thêm" },
  { id: "SUB", label: "Trừ bớt" },
  { id: "SET", label: "Đặt lại số dư" },
];

/** Chủ quán / Quản lý chỉnh điểm của khách — bắt buộc nhập lý do, có ghi lịch sử + nhật ký */
export default function PointAdjustDialog({ customer, saving, error, onCancel, onSave }: Props) {
  const [mode, setMode] = useState<AdjustMode>("ADD");
  const [value, setValue] = useState("");
  const [reason, setReason] = useState("");
  const [localError, setLocalError] = useState("");

  const n = value.trim() === "" ? NaN : Number(value);
  const preview = !Number.isInteger(n) || n < 0 ? null : mode === "SET" ? n : mode === "ADD" ? customer.diemHienTai + n : customer.diemHienTai - n;

  const submit = () => {
    if (!Number.isInteger(n) || n < 0) return setLocalError("Số điểm phải là số nguyên ≥ 0");
    if (!reason.trim()) return setLocalError("Vui lòng nhập lý do chỉnh điểm");
    setLocalError("");
    onSave(mode, n, reason.trim());
  };
  const shown = localError || error;

  return (
    <ModalShell
      title="Chỉnh điểm khách hàng"
      subtitle={`${customer.hoTen} • ${customer.soDienThoai || customer.maKhachHang} • hiện có ${customer.diemHienTai} điểm`}
      icon={<Coins size={18} color="var(--primary)" />}
      onClose={onCancel}
      footer={
        <>
          <button type="button" style={btnGhost} onClick={onCancel}>Hủy</button>
          <button type="button" style={{ ...btnPrimary, opacity: saving ? 0.6 : 1 }} disabled={saving} onClick={submit}>
            {saving ? "Đang lưu..." : "Xác nhận chỉnh điểm"}
          </button>
        </>
      }
    >
      {shown && <div style={errorBox}>{shown}</div>}
      <div style={{ display: "flex", gap: 6, marginBottom: 12 }}>
        {MODES.map((m) => (
          <button
            key={m.id}
            type="button"
            onClick={() => setMode(m.id)}
            style={{
              flex: 1, padding: "8px 6px", borderRadius: 8, fontSize: 13, fontWeight: 600, cursor: "pointer",
              border: "1px solid var(--border)",
              background: mode === m.id ? "var(--primary)" : "var(--surface)",
              color: mode === m.id ? "#fff" : "var(--text)",
            }}
          >
            {m.label}
          </button>
        ))}
      </div>
      <label style={fieldLabel}>{mode === "SET" ? "Số dư mới (điểm)" : "Số điểm"}</label>
      <input style={fieldInput} type="number" min={0} step={1} value={value} onChange={(e) => setValue(e.target.value)} autoFocus />
      {preview !== null && (
        <div style={{ fontSize: 12, marginTop: 6, color: preview < 0 ? "var(--danger, #B3261E)" : "var(--subtext)" }}>
          Số dư sau khi chỉnh: <strong>{preview}</strong> điểm
        </div>
      )}
      <label style={{ ...fieldLabel, marginTop: 12 }}>Lý do *</label>
      <textarea style={{ ...fieldInput, minHeight: 64 }} value={reason} onChange={(e) => setReason(e.target.value)} placeholder="VD: Tặng điểm sinh nhật, sửa nhầm hóa đơn..." />
    </ModalShell>
  );
}
