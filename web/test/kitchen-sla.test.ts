import { describe, expect, it } from "vitest";
import {
  computeKitchenSla,
  formatDurationMs,
  kitchenGroupOfCategory,
  kitchenGroupLabel,
  KITCHEN_GROUP_DRINK,
  KITCHEN_GROUP_FOOD,
} from "../lib/kitchen-sla";

describe("kitchen-sla tests", () => {
  it("classifies categories into drink or food correctly", () => {
    expect(kitchenGroupOfCategory("Trà sữa")).toBe(KITCHEN_GROUP_DRINK);
    expect(kitchenGroupOfCategory("Cà phê")).toBe(KITCHEN_GROUP_DRINK);
    expect(kitchenGroupOfCategory("Bánh ngọt")).toBe(KITCHEN_GROUP_FOOD);
    expect(kitchenGroupOfCategory("Snack & Ăn vặt")).toBe(KITCHEN_GROUP_FOOD);
  });

  it("formats duration ms cleanly", () => {
    expect(formatDurationMs(0)).toBe("0 gi");
    expect(formatDurationMs(45000)).toBe("45 gi");
    expect(formatDurationMs(125000)).toBe("2 p 05 gi");
    expect(formatDurationMs(600000)).toBe("10 p 00 gi");
  });

  it("computes SLA and aggregates correctly", () => {
    const now = 1730000000000;
    const tickets = {
      t1: {
        tableName: "Bàn 1",
        orderCode: "OD-1",
        timestamp: now,
        doneAt: now + 10 * 60 * 1000, // 10m
        isDone: true,
        itemsJson: JSON.stringify([
          { name: "Trà sữa", quantity: 2, category: "Trà" },
          { name: "Bánh bông lan", quantity: 1, category: "Bánh" },
        ]),
      },
      t2: {
        tableName: "Bàn 2",
        orderCode: "OD-2",
        timestamp: now,
        doneAt: now + 25 * 60 * 1000, // 25m (late for 15m threshold)
        isDone: true,
        itemsJson: JSON.stringify([
          { name: "Cà phê đen", quantity: 1, category: "Cà phê" },
        ]),
      },
      t3_not_done: {
        tableName: "Bàn 3",
        timestamp: now,
        isDone: false,
      },
    };

    const summary = computeKitchenSla(tickets, now - 1000, now + 3600 * 1000, 15);

    expect(summary.orders.length).toBe(2);
    expect(summary.items.length).toBe(3);
    expect(summary.lateOrderCount).toBe(1); // OD-2 is 25m > 15m
    expect(summary.averageOrderMs).toBe(Math.round(((10 + 25) / 2) * 60 * 1000));
    expect(summary.maxOrderMs).toBe(25 * 60 * 1000);

    const drinkItem = summary.items.find((i) => i.itemName === "Trà sữa");
    expect(drinkItem?.group).toBe(KITCHEN_GROUP_DRINK);
    expect(drinkItem?.quantity).toBe(2);

    const foodItem = summary.items.find((i) => i.itemName === "Bánh bông lan");
    expect(foodItem?.group).toBe(KITCHEN_GROUP_FOOD);
  });
});
