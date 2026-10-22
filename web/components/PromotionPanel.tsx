"use client";
import { useEffect, useMemo, useState } from "react";
import { get, onValue, ref } from "firebase/database";
import { Tag, Ticket, X } from "lucide-react";
import { db } from "@/lib/firebase";
import type { RawOrderLine } from "@/lib/order-math";
import {
  addWithStacking,
  buildAppliedDiscount,
  campaignTypeDisplay,
  describeBenefit,
  evaluateVoucher,
  linesFromOrder,
  listEligibleCampaigns,
  normalizeVoucherCodeInput,
  parseCampaign,
  parseVoucher,
  quoteCampaign,
  quoteReason,
  recalculateDiscounts,
  type AppliedDiscount,
  type Campaign,
  type VoucherCheckResult,
} from "@/lib/pricing-engine";

const fmt = (n: number) => `${new Intl.NumberFormat("vi-VN").format(n)}đ`;
const VOUCHER_RE = /^[A-Z0-9_-]{3,32}$/;

/**
 * Trạng thái khuyến mãi của một bàn đang thanh toán. Nhân viên CHỌN chương trình hoặc nhập mã
 * (không tự áp dụng). Số tiền giảm luôn được tính lại từ giỏ hàng hiện tại bằng pricing engine:
 * thêm/bớt món thì số tiền đổi theo, chương trình hết đủ điều kiện thì tạm không tính.
 */
export function usePromotions(args: {
  storeCode: string;
  /** Khóa bàn — đổi bàn thì danh sách đã chọn được làm mới */
  tableKey: string;
  items: RawOrderLine[];
  groupOf?: (it: RawOrderLine) => string | null | undefined;
  guestCount?: number;
  allowStack: boolean;
}) {
  const { storeCode, tableKey, items, groupOf, guestCount, allowStack } = args;
  const [loaded, setLoaded] = useState<{ store: string; list: Campaign[] }>({ store: "", list: [] });
  const [selection, setSelection] = useState<{ key: string; list: AppliedDiscount[] }>({ key: "", list: [] });
  const [nowMs, setNowMs] = useState(() => Date.now());

  useEffect(() => {
    const t = setInterval(() => setNowMs(Date.now()), 30_000);
    return () => clearInterval(t);
  }, []);

  useEffect(() => {
    if (!storeCode) return;
    return onValue(
      ref(db, `stores/${storeCode}/campaigns`),
      (snap) => {
        const list: Campaign[] = [];
        snap.forEach((child) => {
          const v = child.val();
          // Bỏ node rác (trường lẻ / không phải chương trình) để không sinh khuyến mãi trống
          if (!v || typeof v !== "object" || !("campaignType" in v)) return;
          list.push(parseCampaign(child.key as string, v));
        });
        setLoaded({ store: storeCode, list });
      },
      () => setLoaded({ store: storeCode, list: [] })
    );
  }, [storeCode]);

  const campaigns = useMemo(() => (loaded.store === storeCode ? loaded.list : []), [loaded, storeCode]);
  const campaignsLoaded = loaded.store === storeCode;
  const byId = useMemo(() => Object.fromEntries(campaigns.map((c) => [c.campaignId, c])), [campaigns]);
  const lines = useMemo(() => linesFromOrder(items, groupOf), [items, groupOf]);
  const ctx = useMemo(() => ({ branchId: storeCode, guestCount, nowMs }), [storeCode, guestCount, nowMs]);

  const chosen = useMemo(() => (selection.key === tableKey ? selection.list : []), [selection, tableKey]);
  const { discounts: applied, dropped } = useMemo(
    () => (campaignsLoaded ? recalculateDiscounts(chosen, byId, lines, ctx) : { discounts: chosen, dropped: [] as string[] }),
    [chosen, byId, lines, ctx, campaignsLoaded]
  );
  const effective = useMemo(() => applied.filter((d) => d.amount > 0), [applied]);
  const total = effective.reduce((s, d) => s + d.amount, 0);

  const eligible = useMemo(() => listEligibleCampaigns(campaigns, storeCode, nowMs).filter((c) => !c.hasCodes), [campaigns, storeCode, nowMs]);

  const add = (campaign: Campaign, amount: number, opts?: { voucherCode?: string; staffNote?: string }): string[] => {
    const incoming = { discount: buildAppliedDiscount(campaign, amount, opts), campaign };
    const r = addWithStacking(effective, incoming, byId, allowStack);
    setSelection({ key: tableKey, list: r.discounts });
    return r.removed;
  };
  const remove = (campaignId: string) =>
    setSelection({ key: tableKey, list: chosen.filter((d) => d.campaignId !== campaignId) });
  const clear = () => setSelection({ key: tableKey, list: [] });

  const quote = (c: Campaign) => quoteCampaign(c, lines, ctx);

  return { campaigns, byId, eligible, applied: effective, dropped, total, add, remove, clear, quote, ctx, nowMs };
}

