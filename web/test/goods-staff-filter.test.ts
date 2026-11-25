import { describe, it, expect } from "vitest";
import { buildHubTable, goodsHubBills } from "../lib/reports-hub";
import { calculateOverviewReport, type HistoryOrder } from "../lib/reports";

// Bình bấm 2 trà tắc 25k, Chi bấm 1 bánh 20k, An thu tiền; combo 10k trên trà tắc (phần của Bình)
const bill = {
  id: "B1", status: "PAID", shiftId: "S1", staffUsername: "an", staffFullName: "An", paymentMethod: "CASH",
  createdAt: Date.parse("2026-11-20T10:00:00+07:00"),
  items: [
    { productId: 1, name: "Trà tắc", price: 25000, quantity: 2, orderedBy: "binh", orderedByName: "Bình", category: "Trà" },
    { productId: 2, name: "Bánh", price: 20000, quantity: 1, orderedBy: "chi", orderedByName: "Chi", category: "Bánh" },
  ],
  subTotal: 70000, itemDiscounts: 0, totalDiscount: 10000, finalAmount: 60000,
  discounts: [{ campaignId: "C", campaignType: "BUY_X_GET_Y", description: "Combo", amount: 10000, comboCount: 1, staffShares: [{ u: "binh", n: "Bình", amount: 10000, combo: 1 }] }],
} as unknown as HistoryOrder;

const rowsOf = (staff: string, kind: "category" | "product" | "staffItems") =>
  buildHubTable(kind, { bills: goodsHubBills([bill], "ALL", staff) } as never).rows;

describe("Báo cáo hàng hóa lọc nhân viên theo NGƯỜI BẤM MÓN", () => {
  it("chỉ tính món người đó bấm (không lấy cả hóa đơn)", () => {
    expect(rowsOf("binh", "category").map((r) => [r[0], r[1], r[2]])).toEqual([["Trà", 2, 50000]]);
    expect(rowsOf("chi", "category").map((r) => [r[0], r[1], r[2]])).toEqual([["Bánh", 1, 20000]]);
    expect(rowsOf("an", "category")).toEqual([]); // thu ngân không bấm món nào
    expect(rowsOf("chi", "staffItems").map((r) => r[0])).toEqual(["Chi"]);
  });

  it("tiền hóa đơn tính lại theo các món của người đó; cộng mọi người = tổng quán", () => {
    const ob = calculateOverviewReport(goodsHubBills([bill], "ALL", "binh"));
    const oc = calculateOverviewReport(goodsHubBills([bill], "ALL", "chi"));
    const all = calculateOverviewReport([bill]);
    expect([ob.grossRevenue, ob.totalDiscount, ob.netRevenue]).toEqual([50000, 10000, 40000]);
    expect([oc.grossRevenue, oc.totalDiscount, oc.netRevenue]).toEqual([20000, 0, 20000]);
    expect(ob.grossRevenue + oc.grossRevenue).toBe(all.grossRevenue);
    expect(ob.netRevenue + oc.netRevenue).toBe(all.netRevenue);
  });

  it("Tất cả nhân viên: giữ nguyên hóa đơn", () => {
    expect(goodsHubBills([bill], "ALL", "ALL")).toEqual([bill]);
  });
});
