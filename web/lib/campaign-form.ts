// Ánh xạ form chương trình KM (Web Admin) <-> dữ liệu campaign trên RTDB.
// Nguồn chuẩn tên trường: app_flutter/lib/data/models/campaign_models.dart
// (CampaignTier.toMap / CampaignBuyCondition.toMap). Hai bên admin phải ghi cùng một dạng.
//
// Đơn vị: % lưu dạng basis points (10000 = 100%) — PricingEngine Flutter tính `money * value ~/ 10000`.
// Số tiền lưu VND nguyên.

export type CampaignTypeCode = "BILLDISCOUNT" | "ORDERVALUEITEMBENEFIT" | "BUYXGETY" | "ITEMPRICERULE";
export type BenefitModeCode = "PERCENT" | "FIXED" | "FREEITEM" | "FIXEDPRICE";
export type RewardBenefit = "FREEITEM" | "PERCENT" | "FIXED";

export const CAMPAIGN_TYPE_LABELS: Record<CampaignTypeCode, string> = {
  BILLDISCOUNT: "Giảm giá đơn hàng",
  ORDERVALUEITEMBENEFIT: "Giảm/tặng món theo giá trị hóa đơn",
  BUYXGETY: "Mua X tặng/giảm giá Y",
  ITEMPRICERULE: "Đồng giá/đồng giảm giá",
};

export const REWARD_BENEFIT_LABELS: Record<RewardBenefit, string> = {
  FREEITEM: "Tặng (miễn phí 100%)",
  PERCENT: "Giảm giá theo %",
  FIXED: "Giảm số tiền (VND)",
};

/** Chuẩn hóa mã loại KM (chấp nhận cả dạng có gạch dưới, vd BILL_DISCOUNT). */
export function normalizeCampaignType(raw: unknown): CampaignTypeCode {
  const t = String(raw ?? "").toUpperCase().replace(/_/g, "");
  return (t in CAMPAIGN_TYPE_LABELS ? t : "BILLDISCOUNT") as CampaignTypeCode;
}

export function percentToBasisPoints(percent: number): number {
  return Math.round(percent * 100);
}

export function basisPointsToPercent(bp: number): number {
  return Math.round(bp) / 100;
}

// ==================== RAW MODEL ====================
export interface RawTier {
  tierId?: string;
  conditionBasis?: string;
  threshold?: number;
  thresholdValue?: number;
  benefitMode?: string;
  benefitType?: string;
  value?: number;
  benefitValue?: number;
  maxDiscountMoney?: number;
  maxBenefitValue?: number;
  maxRewardQty?: number;
  rewardItemIds?: string[];
  sortOrder?: number;
  [key: string]: unknown;
}

export interface RawBuyCondition {
  conditionId?: string;
  buyItemIds?: string[];
  requiredBuyQty?: number;
  rewardItemIds?: string[];
  rewardQty?: number;
  benefitMode?: string;
  value?: number;
  multiplyByBundle?: boolean;
  [key: string]: unknown;
}

/** Suy ra benefitMode của tier (dữ liệu cũ có thể chỉ có benefitType) — khớp CampaignTier.fromMap. */
export function tierBenefitMode(tier: RawTier | undefined): BenefitModeCode {
  if (!tier) return "PERCENT";
  const mode = String(tier.benefitMode ?? "").toUpperCase();
  if (mode === "PERCENT" || mode === "FIXED" || mode === "FREEITEM" || mode === "FIXEDPRICE") return mode;
  const bType = String(tier.benefitType ?? "").toUpperCase();
  if (bType === "DISCOUNT_AMOUNT" || bType === "AMOUNT") return "FIXED";
  if (bType === "FIXED_PRICE") return "FIXEDPRICE";
  return "PERCENT";
}

const num = (v: unknown): number => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};
const strList = (v: unknown): string[] => (Array.isArray(v) ? v.map(String) : []);

/** Giá trị tier (ưu tiên `value`, fallback `benefitValue`) — khớp CampaignTier.fromMap. */
export function tierValue(tier: RawTier | undefined): number {
  return num(tier?.value ?? tier?.benefitValue ?? 0);
}

