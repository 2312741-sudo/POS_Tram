import { describe, it, expect } from "vitest";
import {
  REPORT_KINDS,
  buildHubTable,
  filterBillsByStatus,
  filterHubBills,
  hubStaffOptions,
  percentChange,
  previousRange,
} from "../lib/reports-hub";
import type { HistoryOrder } from "../lib/reports";

const vn = (y: number, mo: number, d: number, h: number, mi = 0) => Date.UTC(y, mo - 1, d, h - 7, mi);

const bill = (id: string, ts: number, items: unknown[], extra: Partial<HistoryOrder> = {}) =>
  ({
    id, billCode: `HD-${id}`, status: "PAID", timestamp: ts, tableName: "Bàn 1", staffUsername: "tn1", staffFullName: "Thu Ngân A",
    paymentMethod: "CASH", shiftId: "S1", items, ...extra,
  }) as unknown as HistoryOrder;

const bills = [
  bill("1", vn(2026, 10, 29, 9), [
    { productId: 1, name: "Trà đào", price: 30000, quantity: 2, orderedBy: "pv1", orderedByName: "Phục Vụ 1", selectedToppings: ["Trân châu"], toppingPrice: 5000 },
    { productId: 2, name: "Bánh mì", price: 20000, quantity: 1, orderedBy: "pv2", orderedByName: "Phục Vụ 2" },
  ]),
  bill("2", vn(2026, 10, 29, 10), [{ productId: 1, name: "Trà đào", price: 30000, quantity: 1, orderedBy: "pv1", orderedByName: "Phục Vụ 1" }], { shiftId: "S2", staffUsername: "tn2", staffFullName: "Thu Ngân B" }),
  bill("3", vn(2026, 10, 29, 11), [{ productId: 2, name: "Bánh mì", price: 20000, quantity: 5, orderedBy: "pv1" }], { status: "CANCELLED" }),
];

describe("Trung tâm báo cáo web (giống app)", () => {
  it("có đủ 16 báo cáo của app + Nhân viên × Món, mã không trùng", () => {
    expect(REPORT_KINDS).toHaveLength(17);
    expect(new Set(REPORT_KINDS.map((k) => k.code)).size).toBe(17);
  });

  it("mọi báo cáo dựng được bảng, số cột của dòng / dòng tổng khớp tiêu đề", () => {
    for (const { kind } of REPORT_KINDS) {
      const t = buildHubTable(kind, { bills, date: "2026-10-29" });
      expect(t.columns.length, kind).toBeGreaterThan(0);
      for (const r of t.rows) expect(r.length, kind).toBe(t.columns.length);
      if (t.total) expect(t.total.length, kind).toBe(t.columns.length);
    }
  });

  it("hàng hóa: topping dòng riêng, tìm kiếm + sắp xếp", () => {
    const t = buildHubTable("product", { bills, productSort: "QTY_DESC" });
    expect(t.rows.map((r) => [r[1], r[5]])).toEqual([["Trà đào", 3], ["Trân châu", 2], ["Bánh mì", 1]]);
    expect(buildHubTable("product", { bills, productSearch: "trân" }).rows.map((r) => r[1])).toEqual(["Trân châu"]);
    expect(buildHubTable("product", { bills, productSort: "NAME_ASC" }).rows.map((r) => r[1])).toEqual(["Bánh mì", "Trà đào", "Trân châu"]);
  });

  it("chi tiết món theo HĐ: có người order + thu ngân, topping có dấu +, lọc trạng thái", () => {
    const t = buildHubTable("billItems", { bills, billStatus: "PAID" });
    const name = t.columns.findIndex((c) => c.label === "Tên món");
    const orderer = t.columns.findIndex((c) => c.label === "Người order món");
    const cashier = t.columns.findIndex((c) => c.label === "Thu ngân");
    expect(t.rows.map((r) => [r[0], r[name], r[orderer], r[cashier]])).toEqual([
      ["HD-1", "Trà đào", "Phục Vụ 1", "Thu Ngân A"],
      ["HD-1", "+ Trân châu", "Phục Vụ 1", "Thu Ngân A"],
      ["HD-1", "Bánh mì", "Phục Vụ 2", "Thu Ngân A"],
      ["HD-2", "Trà đào", "Phục Vụ 1", "Thu Ngân B"],
    ]);
    expect(buildHubTable("bills", { bills, billStatus: "CANCELLED" }).rows.map((r) => r[0])).toEqual(["HD-3"]);
    expect(filterBillsByStatus(bills).length).toBe(3);
  });

  it("lọc ca + nhân viên như app (thu ngân hoặc người order món)", () => {
    expect(filterHubBills(bills, "S2").map((b) => b.id)).toEqual(["2"]);
    expect(filterHubBills(bills, "ALL", "tn2").map((b) => b.id)).toEqual(["2"]);
    expect(filterHubBills(bills, "ALL", "Phục Vụ 2").map((b) => b.id)).toEqual(["1"]);
    expect(filterHubBills(bills, "ALL", "pv1").map((b) => b.id)).toEqual(["1", "2", "3"]);
    expect(hubStaffOptions(bills)).toEqual(["Phục Vụ 1", "Phục Vụ 2", "pv1", "tn1", "tn2"]);
  });

  it("so sánh kỳ trước", () => {
    expect(previousRange({ from: "2026-10-29", to: "2026-10-29" })).toEqual({ from: "2026-10-28", to: "2026-10-28" });
    expect(previousRange({ from: "2026-10-23", to: "2026-10-29" })).toEqual({ from: "2026-10-16", to: "2026-10-22" });
    expect(previousRange({ from: "2026-03-01", to: "2026-03-31" })).toEqual({ from: "2026-01-29", to: "2026-02-28" });
    expect(percentChange(120, 100)).toBe(20);
    expect(percentChange(50, 200)).toBe(-75);
    expect(percentChange(10, 0)).toBeNull();
  });
});
