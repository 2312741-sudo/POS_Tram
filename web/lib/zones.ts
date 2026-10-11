/**
 * Thiết lập khu vực bàn. Nguồn: stores/{code}/zones/{tên khu} = { name } (giống ZoneModel của POS)
 * và stores/{code}/tables/{khu}_{tên bàn} = { name, zone, inUse, currentOrderJson }.
 */

const FORBIDDEN_KEY_CHARS = /[.#$/[\]]/;

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
