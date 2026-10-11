/**
 * Pricing Engine cho Web — bản chuyển TypeScript của app_flutter/lib/core/domain/pricing_engine.dart
 * (+ campaign_pricing.dart, voucher_check.dart, PromotionUsageMath trong order_integrity.dart).
 * Hàm thuần, không đụng Firebase. Tỉ lệ % lưu dạng basis points (5000 = 50%, 10000 = 100%).
 *
 * Thứ tự áp dụng (giống Flutter): giảm thủ công theo dòng → KM theo món (đồng giá, Mua X tặng/giảm Y,
 * giảm/tặng món theo giá trị hóa đơn) → giảm giá hóa đơn (tính trên giá trị còn lại).
 * Món thưởng chỉ giảm trên các dòng ĐÃ CÓ trong hóa đơn (engine không tự thêm dòng), phần rẻ nhất trước.
 * Web KHÔNG tự áp dụng: nhân viên chọn chương trình hoặc nhập mã (engine chỉ tính số tiền).
 */
import { normalizeStackingMode } from "./campaign-form";
import { lineDiscountTotal, lineQuantity, lineUnitPrice, computeLineDiscount, type RawOrderLine } from "./order-math";

// ==================== MODEL ====================
export interface CampaignTier {
  tierId: string;
  conditionBasis: string;
  threshold: number;
  benefitMode: string;
  value: number;
  maxDiscountMoney: number;
  maxRewardQty: number;
  rewardItemIds: string[];
  sortOrder: number;
}

export interface CampaignBuyCondition {
  conditionId: string;
  buyItemIds: string[];
  requiredBuyQty: number;
  rewardItemIds: string[];
  rewardQty: number;
  benefitMode: string;
  value: number;
  multiplyByBundle: boolean;
}

export interface CampaignSchedule {
  absoluteStart?: number;
  absoluteEnd?: number;
  timeSlots: { startTime: string; endTime: string }[];
  /** 1..7 với 1 = Thứ 2, 7 = CN */
  daysOfWeek: number[];
}

export interface Campaign {
  campaignId: string;
  programCode: string;
  name: string;
  description: string;
  campaignType: string;
  schedule: CampaignSchedule;
  branchIds: string[];
  includedCustomerIds: string[];
  excludedCustomerIds: string[];
  includedItemIds: string[];
  includedGroupIds: string[];
  excludedItemIds: string[];
  tiers: CampaignTier[];
  buyConditions: CampaignBuyCondition[];
  budgetMoney?: number;
  maxUses?: number;
  maxUsesPerCustomer?: number;
  hasCodes: boolean;
  autoApply: boolean;
  requireStaffNote: boolean;
  /** "ENABLED" | "DISABLED" (đã chuẩn hóa, "STACKABLE" cũ = ENABLED) */
  stackingMode: "ENABLED" | "DISABLED";
  priority: number;
  active: boolean;
  createdAt: number;
}

const toInt = (v: unknown): number => {
  const n = Number(v);
  return Number.isFinite(n) ? Math.trunc(n) : 0;
};
const optInt = (v: unknown): number | undefined => {
  if (v === null || v === undefined || v === "") return undefined;
  const n = Number(v);
  return Number.isFinite(n) ? Math.trunc(n) : undefined;
};
/** RTDB có thể trả mảng hoặc object khi mảng thưa */
function asList(v: unknown): unknown[] {
  if (Array.isArray(v)) return v.filter((x) => x !== null && x !== undefined);
  if (v && typeof v === "object") return Object.values(v as Record<string, unknown>);
  return [];
}
const strList = (v: unknown): string[] => asList(v).map(String);

/** Khớp CampaignTier.fromMap (Flutter), gồm fallback benefitType / thresholdValue / benefitValue */
export function parseTier(raw: Record<string, unknown>): CampaignTier {
  let mode = raw.benefitMode != null ? String(raw.benefitMode) : "";
  if (!mode) {
    const bType = String(raw.benefitType ?? "").toUpperCase();
    if (bType === "DISCOUNT_PERCENT" || bType === "PERCENT") mode = "PERCENT";
    else if (bType === "DISCOUNT_AMOUNT" || bType === "AMOUNT" || bType === "FIXED_PRICE") mode = "FIXED";
    else mode = "PERCENT";
  }
  let cond = raw.conditionBasis != null ? String(raw.conditionBasis) : "";
  if (!cond) cond = "TOTALAMOUNT";
  return {
    tierId: raw.tierId != null ? String(raw.tierId) : "",
    conditionBasis: cond,
    threshold: toInt(raw.threshold ?? raw.thresholdValue ?? 0),
    benefitMode: mode,
    value: toInt(raw.value ?? raw.benefitValue ?? 0),
    maxDiscountMoney: toInt(raw.maxDiscountMoney ?? raw.maxBenefitValue ?? 0),
    maxRewardQty: toInt(raw.maxRewardQty ?? 0),
    rewardItemIds: strList(raw.rewardItemIds),
    sortOrder: toInt(raw.sortOrder ?? raw.tierIndex ?? 0),
  };
}

export function parseBuyCondition(raw: Record<string, unknown>): CampaignBuyCondition {
  return {
    conditionId: raw.conditionId != null ? String(raw.conditionId) : "",
    buyItemIds: strList(raw.buyItemIds),
    requiredBuyQty: toInt(raw.requiredBuyQty),
    rewardItemIds: strList(raw.rewardItemIds),
    rewardQty: toInt(raw.rewardQty),
    benefitMode: raw.benefitMode != null ? String(raw.benefitMode) : "PERCENT",
    value: toInt(raw.value),
    multiplyByBundle: raw.multiplyByBundle === undefined || raw.multiplyByBundle === null ? true : Boolean(raw.multiplyByBundle),
  };
}

