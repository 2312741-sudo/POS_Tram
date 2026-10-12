/**
 * Danh mục note & topping gắn theo nhóm món / món — LOGIC THUẦN (không đụng Firebase).
 * Bản Dart song song: app_flutter/lib/core/domain/item_options.dart (giữ hai bản cùng quy tắc).
 * Xem docs/NOTE_CATALOG.md.
 *
 *  - stores/{s}/note_groups/{id}    = {name, sortOrder, active, items:[{id,text}]}
 *  - stores/{s}/topping_groups/{id} = {name, sortOrder, active, multi, max, items:[{id,name,price}]}
 *  - categories/{nhóm}.noteGroupIds[] / .toppingGroupIds[] và cùng hai trường trên products/{món}
 *
 * Món có trường (kể cả "không có") → dùng của món; không có → kế thừa nhóm món; nhóm món cũng không có → không có gì.
 * RTDB không lưu mảng rỗng nên "ghi đè = không có" được ghi là [NO_GROUPS].
 * Chi nhánh chưa có note_groups lẫn topping_groups → legacy = true (giữ cách hiển thị cũ).
 */

export const NO_GROUPS = "__none__";

export interface NoteTemplate {
  id: string;
  text: string;
}
export interface NoteGroup {
  id: string;
  name: string;
  sortOrder: number;
  active: boolean;
  items: NoteTemplate[];
}
export interface ToppingItem {
  id: string;
  name: string;
  price: number;
}
export interface ToppingGroup {
  id: string;
  name: string;
  sortOrder: number;
  active: boolean;
  multi: boolean;
  /** 0 = không giới hạn */
  max: number;
  items: ToppingItem[];
}
export interface ItemCatalog {
  noteGroups: NoteGroup[];
  toppingGroups: ToppingGroup[];
}
export const EMPTY_CATALOG: ItemCatalog = { noteGroups: [], toppingGroups: [] };

export interface GroupAttachments {
  /** undefined = không có trường (kế thừa) */
  noteGroupIds?: string[] | null;
  toppingGroupIds?: string[] | null;
}

export type OptionSource = "product" | "category" | "none";

export interface ResolvedItemOptions {
  noteGroups: NoteGroup[];
  toppingGroups: ToppingGroup[];
  legacy: boolean;
  noteSource: OptionSource;
  toppingSource: OptionSource;
}

type Rec = Record<string, unknown>;
const isRec = (v: unknown): v is Rec => typeof v === "object" && v !== null && !Array.isArray(v);

/** RTDB có thể trả mảng hoặc map {"0":..,"2":..} */
function listOf(v: unknown): unknown[] {
  if (Array.isArray(v)) return v.filter((x) => x != null);
  if (isRec(v)) {
    return Object.keys(v)
      .sort((a, b) => (Number.isFinite(Number(a)) ? Number(a) : 1e9) - (Number.isFinite(Number(b)) ? Number(b) : 1e9))
      .map((k) => v[k])
      .filter((x) => x != null);
  }
  return [];
}

const toInt = (v: unknown): number => {
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? Math.trunc(n) : 0;
};

export function parseNoteGroup(id: string, raw: unknown): NoteGroup {
  const m: Rec = isRec(raw) ? raw : {};
  const items = listOf(m.items)
    .map((e, i): NoteTemplate => {
      if (typeof e === "string") return { id: String(i), text: e };
      const r: Rec = isRec(e) ? e : {};
      return { id: r.id != null ? String(r.id) : String(i), text: String(r.text ?? r.name ?? "") };
    })
    .filter((n) => n.text.trim() !== "");
  return { id, name: String(m.name ?? id), sortOrder: toInt(m.sortOrder), active: m.active !== false, items };
}

export function parseToppingGroup(id: string, raw: unknown): ToppingGroup {
  const m: Rec = isRec(raw) ? raw : {};
  const items = listOf(m.items)
    .map((e, i): ToppingItem => {
      const r: Rec = isRec(e) ? e : {};
      return { id: r.id != null ? String(r.id) : String(i), name: String(r.name ?? ""), price: Math.max(0, toInt(r.price)) };
    })
    .filter((t) => t.name.trim() !== "");
  return {
    id,
    name: String(m.name ?? id),
    sortOrder: toInt(m.sortOrder),
    active: m.active !== false,
    multi: m.multi !== false,
    max: Math.max(0, toInt(m.max)),
    items,
  };
}

