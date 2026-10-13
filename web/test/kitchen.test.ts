import { describe, it, expect } from "vitest";
import { buildMarkDoneUpdates, parseKitchenTickets, waitingMinutes } from "../lib/kitchen";

describe("màn hình bếp trên web", () => {
  const items = JSON.stringify([
    { name: "Trà đào", quantity: 2, note: "ít đá", selectedSize: "L", selectedSugar: "50% đường", selectedToppings: ["Kem Cheese"] },
    { name: "Bánh", quantity: 1 },
  ]);

  it("chỉ lấy phiếu chưa xong, cũ nhất trước, kèm tùy chọn món", () => {
    const t = parseKitchenTickets("T1", {
      b: { tableName: "Bàn 2", timestamp: 200, itemsJson: "[]", isDone: false },
      a: { tableName: "Bàn 1", orderCode: "OD-1", timestamp: 100, note: "gấp", orderedByName: "An", itemsJson: items },
      done: { tableName: "Bàn 3", timestamp: 50, isDone: true, itemsJson: "[]" },
      bad: "x",
    });
    expect(t.map((x) => x.key)).toEqual(["a", "b"]);
    expect(t[0]).toMatchObject({ tableName: "Bàn 1", orderCode: "OD-1", note: "gấp", orderedByName: "An" });
    expect(t[0].lines[0]).toEqual({ name: "Trà đào", quantity: 2, note: "ít đá", options: "Size L • 50% đường • + Kem Cheese" });
    expect(parseKitchenTickets("T1", null)).toEqual([]);
  });

  it("đánh dấu xong như POS và đếm phút chờ", () => {
    expect(buildMarkDoneUpdates("T1", "k1", 9)).toEqual({
      "stores/T1/kitchen_orders/k1/isDone": true,
      "stores/T1/kitchen_orders/k1/doneAt": 9,
      "stores/T1/kitchen_orders/k1/pickedUp": false,
    });
    expect(waitingMinutes({ timestamp: 0 }, 5 * 60000 + 10)).toBe(5);
    expect(waitingMinutes({ timestamp: 10 }, 0)).toBe(0);
  });
});
