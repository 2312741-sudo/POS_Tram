import { describe, it, expect } from "vitest";
import { escapeHtml } from "../lib/html";
import { buildTableBillHtml, buildOrderReceiptHtml } from "../lib/print-html";
import { buildStandardReportHtml } from "../lib/export";

const XSS = `<img src=x onerror="alert('x')">&`;
const XSS_ESC = "&lt;img src=x onerror=&quot;alert(&#39;x&#39;)&quot;&gt;&amp;";

describe("escapeHtml", () => {
  it("escapes & < > \" '", () => {
    expect(escapeHtml(`&<>"'`)).toBe("&amp;&lt;&gt;&quot;&#39;");
    expect(escapeHtml(XSS)).toBe(XSS_ESC);
  });
  it("handles non-strings and nullish", () => {
    expect(escapeHtml(null)).toBe("");
    expect(escapeHtml(undefined)).toBe("");
    expect(escapeHtml(12)).toBe("12");
    expect(escapeHtml("Cà phê sữa đá")).toBe("Cà phê sữa đá");
  });
  it("escapes & first (no double-escape artifacts)", () => {
    expect(escapeHtml("&lt;")).toBe("&amp;lt;");
  });
});

describe("print HTML builders", () => {
  it("buildTableBillHtml escapes all DB strings", () => {
    const html = buildTableBillHtml({
      tableName: XSS,
      zone: XSS,
      items: [{ name: XSS, price: 25000, quantity: 2, selectedSize: XSS, selectedToppings: [{ name: XSS }, XSS] }],
      total: 50000,
      printedAt: "09/10/2026",
    });
    expect(html).not.toContain("<img");
    expect(html).toContain(XSS_ESC);
    expect(html).toContain(`<strong>${XSS_ESC}</strong>`);
    expect(html).toContain(new Intl.NumberFormat("vi-VN").format(50000) + " VNĐ");
    expect(html).toContain("window.print()");
  });

  it("buildOrderReceiptHtml escapes all DB strings", () => {
    const html = buildOrderReceiptHtml(
      {
        id: XSS,
        billCode: XSS,
        orderCode: "OC1",
        tableName: XSS,
        orderStaff: XSS,
        cashierName: XSS,
        paymentMethod: XSS,
        totalAmount: 30000,
        items: [{ name: XSS, price: 30000, quantity: 1, selectedSize: XSS, orderedByName: XSS }],
      },
      "09/10/2026 10:00"
    );
    expect(html).not.toContain("<img");
    expect(html).toContain(`<title>Hóa đơn ${XSS_ESC}</title>`);
    expect(html).toContain("Mã đơn: <strong>OC1</strong>");
    expect(html).toContain(`Phục vụ: ${XSS_ESC}`);
  });

  it("buildStandardReportHtml escapes headers, cells, store info", () => {
    const html = buildStandardReportHtml({
      reportCode: XSS,
      reportTitle: XSS,
      storeCode: "S1",
      storeName: "s",
      storeAddress: XSS,
      storePhone: XSS,
      dateRangeText: XSS,
      headers: [XSS, "B"],
      rows: [[1, XSS]],
      totalRow: [XSS, 1000],
    });
    expect(html).not.toContain("<img");
    expect(html).toContain(`<title>${XSS_ESC}</title>`);
    expect(html).toContain("<div class=\"store-name\">S</div>");
  });
});

describe("print builders — giảm giá theo phần", () => {
  const item = {
    name: "Cà phê A",
    price: 20000,
    quantity: 5,
    discountPercent: 10,
    discountedQuantity: 2,
    lineDiscountTotal: 4000,
    discountAmount: 4000,
  };

  it("phiếu tạm tính bàn trừ giảm giá dòng và ghi nhãn", () => {
    const html = buildTableBillHtml({ tableName: "B1", zone: "Khu A", items: [item], total: 96000, printedAt: "now" });
    expect(html).toContain("96.000đ");
    expect(html).not.toContain("100.000đ");
    expect(html).toContain("Giảm 10% × 2/5 món");
  });

  it("hóa đơn thanh toán trừ giảm giá dòng và ghi nhãn", () => {
    const html = buildOrderReceiptHtml({ id: "x", billCode: "HD-1", totalAmount: 96000, items: [item] }, "now");
    expect(html).toContain("Giảm 10% × 2/5 món");
    expect(html).not.toMatch(/100\.000/);
  });
});
