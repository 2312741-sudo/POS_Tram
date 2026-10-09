import { describe, it, expect } from "vitest";
import {
  CLEARED_TABLE_FIELDS,
  buildMergePayloads,
  buildTableOpUpdates,
  buildTransferPayloads,
  mergeOrderLines,
  orderLineKey,
  tableChanged,
  validateMerge,
  validateTransfer,
  type TableNode,
} from "../lib/table-ops";
import { applyLineDiscount, summarizeOrderLines, type RawOrderLine } from "../lib/order-math";

const base: RawOrderLine = { productId: 1, name: "Bạc xỉu", price: 30000, quantity: 1, note: "", isSentKitchen: true };

describe("orderLineKey (port OrderLineMerger.lineKey)", () => {
  it("cùng cấu hình → cùng khóa (topping không phân biệt thứ tự, ghi chú trim, số dạng chuỗi)", () => {
    const a = { ...base, selectedToppings: ["Trân châu", "Thạch"], note: " ít ngọt " };
    const b = { ...base, price: "30000", selectedToppings: ["Thạch", "Trân châu"], note: "ít ngọt", quantity: 5 };
    expect(orderLineKey(a)).toBe(orderLineKey(b));
  });

  it("khác size / đường / đá / ghi chú / giá / gửi bếp → khác khóa", () => {
    const k = orderLineKey(base);
    expect(orderLineKey({ ...base, selectedSize: "L" })).not.toBe(k);
    expect(orderLineKey({ ...base, selectedSugar: "50%" })).not.toBe(k);
    expect(orderLineKey({ ...base, selectedIce: "Ít đá" })).not.toBe(k);
    expect(orderLineKey({ ...base, note: "nóng" })).not.toBe(k);
    expect(orderLineKey({ ...base, price: 35000 })).not.toBe(k);
    expect(orderLineKey({ ...base, isSentKitchen: false })).not.toBe(k);
    expect(orderLineKey({ ...base, productId: 2 })).not.toBe(k);
  });

  it("cấu hình giảm giá dòng là một phần của khóa", () => {
    const k = orderLineKey(base);
    const p10 = applyLineDiscount(base, { percent: 10, discountedQuantity: 1 });
    expect(orderLineKey(p10)).not.toBe(k);
    expect(orderLineKey(applyLineDiscount(base, { percent: 20, discountedQuantity: 1 }))).not.toBe(orderLineKey(p10));
    expect(orderLineKey(applyLineDiscount(base, { unitAmount: 3000, discountedQuantity: 1 }))).not.toBe(orderLineKey(p10));
    expect(orderLineKey({ ...p10, discountReason: "Khách quen" })).not.toBe(orderLineKey(p10));
    // Dữ liệu cũ: số tiền cố định cả dòng → chế độ FIXED
    expect(orderLineKey({ ...base, discountAmount: 5000 })).not.toBe(k);
    // Số phần được giảm khác nhau KHÔNG làm khác khóa (giống Flutter)
    const p10q2 = applyLineDiscount({ ...base, quantity: 3 }, { percent: 10, discountedQuantity: 2 });
    expect(orderLineKey(p10q2)).toBe(orderLineKey(p10));
  });

  it("dùng id khi thiếu productId (giống Flutter fromMap)", () => {
    const { productId: _omit, ...noPid } = base;
    void _omit;
    expect(orderLineKey({ ...noPid, id: 1 })).toBe(orderLineKey(base));
  });
});

