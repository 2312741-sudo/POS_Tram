import { describe, it, expect } from "vitest";
import { groupToppings, toppingLabels, toppingCount } from "../lib/topping-utils";
import { addToppingUnit, removeToppingUnit, type ToppingGroup } from "../lib/item-options";
import { parseKitchenTickets, planKitchenCancel } from "../lib/kitchen";
import { describeSelection } from "../lib/product-options";

const group = (multi: boolean, max: number): ToppingGroup =>
  ({ id: "g", name: "G", sortOrder: 0, active: true, multi, max, items: [{ id: "a", name: "A", price: 5000 }, { id: "b", name: "B", price: 5000 }] }) as ToppingGroup;

describe("topping nhiều phần", () => {
  it("gộp và đếm", () => {
    expect(toppingLabels(["Trân châu", "Thạch", "Trân châu"])).toEqual(["Trân châu x2", "Thạch"]);
    expect(groupToppings([])).toEqual([]);
    expect(toppingCount(["A", "B", "A"], "A")).toBe(2);
  });
  it("describeSelection gộp x2", () => {
    expect(describeSelection({ selectedSize: "L", selectedToppings: ["A", "A"] } as never)).toBe("Size L • + A x2");
  });
  it("addToppingUnit cho lặp, giới hạn tổng phần theo max", () => {
    let sel: string[] = [];
    sel = addToppingUnit(sel, group(true, 3), "A");
    sel = addToppingUnit(sel, group(true, 3), "A");
    sel = addToppingUnit(sel, group(true, 3), "B");
    expect(sel).toEqual(["A", "A", "B"]);
    expect(addToppingUnit(sel, group(true, 3), "A")).toEqual(["A", "A", "B"]);
  });
  it("nhóm chọn một chỉ giữ 1 phần", () => {
    expect(addToppingUnit(["A"], group(false, 0), "B")).toEqual(["B"]);
  });
  it("removeToppingUnit bớt một phần", () => {
    expect(removeToppingUnit(["A", "A", "B"], "A")).toEqual(["A", "B"]);
    expect(removeToppingUnit(["A"], "Z")).toEqual(["A"]);
  });
});

const ticketVal = (items: unknown[], extra: Record<string, unknown> = {}) => ({
  k1: { tableName: "Bàn 1", orderCode: "OD-1", itemsJson: JSON.stringify(items), timestamp: 100, isDone: false, ...extra },
});
const item = (name: string, quantity: number, extra: Record<string, unknown> = {}) => ({ productId: 1, name, price: 1000, quantity, ...extra });

describe("phiếu bếp huỷ món", () => {
  it("parse: topping tách dòng, số phần huỷ", () => {
    const t = parseKitchenTickets("S", ticketVal([item("Trà", 3, { selectedSize: "L", selectedToppings: ["A", "A"], cancelledQty: 1 })]))[0];
    expect(t.lines[0].options).toBe("Size L");
    expect(t.lines[0].toppings).toEqual([{ name: "A", count: 2 }]);
    expect(t.lines[0].cancelledQty).toBe(1);
    expect(t.hasCancellation).toBe(true);
    expect(t.fullyCancelled).toBe(false);
  });
  it("huỷ một phần", () => {
    const upd = planKitchenCancel({ storeCode: "S", kitchenVal: ticketVal([item("Trà", 3)]), tableName: "Bàn 1", orderCode: "OD-1", line: item("Trà", 3), removeQty: 2, now: 5 });
    const items = JSON.parse(upd["stores/S/kitchen_orders/k1/itemsJson"] as string);
    expect(items[0].cancelledQty).toBe(2);
    expect(upd["stores/S/kitchen_orders/k1/cancelledAt"]).toBe(5);
  });
  it("không khớp topping thì không huỷ", () => {
    const upd = planKitchenCancel({ storeCode: "S", kitchenVal: ticketVal([item("Trà", 1, { selectedToppings: ["A"] })]), tableName: "Bàn 1", line: item("Trà", 1), removeQty: 1, now: 5 });
    expect(upd).toEqual({});
  });
  it("bỏ qua phiếu đã xong / bàn khác / mã đơn khác", () => {
    const base = { storeCode: "S", line: item("Trà", 1), removeQty: 1, now: 5 };
    expect(planKitchenCancel({ ...base, kitchenVal: ticketVal([item("Trà", 1)], { isDone: true }), tableName: "Bàn 1" })).toEqual({});
    expect(planKitchenCancel({ ...base, kitchenVal: ticketVal([item("Trà", 1)]), tableName: "Bàn 2" })).toEqual({});
    expect(planKitchenCancel({ ...base, kitchenVal: ticketVal([item("Trà", 1)]), tableName: "Bàn 1", orderCode: "OD-9" })).toEqual({});
  });
  it("huỷ cả đơn", () => {
    const upd = planKitchenCancel({ storeCode: "S", kitchenVal: ticketVal([item("A", 2), item("B", 1)]), tableName: "Bàn 1", line: null, removeQty: 0, now: 5 });
    const items = JSON.parse(upd["stores/S/kitchen_orders/k1/itemsJson"] as string);
    expect(items.map((i: { cancelledQty: number }) => i.cancelledQty)).toEqual([2, 1]);
  });
});
