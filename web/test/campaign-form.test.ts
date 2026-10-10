import { describe, it, expect } from "vitest";
import {
  CAMPAIGN_TYPE_LABELS,
  basisPointsToPercent,
  buildBenefitFields,
  campaignToForm,
  describeCampaignBenefit,
  emptyCampaignForm,
  normalizeCampaignType,
  percentToBasisPoints,
  validateCampaignForm,
  type CampaignFormState,
  normalizeStackingMode,
} from "../lib/campaign-form";

const form = (patch: Partial<CampaignFormState>): CampaignFormState => ({ ...emptyCampaignForm(), name: "KM", ...patch });

describe("units", () => {
  it("percent <-> basis points", () => {
    expect(percentToBasisPoints(10)).toBe(1000);
    expect(percentToBasisPoints(2.5)).toBe(250);
    expect(basisPointsToPercent(1000)).toBe(10);
    // 1% = 100 bp (không bị hiểu nhầm là 100%)
    expect(basisPointsToPercent(100)).toBe(1);
  });
  it("normalizes campaign types incl. underscore variants", () => {
    expect(normalizeCampaignType("BILL_DISCOUNT")).toBe("BILLDISCOUNT");
    expect(normalizeCampaignType("buy_x_get_y")).toBe("BUYXGETY");
    expect(normalizeCampaignType("???")).toBe("BILLDISCOUNT");
  });
  it("renames Mua X tặng Y", () => {
    expect(CAMPAIGN_TYPE_LABELS.BUYXGETY).toBe("Mua X tặng/giảm giá Y");
  });
});

describe("BILLDISCOUNT", () => {
  it("writes Flutter-compatible tier with cap & threshold, whole bill scope", () => {
    const out = buildBenefitFields(form({ discountType: "PERCENT", discountValue: "10", maxDiscount: "50000", threshold: "200000", includedItemIds: ["A"] }));
    expect(out.includedItemIds).toEqual([]);
    expect(out.includedGroupIds).toEqual([]);
    expect(out.buyConditions).toEqual([]);
    expect(out.tiers[0]).toMatchObject({
      tierId: "TIER_1", conditionBasis: "TOTALAMOUNT", benefitMode: "PERCENT", benefitType: "DISCOUNT_PERCENT",
      value: 1000, benefitValue: 1000, threshold: 200000, thresholdValue: 200000,
      maxDiscountMoney: 50000, maxBenefitValue: 50000, sortOrder: 1, rewardItemIds: [],
    });
  });
  it("amount mode keeps cap and threshold", () => {
    const t = buildBenefitFields(form({ discountType: "AMOUNT", discountValue: "20000", maxDiscount: "15000", threshold: "100000" })).tiers[0];
    expect(t).toMatchObject({ benefitMode: "FIXED", benefitType: "DISCOUNT_AMOUNT", value: 20000, maxDiscountMoney: 15000, threshold: 100000 });
  });
  it("round-trips form <-> model and keeps tierId", () => {
    const f = form({ discountType: "PERCENT", discountValue: "12.5", maxDiscount: "30000", threshold: "150000" });
    const tiers = buildBenefitFields(f, { tiers: [{ tierId: "T_OLD" }] }).tiers;
    expect(tiers[0].tierId).toBe("T_OLD");
    const back = campaignToForm({ name: "KM", campaignType: "BILLDISCOUNT", tiers });
    expect(back).toMatchObject({ discountType: "PERCENT", discountValue: "12.5", maxDiscount: "30000", threshold: "150000" });
  });
  it("reads legacy tier with benefitType only", () => {
    const back = campaignToForm({ campaignType: "BILLDISCOUNT", tiers: [{ benefitType: "DISCOUNT_AMOUNT", benefitValue: 5000, thresholdValue: 50000 }] });
    expect(back).toMatchObject({ discountType: "AMOUNT", discountValue: "5000", threshold: "50000" });
  });
  it("validates", () => {
    expect(validateCampaignForm(form({ name: "" }))).toMatch(/Tên/);
    expect(validateCampaignForm(form({ discountValue: "0" }))).toMatch(/%/);
    expect(validateCampaignForm(form({ discountValue: "101" }))).toMatch(/%/);
    expect(validateCampaignForm(form({ discountValue: "10", maxDiscount: "-1" }))).toMatch(/Giảm tối đa/);
    expect(validateCampaignForm(form({ discountValue: "10" }))).toBeNull();
  });
});

