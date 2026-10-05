import { describe, it, expect } from "vitest";
import {
  canCallerManageUsers,
  canCallerCreateRole,
  canCallerResetPassword,
  canCallerSetDisabled,
  normalizeUsername,
  buildSyntheticEmail,
} from "./permissions";

describe("Cloud Functions RBAC & Permissions Unit Tests", () => {
  const owner = { username: "admin", roleId: "owner", isRootOwner: true, isActive: true };
  const manager = { username: "ql1", roleId: "manager_1", isRootOwner: false, isActive: true };
  const cashier = { username: "thungan", roleId: "cashier", isRootOwner: false, isActive: true };
  const waiter = { username: "phucvu", roleId: "waiter", isRootOwner: false, isActive: true };
  const inactiveManager = { username: "ql_bi_khoa", roleId: "manager", isRootOwner: false, isActive: false };

  it("1. Phục vụ không có quyền quản lý người dùng", () => {
    expect(canCallerManageUsers(waiter)).toBe(false);
    expect(canCallerManageUsers(cashier)).toBe(false);
    expect(canCallerManageUsers(inactiveManager)).toBe(false);
    expect(canCallerManageUsers(owner)).toBe(true);
    expect(canCallerManageUsers(manager)).toBe(true);
  });

  it("2. Quản lý không được tạo tài khoản có vai trò Chủ quán", () => {
    expect(canCallerCreateRole(manager, "owner")).toBe(false);
    expect(canCallerCreateRole(manager, "ROLE_OWNER")).toBe(false);
    expect(canCallerCreateRole(manager, "cashier")).toBe(true);
    expect(canCallerCreateRole(manager, "waiter")).toBe(true);
    expect(canCallerCreateRole(owner, "owner")).toBe(true);
    expect(canCallerCreateRole(owner, "manager", true)).toBe(false); // Không ai tạo được root owner
  });

  it("3. Quản lý không được đặt lại mật khẩu cho Chủ quán gốc", () => {
    expect(canCallerResetPassword(manager, owner, false)).toBe(false);
    expect(canCallerResetPassword(owner, manager, false)).toBe(true);
    expect(canCallerResetPassword(owner, cashier, false)).toBe(true);
    expect(canCallerResetPassword(manager, cashier, false)).toBe(true);
    expect(canCallerResetPassword(manager, manager, true)).toBe(true); // Tự đặt lại mật khẩu của mình
  });

  it("4. Không ai được phép khóa Chủ quán gốc", () => {
    expect(canCallerSetDisabled(manager, owner, "owner_uid", "manager_uid")).toBe(false);
    expect(canCallerSetDisabled(owner, owner, "owner_uid", "owner_uid")).toBe(false); // Tự khóa mình -> false
    expect(canCallerSetDisabled(owner, cashier, "cashier_uid", "owner_uid")).toBe(true);
    expect(canCallerSetDisabled(manager, waiter, "waiter_uid", "manager_uid")).toBe(true);
  });

  it("5. Chuẩn hóa tên đăng nhập và sinh email khớp 100% tài liệu hợp đồng", () => {
    expect(normalizeUsername("  Trần Văn A 123 ")).toBe("tranvana123");
    expect(normalizeUsername("Đầu Bếp_01")).toBe("daubep_01");
    expect(buildSyntheticEmail("Lê Thu Ngân", "tram01")).toBe("lethungan.tram01@tram.local");
    expect(buildSyntheticEmail("admin", "TRAM02")).toBe("admin.tram02@tram.local");
  });
});
