import { describe, it, expect } from "vitest";
import {
  normalizeUsername,
  validateUsername,
  generateEmail,
  hasPermission,
  canAccessRoute,
  mapStaffSignInError,
  homePathFor,
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

  it("Quản lý (mã cũ ROLE_MANAGER_1) có quyền điều hành và kiểm soát, nhưng không có MANAGE_USERS", () => {
    const manager1 = createMockUser({ roleId: "ROLE_MANAGER_1" });
    expect(hasPermission(manager1, "VIEW_MENU")).toBe(true);
    expect(hasPermission(manager1, "EDIT_MENU")).toBe(true);
    expect(hasPermission(manager1, "CHANGE_PRICE")).toBe(true);
    expect(hasPermission(manager1, "MANUAL_DISCOUNT")).toBe(true);
    expect(hasPermission(manager1, "VIEW_INVENTORY")).toBe(true);

    // Bị giới hạn
    expect(hasPermission(manager1, "MANAGE_USERS")).toBe(false);
    // Quản lý mặc định không hủy/xóa hóa đơn, không xem nhật ký thao tác (Chủ cấp riêng)
    expect(hasPermission(manager1, "VIEW_AUDIT_LOGS")).toBe(false);
    expect(hasPermission(manager1, "CANCEL_BILL")).toBe(false);
    expect(hasPermission(manager1, "CANCEL_KITCHEN_ITEM")).toBe(false);
    expect(hasPermission(manager1, "DELETE_MENU")).toBe(false);
    expect(hasPermission(manager1, "MANAGE_STORE_SETTINGS")).toBe(false);
  });

  it("Mọi mã Quản lý cũ (QL1/QL2/manager...) đều là Quản lý gộp: hợp quyền của hai vai trò cũ", () => {
    for (const id of ["ROLE_MANAGER", "ROLE_MANAGER_1", "ROLE_MANAGER_2", "manager", "manager_1", "manager_2"]) {
      const m = createMockUser({ roleId: id });
      expect(hasPermission(m, "OPEN_TABLE")).toBe(true);
      expect(hasPermission(m, "VIEW_REPORTS")).toBe(true);
      expect(hasPermission(m, "MANAGE_CASH_SHIFT")).toBe(true);
      expect(hasPermission(m, "VIEW_AUDIT_LOGS")).toBe(false); // đã gỡ khỏi mặc định (Chủ cấp riêng)
      expect(hasPermission(createMockUser({ roleId: id, customPermissions: ["VIEW_AUDIT_LOGS"] }), "VIEW_AUDIT_LOGS")).toBe(true);
      expect(hasPermission(m, "VIEW_INVENTORY")).toBe(true);
      expect(hasPermission(m, "COPY_MENU")).toBe(true);
      expect(hasPermission(m, "MANAGE_USERS")).toBe(false);
      expect(hasPermission(m, "MANAGE_LOYALTY")).toBe(false); // chỉ Chủ quán
    }
  });

  it("Thu ngân + Phục vụ đã gộp thành Nhân viên (mọi mã cũ cùng bộ quyền)", () => {
    for (const id of ["ROLE_STAFF", "ROLE_CASHIER", "ROLE_WAITER", "cashier", "waiter", "employee"]) {
      const u = createMockUser({ roleId: id });
      expect(hasPermission(u, "CREATE_BILL")).toBe(true);
      expect(hasPermission(u, "OPEN_TABLE")).toBe(true);
      expect(hasPermission(u, "DELETE_ITEM")).toBe(true);
      expect(hasPermission(u, "MANAGE_CASH_SHIFT")).toBe(true); // mở/kết ca của chính mình
      expect(hasPermission(u, "ADJUST_CASH_SHIFT")).toBe(false); // thu/chi két cần được cấp riêng
      expect(hasPermission(u, "VIEW_REPORTS")).toBe(false);
    }
    expect(hasPermission(createMockUser({ roleId: "ROLE_KITCHEN" }), "CREATE_BILL")).toBe(false);
    expect(hasPermission(createMockUser({ roleId: "ROLE_KITCHEN" }), "VIEW_KITCHEN")).toBe(true);
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

  it("Phục vụ / Thu ngân / Bếp: không vào Tổng quan, vào đúng trang vận hành và được chuyển hướng", () => {
    const waiter = createMockUser("ROLE_WAITER");
    const cashier = createMockUser("ROLE_CASHIER");
    const kitchen = createMockUser("ROLE_KITCHEN");
    for (const u of [waiter, cashier, kitchen]) {
      expect(canAccessRoute(u, "/dashboard")).toBe(false);
      expect(canAccessRoute(u, "/dashboard/users")).toBe(false);
      expect(canAccessRoute(u, "/dashboard/revenue")).toBe(false);
    }
    expect(canAccessRoute(waiter, "/dashboard/tables")).toBe(true);
    // Xem hóa đơn bị khóa với Nhân viên (và Bếp); cấp riêng qua VIEW_ALL_BILLS_HISTORY thì mới xem được
    expect(canAccessRoute(cashier, "/dashboard/orders")).toBe(false);
    expect(canAccessRoute(waiter, "/dashboard/orders")).toBe(false);
    expect(canAccessRoute(kitchen, "/dashboard/orders")).toBe(false);
    expect(canAccessRoute(createMockUser("ROLE_STAFF", false, ["VIEW_ALL_BILLS_HISTORY"]), "/dashboard/orders")).toBe(true);
    expect(canAccessRoute(createMockUser("ROLE_MANAGER"), "/dashboard/orders")).toBe(true);
    expect(canAccessRoute(kitchen, "/dashboard/kitchen")).toBe(true);
    expect(canAccessRoute(kitchen, "/dashboard/tables")).toBe(false);
    expect(canAccessRoute(waiter, "/dashboard/kitchen")).toBe(true); // Phục vụ được xem màn hình Bếp (VIEW_KITCHEN)
    expect(homePathFor(waiter)).toBe("/dashboard/tables");
    expect(homePathFor(kitchen)).toBe("/dashboard/kitchen");
    expect(homePathFor(createMockUser("ROLE_MANAGER_1"))).toBe("/dashboard");
  });

  it("Chủ quán có thể truy cập mọi trang", () => {
    const owner = createMockUser("ROLE_OWNER", true);
    expect(canAccessRoute(owner, "/dashboard")).toBe(true);
    expect(canAccessRoute(owner, "/dashboard/users")).toBe(true);
    expect(canAccessRoute(owner, "/dashboard/stores")).toBe(true);
    expect(canAccessRoute(owner, "/dashboard/audit")).toBe(true);
    expect(canAccessRoute(owner, "/dashboard/revenue")).toBe(true);
  });

  it("Quản lý 1 truy cập được báo cáo nhưng KHÔNG vào được nhật ký (trừ khi được cấp), trang người dùng & cài đặt chi nhánh", () => {
    const manager1 = createMockUser("ROLE_MANAGER_1");
    expect(canAccessRoute(manager1, "/dashboard")).toBe(true);
    expect(canAccessRoute(manager1, "/dashboard/audit")).toBe(false);
    expect(canAccessRoute(createMockUser("ROLE_MANAGER_1", false, ["VIEW_AUDIT_LOGS"]), "/dashboard/audit")).toBe(true);
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

  it("Quản lý (mã cũ QL2) vào được nhật ký & kho (đã gộp); nhân viên thì không", () => {
    const manager2 = createMockUser("ROLE_MANAGER_2");
    expect(canAccessRoute(manager2, "/dashboard")).toBe(true);
    expect(canAccessRoute(manager2, "/dashboard/revenue")).toBe(true);
    expect(canAccessRoute(manager2, "/dashboard/tables")).toBe(true);

    expect(canAccessRoute(manager2, "/dashboard/audit")).toBe(false); // nhật ký: Chủ cấp riêng
    expect(canAccessRoute(manager2, "/dashboard/inventory")).toBe(true);
    expect(canAccessRoute(manager2, "/dashboard/users")).toBe(false);
    const staff = createMockUser("ROLE_CASHIER");
    expect(canAccessRoute(staff, "/dashboard/audit")).toBe(false);
    expect(canAccessRoute(staff, "/dashboard/inventory")).toBe(false);
    expect(canAccessRoute(staff, "/dashboard/revenue")).toBe(false);
  });
});

describe("mapStaffSignInError — hiển thị nguyên nhân thật khi máy chủ lỗi", () => {
  it("giữ thông báo tiếng Việt của máy chủ và kèm mã lỗi", () => {
    const msg = mapStaffSignInError({ code: "functions/internal", message: "Máy chủ chưa đủ quyền cấp phiên đăng nhập (Service Account Token Creator)." });
    expect(msg).toContain("Service Account Token Creator");
    expect(msg).toContain("mã lỗi: internal");
  });

  it("thông báo chung chung 'internal' thì dùng câu mặc định kèm mã lỗi", () => {
    expect(mapStaffSignInError({ code: "functions/internal", message: "internal" })).toContain("Không thể đăng nhập");
    expect(mapStaffSignInError({ code: "functions/internal", message: "internal" })).toContain("mã lỗi: internal");
  });

  it("hàm chưa triển khai và các mã đã biết", () => {
    expect(mapStaffSignInError({ code: "functions/not-found", message: "NOT_FOUND" })).toContain("chưa triển khai");
    expect(mapStaffSignInError({ code: "functions/unauthenticated" })).toBe("Sai tài khoản hoặc mật khẩu.");
  });
});

describe("Đơn của tôi (/dashboard/my-orders) mở cho mọi vai trò", () => {
  it("mọi vai trò vào được, trang chỉ hiển thị đơn của chính tài khoản", () => {
    for (const role of ["ROLE_STAFF", "ROLE_KITCHEN", "ROLE_MANAGER", "ROLE_OWNER"]) {
      const u = { id: "1", uid: "1", username: "a", fullName: "a", roleId: role, role, isRootOwner: false, isActive: true, storeCode: "TRAM01" } as User;
      expect(canAccessRoute(u, "/dashboard/my-orders")).toBe(true);
    }
  });
});

describe("Thông tin ứng dụng (/dashboard/about) mở cho mọi vai trò", () => {
  it("mọi vai trò đăng nhập đều xem được trang thông tin ứng dụng", () => {
    for (const role of ["ROLE_STAFF", "ROLE_KITCHEN", "ROLE_MANAGER", "ROLE_OWNER", "waiter", "cashier"]) {
      const u = { id: "1", uid: "1", username: "a", fullName: "a", roleId: role, role, isRootOwner: false, isActive: true, storeCode: "TRAM01" } as User;
      expect(canAccessRoute(u, "/dashboard/about")).toBe(true);
    }
  });
});