describe("ORDERVALUEITEMBENEFIT", () => {
  it("stores threshold, reward items, qty and benefit in tier", () => {
    const f = form({ campaignType: "ORDERVALUEITEMBENEFIT", threshold: "300000", rewardItemIds: ["P1", "P2"], rewardQty: "2", rewardBenefit: "PERCENT", rewardValue: "50" });
    const t = buildBenefitFields(f).tiers[0];
    expect(t).toMatchObject({ threshold: 300000, rewardItemIds: ["P1", "P2"], maxRewardQty: 2, benefitMode: "PERCENT", value: 5000 });
    expect(campaignToForm({ campaignType: "ORDERVALUEITEMBENEFIT", tiers: [t] })).toMatchObject({
      threshold: "300000", rewardItemIds: ["P1", "P2"], rewardQty: "2", rewardBenefit: "PERCENT", rewardValue: "50",
    });
  });
  it("free item = FREEITEM 100%", () => {
    const t = buildBenefitFields(form({ campaignType: "ORDERVALUEITEMBENEFIT", threshold: "1", rewardItemIds: ["P"], rewardBenefit: "FREEITEM" })).tiers[0];
    expect(t).toMatchObject({ benefitMode: "FREEITEM", value: 10000, maxRewardQty: 1 });
    expect(campaignToForm({ campaignType: "ORDERVALUEITEMBENEFIT", tiers: [t] }).rewardBenefit).toBe("FREEITEM");
  });
  it("requires threshold and reward items", () => {
    expect(validateCampaignForm(form({ campaignType: "ORDERVALUEITEMBENEFIT", rewardItemIds: ["P"] }))).toMatch(/đơn hàng từ/);
    expect(validateCampaignForm(form({ campaignType: "ORDERVALUEITEMBENEFIT", threshold: "1000" }))).toMatch(/món Y/);
    expect(validateCampaignForm(form({ campaignType: "ORDERVALUEITEMBENEFIT", threshold: "1000", rewardItemIds: ["P"], rewardBenefit: "FIXED", rewardValue: "" }))).toMatch(/tiền/);
  });
});

describe("BUYXGETY", () => {
  it("builds a CampaignBuyCondition", () => {
    const f = form({ campaignType: "BUYXGETY", buyItemIds: ["X"], buyQty: "2", rewardItemIds: ["Y"], rewardQty: "1", rewardBenefit: "FIXED", rewardValue: "10000", multiplyByBundle: false });
    const out = buildBenefitFields(f, { buyConditions: [{ conditionId: "C9" }] });
    expect(out.tiers).toEqual([]);
    expect(out.buyConditions).toEqual([{
      conditionId: "C9", buyItemIds: ["X"], requiredBuyQty: 2, rewardItemIds: ["Y"], rewardQty: 1,
      benefitMode: "FIXED", value: 10000, multiplyByBundle: false,
    }]);
    const back = campaignToForm({ campaignType: "BUYXGETY", buyConditions: out.buyConditions });
    expect(back).toMatchObject({ buyItemIds: ["X"], buyQty: "2", rewardItemIds: ["Y"], rewardQty: "1", rewardBenefit: "FIXED", rewardValue: "10000", multiplyByBundle: false });
  });
  it("multiplyByBundle defaults to true for legacy conditions", () => {
    expect(campaignToForm({ campaignType: "BUYXGETY", buyConditions: [{ buyItemIds: ["X"], requiredBuyQty: 1 }] }).multiplyByBundle).toBe(true);
  });
  it("validates X and Y", () => {
    expect(validateCampaignForm(form({ campaignType: "BUYXGETY", rewardItemIds: ["Y"] }))).toMatch(/món X/);
    expect(validateCampaignForm(form({ campaignType: "BUYXGETY", buyItemIds: ["X"] }))).toMatch(/món Y/);
    expect(validateCampaignForm(form({ campaignType: "BUYXGETY", buyItemIds: ["X"], rewardItemIds: ["Y"] }))).toBeNull();
  });
});

describe("describeCampaignBenefit", () => {
  it("bill discount", () => {
    const tiers = buildBenefitFields(form({ discountValue: "10", maxDiscount: "50000", threshold: "100000" })).tiers;
    expect(describeCampaignBenefit({ campaignType: "BILLDISCOUNT", tiers })).toMatch(/^Giảm 10%, tối đa 50\.000đ \(đơn từ 100\.000đ\)$/);
  });
  it("buy x get y", () => {
    const buyConditions = buildBenefitFields(form({ campaignType: "BUYXGETY", buyItemIds: ["X"], buyQty: "2", rewardItemIds: ["Y"], multiplyByBundle: false })).buyConditions;
    expect(describeCampaignBenefit({ campaignType: "BUYXGETY", buyConditions })).toBe("Mua 2 X → tặng 1 Y (1 lần/đơn)");
  });
});

describe("normalizeStackingMode", () => {
  it("quy STACKABLE (web cũ) và rỗng về ENABLED, giữ DISABLED", () => {
    expect(normalizeStackingMode("STACKABLE")).toBe("ENABLED");
    expect(normalizeStackingMode(undefined)).toBe("ENABLED");
    expect(normalizeStackingMode("disabled")).toBe("DISABLED");
  });
});
