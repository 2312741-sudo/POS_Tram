import { describe, it, expect } from "vitest";
import { legacyHash, planNoteCatalogMigration } from "../lib/note-catalog-migrate";

const products = {
  "Thạch chanh": { id: 1, name: "Thạch chanh", price: 5000, category: "Topping", isTopping: true },
  "Thạch dừa": { id: 2, name: "Thạch dừa", price: 6000, category: "Topping" },
  "Trà Olong - Đào": { id: 3, name: "Trà Olong - Đào", price: 30000, category: "Trà Olong Trái Cây" },
  "Bánh lăn A": { id: 4, name: "Bánh lăn A", price: 20000, category: "Bánh Lăn Nướng" },
  "Cà phê X": { id: 5, name: "Cà phê X", price: 20000, category: "Cafe riêng", allowedToppings: ["Thạch dừa", "Kem Cheese"] },
};
const categories = {
  "Bánh Lăn Nướng": { name: "Bánh Lăn Nướng" },
  Topping: { name: "Topping" },
  "Trà Olong Trái Cây": { name: "Trà Olong Trái Cây" },
  "Cafe riêng": { name: "Cafe riêng" },
  "Sữa tuỳ chọn": { name: "Sữa tuỳ chọn", allowedToppingIds: ["1", "Kem Cheese"] },
};
const notes = { n1: { text: "Ít đá" }, n2: { text: "Ít ngọt" } };
const plan = (o: Partial<Parameters<typeof planNoteCatalogMigration>[0]> = {}) =>
  planNoteCatalogMigration({ products, categories, productNotes: notes, noteGroups: null, toppingGroups: null, ...o });

describe("nhập từ cấu hình cũ", () => {
  it("đồ uống được gắn topping + note; bánh và nhóm Topping không gắn gì", () => {
    const u = plan().updates as Record<string, { items: { name: string }[] } & Record<string, unknown>>;
    expect(u["topping_groups/legacy_toppings"].items).toHaveLength(2);
    expect(u["note_groups/legacy_notes"].items).toHaveLength(2);
    expect(u["categories/Trà Olong Trái Cây/toppingGroupIds"]).toEqual(["legacy_toppings"]);
    expect(u["categories/Trà Olong Trái Cây/noteGroupIds"]).toEqual(["legacy_notes"]);
    expect(Object.keys(u).some((k) => k.startsWith("categories/Bánh Lăn Nướng") || k.startsWith("categories/Topping/"))).toBe(false);
  });
  it("nhóm có allowedToppingIds → nhóm riêng; món có allowedToppings riêng → nhóm theo bộ", () => {
    const u = plan().updates as Record<string, { items: { name: string }[] } & Record<string, unknown>>;
    expect(u["categories/Sữa tuỳ chọn/toppingGroupIds"]).toEqual(["legacy_cat_Sữa_tuỳ_chọn"]);
    expect(u["topping_groups/legacy_cat_Sữa_tuỳ_chọn"].items.map((e: { name: string }) => e.name)).toEqual(["Thạch chanh", "Kem Cheese"]);
    const k = Object.keys(u).find((x) => x.startsWith("products/Cà phê X/"))!;
    expect(u[k]).toHaveLength(1);
  });
  it("idempotent: không ghi đè nhóm có sẵn, giữ trường gắn có sẵn (kể cả không có)", () => {
    const cats2 = { ...categories, "Trà Olong Trái Cây": { name: "Trà Olong Trái Cây", toppingGroupIds: ["__none__"], noteGroupIds: ["x"] } };
    const u = plan({ noteGroups: { legacy_notes: {} }, toppingGroups: { legacy_toppings: {} }, categories: cats2 }).updates;
    expect("note_groups/legacy_notes" in u).toBe(false);
    expect("topping_groups/legacy_toppings" in u).toBe(false);
    expect("categories/Trà Olong Trái Cây/toppingGroupIds" in u).toBe(false);
    expect("categories/Trà Olong Trái Cây/noteGroupIds" in u).toBe(false);
  });
  it("không có món Topping → bộ chuẩn; không có gì → rỗng; hash ổn định", () => {
    const u = plan({ products: { A: { name: "A", price: 1, category: "Trà" } }, categories: { Trà: { name: "Trà" } } }).updates as Record<string, { items: { name: string }[] } & Record<string, unknown>>;
    expect(u["topping_groups/legacy_toppings"].items).toHaveLength(8);
    expect(Object.keys(planNoteCatalogMigration({ products: null, categories: null, productNotes: null, noteGroups: null, toppingGroups: null }).updates)).toHaveLength(0);
    expect(legacyHash("abc")).toBe(legacyHash("abc"));
    expect(legacyHash("Thạch dừa|Kem Cheese")).not.toBe(legacyHash("Kem Cheese|Thạch dừa"));
  });
});