/** Khớp CampaignModel.fromMap: dữ liệu RTDB thô → Campaign */
export function parseCampaign(id: string, raw: Record<string, unknown> | null | undefined): Campaign {
  const r = raw ?? {};
  const sch = (r.schedule && typeof r.schedule === "object" ? r.schedule : {}) as Record<string, unknown>;
  return {
    campaignId: String(r.campaignId ?? id),
    programCode: r.programCode != null ? String(r.programCode) : "",
    name: r.name != null ? String(r.name) : "",
    description: r.description != null ? String(r.description) : "",
    campaignType: r.campaignType != null ? String(r.campaignType) : "BILLDISCOUNT",
    schedule: {
      absoluteStart: optInt(sch.absoluteStart),
      absoluteEnd: optInt(sch.absoluteEnd),
      timeSlots: asList(sch.timeSlots).map((s) => {
        const o = (s && typeof s === "object" ? s : {}) as Record<string, unknown>;
        return { startTime: o.startTime != null ? String(o.startTime) : "00:00", endTime: o.endTime != null ? String(o.endTime) : "23:59" };
      }),
      daysOfWeek: asList(sch.daysOfWeek).map(toInt),
    },
    branchIds: strList(r.branchIds),
    includedCustomerIds: strList(r.includedCustomerIds),
    excludedCustomerIds: strList(r.excludedCustomerIds),
    includedItemIds: strList(r.includedItemIds),
    includedGroupIds: strList(r.includedGroupIds),
    excludedItemIds: strList(r.excludedItemIds),
    tiers: asList(r.tiers).map((t) => parseTier((t ?? {}) as Record<string, unknown>)),
    buyConditions: asList(r.buyConditions).map((c) => parseBuyCondition((c ?? {}) as Record<string, unknown>)),
    budgetMoney: optInt(r.budgetMoney),
    maxUses: optInt(r.maxUses),
    maxUsesPerCustomer: optInt(r.maxUsesPerCustomer),
    hasCodes: Boolean(r.hasCodes),
    autoApply: Boolean(r.autoApply),
    requireStaffNote: Boolean(r.requireStaffNote),
    stackingMode: normalizeStackingMode(r.stackingMode != null ? String(r.stackingMode) : null),
    priority: toInt(r.priority),
    active: Boolean(r.active),
    createdAt: toInt(r.createdAt),
  };
}

// ==================== LỊCH / CHI NHÁNH ====================
function slotContains(slot: { startTime: string; endTime: string }, hour: number, minute: number): boolean {
  const sp = slot.startTime.split(":");
  const ep = slot.endTime.split(":");
  if (sp.length < 2 || ep.length < 2) return true;
  const pi = (s: string, d: number) => {
    const n = parseInt(s, 10);
    return Number.isNaN(n) ? d : n;
  };
  const start = pi(sp[0], 0) * 60 + pi(sp[1], 0);
  const end = pi(ep[0], 23) * 60 + pi(ep[1], 59);
  const cur = hour * 60 + minute;
  // Khung giờ qua đêm (22:00 -> 02:00)
  return start <= end ? cur >= start && cur <= end : cur >= start || cur <= end;
}

/** Khớp CampaignModel.isEligibleAt (không xét cờ active) */
export function isEligibleAt(c: Campaign, ts: number): boolean {
  const s = c.schedule;
  if (s.absoluteStart != null && ts < s.absoluteStart) return false;
  if (s.absoluteEnd != null && ts > s.absoluteEnd) return false;
  const dt = new Date(ts);
  if (s.daysOfWeek.length > 0) {
    const weekday = dt.getDay() === 0 ? 7 : dt.getDay();
    if (!s.daysOfWeek.includes(weekday)) return false;
  }
  if (s.timeSlots.length > 0) {
    if (!s.timeSlots.some((slot) => slotContains(slot, dt.getHours(), dt.getMinutes()))) return false;
  }
  return true;
}

export function isEligibleForBranch(c: Campaign, branchId: string): boolean {
  return c.branchIds.length === 0 || c.branchIds.includes(branchId);
}

/** Chương trình đang chạy được tại chi nhánh lúc [nowMs]: active + lịch + chi nhánh (KHÔNG xét điều kiện đơn). */
export function listEligibleCampaigns(campaigns: Campaign[], branchId: string, nowMs: number): Campaign[] {
  return campaigns
    .filter((c) => c.active && isEligibleAt(c, nowMs) && isEligibleForBranch(c, branchId))
    .sort((a, b) => a.priority - b.priority || a.createdAt - b.createdAt);
}

// ==================== ĐẦU VÀO / ĐẦU RA ====================
export interface PricingLine {
  lineId: string;
  itemId: string;
  groupId?: string | null;
  quantity: number;
  unitPrice: number;
  isGift?: boolean;
  discountedQuantity?: number;
  discountPercent?: number;
  discountUnitAmount?: number;
  /** Ghi đè giảm thủ công của dòng (dòng cũ chỉ có discountAmount cả dòng) */
  manualDiscount?: number;
}

export interface PricingInput {
  branchId: string;
  guestCount?: number | null;
  nowMs: number;
  lines: PricingLine[];
  manualDiscountMoney?: number;
}

export interface QuoteReason {
  campaignId: string;
  reasonCode: string;
  reasonMessage: string;
}

export interface LineBenefit {
  lineId: string;
  campaignId: string;
  tierId: string;
  discountMoney: number;
  originalPrice: number;
  effectivePrice: number;
  isGift: boolean;
  quantity?: number;
}

export interface BillBenefit {
  campaignId: string;
  tierId: string;
  discountMoney: number;
  lineAllocations: Record<string, number>;
}

export interface PriceQuote {
  grossMoney: number;
  totalPromotionDiscount: number;
  manualDiscount: number;
  totalDiscountMoney: number;
  netMoney: number;
  lineBenefits: LineBenefit[];
  rewardBenefits: LineBenefit[];
  billBenefits: BillBenefit[];
  appliedCampaignIds: string[];
  reasons: QuoteReason[];
}

const isType = (type: string, compact: string) => type.toUpperCase().replace(/_/g, "") === compact;

