import { describe, it, expect } from "vitest";
import {
  normalizeStoreCode,
  decideOwnerAccess,
  layoutFromSource,
  buildStoreInfo,
  planCreateStore,
  DEFAULT_ZONES,
  DEFAULT_TABLES,
} from "./createStoreLogic";
import { UserProfile } from "./permissions";

const owner: UserProfile = { username: "chu", fullName: "Chủ Quán", roleId: "ROLE_OWNER", isRootOwner: false, isActive: true, phone: "0900", customPermissions: ["VIEW_AUDIT_LOGS"] };
const manager: UserProfile = { username: "ql", roleId: "ROLE_MANAGER", isRootOwner: false, isActive: true };
const staff: UserProfile = { username: "nv", roleId: "ROLE_STAFF", isRootOwner: false, isActive: true };
const inactiveOwner: UserProfile = { username: "chu2", roleId: "ROLE_OWNER", isActive: false };
const rootOwner: UserProfile = { username: "root", roleId: "ROLE_STAFF", isRootOwner: true, isActive: true };

import { chainOwners } from "./createStoreLogic";

describe("chainOwners", () => {
  const own = (u: string, extra: Partial<UserProfile> = {}) => ({ username: u, isRootOwner: true, isActive: true, ...extra } as UserProfile);
  it("chỉ lấy chủ gốc có mặt ở mọi chi nhánh, bỏ người tạo, bỏ bị khóa", () => {
    const r = chainOwners(
      {
        A: { c: own("creator"), x: own("admin"), y: own("onlyA"), z: own("locked", { isActive: false }) },
        B: { c: own("creator"), x: own("admin"), z: own("locked") },
      },
      "c"
    );
    expect(Object.keys(r)).toEqual(["x"]);
  });
  it("không có chi nhánh -> rỗng", () => {
    expect(chainOwners({}, "c")).toEqual({});
  });
});

describe("normalizeStoreCode", () => {
  it("chuyển thành chữ in hoa và giữ A-Z 0-9 _", () => {
    expect(normalizeStoreCode("  tram_02 ")).toEqual({ code: "TRAM_02" });
  });
  it("bỏ ký tự ngoài A-Z 0-9 _ (giống web)", () => {
    expect(normalizeStoreCode("ab-c d.e")).toEqual({ code: "ABCDE" });
  });
  it("rỗng hoặc toàn ký tự không hợp lệ → lỗi", () => {
    expect(normalizeStoreCode("")).toHaveProperty("error");
    expect(normalizeStoreCode("   ")).toHaveProperty("error");
    expect(normalizeStoreCode("!!!")).toHaveProperty("error");
    expect(normalizeStoreCode(undefined)).toHaveProperty("error");
  });
  it("quá ngắn (dưới 2 ký tự) → lỗi", () => {
    expect(normalizeStoreCode("a")).toHaveProperty("error");
    expect(normalizeStoreCode("a")).not.toHaveProperty("code");
  });
  it("đúng 2 và đúng 20 ký tự → hợp lệ", () => {
    expect(normalizeStoreCode("AB")).toEqual({ code: "AB" });
    expect(normalizeStoreCode("A".repeat(20))).toEqual({ code: "A".repeat(20) });
  });
  it("quá dài (21 ký tự) → lỗi", () => {
    const r = normalizeStoreCode("A".repeat(21));
    expect(r).toHaveProperty("error");
    expect(r).not.toHaveProperty("code");
  });
});

describe("decideOwnerAccess", () => {
  it("chủ quán ở một trong nhiều chi nhánh → được phép, ghi nhận chi nhánh", () => {
    const r = decideOwnerAccess(["A", "B", "C"], { A: manager, B: null, C: owner });
    expect(r).toEqual({ allowed: true, viaStore: "C", profile: owner });
  });
  it("quản lý ở mọi chi nhánh → từ chối", () => {
    expect(decideOwnerAccess(["A", "B"], { A: manager, B: manager })).toEqual({ allowed: false });
  });
  it("nhân viên → từ chối", () => {
    expect(decideOwnerAccess(["A"], { A: staff })).toEqual({ allowed: false });
  });
  it("không có chi nhánh nào trong index → từ chối", () => {
    expect(decideOwnerAccess([], {})).toEqual({ allowed: false });
  });
  it("index có chi nhánh nhưng không có hồ sơ → từ chối", () => {
    expect(decideOwnerAccess(["A"], { A: null })).toEqual({ allowed: false });
  });
  it("chủ quán nhưng bị khóa → từ chối", () => {
    expect(decideOwnerAccess(["A"], { A: inactiveOwner })).toEqual({ allowed: false });
  });
  it("chủ quán gốc (isRootOwner) dù vai trò khác → được phép", () => {
    expect(decideOwnerAccess(["A"], { A: rootOwner }).allowed).toBe(true);
  });
});

describe("layoutFromSource", () => {
  it("lấy tên khu (khai báo ∪ khu của bàn); bàn đặt inUse=false, currentOrderJson rỗng", () => {
    const l = layoutFromSource(
      { "Khu A": { name: "Khu A" } },
      { "Khu B_Bàn 1": { name: "Bàn 1", zone: "Khu B", inUse: true, currentOrderJson: "[{}]" } }
    );
    expect(Object.keys(l.zones).sort()).toEqual(["Khu A", "Khu B"]);
    expect(l.tables).toEqual({
      "Khu B_Bàn 1": { name: "Bàn 1", zone: "Khu B", inUse: false, currentOrderJson: "" },
    });
  });
  it("bỏ khu/bàn chứa ký tự cấm (. # $ / [ ]) và bàn thiếu tên/khu", () => {
    const l = layoutFromSource(
      { "Khu.X": { name: "Khu.X" } },
      { "Sân_Bàn/1": { name: "Bàn/1", zone: "Sân" }, "_x": { name: "", zone: "" }, "K_B": { name: "B", zone: "K" } }
    );
    expect(Object.keys(l.zones)).toEqual(["K"]);
    expect(Object.keys(l.tables)).toEqual(["K_B"]);
  });
  it("nguồn trống → không có khu", () => {
    expect(layoutFromSource(null, null)).toEqual({ zones: {}, tables: {} });
  });
});

