import { describe, it, expect } from "vitest";
import { scopeShifts, shiftOwnedBy, listShiftOwners } from "../lib/shift-scope";

const shifts = [
  { id: "1", staffUid: "uA", staffUsername: "admin", staffFullName: "Admin" },
  { id: "2", staffUid: "uB", staffUsername: "nv1", staffFullName: "NV 1" },
  { id: "3", staffUsername: "NV1", staffFullName: "NV 1" }, // ca cũ
];

describe("shift-scope", () => {
  it("nhân viên chỉ thấy ca của mình (kể cả ca cũ theo username)", () => {
    expect(scopeShifts(shifts, { uid: "uB", username: "nv1" }, false).map((s) => s.id)).toEqual(["2", "3"]);
  });
  it("bỏ qua bộ lọc tài khoản khi không có quyền xem tất cả", () => {
    expect(scopeShifts(shifts, { uid: "uB", username: "nv1" }, false, "admin").map((s) => s.id)).toEqual(["2", "3"]);
  });
  it("quản lý thấy tất cả và lọc theo tài khoản", () => {
    expect(scopeShifts(shifts, { uid: "uA", username: "admin" }, true).length).toBe(3);
    expect(scopeShifts(shifts, { uid: "uA", username: "admin" }, true, "nv1").map((s) => s.id)).toEqual(["2", "3"]);
  });
  it("uid khác thì không nhận ca dù trùng username", () => {
    expect(shiftOwnedBy({ staffUid: "uA", staffUsername: "admin" }, { uid: "uX", username: "admin" })).toBe(false);
  });
  it("liệt kê tài khoản có ca", () => {
    expect(listShiftOwners(shifts).map((o) => o.value)).toEqual(["admin", "nv1", "NV1"]);
  });
});
