import { describe, it, expect } from "vitest";
import {
  addWithStacking,
  applyCampaignUsage,
  applyCustomerUsage,
  buildAppliedDiscount,
  calculatePrice,
  evaluateVoucher,
  linesFromOrder,
  listEligibleCampaigns,
  parseCampaign,
  parseVoucher,
  quoteCampaign,
  recalculateDiscounts,
  redeemVoucherValue,
  rollbackVoucherValue,
  type Campaign,
  type PriceQuote,
  type PricingLine,
} from "../lib/pricing-engine";
import { buildOrderReceiptHtml, buildTableBillHtml } from "../lib/print-html";

const tier = (o: Partial<{ threshold: number; mode: string; value: number; cap: number; maxQty: number; reward: string[] }> = {}) => ({
  tierId: `T${o.threshold ?? 0}`,
  conditionBasis: "TOTALAMOUNT",
  threshold: o.threshold ?? 0,
  benefitMode: o.mode ?? "PERCENT",
  value: o.value ?? 0,
  maxDiscountMoney: o.cap ?? 0,
  maxRewardQty: o.maxQty ?? 0,
  rewardItemIds: o.reward ?? [],
  sortOrder: 1,
});

const bxgy = (o: Partial<{ x: string[]; buy: number; y: string[]; get: number; mode: string; value: number; multiply: boolean }> = {}) => ({
  conditionId: "BC",
  buyItemIds: o.x ?? ["X"],
  requiredBuyQty: o.buy ?? 1,
  rewardItemIds: o.y ?? ["Y"],
  rewardQty: o.get ?? 1,
  benefitMode: o.mode ?? "FREEITEM",
  value: o.value ?? 0,
  multiplyByBundle: o.multiply ?? true,
});

function camp(o: Partial<Campaign> & { campaignType: string }): Campaign {
  return {
    campaignId: "C",
    programCode: "KM_C",
    name: "CT C",
    description: "",
    schedule: { timeSlots: [], daysOfWeek: [] },
    branchIds: [],
    includedCustomerIds: [],
    excludedCustomerIds: [],
    includedItemIds: [],
    includedGroupIds: [],
    excludedItemIds: [],
    tiers: [],
    buyConditions: [],
    hasCodes: false,
    autoApply: false,
    requireStaffNote: false,
    stackingMode: "DISABLED",
    priority: 1,
    active: true,
    createdAt: 0,
    ...o,
  };
}

const line = (id: string, item: string, qty: number, price: number, pct = 0, dq = 0): PricingLine => ({
  lineId: id,
  itemId: item,
  quantity: qty,
  unitPrice: price,
  discountPercent: pct,
  discountedQuantity: dq,
});

const q = (c: Campaign, lines: PricingLine[]): PriceQuote => calculatePrice({ branchId: "B", nowMs: 1000, lines }, [c]);