/** FREE (tặng 100%), PERCENT (basis points), FIXED (đ/phần), FIXEDPRICE (đồng giá) */
export function normalizeBenefitMode(mode: string): string {
  const u = String(mode ?? "").toUpperCase().replace(/_/g, "");
  switch (u) {
    case "FREEITEM":
    case "FREE":
    case "GIFT":
      return "FREE";
    case "PERCENT":
    case "DISCOUNTPERCENT":
      return "PERCENT";
    case "FIXED":
    case "AMOUNT":
    case "DISCOUNTAMOUNT":
      return "FIXED";
    case "FIXEDPRICE":
      return "FIXEDPRICE";
    default:
      return u;
  }
}

const clamp = (v: number, lo: number, hi: number) => Math.min(Math.max(v, lo), hi);

function unitBenefit(mode: string, value: number, unitPrice: number): number {
  if (unitPrice <= 0) return 0;
  switch (normalizeBenefitMode(mode)) {
    case "FREE":
      return unitPrice;
    case "PERCENT":
      return Math.floor((unitPrice * clamp(value, 0, 10000)) / 10000);
    case "FIXED":
      return Math.min(Math.max(0, value), unitPrice);
    case "FIXEDPRICE":
      return Math.max(0, unitPrice - value);
    default:
      return 0;
  }
}

function manualLineDiscount(l: PricingLine): number {
  if (l.isGift) return 0;
  if (l.manualDiscount != null) return Math.min(Math.max(0, l.manualDiscount), l.unitPrice * l.quantity);
  return computeLineDiscount({
    unitPrice: l.unitPrice,
    quantity: l.quantity,
    discountedQuantity: l.discountedQuantity ?? 0,
    percent: l.discountPercent ?? 0,
    unitAmount: l.discountUnitAmount ?? 0,
  });
}

