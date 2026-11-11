import { describe, it, expect } from "vitest";
import { tableDiscountTotal, tablePayableTotal } from "../lib/order-math";

describe("Tiền bàn đang phục vụ sau khuyến mãi", () => {
  const order = JSON.stringify([
    { name: "Trà Olong - Xoài", price: 30000, quantity: 1, toppingPrice: 7000 },
    { name: "Trà đào", price: 30000, quantity: 2, discountAmount: 10000 },
  ]);
  it("trừ giảm giá món + khuyến mãi / giảm đơn đang áp", () => {
    const t = { currentOrderJson: order, discountsJson: JSON.stringify([{ description: "Xoài 16K", amount: 16000 }, { description: "Giảm tay", amount: 4000 }]) };
    expect(tableDiscountTotal(t)).toBe(20000);
    const gross = tablePayableTotal({ currentOrderJson: order });
    expect(tablePayableTotal(t)).toBe(gross - 20000);
  });
  it("không âm; dữ liệu lỗi / trống → 0 giảm", () => {
    expect(tablePayableTotal({ currentOrderJson: order, discountsJson: JSON.stringify([{ amount: 999999 }]) })).toBe(0);
    expect(tableDiscountTotal({ discountsJson: "hỏng" })).toBe(0);
    expect(tablePayableTotal({})).toBe(0);
  });
});
