import { describe, it, expect } from "vitest";
import { calculatePrice, isEligibleAt, parseCampaign, listEligibleCampaigns, quoteCampaign, type Campaign, type PricingLine } from "../lib/pricing-engine";

// Giờ Việt Nam (UTC+7) → timestamp
const vn = (y: number, mo: number, d: number, h: number, mi = 0) => Date.UTC(y, mo - 1, d, h - 7, mi);
const line = (id: string, item: string, qty: number, price: number, group?: string): PricingLine => ({ lineId: id, itemId: item, quantity: qty, unitPrice: price, discountPercent: 0, discountedQuantity: 0, groupId: group });

/** Dữ liệu thô như web ghi vào RTDB cho "Combo bánh và nước giảm 10K" */
const rawCombo = {
  campaignId: "CAM_HD1", programCode: "KM/HD0001", name: "Combo bánh và nước giảm 10K", campaignType: "BUYXGETY", active: true,
  schedule: { timezone: "Asia/Ho_Chi_Minh", timeSlots: [{ startTime: "18:00", endTime: "20:00" }, { startTime: "22:00", endTime: "12:00" }] },
  branchIds: ["TRAM01"], hasCodes: false, stackingMode: "ENABLED", priority: 0, createdAt: 1,
  buyConditions: [{ conditionId: "C1", buyItemIds: [], buyGroupIds: ["TRÀ TRÁI CÂY", "TRÀ TRÁI CÂY PRE"], requiredBuyQty: 1, rewardItemIds: ["77"], rewardGroupIds: [], rewardQty: 1, benefitMode: "FIXED", value: 10000, multiplyByBundle: true }],
};
const combo = (): Campaign => parseCampaign("CAM_HD1", rawCombo as never);
const cart = [line("1", "5", 1, 45000, "TRÀ TRÁI CÂY"), line("2", "77", 1, 30000, "BÁNH")];
const q = (c: Campaign, lines: PricingLine[], nowMs: number) => calculatePrice({ branchId: "TRAM01", nowMs, lines }, [c]);

describe("Combo bánh & nước (Mua X theo nhóm, khung giờ)", () => {
  it("đúng khung giờ 19:00 → giảm 10.000đ", () => {
    expect(q(combo(), cart, vn(2026, 10, 22, 19)).totalPromotionDiscount).toBe(10000);
  });
  it("khung giờ qua đêm 22:00–12:00: 23:30 và 08:00 đều áp dụng", () => {
    expect(q(combo(), cart, vn(2026, 10, 22, 23, 30)).totalPromotionDiscount).toBe(10000);
    expect(q(combo(), cart, vn(2026, 10, 23, 8)).totalPromotionDiscount).toBe(10000);
  });
  it("ngoài khung giờ (15:00) → không áp dụng, có lý do", () => {
    const r = q(combo(), cart, vn(2026, 10, 22, 15));
    expect(r.totalPromotionDiscount).toBe(0);
    expect(r.reasons[0].reasonCode).toBe("OUTSIDE_SCHEDULE");
  });
  it("khung giờ tính theo giờ Việt Nam kể cả khi máy chạy múi giờ khác (UTC 12:00 = 19:00 VN)", () => {
    expect(isEligibleAt(combo(), Date.UTC(2026, 9, 22, 12, 0))).toBe(true);
    expect(isEligibleAt(combo(), Date.UTC(2026, 9, 22, 8, 0))).toBe(false); // 15:00 VN
  });
  it("có nước nhưng chưa có bánh → báo cần thêm món Y (để app tự thêm)", () => {
    const r = q(combo(), [line("1", "5", 1, 45000, "TRÀ TRÁI CÂY")], vn(2026, 10, 22, 19));
    expect(r.reasons[0].reasonCode).toBe("REWARD_ITEM_NOT_IN_BILL");
  });
  it("chỉ có bánh, chưa mua nước → INSUFFICIENT_BUY_ITEMS", () => {
    const r = q(combo(), [line("2", "77", 1, 30000, "BÁNH")], vn(2026, 10, 22, 19));
    expect(r.reasons[0].reasonCode).toBe("INSUFFICIENT_BUY_ITEMS");
  });
  it("dữ liệu RTDB trả mảng thưa (object) vẫn đọc được khung giờ", () => {
    const raw = { ...rawCombo, schedule: { timeSlots: { 0: { startTime: "18:00", endTime: "20:00" } }, daysOfWeek: { 0: 4 } } };
    const c = parseCampaign("X", raw as never);
    expect(c.schedule.timeSlots).toHaveLength(1);
    expect(isEligibleAt(c, vn(2026, 10, 22, 19))).toBe(true); // 22/10/2026 là Thứ Năm (4)
    expect(isEligibleAt(c, vn(2026, 10, 23, 19))).toBe(false);
  });
});