// ==================== ENGINE ====================
export function calculatePrice(input: PricingInput, activeCampaigns: Campaign[]): PriceQuote {
  let grossMoney = 0;
  for (const l of input.lines) if (!l.isGift) grossMoney += l.unitPrice * l.quantity;

  const reasons: QuoteReason[] = [];
  const appliedCampaigns: string[] = [];
  let totalDiscount = 0;
  const eligibleBillDiscounts: Campaign[] = [];
  const rewardBenefits: LineBenefit[] = [];

  const lineFinal: Record<string, number> = {};
  const lineDisc: Record<string, number> = {};
  let manualLineTotal = 0;
  for (const l of input.lines) {
    if (l.isGift) continue;
    const manual = manualLineDiscount(l);
    manualLineTotal += manual;
    lineFinal[l.lineId] = l.unitPrice * l.quantity - manual;
    lineDisc[l.lineId] = manual;
  }
  const afterManual: Record<string, number> = { ...lineFinal };
  const rewardedUnits: Record<string, number> = {};

  const addReason = (c: Campaign, code: string, msg: string) =>
    reasons.push({ campaignId: c.campaignId, reasonCode: code, reasonMessage: msg });
  const markApplied = (id: string) => {
    if (!appliedCampaigns.includes(id)) appliedCampaigns.push(id);
  };
  const inScope = (c: Campaign, l: PricingLine) => {
    if (l.isGift) return false;
    if (c.excludedItemIds.includes(l.itemId)) return false;
    if (c.includedItemIds.length === 0 && c.includedGroupIds.length === 0) return true;
    return c.includedItemIds.includes(l.itemId) || (l.groupId != null && c.includedGroupIds.includes(l.groupId));
  };

  const rewardUnitsOnLine = (line: PricingLine, units: number, mode: string, value: number, campaignId: string, tierId: string): number => {
    const avail = line.quantity - (rewardedUnits[line.lineId] ?? 0);
    if (units <= 0 || avail <= 0) return 0;
    const k = Math.min(units, avail);
    const remaining = Math.max(0, lineFinal[line.lineId] ?? 0);
    const perUnit = unitBenefit(mode, value, line.unitPrice);
    const amount = Math.min(perUnit * k, Math.floor((remaining * k) / avail));
    rewardedUnits[line.lineId] = (rewardedUnits[line.lineId] ?? 0) + k;
    if (amount <= 0) return 0;
    lineDisc[line.lineId] = (lineDisc[line.lineId] ?? 0) + amount;
    lineFinal[line.lineId] = remaining - amount;
    rewardBenefits.push({
      lineId: line.lineId,
      campaignId,
      tierId,
      discountMoney: amount,
      originalPrice: line.unitPrice * k,
      effectivePrice: line.unitPrice * k - amount,
      isGift: normalizeBenefitMode(mode) === "FREE",
      quantity: k,
    });
    return amount;
  };

  const distributeReward = (a: {
    candidates: PricingLine[];
    units: number;
    mode: string;
    value: number;
    campaignId: string;
    tierId: string;
    isBoth?: (l: PricingLine) => boolean;
    maxFromBoth?: number;
  }): number => {
    const sorted = [...a.candidates].sort((x, y) => {
      const c = x.unitPrice - y.unitPrice;
      if (c !== 0) return c;
      return x.lineId < y.lineId ? -1 : x.lineId > y.lineId ? 1 : 0;
    });
    let left = a.units;
    let bothLeft = a.maxFromBoth ?? 1 << 30;
    let total = 0;
    for (const l of sorted) {
      if (left <= 0) break;
      const avail = l.quantity - (rewardedUnits[l.lineId] ?? 0);
      if (avail <= 0) continue;
      const both = a.isBoth?.(l) ?? false;
      let take = Math.min(avail, left);
      if (both) take = Math.min(take, bothLeft);
      if (take <= 0) continue;
      total += rewardUnitsOnLine(l, take, a.mode, a.value, a.campaignId, a.tierId);
      left -= take;
      if (both) bothLeft -= take;
    }
    return total;
  };

  for (const campaign of activeCampaigns) {
    if (!isEligibleAt(campaign, input.nowMs)) {
      addReason(campaign, "OUTSIDE_SCHEDULE", "Ngoài thời gian áp dụng");
      continue;
    }
    if (!isEligibleForBranch(campaign, input.branchId)) {
      addReason(campaign, "BRANCH_NOT_SUPPORTED", "Không áp dụng tại chi nhánh này");
      continue;
    }
    const type = campaign.campaignType;

    if (isType(type, "BILLDISCOUNT")) {
      if (campaign.tiers.length > 0 && campaign.tiers[0].conditionBasis === "GUESTCOUNT") {
        if (input.guestCount == null || input.guestCount < campaign.tiers[0].threshold) {
          addReason(campaign, "GUEST_COUNT_REQUIRED", "Chưa đủ số lượng khách");
          continue;
        }
      }
      eligibleBillDiscounts.push(campaign);
    } else if (isType(type, "BUYXGETY")) {
      let campaignDiscount = 0;
      let earnedAny = false;
      for (const cond of campaign.buyConditions) {
        const buyIds = new Set(cond.buyItemIds);
        const rewardIds = new Set(cond.rewardItemIds);
        const buyQty = cond.requiredBuyQty;
        const rewardQty = cond.rewardQty;
        if (buyIds.size === 0 || rewardIds.size === 0 || buyQty <= 0 || rewardQty <= 0) {
          addReason(campaign, "INVALID_CONFIG", "Điều kiện Mua X tặng/giảm Y chưa cấu hình đủ");
          continue;
        }
        let xo = 0, yo = 0, bo = 0; // chỉ X, chỉ Y, vừa X vừa Y
        for (const l of input.lines) {
          if (l.isGift || campaign.excludedItemIds.includes(l.itemId)) continue;
          const isX = buyIds.has(l.itemId);
          const isY = rewardIds.has(l.itemId);
          const a = Math.max(0, l.quantity - (rewardedUnits[l.lineId] ?? 0));
          if (isX && isY) bo += a;
          else if (isX) xo += a;
          else if (isY) yo += a;
        }
        const maxB = cond.multiplyByBundle
          ? Math.floor((xo + bo) / buyQty)
          : Math.min(1, Math.floor((xo + bo) / buyQty));
        let bestB = 0, bestReward = 0, bestBothAllowed = 0;
        for (let b = 1; b <= maxB; b++) {
          const needFromBoth = Math.max(0, b * buyQty - xo);
          if (needFromBoth > bo) break;
          const bothForY = bo - needFromBoth;
          const reward = Math.min(b * rewardQty, yo + bothForY);
          if (bestB === 0 || reward > bestReward) {
            bestB = b;
            bestReward = reward;
            bestBothAllowed = bothForY;
          }
        }
        if (bestB === 0) {
          addReason(campaign, "INSUFFICIENT_BUY_ITEMS", `Chưa đủ số lượng mua (cần ${buyQty} món X)`);
          continue;
        }
        earnedAny = true;
        if (bestReward <= 0) {
          addReason(campaign, "REWARD_ITEM_NOT_IN_BILL", `Đủ điều kiện: thêm ${bestB * rewardQty} món Y vào đơn để được hưởng ưu đãi`);
          continue;
        }
        const candidates = input.lines.filter((l) => !l.isGift && rewardIds.has(l.itemId) && !campaign.excludedItemIds.includes(l.itemId));
        campaignDiscount += distributeReward({
          candidates,
          units: bestReward,
          mode: cond.benefitMode,
          value: cond.value,
          campaignId: campaign.campaignId,
          tierId: cond.conditionId,
          isBoth: (l) => buyIds.has(l.itemId),
          maxFromBoth: bestBothAllowed,
        });
      }
      if (campaignDiscount > 0) {
        totalDiscount += campaignDiscount;
        markApplied(campaign.campaignId);
      } else if (earnedAny && !reasons.some((r) => r.campaignId === campaign.campaignId)) {
        addReason(campaign, "NO_BENEFIT", "Ưu đãi món Y bằng 0đ");
      }
    } else if (isType(type, "ORDERVALUEITEMBENEFIT")) {
      let base = 0;
      for (const l of input.lines) if (inScope(campaign, l)) base += afterManual[l.lineId] ?? 0;
      const tiers = [...campaign.tiers].sort((a, b) => b.threshold - a.threshold);
      const tier = tiers.find((t) => base >= t.threshold);
      if (!tier) {
        const minTh = tiers.length === 0 ? 0 : tiers[tiers.length - 1].threshold;
        addReason(
          campaign,
          tiers.length === 0 ? "INVALID_CONFIG" : "ORDER_VALUE_NOT_REACHED",
          tiers.length === 0 ? "Chương trình chưa cấu hình mức ưu đãi" : `Đơn hàng chưa đạt ${minTh} đ`
        );
        continue;
      }
      const rewardIds = new Set(tier.rewardItemIds);
      if (rewardIds.size === 0) {
        addReason(campaign, "INVALID_CONFIG", "Chưa chọn món được tặng/giảm");
        continue;
      }
      const units = tier.maxRewardQty > 0 ? tier.maxRewardQty : 1;
      const candidates = input.lines.filter((l) => !l.isGift && rewardIds.has(l.itemId) && !campaign.excludedItemIds.includes(l.itemId));
      if (candidates.length === 0) {
        addReason(campaign, "REWARD_ITEM_NOT_IN_BILL", "Đơn đủ điều kiện: thêm món được tặng/giảm vào đơn để áp dụng");
        continue;
      }
      const d = distributeReward({ candidates, units, mode: tier.benefitMode, value: tier.value, campaignId: campaign.campaignId, tierId: tier.tierId });
      if (d > 0) {
        totalDiscount += d;
        markApplied(campaign.campaignId);
      } else {
        addReason(campaign, "NO_BENEFIT", "Ưu đãi món bằng 0đ");
      }
    } else if (isType(type, "ITEMPRICERULE")) {
      if (campaign.tiers.length > 0) {
        const tier = campaign.tiers[0];
        const fixedPrice = tier.benefitMode === "FIXEDPRICE" ? tier.value : null;
        let applied = false;
        for (const line of input.lines) {
          if (!inScope(campaign, line)) continue;
          if (fixedPrice != null && line.unitPrice > fixedPrice) {
            const remaining = Math.max(0, lineFinal[line.lineId] ?? 0);
            const discount = Math.min((line.unitPrice - fixedPrice) * line.quantity, remaining);
            if (discount <= 0) continue;
            lineDisc[line.lineId] = (lineDisc[line.lineId] ?? 0) + discount;
            lineFinal[line.lineId] = remaining - discount;
            totalDiscount += discount;
            applied = true;
          }
        }
        if (applied) markApplied(campaign.campaignId);
      }
    }
  }

  const billBenefits: BillBenefit[] = [];
  if (eligibleBillDiscounts.length > 0) {
    eligibleBillDiscounts.sort((a, b) => (a.priority !== b.priority ? b.priority - a.priority : b.createdAt - a.createdAt));

    const calculated: { campaign: Campaign; tier: CampaignTier; discount: number; lines: PricingLine[] }[] = [];
    for (const campaign of eligibleBillDiscounts) {
      if (campaign.tiers.length === 0) continue;
      const eligibleLines = input.lines.filter((l) => inScope(campaign, l));
      const baseMoney = eligibleLines.reduce((s, l) => s + Math.max(0, lineFinal[l.lineId] ?? 0), 0);
      const tiers = [...campaign.tiers].sort((a, b) => b.threshold - a.threshold);
      const tier =
        campaign.tiers[0].conditionBasis === "GUESTCOUNT"
          ? campaign.tiers[0]
          : tiers.find((t) => t.threshold <= 0 || baseMoney >= t.threshold);
      if (!tier) {
        reasons.push({
          campaignId: campaign.campaignId,
          reasonCode: "ORDER_VALUE_NOT_REACHED",
          reasonMessage: `Đơn hàng chưa đạt ${tiers[tiers.length - 1].threshold} đ`,
        });
        continue;
      }
      const mode = normalizeBenefitMode(tier.benefitMode);
      let d = 0;
      if (mode === "PERCENT") d = Math.floor((baseMoney * tier.value) / 10000);
      else if (mode === "FIXED") d = tier.value;
      if (tier.maxDiscountMoney > 0 && d > tier.maxDiscountMoney) d = tier.maxDiscountMoney;
      d = Math.max(0, Math.min(d, baseMoney));
      calculated.push({ campaign, tier, discount: d, lines: eligibleLines });
    }

    if (calculated.length > 0) {
      const best = calculated.reduce((a, b) => (a.discount >= b.discount ? a : b));
      const { campaign, tier, lines: eligibleLines } = best;
      const discountToApply = best.discount;
      if (discountToApply > 0) {
        totalDiscount += discountToApply;
        markApplied(campaign.campaignId);

        const eligibleMoney = eligibleLines.reduce((s, l) => s + Math.max(0, lineFinal[l.lineId] ?? 0), 0);
        let allocatedSum = 0;
        const remainders: { lineId: string; remainder: number }[] = [];
        const allocations: Record<string, number> = {};
        for (const line of eligibleLines) {
          const lineMoney = Math.max(0, lineFinal[line.lineId] ?? 0);
          const weight = eligibleMoney > 0 ? lineMoney / eligibleMoney : 0;
          const allocated = Math.floor(discountToApply * weight);
          allocations[line.lineId] = allocated;
          allocatedSum += allocated;
          remainders.push({ lineId: line.lineId, remainder: discountToApply * weight - allocated });
        }
        const diff = discountToApply - allocatedSum;
        remainders.sort((a, b) => {
          const r = b.remainder - a.remainder;
          if (r !== 0) return r;
          return a.lineId < b.lineId ? 1 : a.lineId > b.lineId ? -1 : 0;
        });
        for (let i = 0; i < diff && remainders.length > 0; i++) {
          const id = remainders[i % remainders.length].lineId;
          allocations[id] = (allocations[id] ?? 0) + 1;
        }
        for (const line of eligibleLines) {
          const alloc = allocations[line.lineId] ?? 0;
          lineDisc[line.lineId] = (lineDisc[line.lineId] ?? 0) + alloc;
          lineFinal[line.lineId] = (lineFinal[line.lineId] ?? 0) - alloc;
        }
        billBenefits.push({ campaignId: campaign.campaignId, tierId: tier.tierId, discountMoney: discountToApply, lineAllocations: allocations });
      }
    }
  }

  const manualDiscount = (input.manualDiscountMoney ?? 0) + manualLineTotal;
  const finalDiscount = totalDiscount + manualDiscount;
  const netMoney = Math.max(0, grossMoney - finalDiscount);

  const lineBenefits: LineBenefit[] = [];
  for (const line of input.lines) {
    if (line.isGift) continue;
    lineBenefits.push({
      lineId: line.lineId,
      campaignId: "",
      tierId: "",
      discountMoney: lineDisc[line.lineId] ?? 0,
      originalPrice: line.unitPrice * line.quantity,
      effectivePrice: lineFinal[line.lineId] ?? 0,
      isGift: false,
    });
  }

  return {
    grossMoney,
    totalPromotionDiscount: totalDiscount,
    manualDiscount,
    totalDiscountMoney: finalDiscount,
    netMoney,
    lineBenefits,
    rewardBenefits,
    billBenefits,
    appliedCampaignIds: appliedCampaigns,
    reasons,
  };
}

