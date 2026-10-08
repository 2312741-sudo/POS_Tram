import { describe, it, expect } from "vitest";
import { billDayKey, fallbackBillCode, formatBillCode, isSequentialBillCode } from "../lib/bill-code";
import { lineUnitPrice, summarizeOrderLines, toppingLabel } from "../lib/order-math";
import { calculateOverviewReport, calculateProductReport, mergeHistoryAndBills, HistoryOrder } from "../lib/reports";

describe("Mã hóa đơn tuần tự (đồng bộ định dạng với Flutter)", () => {
  // 2026-10-08T17:30:00Z = 2026-10-09 00:30 giờ Việt Nam
  const ts = Date.UTC(2026, 9, 8, 17, 30, 0);

  it("khóa ngày theo UTC+7", () => {
    expect(billDayKey(ts)).toBe("261009");
  });

  it("HD-yyMMdd-NNNN", () => {
    expect(formatBillCode("261009", 7)).toBe("HD-261009-0007");
    expect(formatBillCode("261009", 12345)).toBe("HD-261009-12345");
    expect(isSequentialBillCode("HD-261009-0007")).toBe(true);
  });

  it("mã dự phòng HD-yyMMdd-HHmmss-XXXX không trùng định dạng tuần tự", () => {
    const code = fallbackBillCode(ts, () => 0);
    expect(code).toBe("HD-261009-003000-AAAA");
    expect(isSequentialBillCode(code)).toBe(false);
  });
});

describe("Tính tiền dòng món giống Flutter OrderItemModel", () => {
  it("đơn giá gồm size + toppingPrice; topping dạng chuỗi", () => {
    const line = { price: 30000, quantity: 2, sizeExtraPrice: 5000, toppingPrice: 10000, selectedToppings: ["Trân châu"] };
    expect(lineUnitPrice(line)).toBe(45000);
    expect(toppingLabel("Trân châu")).toBe("Trân châu");
  });

  it("dữ liệu cũ: topping dạng object có price", () => {
    expect(lineUnitPrice({ price: 20000, selectedToppings: [{ name: "Thạch", price: 5000 }] })).toBe(25000);
    expect(toppingLabel({ name: "Thạch", price: 5000 })).toBe("Thạch");
  });

  it("giảm giá theo dòng và không vượt quá tiền dòng", () => {
    const r = summarizeOrderLines([
      { price: 50000, quantity: 2, discountAmount: 10000 },
      { price: 10000, quantity: 1, discountAmount: 99999 },
    ]);
    expect(r.subTotal).toBe(110000);
    expect(r.itemDiscounts).toBe(20000);
  });
});

describe("Gộp history (tóm tắt) + bills (đầy đủ)", () => {
  const fullBill = {
    billCode: "HD-261009-0001",
    status: "PAID",
    closedAt: 1000,
    subTotal: 60000,
    finalAmount: 60000,
    items: [{ productId: 1, name: "Cà phê", price: 30000, quantity: 2, discountAmount: 0 }],
  };

  it("history thiếu items thì lấy items từ bills; trạng thái lấy từ history", () => {
    const merged = mergeHistoryAndBills(
      { b1: { billCode: "HD-261009-0001", status: "CANCELLED", closedAt: 1000, finalAmount: 60000 } },
      { b1: fullBill }
    );
    expect(merged).toHaveLength(1);
    const [, rec] = merged[0];
    expect(rec.status).toBe("CANCELLED");
    expect(Array.isArray(rec.items) && rec.items.length).toBe(1);
  });

  it("bỏ qua hóa đơn còn mở chỉ có ở bills; giữ hóa đơn đã chốt chỉ có ở bills", () => {
    const merged = mergeHistoryAndBills(null, {
      open1: { status: "OPEN", subTotal: 1 },
      paid1: fullBill,
    });
    expect(merged.map(([id]) => id)).toEqual(["paid1"]);
  });

  it("bản ghi Flutter đầy đủ thiếu trường tùy chọn vẫn tính báo cáo hợp lệ", () => {
    const [[id, rec]] = mergeHistoryAndBills(undefined, { paid1: fullBill });
    const bill = { ...rec, id } as HistoryOrder;
    const overview = calculateOverviewReport([bill]);
    expect(overview.paidBillsCount).toBe(1);
    expect(overview.netRevenue).toBe(60000);
    expect(overview.vatTotal).toBe(0);
    const products = calculateProductReport([bill]);
    expect(products[0].quantity).toBe(2);
  });
});
