import { describe, it, expect } from "vitest";
import {
  CLEAR_PRE_PRINT,
  buildOrderItemsPayload,
  deriveTableStatus,
  orderItemsChanged,
  prePrintPayload,
  prePrintedAtOf,
} from "../lib/table-status";
import { applyLineDiscount, setLineQuantity, summarizeOrderLines } from "../lib/order-math";

describe("deriveTableStatus", () => {
  it("trống / có khách / đặt trước", () => {
    expect(deriveTableStatus({ inUse: false })).toBe("EMPTY");
    expect(deriveTableStatus({ inUse: true })).toBe("IN_USE");
    expect(deriveTableStatus({ inUse: false, isReserved: true })).toBe("RESERVED");
  });

  it("chờ thanh toán khi bàn mở và có prePrintedAt hợp lệ", () => {
    expect(deriveTableStatus({ inUse: true, prePrintedAt: 1_700_000_000_000 })).toBe("AWAITING_PAYMENT");
    expect(deriveTableStatus({ inUse: true, prePrintedAt: "1700000000000" })).toBe("AWAITING_PAYMENT");
  });

  it("bỏ qua prePrintedAt rỗng / không hợp lệ / bàn đã đóng", () => {
    expect(deriveTableStatus({ inUse: true, prePrintedAt: null })).toBe("IN_USE");
    expect(deriveTableStatus({ inUse: true, prePrintedAt: 0 })).toBe("IN_USE");
    expect(deriveTableStatus({ inUse: true, prePrintedAt: "abc" })).toBe("IN_USE");
    expect(deriveTableStatus({ inUse: false, prePrintedAt: 123 })).toBe("EMPTY");
    expect(prePrintedAtOf({ prePrintedAt: -5 })).toBeNull();
  });
});

describe("prePrintPayload", () => {
  it("ghi thời điểm và username (null nếu trống)", () => {
    expect(prePrintPayload(42, "thungan1")).toEqual({ prePrintedAt: 42, prePrintedBy: "thungan1" });
    expect(prePrintPayload(42, "  ")).toEqual({ prePrintedAt: 42, prePrintedBy: null });
    expect(prePrintPayload(42)).toEqual({ prePrintedAt: 42, prePrintedBy: null });
  });
});

describe("buildOrderItemsPayload — xóa trạng thái chờ thanh toán khi món đổi", () => {
  const base = [
    { name: "Trà đào", price: 30000, quantity: 5 },
    { name: "Cà phê", price: 25000, quantity: 1 },
  ];

  it("không đổi gì → null (không ghi, giữ prePrintedAt)", () => {
    expect(buildOrderItemsPayload(base, base.map((x) => ({ ...x })))).toBeNull();
    expect(orderItemsChanged(base, [...base])).toBe(false);
  });

  it("giảm giá dòng → ghi đơn mới và xóa prePrintedAt/prePrintedBy", () => {
    const next = base.map((it, i) => (i === 0 ? applyLineDiscount(it, { percent: 10, discountedQuantity: 2 }) : it));
    const payload = buildOrderItemsPayload(base, next);
    expect(payload).not.toBeNull();
    expect(payload).toMatchObject(CLEAR_PRE_PRINT);
    expect(payload!.prePrintedAt).toBeNull();
    expect(payload!.prePrintedBy).toBeNull();
    const written = JSON.parse(String(payload!.currentOrderJson));
    expect(written[0].lineDiscountTotal).toBe(6000);
    expect(summarizeOrderLines(written)).toEqual({ subTotal: 175000, itemDiscounts: 6000 });
  });

  it("đổi số lượng (setLineQuantity chặn số phần giảm) → xóa trạng thái", () => {
    const discounted = applyLineDiscount(base[0], { percent: 10, discountedQuantity: 5 });
    const prev = [discounted, base[1]];
    const next = [setLineQuantity(discounted, 3), base[1]];
    const payload = buildOrderItemsPayload(prev, next);
    expect(payload).toMatchObject({ prePrintedAt: null, prePrintedBy: null });
    const written = JSON.parse(String(payload!.currentOrderJson));
    expect(written[0].discountedQuantity).toBe(3);
    expect(written[0].lineDiscountTotal).toBe(9000);
  });
});
