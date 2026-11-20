import { describe, it, expect } from "vitest";
import { parseCampaign, quoteStacked, linesFromOrder } from "../lib/pricing-engine";
import { attributeBillsToStaff, discountStaffShares, promoStaffShares, staffMatcher } from "../lib/promo-attribution";
import { calculateCampaignReport } from "../lib/promotion-report";
import type { HistoryOrder } from "../lib/reports";

const combo = parseCampaign("combo", {
  campaignId: "combo", name: "Combo nước + bánh", campaignType: "BUYXGETY", active: true, branchIds: ["TRAM01"],
  buyConditions: [{ conditionId: "c", buyGroupIds: ["TRÀ"], requiredBuyQty: 1, rewardGroupIds: ["BÁNH"], rewardQty: 1, benefitMode: "FIXED", value: 10000 }],
});
const now = Date.UTC(2026, 10, 20, 8);

// A bấm 2 nước, B bấm 1 bánh, C bấm 1 bánh → combo giảm 2 bánh (B, C)
const items = [
  { productId: 1, name: "Trà đào", category: "TRÀ", price: 30000, quantity: 2, orderedBy: "a", orderedByName: "An" },
  { productId: 2, name: "Bánh", category: "BÁNH", price: 25000, quantity: 1, orderedBy: "b", orderedByName: "Bình" },
  { productId: 2, name: "Bánh", category: "BÁNH", price: 25000, quantity: 1, orderedBy: "c", orderedByName: "Chi" },
];

describe("Khuyến mãi tính cho người bấm món", () => {
  const lines = linesFromOrder(items as never);
  const q = quoteStacked([combo], lines, { branchId: "TRAM01", nowMs: now })["combo"];
  const staffOf = (id: string) => {
    const it = items[Number(id.slice(1))];
    return it ? { u: it.orderedBy, n: it.orderedByName } : null;
  };

  it("combo chia cho người bấm MÓN ĐƯỢC GIẢM (bánh), mỗi người 1 combo 10K", () => {
    expect(q.totalPromotionDiscount).toBe(20000);
    const shares = promoStaffShares(q, lines, "combo", staffOf, { u: "thu", n: "Thu ngân" }, 20000);
    expect(shares.sort((x, y) => x.u.localeCompare(y.u))).toEqual([
      { u: "b", n: "Bình", amount: 10000, combo: 1 },
      { u: "c", n: "Chi", amount: 10000, combo: 1 },
    ]);
  });

  it("làm tròn khớp đúng tiền đã lưu", () => {
    const shares = promoStaffShares(q, lines, "combo", staffOf, { u: "thu", n: "Thu ngân" }, 20001);
    expect(shares.reduce((a, s) => a + s.amount, 0)).toBe(20001);
  });

  const bill = (over: Partial<HistoryOrder>): HistoryOrder =>
    ({ id: "B1", billCode: "HD-1", status: "PAID", finalAmount: 90000, staffUsername: "thu", staffFullName: "Thu ngân", items, ...over }) as HistoryOrder;

  it("hóa đơn cũ (chưa lưu người bấm): nhiều người bấm → thu ngân; 1 người bấm → người đó", () => {
    const d = { campaignId: "combo", amount: 20000, comboCount: 2 };
    expect(discountStaffShares(bill({}), d)).toEqual([{ u: "thu", n: "Thu ngân", amount: 20000, combo: 2 }]);
    const one = bill({ items: [items[0]] as never });
    expect(discountStaffShares(one, d)[0].u).toBe("a");
  });

  it("báo cáo lọc theo nhân viên lấy đúng phần của người bấm; tổng cả quán không đổi", () => {
    const shares = promoStaffShares(q, lines, "combo", staffOf, { u: "thu", n: "Thu ngân" }, 20000);
    const b = bill({ discounts: [{ campaignId: "combo", campaignName: "Combo", campaignType: "BUYXGETY", amount: 20000, comboCount: 2, staffShares: shares }] });
    const forB = calculateCampaignReport(attributeBillsToStaff([b], staffMatcher("b")));
    expect([forB.totalDiscount, forB.comboCount]).toEqual([10000, 1]);
    const forThu = attributeBillsToStaff([b], staffMatcher("Thu ngân"));
    expect(calculateCampaignReport(forThu).comboCount).toBe(0);
    const all = calculateCampaignReport([b]);
    expect([all.totalDiscount, all.comboCount]).toEqual([20000, 2]);
    // Bảng theo nhân viên: người bấm món, không phải thu ngân
    expect(all.staffTotals.map((s) => [s.staff, s.comboCount]).sort()).toEqual([["Bình", 1], ["Chi", 1]]);
  });
});
