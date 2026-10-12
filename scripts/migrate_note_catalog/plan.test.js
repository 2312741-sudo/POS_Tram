const test = require("node:test");
const assert = require("node:assert");
const { planNoteCatalogMigration, legacyHash } = require("./plan");

const products = {
  "Thạch chanh": { id: 1, name: "Thạch chanh", price: 5000, category: "Topping", isTopping: true },
  "Trà Olong - Đào": { id: 3, name: "Trà Olong - Đào", price: 30000, category: "Trà Olong Trái Cây" },
  "Bánh lăn A": { id: 4, name: "Bánh lăn A", price: 20000, category: "Bánh Lăn Nướng" },
  "Cà phê X": { id: 5, name: "Cà phê X", price: 20000, category: "Cafe riêng", allowedToppings: ["Thạch chanh", "Kem Cheese"] },
};
const categories = {
  "Bánh Lăn Nướng": { name: "Bánh Lăn Nướng" },
  Topping: { name: "Topping" },
  "Trà Olong Trái Cây": { name: "Trà Olong Trái Cây" },
  "Cafe riêng": { name: "Cafe riêng" },
};
const base = { products, categories, productNotes: { n1: { text: "Ít đá" } }, noteGroups: null, toppingGroups: null };

test("đồ uống được gắn, bánh và nhóm Topping không", () => {
  const u = planNoteCatalogMigration(base).updates;
  assert.deepStrictEqual(u["categories/Trà Olong Trái Cây/toppingGroupIds"], ["legacy_toppings"]);
  assert.deepStrictEqual(u["categories/Trà Olong Trái Cây/noteGroupIds"], ["legacy_notes"]);
  assert.ok(!Object.keys(u).some((k) => k.startsWith("categories/Bánh Lăn Nướng") || k.startsWith("categories/Topping/")));
  assert.ok(Object.keys(u).some((k) => k.startsWith("products/Cà phê X/toppingGroupIds")));
});

test("idempotent: chạy lại sau khi đã có nhóm thì không ghi lại nhóm", () => {
  const u = planNoteCatalogMigration({ ...base, noteGroups: { legacy_notes: {} }, toppingGroups: { legacy_toppings: {} } }).updates;
  assert.ok(!("note_groups/legacy_notes" in u));
  assert.ok(!("topping_groups/legacy_toppings" in u));
});

test("hash ổn định và khác nhau theo thứ tự", () => {
  assert.strictEqual(legacyHash("abc"), legacyHash("abc"));
  assert.notStrictEqual(legacyHash("a|b"), legacyHash("b|a"));
});
