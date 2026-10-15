import { describe, it, expect } from "vitest";
import { planAddTables, planZoneCreate, planZoneRename, validateTablePrefix, validateTableCount, isTableInUse, buildZoneAuditUpdates, planDeleteTable, planDedupeTables } from "../lib/zones";
import { buildZoneCreateUpdates, buildZoneDeleteUpdates, mergeZoneNames, nextTableNames, parseZones, validateZoneName } from "../lib/zones";

describe("khu vực bàn", () => {
  it("đọc danh sách khu từ nhiều dạng dữ liệu", () => {
    expect(parseZones({ "Khu B": { name: "Khu B" }, a: { name: "Khu A" }, bad: 5, "  ": {} })).toEqual(["bad", "Khu A", "Khu B"]);
    expect(parseZones(null)).toEqual([]);
  });

  it("gộp khu đã khai báo với khu của bàn", () => {
    expect(mergeZoneNames(["Khu A"], ["Khu B", undefined, " Khu A "])).toEqual(["Khu A", "Khu B"]);
  });

  it("kiểm tra tên khu", () => {
    expect(validateZoneName("", [])).toMatch(/nhập/);
    expect(validateZoneName("Tầng 1/2", [])).toMatch(/ký tự/);
    expect(validateZoneName("khu a", ["Khu A"])).toMatch(/tồn tại/);
    expect(validateZoneName("x".repeat(41), [])).toMatch(/40/);
    expect(validateZoneName("Sân vườn", ["Khu A"])).toBeNull();
  });

  it("đặt tên bàn tuần tự và tránh trùng", () => {
    expect(nextTableNames("Bàn", 3, [])).toEqual(["Bàn 01", "Bàn 02", "Bàn 03"]);
    expect(nextTableNames("Bàn", 2, ["Bàn 01", "bàn 02"])).toEqual(["Bàn 03", "Bàn 04"]);
  });

  it("tạo khu + bàn trong một update đa đường dẫn (khóa khu_tên như app POS)", () => {
    const u = buildZoneCreateUpdates({ storeCode: "T1", zoneName: " Sân ", tableNames: ["Bàn 01"] });
    expect(u["stores/T1/zones/Sân"]).toEqual({ name: "Sân" });
    expect(u["stores/T1/tables/Sân_Bàn 01"]).toEqual({ name: "Bàn 01", zone: "Sân", inUse: false, currentOrderJson: "" });
  });

  it("không cho xóa khu còn bàn", () => {
    expect(buildZoneDeleteUpdates({ storeCode: "T1", zoneName: "A", tablesInZone: 2 })).toHaveProperty("error");
    expect(buildZoneDeleteUpdates({ storeCode: "T1", zoneName: "A", tablesInZone: 0 })).toEqual({ updates: { "stores/T1/zones/A": null } });
  });
});


const T = (zone: string, name: string, extra: Record<string, unknown> = {}) => ({
  key: `${zone}_${name}`,
  value: { name, zone, inUse: false, currentOrderJson: "", capacity: 4, ...extra },
});

describe("kiểm tra đầu vào khu/bàn", () => {
  it("tiền tố và số bàn", () => {
    expect(validateTablePrefix("Bàn")).toBeNull();
    expect(validateTablePrefix("Bàn/1")).toMatch(/ký tự/);
    expect(validateTablePrefix("T.2")).toMatch(/ký tự/);
    expect(validateTablePrefix("x".repeat(21))).toMatch(/20/);
    expect(validateTableCount(0)).toBeNull();
    expect(validateTableCount(101)).toMatch(/100/);
    expect(validateTableCount(1.5)).toMatch(/nguyên|100/);
    expect(validateTableCount("abc")).toMatch(/100/);
    expect(validateTableCount(0, 1)).toMatch(/1 đến/);
  });

  it("bàn đang dùng: inUse hoặc còn giỏ món", () => {
    expect(isTableInUse({ inUse: true })).toBe(true);
    expect(isTableInUse({ inUse: false, currentOrderJson: "[{}]" })).toBe(true);
    expect(isTableInUse({ inUse: false, currentOrderJson: "" })).toBe(false);
  });
});

