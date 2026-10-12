// scripts/migrate_note_catalog/plan.js
// SINH TỪ web/lib/note-catalog-migrate.ts (cùng quy tắc với Dart: app_flutter/lib/core/domain/note_catalog_migration.dart).
// Sửa quy tắc ở bản TS rồi sinh lại:  node -e "..." (xem README.md).
"use strict";
/**
 * "Nhập từ cấu hình cũ": dựng kế hoạch chuyển topping/ghi chú mẫu cũ sang danh mục note & topping mới
 * — LOGIC THUẦN, idempotent, KHÔNG ghi gì (trả về các đường dẫn cần ghi, tương đối theo stores/{s}).
 * Bản song song: app_flutter/lib/core/domain/note_catalog_migration.dart và scripts/migrate_note_catalog/plan.js.
 * Quy tắc: xem đầu file Dart / docs/NOTE_CATALOG.md.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.isDrinkCategoryName = exports.LEGACY_DEFAULT_TOPPINGS = void 0;
exports.legacyHash = legacyHash;
exports.planNoteCatalogMigration = planNoteCatalogMigration;
const isRec = (v) => typeof v === "object" && v !== null && !Array.isArray(v);
const rec = (v) => {
    if (Array.isArray(v)) {
        const o = {};
        v.forEach((x, i) => {
            if (x != null)
                o[String(i)] = x;
        });
        return o;
    }
    return isRec(v) ? v : {};
};
const strList = (v) => Array.isArray(v) ? v.filter((e) => e != null).map(String) : isRec(v) ? Object.values(v).map(String) : [];
exports.LEGACY_DEFAULT_TOPPINGS = [
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
const isDrinkCategoryName = (name) => {
    const c = name.toLowerCase();
    return DRINK_WORDS.some((w) => c.includes(w));
};
exports.isDrinkCategoryName = isDrinkCategoryName;
/** djb2 32-bit trên mã UTF-16 (giống bản Dart/JS) */
function legacyHash(s) {
    let h = 5381;
    for (let i = 0; i < s.length; i++)
        h = (Math.imul(h, 33) + s.charCodeAt(i)) >>> 0;
    return h.toString(16);
}
const sanitizeKey = (s) => s.replace(/[.#$[\]/\u0000-\u001f\u007f\s]+/g, "_");
function planNoteCatalogMigration(input) {
    const prods = rec(input.products);
    const cats = rec(input.categories);
    const notes = rec(input.productNotes);
    const existingNotes = rec(input.noteGroups);
    const existingTops = rec(input.toppingGroups);
    const updates = {};
    const summary = [];
    let newNote = 0;
    let newTop = 0;
    let attach = 0;
    const nameOf = (p, key) => (String(p.name ?? "").trim() ? String(p.name).trim() : key);
    const catOf = (p) => (isRec(p) ? String(p.category ?? "").trim() : "");
    const toInt = (v) => (typeof v === "number" ? Math.trunc(v) : 0);
    const toppingProds = [];
    const priceByName = new Map();
    const priceByRef = new Map();
    const nameByRef = new Map();
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
        if (isTop)
            toppingProds.push({ name, price: Math.max(0, price) });
    }
    for (const d of exports.LEGACY_DEFAULT_TOPPINGS)
        if (!priceByName.has(d.name.toLowerCase()))
            priceByName.set(d.name.toLowerCase(), d.price);
    const itemsOf = (src) => src.map((s, i) => ({ id: `t${i + 1}`, name: s.name, price: s.price }));
    const toppingGroup = (name, order, items) => ({
        name,
        sortOrder: order,
        active: true,
        multi: true,
        max: 0,
        items: itemsOf(items),
    });
    const resolveRef = (ref) => {
        const r = ref.trim();
        const byRef = priceByRef.get(r) ?? priceByRef.get(r.toLowerCase());
        if (byRef !== undefined)
            return { name: nameByRef.get(r) ?? nameByRef.get(r.toLowerCase()) ?? r, price: byRef };
        return { name: r, price: priceByName.get(r.toLowerCase()) ?? 5000 };
    };
    const dedupe = (items) => {
        const seen = new Set();
        return items.filter((e) => {
            const k = e.name.toLowerCase();
            if (seen.has(k))
                return false;
            seen.add(k);
            return true;
        });
    };
    const addTopGroup = (id, g, label) => {
        if (id in existingTops || `topping_groups/${id}` in updates)
            return;
        updates[`topping_groups/${id}`] = g;
        newTop++;
        summary.push(`Nhóm topping "${label}" (${g.items.length} topping)`);
    };
    const shared = toppingProds.length > 0 ? toppingProds : exports.LEGACY_DEFAULT_TOPPINGS.map((e) => ({ ...e }));
    const catKeys = Object.keys(cats).sort();
    const needShared = catKeys.some((k) => {
        const c = rec(cats[k]);
        return strList(c.allowedToppingIds).length === 0 && c.toppingGroupIds == null && (0, exports.isDrinkCategoryName)(String(c.name ?? k));
    });
    if (needShared)
        addTopGroup("legacy_toppings", toppingGroup("Topping", 1, shared), "Topping");
    const noteItems = [];
    for (const k of Object.keys(notes).sort()) {
        const v = notes[k];
        const text = String(isRec(v) ? (v.text ?? v.name ?? "") : (v ?? "")).trim();
        if (text)
            noteItems.push({ id: k, text });
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
    const catAllowed = new Map();
    for (const k of catKeys) {
        const c = rec(cats[k]);
        const cname = String(c.name ?? "").trim() ? String(c.name).trim() : k;
        const allowed = strList(c.allowedToppingIds);
        catAllowed.set(cname.toLowerCase(), allowed.length > 0);
        const drink = (0, exports.isDrinkCategoryName)(cname);
        if (c.toppingGroupIds == null) {
            if (allowed.length > 0) {
                const gid = `legacy_cat_${sanitizeKey(k)}`;
                addTopGroup(gid, toppingGroup(`Topping - ${cname}`, 2, dedupe(allowed.map(resolveRef))), `Topping - ${cname}`);
                updates[`categories/${k}/toppingGroupIds`] = [gid];
                attach++;
            }
            else if (drink) {
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
        if (own.length === 0 || p.toppingGroupIds != null)
            continue;
        if (catAllowed.get(catOf(p).toLowerCase()) === true)
            continue;
        const items = dedupe(own.map(resolveRef)).sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
        const gid = `legacy_set_${legacyHash(items.map((e) => e.name).join("|"))}`;
        addTopGroup(gid, toppingGroup(`Topping riêng (${items.slice(0, 2).map((e) => e.name).join(", ")}...)`, 3, items), gid);
        updates[`products/${k}/toppingGroupIds`] = [gid];
        attach++;
    }
    if (attach > 0)
        summary.push(`Gắn danh mục vào ${attach} nhóm món/món`);
    return { updates, summary, newNoteGroups: newNote, newToppingGroups: newTop, attachments: attach };
}
