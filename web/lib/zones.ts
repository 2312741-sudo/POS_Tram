/**
 * Thiết lập khu vực bàn. Nguồn: stores/{code}/zones/{tên khu} = { name } (giống ZoneModel của POS)
 * và stores/{code}/tables/{khu}_{tên bàn} = { name, zone, inUse, currentOrderJson, ... }.
 *
 * Logic THUẦN (không đụng Firebase). Bản Dart song song: app_flutter/lib/core/domain/zone_plan.dart
 * — giữ hai bản cùng quy tắc và cùng hình dạng dữ liệu RTDB.
 */

const FORBIDDEN_KEY_CHARS = /[.#$/[\]]/;

/** Một bàn thô đọc từ RTDB: khóa node + toàn bộ giá trị (giữ nguyên mọi trường khi đổi khu) */
export interface ZoneTableRecord {
  key: string;
  value: Record<string, unknown>;
}

export type ZonePlan = { error: string } | { updates: Record<string, unknown>; affected: number };

/** Danh sách khu đã khai báo (loại bỏ giá trị rỗng, giữ thứ tự theo tên) */
export function parseZones(val: unknown): string[] {
  if (!val || typeof val !== "object") return [];
  const names = new Set<string>();
  for (const [key, raw] of Object.entries(val as Record<string, unknown>)) {
    const n = raw && typeof raw === "object" ? String((raw as { name?: unknown }).name ?? key) : key;
    if (n.trim()) names.add(n.trim());
  }
  return [...names].sort((a, b) => a.localeCompare(b, "vi"));
}

/** Gộp khu đã khai báo với khu đang có bàn (bàn cũ có thể thuộc khu chưa khai báo) */
export function mergeZoneNames(declared: string[], tableZones: (string | undefined)[]): string[] {
  const set = new Set<string>(declared);
  tableZones.forEach((z) => z && z.trim() && set.add(z.trim()));
  return [...set].sort((a, b) => a.localeCompare(b, "vi"));
}

/** Kiểm tra tên khu: không rỗng, ≤ 40 ký tự, không chứa ký tự cấm của khóa RTDB, không trùng (không phân biệt hoa thường) */
export function validateZoneName(name: string, existing: string[]): string | null {
  const n = name.trim();
  if (!n) return "Vui lòng nhập tên khu vực";
  if (n.length > 40) return "Tên khu vực tối đa 40 ký tự";
  if (FORBIDDEN_KEY_CHARS.test(n)) return "Tên khu vực không được chứa các ký tự . # $ / [ ]";
  if (existing.some((z) => z.trim().toLowerCase() === n.toLowerCase())) return `Khu "${n}" đã tồn tại`;
  return null;
}

/** Tiền tố tên bàn: sẽ thành một phần của khóa node (khu_tên bàn) nên không được chứa ký tự cấm */
export function validateTablePrefix(prefix: string): string | null {
  const p = prefix.trim();
  if (p.length > 20) return "Tiền tố tên bàn tối đa 20 ký tự";
  if (FORBIDDEN_KEY_CHARS.test(p)) return "Tiền tố tên bàn không được chứa các ký tự . # $ / [ ]";
  return null;
}

/** Số bàn tạo nhanh: số nguyên trong khoảng [min, 100] */
export function validateTableCount(raw: string | number, min = 0): string | null {
  const n = Number(raw);
  if (!Number.isInteger(n) || n < min || n > 100) return `Số bàn tạo nhanh từ ${min} đến 100`;
  return null;
}

/** Tên bàn tuần tự: "Bàn 01".."Bàn 12" (rộng tối thiểu 2 chữ số), bỏ qua tên đã có trong khu */
export function nextTableNames(prefix: string, count: number, takenNames: string[]): string[] {
  const taken = new Set(takenNames.map((n) => n.trim().toLowerCase()));
  const width = Math.max(2, String(count + takenNames.length).length);
  const out: string[] = [];
  for (let i = 1; out.length < count && i < 10_000; i++) {
    const name = `${prefix.trim() || "Bàn"} ${String(i).padStart(width, "0")}`;
    if (!taken.has(name.toLowerCase())) out.push(name);
  }
  return out;
}

/** Bàn đang "bận": đang dùng, hoặc còn giỏ món (không rỗng) */
export function isTableInUse(value: Record<string, unknown>): boolean {
  if (value.inUse === true) return true;
  return typeof value.currentOrderJson === "string" && value.currentOrderJson.length > 0;
}

function tablesOfZone(tables: ZoneTableRecord[], zone: string): ZoneTableRecord[] {
  return tables.filter((t) => String(t.value.zone ?? "") === zone);
}

function tableDisplayName(t: ZoneTableRecord): string {
  return String(t.value.name ?? t.key);
}

export function buildZoneCreateUpdates(args: {
  storeCode: string;
  zoneName: string;
  tableNames: string[];
}): Record<string, unknown> {
  const base = `stores/${args.storeCode}`;
  const zone = args.zoneName.trim();
  const updates: Record<string, unknown> = { [`${base}/zones/${zone}`]: { name: zone } };
  for (const name of args.tableNames) {
    updates[`${base}/tables/${zone}_${name}`] = { name, zone, inUse: false, currentOrderJson: "" };
  }
  return updates;
}

/** Thêm khu mới kèm N bàn. Kiểm tra toàn bộ đầu vào và khóa bàn trùng trước khi ghi. */
export function planZoneCreate(args: {
  storeCode: string;
  zoneName: string;
  prefix: string;
  count: number;
  declaredZones: string[];
  tables: ZoneTableRecord[];
}): ZonePlan {
  const zone = args.zoneName.trim();
  const err =
    validateZoneName(zone, args.declaredZones) ??
    validateTablePrefix(args.prefix) ??
    validateTableCount(args.count);
  if (err) return { error: err };
  const names = nextTableNames(args.prefix, args.count, []);
  const updates = buildZoneCreateUpdates({ storeCode: args.storeCode, zoneName: zone, tableNames: names });
  const existing = new Set(args.tables.map((t) => t.key));
  if (names.some((n) => existing.has(`${zone}_${n}`))) {
    return { error: `Đã có bàn trùng khóa trong khu "${zone}" — hãy đổi tên khu hoặc tiền tố` };
  }
  return { updates, affected: names.length };
}

/** Thêm N bàn vào khu đã có. Tên bàn tiếp nối, không trùng bàn đang có trong khu. */
export function planAddTables(args: {
  storeCode: string;
  zoneName: string;
  prefix: string;
  count: number;
  declaredZones: string[];
  tables: ZoneTableRecord[];
}): ZonePlan {
  const zone = args.zoneName.trim();
  if (!args.declaredZones.includes(zone) && tablesOfZone(args.tables, zone).length === 0) {
    return { error: `Khu "${zone}" không tồn tại` };
  }
  const err = validateTablePrefix(args.prefix) ?? validateTableCount(args.count, 1);
  if (err) return { error: err };
  const taken = tablesOfZone(args.tables, zone).map(tableDisplayName);
  const names = nextTableNames(args.prefix, args.count, taken);
  const base = `stores/${args.storeCode}`;
  const existing = new Set(args.tables.map((t) => t.key));
  const updates: Record<string, unknown> = { [`${base}/zones/${zone}/name`]: zone };
  for (const name of names) {
    const key = `${zone}_${name}`;
    if (existing.has(key)) return { error: `Bàn "${name}" đã tồn tại trong khu "${zone}"` };
    updates[`${base}/tables/${key}`] = { name, zone, inUse: false, currentOrderJson: "" };
  }
  return { updates, affected: names.length };
}

/**
 * Đổi tên khu: chuyển khu node + mọi bàn thuộc khu sang khóa mới (khu_tên) trong MỘT update đa đường dẫn.
 * Từ chối khi tên mới trùng khu khác, khóa bàn đích bị chiếm, hoặc có bàn đang dùng / còn giỏ món.
 */
export function planZoneRename(args: {
  storeCode: string;
  oldName: string;
  newName: string;
  declaredZones: string[];
  tables: ZoneTableRecord[];
}): ZonePlan {
  const oldZ = args.oldName.trim();
  const newZ = args.newName.trim();
  if (newZ === oldZ) return { error: "Tên khu không thay đổi" };
  const err = validateZoneName(newZ, args.declaredZones.filter((z) => z.trim() !== oldZ));
  if (err) return { error: err };

  const movers = tablesOfZone(args.tables, oldZ);
  const busy = movers.filter((t) => isTableInUse(t.value));
  if (busy.length > 0) {
    return { error: `Khu "${oldZ}" còn ${busy.length} bàn đang dùng hoặc còn món — hãy dọn bàn trước khi đổi tên` };
  }

  const base = `stores/${args.storeCode}`;
  const allKeys = new Set(args.tables.map((t) => t.key));
  const updates: Record<string, unknown> = {
    [`${base}/zones/${oldZ}`]: null,
    [`${base}/zones/${newZ}`]: { name: newZ },
  };
  for (const t of movers) {
    const name = tableDisplayName(t);
    const newKey = `${newZ}_${name}`;
    // Khóa đích đã có bàn khác (kể cả bàn cùng khu sẽ bị chuyển) thì từ chối; giữ nguyên khóa của chính nó thì được
    if (allKeys.has(newKey) && newKey !== t.key) {
      return { error: `Bàn "${name}" đã tồn tại trong khu "${newZ}"` };
    }
    updates[`${base}/tables/${t.key}`] = null;
    updates[`${base}/tables/${newKey}`] = { ...t.value, zone: newZ };
  }
  return { updates, affected: movers.length };
}

/** Xóa khu: chỉ khi không còn bàn nào thuộc khu (tránh làm mất bàn / đơn đang mở) */
export function buildZoneDeleteUpdates(args: {
  storeCode: string;
  zoneName: string;
  tablesInZone: number;
}): { error: string } | { updates: Record<string, unknown> } {
  if (args.tablesInZone > 0) {
    return { error: `Khu "${args.zoneName}" còn ${args.tablesInZone} bàn — hãy chuyển hoặc xóa các bàn trước` };
  }
  return { updates: { [`stores/${args.storeCode}/zones/${args.zoneName}`]: null } };
}

export interface ZoneAuditActor {
  username: string;
  fullName?: string;
  role?: string;
}

/** Một bản ghi nhật ký thao tác khu/bàn (khớp rules audit_logs: khóa mới, có timestamp) */
export function buildZoneAuditUpdates(args: {
  storeCode: string;
  action: "ZONE_SAVE" | "ZONE_RENAME" | "ZONE_DELETE" | "TABLE_ADD";
  targetType: "ZONE" | "TABLE";
  targetId: string;
  details: string;
  actor: ZoneAuditActor;
  now: number;
  suffix: number;
}): Record<string, unknown> {
  return {
    [`stores/${args.storeCode}/audit_logs/log_${args.now}_zone_${args.suffix}`]: {
      timestamp: args.now,
      username: args.actor.username,
      userFullName: args.actor.fullName || args.actor.username,
      userRole: args.actor.role || "",
      action: args.action,
      targetType: args.targetType,
      targetId: args.targetId,
      storeCode: args.storeCode,
      details: args.details,
    },
  };
}
