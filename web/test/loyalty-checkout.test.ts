import { describe, it, expect } from "vitest";
import {
  buildPointsPreview,
  clampPointsInput,
  computeBillAmounts,
  computeEarnPoints,
  loyaltyBillFields,
  maxRedeemablePoints,
  minBillForOnePoint,
  rankPickerCustomers,
  resolveRates,
  tableCustomerPayload,
  toPickerCustomers,
  type PickerCustomer,
} from "../lib/loyalty-checkout";
import { parseStoreCustomers } from "../lib/customers";
import { buildOrderReceiptHtml, buildTableBillHtml } from "../lib/print-html";

const tiers = [
  { name: "Thành viên", minPoints: 0 },
  { name: "Bạc", minPoints: 100 },
];

describe("công thức điểm (khớp máy chủ)", () => {
  it("làm tròn như computeEarnPoints", () => {
    expect(computeEarnPoints(100_000, 1, 1000)).toBe(1);
    expect(computeEarnPoints(150_000, 2, 1000)).toBe(3);
    expect(computeEarnPoints(49_999, 1, 1000)).toBe(0); // 0.49999 → 0
    expect(computeEarnPoints(50_000, 1, 1000)).toBe(1); // 0.5 → làm tròn lên
  });
  it("không tích khi tiền/tỷ lệ không hợp lệ", () => {
    expect(computeEarnPoints(0, 1, 1000)).toBe(0);
    expect(computeEarnPoints(100_000, 0, 1000)).toBe(0);
    expect(computeEarnPoints(100_000, 1, 0)).toBe(0);
    expect(computeEarnPoints(-5, 1, 1000)).toBe(0);
  });
  it("hóa đơn tối thiểu để có 1 điểm", () => {
    expect(minBillForOnePoint(1, 1000)).toBe(50_000);
    expect(computeEarnPoints(49_999, 1, 1000)).toBe(0);
    expect(minBillForOnePoint(2, 1000)).toBe(25_000);
    expect(minBillForOnePoint(0, 1000)).toBeNull();
    const m = minBillForOnePoint(3, 700)!;
    expect(computeEarnPoints(m, 3, 700)).toBeGreaterThanOrEqual(1);
    expect(computeEarnPoints(m - 1, 3, 700)).toBe(0);
  });
  it("tỷ lệ: chuỗi > chi nhánh > mặc định", () => {
    expect(resolveRates({ pointEarnRate: 2, pointRedeemRate: 500 }, { pointEarnRate: 5, pointRedeemRate: 900 })).toEqual({ earnRate: 2, redeemRate: 500, source: "chain" });
    expect(resolveRates({}, { pointEarnRate: 5, pointRedeemRate: 900 })).toEqual({ earnRate: 5, redeemRate: 900, source: "store" });
    expect(resolveRates({}, {})).toEqual({ earnRate: 1, redeemRate: 1000, source: "default" });
    expect(resolveRates({ pointEarnRate: 0 }, { pointEarnRate: 5 }).earnRate).toBe(0); // chuỗi đặt 0% là có chủ đích
    expect(resolveRates({ pointRedeemRate: 0 }, { pointRedeemRate: 800 }).redeemRate).toBe(800);
  });
});

describe("xem trước điểm", () => {
  const rates = { earnRate: 1, redeemRate: 1000 };
  it("tích + số dư sau + lên hạng", () => {
    const p = buildPointsPreview({ balance: 95, totalPoints: 95, payable: 200_000, pointsUsed: 0, rates, tiers });
    expect(p).toMatchObject({ earn: 2, before: 95, after: 97, tierBefore: "Thành viên", tierAfter: "Thành viên", minBillForPoint: null });
    const up = buildPointsPreview({ balance: 99, totalPoints: 99, payable: 100_000, pointsUsed: 0, rates, tiers });
    expect(up.tierAfter).toBe("Bạc");
  });
  it("dùng điểm giảm tiền thực trả nhưng không đổi tổng điểm tích lũy", () => {
    const p = buildPointsPreview({ balance: 50, totalPoints: 80, payable: 100_000 - 20 * 1000, pointsUsed: 20, rates, tiers });
    expect(p.earn).toBe(2 - 1 + 0); // 80.000đ → 0.8 → 1
    expect(p.after).toBe(50 - 20 + 1);
  });
  it("bằng 0 điểm → gợi ý hóa đơn tối thiểu; tỷ lệ 0 → không gợi ý", () => {
    expect(buildPointsPreview({ balance: 0, totalPoints: 0, payable: 20_000, pointsUsed: 0, rates, tiers })).toMatchObject({ earn: 0, minBillForPoint: 50_000, after: 0 });
    expect(buildPointsPreview({ balance: 0, totalPoints: 0, payable: 20_000, pointsUsed: 0, rates: { earnRate: 0, redeemRate: 1000 }, tiers }).minBillForPoint).toBeNull();
  });
  it("không dùng quá số dư", () => {
    expect(buildPointsPreview({ balance: 5, totalPoints: 5, payable: 0, pointsUsed: 99, rates, tiers }).used).toBe(5);
  });
});

