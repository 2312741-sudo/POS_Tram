import { describe, it, expect } from "vitest";
import { buildAppliedDiscount, calculatePrice, isEligibleAt, lateOrderBlock, linesFromOrder, outsideScheduleMessage, parseCampaign, listEligibleCampaigns, quoteCampaign, recalculateDiscounts, type Campaign, type PricingLine } from "../lib/pricing-engine";

// Giờ Việt Nam (UTC+7) → timestamp
const vn = (y: number, mo: number, d: number, h: number, mi = 0) => Date.UTC(y, mo - 1, d, h - 7, mi);
const line = (id: string, item: string, qty: number, price: number, group?: string): PricingLine => ({ lineId: id, itemId: item, quantity: qty, unitPrice: price, discountPercent: 0, discountedQuantity: 0, groupId: group });

/** Dữ liệu thô như web ghi vào RTDB cho "Combo bánh và nước giảm 10K" */
const rawCombo = {
  campaignId: "CAM_HD1", programCode: "KM/HD0001", name: "Combo bánh và nước giảm 10K", campaignType: "BUYXGETY", active: true,
  schedule: { timezone: "Asia/Ho_Chi_Minh", timeSlots: [{ startTime: "18:00", endTime: "20:00" }, { startTime: "22:00", endTime: "00:00" }, { startTime: "02:00", endTime: "04:00" }] },
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
  it("khung giờ 22:00–00:00 và 02:00–04:00: 00:55/01:00 bị chặn, 02:30 áp dụng", () => {
    expect(q(combo(), cart, vn(2026, 10, 22, 23, 30)).totalPromotionDiscount).toBe(10000);
    // 00:55 và 01:00 nằm ngoài khung giờ (chưa tới 02:00 sáng)
    expect(q(combo(), cart, vn(2026, 10, 23, 0, 55)).totalPromotionDiscount).toBe(0);
    expect(q(combo(), cart, vn(2026, 10, 23, 1)).totalPromotionDiscount).toBe(0);
    // 02:30 đúng ca 02:00-04:00 (2h sáng mới bật)
    expect(q(combo(), cart, vn(2026, 10, 23, 2, 30)).totalPromotionDiscount).toBe(10000);
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

describe("so khớp nhóm món chịu khác biệt dấu / hoa thường / khoảng trắng", () => {
  const c = parseCampaign("G", { campaignType: "BUYXGETY", active: true, buyConditions: [{ conditionId: "C", buyItemIds: [], buyGroupIds: ["TRÀ TRÁI CÂY"], requiredBuyQty: 1, rewardItemIds: ["BANH"], rewardQty: 1, benefitMode: "FIXED", value: 10000, multiplyByBundle: true }] } as never);
  const run = (g: string) => calculatePrice({ branchId: "B", nowMs: 1000, lines: [line("1", "N", 1, 45000, g), line("2", "BANH", 1, 30000, "BÁNH")] }, [c]).totalPromotionDiscount;
  it("khớp dù khác hoa/thường, khoảng trắng thừa, dấu dạng tổ hợp (NFD)", () => {
    expect(run("TRÀ TRÁI CÂY")).toBe(10000);
    expect(run("Trà Trái Cây")).toBe(10000);
    expect(run("  trà  trái cây ")).toBe(10000);
    expect(run("TRÀ TRÁI CÂY".normalize("NFD"))).toBe(10000);
    expect(run("Tra trai cay")).toBe(10000);
  });
  it("nhóm khác tên thì không khớp", () => {
    expect(run("TRÀ SỮA")).toBe(0);
  });
});

describe("Khung giờ: lúc bấm phải trong giờ VÀ chỉ món GỌI trong khung giờ mới được tính", () => {
  const ctx = (nowMs: number) => ({ branchId: "TRAM01", nowMs });
  const at = (l: PricingLine, ms: number, name?: string): PricingLine => ({ ...l, orderedAtMs: ms, itemName: name });
  it("nước + bánh gọi trong giờ, bấm 18:30 → được giảm (món mới chưa có giờ gọi cũng tính)", () => {
    const lines = [at(cart[0], vn(2026, 10, 22, 18, 10)), at(cart[1], vn(2026, 10, 22, 18, 25))];
    expect(quoteCampaign(combo(), lines, ctx(vn(2026, 10, 22, 18, 30))).totalPromotionDiscount).toBe(10000);
    expect(quoteCampaign(combo(), cart, ctx(vn(2026, 10, 22, 18, 30))).totalPromotionDiscount).toBe(10000);
    expect(outsideScheduleMessage(combo(), lines)).toBeNull();
  });
  it("nước gọi 17:50 (ngoài giờ), bấm 18:30 → bánh KHÔNG được giảm + có thông báo", () => {
    const lines = [at(cart[0], vn(2026, 10, 22, 17, 50), "Trà Olong"), at(cart[1], vn(2026, 10, 22, 18, 30), "Bánh lăn")];
    expect(quoteCampaign(combo(), lines, ctx(vn(2026, 10, 22, 18, 30))).totalPromotionDiscount).toBe(0);
    const msg = outsideScheduleMessage(combo(), lines);
    expect(msg).toContain("Trà Olong (gọi lúc 17:50)");
    expect(msg).toContain("18:00–20:00");
  });
  it("2 nước: 1 gọi ngoài giờ, 1 trong giờ → chỉ được 1 combo", () => {
    const lines = [
      at(line("1", "5", 1, 45000, "TRÀ TRÁI CÂY"), vn(2026, 10, 22, 17, 40)),
      at(line("2", "5", 1, 45000, "TRÀ TRÁI CÂY"), vn(2026, 10, 22, 18, 5)),
      at(line("3", "77", 2, 30000, "BÁNH"), vn(2026, 10, 22, 18, 6)),
    ];
    expect(quoteCampaign(combo(), lines, ctx(vn(2026, 10, 22, 18, 10))).totalPromotionDiscount).toBe(10000);
  });
  it("tự báo: nước gọi ngoài giờ + bánh trong giờ → báo; đủ điều kiện / chưa có bánh thì không báo", () => {
    const now = { branchId: "TRAM01", nowMs: vn(2026, 10, 22, 18, 30) };
    expect(lateOrderBlock(combo(), [at(cart[0], vn(2026, 10, 22, 17, 50)), at(cart[1], vn(2026, 10, 22, 18, 30))], now)).toContain("gọi lúc 17:50");
    expect(lateOrderBlock(combo(), [at(cart[0], vn(2026, 10, 22, 18, 10)), at(cart[1], vn(2026, 10, 22, 18, 30))], now)).toBeNull();
    expect(lateOrderBlock(combo(), [at(cart[0], vn(2026, 10, 22, 17, 50))], now)).toBeNull();
    const partial = lateOrderBlock(combo(), [
      at(line("1", "5", 1, 45000, "TRÀ TRÁI CÂY"), vn(2026, 10, 22, 17, 40)),
      at(line("2", "5", 1, 45000, "TRÀ TRÁI CÂY"), vn(2026, 10, 22, 18, 5)),
      at(line("3", "77", 2, 30000, "BÁNH"), vn(2026, 10, 22, 18, 6)),
    ], now);
    expect(partial).toContain("chỉ được giảm 10.000đ thay vì 20.000đ");
  });
  it("linesFromOrder lấy giờ gọi món từ orderedAt", () => {
    const [l] = linesFromOrder([{ productId: 5, name: "Trà", price: 45000, quantity: 1, orderedAt: 123 }]);
    expect(l.orderedAtMs).toBe(123);
  });
  it("bấm KM ngoài khung giờ (17:50) → không áp dụng được", () => {
    expect(quoteCampaign(combo(), cart, ctx(vn(2026, 10, 22, 17, 50))).totalPromotionDiscount).toBe(0);
    expect(listEligibleCampaigns([combo()], "TRAM01", vn(2026, 10, 22, 17, 50))).toHaveLength(0);
  });
  it("đã áp dụng lúc 19:50 (món gọi trong giờ), treo đơn tới 20:30 → vẫn giữ giảm", () => {
    const lines = [at(cart[0], vn(2026, 10, 22, 19, 40)), at(cart[1], vn(2026, 10, 22, 19, 45))];
    const applied = [buildAppliedDiscount(combo(), 10000)];
    const r = recalculateDiscounts(applied, { CAM_HD1: combo() }, lines, ctx(vn(2026, 10, 22, 20, 30)));
    expect(r.discounts.map((d) => d.amount)).toEqual([10000]);
    expect(r.dropped).toEqual([]);
  });
  it("đã áp dụng nhưng bỏ bớt món (hết nước) → gỡ", () => {
    const applied = [buildAppliedDiscount(combo(), 10000)];
    const r = recalculateDiscounts(applied, { CAM_HD1: combo() }, [cart[1]], ctx(vn(2026, 10, 22, 20, 30)));
    expect(r.discounts).toEqual([]);
    expect(r.dropped).toHaveLength(1);
  });
});