// ==================== CẦU NỐI GIỎ HÀNG ↔ ENGINE ====================
/** Dòng món của bàn → dòng tính giá (lineId = vị trí dòng, groupId = nhóm món tra từ danh mục) */
export function linesFromOrder(
  items: RawOrderLine[],
  groupOf?: (item: RawOrderLine) => string | null | undefined
): PricingLine[] {
  return items.map((it, i) => ({
    lineId: `L${i}`,
    itemId: String(it.productId ?? it.id ?? ""),
    groupId: groupOf?.(it) ?? (typeof it.category === "string" && it.category ? it.category : null),
    quantity: lineQuantity(it),
    unitPrice: lineUnitPrice(it),
    manualDiscount: lineDiscountTotal(it),
  }));
}

/** Tính riêng 1 chương trình trên giỏ hàng */
export function quoteCampaign(
  campaign: Campaign,
  lines: PricingLine[],
  ctx: { branchId: string; guestCount?: number | null; nowMs: number }
): PriceQuote {
  return calculatePrice({ branchId: ctx.branchId, guestCount: ctx.guestCount, nowMs: ctx.nowMs, lines }, [campaign]);
}

export function quoteReason(quote: PriceQuote, campaign: Campaign): string | undefined {
  return quote.reasons.find((r) => r.campaignId === campaign.campaignId)?.reasonMessage;
}

