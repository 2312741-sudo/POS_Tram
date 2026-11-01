/**
 * Dọn MÓN TRÙNG trong thực đơn một chi nhánh (cùng mã món, khác khóa RTDB) — logic thuần, test ở test/menu-dedupe.test.ts.
 *
 * Món trùng làm báo cáo tách dòng / rơi nhóm "Khác", gọi món dễ chọn nhầm bản sai nhóm.
 * Mỗi nhóm trùng giữ MỘT bản, theo thứ tự ưu tiên:
 *   1. đang nối kho (catalog_items.legacyProductId = id số của món) — xóa nhầm bản này thì bán không trừ kho;
 *   2. có nhóm hàng thật (khác rỗng / "Khác");
 *   3. đã gắn nhóm topping / note, có size;
 *   4. khóa nhỏ nhất (ổn định).
 * Bản giữ lại được chép thêm những gì nó còn thiếu từ bản bị xóa (nhóm hàng, nhóm topping/note, size, topping riêng).
 * Hóa đơn cũ không cần sửa: báo cáo đã gom theo mã món.
 */

type Rec = Record<string, unknown>;

export interface DupProduct {
  key: string;
  name: string;
  code: string;
  category: string;
  price: number;
  isTopping: boolean;
  /** Đang nối kho (có mặt hàng kho trỏ tới id số của món) */
  linkedStock: boolean;
}

export interface DupGroup {
  code: string;
  name: string;
  keep: DupProduct;
  remove: DupProduct[];
  /** Trường chép sang bản giữ lại */
  patch: Rec;
}

const norm = (v: unknown) => String(v ?? "").trim().toLowerCase().replace(/\s+/g, " ");
const isRec = (v: unknown): v is Rec => !!v && typeof v === "object" && !Array.isArray(v);
const realCategory = (c: unknown) => !!norm(c) && norm(c) !== "khác";
const hasList = (v: unknown) => (Array.isArray(v) ? v.length > 0 : isRec(v) ? Object.keys(v).length > 0 : false);

/** Id số của món (khớp ProductModel.id bên app khi trường id là số) */
function numericId(p: Rec): number | null {
  const n = Number(p.id);
  return Number.isInteger(n) && n > 0 ? n : null;
}

export function planMenuDedupe(productsRaw: unknown, catalogItemsRaw: unknown): DupGroup[] {
  const products = isRec(productsRaw) ? productsRaw : {};
  const linkedIds = new Set<number>();
  if (isRec(catalogItemsRaw)) {
    for (const v of Object.values(catalogItemsRaw)) {
      const n = isRec(v) ? Number(v.legacyProductId) : NaN;
      if (Number.isInteger(n) && n > 0) linkedIds.add(n);
    }
  }

  const byCode = new Map<string, { key: string; raw: Rec }[]>();
  for (const [key, v] of Object.entries(products)) {
    if (!isRec(v)) continue;
    const code = norm(v.code ?? v.productCode);
    if (!code) continue; // không có mã thì không đủ chắc là trùng
    const list = byCode.get(code) ?? [];
    list.push({ key, raw: v });
    byCode.set(code, list);
  }

  const groups: DupGroup[] = [];
  for (const [code, list] of byCode) {
    if (list.length < 2) continue;
    const view = (e: { key: string; raw: Rec }): DupProduct => {
      const id = numericId(e.raw);
      return {
        key: e.key,
        name: String(e.raw.name ?? e.key),
        code: String(e.raw.code ?? e.raw.productCode ?? code),
        category: String(e.raw.category ?? ""),
        price: Number(e.raw.price) || 0,
        isTopping: e.raw.isTopping === true,
        linkedStock: id != null && linkedIds.has(id),
      };
    };
    const score = (e: { key: string; raw: Rec }) => {
      const p = view(e);
      return (
        (p.linkedStock ? 8 : 0) +
        (realCategory(p.category) ? 4 : 0) +
        (hasList(e.raw.toppingGroupIds) || hasList(e.raw.noteGroupIds) ? 2 : 0) +
        (hasList(e.raw.sizes) ? 1 : 0)
      );
    };
    const sorted = [...list].sort((a, b) => score(b) - score(a) || a.key.localeCompare(b.key));
    const [keepE, ...rest] = sorted;
    const patch: Rec = {};
    const k = keepE.raw;
    for (const r of rest.map((e) => e.raw)) {
      if (!realCategory(k.category) && !("category" in patch) && realCategory(r.category)) patch.category = r.category;
      for (const f of ["toppingGroupIds", "noteGroupIds", "sizes", "allowedToppings"]) {
        if (!hasList(k[f]) && !(f in patch) && hasList(r[f])) patch[f] = r[f];
      }
      if (k.isTopping !== true && r.isTopping === true && !("isTopping" in patch)) patch.isTopping = true;
    }
    groups.push({ code: view(keepE).code, name: view(keepE).name, keep: view(keepE), remove: rest.map(view), patch });
  }
  return groups.sort((a, b) => a.name.localeCompare(b.name, "vi"));
}

/** Lệnh ghi RTDB cho các nhóm được chọn */
export function menuDedupeUpdates(storeCode: string, groups: DupGroup[]): Record<string, unknown> {
  const u: Record<string, unknown> = {};
  for (const g of groups) {
    for (const [f, v] of Object.entries(g.patch)) u[`stores/${storeCode}/products/${g.keep.key}/${f}`] = v;
    for (const r of g.remove) u[`stores/${storeCode}/products/${r.key}`] = null;
  }
  return u;
}
