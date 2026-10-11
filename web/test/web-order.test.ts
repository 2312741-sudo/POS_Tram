import { describe, it, expect } from "vitest";
import { addLineToOrder, buildWebOrderUpdates, generateOrderCode, makeOrderLine, productIdValue } from "../lib/web-order";
import { lineQuantity } from "../lib/order-math";

const actor = { username: "nv1", fullName: "Nhân viên 1", role: "ROLE_CASHIER" };
const tea = { id: "12", name: "Trà đào", price: 30000, category: "Trà" };
const milk = { id: "13", name: "Sữa", price: 20000 };

describe("bấm đơn trên web", () => {
  it("giữ id số của món như app POS", () => {
    expect(productIdValue("12")).toBe(12);
    expect(productIdValue("-Nabc")).toBe("-Nabc");
    expect(productIdValue("012")).toBe("012");
  });

  it("cộng dồn món chưa gửi bếp cùng ghi chú; món đã gửi bếp tạo dòng mới", () => {
    const a = makeOrderLine(tea, 1, "", actor, 1);
    let lines = addLineToOrder([], a);
    lines = addLineToOrder(lines, makeOrderLine(tea, 2, "", actor, 2));
    expect(lines).toHaveLength(1);
    expect(lineQuantity(lines[0])).toBe(3);
    lines = addLineToOrder(lines, makeOrderLine(tea, 1, "ít đá", actor, 3));
    expect(lines).toHaveLength(2);
    const sent = [{ ...lines[0], isSentKitchen: true }];
    expect(addLineToOrder(sent, makeOrderLine(tea, 1, "", actor, 4))).toHaveLength(2);
  });

  it("mở bàn trống + lưu đơn (chưa gửi bếp)", () => {
    const r = buildWebOrderUpdates({
      storeCode: "T1", tableKeys: ["A_Bàn 1", "alt"], table: { name: "Bàn 1", zone: "A", inUse: false },
      existingLines: [], newLines: [makeOrderLine(tea, 2, "", actor, 10)], sendKitchen: false, guestCount: 3, actor, now: 1000, nonce: "n",
    });
    if (!r.ok) throw new Error(r.error);
    expect(r.updates["stores/T1/tables/A_Bàn 1/inUse"]).toBe(true);
    expect(r.updates["stores/T1/tables/alt/openedAt"]).toBe(1000);
    expect(r.updates["stores/T1/tables/A_Bàn 1/guestCount"]).toBe(3);
    expect(r.updates["stores/T1/tables/A_Bàn 1/prePrintedAt"]).toBeNull();
    expect(String(r.updates["stores/T1/tables/A_Bàn 1/currentOrderCode"])).toMatch(/^OD-\d{6}-\d{6}-[A-Z2-9]{4}$/);
    const saved = JSON.parse(String(r.updates["stores/T1/tables/A_Bàn 1/currentOrderJson"]));
    expect(saved[0]).toMatchObject({ productId: 12, quantity: 2, isSentKitchen: false });
    expect(Object.keys(r.updates).some((k) => k.includes("kitchen_orders"))).toBe(false);
    expect(r.updates["stores/T1/audit_logs/log_1000_wo_n"]).toMatchObject({ action: "WEB_ORDER", targetId: "Bàn 1" });
  });

  it("gửi bếp: phiếu chỉ chứa món chưa gửi, đánh dấu đã gửi, giữ mã đơn & giờ mở bàn", () => {
    const existing = [{ ...makeOrderLine(milk, 1, "", actor, 1), isSentKitchen: true }];
    const r = buildWebOrderUpdates({
      storeCode: "T1", tableKeys: ["A_Bàn 1"],
      table: { name: "Bàn 1", inUse: true, currentOrderCode: "OD-X", openedAt: 5, guestCount: 2, actionLogsJson: "[]" },
      existingLines: existing, newLines: [makeOrderLine(tea, 1, "", actor, 10)], sendKitchen: true, kitchenNote: "gấp", actor, now: 2000, kitchenKey: "k1", nonce: "n",
    });
    if (!r.ok) throw new Error(r.error);
    const k = r.updates["stores/T1/kitchen_orders/k1"] as Record<string, unknown>;
    expect(JSON.parse(String(k.itemsJson))).toHaveLength(1);
    expect(k).toMatchObject({ tableName: "Bàn 1", orderCode: "OD-X", isDone: false, pickedUp: false, note: "gấp", orderedBy: "nv1" });
    expect(r.sentCount).toBe(1);
    const saved = JSON.parse(String(r.updates["stores/T1/tables/A_Bàn 1/currentOrderJson"]));
    expect(saved.every((l: { isSentKitchen: boolean }) => l.isSentKitchen)).toBe(true);
    expect(r.updates["stores/T1/tables/A_Bàn 1/currentOrderCode"]).toBe("OD-X");
    expect(r.updates).not.toHaveProperty("stores/T1/tables/A_Bàn 1/openedAt");
  });

  it("từ chối đơn rỗng", () => {
    expect(buildWebOrderUpdates({ storeCode: "T1", tableKeys: ["x"], table: { name: "x" }, existingLines: [], newLines: [], sendKitchen: false, actor, now: 1 })).toMatchObject({ ok: false });
  });

  it("mã đặt món theo giờ Việt Nam", () => {
    // 2026-01-02T17:30:05Z = 00:30:05 ngày 03/01 (UTC+7)
    expect(generateOrderCode(Date.UTC(2026, 0, 2, 17, 30, 5), () => 0)).toBe("OD-260103-003005-AAAA");
  });
});