describe("Lịch áp dụng (mọi loại KM)", () => {
  const base = parseCampaign("S", { campaignType: "BILLDISCOUNT", active: true, tiers: [{ tierId: "T", benefitMode: "PERCENT", value: 1000, threshold: 0 }] } as never);
  it("ngày trong tuần: Thứ 2=1 … CN=7", () => {
    const c: Campaign = { ...base, schedule: { timeSlots: [], daysOfWeek: [7] } };
    expect(isEligibleAt(c, vn(2026, 10, 25, 10))).toBe(true); // Chủ nhật
    expect(isEligibleAt(c, vn(2026, 10, 26, 10))).toBe(false);
  });
  it("hạn đầu / cuối tuyệt đối", () => {
    const c: Campaign = { ...base, schedule: { timeSlots: [], daysOfWeek: [], absoluteStart: vn(2026, 10, 1, 0), absoluteEnd: vn(2026, 10, 31, 23, 59) } };
    expect(isEligibleAt(c, vn(2026, 9, 30, 23))).toBe(false);
    expect(isEligibleAt(c, vn(2026, 10, 15, 12))).toBe(true);
    expect(isEligibleAt(c, vn(2026, 11, 1, 0, 1))).toBe(false);
  });
  it("giờ 00:00 và đúng mốc cuối khung giờ", () => {
    const c: Campaign = { ...base, schedule: { timeSlots: [{ startTime: "18:00", endTime: "20:00" }], daysOfWeek: [] } };
    expect(isEligibleAt(c, vn(2026, 10, 22, 18, 0))).toBe(true);
    expect(isEligibleAt(c, vn(2026, 10, 22, 20, 0))).toBe(true);
    expect(isEligibleAt(c, vn(2026, 10, 22, 20, 1))).toBe(false);
  });
  it("chi nhánh: danh sách rỗng = mọi chi nhánh", () => {
    const c: Campaign = { ...base, branchIds: ["A"] };
    expect(listEligibleCampaigns([c], "B", vn(2026, 10, 22, 10))).toHaveLength(0);
    expect(listEligibleCampaigns([{ ...base, branchIds: [] }], "B", vn(2026, 10, 22, 10))).toHaveLength(1);
    expect(listEligibleCampaigns([{ ...c, active: false, branchIds: [] }], "B", vn(2026, 10, 22, 10))).toHaveLength(0);
  });
});

describe("Mọi loại KM với dữ liệu thô từ web", () => {
  const now = vn(2026, 10, 22, 19);
  it("Giảm giá đơn (%): đạt ngưỡng", () => {
    const c = parseCampaign("A", { campaignType: "BILLDISCOUNT", active: true, tiers: [{ tierId: "T", benefitMode: "PERCENT", value: 2000, threshold: 100000, maxDiscountMoney: 50000 }] } as never);
    expect(q(c, [line("1", "1", 1, 300000)], now).totalPromotionDiscount).toBe(50000);
    expect(q(c, [line("1", "1", 1, 90000)], now).totalPromotionDiscount).toBe(0);
  });
  it("Giảm giá đơn (số tiền, VOUCHER 200K)", () => {
    const c = parseCampaign("V", { campaignType: "BILLDISCOUNT", active: true, tiers: [{ tierId: "T", benefitMode: "FIXED", value: 200000, threshold: 0 }] } as never);
    expect(q(c, [line("1", "1", 1, 500000)], now).totalPromotionDiscount).toBe(200000);
    expect(q(c, [line("1", "1", 1, 150000)], now).totalPromotionDiscount).toBe(150000);
  });
  it("Giảm/tặng món theo giá trị đơn (tặng 1 trà chanh khi đơn từ 100K)", () => {
    const c = parseCampaign("G", { campaignType: "ORDERVALUEITEMBENEFIT", active: true, tiers: [{ tierId: "T", benefitMode: "FREEITEM", value: 10000, threshold: 100000, maxRewardQty: 1, rewardItemIds: ["9"] }] } as never);
    expect(q(c, [line("1", "1", 1, 150000), line("2", "9", 1, 25000)], now).totalPromotionDiscount).toBe(25000);
    const r = q(c, [line("1", "1", 1, 150000)], now);
    expect(r.reasons[0].reasonCode).toBe("REWARD_ITEM_NOT_IN_BILL");
  });
  it("Đồng giá 14K cho trà xoài", () => {
    const c = parseCampaign("D", { campaignType: "ITEMPRICERULE", active: true, includedItemIds: ["3"], tiers: [{ tierId: "T", benefitMode: "FIXEDPRICE", value: 14000 }] } as never);
    expect(q(c, [line("1", "3", 2, 32000)], now).totalPromotionDiscount).toBe(36000);
  });
  it("Đồng giá lưu bằng benefitType FIXED_PRICE (dữ liệu cũ) vẫn là đồng giá", () => {
    const c = parseCampaign("D", { campaignType: "ITEMPRICERULE", active: true, includedItemIds: ["3"], tiers: [{ tierId: "T", benefitType: "FIXED_PRICE", value: 14000 }] } as never);
    expect(q(c, [line("1", "3", 1, 32000)], now).totalPromotionDiscount).toBe(18000);
  });
  it("Mua X tặng Y theo món cụ thể, nhân theo số bộ", () => {
    const c = parseCampaign("B", { campaignType: "BUYXGETY", active: true, buyConditions: [{ conditionId: "C", buyItemIds: ["1"], requiredBuyQty: 2, rewardItemIds: ["2"], rewardQty: 1, benefitMode: "FREEITEM", value: 10000, multiplyByBundle: true }] } as never);
    expect(q(c, [line("1", "1", 4, 20000), line("2", "2", 3, 15000)], now).totalPromotionDiscount).toBe(30000);
  });
  it("loại KM viết có gạch dưới / chữ thường vẫn nhận (BUY_X_GET_Y)", () => {
    const c = parseCampaign("B", { campaignType: "buy_x_get_y", active: true, buyConditions: [{ conditionId: "C", buyItemIds: ["1"], requiredBuyQty: 1, rewardItemIds: ["2"], rewardQty: 1, benefitMode: "FREEITEM", value: 0 }] } as never);
    expect(q(c, [line("1", "1", 1, 20000), line("2", "2", 1, 15000)], now).totalPromotionDiscount).toBe(15000);
  });
  it("quoteCampaign một chương trình bằng ctx.nowMs", () => {
    const c = combo();
    expect(quoteCampaign(c, cart, { branchId: "TRAM01", nowMs: vn(2026, 10, 22, 19) }).totalPromotionDiscount).toBe(10000);
  });
});

