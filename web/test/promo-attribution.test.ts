import { describe, it, expect } from "vitest";
import { parseCampaign, quoteStacked, linesFromOrder } from "../lib/pricing-engine";
import { attributeBillsToStaff, discountStaffShares, promoStaffShares, staffMatcher } from "../lib/promo-attribution";
import { calculateCampaignReport, onlyCampaign } from "../lib/promotion-report";
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

  it("số combo theo chương trình = tổng theo nhân viên (hóa đơn web thiếu / lệch comboCount)", () => {
    const mk = (id: string, comboCount: number | undefined, shares: { u: string; n: string; amount: number; combo: number }[]): HistoryOrder =>
      ({
        id, status: "PAID", staffUsername: "thu", staffFullName: "Thu", totalAmount: 100000, finalAmount: 80000,
        items: [{ name: "Trà tắc", price: 25000, quantity: 4, orderedBy: "a", orderedByName: "A" }],
        discounts: [{ campaignId: "C1", campaignType: "BUY_X_GET_Y", description: "Combo", amount: 20000, ...(comboCount ? { comboCount } : {}), staffShares: shares }],
      }) as unknown as HistoryOrder;
    const bills = [
      mk("W1", undefined, [{ u: "a", n: "A", amount: 10000, combo: 1 }, { u: "b", n: "B", amount: 10000, combo: 1 }]),
      mk("W2", 1, [{ u: "a", n: "A", amount: 20000, combo: 2 }]),
      { ...mk("OLD", 3, []), discounts: [{ campaignId: "C1", campaignType: "BUY_X_GET_Y", description: "Combo", amount: 30000, comboCount: 3 }] } as HistoryOrder,
    ];
    const r = calculateCampaignReport(bills);
    expect(r.comboCount).toBe(7);
    expect(r.campaigns[0].comboCount).toBe(7);
    expect(r.staffTotals.reduce((s, x) => s + x.comboCount, 0)).toBe(7);
  });

  it("lọc riêng một chương trình: bảng nhân viên chỉ tính chương trình đó", () => {
    const b = {
      id: "M1", status: "PAID", staffUsername: "thu", staffFullName: "Thu", finalAmount: 90000, pointsDiscount: 5000, pointsUsed: 5,
      items: [{ name: "Bánh", price: 20000, quantity: 3, orderedBy: "a", orderedByName: "A" }],
      discounts: [
        { campaignId: "BN", campaignName: "Combo bánh nước 10K", campaignType: "BUY_X_GET_Y", amount: 20000, comboCount: 2, staffShares: [{ u: "a", n: "A", amount: 10000, combo: 1 }, { u: "b", n: "B", amount: 10000, combo: 1 }] },
        { campaignId: "X", campaignName: "Tặng ly", campaignType: "ORDER_VALUE_ITEM_BENEFIT", amount: 15000, comboCount: 3, staffShares: [{ u: "a", n: "A", amount: 15000, combo: 3 }] },
      ],
    } as unknown as HistoryOrder;
    const all = calculateCampaignReport([b]);
    expect(all.staffTotals.map((s) => [s.staff, s.comboCount])).toEqual(expect.arrayContaining([["A", 4], ["B", 1]]));
    const bn = calculateCampaignReport(onlyCampaign([b], "id:BN"));
    expect([bn.comboCount, bn.totalDiscount, bn.pointsUsed]).toEqual([2, 20000, 0]);
    expect(bn.staffTotals.map((s) => [s.staff, s.comboCount, s.totalDiscount]).sort()).toEqual([["A", 1, 10000], ["B", 1, 10000]]);
    expect(onlyCampaign([b], "ALL")).toEqual([b]);
  });
});
