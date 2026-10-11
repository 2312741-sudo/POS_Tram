import { describe, it, expect } from "vitest";
import { normalizePhone, planPull, pullKey } from "./pooledLoyalty";

describe("điểm dùng chung - kéo điểm từ chi nhánh khác", () => {
  const others = [
    { storeCode: "A", customerId: "a1", points: 30 },
    { storeCode: "B", customerId: "b1", points: 80 },
    { storeCode: "C", customerId: "c1", points: 0 },
  ];

  it("chuẩn hóa SĐT", () => {
    expect(normalizePhone("+84 912 345 678")).toBe("0912345678");
    expect(normalizePhone("84912345678")).toBe("0912345678");
    expect(normalizePhone("abc")).toBeNull();
    expect(normalizePhone(undefined)).toBeNull();
  });

  it("kéo từ chi nhánh nhiều điểm nhất trước, bỏ qua chi nhánh 0 điểm", () => {
    const r = planPull(others, 100);
    if ("error" in r) throw new Error(r.error);
    expect(r.allocations.map((a) => [a.storeCode, a.take, a.after])).toEqual([["B", 80, 0], ["A", 20, 10]]);
  });

  it("từ chối khi không đủ hoặc số điểm sai", () => {
    expect(planPull(others, 111)).toHaveProperty("error");
    expect(planPull(others, 0)).toHaveProperty("error");
    expect(planPull(others, 2.5)).toHaveProperty("error");
  });

  it("khóa idempotent an toàn cho RTDB", () => {
    expect(pullKey("bill_1.2/3")).toBe("pull_bill_1_2_3");
  });
});