describe("tạo khu (planZoneCreate)", () => {
  it("tạo khu kèm bàn và ghi đúng khóa khu_tên", () => {
    const r = planZoneCreate({ storeCode: "T1", zoneName: "Tầng 2", prefix: "Bàn", count: 2, declaredZones: [], tables: [] });
    expect(r).toMatchObject({ affected: 2 });
    if ("error" in r) throw new Error(r.error);
    expect(Object.keys(r.updates)).toContain("stores/T1/tables/Tầng 2_Bàn 01");
  });

  it("từ chối khu trùng và tiền tố sai", () => {
    expect(planZoneCreate({ storeCode: "T1", zoneName: "khu a", prefix: "Bàn", count: 1, declaredZones: ["Khu A"], tables: [] })).toHaveProperty("error");
    expect(planZoneCreate({ storeCode: "T1", zoneName: "Khu B", prefix: "B/", count: 1, declaredZones: [], tables: [] })).toHaveProperty("error");
  });

  it("không tạo khu rỗng bàn khi count = 0", () => {
    const r = planZoneCreate({ storeCode: "T1", zoneName: "Sân", prefix: "Bàn", count: 0, declaredZones: [], tables: [] });
    if ("error" in r) throw new Error(r.error);
    expect(Object.keys(r.updates)).toEqual(["stores/T1/zones/Sân"]);
  });
});

describe("thêm bàn vào khu (planAddTables)", () => {
  it("tiếp nối số thứ tự, bỏ qua tên đã có", () => {
    const tables = [T("A", "Bàn 01"), T("A", "Bàn 02"), T("B", "Bàn 03")];
    const r = planAddTables({ storeCode: "T1", zoneName: "A", prefix: "Bàn", count: 2, declaredZones: ["A", "B"], tables });
    if ("error" in r) throw new Error(r.error);
    // Chỉ ghi zones/A/name (không ghi cả nút khu) để thêm bàn không xóa ghim / thứ tự khu đã đặt
    expect(Object.keys(r.updates).sort()).toEqual(["stores/T1/tables/A_Bàn 03", "stores/T1/tables/A_Bàn 04", "stores/T1/zones/A/name"]);
    expect(r.updates["stores/T1/zones/A/name"]).toBe("A");
    expect(r.updates["stores/T1/tables/A_Bàn 03"]).toEqual({ name: "Bàn 03", zone: "A", inUse: false, currentOrderJson: "" });
  });

  it("từ chối khu không tồn tại và số bàn < 1", () => {
    expect(planAddTables({ storeCode: "T1", zoneName: "Ma", prefix: "Bàn", count: 1, declaredZones: [], tables: [] })).toHaveProperty("error");
    expect(planAddTables({ storeCode: "T1", zoneName: "A", prefix: "Bàn", count: 0, declaredZones: ["A"], tables: [] })).toHaveProperty("error");
  });
});

