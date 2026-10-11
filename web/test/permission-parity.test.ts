import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { PERMISSION_CATALOG } from "../lib/permission-catalog";
import { ROLE_PERMISSIONS } from "../lib/auth";

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
