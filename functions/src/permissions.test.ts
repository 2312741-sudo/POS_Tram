import { describe, it, expect } from "vitest";
import {
  canCallerManageUsers,
  canCallerCreateRole,
  canCallerResetPassword,
  canCallerSetDisabled,
  normalizeUsername,
  buildSyntheticEmail,
  normalizeRoleId,
  isManagerRole,
  isStaffRole,
  resolveStaffAuthUid,
  isChamCongAccount,
  sanitizeCustomPermissions,
  OWNER_GRANT_ONLY_PERMISSIONS,
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
    expect(canCallerResetPassword(manager, { roleId: "ROLE_MANAGER" }, false)).toBe(false); // không đụng Quản lý khác
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

  it("6. normalizeRoleId gộp Quản lý 1/2 → ROLE_MANAGER, Thu ngân/Phục vụ → ROLE_STAFF", () => {
    for (const r of ["manager", "manager_1", "manager_2", "ROLE_MANAGER_1", "ROLE_MANAGER_2", "Manager-1", "ql"]) {
      expect(normalizeRoleId(r)).toBe("ROLE_MANAGER");
      expect(isManagerRole(r)).toBe(true);
    }
    for (const r of ["cashier", "ROLE_CASHIER", "employee", "waiter", "ROLE_WAITER", "staff", "ROLE_STAFF", "Waiter"]) {
      expect(normalizeRoleId(r)).toBe("ROLE_STAFF");
      expect(isStaffRole(r)).toBe(true);
    }
    expect(normalizeRoleId("ROLE_KITCHEN")).toBe("ROLE_KITCHEN");
    expect(normalizeRoleId("owner")).toBe("owner");
    expect(isStaffRole("ROLE_KITCHEN")).toBe(false);
    expect(normalizeRoleId(undefined)).toBe("");
  });

  it("7. Ma trận đặt lại mật khẩu / khóa: Chủ → mọi người (trừ chủ gốc), Quản lý → Nhân viên/Bếp", () => {
    const staff = { roleId: "ROLE_STAFF" };
    const kitchen = { roleId: "ROLE_KITCHEN" };
    const otherOwner = { roleId: "ROLE_OWNER" };
    expect(canCallerResetPassword(owner, staff, false)).toBe(true);
    expect(canCallerResetPassword(owner, otherOwner, false)).toBe(true);
    expect(canCallerResetPassword(otherOwner, owner, false)).toBe(false); // chủ gốc chỉ tự đặt lại
    expect(canCallerResetPassword(manager, kitchen, false)).toBe(true);
    expect(canCallerResetPassword(manager, staff, false)).toBe(true);
    expect(canCallerResetPassword(manager, otherOwner, false)).toBe(false);
    expect(canCallerResetPassword(staff, kitchen, false)).toBe(false);
    expect(canCallerResetPassword(kitchen, kitchen, true)).toBe(true);
    expect(canCallerResetPassword({ ...manager, isActive: false }, staff, false)).toBe(false);
    expect(canCallerSetDisabled(manager, { roleId: "manager_2" }, "m2", "m1")).toBe(false);
  });

  it("8. Hồ sơ cũ khóa theo tên đăng nhập: uid thật lấy từ trường uid, không có thì dùng khóa nút", () => {
    expect(resolveStaffAuthUid("thungan", { uid: "AbC123" })).toBe("AbC123");
    expect(resolveStaffAuthUid("thungan", {})).toBe("thungan");
    expect(resolveStaffAuthUid("thungan", { uid: "  " })).toBe("thungan");
    expect(isChamCongAccount("cc_x", {})).toBe(true);
    expect(isChamCongAccount("u1", { authProvider: "chamcong" })).toBe(true);
    expect(isChamCongAccount("u1", {})).toBe(false);
  });
});

describe("Quyền chỉ Chủ quán được cấp (Quản lý không được hủy/xóa đơn, xem nhật ký trừ khi Chủ cấp)", () => {
  const owner = { roleId: "ROLE_OWNER", isActive: true };
  const rootOwner = { roleId: "x", isRootOwner: true };
  const manager = { roleId: "ROLE_MANAGER_1", isActive: true };

  it("danh sách quyền Chủ-cấp-riêng gồm hủy hóa đơn, hủy món đã gửi bếp, xem/xuất nhật ký thao tác", () => {
    expect([...OWNER_GRANT_ONLY_PERMISSIONS].sort()).toEqual(["CANCEL_BILL", "CANCEL_KITCHEN_ITEM", "EXPORT_AUDIT_LOGS", "VIEW_AUDIT_LOGS"]);
  });

  it("Chủ quán cấp được mọi quyền khi tạo tài khoản", () => {
    expect(sanitizeCustomPermissions(owner, ["CANCEL_BILL", "VIEW_AUDIT_LOGS", "EXPORT_CODES"])).toEqual(["CANCEL_BILL", "VIEW_AUDIT_LOGS", "EXPORT_CODES"]);
    expect(sanitizeCustomPermissions(rootOwner, ["CANCEL_BILL"])).toEqual(["CANCEL_BILL"]);
  });

  it("Quản lý bị loại các quyền Chủ-cấp-riêng; quyền thường giữ nguyên; bỏ trùng và giá trị lạ", () => {
    expect(
      sanitizeCustomPermissions(manager, ["CANCEL_BILL", "CANCEL_KITCHEN_ITEM", "VIEW_AUDIT_LOGS", "EXPORT_AUDIT_LOGS", "VIEW_REPORTS", "VIEW_REPORTS", 5, "", null])
    ).toEqual(["VIEW_REPORTS"]);
    expect(sanitizeCustomPermissions(manager, undefined)).toEqual([]);
    expect(sanitizeCustomPermissions(null, ["CANCEL_BILL"])).toEqual([]);
  });
});

