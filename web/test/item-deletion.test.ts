import { describe, it, expect } from "vitest";
import {
  DELETION_REASONS,
  appendDeletedItemsJson,
  applyLineRemoval,
  billDeletionFields,
  buildDeletionAuditLog,
  buildDeletionEntry,
  deletedAmountOf,
  deletionReportFromAuditLogs,
  deletionReportFromBills,
  mergeDeletedItemsJson,
  parseDeletedItems,
  reasonGroupOf,
  resolveDeletionReason,
  type DeletedItemEntry,
} from "../lib/item-deletion";
import { applyLineDiscount, setLineQuantity, type RawOrderLine } from "../lib/order-math";
import { buildMergePayloads, buildTransferPayloads, CLEARED_TABLE_FIELDS } from "../lib/table-ops";
import { billLevelDiscount, billItemDiscount, billStatusLabel, generateEndOfDayZReport, isRevenueBill, type HistoryOrder } from "../lib/reports";

const line: RawOrderLine = { productId: 7, name: "Trà đào", price: 30000, sizeExtraPrice: 5000, toppingPrice: 5000, quantity: 4 };
const actor = { staffUsername: "lan", staffFullName: "Lan" };

const entry = (over: Partial<DeletedItemEntry> = {}): DeletedItemEntry => ({
  name: "Trà đào",
  productId: 7,
  quantity: 1,
  unitPrice: 40000,
  amount: 40000,
  reason: "Nhập sai",
  staffUsername: "lan",
  staffFullName: "Lan",
  timestamp: 1000,
  sentToKitchen: false,
  ...over,
});

describe("lý do xóa món", () => {
  it("danh sách lý do đúng hợp đồng", () => {
    expect([...DELETION_REASONS]).toEqual(["Khách đổi món", "Khách hủy món", "Nhập sai", "Hết món/hết nguyên liệu", "Khác"]);
  });
  it("bắt buộc chọn; Khác bắt buộc nội dung", () => {
    expect(resolveDeletionReason("")).toHaveProperty("error");
    expect(resolveDeletionReason("Lý do lạ")).toHaveProperty("error");
    expect(resolveDeletionReason("Khác", "  ")).toHaveProperty("error");
    expect(resolveDeletionReason("Khác", " khách say ")).toEqual({ reason: "Khác: khách say" });
    expect(resolveDeletionReason("Nhập sai")).toEqual({ reason: "Nhập sai" });
  });
  it("nhóm lý do Khác: ... về Khác", () => {
    expect(reasonGroupOf("Khác: abc")).toBe("Khác");
    expect(reasonGroupOf("Nhập sai")).toBe("Nhập sai");
    expect(reasonGroupOf("")).toBe("Không rõ");
  });
});

describe("bản ghi xóa món", () => {
  it("unitPrice gồm size + topping; amount = gốc khi không giảm giá", () => {
    const e = buildDeletionEntry({ line, removeQty: 2, reason: "Nhập sai", ...actor, now: 5 });
    expect(e).toEqual({
      name: "Trà đào",
      productId: 7,
      quantity: 2,
      unitPrice: 40000,
      amount: 80000,
      reason: "Nhập sai",
      staffUsername: "lan",
      staffFullName: "Lan",
      timestamp: 5,
      sentToKitchen: false,
    });
  });
  it("amount trừ phần giảm giá dòng tương ứng", () => {
    const disc = applyLineDiscount(line, { percent: 10, discountedQuantity: 4 }); // giảm 16.000
    expect(deletedAmountOf(disc, 1)).toBe(36000);
    expect(deletedAmountOf(disc, 4)).toBe(144000);
  });
  it("chặn số lượng trong [1, quantity] và ghi sentToKitchen", () => {
    const e = buildDeletionEntry({ line: { ...line, isSentKitchen: true }, removeQty: 99, reason: "x", now: 1 });
    expect(e.quantity).toBe(4);
    expect(e.sentToKitchen).toBe(true);
    expect(e.staffUsername).toBe("admin_web");
  });
  it("applyLineRemoval: giảm số lượng hoặc bỏ hẳn dòng", () => {
    const items = [line, { ...line, productId: 8, name: "Cà phê", quantity: 1 }];
    const reduced = applyLineRemoval(items, 0, 1, setLineQuantity);
    expect(reduced[0].quantity).toBe(3);
    expect(applyLineRemoval(items, 0, 4, setLineQuantity)).toHaveLength(1);
    expect(applyLineRemoval(items, 1, 1, setLineQuantity).map((i) => i.name)).toEqual(["Trà đào"]);
  });
});

