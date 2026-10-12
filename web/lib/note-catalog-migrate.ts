/**
 * "Nhập từ cấu hình cũ": dựng kế hoạch chuyển topping/ghi chú mẫu cũ sang danh mục note & topping mới
 * — LOGIC THUẦN, idempotent, KHÔNG ghi gì (trả về các đường dẫn cần ghi, tương đối theo stores/{s}).
 * Bản song song: app_flutter/lib/core/domain/note_catalog_migration.dart và scripts/migrate_note_catalog/plan.js.
 * Quy tắc: xem đầu file Dart / docs/NOTE_CATALOG.md.
 */

type Rec = Record<string, unknown>;
const isRec = (v: unknown): v is Rec => typeof v === "object" && v !== null && !Array.isArray(v);
const rec = (v: unknown): Rec => {
  if (Array.isArray(v)) {
    const o: Rec = {};
    v.forEach((x, i) => {
      if (x != null) o[String(i)] = x;
    });
    return o;
  }
  return isRec(v) ? v : {};
};
const strList = (v: unknown): string[] =>
  Array.isArray(v) ? v.filter((e) => e != null).map(String) : isRec(v) ? Object.values(v).map(String) : [];

export const LEGACY_DEFAULT_TOPPINGS = [
  { name: "Trân châu đen", price: 5000 },
  { name: "Trân châu trắng", price: 6000 },
  { name: "Thạch phô mai", price: 8000 },
  { name: "Thạch củ năng", price: 7000 },
  { name: "Kem Cheese", price: 10000 },
  { name: "Pudding trứng", price: 7000 },
  { name: "Đào miếng", price: 8000 },
  { name: "Thạch chanh", price: 5000 },
];

const DRINK_WORDS = ["trà", "tea", "cà phê", "cafe", "coffee", "nước", "uống", "sinh tố", "đá xay", "sữa", "matcha", "bơ"];
export const isDrinkCategoryName = (name: string): boolean => {
  const c = name.toLowerCase();
  return DRINK_WORDS.some((w) => c.includes(w));
};

/** djb2 32-bit trên mã UTF-16 (giống bản Dart/JS) */
export function legacyHash(s: string): string {
  let h = 5381;
  for (let i = 0; i < s.length; i++) h = (Math.imul(h, 33) + s.charCodeAt(i)) >>> 0;
  return h.toString(16);
}

