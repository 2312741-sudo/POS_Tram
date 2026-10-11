import { describe, it, expect } from "vitest";
import { CLEARED_TABLE_FIELDS, buildMergePayloads, buildTransferPayloads, type TableNode } from "../lib/table-ops";
import { tableCustomerOf } from "../lib/table-status";

const actor = { username: "admin", fullName: "Admin" };
const item = JSON.stringify([{ productId: 1, name: "Bạc xỉu", price: 30000, quantity: 1 }]);
const mk = (name: string, extra: TableNode = {}): TableNode => ({ name, zone: "Khu A", inUse: true, currentOrderJson: item, openedAt: 1000, ...extra });
const cust = { customerId: "C1", customerName: "Lan", customerPhone: "0901" };

describe("khách gắn với bàn", () => {
  it("dọn bàn xóa khách", () => {
    expect(CLEARED_TABLE_FIELDS).toMatchObject({ customerId: null, customerName: null, customerPhone: null });
  });

  it("chuyển bàn: đích nhận khách, nguồn bị xóa", () => {
    const p = buildTransferPayloads({ source: mk("A1", cust), target: mk("A2", { inUse: false }), actor, now: 5, storeCode: "S" });
    expect(p.targetFields).toMatchObject(cust);
    expect(p.sourceFields).toMatchObject({ customerId: null });
  });

  it("chuyển bàn nguồn không khách: xóa khách sót ở đích", () => {
    const p = buildTransferPayloads({ source: mk("A1"), target: mk("A2", { inUse: false, ...cust }), actor, now: 5, storeCode: "S" });
    expect(p.targetFields).toMatchObject({ customerId: null, customerName: null, customerPhone: null });
  });

  it("gộp bàn: giữ khách đích", () => {
    const p = buildMergePayloads({ source: mk("A1", cust), target: mk("A2", { customerId: "D", customerName: "Đích" }), actor, now: 5, storeCode: "S" });
    expect("customerId" in p.targetFields).toBe(false);
    expect(p.sourceFields).toMatchObject({ customerId: null, mergedIntoTable: "A2" });
  });

  it("gộp bàn: đích chưa có khách thì lấy của nguồn", () => {
    const p = buildMergePayloads({ source: mk("A1", cust), target: mk("A2"), actor, now: 5, storeCode: "S" });
    expect(p.targetFields).toMatchObject(cust);
  });

  it("gộp bàn: cả hai không khách thì không ghi trường khách", () => {
    const p = buildMergePayloads({ source: mk("A1"), target: mk("A2"), actor, now: 5, storeCode: "S" });
    expect("customerId" in p.targetFields).toBe(false);
  });

  it("tableCustomerOf: rỗng nếu không có id, chỉ lấy trường có giá trị", () => {
    expect(tableCustomerOf({ customerName: "x" })).toEqual({});
    expect(tableCustomerOf({ customerId: "C1", customerName: " ", customerPhone: "09" })).toEqual({ customerId: "C1", customerPhone: "09" });
  });
});
