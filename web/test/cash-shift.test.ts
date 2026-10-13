import { describe, it, expect } from "vitest";
import { applyShiftDelta, buildCloseShift, buildOpenShift, expectedCash, findOwnOpenShift, paymentKindOf, shiftCodeFor, totalRevenue } from "../lib/cash-shift";

const actor = { uid: "u1", username: "nv1", fullName: "Nhân viên 1", role: "ROLE_STAFF" };
const open = { id: "S1", shiftCode: "CA-1", storeCode: "T1", staffUid: "u1", staffUsername: "nv1", status: "OPEN", openedAt: 100, initialCash: 500000, totalCashSales: 200000, totalQrSales: 50000, totalCardSales: 0, cashIn: 10000, cashOut: 30000 };

describe("ca / két trên web", () => {
  it("mã ca theo giờ Việt Nam", () => {
    expect(shiftCodeFor(Date.UTC(2026, 0, 2, 17, 30, 5))).toBe("CA-260103-003005");
  });

  it("tìm ca đang mở của chính mình (không lấy ca người khác / ca đã chốt)", () => {
    const list = [open, { ...open, id: "S2", staffUid: "u2", staffUsername: "nv2" }, { ...open, id: "S3", status: "CLOSED", closedAt: 5 }];
    expect(findOwnOpenShift(list, { uid: "u1", username: "nv1" }, "T1")?.id).toBe("S1");
    expect(findOwnOpenShift(list, { uid: "u9", username: "x" }, "T1")).toBeNull();
    // ca cũ không có staffUid → nhận theo username
    expect(findOwnOpenShift([{ ...open, staffUid: undefined }], { uid: "u7", username: "NV1" })?.id).toBe("S1");
  });

  it("tiền kỳ vọng và tổng doanh thu", () => {
    expect(expectedCash(open)).toBe(500000 + 200000 + 10000 - 30000);
    expect(totalRevenue(open)).toBe(250000);
  });

  it("mở ca: ghi đúng node (staffUid = người mở), từ chối tiền sai hoặc khi còn ca treo", () => {
    const r = buildOpenShift({ storeCode: "T1", actor, initialCash: 300000, existing: [], now: 1_000_000 });
    if ("error" in r) throw new Error(r.error);
    const node = r.updates[`stores/T1/cash_shifts/${r.shiftId}`] as Record<string, unknown>;
    expect(node).toMatchObject({ staffUid: "u1", staffUsername: "nv1", status: "OPEN", initialCash: 300000, totalCashSales: 0, storeCode: "T1" });
    expect(node.closedAt).toBeUndefined();
    expect(Object.values(r.updates).some((v) => (v as { action?: string }).action === "OPEN_SHIFT")).toBe(true);
    expect(buildOpenShift({ storeCode: "T1", actor, initialCash: -1, existing: [], now: 1 })).toHaveProperty("error");
    expect(buildOpenShift({ storeCode: "T1", actor, initialCash: 1.5, existing: [], now: 1 })).toHaveProperty("error");
    expect(buildOpenShift({ storeCode: "T1", actor, initialCash: 0, existing: [open], now: 1 })).toHaveProperty("error");
    expect(buildOpenShift({ storeCode: "T1", actor: { ...actor, uid: "" }, initialCash: 0, existing: [], now: 1 })).toHaveProperty("error");
  });

  it("chốt ca: chỉ ghi trường chốt, tính chênh lệch; người khác bị chặn trừ khi có quyền đóng bắt buộc", () => {
    const r = buildCloseShift({ storeCode: "T1", actor, shift: open, actualCash: 690000, notes: " thiếu 10k ", now: 9 });
    if ("error" in r) throw new Error(r.error);
    expect(r.updates["stores/T1/cash_shifts/S1/status"]).toBe("CLOSED");
    expect(r.updates["stores/T1/cash_shifts/S1/closedAt"]).toBe(9);
    expect(r.updates["stores/T1/cash_shifts/S1/difference"]).toBe(690000 - 680000);
    expect(r.updates["stores/T1/cash_shifts/S1/notes"]).toBe("thiếu 10k");
    expect(Object.keys(r.updates).some((k) => k.endsWith("/totalCashSales"))).toBe(false);

    const other = { ...actor, uid: "u2", username: "nv2" };
    expect(buildCloseShift({ storeCode: "T1", actor: other, shift: open, actualCash: 1, notes: "", now: 9 })).toHaveProperty("error");
    const forced = buildCloseShift({ storeCode: "T1", actor: other, shift: open, actualCash: 1, notes: "", canForceClose: true, now: 9 });
    if ("error" in forced) throw new Error(forced.error);
    expect(forced.updates["stores/T1/cash_shifts/S1/forceClosedByUid"]).toBe("u2");
    expect(buildCloseShift({ storeCode: "T1", actor, shift: { ...open, status: "CLOSED", closedAt: 5 }, actualCash: 1, notes: "", now: 9 })).toHaveProperty("error");
    expect(buildCloseShift({ storeCode: "T1", actor, shift: open, actualCash: -5, notes: "", now: 9 })).toHaveProperty("error");
  });

  it("phân loại phương thức thanh toán và cộng dồn doanh số an toàn", () => {
    expect(paymentKindOf("CASH")).toBe("CASH");
    expect(paymentKindOf("TRANSFER_QR")).toBe("QR");
    expect(paymentKindOf("Thẻ")).toBe("CARD");
    const next = applyShiftDelta({ ...open }, { cash: 1000, qr: 500 }) as Record<string, number>;
    expect(next.totalCashSales).toBe(201000);
    expect(next.totalQrSales).toBe(50500);
    expect((applyShiftDelta({ ...open }, { cash: -999999999 }) as Record<string, number>).totalCashSales).toBe(0);
    expect(applyShiftDelta({ ...open, status: "CLOSED" }, { cash: 1 })).toBeUndefined();
    expect(applyShiftDelta(null, { cash: 1 })).toBeNull();
  });
});