// ==================== FORM ====================
export interface CampaignFormState {
  name: string;
  programCode: string;
  description: string;
  campaignType: CampaignTypeCode;
  active: boolean;
  startDate: string;
  endDate: string;
  budgetMoney: string;
  maxUses: string;
  hasCodes: boolean;
  autoApply: boolean;
  requireStaffNote: boolean;
  stackingMode: string;
  priority: string;
  // BILLDISCOUNT
  discountType: "PERCENT" | "AMOUNT";
  discountValue: string;
  /** Giảm tối đa (tier.maxDiscountMoney), "" = không giới hạn */
  maxDiscount: string;
  /** Đơn hàng từ (tier.threshold) — dùng cho BILLDISCOUNT & ORDERVALUEITEMBENEFIT */
  threshold: string;
  // ITEMPRICERULE
  fixedPriceValue: string;
  // ORDERVALUEITEMBENEFIT & BUYXGETY: món thưởng Y
  rewardItemIds: string[];
  rewardQty: string;
  rewardBenefit: RewardBenefit;
  /** % (khi PERCENT) hoặc VND (khi FIXED); bỏ qua khi FREEITEM */
  rewardValue: string;
  // BUYXGETY: món mua X
  buyItemIds: string[];
  buyQty: string;
  multiplyByBundle: boolean;
  // Phạm vi
  includedItemIds: string[];
  includedGroupIds: string[];
  daysOfWeek: number[];
  timeSlots: { startTime: string; endTime: string }[];
}

export function emptyCampaignForm(): CampaignFormState {
  return {
    name: "", programCode: "", description: "", campaignType: "BILLDISCOUNT",
    active: true, startDate: "", endDate: "", budgetMoney: "", maxUses: "",
    hasCodes: false, autoApply: true, requireStaffNote: false, stackingMode: "ENABLED", priority: "0",
    discountType: "PERCENT", discountValue: "", maxDiscount: "", threshold: "",
    fixedPriceValue: "",
    rewardItemIds: [], rewardQty: "1", rewardBenefit: "FREEITEM", rewardValue: "",
    buyItemIds: [], buyQty: "1", multiplyByBundle: true,
    includedItemIds: [], includedGroupIds: [], daysOfWeek: [], timeSlots: [],
  };
}

/** Phần campaign đã lưu cần để dựng form. */
export interface StoredCampaign {
  name?: string;
  programCode?: string;
  description?: string;
  campaignType?: string;
  active?: boolean;
  schedule?: { absoluteStart?: number; absoluteEnd?: number; daysOfWeek?: number[]; timeSlots?: { startTime: string; endTime: string }[] };
  budgetMoney?: number;
  maxUses?: number;
  hasCodes?: boolean;
  autoApply?: boolean;
  requireStaffNote?: boolean;
  stackingMode?: string;
  priority?: number;
  tiers?: RawTier[];
  buyConditions?: RawBuyCondition[];
  includedItemIds?: string[];
  includedGroupIds?: string[];
}

const posStr = (n: number) => (n > 0 ? String(n) : "");

/** datetime-local theo giờ máy (không dùng toISOString vì lệch UTC). */
export function toLocalDateTimeInput(ts: number | undefined): string {
  if (!ts) return "";
  const d = new Date(ts);
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
}

function rewardFromMode(mode: string | undefined, value: number): { rewardBenefit: RewardBenefit; rewardValue: string } {
  const m = String(mode ?? "").toUpperCase();
  if (m === "PERCENT") {
    // 100% giảm = tặng
    if (value >= 10000) return { rewardBenefit: "FREEITEM", rewardValue: "" };
    return { rewardBenefit: "PERCENT", rewardValue: posStr(basisPointsToPercent(value)) };
  }
  if (m === "FIXED") return { rewardBenefit: "FIXED", rewardValue: posStr(value) };
  return { rewardBenefit: "FREEITEM", rewardValue: "" };
}

