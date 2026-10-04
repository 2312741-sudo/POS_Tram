import { describe, it, expect } from "vitest";
import {
  normalizeUsername,
  validateUsername,
  generateEmail,
  hasPermission,
  canAccessRoute,
  User,
} from "../lib/auth";

describe("Chuẩn hóa và Xác thực Username (AUTH_CONTRACT Section 2.3)", () => {
  it("normalizeUsername loại bỏ khoảng trắng và chuyển thành chữ thường", () => {
    expect(normalizeUsername("  thungan1  ")).toBe("thungan1");
    expect(normalizeUsername("ThuNgan_01")).toBe("thungan_01");
    expect(normalizeUsername("  ADMIN  ")).toBe("admin");
  });

  it("validateUsername chấp nhận các username hợp lệ", () => {
    expect(validateUsername("thungan1").valid).toBe(true);
    expect(validateUsername("admin").valid).toBe(true);
    expect(validateUsername("bep_truong").valid).toBe(true);
    expect(validateUsername("ql-kho").valid).toBe(true);
    expect(validateUsername("nv_123").valid).toBe(true);
  });

  it("validateUsername từ chối username có khoảng trắng", () => {
    const result = validateUsername("thu ngan");
    expect(result.valid).toBe(false);
    expect(result.error).toContain("khoảng trắng");
  });

  it("validateUsername từ chối username có dấu chấm", () => {
    const result = validateUsername("thu.ngan");
    expect(result.valid).toBe(false);
    expect(result.error).toContain("dấu chấm");
  });

  it("validateUsername từ chối ký tự tiếng Việt có dấu", () => {
    const result = validateUsername("thu_ngân");
    expect(result.valid).toBe(false);
    expect(result.error).toBeDefined();
  });

  it("validateUsername từ chối username quá ngắn (< 3 ký tự)", () => {
    const result = validateUsername("ab");
    expect(result.valid).toBe(false);
    expect(result.error).toContain("ít nhất 3 ký tự");
  });

  it("validateUsername từ chối username quá dài (> 30 ký tự)", () => {
    const result = validateUsername("a".repeat(31));
    expect(result.valid).toBe(false);
    expect(result.error).toContain("tối đa 30 ký tự");
  });

  it("validateUsername từ chối ký tự đặc biệt không hợp lệ (@, #, $, %)", () => {
    expect(validateUsername("user@123").valid).toBe(false);
    expect(validateUsername("admin#1").valid).toBe(false);
  });
});

describe("Quy tắc sinh Email Firebase Auth (AUTH_CONTRACT Section 2.3)", () => {
  it("sinh email đúng quy ước {username}.{storeCode}@tram.local", () => {
    expect(generateEmail("thungan1", "TRAM01")).toBe("thungan1.tram01@tram.local");
    expect(generateEmail("admin", "TRAM01")).toBe("admin.tram01@tram.local");
    expect(generateEmail("bep_truong", "TRAM02")).toBe("bep_truong.tram02@tram.local");
    expect(generateEmail("ql-kho", "tram01")).toBe("ql-kho.tram01@tram.local");
  });
});