// ==================== GIẢM GIÁ ĐÃ ÁP DỤNG (bill.discounts) ====================
export interface AppliedDiscount {
  promoId: string;
  promoCode?: string;
  description: string;
  amount: number;
  staffNote?: string;
  campaignId: string;
  campaignName: string;
  programCode: string;
  campaignType: string;
  voucherCode?: string;
}

/** Bản ghi bill.discounts — khớp CartCampaignPricing.discount (Flutter) */
export function buildAppliedDiscount(campaign: Campaign, amount: number, opts?: { voucherCode?: string | null; staffNote?: string | null }): AppliedDiscount {
  const code = opts?.voucherCode && opts.voucherCode.trim() ? opts.voucherCode.trim().toUpperCase() : undefined;
  const note = opts?.staffNote && opts.staffNote.trim() ? opts.staffNote.trim() : undefined;
  return {
    promoId: campaign.campaignId,
    ...(code ? { promoCode: code } : {}),
    description: code ? `${campaign.name} (mã ${code})` : campaign.name,
    amount,
    ...(note ? { staffNote: note } : {}),
    campaignId: campaign.campaignId,
    campaignName: campaign.name,
    programCode: campaign.programCode,
    campaignType: campaign.campaignType,
    ...(code ? { voucherCode: code } : {}),
  };
}

/**
 * Tính lại các giảm giá khi giỏ hàng đổi. Trả về danh sách mới + tên chương trình bị gỡ
 * (không còn đủ điều kiện). Giảm giá không còn trong [campaignsById] được giữ nguyên (khớp Flutter).
 */
export function recalculateDiscounts(
  applied: AppliedDiscount[],
  campaignsById: Record<string, Campaign>,
  lines: PricingLine[],
  ctx: { branchId: string; guestCount?: number | null; nowMs: number }
): { discounts: AppliedDiscount[]; dropped: string[] } {
  const out: AppliedDiscount[] = [];
  const dropped: string[] = [];
  for (const d of applied) {
    const c = campaignsById[d.campaignId];
    if (!c) {
      out.push(d);
      continue;
    }
    const amt = quoteCampaign(c, lines, ctx).totalPromotionDiscount;
    if (amt > 0) out.push({ ...d, amount: amt });
    else dropped.push(d.description);
  }
  return { discounts: out, dropped };
}

/**
 * Cộng dồn: quyết định danh sách sau khi thêm [incoming].
 *  - Cửa hàng tắt "cho phép cộng dồn" (allowStackPromotions=false) → chỉ giữ chương trình mới (như Flutter).
 *  - Chương trình mới hoặc đã áp dụng có stackingMode DISABLED → không đi cùng chương trình khác.
 * Trả về danh sách mới và tên các chương trình bị gỡ.
 */
export function addWithStacking(
  applied: AppliedDiscount[],
  incoming: { discount: AppliedDiscount; campaign: Campaign },
  campaignsById: Record<string, Campaign>,
  allowStackPromotions = true
): { discounts: AppliedDiscount[]; removed: string[] } {
  const without = applied.filter((d) => d.campaignId !== incoming.campaign.campaignId);
  const stackable = (c: Campaign | undefined) => c == null || c.stackingMode === "ENABLED";
  let keep = without;
  if (!allowStackPromotions || !stackable(incoming.campaign)) {
    keep = [];
  } else {
    keep = without.filter((d) => stackable(campaignsById[d.campaignId]));
  }
  const removed = without.filter((d) => !keep.includes(d)).map((d) => d.description);
  return { discounts: [...keep, incoming.discount], removed };
}

// ==================== MÔ TẢ ƯU ĐÃI ====================
const vnd = (n: number) => `${new Intl.NumberFormat("vi-VN").format(n)} đ`;

function benefitText(mode: string, value: number): string {
  switch (normalizeBenefitMode(mode)) {
    case "FREE":
      return "tặng";
    case "PERCENT": {
      const pct = value / 100;
      return `giảm ${pct}%`;
    }
    case "FIXED":
      return `giảm ${vnd(value)}`;
    case "FIXEDPRICE":
      return `đồng giá ${vnd(value)}`;
    default:
      return "";
  }
}

export const CAMPAIGN_TYPE_DISPLAY: Record<string, string> = {
  BILLDISCOUNT: "Giảm giá đơn hàng",
  ORDERVALUEITEMBENEFIT: "Giảm/tặng món theo giá trị hóa đơn",
  BUYXGETY: "Mua X tặng/giảm giá Y",
  ITEMPRICERULE: "Đồng giá/đồng giảm giá",
};

export function campaignTypeDisplay(c: Campaign): string {
  return CAMPAIGN_TYPE_DISPLAY[c.campaignType.toUpperCase().replace(/_/g, "")] ?? CAMPAIGN_TYPE_DISPLAY.BILLDISCOUNT;
}

/** Mô tả ngắn lợi ích (hiển thị khi chọn / nhập mã) — khớp describeCampaignBenefit (Flutter) */
export function describeBenefit(c: Campaign): string {
  const type = c.campaignType.toUpperCase().replace(/_/g, "");
  if (type === "BUYXGETY") {
    if (c.buyConditions.length === 0) return campaignTypeDisplay(c);
    const b = c.buyConditions[0];
    return `Mua ${b.requiredBuyQty} món X ${benefitText(b.benefitMode, b.value)} ${b.rewardQty} món Y${b.multiplyByBundle ? " (nhân theo số món X)" : ""}`;
  }
  if (c.tiers.length === 0) return campaignTypeDisplay(c);
  const t = c.tiers[0];
  const from = t.threshold > 0 ? ` cho đơn từ ${vnd(t.threshold)}` : "";
  if (type === "ORDERVALUEITEMBENEFIT") {
    const qty = t.maxRewardQty > 0 ? t.maxRewardQty : 1;
    return `${benefitText(t.benefitMode, t.value)} ${qty} món${from}`;
  }
  if (type === "ITEMPRICERULE") return `đồng giá ${vnd(t.value)}`;
  const cap = t.maxDiscountMoney > 0 ? `, tối đa ${vnd(t.maxDiscountMoney)}` : "";
  return `${benefitText(t.benefitMode, t.value)} hóa đơn${cap}${from}`;
}