export function campaignToForm(cam: StoredCampaign): CampaignFormState {
  const base = emptyCampaignForm();
  const type = normalizeCampaignType(cam.campaignType);
  const tier = cam.tiers?.[0];
  const cond = cam.buyConditions?.[0];
  const form: CampaignFormState = {
    ...base,
    name: cam.name ?? "",
    programCode: cam.programCode ?? "",
    description: cam.description ?? "",
    campaignType: type,
    active: cam.active ?? false,
    startDate: toLocalDateTimeInput(cam.schedule?.absoluteStart),
    endDate: toLocalDateTimeInput(cam.schedule?.absoluteEnd),
    budgetMoney: posStr(num(cam.budgetMoney)),
    maxUses: posStr(num(cam.maxUses)),
    hasCodes: cam.hasCodes ?? false,
    autoApply: cam.autoApply ?? true,
    requireStaffNote: cam.requireStaffNote ?? false,
    stackingMode: normalizeStackingMode(cam.stackingMode),
    priority: String(cam.priority || 0),
    includedItemIds: strList(cam.includedItemIds),
    includedGroupIds: strList(cam.includedGroupIds),
    daysOfWeek: Array.isArray(cam.schedule?.daysOfWeek) ? [...cam.schedule.daysOfWeek] : [],
    timeSlots: Array.isArray(cam.schedule?.timeSlots) ? cam.schedule.timeSlots.map((s) => ({ ...s })) : [],
  };

  if (tier) {
    const mode = tierBenefitMode(tier);
    const value = tierValue(tier);
    form.threshold = posStr(num(tier.threshold ?? tier.thresholdValue));
    form.maxDiscount = posStr(num(tier.maxDiscountMoney ?? tier.maxBenefitValue));
    if (type === "BILLDISCOUNT") {
      form.discountType = mode === "PERCENT" ? "PERCENT" : "AMOUNT";
      form.discountValue = posStr(mode === "PERCENT" ? basisPointsToPercent(value) : value);
    } else if (type === "ITEMPRICERULE") {
      form.fixedPriceValue = posStr(value);
    } else if (type === "ORDERVALUEITEMBENEFIT") {
      form.rewardItemIds = strList(tier.rewardItemIds);
      form.rewardQty = posStr(num(tier.maxRewardQty)) || "1";
      Object.assign(form, rewardFromMode(mode, value));
    }
  }

  if (type === "BUYXGETY" && cond) {
    form.buyItemIds = strList(cond.buyItemIds);
    form.buyQty = posStr(num(cond.requiredBuyQty)) || "1";
    form.rewardItemIds = strList(cond.rewardItemIds);
    form.rewardQty = posStr(num(cond.rewardQty)) || "1";
    form.multiplyByBundle = cond.multiplyByBundle ?? true;
    Object.assign(form, rewardFromMode(cond.benefitMode, num(cond.value)));
  }
  return form;
}

const toInt = (s: string) => {
  const n = Number(String(s).trim());
  return Number.isFinite(n) ? n : NaN;
};

/** Kiểm tra form, trả về thông báo lỗi tiếng Việt hoặc null nếu hợp lệ. */
export function validateCampaignForm(form: CampaignFormState): string | null {
  if (!form.name.trim()) return "Tên chương trình là bắt buộc";
  const nonNeg = (s: string) => s.trim() === "" || (toInt(s) >= 0);
  if (!nonNeg(form.threshold)) return "Giá trị \"Đơn hàng từ\" không hợp lệ";
  if (!nonNeg(form.maxDiscount)) return "Giá trị \"Giảm tối đa\" không hợp lệ";

  const checkReward = (): string | null => {
    if (form.rewardItemIds.length === 0) return "Vui lòng chọn ít nhất 1 món Y được tặng/giảm giá";
    const q = toInt(form.rewardQty);
    if (!Number.isInteger(q) || q <= 0) return "Số lượng món Y phải là số nguyên lớn hơn 0";
    if (form.rewardBenefit === "PERCENT") {
      const v = toInt(form.rewardValue);
      if (!(v > 0 && v <= 100)) return "Tỷ lệ giảm món Y (%) phải lớn hơn 0 và không quá 100";
    } else if (form.rewardBenefit === "FIXED") {
      const v = toInt(form.rewardValue);
      if (!(v > 0)) return "Số tiền giảm món Y phải lớn hơn 0";
    }
    return null;
  };

  switch (form.campaignType) {
    case "BILLDISCOUNT": {
      const v = toInt(form.discountValue);
      if (form.discountType === "PERCENT") {
        if (!(v > 0 && v <= 100)) return "Tỷ lệ giảm giá (%) phải lớn hơn 0 và không quá 100";
      } else if (!(v > 0)) return "Số tiền giảm (VND) phải lớn hơn 0";
      return null;
    }
    case "ITEMPRICERULE": {
      if (!(toInt(form.fixedPriceValue) > 0)) return "Giá đồng giá (VND) phải lớn hơn 0";
      return null;
    }
    case "ORDERVALUEITEMBENEFIT": {
      if (!(toInt(form.threshold) > 0)) return "Vui lòng nhập \"Áp dụng khi đơn hàng từ\" lớn hơn 0";
      return checkReward();
    }
    case "BUYXGETY": {
      if (form.buyItemIds.length === 0) return "Vui lòng chọn ít nhất 1 món X (món mua)";
      const q = toInt(form.buyQty);
      if (!Number.isInteger(q) || q <= 0) return "Số lượng món X phải là số nguyên lớn hơn 0";
      return checkReward();
    }
  }
  return null;
}