describe("deletedItemsJson + trường hóa đơn", () => {
  it("parse an toàn chuỗi / mảng / object / rác", () => {
    expect(parseDeletedItems("")).toEqual([]);
    expect(parseDeletedItems("{bad")).toEqual([]);
    expect(parseDeletedItems(null)).toEqual([]);
    expect(parseDeletedItems([entry()])).toHaveLength(1);
    expect(parseDeletedItems({ 0: entry(), 1: entry() })).toHaveLength(2);
  });
  it("nối và gộp", () => {
    const json = appendDeletedItemsJson(JSON.stringify([entry()]), [entry({ quantity: 2, amount: 80000 })]);
    expect(parseDeletedItems(json)).toHaveLength(2);
    expect(mergeDeletedItemsJson(null, "")).toBeNull();
    expect(parseDeletedItems(mergeDeletedItemsJson(json, JSON.stringify([entry()])))).toHaveLength(3);
  });
  it("billDeletionFields: count = tổng số phần, amount = tổng tiền", () => {
    const f = billDeletionFields([entry(), entry({ quantity: 2, amount: 70000 })]);
    expect(f.deletedItemsCount).toBe(3);
    expect(f.deletedItemsAmount).toBe(110000);
    expect(f.deletedItems).toHaveLength(2);
  });
  it("audit log DELETE_ITEM đúng hợp đồng", () => {
    const log = buildDeletionAuditLog({ entry: entry({ amount: 35000 }), tableName: "Bàn 3", orderCode: "HD-1", storeCode: "TRAM01", userRole: "staff" });
    expect(log).toMatchObject({
      action: "DELETE_ITEM",
      targetType: "ORDER_ITEM",
      username: "lan",
      userFullName: "Lan",
      userRole: "staff",
      timestamp: 1000,
      productName: "Trà đào",
      quantity: 1,
      amount: 35000,
      reason: "Nhập sai",
      tableName: "Bàn 3",
      orderCode: "HD-1",
    });
    expect(log.details).toBe("Xóa 1 x Trà đào (35.000đ) bàn Bàn 3 — Lý do: Nhập sai");
  });
});

describe("chuyển / gộp bàn mang theo deletedItemsJson", () => {
  const actorT = { username: "lan", fullName: "Lan" };
  it("chuyển: bàn đích nhận, bàn nguồn xóa", () => {
    const src = { name: "A1", zone: "Z", inUse: true, currentOrderJson: "[]", deletedItemsJson: JSON.stringify([entry()]) };
    const p = buildTransferPayloads({ source: src, target: { name: "A2", zone: "Z" }, actor: actorT, now: 1, storeCode: "S" });
    expect(p.targetFields.deletedItemsJson).toBe(src.deletedItemsJson);
    expect(p.sourceFields.deletedItemsJson).toBeNull();
    expect(CLEARED_TABLE_FIELDS.deletedItemsJson).toBeNull();
  });
  it("gộp: nối danh sách", () => {
    const p = buildMergePayloads({
      source: { name: "A1", inUse: true, currentOrderJson: "[]", deletedItemsJson: JSON.stringify([entry()]) },
      target: { name: "A2", inUse: true, currentOrderJson: "[]", deletedItemsJson: JSON.stringify([entry(), entry()]) },
      actor: actorT,
      now: 1,
      storeCode: "S",
    });
    expect(parseDeletedItems(p.targetFields.deletedItemsJson)).toHaveLength(3);
  });
});

