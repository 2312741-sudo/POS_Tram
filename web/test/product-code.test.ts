import { describe, it, expect } from "vitest";
import { resolveProductCode, buildProductCodeMap } from "../lib/product-code";
import { calculateProductReport, calculateGrossProfitReport } from "../lib/reports";

describe("resolveProductCode", () => {
  const map = buildProductCodeMap([{ id: "p1", name: "Trà đào", code: "TD01" }, { id: "p2", name: "Cà phê", productCode: "CF02" }]);
  it("ưu tiên mã hiện tại trong danh mục theo id", () => {
    expect(resolveProductCode({ productId: "p1", name: "x", productCode: "CU" }, map)).toBe("TD01");
  });
  it("id không khớp (danh mục nạp lại) thì tra theo tên", () => {
    expect(resolveProductCode({ productId: "cu-999", name: "Cà phê" }, map)).toBe("CF02");
  });
  it("không có trong danh mục thì dùng mã chụp trên dòng hóa đơn", () => {
    expect(resolveProductCode({ productId: 5, name: "Lạ", productCode: "OLD" }, map)).toBe("OLD");
    expect(resolveProductCode({ name: "Lạ" })).toBe("");
  });
});

describe("báo cáo có mã món", () => {
  const bills = [{ id: "b1", status: "PAID", timestamp: 1, totalAmount: 20000, items: [{ productId: "old-1", name: "Trà đào", price: 20000, quantity: 1 }] }] as never;
  const map = buildProductCodeMap([{ id: "p1", name: "Trà đào", code: "TD01" }]);
  it("hiệu suất món và lợi nhuận gộp đều có productCode", () => {
    expect(calculateProductReport(bills, map)[0].productCode).toBe("TD01");
    expect(calculateGrossProfitReport(bills, map).items[0].productCode).toBe("TD01");
  });
});
