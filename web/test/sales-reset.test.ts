import { describe, it, expect } from "vitest";
import { RESET_GROUPS, buildResetPlan, isAutoSplitTable, orderedChunks } from "../lib/sales-reset";

const data = {
  history: { B1: { status: "PAID" }, B2: { status: "CANCELLED" } },
  bills: { B1: {}, B2: {} },
  kitchen_orders: { K1: {} },
  staff_calls: null,
  online_orders: { O1: {} },
  payment_events: {},
  cash_shifts: { S1: {} },
  bill_stock_applied: { B1: true },
  bill_stock_lines: null,
  stock_retry_queue: null,
  campaign_counters: { C1: { used: 3 } },
  customer_campaign_counters: null,
};
const tables = {
  t1: { name: "Bàn 01", inUse: true, currentOrderJson: "[{}]", isReserved: false },
  t2: { name: "Bàn 02", isReserved: true, reservationCustomer: "An" },
  t3: { name: "Bàn 01 (2)", inUse: true },
  t4: { name: "Mang về", isSplitTable: true },
};
const defaults = RESET_GROUPS.filter((g) => g.defaultOn).map((g) => g.key);

describe("Reset dữ liệu bán hàng", () => {
  it("xóa từng phần tử con của các node được chọn (rules chỉ cho xóa cấp phần tử)", () => {
    const p = buildResetPlan("TRAM01", defaults, data, tables);
    expect(p.updates["stores/TRAM01/history/B1"]).toBeNull();
    expect(p.updates["stores/TRAM01/history/B2"]).toBeNull();
    expect(p.updates["stores/TRAM01/bills/B2"]).toBeNull();
    expect(p.updates["stores/TRAM01/cash_shifts/S1"]).toBeNull();
    expect(p.updates["stores/TRAM01/bill_stock_applied/B1"]).toBeNull();
    expect("stores/TRAM01/history" in p.updates).toBe(false);
    expect(p.counts).toMatchObject({ history: 2, bills: 2, kitchen_orders: 1, online_orders: 1, cash_shifts: 1, staff_calls: 0 });
  });
  it("khuyến mãi chỉ xóa khi chọn; thực đơn / khách / kho / nhật ký không bao giờ đụng tới", () => {
    expect("stores/TRAM01/campaign_counters/C1" in buildResetPlan("TRAM01", defaults, data, tables).updates).toBe(false);
    expect(buildResetPlan("TRAM01", [...defaults, "promoCounters"], data, tables).updates["stores/TRAM01/campaign_counters/C1"]).toBeNull();
    const all = Object.keys(buildResetPlan("TRAM01", RESET_GROUPS.map((g) => g.key), data, tables).updates);
    for (const keep of ["products", "customers", "users", "stock_balances", "catalog_items", "campaigns", "audit_logs", "counters"]) {
      expect(all.some((p) => p.startsWith(`stores/TRAM01/${keep}/`))).toBe(false);
    }
  });
  it("bàn thường về TRỐNG (giữ tên / khu vực), bàn tách tạm bị xóa", () => {
    const p = buildResetPlan("TRAM01", defaults, data, tables);
    expect(p.updates["stores/TRAM01/tables/t1/inUse"]).toBe(false);
    expect(p.updates["stores/TRAM01/tables/t1/currentOrderJson"]).toBe("");
    expect(p.updates["stores/TRAM01/tables/t2/isReserved"]).toBe(false);
    expect(p.updates["stores/TRAM01/tables/t2/reservationCustomer"]).toBeNull();
    expect("stores/TRAM01/tables/t1/name" in p.updates).toBe(false);
    expect(p.updates["stores/TRAM01/tables/t3"]).toBeNull();
    expect(p.updates["stores/TRAM01/tables/t4"]).toBeNull();
    expect([p.tablesCleared, p.tablesRemoved]).toEqual([2, 2]);
    expect(isAutoSplitTable({ name: "Bàn 10" })).toBe(false);
  });
  it("chia đợt: xóa hóa đơn trước, trả bàn sau cùng; không mất lệnh nào", () => {
    const p = buildResetPlan("TRAM01", defaults, data, tables);
    const chunks = orderedChunks(p.updates, 5);
    const flat = chunks.flatMap((c) => Object.keys(c));
    expect(flat.length).toBe(Object.keys(p.updates).length);
    const firstTable = flat.findIndex((k) => k.includes("/tables/"));
    expect(flat.slice(firstTable).every((k) => k.includes("/tables/"))).toBe(true);
  });
});

describe("baseTableName — bàn tự tách gộp về bàn gốc trong báo cáo", () => {
  it("bỏ hậu tố (số); giữ (Tách)", async () => {
    const { baseTableName } = await import("../lib/table-status");
    expect(baseTableName("Bàn 01 (2)")).toBe("Bàn 01");
    expect(baseTableName("Mang về (3) ")).toBe("Mang về");
    expect(baseTableName("Bàn 01")).toBe("Bàn 01");
    expect(baseTableName("Bàn 01 (Tách)")).toBe("Bàn 01");
    expect(baseTableName("MANG VỀ 01 (Tách) (2)")).toBe("MANG VỀ 01");
  });
});
