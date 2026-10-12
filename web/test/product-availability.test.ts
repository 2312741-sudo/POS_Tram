import { describe, it, expect } from "vitest";
import { isProductAvailable, isSoldOutStale, nextSoldOutReset, soldOutPatch, soldOutNote } from "../lib/product-availability";
import { buildCopyPlan, type MenuSnapshot } from "../lib/menu-copy";

const at = (y: number, mo: number, d: number, h = 0, mi = 0) => new Date(y, mo - 1, d, h, mi).getTime();

describe("isProductAvailable", () => {
  const now = at(2026, 10, 12, 14, 0);
  it("thiếu trường / isAvailable true => còn bán", () => {
    expect(isProductAvailable({}, now)).toBe(true);
    expect(isProductAvailable(null, now)).toBe(true);
    expect(isProductAvailable({ isAvailable: true }, now)).toBe(true);
    expect(isProductAvailable({ isAvailable: true, soldOutUntil: now + 1000 }, now)).toBe(true);
  });
  it("dữ liệu cũ isAvailable=false không có soldOutUntil => hết vô thời hạn", () => {
    expect(isProductAvailable({ isAvailable: false }, now)).toBe(false);
    expect(isProductAvailable({ isAvailable: false, soldOutUntil: null }, now)).toBe(false);
  });
  it("trước/sau soldOutUntil", () => {
    expect(isProductAvailable({ isAvailable: false, soldOutUntil: now + 1 }, now)).toBe(false);
    expect(isProductAvailable({ isAvailable: false, soldOutUntil: now }, now)).toBe(true);
    expect(isProductAvailable({ isAvailable: false, soldOutUntil: now - 1 }, now)).toBe(true);
    expect(isSoldOutStale({ isAvailable: false, soldOutUntil: now - 1 }, now)).toBe(true);
    expect(isSoldOutStale({ isAvailable: false }, now)).toBe(false);
  });
});

describe("nextSoldOutReset / soldOutPatch", () => {
  it("sau 05:00 => 05:00 ngày mai; trước 05:00 => 05:00 hôm nay; qua cuối tháng", () => {
    expect(nextSoldOutReset(at(2026, 10, 12, 14))).toBe(at(2026, 10, 13, 5));
    expect(nextSoldOutReset(at(2026, 10, 12, 2))).toBe(at(2026, 10, 12, 5));
    expect(nextSoldOutReset(at(2026, 10, 12, 5))).toBe(at(2026, 10, 13, 5));
    expect(nextSoldOutReset(at(2026, 10, 31, 23))).toBe(at(2026, 11, 1, 5));
  });
  it("patch hết / bật lại", () => {
    const now = at(2026, 10, 12, 14);
    expect(soldOutPatch({ soldOut: true, by: "bep", now })).toEqual({ isAvailable: false, soldOutAt: now, soldOutBy: "bep", soldOutUntil: null });
    expect(soldOutPatch({ soldOut: true, by: "bep", now, untilNextReset: true }).soldOutUntil).toBe(at(2026, 10, 13, 5));
    expect(soldOutPatch({ soldOut: false, by: "bep", now })).toEqual({ isAvailable: true, soldOutAt: null, soldOutBy: null, soldOutUntil: null });
    expect((soldOutPatch({ soldOut: true, by: "x".repeat(80), now }).soldOutBy as string).length).toBe(64);
  });
  it("ghi chú hiển thị", () => {
    expect(soldOutNote({ isAvailable: true })).toBe("");
    expect(soldOutNote({ isAvailable: false, soldOutAt: at(2026, 10, 12, 9, 5), soldOutBy: "bep", soldOutUntil: 1 })).toBe("Hết từ 09:05 · bep · tự bật lại sáng mai");
  });
});

describe("sao chép thực đơn xóa trạng thái báo hết", () => {
  const source: MenuSnapshot = {
    products: { "Trà đào": { id: 2, name: "Trà đào", price: 30000, category: "Trà", isAvailable: false, soldOutAt: 5, soldOutBy: "bep", soldOutUntil: 9 } },
    categories: { Trà: { name: "Trà" } },
    notes: {},
  };
  it("tạo mới: isAvailable true, không còn soldOut*", () => {
    const plan = buildCopyPlan({ source, target: { products: {}, categories: {}, notes: {} }, options: { conflict: "skip" } });
    const p = Object.entries(plan.updates).find(([k]) => k.startsWith("products/") && k.split("/").length === 2)![1] as Record<string, unknown>;
    expect(p.isAvailable).toBe(true);
    expect(p).not.toHaveProperty("soldOutAt");
    expect(p).not.toHaveProperty("soldOutBy");
    expect(p).not.toHaveProperty("soldOutUntil");
  });
  it("ghi đè: bật lại và xóa dấu vết ở món đích", () => {
    const target: MenuSnapshot = { products: { tda: { id: 7, name: "Trà đào", price: 1, category: "Trà", isAvailable: false, soldOutAt: 3 } }, categories: { Trà: { name: "Trà" } }, notes: {} };
    const plan = buildCopyPlan({ source, target, options: { conflict: "overwrite" } });
    expect(plan.updates["products/tda/isAvailable"]).toBe(true);
    expect(plan.updates["products/tda/soldOutAt"]).toBeNull();
    expect(plan.updates["products/tda/soldOutBy"]).toBeNull();
    expect(plan.updates["products/tda/soldOutUntil"]).toBeNull();
  });
});