function rewardModeValue(form: CampaignFormState): { benefitMode: BenefitModeCode; value: number } {
  if (form.rewardBenefit === "PERCENT") return { benefitMode: "PERCENT", value: percentToBasisPoints(toInt(form.rewardValue) || 0) };
  if (form.rewardBenefit === "FIXED") return { benefitMode: "FIXED", value: Math.round(toInt(form.rewardValue) || 0) };
  // Tặng = giảm 100% (10000 bp)
  return { benefitMode: "FREEITEM", value: 10000 };
}

/** Tier theo đúng CampaignTier.toMap() của Flutter. */
export function buildTier(p: {
  tierId: string;
  threshold: number;
  benefitMode: BenefitModeCode;
  value: number;
  maxDiscountMoney?: number;
  maxRewardQty?: number;
  rewardItemIds?: string[];
}): RawTier {
  const sortOrder = 1;
  const maxDiscountMoney = p.maxDiscountMoney ?? 0;
  return {
    tierId: p.tierId,
    conditionBasis: "TOTALAMOUNT",
    threshold: p.threshold,
    thresholdValue: p.threshold,
    thresholdType: "ORDER_VALUE",
    benefitMode: p.benefitMode,
    benefitType: p.benefitMode === "PERCENT" ? "DISCOUNT_PERCENT" : "DISCOUNT_AMOUNT",
    value: p.value,
    benefitValue: p.value,
    maxDiscountMoney,
    maxBenefitValue: maxDiscountMoney,
    maxRewardQty: p.maxRewardQty ?? 0,
    rewardItemIds: p.rewardItemIds ?? [],
    sortOrder,
    tierIndex: sortOrder,
  };
}

/**
 * Dựng phần ưu đãi của campaign (tiers, buyConditions, phạm vi món) từ form.
 * Các loại không thuộc form hiện tại giữ nguyên dữ liệu cũ (`previous`).
 */
