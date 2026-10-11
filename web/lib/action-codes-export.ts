import * as XLSX from "xlsx";
import { format } from "date-fns";
import type { ActionCode, PermissionCode } from "./permission-catalog";
import { ROLE_OWNER, ROLE_MANAGER, ROLE_STAFF, ROLE_KITCHEN, OWNER_ROLE_LABEL, MANAGER_ROLE_LABEL, STAFF_ROLE_LABEL } from "./roles";

/** Cột vai trò dùng chung cho trang & file Excel. `ids`: mã vai trò ưu tiên theo thứ tự (lấy mã đầu tiên có trong bảng preset). */
export const ROLE_COLUMNS: { ids: string[]; label: string }[] = [
  { ids: [ROLE_OWNER], label: OWNER_ROLE_LABEL },
  { ids: [ROLE_MANAGER], label: MANAGER_ROLE_LABEL },
  { ids: [ROLE_STAFF], label: STAFF_ROLE_LABEL },
  { ids: [ROLE_KITCHEN], label: "Bếp·Bar" },
];

export type RolePresets = Record<string, string[]>;
export type Cell = string | number;
export interface SheetData { headers: string[]; rows: Cell[][] }

const GRANT = "✓";
const NONE = "—";

export function roleGrants(presets: RolePresets, ids: string[], permKey: string): boolean {
  if (ids.includes(ROLE_OWNER)) return true; // Chủ quán luôn có toàn quyền
  const id = ids.find((i) => presets[i]);
  return !!id && presets[id].includes(permKey);
}

export function filterActions(list: ActionCode[], q: string): ActionCode[] {
  const n = q.trim().toLowerCase();
  return list.filter((a) => !n || `${a.code} ${a.label} ${a.group}`.toLowerCase().includes(n));
}

export function filterPermissions(list: PermissionCode[], q: string): PermissionCode[] {
  const n = q.trim().toLowerCase();
  return list.filter((p) => !n || `${p.key} ${p.label} ${p.category} ${p.description}`.toLowerCase().includes(n));
}

export function buildActionCodeRows(actions: ActionCode[]): SheetData {
  return {
    headers: ["STT", "Mã hành động", "Ý nghĩa", "Nhóm", "Quyền cần có", "Nhạy cảm"],
    rows: actions.map((a, i) => [i + 1, a.code, a.label ?? "", a.group ?? "", a.permission || NONE, a.sensitive ? "Có" : "Không"]),
  };
}

export function buildPermissionRows(perms: PermissionCode[], presets: RolePresets): SheetData {
  return {
    headers: ["STT", "Mã quyền", "Tên", "Nhóm", "Mô tả", ...ROLE_COLUMNS.map((r) => r.label)],
    rows: perms.map((p, i) => [
      i + 1, p.key, p.label ?? "", p.category ?? "", p.description ?? "",
      ...ROLE_COLUMNS.map((r) => (roleGrants(presets, r.ids, p.key) ? GRANT : NONE)),
    ]),
  };
}

/** Ma trận gọn: mỗi vai trò một dòng, số quyền mặc định theo từng nhóm. */
export function buildRoleMatrix(perms: PermissionCode[], presets: RolePresets): SheetData {
  const cats = Array.from(new Set(perms.map((p) => p.category)));
  return {
    headers: ["Vai trò", "Tổng số quyền", ...cats],
    rows: ROLE_COLUMNS.map((r) => {
      const granted = perms.filter((p) => roleGrants(presets, r.ids, p.key));
      return [
        r.label, granted.length,
        ...cats.map((c) => {
          const total = perms.filter((p) => p.category === c).length;
          return `${granted.filter((p) => p.category === c).length}/${total}`;
        }),
      ];
    }),
  };
}

export function actionCodesFileName(now = new Date()): string {
  return `BoMaHanhDong_${format(now, "yyyyMMdd")}.xlsx`;
}

function toSheet(title: string, note: string, d: SheetData): XLSX.WorkSheet {
  const aoa: Cell[][] = [[title.toUpperCase()], [note], [], d.headers, ...d.rows];
  const ws = XLSX.utils.aoa_to_sheet(aoa);
  ws["!cols"] = d.headers.map((h, i) => {
    let max = h.length;
    for (const r of d.rows) max = Math.max(max, String(r[i] ?? "").length);
    return { wch: Math.min(Math.max(max + 4, 10), 70) };
  });
  return ws;
}

export interface ExportActionCodesOptions {
  actions: ActionCode[];
  permissions: PermissionCode[];
  presets: RolePresets;
  allPermissions: PermissionCode[];
  filterText?: string;
  storeName?: string;
  userName?: string;
}

export function exportActionCodesExcel(o: ExportActionCodesOptions) {
  const now = new Date();
  const note =
    `Xuất lúc ${format(now, "dd/MM/yyyy HH:mm:ss")}` +
    (o.storeName ? ` | Cửa hàng: ${o.storeName}` : "") +
    (o.userName ? ` | Người xuất: ${o.userName}` : "") +
    (o.filterText?.trim() ? ` | Bộ lọc: "${o.filterText.trim()}"` : " | Toàn bộ danh mục");
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, toSheet("Mã hành động", note, buildActionCodeRows(o.actions)), "Mã hành động");
  XLSX.utils.book_append_sheet(wb, toSheet("Mã quyền", note, buildPermissionRows(o.permissions, o.presets)), "Mã quyền");
  XLSX.utils.book_append_sheet(wb, toSheet("Ma trận vai trò", note, buildRoleMatrix(o.allPermissions, o.presets)), "Ma trận vai trò");
  XLSX.writeFile(wb, actionCodesFileName(now));
}