type PromotionsState = ReturnType<typeof usePromotions>;

interface PanelProps {
  state: PromotionsState;
  storeCode: string;
  canApply: boolean;
  /** Mã bàn đang thanh toán — để voucher đã đổi bởi chính hóa đơn này vẫn hợp lệ */
  billId?: string;
}

const box = { border: "1px solid var(--border)", borderRadius: "10px", background: "var(--surface)", padding: "12px 14px" } as const;

export default function PromotionPanel({ state, storeCode, canApply, billId }: PanelProps) {
  const { eligible, applied, dropped, quote, add, remove } = state;
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<VoucherCheckResult | null>(null);
  const [notice, setNotice] = useState("");

  const askStaffNote = (campaign: Campaign): string | null | undefined => {
    if (!campaign.requireStaffNote) return undefined;
    const note = window.prompt(`Chương trình "${campaign.name}" yêu cầu ghi chú của nhân viên:`, "");
    if (!note || !note.trim()) {
      setNotice("Bắt buộc nhập ghi chú nhân viên để áp dụng chương trình này.");
      return null;
    }
    return note.trim();
  };

  const applyCode = async () => {
    const c = normalizeVoucherCodeInput(code);
    if (!c) return;
    setNotice("");
    if (applied.some((d) => d.voucherCode === c || d.promoCode === c)) {
      setResult({ status: "notApplicable", message: "Mã này đã được áp dụng cho đơn hiện tại", discount: 0, isValid: false });
      return;
    }
    setBusy(true);
    try {
      let result: VoucherCheckResult;
      if (!VOUCHER_RE.test(c)) {
        result = evaluateVoucher({ code: c, voucher: null, campaign: null, nowMs: Date.now(), branchId: storeCode });
      } else {
        const lookup = (await get(ref(db, `stores/${storeCode}/voucher_lookup/${c}`))).val() as { campaignId?: string; voucherId?: string } | null;
        let voucher = null;
        let campaign: Campaign | null = null;
        if (lookup?.campaignId && lookup.voucherId) {
          const vSnap = await get(ref(db, `stores/${storeCode}/vouchers/${lookup.campaignId}/${lookup.voucherId}`));
          voucher = vSnap.exists() ? parseVoucher(String(lookup.voucherId), vSnap.val()) : null;
          if (voucher) {
            const cSnap = await get(ref(db, `stores/${storeCode}/campaigns/${lookup.campaignId}`));
            campaign = cSnap.exists() ? parseCampaign(String(lookup.campaignId), cSnap.val()) : null;
          }
        }
        const now = Date.now();
        result = evaluateVoucher({
          code: c,
          voucher,
          campaign,
          nowMs: now,
          branchId: storeCode,
          quote: campaign ? quote(campaign) : null,
          currentBillId: billId,
        });
      }
      setResult(result);
      if (!result.isValid || !result.campaign) return;
      const note = askStaffNote(result.campaign);
      if (note === null) return;
      const removed = add(result.campaign, result.discount, { voucherCode: c, staffNote: note });
      if (removed.length > 0) setNotice(`Đã gỡ khuyến mãi không cộng dồn được: ${removed.join(", ")}`);
      setCode("");
    } catch (e) {
      setResult({
        status: "notFound",
        message: `Không kiểm tra được mã (mất kết nối?). Vui lòng thử lại. ${e instanceof Error ? e.message : ""}`.trim(),
        discount: 0,
        isValid: false,
      });
    } finally {
      setBusy(false);
    }
  };

  const toggle = (c: Campaign, amt: number, on: boolean) => {
    setNotice("");
    if (!on) {
      remove(c.campaignId);
      return;
    }
    const note = askStaffNote(c);
    if (note === null) return;
    const removed = add(c, amt, { staffNote: note });
    if (removed.length > 0) setNotice(`Đã gỡ khuyến mãi không cộng dồn được: ${removed.join(", ")}`);
  };

  return (
    <div style={{ ...box, marginBottom: "16px" }}>
      <div style={{ display: "flex", alignItems: "center", gap: "8px", fontSize: "13px", fontWeight: 700, marginBottom: "10px" }}>
        <Tag size={16} /> Khuyến mãi & Voucher
      </div>

      {!canApply && (
        <div style={{ fontSize: "12px", color: "var(--warning)", marginBottom: "8px" }}>
          Tài khoản chưa có quyền áp dụng khuyến mãi (APPLY_PROMOTION).
        </div>
      )}

      {canApply && (
        <>
          <div style={{ display: "flex", gap: "8px", marginBottom: "8px" }}>
            <div style={{ position: "relative", flex: 1 }}>
              <Ticket size={15} style={{ position: "absolute", left: "10px", top: "50%", transform: "translateY(-50%)", color: "var(--subtext)" }} />
              <input
                className="input-field"
                style={{ width: "100%", paddingLeft: "32px", textTransform: "uppercase" }}
                placeholder="Nhập mã voucher"
                value={code}
                aria-label="Mã voucher"
                onChange={(e) => setCode(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") void applyCode();
                }}
              />
            </div>
            <button type="button" className="btn-primary" disabled={busy || !code.trim()} onClick={() => void applyCode()}>
              {busy ? "Đang kiểm tra..." : "Áp dụng"}
            </button>
          </div>
          {result && (
            <div
              role="status"
              style={{
                fontSize: "12px",
                fontWeight: 600,
                padding: "8px 10px",
                borderRadius: "8px",
                marginBottom: "8px",
                border: `1px solid ${result.isValid ? "var(--success)" : "var(--danger)"}`,
                color: result.isValid ? "var(--success)" : "var(--danger)",
                background: result.isValid ? "var(--success-bg)" : "transparent",
              }}
            >
              {result.isValid && result.discount > 0 ? `${result.message} (-${fmt(result.discount)})` : result.message}
            </div>
          )}
        </>
      )}

      {notice && <div style={{ fontSize: "12px", color: "var(--warning)", marginBottom: "8px" }}>{notice}</div>}
      {dropped.length > 0 && (
        <div style={{ fontSize: "12px", color: "var(--warning)", marginBottom: "8px" }}>
          Tạm không tính (đơn chưa đủ điều kiện): {dropped.join(", ")}
        </div>
      )}

      {applied.length > 0 && (
        <div style={{ marginBottom: "10px" }}>
          {applied.map((d) => (
            <div
              key={d.campaignId}
              style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: "8px", padding: "6px 0", fontSize: "13px", borderBottom: "1px dashed var(--border)" }}
            >
              <div>
                <strong>{d.campaignName}</strong>
                {d.voucherCode && <span style={{ color: "var(--subtext)" }}> • mã {d.voucherCode}</span>}
                {d.staffNote && <div style={{ fontSize: "11px", color: "var(--subtext)" }}>Ghi chú: {d.staffNote}</div>}
              </div>
              <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
                <span style={{ color: "var(--success)", fontWeight: 700 }}>-{fmt(d.amount)}</span>
                {canApply && (
                  <button type="button" className="btn-secondary" aria-label={`Gỡ ${d.campaignName}`} title="Gỡ khuyến mãi" onClick={() => remove(d.campaignId)} style={{ padding: "4px" }}>
                    <X size={14} />
                  </button>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      {canApply && (
        <div>
          <div style={{ fontSize: "12px", fontWeight: 700, margin: "4px 0 6px" }}>Chương trình khả dụng (chọn để áp dụng):</div>
          {eligible.length === 0 ? (
            <div style={{ fontSize: "12px", color: "var(--subtext)" }}>Hiện không có chương trình nào đang chạy tại chi nhánh này (chương trình phát hành mã thì nhập mã ở trên).</div>
          ) : (
            eligible.map((c) => {
              const q = quote(c);
              const amt = q.totalPromotionDiscount;
              const reason = quoteReason(q, c);
              const selected = applied.some((d) => d.campaignId === c.campaignId);
              return (
                <label key={c.campaignId} style={{ display: "flex", alignItems: "flex-start", gap: "8px", padding: "6px 0", fontSize: "13px", opacity: amt > 0 || selected ? 1 : 0.6 }}>
                  <input
                    type="checkbox"
                    checked={selected}
                    disabled={!(amt > 0 || selected)}
                    onChange={(e) => toggle(c, amt, e.target.checked)}
                    style={{ marginTop: "3px" }}
                  />
                  <span>
                    <strong>{c.name}</strong>
                    <span style={{ display: "block", fontSize: "11px", color: "var(--subtext)" }}>
                      {campaignTypeDisplay(c)} • {describeBenefit(c)}
                      {amt > 0 ? ` → -${fmt(amt)}` : reason ? ` • ${reason}` : ""}
                    </span>
                  </span>
                </label>
              );
            })
          )}
        </div>
      )}
    </div>
  );
}