describe("giới hạn dùng điểm", () => {
  it("min(số dư, điểm phủ phần tiền còn lại)", () => {
    expect(maxRedeemablePoints(10, 100_000, 1000)).toBe(10);
    expect(maxRedeemablePoints(500, 100_000, 1000)).toBe(100);
    expect(maxRedeemablePoints(500, 99_999, 1000)).toBe(99);
    expect(maxRedeemablePoints(0, 100_000, 1000)).toBe(0);
    expect(maxRedeemablePoints(50, 0, 1000)).toBe(0);
    expect(maxRedeemablePoints(50, 10_000, 0)).toBe(0);
  });
  it("nhập số điểm: chỉ chữ số, kẹp tối đa", () => {
    expect(clampPointsInput("12abc", 100)).toBe(12);
    expect(clampPointsInput("999", 100)).toBe(100);
    expect(clampPointsInput("", 100)).toBe(0);
    expect(clampPointsInput("-5", 100)).toBe(5);
    expect(clampPointsInput("7", 0)).toBe(0);
  });
});

describe("số tiền + trường hóa đơn", () => {
  it("đổi điểm nằm trong totalDiscount như Flutter", () => {
    const a = computeBillAmounts({ subTotal: 200_000, itemDiscounts: 10_000, promoTotal: 20_000, pointsUsed: 30, redeemRate: 1000 });
    expect(a).toMatchObject({ pointsUsed: 30, pointsDiscount: 30_000, billDiscounts: 50_000, totalDiscount: 60_000, finalAmount: 140_000 });
  });
  it("không âm và không vượt tạm tính", () => {
    const a = computeBillAmounts({ subTotal: 50_000, itemDiscounts: 0, pointsUsed: 80, redeemRate: 1000 });
    expect(a.finalAmount).toBe(0);
    expect(a.totalDiscount).toBe(50_000);
  });
  it("không dùng điểm → không có discount điểm", () => {
    expect(computeBillAmounts({ subTotal: 100_000, itemDiscounts: 0 })).toMatchObject({ pointsUsed: 0, pointsDiscount: 0, finalAmount: 100_000 });
  });
  it("trường khách + điểm ghi vào hóa đơn", () => {
    expect(loyaltyBillFields({ id: "C1", name: "Lan", phone: "0901234567" }, { pointsUsed: 5, pointsDiscount: 5000 })).toEqual({
      customerId: "C1", customerName: "Lan", customerPhone: "0901234567", pointsUsed: 5, pointsDiscount: 5000,
    });
    expect(loyaltyBillFields({ id: "C1" }, { pointsUsed: 0, pointsDiscount: 0 })).toEqual({ customerId: "C1" });
    expect(loyaltyBillFields(undefined, { pointsUsed: 3, pointsDiscount: 3000 })).toEqual({});
  });
  it("payload ghi vào bàn", () => {
    expect(tableCustomerPayload({ id: "C1", name: "Lan", phone: "09" })).toEqual({ customerId: "C1", customerName: "Lan", customerPhone: "09" });
    expect(tableCustomerPayload(null)).toEqual({ customerId: null, customerName: null, customerPhone: null });
  });
});

