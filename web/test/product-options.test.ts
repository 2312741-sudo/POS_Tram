import { describe, it, expect } from "vitest";
import { defaultSelection, describeSelection, getProductOptions, makeConfiguredLine, type OptionProduct } from "../lib/product-options";
import { addLineToOrder } from "../lib/web-order";
import { lineUnitPrice } from "../lib/order-math";

const actor = { username: "nv1" };
const tea: OptionProduct = { id: "1", name: "Trà đào", price: 30000, category: "Trà", sizes: { S: 0, M: 5000, L: 10000 } };
const tops: OptionProduct[] = [
  { id: "90", name: "Trân châu đen", price: 5000, category: "Topping", isTopping: true },
  { id: "91", name: "Kem Cheese", price: 12000, category: "Topping", isTopping: true },
];
const cake: OptionProduct = { id: "2", name: "Bánh waffle", price: 55000, category: "Bánh" };

describe("tùy chọn món", () => {
  it("đồ uống có size, topping và đường/đá; bánh không có gì để hỏi", () => {
    const o = getProductOptions(tea, [], [tea, ...tops]);
    expect(o.sizes.map((s) => s.name)).toEqual(["S", "M", "L"]);
    expect(o.iceSugar).toBe(true);
    expect(o.toppings.find((t) => t.name === "Kem Cheese")?.price).toBe(12000);
    expect(getProductOptions(cake, [], [cake, ...tops]).hasAny).toBe(false);
    expect(getProductOptions(tops[0], [], tops).hasAny).toBe(false);
  });

  it("thiếu size ở danh mục đồ uống → mặc định S/M/L", () => {
    const o = getProductOptions({ id: "3", name: "Sữa tươi", price: 20000, category: "Sữa" }, [], []);
    expect(o.sizes).toEqual([{ name: "S", extra: 0 }, { name: "M", extra: 5000 }, { name: "L", extra: 10000 }]);
  });

  it("topping theo danh mục (allowedToppingIds) ưu tiên hơn mặc định", () => {
    const o = getProductOptions(tea, [{ name: "Trà", allowedToppingIds: ["91", "Thạch chanh"] }], [tea, ...tops]);
    expect(o.toppings).toEqual([{ name: "Kem Cheese", price: 12000 }, { name: "Thạch chanh", price: 5000 }]);
  });

  it("dòng có size + topping tính đúng đơn giá và ghi trường như POS", () => {
    const o = getProductOptions(tea, [], [tea, ...tops]);
    const sel = { ...defaultSelection(o), size: "L", sugar: "70% đường", ice: "Không đá", toppings: ["Trân châu đen", "Kem Cheese"] };
    const line = makeConfiguredLine(tea, o, sel, 2, " ít ngọt ", actor, 1);
    expect(line).toMatchObject({ productId: 1, selectedSize: "L", sizeExtraPrice: 10000, selectedSugar: "70% đường", selectedIce: "Không đá", toppingPrice: 17000, quantity: 2, note: "ít ngọt" });
    expect(lineUnitPrice(line)).toBe(30000 + 10000 + 17000);
    expect(describeSelection(line)).toBe("Size L • 70% đường • Không đá • + Trân châu đen, Kem Cheese");
  });

  it("mặc định: size nhỏ nhất, 100% đường/đá, không topping", () => {
    expect(defaultSelection(getProductOptions(tea, [], []))).toEqual({ size: "S", sugar: "100% đường", ice: "100% đá", toppings: [] });
  });

  it("chỉ gộp dòng khi cùng tùy chọn", () => {
    const o = getProductOptions(tea, [], [tea, ...tops]);
    const base = defaultSelection(o);
    const a = makeConfiguredLine(tea, o, base, 1, "", actor, 1);
    const same = makeConfiguredLine(tea, o, base, 1, "", actor, 2);
    const diff = makeConfiguredLine(tea, o, { ...base, size: "L" }, 1, "", actor, 3);
    expect(addLineToOrder(addLineToOrder([], a), same)).toHaveLength(1);
    expect(addLineToOrder(addLineToOrder([], a), diff)).toHaveLength(2);
  });
});
