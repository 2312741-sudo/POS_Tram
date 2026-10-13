import { describe, it, expect } from "vitest";
import { ASSIGNABLE_ROLES, buildAssignedProfile, canAssignAcrossStores, countIndexedStores, isAssignableRole, shouldDisableAuthAccount } from "./multiStore";

const owner = { username: "chu", roleId: "ROLE_OWNER", isActive: true };
const root = { username: "admin", roleId: "ROLE_MANAGER", isRootOwner: true, isActive: true };
const manager = { username: "ql", roleId: "ROLE_MANAGER", isActive: true };

describe("nhân viên nhiều cửa hàng", () => {
  it("chỉ Chủ/Admin ở cả hai cửa hàng được gán", () => {
    expect(canAssignAcrossStores(owner, owner)).toBe(true);
    expect(canAssignAcrossStores(root, owner)).toBe(true);
    expect(canAssignAcrossStores(manager, owner)).toBe(false);
    expect(canAssignAcrossStores(owner, manager)).toBe(false);
    expect(canAssignAcrossStores(owner, null)).toBe(false);
    expect(canAssignAcrossStores({ ...owner, isActive: false }, owner)).toBe(false);
  });

  it("chỉ gán vai trò Quản lý / Nhân viên / Bếp, không gán Chủ", () => {
    expect([...ASSIGNABLE_ROLES]).toEqual(["ROLE_MANAGER", "ROLE_STAFF", "ROLE_KITCHEN"]);
    expect(isAssignableRole("ROLE_STAFF")).toBe(true);
    expect(isAssignableRole("ROLE_OWNER")).toBe(false);
    expect(isAssignableRole("owner")).toBe(false);
    expect(isAssignableRole(undefined)).toBe(false);
  });

  it("hồ sơ ở cửa hàng mới: cùng uid/username, vai trò mới, không chép quyền riêng", () => {
    const p = buildAssignedProfile({ username: "an", fullName: "An", roleId: "ROLE_STAFF", customPermissions: ["X"], phone: "09" }, "uid1", "ROLE_MANAGER", { username: "chu", storeCode: "A" }, 5);
    expect(p).toMatchObject({ uid: "uid1", username: "an", roleId: "ROLE_MANAGER", isRootOwner: false, isActive: true, customPermissions: [], assignedFromStore: "A", assignedBy: "chu", phone: "09" });
    expect(p).not.toHaveProperty("password");
  });

  it("khóa tài khoản đăng nhập chỉ khi thuộc 1 cửa hàng", () => {
    expect(countIndexedStores({ A: true, B: true, C: false })).toBe(2);
    expect(countIndexedStores(null)).toBe(0);
    expect(shouldDisableAuthAccount(1)).toBe(true);
    expect(shouldDisableAuthAccount(2)).toBe(false);
  });
});
