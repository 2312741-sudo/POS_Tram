import { describe, it, expect } from "vitest";
import {
  addToEarnQueue,
  earnQueueKey,
  earnWithRetry,
  listEarnQueueKeys,
  processEarnQueue,
  readEarnQueue,
  removeFromEarnQueue,
  type KeyValueStorage,
} from "../lib/loyalty-earn-queue";

function mem() {
  const m = new Map<string, string>();
  const s: KeyValueStorage & { length: number; key(i: number): string | null } = {
    getItem: (k) => m.get(k) ?? null,
    setItem: (k, v) => void m.set(k, v),
    get length() { return m.size; },
    key: (i) => [...m.keys()][i] ?? null,
  };
  return s;
}

describe("hàng đợi thử lại tích điểm", () => {
  const key = earnQueueKey("thu", "TRAM01");
  it("khóa theo người dùng + chi nhánh", () => {
    expect(key).not.toBe(earnQueueKey("khac", "TRAM01"));
    expect(key).not.toBe(earnQueueKey("thu", "TRAM02"));
  });
  it("thêm không trùng, xóa theo hóa đơn", () => {
    const s = mem();
    addToEarnQueue(s, key, { billId: "b1", billCode: "HD-1" }, 1);
    addToEarnQueue(s, key, { billId: "b1", error: "x" }, 2);
    addToEarnQueue(s, key, { billId: "b2" }, 3);
    expect(readEarnQueue(s, key).map((e) => e.billId)).toEqual(["b1", "b2"]);
    removeFromEarnQueue(s, key, "b1");
    expect(readEarnQueue(s, key).map((e) => e.billId)).toEqual(["b2"]);
  });
  it("dữ liệu hỏng / không có storage không làm vỡ", () => {
    const s = mem();
    s.setItem(key, "{không phải json");
    expect(readEarnQueue(s, key)).toEqual([]);
    expect(readEarnQueue(null, key)).toEqual([]);
    expect(() => addToEarnQueue(null, key, { billId: "b" })).not.toThrow();
  });
  it("processEarnQueue: thành công thì bỏ, thất bại thì giữ và tăng số lần thử", async () => {
    const s = mem();
    addToEarnQueue(s, key, { billId: "ok" });
    addToEarnQueue(s, key, { billId: "bad" });
    const r = await processEarnQueue(s, key, async (id) => {
      if (id === "bad") throw new Error("mạng");
    });
    expect(r).toEqual({ done: ["ok"], failed: ["bad"] });
    const left = readEarnQueue(s, key);
    expect(left).toHaveLength(1);
    expect(left[0]).toMatchObject({ billId: "bad", attempts: 1, error: "mạng" });
    await processEarnQueue(s, key, async () => undefined);
    expect(readEarnQueue(s, key)).toEqual([]);
  });
  it("earnWithRetry: lỗi → vào hàng đợi và báo ok=false; thành công → không vào", async () => {
    const s = mem();
    expect(await earnWithRetry(s, key, { billId: "b1" }, async () => undefined)).toEqual({ ok: true });
    expect(readEarnQueue(s, key)).toEqual([]);
    expect(await earnWithRetry(s, key, { billId: "b2", billCode: "HD-2" }, async () => { throw new Error("down"); })).toEqual({ ok: false });
    expect(readEarnQueue(s, key)[0]).toMatchObject({ billId: "b2", billCode: "HD-2", error: "down" });
  });
  it("liệt kê các hàng đợi của một người dùng", () => {
    const s = mem();
    addToEarnQueue(s, earnQueueKey("thu", "A"), { billId: "1" });
    addToEarnQueue(s, earnQueueKey("thu", "B"), { billId: "2" });
    addToEarnQueue(s, earnQueueKey("khac", "A"), { billId: "3" });
    s.setItem("other", "x");
    expect(listEarnQueueKeys(s, "thu").map((k) => k.storeCode).sort()).toEqual(["A", "B"]);
  });
});