describe("BILL_DISCOUNT", () => {
  it("không chọn món → áp dụng toàn bộ hóa đơn, phân bổ mọi dòng", () => {
    const r = q(camp({ campaignType: "BILLDISCOUNT", tiers: [tier({ mode: "PERCENT", value: 1000 })] }), [line("1", "A", 1, 100000), line("2", "B", 2, 50000)]);
    expect(r.totalPromotionDiscount).toBe(20000);
    expect(Object.keys(r.billBenefits[0].lineAllocations).sort()).toEqual(["1", "2"]);
  });

  it("giảm % có 'Giảm tối đa' (cap), kiểu BILL_DISCOUNT có gạch dưới", () => {
    const r = q(camp({ campaignType: "BILL_DISCOUNT", tiers: [tier({ mode: "PERCENT", value: 2000, cap: 30000 })] }), [line("1", "A", 1, 500000)]);
    expect(r.totalPromotionDiscount).toBe(30000);
  });

  it("giảm số tiền: cap được tôn trọng & không vượt tiền đơn", () => {
    expect(q(camp({ campaignType: "BILLDISCOUNT", tiers: [tier({ mode: "FIXED", value: 50000, cap: 20000 })] }), [line("1", "A", 1, 100000)]).totalPromotionDiscount).toBe(20000);
    expect(q(camp({ campaignType: "BILLDISCOUNT", tiers: [tier({ mode: "FIXED", value: 50000 })] }), [line("1", "A", 1, 30000)]).totalPromotionDiscount).toBe(30000);
  });

  it("'Đơn hàng từ' (threshold) tính trên giá trị sau giảm thủ công theo dòng", () => {
    const c = camp({ campaignType: "BILLDISCOUNT", tiers: [tier({ threshold: 200000, mode: "FIXED", value: 20000 })] });
    expect(q(c, [line("1", "A", 1, 199000)]).totalPromotionDiscount).toBe(0);
    expect(q(c, [line("1", "A", 1, 199000)]).reasons[0].reasonCode).toBe("ORDER_VALUE_NOT_REACHED");
    expect(q(c, [line("1", "A", 2, 100000)]).totalPromotionDiscount).toBe(20000);
    // 2 x 100k giảm thủ công 10% 1 phần → còn 190k < 200k
    expect(q(c, [line("1", "A", 2, 100000, 10, 1)]).totalPromotionDiscount).toBe(0);
  });

  it("lấy bậc cao nhất đạt ngưỡng", () => {
    const c = camp({
      campaignType: "BILLDISCOUNT",
      tiers: [tier({ threshold: 100000, mode: "PERCENT", value: 500 }), tier({ threshold: 300000, mode: "PERCENT", value: 1000 })],
    });
    expect(q(c, [line("1", "A", 1, 150000)]).totalPromotionDiscount).toBe(7500);
    expect(q(c, [line("1", "A", 1, 400000)]).totalPromotionDiscount).toBe(40000);
  });

  it("món loại trừ / phạm vi món", () => {
    const c = camp({ campaignType: "BILLDISCOUNT", includedItemIds: ["A"], tiers: [tier({ mode: "PERCENT", value: 1000 })] });
    expect(q(c, [line("1", "A", 1, 100000), line("2", "B", 1, 100000)]).totalPromotionDiscount).toBe(10000);
  });

  it("phân bổ phần dư đủ tổng giảm", () => {
    const r = q(camp({ campaignType: "BILLDISCOUNT", tiers: [tier({ mode: "FIXED", value: 100 })] }), [line("a", "A", 1, 10000), line("b", "B", 1, 10000), line("c", "C", 1, 10000)]);
    const sum = Object.values(r.billBenefits[0].lineAllocations).reduce((s, n) => s + n, 0);
    expect(sum).toBe(100);
  });
});

