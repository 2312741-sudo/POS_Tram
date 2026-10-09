import { describe, it, expect } from "vitest";
import {
  applyLineDiscount,
  computeLineDiscount,
  lineDiscountedQuantity,
  lineDiscountLabel,
  lineDiscountTotal,
  setLineQuantity,
  summarizeOrderLines,
  type RawOrderLine,
} from "../lib/order-math";
import {
  calculateCategoryReport,
  calculateOverviewReport,
  calculateProductReport,
  calculatePromotionsReport,
  calculateStaffPerformance,
  itemLineDiscount,
  type HistoryOrder,
} from "../lib/reports";

const fmt = (n: number) => `${n}đ`;

describe("Giảm giá dòng theo số phần được chọn (order-math)", () => {
  it("PERCENT: chỉ giảm 2/5 phần, đơn giá gồm size + topping", () => {
    // unitPrice = 30000 + 5000 + 5000 = 40000; 10% × 2 phần = 8000
    expect(computeLineDiscount({ unitPrice: 40000, quantity: 5, discountedQuantity: 2, percent: 10 })).toBe(8000);
    const line = applyLineDiscount(
      { price: 30000, sizeExtraPrice: 5000, toppingPrice: 5000, quantity: 5 } as RawOrderLine,
      { percent: 10, discountedQuantity: 2 }
    );
    expect(line.lineDiscountTotal).toBe(8000);
    expect(line.discountAmount).toBe(8000);
    expect(line.discountedQuantity).toBe(2);
    expect(lineDiscountLabel(line, fmt)).toBe("Giảm 10% × 2/5 món");
    expect(summarizeOrderLines([line])).toEqual({ subTotal: 200000, itemDiscounts: 8000 });
  });

  it("AMOUNT: đ/phần × số phần, không vượt đơn giá và tiền dòng", () => {
    expect(computeLineDiscount({ unitPrice: 30000, quantity: 5, discountedQuantity: 3, unitAmount: 5000 })).toBe(15000);
    // đơn giá giảm > đơn giá → chặn bằng đơn giá
    expect(computeLineDiscount({ unitPrice: 30000, quantity: 2, discountedQuantity: 2, unitAmount: 50000 })).toBe(60000);
    // discountedQuantity > quantity → chặn
    expect(computeLineDiscount({ unitPrice: 30000, quantity: 2, discountedQuantity: 9, percent: 100 })).toBe(60000);
  });

  it("Đổi số lượng dòng chặn discountedQuantity và tính lại tổng giảm", () => {
    const line = applyLineDiscount({ price: 20000, quantity: 5 } as RawOrderLine, { percent: 50, discountedQuantity: 4 });
    expect(line.lineDiscountTotal).toBe(40000);
    const smaller = setLineQuantity(line, 2);
    expect(smaller.discountedQuantity).toBe(2);
    expect(smaller.lineDiscountTotal).toBe(20000);
    const bigger = setLineQuantity(smaller, 6);
    expect(bigger.discountedQuantity).toBe(2);
    expect(bigger.lineDiscountTotal).toBe(20000);
  });

  it("Dữ liệu cũ: discountAmount là giảm CẢ DÒNG, không nhân quantity", () => {
    const legacy = { price: 30000, quantity: 3, discountAmount: 10000 } as RawOrderLine;
    expect(lineDiscountTotal(legacy)).toBe(10000);
    expect(lineDiscountedQuantity(legacy)).toBe(3);
    expect(lineDiscountLabel(legacy, fmt)).toBe("Giảm 10000đ");
    expect(summarizeOrderLines([legacy]).itemDiscounts).toBe(10000);
    // lineDiscountTotal được ưu tiên hơn discountAmount
    expect(lineDiscountTotal({ price: 30000, quantity: 3, discountAmount: 1, lineDiscountTotal: 6000 } as RawOrderLine)).toBe(6000);
  });
});

function bill(id: string, items: RawOrderLine[], extra: Partial<HistoryOrder> = {}): HistoryOrder {
  const { subTotal, itemDiscounts } = summarizeOrderLines(items);
  return {
    id,
    billCode: id,
    status: "PAID",
    subTotal,
    totalDiscount: itemDiscounts,
    finalAmount: subTotal - itemDiscounts,
    timestamp: 1791077700000,
    staffUsername: "thungan",
    items: items as unknown as HistoryOrder["items"],
    ...extra,
  } as HistoryOrder;
}

describe("Báo cáo dùng lineDiscountTotal / legacy fallback (REPORT_SPEC §2.2)", () => {
  const newLine = applyLineDiscount(
    { productId: 1, name: "Cà phê", category: "Cà phê", price: 20000, quantity: 5, orderedBy: "pv1" } as RawOrderLine,
    { percent: 10, discountedQuantity: 2 }
  ); // 4000
  const legacyLine = { productId: 2, name: "Trà đào", category: "Trà", price: 30000, quantity: 3, discountAmount: 10000, orderedBy: "pv1" } as RawOrderLine;
  // Bill không có itemDiscounts cấp hóa đơn → báo cáo phải cộng từ dòng
  const b1 = bill("B1", [newLine, legacyLine]);

  it("itemLineDiscount", () => {
    expect(itemLineDiscount(newLine as never)).toBe(4000);
    expect(itemLineDiscount(legacyLine as never)).toBe(10000);
  });

  it("Tổng quan, danh mục, món, nhân viên, khuyến mãi đều khớp", () => {
    expect(calculateOverviewReport([b1]).itemDiscounts).toBe(14000);

    const cats = calculateCategoryReport([b1]);
    expect(cats.find((c) => c.category === "Trà")!.itemDiscount).toBe(10000);
    expect(cats.find((c) => c.category === "Cà phê")!.itemDiscount).toBe(4000);

    const prods = calculateProductReport([b1]);
    expect(prods.find((p) => p.productId === 2)!.netRevenue).toBe(80000);
    expect(prods.find((p) => p.productId === 1)!.netRevenue).toBe(96000);

    const staff = calculateStaffPerformance([b1]);
    expect(staff.orderStaff.find((s) => s.staffUsername === "pv1")!.netRevenue).toBe(190000 - 14000);

    const promo = calculatePromotionsReport([b1]);
    expect(promo.itemDiscounts.discountAmount).toBe(14000);
    expect(promo.itemDiscounts.appliedCount).toBe(2);
    const cafe = promo.itemDiscounts.details.find((d) => String(d.productId) === "1")!;
    expect(cafe.quantity).toBe(2); // chỉ số phần được giảm
    expect(cafe.discountAmount).toBe(4000);
  });
});
