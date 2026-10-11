"use client";
import { useState } from "react";
import { Award, Plus, Trash2 } from "lucide-react";
import ModalShell, { btnGhost, btnPrimary, errorBox, fieldInput } from "./ModalShell";
import { DEFAULT_LOYALTY_TIERS, validateTiers, type LoyaltyTier } from "@/lib/loyalty";

interface Props {
  storeCode: string;
  tiers: LoyaltyTier[];
  saving?: boolean;
  onCancel: () => void;
  onSave: (tiers: LoyaltyTier[]) => void;
}

/** Cấu hình số điểm tích lũy tối thiểu cho từng hạng (Bạc, Vàng, ...) — Chủ quán */
export default function LoyaltyTierDialog({ storeCode, tiers, saving, onCancel, onSave }: Props) {
  const [rows, setRows] = useState<{ name: string; min: string }[]>(
    tiers.map((t) => ({ name: t.name, min: String(t.minPoints) }))
  );
  const [error, setError] = useState("");

  const submit = () => {
    const next = rows.map((r) => ({ name: r.name.trim(), minPoints: r.min.trim() === "" ? NaN : Number(r.min) }));
    const err = validateTiers(next);
    if (err) return setError(err);
    setError("");
    onSave([...next].sort((a, b) => a.minPoints - b.minPoints));
  };

  return (
    <ModalShell
      title="Cấu hình điểm theo hạng"
      subtitle={`Chi nhánh ${storeCode} • hạng xét theo tổng điểm đã tích lũy`}
      icon={<Award size={18} color="var(--primary)" />}
      maxWidth={520}
      onClose={onCancel}
      footer={
        <>
          <button type="button" style={btnGhost} onClick={() => setRows(DEFAULT_LOYALTY_TIERS.map((t) => ({ name: t.name, min: String(t.minPoints) })))}>
            Về mặc định
          </button>
          <button type="button" style={btnGhost} onClick={onCancel}>Hủy</button>
          <button type="button" style={{ ...btnPrimary, opacity: saving ? 0.6 : 1 }} disabled={saving} onClick={submit}>
            {saving ? "Đang lưu..." : "Lưu cấu hình"}
          </button>
        </>
      }
    >
      {error && <div style={errorBox}>{error}</div>}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 150px 36px", gap: 8, fontSize: 12, color: "var(--subtext)", marginBottom: 6 }}>
        <span>Tên hạng</span>
        <span>Từ (điểm)</span>
        <span />
      </div>
      <div style={{ display: "grid", gap: 8 }}>
        {rows.map((r, i) => (
          <div key={i} style={{ display: "grid", gridTemplateColumns: "1fr 150px 36px", gap: 8 }}>
            <input style={fieldInput} value={r.name} onChange={(e) => setRows(rows.map((x, j) => (j === i ? { ...x, name: e.target.value } : x)))} />
            <input
              style={fieldInput}
              type="number"
              min={0}
              step={1}
              value={r.min}
              onChange={(e) => setRows(rows.map((x, j) => (j === i ? { ...x, min: e.target.value } : x)))}
            />
            <button
              type="button"
              aria-label="Xóa hạng"
              disabled={rows.length <= 1}
              onClick={() => setRows(rows.filter((_, j) => j !== i))}
              style={{ background: "none", border: "none", cursor: rows.length <= 1 ? "not-allowed" : "pointer", color: "var(--danger, #B3261E)" }}
            >
              <Trash2 size={16} />
            </button>
          </div>
        ))}
      </div>
      <button
        type="button"
        onClick={() => setRows([...rows, { name: "", min: "" }])}
        disabled={rows.length >= 10}
        style={{ ...btnGhost, marginTop: 12, display: "inline-flex", alignItems: "center", gap: 6 }}
      >
        <Plus size={14} /> Thêm hạng
      </button>
      <p style={{ fontSize: 12, color: "var(--subtext)", marginTop: 12 }}>
        Hạng thấp nhất phải bắt đầu từ 0 điểm. Khách được xếp vào hạng cao nhất mà tổng điểm tích lũy đạt được; đổi điểm không làm khách bị tụt hạng.
      </p>
    </ModalShell>
  );
}
