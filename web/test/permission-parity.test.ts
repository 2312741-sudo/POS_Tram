import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { PERMISSION_CATALOG, OWNER_GRANT_ONLY_PERMISSIONS } from "../lib/permission-catalog";
import { ROLE_PERMISSIONS, hasPermission, canAccessRoute, type User } from "../lib/auth";

/** Đồng bộ danh mục quyền + quyền mặc định theo vai trò giữa Web và app Flutter (nguồn: app_permissions.dart). */
const dart = readFileSync(resolve(__dirname, "../../app_flutter/lib/core/permissions/app_permissions.dart"), "utf8");

function dartCatalogKeys(): string[] {
  const body = dart.slice(dart.indexOf("class AppPermissions {"));
  const keys: string[] = [];
  for (const m of body.matchAll(/static const String \w+ = '([A-Z][A-Z_]+)';/g)) keys.push(m[1]);
  return keys;
}

function dartPreset(role: string): string[] {
  const start = dart.indexOf(`'${role}': [`);
  expect(start, role).toBeGreaterThan(-1);
  const end = dart.indexOf("],", start);
  return [...dart.slice(start, end).matchAll(/'([A-Z][A-Z_]+)'/g)].map((m) => m[1]).filter((k) => k !== role);
}

describe("Web ↔ Flutter: danh mục quyền", () => {
  it("cùng một tập mã quyền (không lệch)", () => {
    const web = PERMISSION_CATALOG.map((p) => p.key).sort();
    const flutter = dartCatalogKeys().sort();
    expect(flutter).toEqual(web);
  });
  it("nhãn tiếng Việt của quyền mới có trong cả hai bản", () => {
    for (const p of PERMISSION_CATALOG) {
      expect(dart.includes(`label: '${p.label}'`), p.key).toBe(true);
    }
  });
});

describe("Web ↔ Flutter: quyền mặc định theo vai trò", () => {
  for (const role of ["ROLE_MANAGER", "ROLE_STAFF", "ROLE_KITCHEN"]) {
    it(role, () => {
      expect([...dartPreset(role)].sort()).toEqual([...ROLE_PERMISSIONS[role]].sort());
    });
  }
});

const quoted = (src: string) => [...src.matchAll(/'([A-Z][A-Z_]+)'/g)].map((m) => m[1]);