describe("BUY_X_GET_Y", () => {
  it("tặng Y, nhân theo số X (5 X mua 1 tặng 1 → 5 Y)", () => {
    const r = q(camp({ campaignType: "BUYXGETY", buyConditions: [bxgy()] }), [line("x", "X", 5, 30000), line("y", "Y", 6, 20000)]);
    expect(r.totalPromotionDiscount).toBe(100000);
    expect(r.rewardBenefits[0].quantity).toBe(5);
    expect(r.rewardBenefits[0].isGift).toBe(true);
    expect(r.appliedCampaignIds).toEqual(["C"]);
  });

  it("không nhân: bao nhiêu X cũng chỉ thưởng rewardQty 1 lần", () => {
    const r = q(camp({ campaignType: "BUYXGETY", buyConditions: [bxgy({ get: 2, multiply: false })] }), [line("x", "X", 5, 30000), line("y", "Y", 6, 20000)]);
    expect(r.totalPromotionDiscount).toBe(40000);
  });

  it("giảm % và giảm số tiền cho Y, chọn Y rẻ nhất trước", () => {
    const lines = [line("x", "X", 2, 30000), line("y1", "Y1", 1, 50000), line("y2", "Y2", 1, 20000)];
    const pct = q(camp({ campaignType: "BUYXGETY", buyConditions: [bxgy({ buy: 2, y: ["Y1", "Y2"], mode: "PERCENT", value: 5000 })] }), lines);
    expect(pct.totalPromotionDiscount).toBe(10000);
    expect(pct.rewardBenefits[0].lineId).toBe("y2");
    const amt = q(camp({ campaignType: "BUYXGETY", buyConditions: [bxgy({ buy: 2, y: ["Y1", "Y2"], mode: "FIXED", value: 30000 })] }), lines);
    expect(amt.totalPromotionDiscount).toBe(20000);
  });

  it("X trùng Y: mua 2 tặng 1 cùng món", () => {
    const c = camp({ campaignType: "BUYXGETY", buyConditions: [bxgy({ x: ["X"], buy: 2, y: ["X"] })] });
    expect(q(c, [line("1", "X", 2, 10000)]).totalPromotionDiscount).toBe(0);
    expect(q(c, [line("1", "X", 3, 10000)]).totalPromotionDiscount).toBe(10000);
    expect(q(c, [line("1", "X", 6, 10000)]).totalPromotionDiscount).toBe(20000);
  });

  it("chưa có Y trong đơn → lý do REWARD_ITEM_NOT_IN_BILL", () => {
    const r = q(camp({ campaignType: "BUYXGETY", buyConditions: [bxgy()] }), [line("x", "X", 1, 30000)]);
    expect(r.totalPromotionDiscount).toBe(0);
    expect(r.reasons[0].reasonCode).toBe("REWARD_ITEM_NOT_IN_BILL");
  });

  it("chưa đủ X → INSUFFICIENT_BUY_ITEMS", () => {
    const r = q(camp({ campaignType: "BUYXGETY", buyConditions: [bxgy({ buy: 3 })] }), [line("x", "X", 2, 30000), line("y", "Y", 1, 1000)]);
    expect(r.reasons[0].reasonCode).toBe("INSUFFICIENT_BUY_ITEMS");
  });

  it("tôn trọng giảm giá đã có trên dòng Y", () => {
    const r = q(camp({ campaignType: "BUYXGETY", buyConditions: [bxgy()] }), [line("x", "X", 1, 30000), line("y", "Y", 1, 20000, 50, 1)]);
    expect(r.totalPromotionDiscount).toBe(10000);
    expect(r.netMoney).toBe(50000 - 10000 - 10000);
  });

  it("web lưu FREEITEM value 10000 vẫn là tặng 100%", () => {
    const r = q(camp({ campaignType: "BUY_X_GET_Y", buyConditions: [bxgy({ mode: "FREEITEM", value: 10000 })] }), [line("x", "X", 1, 1), line("y", "Y", 1, 25000)]);
    expect(r.totalPromotionDiscount).toBe(25000);
  });
});

describe("ORDER_VALUE_ITEM_BENEFIT", () => {
  const c = camp({
    campaignType: "ORDERVALUEITEMBENEFIT",
    tiers: [tier({ threshold: 200000, mode: "FREEITEM", maxQty: 1, reward: ["G"] }), tier({ threshold: 500000, mode: "FREEITEM", maxQty: 2, reward: ["G"] })],
  });

  it("dưới ngưỡng → không áp dụng", () => {
    const r = q(c, [line("a", "A", 1, 120000), line("g", "G", 3, 20000)]); // 180k < 200k
    expect(r.totalPromotionDiscount).toBe(0);
    expect(r.reasons[0].reasonCode).toBe("ORDER_VALUE_NOT_REACHED");
  });

  it("đạt ngưỡng → tặng tối đa maxRewardQty, lấy bậc cao nhất", () => {
    expect(q(c, [line("a", "A", 1, 200000), line("g", "G", 3, 20000)]).totalPromotionDiscount).toBe(20000);
    expect(q(c, [line("a", "A", 1, 500000), line("g", "G", 3, 20000)]).totalPromotionDiscount).toBe(40000);
  });

  it("giảm % món thưởng; chưa có món thưởng → lý do", () => {
    const pc = camp({ campaignType: "ORDERVALUEITEMBENEFIT", tiers: [tier({ threshold: 100000, mode: "PERCENT", value: 5000, maxQty: 1, reward: ["G"] })] });
    expect(q(pc, [line("a", "A", 1, 100000), line("g", "G", 2, 30000)]).totalPromotionDiscount).toBe(15000);
    expect(q(pc, [line("a", "A", 1, 100000)]).reasons[0].reasonCode).toBe("REWARD_ITEM_NOT_IN_BILL");
  });
});