// ==================== VOUCHER ====================
export interface VoucherRecord {
  voucherId: string;
  campaignId: string;
  normalizedCode: string;
  state: string;
  holdExpiresAt?: number;
  redeemedBillId?: string;
  redeemedBillCode?: string;
  redeemedAt?: number;
  redeemedBy?: string;
  redeemedByName?: string;
  tableName?: string;
  cancelledAt?: number;
}

const optStr = (v: unknown) => (v === undefined || v === null || v === "" ? undefined : String(v));

/** Voucher RTDB thô → VoucherRecord (state suy từ status cũ nếu thiếu — khớp VoucherModel.fromMap) */
export function parseVoucher(id: string, raw: Record<string, unknown> | null | undefined): VoucherRecord | null {
  if (!raw) return null;
  let state = String(raw.state ?? "").toUpperCase();
  if (!["DRAFT", "RELEASED", "RESERVED", "REDEEMED", "CANCELLED"].includes(state)) {
    const st = String(raw.status ?? "").toUpperCase();
    state = st === "USED" ? "REDEEMED" : st === "CANCELLED" ? "CANCELLED" : "RELEASED";
  }
  return {
    voucherId: optStr(raw.voucherId) ?? id,
    campaignId: optStr(raw.campaignId) ?? "",
    normalizedCode: String(raw.normalizedCode ?? raw.code ?? "").toUpperCase(),
    state,
    holdExpiresAt: optInt(raw.holdExpiresAt),
    redeemedBillId: optStr(raw.redeemedBillId),
    redeemedBillCode: optStr(raw.redeemedBillCode),
    redeemedAt: optInt(raw.redeemedAt) ?? optInt(raw.usedAt),
    redeemedBy: optStr(raw.redeemedBy) ?? optStr(raw.usedBy),
    redeemedByName: optStr(raw.redeemedByName),
    tableName: optStr(raw.tableName),
    cancelledAt: optInt(raw.cancelledAt),
  };
}

export type VoucherCheckStatus =
  | "valid" | "notFound" | "redeemed" | "cancelled" | "notReleased" | "held"
  | "campaignInactive" | "notStarted" | "ended" | "outsideSchedule" | "wrongBranch" | "notApplicable";

export interface VoucherCheckResult {
  status: VoucherCheckStatus;
  message: string;
  voucher?: VoucherRecord | null;
  campaign?: Campaign | null;
  discount: number;
  isValid: boolean;
}

export const normalizeVoucherCodeInput = (code: string) => String(code ?? "").trim().toUpperCase();

