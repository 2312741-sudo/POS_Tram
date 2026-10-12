import { describe, it, expect } from "vitest";
import { normalizeRoleId, roleLabel, isManagerRoleId, isStaffRoleId, ASSIGNABLE_ROLES, STAFF_ROLE_LABEL } from "../lib/roles";
import { ROLE_PERMISSIONS } from "../lib/auth";
import { PERMISSION_CATALOG, ACTION_CATALOG } from "../lib/permission-catalog";

describe("normalizeRoleId", () => {
  it("gộp mọi mã Quản lý cũ → ROLE_MANAGER", () => {
    for (const r of ["manager", "manager_1", "manager_2", "ROLE_MANAGER", "ROLE_MANAGER_1", "ROLE_MANAGER_2", "Manager-1", " ql2 "]) {
      expect(normalizeRoleId(r)).toBe("ROLE_MANAGER");
      expect(isManagerRoleId(r)).toBe(true);
    }
  });
  it("gộp Thu ngân / Phục vụ / employee → ROLE_STAFF", () => {
    for (const r of ["cashier", "ROLE_CASHIER", "employee", "waiter", "ROLE_WAITER", "STAFF", "role_staff"]) {
      expect(normalizeRoleId(r)).toBe("ROLE_STAFF");
      expect(isStaffRoleId(r)).toBe(true);
    }
  });
  it("giữ Chủ quán và Bếp", () => {
    expect(normalizeRoleId("owner")).toBe("ROLE_OWNER");
    expect(normalizeRoleId("chu")).toBe("ROLE_OWNER");
    expect(normalizeRoleId("kitchen")).toBe("ROLE_KITCHEN");
    expect(normalizeRoleId("ROLE_KITCHEN")).toBe("ROLE_KITCHEN");
    expect(normalizeRoleId("CUSTOM")).toBe("CUSTOM");
    expect(normalizeRoleId(undefined)).toBe("");
  });
  it("nhãn hiển thị chỉ còn Quản lý / Nhân viên", () => {
    expect(roleLabel("ROLE_MANAGER_1")).toBe("Quản lý");
    expect(roleLabel("ROLE_MANAGER_2")).toBe("Quản lý");
    expect(roleLabel("ROLE_CASHIER")).toBe(STAFF_ROLE_LABEL);
    expect(roleLabel("ROLE_WAITER")).toBe(STAFF_ROLE_LABEL);
    const labels = ASSIGNABLE_ROLES.map((r) => r.label).join("|");
    expect(labels).not.toMatch(/Quản lý [12]|Thu ngân\b(?! \/)|Phục vụ\b(?! \))/);
  });
});

describe("danh mục quyền & bảng quyền mặc định", () => {
  const keys = new Set(PERMISSION_CATALOG.map((p) => p.key));
  it("mã quyền không trùng và có đủ nhãn, nhóm, mô tả", () => {
    expect(keys.size).toBe(PERMISSION_CATALOG.length);
    for (const p of PERMISSION_CATALOG) {
      expect(p.label.length).toBeGreaterThan(0);
      expect(p.category.length).toBeGreaterThan(0);
      expect(p.description.length).toBeGreaterThan(0);
    }
  });
  it("mọi quyền trong bảng vai trò và trong mã hành động đều có trong danh mục", () => {
    for (const [role, perms] of Object.entries(ROLE_PERMISSIONS)) {
      for (const p of perms) expect(keys.has(p), `${role}:${p}`).toBe(true);
    }
    for (const a of ACTION_CATALOG) if (a.permission) expect(keys.has(a.permission), a.code).toBe(true);
  });
  it("chỉ 4 mã vai trò chuẩn; Quản lý ⊇ hợp QL1 + QL2; có COPY_MENU", () => {
    expect(Object.keys(ROLE_PERMISSIONS).sort()).toEqual(["ROLE_KITCHEN", "ROLE_MANAGER", "ROLE_OWNER", "ROLE_STAFF"]);
    const mgr = new Set(ROLE_PERMISSIONS.ROLE_MANAGER);
    for (const p of ["OPEN_TABLE", "MANAGE_CASH_SHIFT", "VIEW_REPORTS", "ADJUST_CASH_SHIFT", "MANAGE_PROMOTIONS", "COPY_MENU"]) {
      expect(mgr.has(p), p).toBe(true);
    }
    expect(mgr.has("MANAGE_USERS")).toBe(false);
    expect(ROLE_PERMISSIONS.ROLE_OWNER.length).toBe(PERMISSION_CATALOG.length);
  });
  it("Nhân viên (Thu ngân ∪ Phục vụ) giữ đủ quyền Thu ngân cũ", () => {
    const staff = new Set(ROLE_PERMISSIONS.ROLE_STAFF);
    for (const p of ["VIEW_MENU", "OPEN_TABLE", "CHANGE_TABLE", "SEND_KITCHEN", "CREATE_BILL", "APPLY_PROMOTION", "PRINT_BILL"]) {
      expect(staff.has(p), p).toBe(true);
    }
    expect(staff.has("CANCEL_BILL")).toBe(false);
  });
});