describe("chọn khách: tìm + xếp hạng", () => {
  const mk = (id: string, name: string, phone: string, points: number, lastVisitAt = 0): PickerCustomer => ({ id, name, phone, points, totalPoints: points, lastVisitAt });
  const all = [
    mk("a", "Nguyễn Văn An", "0901234567", 10, 100),
    mk("b", "Trần Thị Bình", "0912345678", 500, 300),
    mk("c", "Lê Hoàng Cường", "0987654321", 50, 300),
    mk("d", "Phạm Minh Đức", "0971234567", 70),
  ];
  it("rỗng: gần đây trước, rồi nhiều điểm", () => {
    expect(rankPickerCustomers(all, "").map((m) => m.customer.id)).toEqual(["b", "c", "a", "d"]);
  });
  it("giới hạn 10", () => {
    const many = Array.from({ length: 30 }, (_, i) => mk(`x${i}`, `Khách ${i}`, `09000000${String(i).padStart(2, "0")}`, i));
    expect(rankPickerCustomers(many, "")).toHaveLength(10);
  });
  it("SĐT đủ / 4 số cuối / một phần", () => {
    expect(rankPickerCustomers(all, "0901234567")[0].customer.id).toBe("a");
    expect(rankPickerCustomers(all, "4321")[0].customer.id).toBe("c");
    expect(rankPickerCustomers(all, "1234").map((m) => m.customer.id)).toContain("a");
    expect(rankPickerCustomers(all, "12")).toHaveLength(0); // < 3 số không tìm
  });
  it("SĐT khớp cuối xếp trước khớp giữa", () => {
    const r = rankPickerCustomers(all, "4567").map((m) => m.customer.id);
    expect(r[0]).toBe("a"); // ...4567 kết thúc
    expect(r).toContain("d");
  });
  it("tên không dấu, thứ tự từ bất kỳ, có vị trí tô sáng", () => {
    const r = rankPickerCustomers(all, "cuong hoang");
    expect(r[0].customer.id).toBe("c");
    expect(r[0].nameRanges.length).toBeGreaterThan(0);
    expect(rankPickerCustomers(all, "binh tran")[0].customer.id).toBe("b");
  });
  it("chuyển từ khách RTDB: lastVisitAt lấy mốc mới nhất", () => {
    const list = parseStoreCustomers("S", { c1: { ho_ten: "Lan", so_dien_thoai: "0901234567", diem_hien_tai: 5, ngay_tao: 1000, lastVisitAt: 5000 }, c2: { ho_ten: "Mai", diem_hien_tai: 9, ngay_tao: 2000 } });
    const picks = toPickerCustomers(list);
    expect(picks.find((c) => c.id === "c1")?.lastVisitAt).toBe(5000);
    expect(rankPickerCustomers(picks, "")[0].customer.id).toBe("c1");
  });
});

describe("in phiếu: khách + điểm", () => {
  it("phiếu tạm tính có khách (che SĐT), điểm dùng và điểm sẽ tích", () => {
    const html = buildTableBillHtml({
      tableName: "A1", zone: "Khu A", items: [{ name: "Trà", price: 30000, quantity: 1 }], total: 25000,
      customer: { name: "Lan <b>", phone: "0901234567" }, pointsRedeemed: { points: 5, amount: 5000 }, pointsEarn: 1, printedAt: "now",
    });
    expect(html).toContain("Khách: Lan &lt;b&gt;");
    expect(html).toContain("090****567");
    expect(html).not.toContain("0901234567");
    expect(html).toContain("Dùng 5 điểm");
    expect(html).toContain("+1 điểm");
  });
  it("không khách thì không có dòng điểm", () => {
    const html = buildTableBillHtml({ tableName: "A1", zone: "Khu A", items: [], total: 0, printedAt: "now" });
    expect(html).not.toContain("điểm");
  });
  it("hóa đơn thanh toán có khách + điểm đã dùng", () => {
    const html = buildOrderReceiptHtml({ id: "b1", items: [], totalAmount: 1, customerName: "Lan", customerPhone: "0901234567", pointsUsed: 7, pointsDiscount: 7000 }, "t");
    expect(html).toContain("Khách: <strong>Lan</strong>");
    expect(html).toContain("Dùng 7 điểm");
  });
});
