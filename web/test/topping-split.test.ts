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

describe("Báo cáo hàng hóa gom theo mã món", () => {
  it("Thạch dừa gọi riêng + gọi làm topping + bản ghi trùng trong thực đơn → MỘT dòng", async () => {
    const { calculateProductReport } = await import("../lib/reports");
    const productsMap = {
      "-Na": { id: "-Na", name: "Thạch dừa", code: "PK202500044", price: 5000, isTopping: true, category: "Topping" },
      "-Nb": { id: "-Nb", name: "Thạch dừa", code: "PK202500044", price: 5000, category: "Khác" },
      "-Nt": { id: "-Nt", name: "Trà Olong - Xoài", code: "DR202500003", price: 30000, category: "Trà" },
      "-Nt2": { id: "-Nt2", name: "Trà Olong - Xoài", code: "DR202500003", price: 30000, category: "Khác" },
    };
    const bills = [
      { id: "B1", status: "PAID", items: [
        { productId: "-Nt", name: "Trà Olong - Xoài", price: 30000, quantity: 2, selectedToppings: ["Thạch dừa"], toppingPrice: 5000 },
        { productId: "-Nb", name: "Thạch dừa", price: 5000, quantity: 3 },
        { productId: "-Nt2", name: "Trà Olong - Xoài", price: 30000, quantity: 1 },
      ] },
    ];
    const rows = calculateProductReport(bills as never, productsMap as never);
    const pick = (n: string) => rows.filter((r) => r.productName === n).map((r) => [r.productCode, r.quantity]);
    expect(pick("Thạch dừa")).toEqual([["PK202500044", 5]]);
    expect(pick("Trà Olong - Xoài")).toEqual([["DR202500003", 3]]);
  });
});

describe("Nhóm hàng tra theo id → mã → tên (món bấm trên app lưu id số, web nạp thực đơn theo khóa)", () => {
  it("không còn rơi về 'Khác': báo cáo hàng hóa + nhóm hàng ra đúng TRÀ TRÁI CÂY", async () => {
    const { calculateProductReport, calculateCategoryReport, findProductForLine } = await import("../lib/reports");
    const productsMap = {
      "-Nt": { name: "Trà Olong - Xoài", code: "DR202500003", price: 30000, category: "TRÀ TRÁI CÂY" },
      "-Nt2": { name: "Trà Olong - Xoài", code: "DR202500003", price: 30000, category: "Khác" },
    };
    const bills = [{ id: "B1", status: "PAID", items: [{ productId: 5, name: "Trà Olong - Xoài", price: 30000, quantity: 2 }] }];
    expect(calculateProductReport(bills as never, productsMap).map((r) => r.category)).toEqual(["TRÀ TRÁI CÂY"]);
    const cake = { "-Nc": { name: "Bánh lăn choco - vừa", price: 30000, unit: "Cái", category: "BÁNH LĂN" } };
    const cakeBills = [{ id: "B2", status: "PAID", items: [{ productId: 7, name: "Bánh lăn choco - vừa", price: 30000, quantity: 1 }] }];
    expect(calculateProductReport(cakeBills as never, cake).map((r) => [r.category, r.unit])).toEqual([["BÁNH LĂN", "Cái"]]);
    expect(calculateCategoryReport(bills as never, productsMap).map((c) => c.category)).toEqual(["TRÀ TRÁI CÂY"]);
    expect(findProductForLine({ productId: 999, code: "dr202500003" }, productsMap)?.category).toBe("TRÀ TRÁI CÂY");
    expect(findProductForLine({ productId: 999, name: "Không có" }, productsMap)).toBeUndefined();
  });
});