describe("ITEM_PRICE_RULE", () => {
  it("đồng giá: giảm phần chênh trên các dòng trong phạm vi", () => {
    const c = camp({ campaignType: "ITEMPRICERULE", includedItemIds: ["A"], tiers: [tier({ mode: "FIXEDPRICE", value: 20000 })] });
    const r = q(c, [line("1", "A", 3, 35000), line("2", "B", 1, 50000), line("3", "A", 1, 15000)]);
    expect(r.totalPromotionDiscount).toBe(45000);
    expect(r.appliedCampaignIds).toEqual(["C"]);
  });
});

describe("lịch & chi nhánh", () => {
  it("ngoài lịch / sai chi nhánh → lý do, không giảm", () => {
    const c = camp({ campaignType: "BILLDISCOUNT", tiers: [tier({ value: 1000 })], schedule: { absoluteStart: 5000, timeSlots: [], daysOfWeek: [] } });
    expect(q(c, [line("1", "A", 1, 10000)]).reasons[0].reasonCode).toBe("OUTSIDE_SCHEDULE");
    const b = camp({ campaignType: "BILLDISCOUNT", tiers: [tier({ value: 1000 })], branchIds: ["Z"] });
    expect(q(b, [line("1", "A", 1, 10000)]).reasons[0].reasonCode).toBe("BRANCH_NOT_SUPPORTED");
  });

  it("listEligibleCampaigns: active + lịch + chi nhánh, sắp theo priority", () => {
    const a = camp({ campaignId: "A", campaignType: "BILLDISCOUNT", priority: 2 });
    const b = camp({ campaignId: "B", campaignType: "BILLDISCOUNT", priority: 1 });
    const off = camp({ campaignId: "OFF", campaignType: "BILLDISCOUNT", active: false });
    const future = camp({ campaignId: "F", campaignType: "BILLDISCOUNT", schedule: { absoluteStart: 9e12, timeSlots: [], daysOfWeek: [] } });
    const other = camp({ campaignId: "O", campaignType: "BILLDISCOUNT", branchIds: ["Z"] });
    expect(listEligibleCampaigns([a, b, off, future, other], "B", 1000).map((c) => c.campaignId)).toEqual(["B", "A"]);
  });

  it("khung giờ qua đêm", () => {
    const c = camp({ campaignType: "BILLDISCOUNT", schedule: { timeSlots: [{ startTime: "22:00", endTime: "02:00" }], daysOfWeek: [] } });
    const at = (h: number, m: number) => new Date(2026, 9, 12, h, m).getTime();
    expect(listEligibleCampaigns([c], "B", at(23, 0))).toHaveLength(1);
    expect(listEligibleCampaigns([c], "B", at(1, 0))).toHaveLength(1);
    expect(listEligibleCampaigns([c], "B", at(12, 0))).toHaveLength(0);
  });
});

describe("bản ghi bill.discounts", () => {
  it("ghi đủ trường campaign + giữ promoId/promoCode", () => {
    const c = camp({ campaignType: "BILLDISCOUNT", hasCodes: true });
    const d = buildAppliedDiscount(c, 12000, { voucherCode: "tram10" });
    expect(d).toMatchObject({
      campaignId: "C",
      campaignName: "CT C",
      programCode: "KM_C",
      campaignType: "BILLDISCOUNT",
      voucherCode: "TRAM10",
      amount: 12000,
      promoId: "C",
      promoCode: "TRAM10",
      description: "CT C (mã TRAM10)",
    });
    expect(buildAppliedDiscount(c, 5, {}).voucherCode).toBeUndefined();
  });
});