describe("đổi tên khu (planZoneRename)", () => {
  it("chuyển khu node và mọi bàn trong MỘT update, giữ nguyên trường khác", () => {
    const tables = [T("Khu A", "Bàn 01", { capacity: 6 }), T("Khu A", "Bàn 02"), T("Khu B", "Bàn 01")];
    const r = planZoneRename({ storeCode: "T1", oldName: "Khu A", newName: "Tầng 1", declaredZones: ["Khu A", "Khu B"], tables });
    if ("error" in r) throw new Error(r.error);
    expect(r.affected).toBe(2);
    expect(r.updates["stores/T1/zones/Khu A"]).toBeNull();
    expect(r.updates["stores/T1/zones/Tầng 1"]).toEqual({ name: "Tầng 1" });
    expect(r.updates["stores/T1/tables/Khu A_Bàn 01"]).toBeNull();
    expect(r.updates["stores/T1/tables/Tầng 1_Bàn 01"]).toEqual({ name: "Bàn 01", zone: "Tầng 1", inUse: false, currentOrderJson: "", capacity: 6 });
    expect(r.updates["stores/T1/tables/Khu B_Bàn 01"]).toBeUndefined();
  });

  it("từ chối khi có bàn đang dùng hoặc còn giỏ món", () => {
    const busy = [T("A", "Bàn 01", { inUse: true })];
    expect(planZoneRename({ storeCode: "T1", oldName: "A", newName: "B", declaredZones: ["A"], tables: busy })).toHaveProperty("error");
    const order = [T("A", "Bàn 01", { currentOrderJson: "[{\"x\":1}]" })];
    expect(planZoneRename({ storeCode: "T1", oldName: "A", newName: "B", declaredZones: ["A"], tables: order })).toHaveProperty("error");
  });

  it("từ chối tên trùng khu khác (không phân biệt hoa thường) và tên không đổi", () => {
    expect(planZoneRename({ storeCode: "T1", oldName: "A", newName: "b", declaredZones: ["A", "B"], tables: [] })).toHaveProperty("error");
    expect(planZoneRename({ storeCode: "T1", oldName: "A", newName: " A ", declaredZones: ["A"], tables: [] })).toHaveProperty("error");
  });

  it("từ chối khi khóa bàn đích đã bị chiếm bởi bàn khác", () => {
    const tables = [T("A", "Bàn 01"), T("B", "Bàn 01")];
    expect(planZoneRename({ storeCode: "T1", oldName: "A", newName: "B", declaredZones: ["A"], tables })).toHaveProperty("error");
  });

  it("đổi hoa/thường tên khu vẫn hợp lệ (khóa khác)", () => {
    const r = planZoneRename({ storeCode: "T1", oldName: "khu a", newName: "Khu A", declaredZones: ["khu a"], tables: [T("khu a", "Bàn 01")] });
    if ("error" in r) throw new Error(r.error);
    expect(r.updates["stores/T1/tables/khu a_Bàn 01"]).toBeNull();
    expect(r.updates["stores/T1/tables/Khu A_Bàn 01"]).toBeDefined();
  });
});

describe("nhật ký thao tác khu", () => {
  it("ghi khóa mới với timestamp và đúng trường", () => {
    const u = buildZoneAuditUpdates({ storeCode: "T1", action: "ZONE_RENAME", targetType: "ZONE", targetId: "A", details: "x", actor: { username: "boss" }, now: 1000, suffix: 7 });
    const e = u["stores/T1/audit_logs/log_1000_zone_7"] as Record<string, unknown>;
    expect(e).toMatchObject({ timestamp: 1000, username: "boss", userFullName: "boss", action: "ZONE_RENAME", targetType: "ZONE", storeCode: "T1" });
  });
});

describe("xóa bàn / dọn bàn trùng", () => {
  const rec = (key: string, name: string, zone: string, extra: Record<string, unknown> = {}) => ({ key, value: { name, zone, inUse: false, currentOrderJson: "", ...extra } });
  it("xóa bàn xóa mọi node cùng khu + tên", () => {
    const r = planDeleteTable({ storeCode: "T1", zoneName: "A", tableName: "Grab", tables: [rec("A_Grab", "Grab", "A"), rec("Grab", "Grab", "A"), rec("B_Grab", "Grab", "B")] });
    expect(r).toEqual({ updates: { "stores/T1/tables/A_Grab": null, "stores/T1/tables/Grab": null }, affected: 1 });
  });
  it("từ chối xóa bàn đang dùng hoặc không tồn tại", () => {
    expect("error" in planDeleteTable({ storeCode: "T1", zoneName: "A", tableName: "Grab", tables: [rec("A_Grab", "Grab", "A", { inUse: true })] })).toBe(true);
    expect("error" in planDeleteTable({ storeCode: "T1", zoneName: "A", tableName: "X", tables: [] })).toBe(true);
  });
  it("dọn trùng giữ khóa chuẩn, ưu tiên bàn đang dùng", () => {
    const r = planDedupeTables({ storeCode: "T1", tables: [rec("Grab", "Grab", "A"), rec("A_Grab", "Grab", "A"), rec("B_Grab", "Grab", "B")] });
    expect(r).toEqual({ updates: { "stores/T1/tables/Grab": null }, affected: 1 });
    const busy = planDedupeTables({ storeCode: "T1", tables: [rec("Grab", "Grab", "A", { inUse: true }), rec("A_Grab", "Grab", "A")] });
    expect(busy).toEqual({ updates: { "stores/T1/tables/A_Grab": null }, affected: 1 });
    expect("error" in planDedupeTables({ storeCode: "T1", tables: [rec("A_Grab", "Grab", "A")] })).toBe(true);
  });
});
