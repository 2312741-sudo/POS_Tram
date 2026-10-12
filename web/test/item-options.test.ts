import { describe, it, expect } from "vitest";
import { EMPTY_CATALOG, NO_GROUPS, encodeGroupIds, noteChips, parseCatalog, parseGroupIds, resolveItemOptions, toggleTopping, type ItemCatalog } from "../lib/item-options";

const cat: ItemCatalog = parseCatalog(
  {
    n1: { name: "Đồ uống", sortOrder: 1, items: [{ id: "a", text: "Ít đá" }, { id: "b", text: "Ít ngọt" }] },
    n2: { name: "Bánh", sortOrder: 2, items: [{ id: "c", text: "Cắt đôi" }, { id: "d", text: "Ít đá" }] },
    n3: { name: "Tắt", sortOrder: 3, active: false, items: [{ id: "e", text: "X" }] },
  },
  {
    t1: { name: "Topping trà", sortOrder: 1, items: [{ id: "1", name: "Trân châu", price: 5000 }, { id: "2", name: "Thạch", price: 4000 }] },
    t2: { name: "Sốt", sortOrder: 2, multi: false, items: [{ id: "3", name: "Socola", price: 3000 }, { id: "4", name: "Dâu", price: 3000 }] },
    t3: { name: "Rỗng", sortOrder: 3 },
  }
);

describe("resolveItemOptions", () => {
  it("chưa cấu hình → legacy", () => {
    expect(resolveItemOptions({}, {}, EMPTY_CATALOG).legacy).toBe(true);
  });
  it("không gắn gì → không note/topping", () => {
    const r = resolveItemOptions({}, {}, cat);
    expect(r.legacy).toBe(false);
    expect(r.noteGroups).toEqual([]);
    expect(r.toppingGroups).toEqual([]);
    expect(r.noteSource).toBe("none");
  });
  it("kế thừa nhóm món", () => {
    const r = resolveItemOptions({}, { noteGroupIds: ["n1"], toppingGroupIds: ["t1"] }, cat);
    expect(r.noteGroups.map((g) => g.id)).toEqual(["n1"]);
    expect(r.toppingGroups.map((g) => g.id)).toEqual(["t1"]);
    expect(r.noteSource).toBe("category");
  });
  it("món ghi đè, kể cả rỗng / __none__", () => {
    const c = { noteGroupIds: ["n1"], toppingGroupIds: ["t1"] };
    expect(resolveItemOptions({ noteGroupIds: ["n2"] }, c, cat).noteGroups.map((g) => g.id)).toEqual(["n2"]);
    const none = resolveItemOptions({ noteGroupIds: [], toppingGroupIds: [NO_GROUPS] }, c, cat);
    expect(none.noteGroups).toEqual([]);
    expect(none.toppingGroups).toEqual([]);
    expect(none.noteSource).toBe("product");
  });
  it("bỏ nhóm tắt/không tồn tại/rỗng, giữ thứ tự gắn, bỏ trùng", () => {
    const r = resolveItemOptions({ noteGroupIds: ["n2", "n3", "zzz", "n1", "n2"], toppingGroupIds: ["t3", "t2", "t1"] }, null, cat);
    expect(r.noteGroups.map((g) => g.id)).toEqual(["n2", "n1"]);
    expect(r.toppingGroups.map((g) => g.id)).toEqual(["t2", "t1"]);
    expect(noteChips(r)).toEqual(["Cắt đôi", "Ít đá", "Ít ngọt"]);
  });
});

describe("encode/parse", () => {
  it("rỗng → [__none__]; null → null; map RTDB", () => {
    expect(encodeGroupIds(undefined)).toBeNull();
    expect(encodeGroupIds([])).toEqual([NO_GROUPS]);
    expect(encodeGroupIds(["a", NO_GROUPS])).toEqual(["a"]);
    expect(parseGroupIds(null)).toBeUndefined();
    expect(parseGroupIds({ "0": "a", "2": "b" })).toEqual(["a", "b"]);
  });
});

describe("toggleTopping", () => {
  const [t1, t2] = cat.toppingGroups;
  it("chọn một thay thế trong nhóm", () => {
    let s = ["Trân châu"];
    s = toggleTopping(s, t2, "Socola");
    s = toggleTopping(s, t2, "Dâu");
    expect(s).toEqual(["Trân châu", "Dâu"]);
  });
  it("giới hạn tối đa", () => {
    const g = { ...t1, max: 1 };
    let s = toggleTopping([], g, "Trân châu");
    s = toggleTopping(s, g, "Thạch");
    expect(s).toEqual(["Trân châu"]);
    expect(toggleTopping(s, g, "Trân châu")).toEqual([]);
  });
});

describe("parseCatalog", () => {
  it("sắp theo sortOrder, giá âm → 0", () => {
    expect(cat.noteGroups.map((g) => g.id)).toEqual(["n1", "n2", "n3"]);
    const c = parseCatalog(null, { x: { name: "A", items: { "0": { name: "T", price: -5 } } } });
    expect(c.toppingGroups[0].items[0].price).toBe(0);
  });
});
