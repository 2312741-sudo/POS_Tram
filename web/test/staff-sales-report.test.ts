import { describe, it, expect } from "vitest";
import { inReportRange, resolveReportRange, soldItemRows, staffItemSummary, formatRangeLabel } from "../lib/staff-sales-report";
import type { HistoryOrder } from "../lib/reports";

const vn = (y: number, mo: number, d: number, h: number, mi = 0) => Date.UTC(y, mo - 1, d, h - 7, mi);

const bill = (id: string, ts: number, items: unknown[], extra: Partial<HistoryOrder> = {}) =>
  ({ id, billCode: `HD-${id}`, status: "PAID", timestamp: ts, tableName: "Bàn 1", cashierName: "Thu Ngân A", paymentMethod: "CASH", items, ...extra }) as unknown as HistoryOrder;

const bills = [
  bill("1", vn(2026, 10, 29, 9), [
    { productId: 1, name: "Trà đào", price: 30000, quantity: 2, orderedBy: "pv1", orderedByName: "Phục Vụ 1", selectedToppings: ["Trân châu"], toppingPrice: 5000 },
    { productId: 2, name: "Bánh mì", price: 20000, quantity: 1, orderedBy: "pv2", orderedByName: "Phục Vụ 2" },
  ]),
  bill("2", vn(2026, 10, 29, 10), [{ productId: 1, name: "Trà đào", price: 30000, quantity: 1, orderedBy: "pv1", orderedByName: "Phục Vụ 1", lineDiscountTotal: 5000, discountAmount: 5000 }]),
  bill("3", vn(2026, 10, 29, 11), [{ productId: 2, name: "Bánh mì", price: 20000, quantity: 5, orderedBy: "pv1" }], { status: "CANCELLED" }),
];

describe("Món đã bán theo nhân viên", () => {
  it("mỗi món một dòng kèm người order + người thu; topping dòng riêng; bỏ đơn hủy", () => {
    const rows = soldItemRows(bills);
    expect(rows.map((r) => [r.billCode, r.productName, r.quantity, r.netAmount, r.orderStaffName, r.cashierName])).toEqual([
      ["HD-1", "Trà đào", 2, 60000, "Phục Vụ 1", "Thu Ngân A"],
      ["HD-1", "Trân châu", 2, 10000, "Phục Vụ 1", "Thu Ngân A"],
      ["HD-1", "Bánh mì", 1, 20000, "Phục Vụ 2", "Thu Ngân A"],
      ["HD-2", "Trà đào", 1, 25000, "Phục Vụ 1", "Thu Ngân A"],
    ]);
    expect(rows[1].options).toBe("Topping (kèm Trà đào)");
  });
  it("gộp nhân viên × món: số lượng, doanh thu, số hóa đơn; nhân viên doanh thu cao xếp trước", () => {
    const { items, staff } = staffItemSummary(soldItemRows(bills));
    expect(items.map((r) => [r.orderStaffName, r.productName, r.quantity, r.netAmount, r.billCount])).toEqual([
      ["Phục Vụ 1", "Trà đào", 3, 85000, 2],
      ["Phục Vụ 1", "Trân châu", 2, 10000, 1],
      ["Phục Vụ 2", "Bánh mì", 1, 20000, 1],
    ]);
    expect(staff.map((s) => [s.orderStaffName, s.itemCount, s.netAmount, s.billCount])).toEqual([
      ["Phục Vụ 1", 5, 95000, 2],
      ["Phục Vụ 2", 1, 20000, 1],
    ]);
  });
  it("thiếu tên người order → dùng mã tài khoản, không có thì 'Không rõ'", () => {
    const rows = soldItemRows([bill("9", vn(2026, 10, 29, 9), [{ name: "X", price: 1, orderedBy: "pv9" }, { name: "Y", price: 1 }])]);
    expect(rows.map((r) => r.orderStaffName)).toEqual(["pv9", "Không rõ"]);
  });
});

describe("Khoảng ngày theo ngày kinh doanh", () => {
  const now = vn(2026, 10, 29, 15);
  it("các mốc có sẵn", () => {
    expect(resolveReportRange("TODAY", now)).toEqual({ from: "2026-10-29", to: "2026-10-29" });
    expect(resolveReportRange("YESTERDAY", now)).toEqual({ from: "2026-10-28", to: "2026-10-28" });
    expect(resolveReportRange("7DAYS", now)).toEqual({ from: "2026-10-23", to: "2026-10-29" });
    expect(resolveReportRange("THIS_MONTH", now)).toEqual({ from: "2026-10-01", to: "2026-10-29" });
    expect(resolveReportRange("LAST_MONTH", now)).toEqual({ from: "2026-09-01", to: "2026-09-30" });
    expect(resolveReportRange("LAST_MONTH", vn(2026, 1, 5, 9))).toEqual({ from: "2025-12-01", to: "2025-12-31" });
    expect(resolveReportRange("CUSTOM", now, 0, { from: "2026-10-10", to: "2026-10-05" })).toEqual({ from: "2026-10-10", to: "2026-10-10" });
  });
  it("giờ bắt đầu ngày 04:00: 02:00 sáng vẫn thuộc hôm trước", () => {
    expect(resolveReportRange("TODAY", vn(2026, 10, 29, 2), 240)).toEqual({ from: "2026-10-28", to: "2026-10-28" });
  });
  it("lọc hóa đơn theo ngày VN", () => {
    const r = { from: "2026-10-29", to: "2026-10-29" };
    expect(inReportRange(bills[0], r)).toBe(true);
    expect(inReportRange(bill("x", vn(2026, 10, 30, 0, 30), []), r)).toBe(false);
    expect(formatRangeLabel(r)).toBe("Ngày 29/10/2026");
    expect(formatRangeLabel({ from: "2026-10-01", to: "2026-10-29" })).toBe("Từ 01/10/2026 đến 29/10/2026");
  });
});