import { calculateCampaignReport, POINTS_ROW_KEY } from "../lib/promotion-report";

describe("Báo cáo khuyến mãi có dòng Đổi điểm tích lũy", () => {
  const bill = (id: string, o: Record<string, unknown>) => ({ id, billCode: id, status: "PAID", timestamp: 1000, finalAmount: 90000, totalAmount: 100000, tableName: "B1", ...o }) as never;
  it("gom điểm đã dùng + tiền giảm từ đổi điểm, kể cả đơn không có CTKM", () => {
    const r = calculateCampaignReport([
      bill("b1", { pointsUsed: 50, pointsDiscount: 5000 }),
      bill("b2", { pointsUsed: 20, pointsDiscount: 2000, discounts: [{ campaignId: "C", campaignName: "KM", amount: 3000 }] }),
      bill("b3", {}),
      bill("b4", { status: "CANCELLED", pointsUsed: 999, pointsDiscount: 99900 }),
    ]);
    const p = r.campaigns.find((c) => c.key === POINTS_ROW_KEY)!;
    expect(p.name).toBe("Đổi điểm tích lũy");
    expect(p.billCount).toBe(2);
    expect(p.pointsUsed).toBe(70);
    expect(p.totalDiscount).toBe(7000);
    expect(p.bills.map((b) => b.pointsUsed).sort()).toEqual([20, 50]);
    expect(r.pointsUsed).toBe(70);
    expect(r.totalDiscount).toBe(10000); // 7.000 đổi điểm + 3.000 KM
    expect(r.billCount).toBe(2); // b1, b2
  });
  it("không có đổi điểm → không có dòng", () => {
    const r = calculateCampaignReport([bill("b1", { discounts: [{ campaignId: "C", campaignName: "KM", amount: 1000 }] })]);
    expect(r.campaigns.some((c) => c.key === POINTS_ROW_KEY)).toBe(false);
    expect(r.pointsUsed).toBe(0);
  });
});

describe("Combo nước + bánh: mỗi món độc lập, không tự thêm", () => {
  const c = parseCampaign("H", { campaignType: "BUYXGETY", active: true, buyConditions: [{ conditionId: "C", buyItemIds: [], buyGroupIds: ["NƯỚC"], requiredBuyQty: 1, rewardItemIds: ["BANH"], rewardQty: 1, benefitMode: "FIXED", value: 10000, multiplyByBundle: true }] } as never);
  const run = (lines: PricingLine[]) => calculatePrice({ branchId: "B", nowMs: 1000, lines }, [c]);
  const nuoc = (qty: number) => line("1", "TRA", qty, 45000, "NƯỚC");
  const banh = (qty: number) => line("2", "BANH", qty, 30000, "BÁNH");
  it("giảm đúng theo số bánh thực tế trong đơn (không tự thêm bánh)", () => {
    expect(run([nuoc(1), banh(1)]).totalPromotionDiscount).toBe(10000);
    expect(run([nuoc(2), banh(1)]).totalPromotionDiscount).toBe(10000);
    expect(run([nuoc(2), banh(2)]).totalPromotionDiscount).toBe(20000);
    expect(run([nuoc(1), banh(2)]).totalPromotionDiscount).toBe(10000); // 1 nước chỉ ghép 1 bánh
  });
  it("chưa có bánh → không giảm; engine chỉ báo lý do, không thêm dòng mới", () => {
    const r = run([nuoc(2)]);
    expect(r.totalPromotionDiscount).toBe(0);
    expect(r.lineBenefits).toHaveLength(1);
  });
});