describe("Voucher", () => {
  const vRaw = (state: string, bill?: string) => ({
    voucherId: "V1",
    campaignId: "C",
    normalizedCode: "ABC123",
    state,
    ...(bill ? { redeemedBillId: bill, redeemedBillCode: "HD-261010-0001", redeemedAt: new Date(2026, 9, 10, 9, 30).getTime(), redeemedBy: "thungan1", redeemedByName: "Thu Ngân 1", tableName: "Bàn 5" } : {}),
  });
  const v = (state: string, bill?: string) => parseVoucher("V1", vRaw(state, bill));
  const c = camp({ campaignType: "BILLDISCOUNT", hasCodes: true, tiers: [tier({ mode: "FIXED", value: 10000, threshold: 50000 })] });
  const ev = (vv: ReturnType<typeof v>, cc: Campaign | null, quote?: PriceQuote | null, now = 1000) =>
    evaluateVoucher({ code: " abc123 ", voucher: vv, campaign: cc, nowMs: now, branchId: "B", quote });

  it("ánh xạ trạng thái → thông báo", () => {
    expect(ev(null, null).status).toBe("notFound");
    expect(ev(null, null).message).toBe("Mã ABC123 không tồn tại");
    const used = ev(v("REDEEMED", "BILL1"), c);
    expect(used.status).toBe("redeemed");
    expect(used.message).toContain("HD-261010-0001");
    expect(used.message).toContain("Thu Ngân 1");
    expect(used.message).toContain("10/10/2026 09:30");
    expect(used.message).toContain("(Bàn 5)");
    expect(ev(v("CANCELLED"), c).message).toBe("Mã đã hủy");
    expect(ev(v("DRAFT"), c).status).toBe("notReleased");
    expect(ev(v("RELEASED"), { ...c, schedule: { absoluteStart: 5000, timeSlots: [], daysOfWeek: [] } }).status).toBe("notStarted");
    expect(ev(v("RELEASED"), { ...c, schedule: { absoluteEnd: 500, timeSlots: [], daysOfWeek: [] } }).status).toBe("ended");
    expect(ev(v("RELEASED"), { ...c, active: false }).status).toBe("campaignInactive");
    expect(ev(v("RELEASED"), { ...c, branchIds: ["Z"] }).status).toBe("wrongBranch");
    expect(ev(v("RESERVED"), c).status).toBe("valid"); // hold không có hạn
    const held = parseVoucher("V1", { ...vRaw("RESERVED"), holdExpiresAt: 99999 });
    expect(ev(held, c).status).toBe("held");
  });

  it("mã đã đổi bởi chính hóa đơn này vẫn hợp lệ", () => {
    const r = evaluateVoucher({ code: "abc123", voucher: v("REDEEMED", "BILL1"), campaign: c, nowMs: 1000, branchId: "B", currentBillId: "BILL1" });
    expect(r.status).toBe("valid");
  });

  it("không áp dụng được cho đơn → nêu lý do; hợp lệ → số tiền giảm", () => {
    const na = ev(v("RELEASED"), c, q(c, [line("1", "A", 1, 30000)]));
    expect(na.status).toBe("notApplicable");
    expect(na.message).toContain("chưa đạt");
    const ok = ev(v("RELEASED"), c, q(c, [line("1", "A", 1, 60000)]));
    expect(ok.isValid).toBe(true);
    expect(ok.discount).toBe(10000);
    expect(ok.message).toContain("CT C");
  });

  it("status cũ USED → REDEEMED", () => {
    expect(parseVoucher("V", { status: "USED" })?.state).toBe("REDEEMED");
    expect(parseVoucher("V", { status: "CANCELLED" })?.state).toBe("CANCELLED");
    expect(parseVoucher("V", {})?.state).toBe("RELEASED");
  });

  it("đổi mã: ghi đủ trường, không dùng 2 lần, hoàn tác về RELEASED", () => {
    const base = vRaw("RELEASED");
    const r1 = redeemVoucherValue(base, { billId: "B1", username: "u", billCode: "HD-1", tableName: "Bàn 1", staffName: "Thu Ngân", now: 5000 });
    expect(r1 && "next" in r1).toBe(true);
    const next = (r1 as { next: Record<string, unknown> }).next;
    expect(next).toMatchObject({ state: "REDEEMED", status: "USED", redeemedBillId: "B1", redeemedBillCode: "HD-1", redeemedBy: "u", redeemedByName: "Thu Ngân", tableName: "Bàn 1", redeemedAt: 5000 });
    expect(redeemVoucherValue(next, { billId: "B2", username: "x", now: 6000 })).toEqual({ reject: "Mã voucher đã được sử dụng" });
    expect(redeemVoucherValue(next, { billId: "B1", username: "x", now: 6000 })).toEqual({ reject: "MINE" });
    expect(redeemVoucherValue(null, { billId: "B1", username: "x", now: 1 })).toBeNull();
    expect(redeemVoucherValue({ ...base, state: "CANCELLED" }, { billId: "B", username: "x", now: 1 })).toEqual({ reject: "Mã voucher đã bị hủy" });
    expect(redeemVoucherValue({ ...base, state: "RESERVED", holdExpiresAt: 9000 }, { billId: "B", username: "x", now: 1 })).toMatchObject({ reject: expect.stringContaining("giữ") });
    const back = rollbackVoucherValue(next, "B1");
    expect(back).toMatchObject({ state: "RELEASED", status: "ISSUED", redeemedBillId: null });
    expect(rollbackVoucherValue(next, "OTHER")).toBeNull();
  });
});