const sanitizeKey = (s: string): string => s.replace(/[.#$[\]/\u0000-\u001f\u007f\s]+/g, "_");

export interface MigrationPlan {
  updates: Record<string, unknown>;
  summary: string[];
  newNoteGroups: number;
  newToppingGroups: number;
  attachments: number;
}

interface Item {
  name: string;
  price: number;
}

export function planNoteCatalogMigration(input: {
  products: unknown;
  categories: unknown;
  productNotes: unknown;
  noteGroups: unknown;
  toppingGroups: unknown;
}): MigrationPlan {
  const prods = rec(input.products);
  const cats = rec(input.categories);
  const notes = rec(input.productNotes);
  const existingNotes = rec(input.noteGroups);
  const existingTops = rec(input.toppingGroups);
  const updates: Record<string, unknown> = {};
  const summary: string[] = [];
  let newNote = 0;
  let newTop = 0;
  let attach = 0;

  const nameOf = (p: Rec, key: string) => (String(p.name ?? "").trim() ? String(p.name).trim() : key);
  const catOf = (p: unknown) => (isRec(p) ? String(p.category ?? "").trim() : "");
  const toInt = (v: unknown) => (typeof v === "number" ? Math.trunc(v) : 0);

  const toppingProds: Item[] = [];
  const priceByName = new Map<string, number>();
  const priceByRef = new Map<string, number>();
  const nameByRef = new Map<string, string>();
  const sortedKeys = Object.keys(prods).sort();
  for (const k of sortedKeys) {
    const p = rec(prods[k]);
    const name = nameOf(p, k);
    const price = toInt(p.price);
    const isTop = p.isTopping === true || catOf(p).toLowerCase().includes("topping");
    priceByName.set(name.toLowerCase(), price);
    const id = p.id != null ? String(p.id) : "";
    if (id) {
      priceByRef.set(id, price);
      nameByRef.set(id, name);
    }
    const code = p.code != null ? String(p.code) : "";
    if (code) {
      priceByRef.set(code.toLowerCase(), price);
      nameByRef.set(code.toLowerCase(), name);
    }
    if (isTop) toppingProds.push({ name, price: Math.max(0, price) });
  }
  for (const d of LEGACY_DEFAULT_TOPPINGS) if (!priceByName.has(d.name.toLowerCase())) priceByName.set(d.name.toLowerCase(), d.price);

  const itemsOf = (src: Item[]) => src.map((s, i) => ({ id: `t${i + 1}`, name: s.name, price: s.price }));
  const toppingGroup = (name: string, order: number, items: Item[]) => ({
    name,
    sortOrder: order,
    active: true,
    multi: true,
    max: 0,
    items: itemsOf(items),
  });
  const resolveRef = (ref: string): Item => {
    const r = ref.trim();
    const byRef = priceByRef.get(r) ?? priceByRef.get(r.toLowerCase());
    if (byRef !== undefined) return { name: nameByRef.get(r) ?? nameByRef.get(r.toLowerCase()) ?? r, price: byRef };
    return { name: r, price: priceByName.get(r.toLowerCase()) ?? 5000 };
  };
  const dedupe = (items: Item[]) => {
    const seen = new Set<string>();
    return items.filter((e) => {
      const k = e.name.toLowerCase();
      if (seen.has(k)) return false;
      seen.add(k);
      return true;
    });
  };
  const addTopGroup = (id: string, g: ReturnType<typeof toppingGroup>, label: string) => {
    if (id in existingTops || `topping_groups/${id}` in updates) return;
    updates[`topping_groups/${id}`] = g;
    newTop++;
    summary.push(`Nhóm topping "${label}" (${g.items.length} topping)`);
  };

  const shared: Item[] = toppingProds.length > 0 ? toppingProds : LEGACY_DEFAULT_TOPPINGS.map((e) => ({ ...e }));
  const catKeys = Object.keys(cats).sort();
  const needShared = catKeys.some((k) => {
    const c = rec(cats[k]);
    return strList(c.allowedToppingIds).length === 0 && c.toppingGroupIds == null && isDrinkCategoryName(String(c.name ?? k));
  });
  if (needShared) addTopGroup("legacy_toppings", toppingGroup("Topping", 1, shared), "Topping");

  const noteItems: { id: string; text: string }[] = [];
  for (const k of Object.keys(notes).sort()) {
    const v = notes[k];
    const text = String(isRec(v) ? (v.text ?? v.name ?? "") : (v ?? "")).trim();
    if (text) noteItems.push({ id: k, text });
  }
  let attachNotes = false;
  if (noteItems.length > 0) {
    attachNotes = true;
    if (!("legacy_notes" in existingNotes)) {
      updates["note_groups/legacy_notes"] = { name: "Ghi chú nhanh", sortOrder: 1, active: true, items: noteItems };
      newNote++;
      summary.push(`Nhóm note "Ghi chú nhanh" (${noteItems.length} câu)`);
    }
  }

  const catAllowed = new Map<string, boolean>();
  for (const k of catKeys) {
    const c = rec(cats[k]);
    const cname = String(c.name ?? "").trim() ? String(c.name).trim() : k;
    const allowed = strList(c.allowedToppingIds);
    catAllowed.set(cname.toLowerCase(), allowed.length > 0);
    const drink = isDrinkCategoryName(cname);
    if (c.toppingGroupIds == null) {
      if (allowed.length > 0) {
        const gid = `legacy_cat_${sanitizeKey(k)}`;
        addTopGroup(gid, toppingGroup(`Topping - ${cname}`, 2, dedupe(allowed.map(resolveRef))), `Topping - ${cname}`);
        updates[`categories/${k}/toppingGroupIds`] = [gid];
        attach++;
      } else if (drink) {
        updates[`categories/${k}/toppingGroupIds`] = ["legacy_toppings"];
        attach++;
      }
    }
    if (attachNotes && drink && c.noteGroupIds == null) {
      updates[`categories/${k}/noteGroupIds`] = ["legacy_notes"];
      attach++;
    }
  }

  for (const k of sortedKeys) {
    const p = rec(prods[k]);
    const own = strList(p.allowedToppings);
    if (own.length === 0 || p.toppingGroupIds != null) continue;
    if (catAllowed.get(catOf(p).toLowerCase()) === true) continue;
    const items = dedupe(own.map(resolveRef)).sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
    const gid = `legacy_set_${legacyHash(items.map((e) => e.name).join("|"))}`;
    addTopGroup(gid, toppingGroup(`Topping riêng (${items.slice(0, 2).map((e) => e.name).join(", ")}...)`, 3, items), gid);
    updates[`products/${k}/toppingGroupIds`] = [gid];
    attach++;
  }

  if (attach > 0) summary.push(`Gắn danh mục vào ${attach} nhóm món/món`);
  return { updates, summary, newNoteGroups: newNote, newToppingGroups: newTop, attachments: attach };
}
