import { describe, it, expect } from "vitest";
import { buildCategoryOrderUpdates, compareCategories, moveName, sortCategories } from "../lib/category-order";
import { buildZoneOrderUpdates, buildZonePinUpdates, parseZoneMeta, sortZoneNames } from "../lib/zones";

describe("thứ tự danh mục", () => {
  it("order trước, chưa có order sau theo tên", () => {
    const r = sortCategories([{ name: "Z" }, { name: "B", order: 1 }, { name: "A", order: 0 }, { name: "C" }]);
    expect(r.map((x) => x.name)).toEqual(["A", "B", "C", "Z"]);
    expect(compareCategories({ name: "a", order: 2 }, { name: "b", order: 2 })).toBeLessThan(0);
  });
  it("moveName đổi chỗ và chặn biên", () => {
    expect(moveName(["a", "b", "c"], 1, -1)).toEqual(["b", "a", "c"]);
    expect(moveName(["a", "b"], 0, -1)).toBeNull();
    expect(moveName(["a", "b"], 1, 1)).toBeNull();
  });
  it("chỉ ghi order cho danh mục có trong chi nhánh", () => {
    expect(buildCategoryOrderUpdates("S", ["x", "gone", "y"], new Set(["x", "y"]))).toEqual({
      "stores/S/categories/x/order": 0,
      "stores/S/categories/y/order": 1,
    });
  });
});

describe("ghim và thứ tự khu vực (khớp bản Dart)", () => {
  const meta = parseZoneMeta({
    Sân: { name: "Sân", order: 0 },
    "Tầng 1": { name: "Tầng 1", order: 1 },
    "Tầng 2": { name: "Tầng 2", pinned: true, order: 5 },
    VIP: { name: "VIP" },
  });
  it("ghim trước, rồi thứ tự, rồi tên; khu chưa khai báo cuối", () => {
    expect(sortZoneNames(["VIP", "Tầng 1", "Mới", "Sân", "Tầng 2"], meta)).toEqual(["Tầng 2", "Sân", "Tầng 1", "VIP", "Mới"]);
  });
  it("ghim chỉ ghi cờ pinned", () => {
    expect(buildZonePinUpdates("S", "Sân", true)).toEqual({ "stores/S/zones/Sân/name": "Sân", "stores/S/zones/Sân/pinned": true });
    expect(buildZonePinUpdates("S", "Sân", false)["stores/S/zones/Sân/pinned"]).toBeNull();
  });
  it("lưu thứ tự đặt khu ghim lên trước", () => {
    const u = buildZoneOrderUpdates("S", ["A", "B", "C"], new Set(["C"]));
    expect(u["stores/S/zones/C/order"]).toBe(0);
    expect(u["stores/S/zones/A/order"]).toBe(1);
  });
});