describe("Quy tắc vai trò (docs/ROLE_RULES.md)", () => {
  const NEW_CODES = ["VIEW_SHIFT_HANDOVER", "VIEW_ALL_SHIFTS", "VIEW_ALL_BILLS_HISTORY", "TOGGLE_ITEM_AVAILABILITY", "MANAGE_NOTE_CATALOG"];
  const user = (roleId: string, customPermissions: string[] = []) => ({ roleId, role: roleId, customPermissions }) as unknown as User;

  it("quyền mới có trong danh mục, đủ nhãn/nhóm/mô tả tiếng Việt", () => {
    for (const k of NEW_CODES) {
      const p = PERMISSION_CATALOG.find((x) => x.key === k);
      expect(p, k).toBeTruthy();
      expect(p!.label.length).toBeGreaterThan(3);
      expect(p!.category.length).toBeGreaterThan(3);
      expect(p!.description.length).toBeGreaterThan(10);
    }
  });

  it("phân phối mặc định quyền mới: Quản lý đủ 5; Nhân viên/Bếp chỉ có TOGGLE_ITEM_AVAILABILITY", () => {
    for (const k of NEW_CODES) expect(ROLE_PERMISSIONS.ROLE_MANAGER, k).toContain(k);
    for (const r of ["ROLE_STAFF", "ROLE_KITCHEN"]) {
      for (const k of NEW_CODES) {
        expect(ROLE_PERMISSIONS[r].includes(k), `${r} ${k}`).toBe(k === "TOGGLE_ITEM_AVAILABILITY");
      }
    }
    for (const k of NEW_CODES) expect(ROLE_PERMISSIONS.ROLE_OWNER).toContain(k);
  });

  it("Quản lý mặc định KHÔNG có quyền hủy/xóa hóa đơn, hủy món đã gửi bếp, xem/xuất nhật ký thao tác", () => {
    expect([...OWNER_GRANT_ONLY_PERMISSIONS].sort()).toEqual(["CANCEL_BILL", "CANCEL_KITCHEN_ITEM", "EXPORT_AUDIT_LOGS", "VIEW_AUDIT_LOGS"]);
    for (const k of OWNER_GRANT_ONLY_PERMISSIONS) {
      expect(ROLE_PERMISSIONS.ROLE_MANAGER, k).not.toContain(k);
      expect(ROLE_PERMISSIONS.ROLE_STAFF, k).not.toContain(k);
      expect(ROLE_PERMISSIONS.ROLE_KITCHEN, k).not.toContain(k);
      expect(ROLE_PERMISSIONS.ROLE_OWNER, k).toContain(k);
      expect(hasPermission(user("ROLE_MANAGER"), k), k).toBe(false);
      // Chủ cấp riêng qua customPermissions thì có hiệu lực (customPermissions chỉ THÊM)
      expect(hasPermission(user("manager_1", [k]), k), k).toBe(true);
    }
    expect(canAccessRoute(user("ROLE_MANAGER"), "/dashboard/audit")).toBe(false);
    expect(canAccessRoute(user("ROLE_MANAGER", ["VIEW_AUDIT_LOGS"]), "/dashboard/audit")).toBe(true);
  });

  it("Nhân viên / Bếp không vào được quản lý thực đơn (VIEW_MENU không còn thay được MENU_MANAGEMENT)", () => {
    for (const r of ["ROLE_STAFF", "cashier", "waiter", "ROLE_KITCHEN"]) {
      for (const k of ["MENU_MANAGEMENT", "EDIT_MENU", "DELETE_MENU", "CHANGE_PRICE", "MANAGE_NOTE_CATALOG", "MANAGE_TABLES"]) {
        expect(hasPermission(user(r), k), `${r} ${k}`).toBe(false);
      }
      expect(hasPermission(user(r), "VIEW_MENU")).toBe(true);
      expect(canAccessRoute(user(r), "/dashboard/products")).toBe(false);
    }
    expect(canAccessRoute(user("ROLE_MANAGER"), "/dashboard/products")).toBe(true);
  });

  it("phiếu bàn giao ca: Nhân viên không thấy trên Web; Quản lý thấy", () => {
    expect(canAccessRoute(user("ROLE_STAFF"), "/dashboard/shifts")).toBe(false);
    expect(canAccessRoute(user("ROLE_MANAGER"), "/dashboard/shifts")).toBe(true);
  });

  it("danh sách quyền Chủ-cấp-riêng khớp Flutter, Cloud Functions và RTDB rules", () => {
    const web = [...OWNER_GRANT_ONLY_PERMISSIONS].sort();
    const dartBlock = dart.slice(dart.indexOf("static const List<String> ownerGrantOnly"));
    expect(quoted(dartBlock.slice(0, dartBlock.indexOf("];"))).sort()).toEqual(web);
    const fn = readFileSync(resolve(__dirname, "../../functions/src/permissions.ts"), "utf8");
    const fnBlock = fn.slice(fn.indexOf("export const OWNER_GRANT_ONLY_PERMISSIONS"));
    expect([...fnBlock.slice(0, fnBlock.indexOf("];")).matchAll(/"([A-Z][A-Z_]+)"/g)].map((m) => m[1]).sort()).toEqual(web);
    const rules = readFileSync(resolve(__dirname, "../../database.rules.json"), "utf8");
    for (const k of web) expect(rules.includes(`newData.val() !== '${k}'`), `rules chặn ${k}`).toBe(true);
  });

  it("Flutter: manager không còn quyền bị gỡ (parity với web đã kiểm tra ở trên)", () => {
    const m = dartPreset("ROLE_MANAGER");
    for (const k of OWNER_GRANT_ONLY_PERMISSIONS) expect(m).not.toContain(k);
  });
});

