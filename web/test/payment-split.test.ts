import { describe, it, expect } from "vitest";
import { billPaymentPortions, isMixedPayment, calculatePaymentMethodsReport, generateEndOfDayZReport, type HistoryOrder } from "../lib/reports";

const bill = (o: Partial<HistoryOrder>): HistoryOrder => ({ id: String(Math.random()), status: "PAID", subTotal: o.finalAmount, ...o }) as HistoryOrder;

describe("Hóa đơn thanh toán hỗn hợp (tiền mặt + QR)", () => {
  const bills = [
    bill({ id: "a", finalAmount: 100000, paymentMethod: "CASH" }),
    bill({ id: "b", finalAmount: 200000, paymentMethod: "TRANSFER_QR" }),
    bill({ id: "c", finalAmount: 405000, paymentMethod: "SPLIT", paymentSplits: [{ method: "CASH", amount: 185000 }, { method: "TRANSFER_QR", amount: 220000 }] }),
  ];
  it("chia đúng theo paymentSplits", () => {
    expect(billPaymentPortions(bills[2])).toEqual({ CASH: 185000, TRANSFER_QR: 220000, CARD: 0 });
  });
  it("nhận diện hóa đơn hỗn hợp (kể cả paymentSplits dạng object của RTDB)", () => {
    expect(bills.map(isMixedPayment)).toEqual([false, false, true]);
    const obj = bill({ finalAmount: 50000, paymentMethod: "SPLIT", paymentSplits: { 0: { method: "CASH", amount: 20000 }, 1: { method: "TRANSFER_QR", amount: 30000 } } as never });
    expect(billPaymentPortions(obj)).toEqual({ CASH: 20000, TRANSFER_QR: 30000, CARD: 0 });
  });
  it("tiền mặt + QR = tổng thực thu", () => {
    const r = calculatePaymentMethodsReport(bills);
    expect(r.CASH.finalAmount).toBe(285000);
    expect(r.TRANSFER_QR.finalAmount).toBe(420000);
    const z = generateEndOfDayZReport(bills, [], [], {}, {});
    expect(z.tab2_thuChi.cashSales + z.tab2_thuChi.transferSales).toBe(705000);
  });
});