describe("mergeOrderLines (port OrderLineMerger.merge)", () => {
  it("cộng dồn dòng giống hệt, giữ riêng dòng khác cấu hình, không sửa đầu vào", () => {
    const target = [{ ...base, quantity: 2 }, { ...base, productId: 9, name: "Trà" }];
    const source = [{ ...base, quantity: 3 }, { ...base, selectedSize: "L" }];
    const snapshot = JSON.stringify([target, source]);
    const out = mergeOrderLines(target, source);
    expect(JSON.stringify([target, source])).toBe(snapshot);
    expect(out).toHaveLength(3);
    expect(out[0].quantity).toBe(5);
    expect(out[2].selectedSize).toBe("L");
  });

  it("dòng có giảm giá: cộng số phần được giảm và tổng giảm đã lưu — tổng tiền bảo toàn", () => {
    const t = applyLineDiscount({ ...base, quantity: 2 }, { percent: 10, discountedQuantity: 1 });
    const s = applyLineDiscount({ ...base, quantity: 3 }, { percent: 10, discountedQuantity: 3 });
    const out = mergeOrderLines([t], [s]);
    expect(out).toHaveLength(1);
    expect(out[0]).toMatchObject({ quantity: 5, discountedQuantity: 4, lineDiscountTotal: 12000, discountAmount: 12000 });
    const before = summarizeOrderLines([t, s]);
    const after = summarizeOrderLines(out);
    expect(after).toEqual(before);
  });

  it("giảm giá khác nhau → không gộp", () => {
    const t = applyLineDiscount(base, { percent: 10, discountedQuantity: 1 });
    expect(mergeOrderLines([t], [base])).toHaveLength(2);
  });

  it("các dòng trùng trong source cũng gộp với nhau", () => {
    const out = mergeOrderLines([], [{ ...base }, { ...base, quantity: 2 }]);
    expect(out).toEqual([{ ...base, quantity: 3 }]);
  });
});

const actor = { username: "ql1", fullName: "Quản lý Lan", roleId: "ROLE_MANAGER_1" };
const now = 1_760_000_000_000;

const src: TableNode = {
  name: "A1",
  zone: "Khu A",
  inUse: true,
  currentOrderJson: JSON.stringify([{ ...base, quantity: 2 }]),
  openedAt: 1_759_999_000_000,
  guestCount: 3,
  currentBillId: "HD-1",
  currentOrderCode: "OD-1",
  actionLogsJson: JSON.stringify([{ action: "OPEN", details: "x", timestamp: 1 }]),
  prePrintedAt: 1_759_999_900_000,
  prePrintedBy: "thungan",
};
const empty: TableNode = { name: "B2", zone: "Khu B", inUse: false, currentOrderJson: "", capacity: 4 };

describe("buildTransferPayloads", () => {
  it("đơn + bill + mã đơn + khách + giờ mở + nhật ký + tạm tính đi theo sang bàn đích; bàn nguồn được dọn", () => {
    const p = buildTransferPayloads({ source: src, target: empty, actor, now, storeCode: "TRAM01" });
    expect(p.targetFields).toMatchObject({
      inUse: true,
      currentOrderJson: src.currentOrderJson,
      openedAt: src.openedAt,
      guestCount: 3,
      currentBillId: "HD-1",
      currentOrderCode: "OD-1",
      mergedIntoTable: null,
      prePrintedAt: src.prePrintedAt,
      prePrintedBy: "thungan",
    });
    const logs = JSON.parse(String(p.targetFields.actionLogsJson));
    expect(logs).toHaveLength(2);
    expect(logs[1]).toMatchObject({ action: "TRANSFER_TABLE", staffUsername: "ql1", timestamp: now });
    expect(p.sourceFields).toEqual(CLEARED_TABLE_FIELDS);
    expect(p.targetFields).not.toHaveProperty("capacity");
    expect(p.audit).toMatchObject({ action: "TRANSFER_TABLE", targetType: "TABLE", targetId: "A1 -> B2", username: "ql1", timestamp: now });
  });

  it("bàn nguồn chưa in tạm tính → bàn đích không có prePrintedAt", () => {
    const p = buildTransferPayloads({ source: { ...src, prePrintedAt: null }, target: empty, actor, now, storeCode: "S" });
    expect(p.targetFields.prePrintedAt).toBeNull();
    expect(p.targetFields.prePrintedBy).toBeNull();
  });
});

