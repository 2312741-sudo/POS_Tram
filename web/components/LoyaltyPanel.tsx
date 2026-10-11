"use client";
import Link from "next/link";
import { Gift, UserCheck, UserPlus, X } from "lucide-react";
import { maskPhone } from "@/lib/customer-search";
import { buildPointsPreview, clampPointsInput, maxRedeemablePoints, type BillCustomer, type LoyaltyRates } from "@/lib/loyalty-checkout";
import type { LoyaltyTier } from "@/lib/loyalty";

const fmt = (n: number) => new Intl.NumberFormat("vi-VN").format(n);

interface Props {
  customer: BillCustomer | null;
  /** Đã có quyền xem khách (VIEW_CUSTOMERS) + vai trò đọc được customers */
  available: boolean;
  /** Lý do không dùng được (rules chặn đọc...) */
  unavailableReason?: string;
  showFullPhone: boolean;
  canRedeem: boolean;
  isOwner: boolean;
  balance: { points: number; total: number };
  rates: LoyaltyRates;
  tiers: LoyaltyTier[];
  /** Tiền còn lại sau giảm giá món + khuyến mãi (chưa trừ điểm) */
  amountBeforePoints: number;
  pointsUsed: number;
  onPointsChange: (n: number) => void;
  onPick: () => void;
  onRemove: () => void;
  busy?: boolean;
}

/** Khách hàng + tích điểm + đổi điểm của bàn (bản web của khối khách trong giỏ hàng Flutter) */
export default function LoyaltyPanel(p: Props) {
  const box = { background: "var(--surface-muted)", border: "1px solid var(--border)", borderRadius: 12, padding: "12px 14px", marginBottom: 14 } as const;

  if (!p.available) {
    return (
      <div style={{ ...box, fontSize: 12, color: "var(--subtext)" }}>
        <b style={{ color: "var(--text)" }}>Khách hàng & tích điểm:</b> {p.unavailableReason || "Bạn không có quyền xem khách hàng (VIEW_CUSTOMERS)."}
      </div>
    );
  }

  const maxUse = p.canRedeem ? maxRedeemablePoints(p.balance.points, p.amountBeforePoints, p.rates.redeemRate) : 0;
  const used = Math.min(p.pointsUsed, maxUse);
  const payable = Math.max(0, p.amountBeforePoints - used * p.rates.redeemRate);
  const pv = p.customer
    ? buildPointsPreview({ balance: p.balance.points, totalPoints: p.balance.total, payable, pointsUsed: used, rates: p.rates, tiers: p.tiers })
    : null;

  return (
    <div style={box}>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 10, flexWrap: "wrap" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8, minWidth: 0 }}>
          <UserCheck size={16} color="var(--primary)" />
          {p.customer ? (
            <div style={{ minWidth: 0 }}>
              <div style={{ fontWeight: 700, fontSize: 14, color: "var(--text)" }}>{p.customer.name || "Khách hàng"}</div>
              <div style={{ fontSize: 12, color: "var(--subtext)" }}>{p.customer.phone ? (p.showFullPhone ? p.customer.phone : maskPhone(p.customer.phone)) : "Chưa có SĐT"}</div>
            </div>
          ) : (
            <span style={{ fontSize: 13, color: "var(--subtext)" }}>Chưa chọn khách hàng tích điểm</span>
          )}
        </div>
        <div style={{ display: "flex", gap: 8 }}>
          <button type="button" className="btn-secondary" disabled={p.busy} onClick={p.onPick} style={{ padding: "6px 12px", fontSize: 12 }}>
            <UserPlus size={14} />
            {p.customer ? "Đổi khách" : "Chọn khách hàng"}
          </button>
          {p.customer && (
            <button type="button" className="btn-secondary" disabled={p.busy} onClick={p.onRemove} aria-label="Bỏ khách khỏi bàn" title="Bỏ khách khỏi bàn" style={{ padding: "6px 10px" }}>
              <X size={14} />
            </button>
          )}
        </div>
      </div>

      {p.customer && pv && (
        <div style={{ marginTop: 10, display: "grid", gap: 6, fontSize: 13 }}>
          <div style={{ display: "flex", justifyContent: "space-between", flexWrap: "wrap", gap: 4 }}>
            <span style={{ color: "var(--subtext)" }}>Điểm hiện có • hạng {pv.tierBefore}</span>
            <b style={{ color: "var(--text)" }}>{fmt(pv.before)} điểm</b>
          </div>

          {p.canRedeem && pv.before > 0 && (
            <label style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, flexWrap: "wrap" }}>
              <span style={{ color: "var(--text)", fontWeight: 600 }}>
                <Gift size={13} style={{ verticalAlign: -2, marginRight: 4 }} />
                Dùng điểm (tối đa {fmt(maxUse)}; 1 điểm = {fmt(p.rates.redeemRate)}đ)
              </span>
              <span style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
                <input
                  type="text"
                  inputMode="numeric"
                  aria-label="Số điểm muốn dùng"
                  disabled={p.busy || maxUse <= 0}
                  value={used > 0 ? String(used) : ""}
                  placeholder="0"
                  onChange={(e) => p.onPointsChange(clampPointsInput(e.target.value, maxUse))}
                  style={{ width: 86, padding: "6px 8px", borderRadius: 8, border: "1px solid var(--border)", background: "var(--bg)", color: "var(--text)", textAlign: "right" }}
                />
                {maxUse > 0 && (
                  <button type="button" className="btn-secondary" style={{ padding: "5px 9px", fontSize: 12 }} onClick={() => p.onPointsChange(used === maxUse ? 0 : maxUse)}>
                    {used === maxUse ? "Bỏ" : "Tối đa"}
                  </button>
                )}
              </span>
            </label>
          )}
          {used > 0 && (
            <div style={{ display: "flex", justifyContent: "space-between", color: "var(--danger)" }}>
              <span>Giảm từ điểm ({fmt(used)} điểm)</span>
              <b>-{fmt(used * p.rates.redeemRate)}đ</b>
            </div>
          )}

          {pv.earn > 0 ? (
            <div style={{ display: "flex", justifyContent: "space-between", color: "var(--success)", fontWeight: 700 }}>
              <span>Tích điểm</span>
              <span>+{fmt(pv.earn)} điểm</span>
            </div>
          ) : p.rates.earnRate > 0 && pv.minBillForPoint ? (
            <div style={{ color: "var(--subtext)" }}>Tích điểm: +0 (hóa đơn từ {fmt(pv.minBillForPoint)}đ được 1 điểm)</div>
          ) : (
            <div style={{ color: "var(--subtext)" }}>Tích điểm: +0 (tỷ lệ tích điểm đang bằng 0%)</div>
          )}
          <div style={{ display: "flex", justifyContent: "space-between", flexWrap: "wrap", gap: 4 }}>
            <span style={{ color: "var(--subtext)" }}>
              Điểm: {fmt(pv.before)} → {fmt(pv.after)} sau thanh toán
            </span>
            {pv.tierAfter !== pv.tierBefore && <b style={{ color: "var(--primary)" }}>Lên hạng {pv.tierAfter}</b>}
          </div>
          {p.rates.source === "default" && (
            <div style={{ fontSize: 12, color: "var(--warning)" }}>
              Chưa cấu hình tỷ lệ tích điểm (đang dùng mặc định {p.rates.earnRate}% • {fmt(p.rates.redeemRate)}đ/điểm).{" "}
              {p.isOwner && (
                <Link href="/dashboard/customers" style={{ color: "var(--primary)", fontWeight: 700 }}>
                  Cài đặt tích điểm
                </Link>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