export function buildBenefitFields(
  form: CampaignFormState,
  previous?: { tiers?: RawTier[]; buyConditions?: RawBuyCondition[] },
): { tiers: RawTier[]; buyConditions: RawBuyCondition[]; includedItemIds: string[]; includedGroupIds: string[] } {
  const prevTiers = previous?.tiers ?? [];
  const prevConds = previous?.buyConditions ?? [];
  const tierId = prevTiers[0]?.tierId || "TIER_1";
  const threshold = Math.max(0, Math.round(toInt(form.threshold) || 0));
  const maxDiscountMoney = Math.max(0, Math.round(toInt(form.maxDiscount) || 0));

  switch (form.campaignType) {
    case "BILLDISCOUNT": {
      const isPercent = form.discountType === "PERCENT";
      const v = toInt(form.discountValue) || 0;
      return {
        tiers: [buildTier({
          tierId, threshold,
          benefitMode: isPercent ? "PERCENT" : "FIXED",
          value: isPercent ? percentToBasisPoints(v) : Math.round(v),
          maxDiscountMoney,
        })],
        buyConditions: [],
        // Giảm giá đơn hàng áp dụng cho toàn bộ hóa đơn
        includedItemIds: [],
        includedGroupIds: [],
      };
    }
    case "ITEMPRICERULE": {
      const v = Math.round(toInt(form.fixedPriceValue) || 0);
      return {
        tiers: [buildTier({ tierId, threshold: 0, benefitMode: "FIXEDPRICE", value: v })],
        buyConditions: [],
        includedItemIds: form.includedItemIds,
        includedGroupIds: form.includedGroupIds,
      };
    }
    case "ORDERVALUEITEMBENEFIT": {
      const { benefitMode, value } = rewardModeValue(form);
      return {
        tiers: [buildTier({
          tierId, threshold, benefitMode, value,
          maxRewardQty: Math.round(toInt(form.rewardQty) || 1),
          rewardItemIds: [...form.rewardItemIds],
        })],
        buyConditions: [],
        includedItemIds: form.includedItemIds,
        includedGroupIds: form.includedGroupIds,
      };
    }
    case "BUYXGETY": {
      const { benefitMode, value } = rewardModeValue(form);
      return {
        tiers: [],
        buyConditions: [{
          conditionId: prevConds[0]?.conditionId || "COND_1",
          buyItemIds: [...form.buyItemIds],
          requiredBuyQty: Math.round(toInt(form.buyQty) || 1),
          rewardItemIds: [...form.rewardItemIds],
          rewardQty: Math.round(toInt(form.rewardQty) || 1),
          benefitMode,
          value,
          multiplyByBundle: form.multiplyByBundle,
        }],
        includedItemIds: form.includedItemIds,
        includedGroupIds: form.includedGroupIds,
      };
    }
  }
}

const vnd = (n: number) => `${new Intl.NumberFormat("vi-VN").format(n)}đ`;

function rewardText(mode: string | undefined, value: number): string {
  const m = String(mode ?? "").toUpperCase();
  if (m === "PERCENT" && value < 10000) return `giảm ${basisPointsToPercent(value)}%`;
  if (m === "FIXED") return `giảm ${vnd(value)}`;
  return "tặng";
}

/** Mô tả ngắn ưu đãi để hiển thị trong bảng danh sách. */
export function describeCampaignBenefit(cam: StoredCampaign): string {
  const type = normalizeCampaignType(cam.campaignType);
  const tier = cam.tiers?.[0];
  if (type === "BUYXGETY") {
    const c = cam.buyConditions?.[0];
    if (!c) return "";
    return `Mua ${num(c.requiredBuyQty)} X → ${rewardText(c.benefitMode, num(c.value))} ${num(c.rewardQty)} Y${c.multiplyByBundle === false ? " (1 lần/đơn)" : ""}`;
  }
  if (!tier) return "";
  const value = tierValue(tier);
  const mode = tierBenefitMode(tier);
  const threshold = num(tier.threshold ?? tier.thresholdValue);
  const cap = num(tier.maxDiscountMoney ?? tier.maxBenefitValue);
  const from = threshold > 0 ? ` (đơn từ ${vnd(threshold)})` : "";
  if (type === "ITEMPRICERULE") return value > 0 ? `Đồng giá ${vnd(value)}` : "";
  if (type === "ORDERVALUEITEMBENEFIT") {
    const t = rewardText(mode, value);
    return `${t.charAt(0).toUpperCase()}${t.slice(1)} ${num(tier.maxRewardQty) || 1} món${from}`;
  }
  if (value <= 0) return "";
  const main = mode === "PERCENT" ? `Giảm ${basisPointsToPercent(value)}%` : `Giảm ${vnd(value)}`;
  return `${main}${cap > 0 ? `, tối đa ${vnd(cap)}` : ""}${from}`;
}

/** Chuẩn hóa chế độ cộng dồn về giá trị Flutter dùng ("ENABLED" | "DISABLED"); dữ liệu web cũ ghi "STACKABLE". */
export function normalizeStackingMode(mode?: string | null): "ENABLED" | "DISABLED" {
  const m = (mode || "").toUpperCase();
  return m === "DISABLED" || m === "EXCLUSIVE" ? "DISABLED" : "ENABLED";
}
