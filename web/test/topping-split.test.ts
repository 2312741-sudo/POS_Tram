import { describe, it, expect } from "vitest";
import { buildToppingLookup, splitLineParts } from "../lib/topping-split";
import { calculateProductReport, type HistoryOrder } from "../lib/reports";

// Cùng tình huống với app_flutter/test/topping_split_test.dart — hai bên phải ra cùng số
const lookup = buildToppingLookup([
  { id: 901, name: "Trân châu", price: 5000, costPrice: 1500, isTopping: true, category: "Topping" },
  { id: 902, name: "Kem cheese", price: 8000, costPrice: 2500, isTopping: true, category: "Topping" },
]);
const line = {
  productId: 1, name: "Trà đào", price: 30000, sizeExtraPrice: 5000, quantity: 2,
  selectedToppings: ["Trân châu", "Kem cheese"], toppingPrice: 13000, lineDiscountTotal: 10000, discountAmount: 10000,
};

describe("Tách topping khỏi món gốc", () => {
  it("món gốc = giá + size; mỗi topping một dòng riêng; giảm giá chia theo tỉ lệ tiền", () => {
    const parts = splitLineParts(line, lookup);
    expect(parts.map((p) => [p.name, p.isTopping, p.quantity, p.grossRevenue, p.itemDiscount, p.costPrice])).toEqual([
      ["Trà đào", false, 2, 70000, 7292, 0],
      ["Trân châu", true, 2, 10000, 1042, 3000],
      ["Kem cheese", true, 2, 16000, 1666, 5000],
    ]);
    // Tổng không đổi so với dòng gốc
    expect(parts.reduce((s, p) => s + p.grossRevenue, 0)).toBe((30000 + 5000 + 13000) * 2);
    expect(parts.reduce((s, p) => s + p.itemDiscount, 0)).toBe(10000);
  });
  it("không tra được giá topping → chia đều toppingPrice", () => {
    const parts = splitLineParts({ ...line, lineDiscountTotal: 0, discountAmount: 0, toppingPrice: 9000, selectedToppings: ["A", "B"] });
    expect(parts.slice(1).map((p) => [p.name, p.grossRevenue, p.category])).toEqual([["A", 9000, "Topping"], ["B", 9000, "Topping"]]);
  });
  it("báo cáo hàng hóa: topping có số bán riêng, món gốc không còn gộp tiền topping", () => {
    const bill = { id: "B1", status: "PAID", timestamp: 1, items: [line] } as unknown as HistoryOrder;
    const pm = { 901: { id: 901, name: "Trân châu", price: 5000, costPrice: 1500, isTopping: true, category: "Topping" }, "Trân châu": { id: 901, name: "Trân châu", price: 5000, costPrice: 1500, isTopping: true, category: "Topping" }, "Kem cheese": { id: 902, name: "Kem cheese", price: 8000, costPrice: 2500, isTopping: true, category: "Topping" } };
    const r = calculateProductReport([bill], pm as never);
    const by = Object.fromEntries(r.map((x) => [x.productName, [x.quantity, x.grossRevenue, x.netRevenue]]));
    expect(by).toEqual({ "Trà đào": [2, 70000, 62708], "Trân châu": [2, 10000, 8958], "Kem cheese": [2, 16000, 14334] });
  });
});