describe("bộ đếm lượt dùng", () => {
  it("campaign: cộng spent/use, chặn vượt maxUses & budget, hoàn tác không chặn", () => {
    const a = applyCampaignUsage(null, { campaignId: "C", spentDelta: 10000, useDelta: 1, maxUses: 2, budgetMoney: 25000 });
    expect(a).toMatchObject({ spentMoney: 10000, committedUseCount: 1, version: 1 });
    const b = applyCampaignUsage(a, { campaignId: "C", spentDelta: 10000, useDelta: 1, maxUses: 2, budgetMoney: 25000 });
    expect(b).toMatchObject({ spentMoney: 20000, committedUseCount: 2 });
    expect(applyCampaignUsage(b, { campaignId: "C", spentDelta: 1, useDelta: 1, maxUses: 2 })).toBeNull();
    expect(applyCampaignUsage(a, { campaignId: "C", spentDelta: 20000, useDelta: 1, budgetMoney: 25000 })).toBeNull();
    expect(applyCampaignUsage(b, { campaignId: "C", spentDelta: -20000, useDelta: -2 })).toMatchObject({ spentMoney: 0, committedUseCount: 0 });
    expect(applyCampaignUsage(a, { campaignId: "C", spentDelta: 5, useDelta: 1, maxUses: 0, budgetMoney: 0 })).not.toBeNull();
  });

  it("khách: chặn vượt maxUsesPerCustomer", () => {
    const a = applyCustomerUsage(null, { campaignId: "C", customerId: "K", delta: 1, maxUsesPerCustomer: 1 });
    expect(a).toMatchObject({ usedCount: 1, customerId: "K" });
    expect(applyCustomerUsage(a, { campaignId: "C", customerId: "K", delta: 1, maxUsesPerCustomer: 1 })).toBeNull();
    expect(applyCustomerUsage(a, { campaignId: "C", customerId: "K", delta: -1 })).toMatchObject({ usedCount: 0 });
  });
});

describe("cộng dồn (stacking)", () => {
  const A = camp({ campaignId: "A", campaignType: "BILLDISCOUNT", stackingMode: "ENABLED" });
  const B = camp({ campaignId: "B", campaignType: "BILLDISCOUNT", stackingMode: "ENABLED" });
  const N = camp({ campaignId: "N", campaignType: "BILLDISCOUNT", stackingMode: "DISABLED" });
  const byId = { A, B, N };
  const d = (c: Campaign) => buildAppliedDiscount(c, 1000);

  it("hai chương trình ENABLED đi cùng nhau", () => {
    const r = addWithStacking([d(A)], { discount: d(B), campaign: B }, byId);
    expect(r.discounts.map((x) => x.campaignId)).toEqual(["A", "B"]);
    expect(r.removed).toEqual([]);
  });

  it("chương trình DISABLED loại các chương trình khác, và bị loại khi thêm cái khác", () => {
    expect(addWithStacking([d(A)], { discount: d(N), campaign: N }, byId).discounts.map((x) => x.campaignId)).toEqual(["N"]);
    const r = addWithStacking([d(N)], { discount: d(A), campaign: A }, byId);
    expect(r.discounts.map((x) => x.campaignId)).toEqual(["A"]);
    expect(r.removed).toHaveLength(1);
  });

  it("cửa hàng tắt allowStackPromotions → chỉ giữ cái mới; thêm lại cùng chương trình thì thay thế", () => {
    expect(addWithStacking([d(A)], { discount: d(B), campaign: B }, byId, false).discounts.map((x) => x.campaignId)).toEqual(["B"]);
    expect(addWithStacking([d(A)], { discount: d(A), campaign: A }, byId).discounts).toHaveLength(1);
  });

  it("STACKABLE (web cũ) = ENABLED, DISABLED giữ nguyên", () => {
    expect(parseCampaign("X", { stackingMode: "stackable" }).stackingMode).toBe("ENABLED");
    expect(parseCampaign("X", { stackingMode: "DISABLED" }).stackingMode).toBe("DISABLED");
  });
});

