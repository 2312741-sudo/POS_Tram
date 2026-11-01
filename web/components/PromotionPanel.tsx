"use client";
import { useEffect, useMemo, useRef, useState } from "react";
import { get, onValue, ref } from "firebase/database";
import { Clock, Tag, Ticket, X } from "lucide-react";
import { db } from "@/lib/firebase";
import type { RawOrderLine } from "@/lib/order-math";
import { makeOrderLine, type OrderActor } from "@/lib/web-order";
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
  lateOrderBlock,
  outsideScheduleMessage,
  quoteStacked,
  rewardPlanFor,
  type PriceQuote,
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
/** Món trong thực đơn có thể làm món tặng */
export interface RewardProduct {
  id: string;
  name: string;
  price: number;
  code?: string;
  category?: string;
  unit?: string;
  isTopping?: boolean;
}

export function usePromotions(args: {
  storeCode: string;
  /** Khóa bàn — đổi bàn thì danh sách đã chọn được làm mới */
  tableKey: string;
  items: RawOrderLine[];
  groupOf?: (it: RawOrderLine) => string | null | undefined;
  guestCount?: number;
  allowStack: boolean;
  /** Thực đơn của chi nhánh — để thêm DÒNG MÓN TẶNG riêng (tặng/giảm món theo giá trị đơn) */
  rewardProducts?: RewardProduct[];
  /** Ghi thêm dòng vào đơn của bàn; trả danh sách món mới (null = lỗi). Không truyền = không thêm được món tặng */
  onAddLines?: (lines: RawOrderLine[]) => Promise<RawOrderLine[] | null>;
  /** Gỡ các dòng món tặng CHƯA gửi bếp của chương trình khỏi đơn (bỏ chương trình / đơn hết đủ điều kiện) */
  onRemoveRewardLines?: (campaignId: string) => Promise<void>;
  actor?: OrderActor;
}) {
  const { storeCode, tableKey, items, groupOf, guestCount, allowStack, rewardProducts = [], onAddLines, onRemoveRewardLines, actor } = args;
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

  const selected = useMemo(() => (selection.key === tableKey ? selection.list : []), [selection, tableKey]);
  // Đơn đã có dòng món tặng của chương trình (thêm từ app / lần trước) → chương trình đó coi như đang áp dụng
  const chosen = useMemo(() => {
    const ids = new Set(selected.map((d) => d.campaignId));
    const implicit: AppliedDiscount[] = [];
    for (const it of items) {
      const id = it.rewardCampaignId ? String(it.rewardCampaignId) : "";
      if (id && !ids.has(id) && byId[id]) {
        ids.add(id);
        implicit.push(buildAppliedDiscount(byId[id], 0));
      }
    }
    return [...selected, ...implicit];
  }, [selected, items, byId]);
  // Thêm được dòng tặng riêng (trang bàn) → chương trình tặng món chỉ giảm trên dòng tặng, không lấy món khách gọi
  const giftOnly = useMemo(
    () => new Set(onAddLines ? campaigns.filter((c) => c.campaignType.toUpperCase().replace(/_/g, "") === "ORDERVALUEITEMBENEFIT").map((c) => c.campaignId) : []),
    [campaigns, onAddLines]
  );
  const { discounts: applied, dropped } = useMemo(
    () => (campaignsLoaded ? recalculateDiscounts(chosen, byId, lines, ctx, { dedicatedOnlyFor: giftOnly }) : { discounts: chosen, dropped: [] as string[] }),
    [chosen, byId, lines, ctx, campaignsLoaded, giftOnly]
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
  const remove = (campaignId: string) => {
    setSelection({ key: tableKey, list: selected.filter((d) => d.campaignId !== campaignId) });
    // Bỏ chương trình: gỡ luôn ly tặng chưa gửi bếp (không để thành ly tính tiền)
    if (onRemoveRewardLines && items.some((l) => String(l.rewardCampaignId ?? "") === campaignId && l.isSentKitchen !== true)) {
      void onRemoveRewardLines(campaignId);
    }
  };
  // Đơn không còn đủ điều kiện (vd khách bớt món) → tự gỡ ly tặng chưa gửi bếp của chương trình đó
  const removing = useRef(new Set<string>());
  useEffect(() => {
    if (!onRemoveRewardLines || !campaignsLoaded) return;
    const live = new Set(applied.filter((d) => d.amount > 0).map((d) => d.campaignId));
    const orphan = new Set(
      items
        .filter((l) => l.rewardCampaignId && l.isSentKitchen !== true && !live.has(String(l.rewardCampaignId)) && byId[String(l.rewardCampaignId)])
        .map((l) => String(l.rewardCampaignId))
    );
    for (const id of orphan) {
      if (removing.current.has(id)) continue;
      removing.current.add(id);
      void onRemoveRewardLines(id)
        .then(() => setSelection((prev) => ({ ...prev, list: prev.list.filter((d) => d.campaignId !== id) })))
        .finally(() => removing.current.delete(id));
    }
  }, [applied, items, byId, campaignsLoaded, onRemoveRewardLines]);
  const clear = () => setSelection({ key: tableKey, list: [] });

  // Cộng dồn: báo giá chương trình cùng các chương trình đang áp dụng khác (KM theo món trước, giảm hóa đơn sau)
  const quote = (c: Campaign) => {
    const others = effective.filter((d) => d.campaignId !== c.campaignId).map((d) => byId[d.campaignId]).filter((x): x is Campaign => !!x);
    const isApplied = effective.some((d) => d.campaignId === c.campaignId);
    const ignore = new Set([...others.map((o) => o.campaignId), ...(isApplied ? [c.campaignId] : [])]);
    // Thêm được dòng tặng riêng (trang bàn) → áp dụng mới KHÔNG lấy món khách đã gọi làm món tặng (giống app)
    const dedicated = new Set(onAddLines && !isApplied ? [c.campaignId] : []);
    return quoteStacked([...others, c], lines, ctx, { ignoreScheduleFor: ignore, dedicatedOnlyFor: dedicated })[c.campaignId];
  };
  /** Đủ điều kiện nhưng chưa có món tặng → thêm được dòng tặng riêng? */
  const canAddReward = (c: Campaign, q: PriceQuote) =>
    !!onAddLines &&
    q.reasons.some((r) => r.campaignId === c.campaignId && r.reasonCode === "REWARD_ITEM_NOT_IN_BILL") &&
    !!rewardPlanFor(c, rewardProducts);
  /** Mô tả ly tặng sẽ thêm: "Trà Olong - Chanh tươi + Tăng giá Grab 2K (22.000đ → 0đ)" */
  const rewardLabel = (c: Campaign): string => {
    const plan = rewardPlanFor(c, rewardProducts);
    if (!plan) return "";
    const p = plan.candidates.length === 1 ? plan.candidates[0] : null;
    const tops = plan.toppings.map((t) => t.name).join(", ");
    const price = p ? p.price + plan.toppings.reduce((sum, t) => sum + (Number(t.price) || 0), 0) : 0;
    const name = p ? p.name : `1 trong ${plan.candidates.length} món`;
    return `${plan.units > 1 ? `${plan.units} x ` : ""}${name}${tops ? ` + ${tops}` : ""}${p ? ` (${price.toLocaleString("vi-VN")}đ → 0đ)` : ""}`;
  };
  /** Thêm dòng món tặng riêng (ghi chú "Tặng KM: …") vào đơn rồi trả số tiền giảm tính trên đơn mới (0 = không được) */
  const addRewardLine = async (c: Campaign): Promise<number> => {
    const plan = rewardPlanFor(c, rewardProducts);
    if (!plan || !onAddLines) return 0;
    let product = plan.candidates[0];
    if (plan.candidates.length > 1) {
      const pick = window.prompt(
        `Chọn món tặng (${plan.units} phần) — nhập số:\n` + plan.candidates.map((p, i) => `${i + 1}. ${p.name} (${p.price.toLocaleString("vi-VN")}đ)`).join("\n"),
        "1"
      );
      if (pick == null) return 0;
      product = plan.candidates[Math.max(0, Math.min(plan.candidates.length - 1, (parseInt(pick, 10) || 1) - 1))];
    }
    const now = Date.now();
    const line: RawOrderLine = {
      ...makeOrderLine(product, plan.units, `Tặng KM: ${c.name}`, actor ?? { username: "admin_web" }, now),
      rewardCampaignId: c.campaignId,
    };
    // Topping luôn kèm món tặng (vd 'Tăng giá Grab 2K'): gắn sẵn vào dòng tặng — được tặng luôn
    if (plan.toppings.length > 0) {
      line.selectedToppings = plan.toppings.map((t) => t.name);
      line.toppingPrice = plan.toppings.reduce((sum, t) => sum + Math.max(0, Math.trunc(t.price) || 0), 0);
    }
    const next = await onAddLines([line]);
    if (!next) return 0;
    const others = effective.map((d) => byId[d.campaignId]).filter((x): x is Campaign => !!x && x.campaignId !== c.campaignId);
    const q = quoteStacked([...others, c], linesFromOrder(next, groupOf), ctx, {
      ignoreScheduleFor: new Set(others.map((o) => o.campaignId)),
      dedicatedOnlyFor: new Set([c.campaignId]),
    })[c.campaignId];
    return q.totalPromotionDiscount;
  };
  /** Món liên quan gọi ngoài khung giờ của [c] → câu báo không áp dụng được */
  const lateItems = (c: Campaign) => outsideScheduleMessage(c, lines);
  /** Chương trình đang chạy mà đơn lẽ ra được giảm nhưng bị chặn vì món gọi ngoài khung giờ → tự báo */
  const lateBlocks = useMemo(
    () => listEligibleCampaigns(campaigns, storeCode, nowMs)
      .filter((c) => !c.hasCodes)
      .map((c) => ({ campaign: c, message: lateOrderBlock(c, lines, ctx) }))
      .filter((x): x is { campaign: Campaign; message: string } => !!x.message),
    [campaigns, storeCode, nowMs, lines, ctx]
  );

  return { campaigns, byId, eligible, applied: effective, dropped, total, add, remove, clear, quote, lateItems, lateBlocks, canAddReward, addRewardLine, rewardLabel, ctx, nowMs };
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
  const { eligible, applied, dropped, quote, lateItems, lateBlocks, canAddReward, addRewardLine, rewardLabel, add, remove } = state;
  const [blocked, setBlocked] = useState("");
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

  const toggle = async (c: Campaign, amt: number, on: boolean, addReward = false) => {
    setNotice("");
    setBlocked("");
    if (on && amt <= 0 && addReward) {
      // Đủ điều kiện: thêm dòng món tặng riêng vào đơn rồi áp dụng (không trừ món khách đã gọi)
      setBusy(true);
      try {
        amt = await addRewardLine(c);
      } finally {
        setBusy(false);
      }
      if (amt <= 0) {
        setNotice(`Chưa thêm được món tặng cho "${c.name}".`);
        return;
      }
    }
    if (on && amt <= 0) {
      // Món gọi ngoài khung giờ → báo không áp dụng được
      const late = lateItems(c);
      if (late) setBlocked(`Không áp dụng được "${c.name}": ${late}`);
      return;
    }
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
      {lateBlocks.map(({ campaign, message }) => (
        <div key={campaign.campaignId} role="alert" style={{ display: "flex", gap: "6px", alignItems: "flex-start", fontSize: "12px", fontWeight: 600, color: "var(--danger)", border: "1px solid var(--danger)", borderRadius: "8px", padding: "8px 10px", marginBottom: "8px" }}>
          <Clock size={14} style={{ flexShrink: 0, marginTop: "1px" }} />
          <span>Khuyến mãi &quot;{campaign.name}&quot; không được áp dụng: {message}</span>
        </div>
      ))}
      {blocked && !lateBlocks.some((x) => blocked.includes(x.campaign.name)) && (
        <div role="alert" style={{ display: "flex", gap: "6px", alignItems: "flex-start", fontSize: "12px", fontWeight: 600, color: "var(--danger)", border: "1px solid var(--danger)", borderRadius: "8px", padding: "8px 10px", marginBottom: "8px" }}>
          <Clock size={14} style={{ flexShrink: 0, marginTop: "1px" }} />
          <span>{blocked}</span>
        </div>
      )}
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
              // Món liên quan gọi ngoài khung giờ: vẫn cho bấm để hiện thông báo không áp dụng được
              const late = amt <= 0 && !selected ? lateItems(c) : null;
              // Đủ điều kiện nhưng chưa có món tặng: bấm để thêm dòng tặng riêng vào đơn
              const addable = amt <= 0 && !selected && !late && canAddReward(c, q);
              return (
                <label key={c.campaignId} style={{ display: "flex", alignItems: "flex-start", gap: "8px", padding: "6px 0", fontSize: "13px", opacity: amt > 0 || selected || addable ? 1 : 0.6 }}>
                  <input
                    type="checkbox"
                    checked={selected}
                    disabled={busy || !(amt > 0 || selected || late || addable)}
                    onChange={(e) => void toggle(c, amt, e.target.checked, addable)}
                    style={{ marginTop: "3px" }}
                  />
                  <span>
                    <strong>{c.name}</strong>
                    <span style={{ display: "block", fontSize: "11px", color: "var(--subtext)" }}>
                      {campaignTypeDisplay(c)} • {describeBenefit(c)}
                      {amt > 0 ? ` → -${fmt(amt)}` : late ? "" : addable ? "" : reason ? ` • ${reason}` : ""}
                    </span>
                    {late && <span style={{ display: "block", fontSize: "11px", color: "var(--danger)" }}>Món gọi ngoài khung giờ — không áp dụng được</span>}
                    {addable && (
                      <span style={{ display: "block", fontSize: "12px", color: "var(--success)", fontWeight: 700 }}>
                        Đủ điều kiện — bấm để thêm: {rewardLabel(c) || "món tặng"}
                      </span>
                    )}
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
