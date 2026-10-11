import { describe, it, expect } from "vitest";
import { callableErrorMessage, canResetStaffPassword, validateStaffPassword } from "../lib/staff-password";

const owner = { roleId: "ROLE_OWNER", isRootOwner: true };
const manager = { roleId: "ROLE_MANAGER" };
const staff = { roleId: "ROLE_STAFF" };

describe("validateStaffPassword", () => {
  it("khớp chính sách máy chủ (>= 6 ký tự)", () => {
    expect(validateStaffPassword("")).toMatch(/nhập/);
    expect(validateStaffPassword("12345")).toMatch(/tối thiểu 6/);
    expect(validateStaffPassword("123456")).toBeNull();
    expect(validateStaffPassword("x".repeat(129))).toMatch(/tối đa/);
  });
});

describe("canResetStaffPassword", () => {
  it("chủ quán đặt lại cho mọi người, trừ chủ gốc khác", () => {
    expect(canResetStaffPassword(owner, manager, false)).toBe(true);
    expect(canResetStaffPassword(owner, staff, false)).toBe(true);
    expect(canResetStaffPassword({ roleId: "ROLE_OWNER" }, owner, false)).toBe(false);
  });
  it("quản lý chỉ đặt lại cho nhân viên/bếp (cả mã cũ), không cho chủ hay quản lý khác", () => {
    expect(canResetStaffPassword(manager, staff, false)).toBe(true);
    expect(canResetStaffPassword(manager, { roleId: "cashier" }, false)).toBe(true);
    expect(canResetStaffPassword(manager, { roleId: "ROLE_KITCHEN" }, false)).toBe(true);
    expect(canResetStaffPassword(manager, { roleId: "manager_2" }, false)).toBe(false);
    expect(canResetStaffPassword({ roleId: "manager_1" }, owner, false)).toBe(false);
  });
  it("nhân viên không đặt lại cho người khác; tài khoản Chấm Công không có mật khẩu", () => {
    expect(canResetStaffPassword(staff, staff, false)).toBe(false);
    expect(canResetStaffPassword(owner, { roleId: "ROLE_STAFF", authProvider: "chamcong" }, false)).toBe(false);
    expect(canResetStaffPassword({ ...manager, isActive: false }, staff, false)).toBe(false);
    expect(canResetStaffPassword(null, staff, false)).toBe(false);
  });
});

describe("callableErrorMessage", () => {
  it("giữ nguyên thông báo tiếng Việt của máy chủ", () => {
    expect(callableErrorMessage({ code: "functions/permission-denied", message: "Bạn không có quyền." })).toBe("Bạn không có quyền.");
  });
  it("thay lỗi hạ tầng chung chung bằng thông báo dễ hiểu", () => {
    expect(callableErrorMessage({ code: "functions/internal", message: "internal" })).toMatch(/Không thực hiện/);
    expect(callableErrorMessage({ code: "functions/unavailable", message: "x" })).toMatch(/kết nối/);
    expect(callableErrorMessage({ code: "functions/unauthenticated", message: "x" })).toMatch(/đăng nhập lại/);
    expect(callableErrorMessage(null, "Lỗi")).toBe("Lỗi");
  });
});