const bill = (over: Partial<HistoryOrder>): HistoryOrder => ({ id: "b", status: "PAID", ...over });

describe("báo cáo xóa món", () => {
  const bills: HistoryOrder[] = [
    bill({ id: "1", tableName: "A1", billCode: "HD-1", deletedItems: [entry(), entry({ reason: "Khác: đổ", staffUsername: "minh", staffFullName: "Minh", amount: 20000 })] }),
    bill({ id: "2", status: "CANCELLED", deletedItemsJson: JSON.stringify([entry({ quantity: 2, amount: 80000 })]) }),
    bill({ id: "3", status: "REFUNDED", deletedItems: [entry()] }),
    bill({ id: "1", deletedItems: [entry()] }), // trùng id → bỏ qua
  ];
  it("từ hóa đơn PAID + CANCELLED, nhóm theo lý do / nhân viên", () => {
    const r = deletionReportFromBills(bills);
    expect(r.entries).toBe(3);
    expect(r.quantity).toBe(4);
    expect(r.amount).toBe(140000);
    expect(r.byReason.find((g) => g.key === "Nhập sai")).toMatchObject({ count: 2, quantity: 3, amount: 120000 });
    expect(r.byReason.find((g) => g.key === "Khác")).toMatchObject({ count: 1, amount: 20000 });
    expect(r.byStaff.find((g) => g.key === "minh")?.label).toBe("Minh");
    expect(r.rows[0].billCode).toBeTruthy();
  });
  it("từ audit log DELETE_ITEM", () => {
    const r = deletionReportFromAuditLogs([
      { action: "DELETE_ITEM", productName: "Trà", quantity: 2, amount: 50000, reason: "Nhập sai", tableName: "B1", username: "lan", userFullName: "Lan", timestamp: 3 },
      { action: "PAY_BILL", timestamp: 4 },
    ]);
    expect(r.entries).toBe(1);
    expect(r.rows[0]).toMatchObject({ name: "Trà", quantity: 2, amount: 50000, tableName: "B1" });
  });
  it("báo cáo cuối ngày: số món xóa, tiền xóa, đơn hủy", () => {
    const eod = generateEndOfDayZReport(
      [
        bill({ id: "p", subTotal: 100000, finalAmount: 100000, deletedItems: [entry()] }),
        bill({ id: "c", status: "CANCELLED", subTotal: 60000, finalAmount: 0, deletedItems: [entry({ quantity: 2, amount: 50000 })] }),
      ],
      [],
      [],
      {},
      { date: "x", storeCode: "S", storeName: "S" }
    );
    expect(eod.tab1_tongHop.deletedItemsCount).toBe(3);
    expect(eod.tab1_tongHop.deletedItemsAmount).toBe(90000);
    expect(eod.tab1_tongHop.cancelledBillsCount).toBe(1);
    expect(eod.tab1_tongHop.cancelledBillsAmount).toBe(60000);
    expect(eod.tab1_tongHop.netRevenue).toBe(100000);
  });
});

describe("trạng thái & giảm giá cấp đơn", () => {
  it("nhãn trạng thái", () => {
    expect(billStatusLabel("PAID")).toBe("Hoàn thành");
    expect(billStatusLabel(undefined)).toBe("Hoàn thành");
    expect(billStatusLabel("CANCELLED")).toBe("Đã hủy");
    expect(isRevenueBill(bill({ status: "CANCELLED" }))).toBe(false);
    expect(isRevenueBill(bill({}))).toBe(true);
  });
  it("giảm giá đơn = tổng giảm − giảm món", () => {
    expect(billLevelDiscount(bill({ totalDiscount: 30000, itemDiscounts: 10000 }))).toBe(20000);
    const items = [{ name: "A", price: 50000, quantity: 1, lineDiscountTotal: 5000 }];
    expect(billItemDiscount(bill({ items }))).toBe(5000);
    expect(billLevelDiscount(bill({ discountAmount: 15000, items }))).toBe(10000);
    expect(billLevelDiscount(bill({ totalDiscount: 0, items }))).toBe(0);
  });
});