describe("Ma trận phân quyền RBAC & Quyền riêng (AUTH_CONTRACT Section 4.2)", () => {
  const createMockUser = (partial: Partial<User>): User => ({
    id: "uid_123",
    uid: "uid_123",
    username: "testuser",
    fullName: "Test User",
    roleId: "ROLE_WAITER",
    role: "ROLE_WAITER",
    isRootOwner: false,
    isActive: true,
    storeCode: "TRAM01",
    ...partial,
  });

  it("Chủ quán (isRootOwner hoặc ROLE_OWNER) có mọi quyền (Sovereign Owner Rule)", () => {
    const rootOwner = createMockUser({ isRootOwner: true, roleId: "ROLE_OWNER" });
    expect(hasPermission(rootOwner, "MANAGE_USERS")).toBe(true);
    expect(hasPermission(rootOwner, "DELETE_MENU")).toBe(true);
    expect(hasPermission(rootOwner, "MANAGE_STORE_SETTINGS")).toBe(true);
    expect(hasPermission(rootOwner, "VIEW_AUDIT_LOGS")).toBe(true);
    expect(hasPermission(rootOwner, "ANY_CUSTOM_PERMISSION")).toBe(true);
  });

  it("Quản lý 1 (ROLE_MANAGER_1) có quyền điều hành và kiểm soát, nhưng không có MANAGE_USERS", () => {
    const manager1 = createMockUser({ roleId: "ROLE_MANAGER_1" });
    expect(hasPermission(manager1, "VIEW_MENU")).toBe(true);
    expect(hasPermission(manager1, "EDIT_MENU")).toBe(true);
    expect(hasPermission(manager1, "CHANGE_PRICE")).toBe(true);
    expect(hasPermission(manager1, "VIEW_AUDIT_LOGS")).toBe(true);
    expect(hasPermission(manager1, "MANUAL_DISCOUNT")).toBe(true);
    expect(hasPermission(manager1, "VIEW_INVENTORY")).toBe(true);

    // Bị giới hạn
    expect(hasPermission(manager1, "MANAGE_USERS")).toBe(false);
    expect(hasPermission(manager1, "DELETE_MENU")).toBe(false);
    expect(hasPermission(manager1, "MANAGE_STORE_SETTINGS")).toBe(false);
  });

  it("Quản lý 2 (ROLE_MANAGER_2) chỉ có quyền giám sát ca và xem báo cáo cơ bản", () => {
    const manager2 = createMockUser({ roleId: "ROLE_MANAGER_2" });
    expect(hasPermission(manager2, "VIEW_MENU")).toBe(true);
    expect(hasPermission(manager2, "OPEN_TABLE")).toBe(true);
    expect(hasPermission(manager2, "VIEW_REPORTS")).toBe(true);
    expect(hasPermission(manager2, "MANAGE_CASH_SHIFT")).toBe(true);

    // Không có quyền nhạy cảm
    expect(hasPermission(manager2, "MANAGE_USERS")).toBe(false);
    expect(hasPermission(manager2, "VIEW_AUDIT_LOGS")).toBe(false);
    expect(hasPermission(manager2, "MANUAL_DISCOUNT")).toBe(false);
    expect(hasPermission(manager2, "VIEW_INVENTORY")).toBe(false);
  });

  it("Nhân viên thường có thể được cấp quyền riêng qua customPermissions", () => {
    const staff = createMockUser({
      roleId: "ROLE_CASHIER",
      customPermissions: ["MANUAL_DISCOUNT", "VIEW_AUDIT_LOGS"],
    });
    expect(hasPermission(staff, "MANUAL_DISCOUNT")).toBe(true);
    expect(hasPermission(staff, "VIEW_AUDIT_LOGS")).toBe(true);
    expect(hasPermission(staff, "MANAGE_USERS")).toBe(false);
  });
});

describe("Bảo vệ truy cập đường dẫn Web Admin (canAccessRoute)", () => {
  const createMockUser = (roleId: string, isRootOwner = false, customPermissions: string[] = []): User => ({
    id: "uid_123",
    uid: "uid_123",
    username: "user1",
    fullName: "User 1",
    roleId,
    role: roleId,
    isRootOwner,
    customPermissions,
    isActive: true,
    storeCode: "TRAM01",
  });

  it("Chủ quán có thể truy cập mọi trang", () => {
    const owner = createMockUser("ROLE_OWNER", true);
    expect(canAccessRoute(owner, "/dashboard")).toBe(true);
    expect(canAccessRoute(owner, "/dashboard/users")).toBe(true);
    expect(canAccessRoute(owner, "/dashboard/stores")).toBe(true);
    expect(canAccessRoute(owner, "/dashboard/audit")).toBe(true);
    expect(canAccessRoute(owner, "/dashboard/revenue")).toBe(true);
  });

  it("Quản lý 1 truy cập được báo cáo & nhật ký nhưng KHÔNG vào được trang người dùng & cài đặt chi nhánh", () => {
    const manager1 = createMockUser("ROLE_MANAGER_1");
    expect(canAccessRoute(manager1, "/dashboard")).toBe(true);
    expect(canAccessRoute(manager1, "/dashboard/audit")).toBe(true);
    expect(canAccessRoute(manager1, "/dashboard/inventory")).toBe(true);
    expect(canAccessRoute(manager1, "/dashboard/revenue")).toBe(true);

    // Bị chặn
    expect(canAccessRoute(manager1, "/dashboard/users")).toBe(false);
    expect(canAccessRoute(manager1, "/dashboard/stores")).toBe(false);
  });

  it("Quản lý 1 được cấp customPermission MANAGE_USERS có thể vào trang người dùng", () => {
    const manager1WithPerm = createMockUser("ROLE_MANAGER_1", false, ["MANAGE_USERS"]);
    expect(canAccessRoute(manager1WithPerm, "/dashboard/users")).toBe(true);
  });

  it("Quản lý 2 không thể vào trang nhật ký kiểm toán và kho hàng", () => {
    const manager2 = createMockUser("ROLE_MANAGER_2");
    expect(canAccessRoute(manager2, "/dashboard")).toBe(true);
    expect(canAccessRoute(manager2, "/dashboard/revenue")).toBe(true);
    expect(canAccessRoute(manager2, "/dashboard/tables")).toBe(true);

    // Bị chặn
    expect(canAccessRoute(manager2, "/dashboard/users")).toBe(false);
    expect(canAccessRoute(manager2, "/dashboard/audit")).toBe(false);
    expect(canAccessRoute(manager2, "/dashboard/inventory")).toBe(false);
  });
});
