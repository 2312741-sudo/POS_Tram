import { describe, it, expect } from "vitest";
import { menuDedupeUpdates, planMenuDedupe } from "../lib/menu-dedupe";

const products = {
  "-NxoaiA": { id: 3, name: "Trà Olong - Xoài", code: "DR202500003", price: 30000, category: "Khác" },
  "Trà Olong - Xoài": { id: 33, name: "Trà Olong - Xoài", code: "DR202500003", price: 30000, category: "TRÀ TRÁI CÂY", sizes: { M: 0 } },
  "-NduaA": { id: 44, name: "Thạch dừa", code: "PK202500044", price: 5000, category: "Khác", toppingGroupIds: ["g1"] },
  "-NduaB": { id: 45, name: "Thạch dừa", code: "PK202500044", price: 5000, category: "THẠCH", isTopping: true },
  "-Nchanh": { id: 2, name: "Trà Olong - Chanh tươi", code: "DR202500002", price: 30000, category: "TRÀ TRÁI CÂY" },
  "-NnoCode1": { name: "Món không mã", price: 1 },
  "-NnoCode2": { name: "Món không mã", price: 1 },
};

describe("Dọn món trùng trong thực đơn", () => {
  it("chỉ nhóm theo mã món; món không mã không đụng", () => {
    const g = planMenuDedupe(products, null);
    expect(g.map((x) => [x.code, x.keep.key, x.remove.map((r) => r.key)])).toEqual([
      ["PK202500044", "-NduaB", ["-NduaA"]],
      ["DR202500003", "Trà Olong - Xoài", ["-NxoaiA"]],
    ]);
  });
  it("ưu tiên giữ bản đang nối kho, kể cả khi nhóm hàng là 'Khác'; chép nhóm hàng thật sang", () => {
    const g = planMenuDedupe(products, { CI1: { legacyProductId: 3 } });
    const xoai = g.find((x) => x.code === "DR202500003")!;
    expect(xoai.keep.key).toBe("-NxoaiA");
    expect(xoai.keep.linkedStock).toBe(true);
    expect(xoai.patch).toEqual({ category: "TRÀ TRÁI CÂY", sizes: { M: 0 } });
  });
  it("chép nhóm topping / note còn thiếu; lệnh ghi xóa bản thừa + vá bản giữ", () => {
    const g = planMenuDedupe(products, null);
    const dua = g.find((x) => x.code === "PK202500044")!;
    expect(dua.patch).toEqual({ toppingGroupIds: ["g1"] });
    const u = menuDedupeUpdates("TRAM01", g);
    expect(u["stores/TRAM01/products/-NduaA"]).toBeNull();
    expect(u["stores/TRAM01/products/-NxoaiA"]).toBeNull();
    expect("stores/TRAM01/products/Trà Olong - Xoài" in u).toBe(false);
    expect(u["stores/TRAM01/products/-NduaB/toppingGroupIds"]).toEqual(["g1"]);
  });
});
