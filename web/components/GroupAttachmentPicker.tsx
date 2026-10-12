"use client";
import { NO_GROUPS } from "@/lib/item-options";

interface Props {
  title: string;
  /** Các nhóm của chi nhánh (id, tên) */
  options: { id: string; name: string; active: boolean }[];
  /** undefined = kế thừa (món) / chưa gắn (nhóm món); mảng (kể cả rỗng) = tùy chỉnh */
  value: string[] | undefined;
  onChange: (v: string[] | undefined) => void;
  /** true = trên form món (có lựa chọn kế thừa); false = form nhóm món */
  isProduct: boolean;
  /** Tên các nhóm đang kế thừa từ nhóm món (để hiển thị) */
  inheritedLabel?: string;
}

/** "Danh mục note áp dụng" / "Nhóm topping áp dụng": kế thừa nhóm món hoặc tùy chỉnh cho món (xem docs/NOTE_CATALOG.md) */
export default function GroupAttachmentPicker({ title, options, value, onChange, isProduct, inheritedLabel }: Props) {
  const custom = value !== undefined;
  const selected = (value ?? []).filter((id) => id !== NO_GROUPS);
  const toggle = (id: string) => onChange(selected.includes(id) ? selected.filter((x) => x !== id) : [...selected, id]);
  return (
    <div style={{ border: "1px solid var(--border)", borderRadius: 10, padding: "10px 12px", background: "var(--surface)" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8 }}>
        <span style={{ fontSize: 13, fontWeight: 700, color: "var(--text)" }}>{title}</span>
        <span style={{ fontSize: 11, fontWeight: 700, padding: "2px 8px", borderRadius: 10, background: custom ? "rgba(126,41,48,0.12)" : "var(--surface-muted)", color: custom ? "var(--primary)" : "var(--subtext)" }}>
          {custom ? "Tùy chỉnh" : isProduct ? "Kế thừa" : "Chưa gắn"}
        </span>
      </div>
      {isProduct && (
        <div style={{ display: "flex", flexDirection: "column", gap: 4, margin: "8px 0", fontSize: 12 }}>
          <label style={{ display: "flex", gap: 6, alignItems: "center", cursor: "pointer" }}>
            <input type="radio" checked={!custom} onChange={() => onChange(undefined)} /> Kế thừa từ nhóm món{inheritedLabel ? `: ${inheritedLabel}` : ""}
          </label>
          <label style={{ display: "flex", gap: 6, alignItems: "center", cursor: "pointer" }}>
            <input type="radio" checked={custom} onChange={() => onChange(selected)} /> Tùy chỉnh cho món này
          </label>
        </div>
      )}
      {(custom || !isProduct) && (
        <div style={{ display: "flex", flexWrap: "wrap", gap: 6, marginTop: isProduct ? 0 : 8 }}>
          {options.length === 0 && <span style={{ fontSize: 12, color: "var(--subtext)" }}>Chưa có nhóm nào — tạo ở trang “Danh mục note &amp; topping”.</span>}
          {options.map((o) => {
            const on = selected.includes(o.id);
            return (
              <button
                key={o.id}
                type="button"
                onClick={() => toggle(o.id)}
                style={{
                  padding: "5px 12px", borderRadius: 16, fontSize: 12, fontWeight: 600, cursor: "pointer",
                  border: on ? "2px solid var(--primary)" : "1px solid var(--border)",
                  background: on ? "rgba(126,41,48,0.12)" : "var(--surface)", color: on ? "var(--primary)" : "var(--subtext)",
                }}
              >
                {on ? "✓ " : "+ "}{o.name}{o.active ? "" : " (đã tắt)"}
              </button>
            );
          })}
          {custom && selected.length === 0 && options.length > 0 && (
            <span style={{ fontSize: 11, color: "var(--subtext)", width: "100%" }}>{isProduct ? "Không chọn nhóm nào = món này KHÔNG có mục này." : "Không chọn nhóm nào = không gắn."}</span>
          )}
        </div>
      )}
    </div>
  );
}
