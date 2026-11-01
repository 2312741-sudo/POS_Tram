import { describe, it, expect } from "vitest";
import { addLineToOrder, sameOrderWindow } from "../lib/web-order";
import { buildAppliedDiscount, calculatePrice, isEligibleAt, lateOrderBlock, linesFromOrder, quoteStacked, rewardPlanFor, outsideScheduleMessage, parseCampaign, listEligibleCampaigns, quoteCampaign, recalculateDiscounts, type Campaign, type PricingLine } from "../lib/pricing-engine";

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
  it("2 nước bấm ngoài giờ + 1 nước bấm trong giờ + 1 bánh → combo vẫn giảm 1 bánh, không báo lỗi", () => {
    const now = { branchId: "TRAM01", nowMs: vn(2026, 10, 22, 18, 15) };
    const lines = [
      at(line("1", "5", 2, 45000, "TRÀ TRÁI CÂY"), vn(2026, 10, 22, 17, 50)),
      at(line("2", "5", 1, 45000, "TRÀ TRÁI CÂY"), vn(2026, 10, 22, 18, 10)),
      at(line("3", "77", 1, 30000, "BÁNH"), vn(2026, 10, 22, 18, 12)),
    ];
    expect(quoteCampaign(combo(), lines, now).totalPromotionDiscount).toBe(10000);
    expect(lateOrderBlock(combo(), lines, now)).toBeNull();
  });
  it("không gộp món bấm khác khung giờ KM vào cùng dòng", () => {
    const base = { productId: 5, name: "Trà", price: 45000, quantity: 2, orderedAt: vn(2026, 10, 22, 17, 50) };
    const later = { ...base, quantity: 1, orderedAt: vn(2026, 10, 22, 18, 10) };
    expect(addLineToOrder([base], later, [combo()])).toHaveLength(2);
    expect(addLineToOrder([base], { ...later, orderedAt: vn(2026, 10, 22, 17, 55) }, [combo()])).toHaveLength(1);
    expect(sameOrderWindow(vn(2026, 10, 22, 18, 5), vn(2026, 10, 22, 18, 10), [combo()])).toBe(true);
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

describe("Tặng món theo giá trị đơn: món tặng là dòng RIÊNG (rewardCampaignId)", () => {
  const raw = {
    campaignId: "CAM_CHANH", programCode: "KM/CHANH", name: "Tặng 1 chanh đơn 100K", campaignType: "ORDER_VALUE_ITEM_BENEFIT", active: true,
    branchIds: ["TRAM01"], hasCodes: false, stackingMode: "ENABLED", priority: 0, createdAt: 1, schedule: {},
    tiers: [{ tierId: "T1", conditionBasis: "TOTALAMOUNT", threshold: 100000, benefitMode: "FREEITEM", value: 0, maxRewardQty: 1, rewardItemIds: ["8"], sortOrder: 1 }],
  };
  const c = () => parseCampaign("CAM_CHANH", raw as never);
  const ctx = { branchId: "TRAM01", nowMs: vn(2026, 10, 22, 10) };
  const xoai = line("1", "5", 2, 45000, "TRÀ");
  const chanh = (id: string, reward?: string): PricingLine => ({ ...line(id, "8", 1, 30000, "TRÀ"), rewardCampaignId: reward ?? null });

  it("dòng tặng riêng được ưu tiên; ly khách gọi không bị trừ; dòng tặng không tính mốc", () => {
    const q = quoteCampaign(c(), [xoai, chanh("2"), chanh("3", "CAM_CHANH")], ctx);
    expect(q.totalPromotionDiscount).toBe(30000);
    expect(q.rewardBenefits.map((b) => b.lineId)).toEqual(["3"]);
    expect(quoteCampaign(c(), [xoai, chanh("3", "CAM_CHANH")], ctx).totalPromotionDiscount).toBe(0);
  });
  it("chưa có dòng tặng: web (đơn cũ) vẫn giảm món có sẵn; dedicatedRewardOnly thì không", () => {
    expect(quoteCampaign(c(), [xoai, chanh("2")], ctx).totalPromotionDiscount).toBe(30000);
    expect(calculatePrice({ ...ctx, lines: [xoai, chanh("2")], dedicatedRewardOnly: true }, [c()]).totalPromotionDiscount).toBe(0);
  });
  it("linesFromOrder đọc rewardCampaignId", () => {
    expect(linesFromOrder([{ productId: 8, name: "Chanh", price: 30000, quantity: 1, rewardCampaignId: "CAM_CHANH" }])[0].rewardCampaignId).toBe("CAM_CHANH");
  });
});

describe("Tặng món theo giá trị đơn: tặng kèm topping trên dòng tặng", () => {
  const raw = (n: number) => ({
    campaignId: "CAM_CHANH", programCode: "KM/CHANH", name: "Tặng chanh kèm topping", campaignType: "ORDER_VALUE_ITEM_BENEFIT", active: true,
    branchIds: ["TRAM01"], hasCodes: false, stackingMode: "ENABLED", priority: 0, createdAt: 1, schedule: {},
    tiers: [{ tierId: "T1", threshold: 100000, benefitMode: "FREEITEM", value: 0, maxRewardQty: 1, rewardToppingQty: n, rewardItemIds: ["8"] }],
  });
  const ctx = { branchId: "TRAM01", nowMs: vn(2026, 10, 22, 10) };
  const lines = (tops: number, topPrice: number): PricingLine[] => [
    line("1", "5", 3, 45000, "TRÀ"),
    { ...line("2", "8", 1, 30000 + topPrice, "TRÀ"), rewardCampaignId: "CAM_CHANH", toppingUnitPrice: topPrice, toppingCount: tops },
  ];
  it("kèm 1 topping: ly + 1 topping miễn phí; topping thứ 2 tính tiền; 0 topping tặng thì topping tính tiền", () => {
    expect(quoteCampaign(parseCampaign("C", raw(1) as never), lines(1, 5000), ctx).totalPromotionDiscount).toBe(35000);
    expect(quoteCampaign(parseCampaign("C", raw(1) as never), lines(2, 10000), ctx).totalPromotionDiscount).toBe(35000);
    expect(quoteCampaign(parseCampaign("C", raw(0) as never), lines(1, 5000), ctx).totalPromotionDiscount).toBe(30000);
  });
});

describe("Cộng dồn KM: giảm hóa đơn KHÔNG tính lại trên ly đã tặng", () => {
  const gift = parseCampaign("CAM_CHANH", {
    campaignId: "CAM_CHANH", name: "Tặng chanh", campaignType: "ORDER_VALUE_ITEM_BENEFIT", active: true, branchIds: [], stackingMode: "ENABLED", schedule: {},
    tiers: [{ tierId: "T1", threshold: 100000, benefitMode: "FREEITEM", value: 0, maxRewardQty: 1, rewardItemIds: ["8"] }],
  } as never);
  const bill20 = parseCampaign("CAM_20", {
    campaignId: "CAM_20", name: "Giảm 20%", campaignType: "BILL_DISCOUNT", active: true, branchIds: [], stackingMode: "ENABLED", schedule: {},
    tiers: [{ tierId: "B1", threshold: 0, benefitMode: "PERCENT", value: 2000 }],
  } as never);
  const ctx = { branchId: "TRAM01", nowMs: vn(2026, 10, 22, 10) };
  const lines: PricingLine[] = [line("1", "5", 3, 45000, "TRÀ"), { ...line("2", "8", 1, 22000, "TRÀ"), rewardCampaignId: "CAM_CHANH" }];
  it("tặng chanh 22K + giảm 20% → 20% chỉ trên 135K (27.000đ); recalculate cũng vậy bất kể thứ tự", () => {
    const st = quoteStacked([bill20, gift], lines, ctx);
    expect(st.CAM_CHANH.totalPromotionDiscount).toBe(22000);
    expect(st.CAM_20.totalPromotionDiscount).toBe(27000);
    const r = recalculateDiscounts([buildAppliedDiscount(bill20, 1), buildAppliedDiscount(gift, 1)], { CAM_20: bill20, CAM_CHANH: gift }, lines, ctx);
    expect(Object.fromEntries(r.discounts.map((d) => [d.campaignId, d.amount]))).toEqual({ CAM_20: 27000, CAM_CHANH: 22000 });
  });
});

describe("Món tặng chỉ miễn phí giá món + size, topping / phụ thu Grab vẫn tính tiền", () => {
  const gift = parseCampaign("CAM_CHANH", {
    campaignId: "CAM_CHANH", name: "Grab - Tặng 1 trà chanh đơn trên 100K", campaignType: "ORDER_VALUE_ITEM_BENEFIT", active: true, branchIds: [], stackingMode: "ENABLED", schedule: {},
    tiers: [{ tierId: "T1", threshold: 100000, benefitMode: "FREEITEM", value: 0, maxRewardQty: 1, rewardItemIds: ["8"] }],
  } as never);
  const ctx = { branchId: "TRAM01", nowMs: vn(2026, 10, 22, 10) };
  it("đơn trong ảnh: 3 bánh 32K + trà chanh 27K (20K + thạch dừa 5K + Grab 2K) → giảm 20.000đ, không 27.000đ", () => {
    const lines = linesFromOrder([
      { productId: 4, name: "Bánh lăn choco - vừa", price: 30000, quantity: 3, selectedToppings: ["Tăng giá Grab 2K"], toppingPrice: 2000 },
      { productId: 8, name: "Trà Olong - Chanh tươi", price: 20000, quantity: 1, selectedToppings: ["Thạch dừa", "Tăng giá Grab 2K"], toppingPrice: 7000 },
    ]);
    expect(quoteCampaign(gift, lines, ctx).totalPromotionDiscount).toBe(20000);
  });
});

describe("rewardPlanFor: món có thể làm món tặng (web thêm dòng tặng riêng)", () => {
  it("theo mã món / nhóm món; bỏ topping & món loại trừ", () => {
    const c = parseCampaign("G", {
      campaignId: "G", name: "Tặng chanh", campaignType: "ORDER_VALUE_ITEM_BENEFIT", active: true, branchIds: [], schedule: {}, excludedItemIds: ["X"],
      tiers: [{ tierId: "T1", threshold: 100000, benefitMode: "FREEITEM", value: 0, maxRewardQty: 2, rewardItemIds: ["DR2"], rewardGroupIds: ["Bánh"] }],
    } as never);
    const prods = [
      { id: "-a", name: "Trà Olong - Chanh tươi", code: "DR2", price: 22000 },
      { id: "-b", name: "Bánh A", category: "BÁNH", price: 30000 },
      { id: "-c", name: "Thạch", code: "DR2X", price: 5000, isTopping: true, category: "Bánh" },
      { id: "X", name: "Bánh loại trừ", category: "Bánh", price: 1 },
    ];
    const plan = rewardPlanFor(c, prods);
    expect(plan?.units).toBe(2);
    expect(plan?.candidates.map((p) => p.id)).toEqual(["-a", "-b"]);
    expect(rewardPlanFor(parseCampaign("B", { campaignType: "BILL_DISCOUNT", tiers: [] } as never), prods)).toBeNull();
  });
});

describe("Topping luôn kèm món tặng (vd 'Tăng giá Grab 2K') — dòng tặng 22K về 0đ", () => {
  const camp = parseCampaign("CAM_CHANH", {
    campaignId: "CAM_CHANH", name: "Grab - Tặng 1 trà chanh", campaignType: "ORDER_VALUE_ITEM_BENEFIT", active: true, branchIds: [], stackingMode: "ENABLED", schedule: {},
    tiers: [{ tierId: "T1", threshold: 100000, benefitMode: "FREEITEM", value: 0, maxRewardQty: 1, rewardItemIds: ["8"], rewardToppingIds: ["-grab2k"] }],
  } as never);
  const ctx = { branchId: "TRAM01", nowMs: vn(2026, 10, 22, 10) };
  it("rewardPlanFor trả topping kèm; dòng tặng chanh 20K + Grab 2K = 22K giảm đủ 22K; ly 27K khách gọi giữ nguyên", () => {
    const prods = [
      { id: "8", name: "Trà Olong - Chanh tươi", price: 20000 },
      { id: "-grab2k", name: "Tăng giá Grab 2K (tính theo hoa hồng)", price: 2000, isTopping: true },
    ];
    expect(rewardPlanFor(camp, prods)?.toppings.map((t) => t.name)).toEqual(["Tăng giá Grab 2K (tính theo hoa hồng)"]);
    const lines = linesFromOrder([
      { productId: 4, name: "Bánh lăn choco - vừa", price: 30000, quantity: 3, selectedToppings: ["Tăng giá Grab 2K"], toppingPrice: 2000 },
      { productId: 8, name: "Trà Olong - Chanh tươi", price: 20000, quantity: 1, selectedToppings: ["Thạch dừa", "Tăng giá Grab 2K"], toppingPrice: 7000 },
      { productId: 8, name: "Trà Olong - Chanh tươi", price: 20000, quantity: 1, selectedToppings: ["Tăng giá Grab 2K (tính theo hoa hồng)"], toppingPrice: 2000, rewardCampaignId: "CAM_CHANH" },
    ]);
    const q = quoteCampaign(camp, lines, ctx);
    expect(q.totalPromotionDiscount).toBe(22000);
    expect(q.rewardBenefits.map((b) => b.lineId)).toEqual(["L2"]);
  });
});

describe("recalculateDiscounts với dedicatedOnlyFor (trang bàn web)", () => {
  const camp = parseCampaign("CAM_CHANH", {
    campaignId: "CAM_CHANH", name: "Tặng chanh", campaignType: "ORDER_VALUE_ITEM_BENEFIT", active: true, branchIds: [], stackingMode: "ENABLED", schedule: {},
    tiers: [{ tierId: "T1", threshold: 100000, benefitMode: "FREEITEM", value: 0, maxRewardQty: 1, rewardItemIds: ["8"] }],
  } as never);
  const ctx = { branchId: "TRAM01", nowMs: vn(2026, 10, 22, 10) };
  const only = new Set(["CAM_CHANH"]);
  it("không có ly tặng riêng → gỡ (không trừ ly khách gọi); có ly tặng → giảm ly đó; dưới mốc → gỡ", () => {
    const base = [line("1", "5", 3, 45000, "TRÀ"), line("2", "8", 1, 27000, "TRÀ")];
    expect(recalculateDiscounts([buildAppliedDiscount(camp, 1)], { CAM_CHANH: camp }, base, ctx, { dedicatedOnlyFor: only }).discounts).toEqual([]);
    const withGift = [...base, { ...line("3", "8", 1, 22000, "TRÀ"), rewardCampaignId: "CAM_CHANH" }];
    expect(recalculateDiscounts([buildAppliedDiscount(camp, 1)], { CAM_CHANH: camp }, withGift, ctx, { dedicatedOnlyFor: only }).discounts.map((d) => d.amount)).toEqual([22000]);
    const small = [line("1", "5", 1, 45000, "TRÀ"), { ...line("3", "8", 1, 22000, "TRÀ"), rewardCampaignId: "CAM_CHANH" }];
    expect(recalculateDiscounts([buildAppliedDiscount(camp, 1)], { CAM_CHANH: camp }, small, ctx, { dedicatedOnlyFor: only }).dropped).toHaveLength(1);
  });
});

describe("Giảm 1 ly (giảm tiền / %) theo giá trị đơn: giảm thẳng món khách gọi, không cần ly tặng riêng", () => {
  it("giảm 16K cho 1 ly xoài: chỉ 1 ly trong 3 ly được giảm, kể cả khi dedicatedOnly", () => {
    const c = parseCampaign("X1", {
      campaignId: "X1", name: "Giảm 16K 1 ly xoài", campaignType: "ORDER_VALUE_ITEM_BENEFIT", active: true, branchIds: [], stackingMode: "ENABLED", schedule: {},
      tiers: [{ tierId: "T", threshold: 0, benefitMode: "FIXED", value: 16000, maxRewardQty: 1, rewardItemIds: ["XOAI"] }],
    } as never);
    const lines = [line("L0", "XOAI", 3, 45000, "TRÀ"), line("L1", "BANH", 2, 40000, "BÁNH")];
    const q = quoteStacked([c], lines, { branchId: "B", nowMs: vn(2026, 10, 22, 10) }, { dedicatedOnlyFor: new Set(["X1"]) }).X1;
    expect(q.totalPromotionDiscount).toBe(16000);
    expect(q.rewardBenefits.map((b) => [b.lineId, b.quantity])).toEqual([["L0", 1]]);
  });
});