describe("cầu nối giỏ hàng & tính lại", () => {
  it("linesFromOrder dùng đơn giá size+topping và giảm giá dòng đã lưu", () => {
    const lines = linesFromOrder([{ productId: 7, name: "Trà", price: 30000, sizeExtraPrice: 5000, quantity: 2, lineDiscountTotal: 7000, discountAmount: 7000 }, { productId: "9", price: 10000, quantity: 1, category: "Bánh" }]);
    expect(lines[0]).toMatchObject({ lineId: "L0", itemId: "7", quantity: 2, unitPrice: 35000, manualDiscount: 7000 });
    expect(lines[1]).toMatchObject({ itemId: "9", groupId: "Bánh" });
    const c = camp({ campaignType: "BILLDISCOUNT", tiers: [tier({ mode: "PERCENT", value: 1000 })] });
    // cơ sở tính = 70000 - 7000 + 10000 = 73000 → 7300
    expect(quoteCampaign(c, lines, { branchId: "B", nowMs: 1000 }).totalPromotionDiscount).toBe(7300);
  });

  it("recalculateDiscounts cập nhật số tiền và gỡ chương trình hết đủ điều kiện", () => {
    const c = camp({ campaignType: "BILLDISCOUNT", tiers: [tier({ threshold: 50000, mode: "FIXED", value: 10000 })] });
    const ctx = { branchId: "B", nowMs: 1000 };
    const applied = [buildAppliedDiscount(c, 10000)];
    const ok = recalculateDiscounts(applied, { C: c }, [line("L0", "A", 1, 80000)], ctx);
    expect(ok.discounts[0].amount).toBe(10000);
    const low = recalculateDiscounts(applied, { C: c }, [line("L0", "A", 1, 20000)], ctx);
    expect(low.discounts).toHaveLength(0);
    expect(low.dropped).toEqual(["CT C"]);
  });
});

describe("parseCampaign", () => {
  it("khớp CampaignTier.fromMap: benefitType/thresholdValue/benefitValue và mảng RTDB dạng object", () => {
    const c = parseCampaign("CAM1", {
      name: "KM",
      campaignType: "BILL_DISCOUNT",
      active: true,
      tiers: { "0": { benefitType: "DISCOUNT_AMOUNT", benefitValue: 5000, thresholdValue: 100000, maxBenefitValue: 3000 } },
      branchIds: ["TRAM01"],
    });
    expect(c.campaignId).toBe("CAM1");
    expect(c.tiers[0]).toMatchObject({ benefitMode: "FIXED", value: 5000, threshold: 100000, maxDiscountMoney: 3000 });
    expect(c.branchIds).toEqual(["TRAM01"]);
    expect(c.budgetMoney).toBeUndefined();
  });
});

describe("in phiếu có khuyến mãi", () => {
  it("phiếu tạm tính và hóa đơn hiển thị tên chương trình, mã voucher, số tiền (đã escape)", () => {
    const tmp = buildTableBillHtml({ tableName: "B1", zone: "A", items: [{ name: "Trà", price: 50000, quantity: 1 }], total: 40000, promotions: [{ name: "Giảm <b>20%</b>", code: "TRAM10", amount: 10000 }], printedAt: "now" });
    expect(tmp).toContain("KM: Giảm &lt;b&gt;20%&lt;/b&gt; (mã TRAM10)");
    expect(tmp).toContain("-10.000đ");
    const bill = buildOrderReceiptHtml({ id: "x", billCode: "HD-1", totalAmount: 40000, items: [{ name: "Trà", price: 50000, quantity: 1 }], discounts: [{ campaignName: "CT C", voucherCode: "ABC123", amount: 10000 }, { promoName: "Không tiền", amount: 0 }] }, "now");
    expect(bill).toContain("KM: CT C (mã ABC123)");
    expect(bill).not.toContain("Không tiền");
  });
});