describe("buildStoreInfo", () => {
  it("điền mặc định cho trường trống, ép kiểu số/boolean", () => {
    const info = buildStoreInfo("TRAM02", { storeName: "  ", defaultVatRate: "8", allowStackPromotions: false }, 123);
    expect(info).toEqual({
      id: "TRAM02",
      storeCode: "TRAM02",
      storeName: "POS Trạm - TRAM02",
      address: "Chi nhánh mới",
      phone: "",
      wifiName: "Tram_FnB_Free",
      bankId: "MB",
      bankAccount: "",
      accountName: "CHU CUA HANG",
      defaultVatRate: 0,
      allowStackPromotions: false,
      active: true,
      createdAt: 123,
    });
  });
  it("giữ giá trị người dùng nhập", () => {
    const info = buildStoreInfo("X1", { storeName: "Quận 1", address: "12 Lê Lợi", defaultVatRate: 8, allowStackPromotions: true, bankAccount: "123" }, 1);
    expect(info).toMatchObject({ storeName: "Quận 1", address: "12 Lê Lợi", defaultVatRate: 8, allowStackPromotions: true, bankAccount: "123" });
  });
});

describe("planCreateStore", () => {
  const base = { code: "TRAM02", uid: "uid-1", now: 1000, auditId: "LOG_1000_abc", input: { storeName: "Chi nhánh 2" }, caller: owner };

  it("mặc định: đúng 6 đường dẫn ghi", () => {
    const plan = planCreateStore({ ...base, layout: null });
    expect(Object.keys(plan.updates).sort()).toEqual([
      "stores/TRAM02/audit_logs/LOG_1000_abc",
      "stores/TRAM02/storeInfo",
      "stores/TRAM02/tables",
      "stores/TRAM02/users/uid-1",
      "stores/TRAM02/zones",
      "userIndex/uid-1/TRAM02",
    ]);
    expect(plan.zonesFrom).toBe("default");
    expect(plan.updates["stores/TRAM02/zones"]).toEqual(DEFAULT_ZONES);
    expect(plan.updates["stores/TRAM02/tables"]).toEqual(DEFAULT_TABLES);
    expect(plan.updates["userIndex/uid-1/TRAM02"]).toBe(true);
  });

  it("hồ sơ chủ quán tại chi nhánh mới", () => {
    const plan = planCreateStore({ ...base, layout: null });
    expect(plan.updates["stores/TRAM02/users/uid-1"]).toEqual({
      uid: "uid-1",
      username: "chu",
      fullName: "Chủ Quán",
      roleId: "ROLE_OWNER",
      isRootOwner: false,
      isActive: true,
      phone: "0900",
      customPermissions: ["VIEW_AUDIT_LOGS"],
      createdAt: 1000,
      storeCode: "TRAM02",
    });
  });

  it("audit CREATE_STORE có người thực hiện", () => {
    const plan = planCreateStore({ ...base, layout: null });
    expect(plan.updates["stores/TRAM02/audit_logs/LOG_1000_abc"]).toEqual({
      action: "CREATE_STORE",
      targetType: "STORE",
      targetId: "TRAM02",
      details: "Tạo chi nhánh mới: Chi nhánh 2 (TRAM02)",
      timestamp: 1000,
      username: "chu",
      userFullName: "Chủ Quán",
      userRole: "ROLE_OWNER",
    });
  });

  it("không có giá trị undefined trong bất kỳ bản ghi nào", () => {
    const plan = planCreateStore({ ...base, caller: { username: "x", roleId: "owner" }, layout: null });
    for (const v of Object.values(plan.updates)) {
      expect(hasUndefined(v)).toBe(false);
    }
  });

  it("sao chép bố cục: dùng khu/bàn của nguồn", () => {
    const layout = layoutFromSource({ "Khu A": { name: "Khu A" } }, { "Khu A_Bàn 1": { name: "Bàn 1", zone: "Khu A" } });
    const plan = planCreateStore({ ...base, layout });
    expect(plan.zonesFrom).toBe("copied");
    expect(plan.updates["stores/TRAM02/zones"]).toEqual({ "Khu A": { name: "Khu A" } });
    expect(plan.updates["stores/TRAM02/tables"]).toEqual({
      "Khu A_Bàn 1": { name: "Bàn 1", zone: "Khu A", inUse: false, currentOrderJson: "" },
    });
  });

  it("bố cục sao chép rỗng → quay về mặc định", () => {
    const plan = planCreateStore({ ...base, layout: { zones: {}, tables: {} } });
    expect(plan.zonesFrom).toBe("default");
    expect(plan.updates["stores/TRAM02/zones"]).toEqual(DEFAULT_ZONES);
  });
});

function hasUndefined(v: unknown): boolean {
  if (v === undefined) return true;
  if (v && typeof v === "object") return Object.values(v as Record<string, unknown>).some(hasUndefined);
  return false;
}
