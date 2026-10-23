"use client";
import { useMemo, useState } from "react";
import { ClipboardList, Search, X } from "lucide-react";
import { useAuth } from "@/lib/auth";
import { useDashboardData, type HistoryOrder } from "@/lib/data-context";
import { scopeOwnBills, type BillOwnerFields } from "@/lib/bill-scope";
import { businessDayStartFor } from "@/lib/business-day";
import { nowMs } from "@/lib/kitchen";
import { billStatusLabel, formatVND, getBillTimestamp } from "@/lib/reports";
import { describeSelection } from "@/lib/product-options";
import { lineQuantity, lineUnitPrice, type RawOrderLine } from "@/lib/order-math";

const RANGES = [
  { id: "TODAY", label: "Hôm nay" },
  { id: "7D", label: "7 ngày" },
  { id: "ALL", label: "Tất cả" },
] as const;

const fmtTime = (ms: number) => (ms > 0 ? new Date(ms).toLocaleString("vi-VN") : "—");

/** Lịch sử đơn do CHÍNH tài khoản lập / thu tiền — mọi vai trò xem được (chỉ đọc) */
export default function MyOrdersPage() {
  const { user } = useAuth();
  const { historyData, historyLoaded, currentStoreCode } = useDashboardData();
  const [range, setRange] = useState<(typeof RANGES)[number]["id"]>("TODAY");
  const [search, setSearch] = useState("");
  const [selected, setSelected] = useState<HistoryOrder | null>(null);

  const mine = useMemo(
    () => scopeOwnBills(historyData as unknown as (HistoryOrder & BillOwnerFields)[], { uid: user?.uid, username: user?.username }),
    [historyData, user?.uid, user?.username]
  );

  const rows = useMemo(() => {
    const q = search.trim().toLowerCase();
    // Ngày kinh doanh: ngày bắt đầu từ "giờ bắt đầu ngày" của cửa hàng (vd. 04:00)
    const cutoffMs = businessDayStartFor(currentStoreCode) * 60_000;
    const start = new Date(nowMs() - cutoffMs);
    start.setHours(0, 0, 0, 0);
    const from = range === "TODAY" ? start.getTime() : range === "7D" ? start.getTime() - 6 * 86400_000 : 0;
    return mine
      .map((b) => ({ b, ts: getBillTimestamp(b as never) }))
      .filter(({ b, ts }) => ts - cutoffMs >= from && (!q || `${b.billCode ?? ""} ${b.orderCode ?? ""} ${b.tableName ?? ""}`.toLowerCase().includes(q)))
      .sort((a, c) => c.ts - a.ts);
  }, [mine, range, search, currentStoreCode]);

  const total = rows.filter(({ b }) => (b.status || "PAID").toUpperCase() === "PAID").reduce((s, { b }) => s + (Number(b.finalAmount ?? b.totalAmount) || 0), 0);
  const chip = (active: boolean) => ({
    padding: "6px 14px", borderRadius: 16, fontSize: 13, fontWeight: active ? 700 : 500, cursor: "pointer",
    border: active ? "1px solid var(--primary)" : "1px solid var(--border)", background: active ? "var(--primary)" : "var(--surface)", color: active ? "#fff" : "var(--subtext)",
  }) as const;

  return (
    <div style={{ padding: "24px 28px", maxWidth: 980, margin: "0 auto" }}>
      <h1 style={{ fontSize: 22, fontWeight: 800, margin: 0, display: "flex", alignItems: "center", gap: 8 }}>
        <ClipboardList size={22} /> Đơn của tôi
      </h1>
      <p style={{ fontSize: 13, color: "var(--subtext)", margin: "4px 0 14px" }}>
        Lịch sử các đơn do tài khoản {user?.fullName || user?.username} lập hoặc thu tiền. Chỉ xem, không sửa.
      </p>

      <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center", marginBottom: 12 }}>
        {RANGES.map((r) => (
          <button key={r.id} style={chip(range === r.id)} onClick={() => setRange(r.id)}>{r.label}</button>
        ))}
        <div style={{ display: "flex", alignItems: "center", gap: 6, padding: "6px 12px", border: "1px solid var(--border)", borderRadius: 8, background: "var(--bg)", flex: 1, minWidth: 180 }}>
          <Search size={14} />
          <input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Mã hóa đơn, bàn..." style={{ border: "none", background: "transparent", outline: "none", width: "100%", fontSize: 13, color: "var(--text)" }} />
        </div>
      </div>

      <div style={{ fontSize: 13, color: "var(--subtext)", marginBottom: 8 }}>
        {rows.length} đơn • Tổng đã thanh toán: <strong style={{ color: "var(--primary)" }}>{formatVND(total)}</strong>
      </div>

      <div style={{ background: "var(--surface)", border: "1px solid var(--border)", borderRadius: 14, overflowX: "auto" }}>
        <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13 }}>
          <thead>
            <tr style={{ background: "var(--bg)", textAlign: "left", color: "var(--subtext)" }}>
              <th style={{ padding: "10px 12px" }}>Mã hóa đơn</th>
              <th style={{ padding: "10px 12px" }}>Bàn</th>
              <th style={{ padding: "10px 12px" }}>Thời gian</th>
              <th style={{ padding: "10px 12px", textAlign: "right" }}>Thành tiền</th>
              <th style={{ padding: "10px 12px" }}>Trạng thái</th>
            </tr>
          </thead>
          <tbody>
            {!historyLoaded && rows.length === 0 ? (
              <tr><td colSpan={5} style={{ padding: 32, textAlign: "center" }}>Đang tải...</td></tr>
            ) : rows.length === 0 ? (
              <tr><td colSpan={5} style={{ padding: 32, textAlign: "center", color: "var(--subtext)" }}>Chưa có đơn nào trong khoảng này</td></tr>
            ) : (
              rows.map(({ b, ts }) => (
                <tr key={b.id} onClick={() => setSelected(b)} style={{ borderTop: "1px solid var(--border)", cursor: "pointer" }}>
                  <td style={{ padding: "10px 12px", fontFamily: "monospace", fontWeight: 700 }}>{b.billCode || b.orderCode || b.id}</td>
                  <td style={{ padding: "10px 12px" }}>{b.tableName || "—"}</td>
                  <td style={{ padding: "10px 12px" }}>{fmtTime(ts)}</td>
                  <td style={{ padding: "10px 12px", textAlign: "right", fontWeight: 700 }}>{formatVND(Number(b.finalAmount ?? b.totalAmount) || 0)}</td>
                  <td style={{ padding: "10px 12px" }}>{billStatusLabel(b.status)}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {selected && (
        <div className="modal-overlay" style={{ zIndex: 1100 }} onClick={() => setSelected(null)}>
          <div className="modal-content" role="dialog" aria-modal="true" style={{ maxWidth: 520 }} onClick={(e) => e.stopPropagation()}>
            <div style={{ padding: "18px 22px 0", display: "flex", justifyContent: "space-between" }}>
              <div>
                <h2 style={{ margin: 0, fontSize: 17, fontWeight: 800 }}>{selected.billCode || selected.orderCode || selected.id}</h2>
                <div style={{ fontSize: 12, color: "var(--subtext)" }}>{selected.tableName} • {fmtTime(getBillTimestamp(selected as never))} • {billStatusLabel(selected.status)}</div>
              </div>
              <button aria-label="Đóng" onClick={() => setSelected(null)} style={{ background: "none", border: "none", cursor: "pointer", color: "var(--subtext)" }}><X size={18} /></button>
            </div>
            <div style={{ padding: "14px 22px 20px" }}>
              <div style={{ display: "grid", gap: 8, marginBottom: 12 }}>
                {((selected.items ?? []) as unknown as RawOrderLine[]).map((it, i) => (
                  <div key={i} style={{ display: "flex", justifyContent: "space-between", gap: 8, fontSize: 13 }}>
                    <div>
                      <strong>{lineQuantity(it)} ×</strong> {String(it.name ?? "")}
                      {describeSelection(it) && <div style={{ fontSize: 11, color: "var(--subtext)" }}>{describeSelection(it)}</div>}
                      {it.note ? <div style={{ fontSize: 11, color: "#B06000" }}>Ghi chú: {String(it.note)}</div> : null}
                    </div>
                    <div>{formatVND(lineUnitPrice(it) * lineQuantity(it))}</div>
                  </div>
                ))}
              </div>
              <div style={{ borderTop: "1px solid var(--border)", paddingTop: 10, display: "grid", gap: 4, fontSize: 13 }}>
                <Row label="Tạm tính" value={formatVND(Number(selected.subTotal ?? selected.totalAmount) || 0)} />
                {Number(selected.totalDiscount ?? selected.discountAmount) > 0 && <Row label="Giảm giá" value={`−${formatVND(Number(selected.totalDiscount ?? selected.discountAmount))}`} />}
                <Row label="Thanh toán" value={formatVND(Number(selected.finalAmount ?? selected.totalAmount) || 0)} bold />
                <Row label="Hình thức" value={String(selected.paymentMethod || "—")} />
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function Row({ label, value, bold }: { label: string; value: string; bold?: boolean }) {
  return (
    <div style={{ display: "flex", justifyContent: "space-between", fontWeight: bold ? 800 : 400, fontSize: bold ? 15 : 13 }}>
      <span>{label}</span>
      <span>{value}</span>
    </div>
  );
}
