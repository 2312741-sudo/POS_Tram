import { describe, it, expect } from "vitest";
import {
  buildActionCodeRows, buildPermissionRows, buildRoleMatrix, filterActions, filterPermissions,
  ROLE_COLUMNS, actionCodesFileName,
} from "../lib/action-codes-export";
import { ACTION_CATALOG, PERMISSION_CATALOG } from "../lib/permission-catalog";

const presets = {
  ROLE_OWNER: [],
  ROLE_MANAGER: ["VIEW_MENU", "EDIT_MENU"],
  ROLE_STAFF: ["VIEW_MENU"],
  ROLE_KITCHEN: ["SEND_KITCHEN"],
};
const noUndef = (rows: unknown[][]) => rows.every((r) => r.every((c) => c !== undefined && c !== null));

describe("action-codes-export", () => {
  it("action rows: columns, Vietnamese kept, no undefined", () => {
    const d = buildActionCodeRows(ACTION_CATALOG);
    expect(d.headers).toEqual(["STT", "Mã hành động", "Ý nghĩa", "Nhóm", "Quyền cần có", "Nhạy cảm"]);
    expect(d.rows).toHaveLength(ACTION_CATALOG.length);
    expect(d.rows.every((r) => r.length === d.headers.length)).toBe(true);
    expect(noUndef(d.rows)).toBe(true);
    expect(d.rows[0][2]).toBe(ACTION_CATALOG[0].label);
  });
  it("permission rows: one column per role with grants", () => {
    const d = buildPermissionRows(PERMISSION_CATALOG, presets);
    expect(d.headers.slice(5)).toEqual(ROLE_COLUMNS.map((r) => r.label));
    expect(noUndef(d.rows)).toBe(true);
    const menu = d.rows.find((r) => r[1] === "EDIT_MENU")!;
    expect(menu.slice(5)).toEqual(["✓", "✓", "—", "—"]); // chủ luôn ✓; cột: Chủ quán / Quản lý / Nhân viên / Bếp·Bar
    expect(d.rows.every((r) => r.length === d.headers.length)).toBe(true);
  });
  it("cột vai trò: Chủ quán / Quản lý / Nhân viên / Bếp·Bar (mã chuẩn)", () => {
    expect(ROLE_COLUMNS.map((r) => r.label)).toEqual(["Chủ quán", "Quản lý", "Nhân viên", "Bếp·Bar"]);
    expect(ROLE_COLUMNS.map((r) => r.ids[0])).toEqual(["ROLE_OWNER", "ROLE_MANAGER", "ROLE_STAFF", "ROLE_KITCHEN"]);
  });
  it("filters by search", () => {
    expect(filterActions(ACTION_CATALOG, "zzzz-none")).toHaveLength(0);
    expect(filterActions(ACTION_CATALOG, "")).toHaveLength(ACTION_CATALOG.length);
    const p = filterPermissions(PERMISSION_CATALOG, "edit_menu");
    expect(p.length).toBeGreaterThan(0);
    expect(buildPermissionRows(p, presets).rows).toHaveLength(p.length);
  });
  it("role matrix", () => {
    const d = buildRoleMatrix(PERMISSION_CATALOG, presets);
    expect(d.rows).toHaveLength(ROLE_COLUMNS.length);
    expect(d.rows[0][1]).toBe(PERMISSION_CATALOG.length);
    expect(noUndef(d.rows)).toBe(true);
  });
  it("file name", () => {
    expect(actionCodesFileName(new Date(2026, 9, 12))).toBe("BoMaHanhDong_20261012.xlsx");
  });
});
