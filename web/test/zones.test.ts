import { describe, it, expect } from "vitest";
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
