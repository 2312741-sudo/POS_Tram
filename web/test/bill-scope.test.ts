import { describe, it, expect } from "vitest";
import { billOwnedBy, scopeOwnBills } from "../lib/bill-scope";

describe("đơn của tôi", () => {
  const who = { uid: "u1", username: "Nv1" };
  it("người thu tiền (uid hoặc username)", () => {
    expect(billOwnedBy({ staffUid: "u1" }, who)).toBe(true);
    expect(billOwnedBy({ staffUid: "u2", staffUsername: "nv1" }, who)).toBe(false); // có uid thì so uid
    expect(billOwnedBy({ staffUsername: "NV1" }, who)).toBe(true);
    expect(billOwnedBy({ staffUsername: "nv2" }, who)).toBe(false);
  });
  it("người gọi món / gửi bếp dù không phải người thu tiền", () => {
    expect(billOwnedBy({ staffUsername: "ql", actionLogs: [{ action: "SEND_KITCHEN", staffUsername: "nv1" }] }, who)).toBe(true);
    expect(billOwnedBy({ staffUsername: "ql", actionLogs: [{ action: "DELETE_ITEM", staffUsername: "nv1" }] }, who)).toBe(false);
    expect(billOwnedBy({ staffUsername: "ql", items: [{ orderedBy: "nv1" }] }, who)).toBe(true);
  });
  it("không có tài khoản thì không thấy gì; lọc danh sách", () => {
    expect(billOwnedBy({ staffUsername: "nv1" }, {})).toBe(false);
    expect(scopeOwnBills([{ staffUsername: "nv1" }, { staffUsername: "x" }], who)).toHaveLength(1);
  });
});