const pad = (n: number) => String(n).padStart(2, "0");
/** dd/MM/yyyy HH:mm — khớp FormatUtils.dateTime */
export function formatDateTimeVi(ms: number): string {
  const d = new Date(ms);
  return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function result(status: VoucherCheckStatus, message: string, extra?: { voucher?: VoucherRecord | null; campaign?: Campaign | null; discount?: number }): VoucherCheckResult {
  return { status, message, voucher: extra?.voucher, campaign: extra?.campaign, discount: extra?.discount ?? 0, isValid: status === "valid" };
}

/**
 * Ánh xạ kết quả tra mã → thông báo cho thu ngân (khớp evaluateVoucher của Flutter).
 * [quote] là kết quả engine của riêng chương trình của mã trên hóa đơn hiện tại.
 * [currentBillId]: mã đã đổi bởi chính hóa đơn này vẫn hợp lệ.
 */
export function evaluateVoucher(a: {
  code: string;
  voucher: VoucherRecord | null;
  campaign: Campaign | null;
  nowMs: number;
  branchId: string;
  quote?: PriceQuote | null;
  currentBillId?: string | null;
}): VoucherCheckResult {
  const c = normalizeVoucherCodeInput(a.code);
  const { voucher, campaign, nowMs } = a;
  if (!voucher) return result("notFound", `Mã ${c} không tồn tại`);
  const ex = { voucher, campaign };
  const state = voucher.state.toUpperCase();
  if (state === "REDEEMED" && !(a.currentBillId && voucher.redeemedBillId === a.currentBillId)) {
    const bill = voucher.redeemedBillCode ?? voucher.redeemedBillId ?? "?";
    const at = voucher.redeemedAt != null ? formatDateTimeVi(voucher.redeemedAt) : "?";
    const by = voucher.redeemedByName ?? voucher.redeemedBy ?? "?";
    const table = voucher.tableName ? ` (${voucher.tableName})` : "";
    return result("redeemed", `Mã đã được sử dụng ở đơn ${bill}${table} lúc ${at} bởi ${by}`, ex);
  }
  if (state === "CANCELLED") return result("cancelled", "Mã đã hủy", ex);
  if (state === "DRAFT") return result("notReleased", "Mã chưa được phát hành", ex);
  if (state === "RESERVED" && voucher.holdExpiresAt != null && voucher.holdExpiresAt > nowMs) {
    return result("held", "Mã đang được giữ bởi giao dịch khác", ex);
  }
  if (!campaign || !campaign.active) return result("campaignInactive", "Chương trình của mã đã ngừng hoạt động", ex);
  const s = campaign.schedule;
  if (s.absoluteStart != null && nowMs < s.absoluteStart) {
    return result("notStarted", `Chương trình "${campaign.name}" chưa bắt đầu (từ ${formatDateTimeVi(s.absoluteStart)})`, ex);
  }
  if (s.absoluteEnd != null && nowMs > s.absoluteEnd) {
    return result("ended", `Chương trình "${campaign.name}" đã kết thúc (${formatDateTimeVi(s.absoluteEnd)})`, ex);
  }
  if (!isEligibleAt(campaign, nowMs)) {
    return result("outsideSchedule", `Chương trình "${campaign.name}" không áp dụng vào ngày/khung giờ này`, ex);
  }
  if (!isEligibleForBranch(campaign, a.branchId)) {
    return result("wrongBranch", `Chương trình "${campaign.name}" không áp dụng tại chi nhánh này`, ex);
  }
  if (a.quote) {
    const discount = a.quote.totalPromotionDiscount;
    if (discount <= 0 || !a.quote.appliedCampaignIds.includes(campaign.campaignId)) {
      const reason = quoteReason(a.quote, campaign);
      return result("notApplicable", `Mã hợp lệ nhưng chưa áp dụng được cho đơn này: ${reason ?? "đơn chưa đạt điều kiện"}`, ex);
    }
    return result("valid", `Mã hợp lệ - ${campaign.name}: ${describeBenefit(campaign)}`, { ...ex, discount });
  }
  return result("valid", `Mã hợp lệ - ${campaign.name}: ${describeBenefit(campaign)}`, ex);
}

// ==================== BỘ ĐẾM LƯỢT DÙNG (PromotionUsageMath) ====================
const asNum = (v: unknown) => {
  const n = Number(v);
  return Number.isFinite(n) ? Math.trunc(n) : 0;
};

/**
 * Giá trị mới cho campaign_counters/{id}; null nếu vượt giới hạn (chỉ kiểm khi delta dương;
 * giới hạn rỗng hoặc <= 0 = không giới hạn).
 */
export function applyCampaignUsage(
  current: unknown,
  a: { campaignId: string; spentDelta: number; useDelta: number; maxUses?: number | null; budgetMoney?: number | null }
): Record<string, unknown> | null {
  const data = current && typeof current === "object" ? (current as Record<string, unknown>) : {};
  const spent = asNum(data.spentMoney) + a.spentDelta;
  const uses = asNum(data.committedUseCount) + a.useDelta;
  if (a.useDelta > 0 && a.maxUses != null && a.maxUses > 0 && uses > a.maxUses) return null;
  if (a.spentDelta > 0 && a.budgetMoney != null && a.budgetMoney > 0 && spent > a.budgetMoney) return null;
  return {
    ...data,
    campaignId: a.campaignId,
    spentMoney: Math.max(0, spent),
    reservedMoney: asNum(data.reservedMoney),
    committedUseCount: Math.max(0, uses),
    reservedUseCount: asNum(data.reservedUseCount),
    version: asNum(data.version) + 1,
  };
}

/** customer_campaign_counters/{campaignId_customerId}; null nếu vượt giới hạn/khách */
export function applyCustomerUsage(
  current: unknown,
  a: { campaignId: string; customerId: string; delta: number; maxUsesPerCustomer?: number | null }
): Record<string, unknown> | null {
  const data = current && typeof current === "object" ? (current as Record<string, unknown>) : {};
  const used = asNum(data.usedCount) + a.delta;
  if (a.delta > 0 && a.maxUsesPerCustomer != null && a.maxUsesPerCustomer > 0 && used > a.maxUsesPerCustomer) return null;
  return {
    ...data,
    campaignId: a.campaignId,
    customerId: a.customerId,
    usedCount: Math.max(0, used),
    heldCount: asNum(data.heldCount),
  };
}

/**
 * Giá trị voucher sau khi ĐỔI (transaction handler thuần) — khớp _redeemVoucherHandler (Flutter).
 * Trả { next } khi đổi được, { reject } với lý do ('MINE' = chính hóa đơn này đã đổi trước đó), hoặc null nếu chưa có dữ liệu.
 */
export function redeemVoucherValue(
  current: unknown,
  a: { billId: string; username: string; billCode?: string; tableName?: string; staffName?: string; staffNote?: string; now: number }
): { next: Record<string, unknown> } | { reject: string } | null {
  if (current === null || current === undefined) return null;
  const m = { ...(current as Record<string, unknown>) };
  const state = String(m.state ?? "");
  if (state === "REDEEMED") return { reject: m.redeemedBillId === a.billId ? "MINE" : "Mã voucher đã được sử dụng" };
  if (state === "CANCELLED") return { reject: "Mã voucher đã bị hủy" };
  if (state === "DRAFT") return { reject: "Mã voucher chưa được phát hành" };
  if (state === "RESERVED") {
    const exp = optInt(m.holdExpiresAt);
    if (exp != null && a.now < exp) return { reject: "Mã voucher đang được giữ bởi giao dịch khác" };
  }
  m.state = "REDEEMED";
  m.redeemedAt = a.now;
  m.redeemedBillId = a.billId;
  m.redeemedBillCode = a.billCode ? a.billCode : a.billId;
  m.redeemedBy = a.username;
  m.usedBy = a.username;
  m.usedAt = a.now;
  m.status = "USED";
  if (a.staffName) m.redeemedByName = a.staffName;
  if (a.tableName) m.tableName = a.tableName;
  m.holdId = null;
  m.holdExpiresAt = null;
  m.version = asNum(m.version) + 1;
  if (a.staffNote) m.staffNote = a.staffNote;
  return { next: m };
}

/** Voucher sau khi hoàn tác đổi mã (REDEEMED → RELEASED); null nếu không phải hóa đơn đã đổi */
export function rollbackVoucherValue(current: unknown, billId: string): Record<string, unknown> | null {
  if (current === null || current === undefined) return null;
  const m = { ...(current as Record<string, unknown>) };
  if (m.redeemedBillId !== billId) return null;
  m.state = "RELEASED";
  m.redeemedAt = null;
  m.redeemedBillId = null;
  m.redeemedBillCode = null;
  m.redeemedBy = null;
  m.redeemedByName = null;
  m.tableName = null;
  m.usedBy = null;
  m.usedAt = null;
  m.status = "ISSUED";
  m.version = asNum(m.version) + 1;
  return m;
}
