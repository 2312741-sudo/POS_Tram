import { describe, it, expect } from "vitest";
import { buildStockAdjustment, collectItemGroups } from "../lib/stock-adjust";

const actor = { username: "ql1", fullName: "Quản lý 1" };
const item = { itemId: "I1", name: "Đường", costPrice: 20000 };

describe("nhập tồn kho", () => {
  it("từ chối số âm, thiếu lý do hoặc không đổi", () => {
    const base = { storeCode: "T1", item, actor, now: 1, nonce: "n", reason: "kiểm kê" };
    expect(buildStockAdjustment({ ...base, current: undefined, newQty: -1 })).toMatchObject({ ok: false });
    expect(buildStockAdjustment({ ...base, current: undefined, newQty: 5, reason: " " })).toMatchObject({ ok: false });
    expect(buildStockAdjustment({ ...base, current: { onHandQty: 5, reservedQty: 0, inventoryValue: 0, averageCostScaled: 0 }, newQty: 5 })).toMatchObject({ ok: false });
  });

  it("chưa có số dư → tồn đầu kỳ, giá trị theo giá vốn danh mục", () => {
    const r = buildStockAdjustment({ storeCode: "T1", item, current: undefined, newQty: 10, reason: "tồn đầu", actor, now: 5, nonce: "n" });
    if (!r.ok) throw new Error(r.error);
    expect(r.delta).toBe(10);
    expect(r.updates["stores/T1/stock_balances/T1_I1"]).toMatchObject({ onHandQty: 10, inventoryValue: 200000, averageCostScaled: 2000000, reservedQty: 0 });
    expect(r.updates["stores/T1/stock_events/EVT_5_n"]).toMatchObject({ documentType: "OPENING", qtyDeltaBase: 10, valueDeltaMoney: 200000 });
    expect(r.updates["stores/T1/audit_logs/log_5_stk_n"]).toMatchObject({ action: "STOCK_SET_ONHAND" });
  });

  it("đã có số dư → điều chỉnh, giữ giá vốn bình quân và hàng đang giữ", () => {
    const cur = { onHandQty: 10, reservedQty: 2, inventoryValue: 150000, averageCostScaled: 1500000 };
    const r = buildStockAdjustment({ storeCode: "T1", item, current: cur, newQty: 4, reason: "hao hụt", actor, now: 5, nonce: "n" });
    if (!r.ok) throw new Error(r.error);
    expect(r.delta).toBe(-6);
    expect(r.updates["stores/T1/stock_balances/T1_I1"]).toMatchObject({ onHandQty: 4, reservedQty: 2, inventoryValue: 60000, averageCostScaled: 1500000 });
    expect(r.updates["stores/T1/stock_events/EVT_5_n"]).toMatchObject({ documentType: "STOCK_ADJUSTMENT", qtyDeltaBase: -6, valueDeltaMoney: -90000 });
  });
});

describe("nhóm hàng", () => {
  it("gom nhóm không trùng", () => {
    expect(collectItemGroups([{ managementGroup: "Sữa" }, { managementGroup: " sữa " , groupIds: ["Trà", "Sữa"] }, { managementGroup: "" }])).toEqual(["sữa", "Sữa", "Trà"].sort((a, b) => a.localeCompare(b, "vi")));
  });
});
