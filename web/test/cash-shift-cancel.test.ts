import { describe, it, expect } from "vitest";
import { applyShiftDelta, billShiftPortions, expectedCash, findBillShift } from "../lib/cash-shift";

const shifts = [
  { id: "S_NV", shiftCode: "CA-NV", staffUid: "nv", staffUsername: "nv1", status: "OPEN", openedAt: 1000, initialCash: 0, totalCashSales: 50000, totalQrSales: 0, totalCardSales: 0, cashIn: 0, cashOut: 0 },
  { id: "S_QL", shiftCode: "CA-QL", staffUid: "ql", staffUsername: "ql1", status: "OPEN", openedAt: 1500, initialCash: 0, totalCashSales: 0, totalQrSales: 0, totalCardSales: 0, cashIn: 0, cashOut: 0 },
  { id: "S_OLD", shiftCode: "CA-OLD", staffUid: "nv", staffUsername: "nv1", status: "CLOSED", openedAt: 100, closedAt: 900 },
];

describe("hủy hóa đơn → trừ ở ca đã thu tiền", () => {
  it("thu TM 50k, Quản lý hủy đơn TM 30k của nhân viên → ca nhân viên còn 20k, ca quản lý không đổi", () => {
    const bill = { shiftId: "S_NV", paymentMethod: "CASH", finalAmount: 30000, staffUid: "nv", staffUsername: "nv1" };
    const target = findBillShift(bill, shifts)!;
    expect(target.id).toBe("S_NV");
    const p = billShiftPortions(bill);
    const after = applyShiftDelta(target, { cash: -p.cash, qr: -p.qr, card: -p.card }) as typeof target;
    expect(after.totalCashSales).toBe(20000);
    expect(expectedCash(after)).toBe(20000);
  });

  it("đơn hỗn hợp: chỉ trừ phần tiền mặt khỏi tiền mặt, phần CK khỏi CK", () => {
    expect(billShiftPortions({ paymentMethod: "SPLIT", finalAmount: 30000, paymentSplits: [{ method: "CASH", amount: 10000 }, { method: "TRANSFER_QR", amount: 20000 }] }))
      .toEqual({ cash: 10000, qr: 20000, card: 0 });
    expect(billShiftPortions({ paymentMethod: "TRANSFER_QR", finalAmount: 30000 })).toEqual({ cash: 0, qr: 30000, card: 0 });
    expect(billShiftPortions({ paymentMethod: "SPLIT", finalAmount: 30000 })).toEqual({ cash: 0, qr: 0, card: 0 });
  });

  it("hóa đơn không ghi ca (web / bản cũ): ca của người thu tiền bao trùm giờ thanh toán", () => {
    expect(findBillShift({ staffUid: "nv", closedAt: 2000 }, shifts)?.id).toBe("S_NV");
    expect(findBillShift({ staffUsername: "NV1", closedAt: 500 }, shifts)?.id).toBe("S_OLD");
    expect(findBillShift({ staffUid: "nv", closedAt: 950 }, shifts)).toBeNull();
  });

  it("ca đã chốt: không sửa (giao dịch bị hủy)", () => {
    expect(applyShiftDelta(shifts[2], { cash: -30000 })).toBeUndefined();
  });
});