/** Đọc cả node note_groups / topping_groups; sắp theo sortOrder rồi tên */
export function parseCatalog(noteGroupsRaw: unknown, toppingGroupsRaw: unknown): ItemCatalog {
  const byOrder = <T extends { sortOrder: number; name: string }>(a: T, b: T) =>
    a.sortOrder - b.sortOrder || a.name.localeCompare(b.name, "vi");
  const notes = isRec(noteGroupsRaw) ? Object.entries(noteGroupsRaw).map(([k, v]) => parseNoteGroup(k, v)) : [];
  const tops = isRec(toppingGroupsRaw) ? Object.entries(toppingGroupsRaw).map(([k, v]) => parseToppingGroup(k, v)) : [];
  return { noteGroups: notes.sort(byOrder), toppingGroups: tops.sort(byOrder) };
}

/** Đọc trường danh sách id nhóm: undefined = không có trường (kế thừa) */
export function parseGroupIds(v: unknown): string[] | undefined {
  if (v == null) return undefined;
  return listOf(v).map(String).filter((s) => s !== "");
}

/** Giá trị ghi lên RTDB: undefined/null → null (xóa trường, kế thừa); rỗng → [NO_GROUPS] */
export function encodeGroupIds(ids: string[] | null | undefined): string[] | null {
  if (ids == null) return null;
  const clean = ids.filter((s) => s !== "" && s !== NO_GROUPS);
  return clean.length === 0 ? [NO_GROUPS] : clean;
}

export function isLegacyCatalog(c: ItemCatalog): boolean {
  return c.noteGroups.length === 0 && c.toppingGroups.length === 0;
}

function effective(productIds: string[] | null | undefined, categoryIds: string[] | null | undefined): [string[], OptionSource] {
  if (productIds != null) return [productIds, "product"];
  if (categoryIds != null) return [categoryIds, "category"];
  return [[], "none"];
}

function pick<T extends { id: string }>(ids: string[], all: T[]): T[] {
  const byId = new Map(all.map((g) => [g.id, g]));
  const seen = new Set<string>();
  const out: T[] = [];
  for (const id of ids) {
    const g = byId.get(id);
    if (g && !seen.has(id)) {
      seen.add(id);
      out.push(g);
    }
  }
  return out;
}

export function resolveItemOptions(
  product: GroupAttachments | null | undefined,
  category: GroupAttachments | null | undefined,
  catalog: ItemCatalog
): ResolvedItemOptions {
  if (isLegacyCatalog(catalog)) return { noteGroups: [], toppingGroups: [], legacy: true, noteSource: "none", toppingSource: "none" };
  const [noteIds, noteSource] = effective(product?.noteGroupIds, category?.noteGroupIds);
  const [topIds, toppingSource] = effective(product?.toppingGroupIds, category?.toppingGroupIds);
  return {
    noteGroups: pick(noteIds, catalog.noteGroups.filter((g) => g.active)).filter((g) => g.items.length > 0),
    toppingGroups: pick(topIds, catalog.toppingGroups.filter((g) => g.active)).filter((g) => g.items.length > 0),
    legacy: false,
    noteSource,
    toppingSource,
  };
}

/** Các câu note nhanh (bỏ trùng, giữ thứ tự) */
export function noteChips(r: Pick<ResolvedItemOptions, "noteGroups">): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const g of r.noteGroups)
    for (const n of g.items) {
      const t = n.text.trim();
      if (t && !seen.has(t.toLowerCase())) {
        seen.add(t.toLowerCase());
        out.push(t);
      }
    }
  return out;
}

/** Bật/tắt một topping theo luật nhóm (chọn một / tối đa N). Trả danh sách mới. */
export function toggleTopping(selected: string[], group: ToppingGroup, name: string): string[] {
  if (selected.includes(name)) return selected.filter((x) => x !== name);
  const names = new Set(group.items.map((t) => t.name));
  let next = [...selected];
  if (!group.multi) next = next.filter((x) => !names.has(x));
  else if (group.max > 0 && next.filter((x) => names.has(x)).length >= group.max) return next;
  next.push(name);
  return next;
}