describe("buildMergePayloads", () => {
  const target: TableNode = {
    name: "C3",
    zone: "Khu C",
    inUse: true,
    currentOrderJson: JSON.stringify([{ ...base, quantity: 1 }, { ...base, productId: 7, name: "Trà đào" }]),
    openedAt: new Date(1_759_999_500_000).toISOString(),
    guestCount: 2,
    currentBillId: "HD-2",
    actionLogsJson: null,
    prePrintedAt: 1_759_999_950_000,
    prePrintedBy: "x",
  };

  it("gộp món, cộng khách, giờ mở sớm nhất, xóa tạm tính bàn đích, bàn nguồn trống + mergedIntoTable", () => {
    const p = buildMergePayloads({ source: src, target, actor, now, storeCode: "TRAM01" });
    const items = JSON.parse(String(p.targetFields.currentOrderJson));
    expect(items).toHaveLength(2);
    expect(items[0].quantity).toBe(3);
    expect(p.targetFields).toMatchObject({ inUse: true, guestCount: 5, openedAt: src.openedAt, prePrintedAt: null, prePrintedBy: null });
    // Giữ bill của bàn đích
    expect(p.targetFields).not.toHaveProperty("currentBillId");
    expect(JSON.parse(String(p.targetFields.actionLogsJson))).toEqual([
      expect.objectContaining({ action: "MERGE_TABLE", details: expect.stringContaining("Gộp A1 vào C3") }),
    ]);
    expect(p.sourceFields).toEqual({ ...CLEARED_TABLE_FIELDS, mergedIntoTable: "C3" });
    expect(p.sourceFields.prePrintedAt).toBeNull();
    expect(p.audit).toMatchObject({ action: "MERGE_TABLE", targetId: "A1 -> C3" });
  });

  it("giờ mở bàn đích sớm hơn → giữ nguyên; không bên nào có → hiện tại; không khách → null", () => {
    const p1 = buildMergePayloads({ source: { ...src, openedAt: 1_759_999_999_000 }, target, actor, now, storeCode: "S" });
    expect(p1.targetFields.openedAt).toBe(target.openedAt);
    const p2 = buildMergePayloads({
      source: { ...src, openedAt: null, guestCount: 0 },
      target: { ...target, openedAt: null, guestCount: null },
      actor,
      now,
      storeCode: "S",
    });
    expect(p2.targetFields.openedAt).toBe(now);
    expect(p2.targetFields.guestCount).toBeNull();
  });
});

describe("validate / tableChanged / buildTableOpUpdates", () => {
  it("điều kiện chuyển / gộp", () => {
    expect(validateTransfer(src, empty)).toBeNull();
    expect(validateTransfer(src, { ...empty, isReserved: true })).toMatch(/đặt trước/);
    expect(validateTransfer(src, { ...empty, inUse: true })).toMatch(/Gộp bàn/);
    expect(validateTransfer({ ...src, inUse: false }, empty)).toMatch(/không còn khách/);
    expect(validateTransfer(src, src)).toMatch(/trùng/);
    expect(validateTransfer(src, null)).toMatch(/Không tìm thấy/);
    expect(validateMerge(src, { ...empty, inUse: true })).toBeNull();
    expect(validateMerge(src, empty)).toMatch(/Chuyển bàn/);
  });

  it("phát hiện bàn đổi trên thiết bị khác", () => {
    expect(tableChanged(src, { ...src })).toBe(false);
    expect(tableChanged(src, { ...src, currentOrderJson: JSON.stringify([{ ...base, quantity: 3 }]) })).toBe(true);
    expect(tableChanged(src, { ...src, prePrintedAt: null })).toBe(true);
    expect(tableChanged(empty, { ...empty, inUse: true })).toBe(true);
    expect(tableChanged(empty, { ...empty, isReserved: true })).toBe(true);
    expect(tableChanged(src, null)).toBe(true);
    // Chỉ khác định dạng JSON (khoảng trắng) → không coi là đổi
    expect(tableChanged(src, { ...src, currentOrderJson: JSON.stringify(JSON.parse(String(src.currentOrderJson)), null, 2) })).toBe(false);
  });

  it("một update đa đường dẫn: mọi khóa của 2 bàn + audit log", () => {
    const payloads = buildTransferPayloads({ source: src, target: empty, actor, now, storeCode: "TRAM01" });
    const u = buildTableOpUpdates({ storeCode: "TRAM01", sourceKeys: ["k1", "Khu A_A1"], targetKeys: ["Khu B_B2"], payloads, logId: "log_1" });
    expect(u["stores/TRAM01/tables/k1/inUse"]).toBe(false);
    expect(u["stores/TRAM01/tables/Khu A_A1/currentOrderJson"]).toBe("");
    expect(u["stores/TRAM01/tables/Khu B_B2/inUse"]).toBe(true);
    expect(u["stores/TRAM01/audit_logs/log_1"]).toBe(payloads.audit);
    expect(() => buildTableOpUpdates({ storeCode: "S", sourceKeys: ["a"], targetKeys: ["a"], payloads, logId: "l" })).toThrow();
  });
});
