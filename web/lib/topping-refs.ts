/**
 * Topping cho phép của NHÓM MÓN (categories/{id}.allowedToppingIds) lưu bằng TÊN món topping.
 *
 * Trước đây web lưu KHÓA RTDB của món (products/{key}); app bản cũ chỉ tra theo id số / mã / tên nên
 * hiện mã thô với giá 5.000đ. Tên đọc được ở mọi bản app và web, và dùng chung được giữa các chi nhánh
 * (khóa mỗi chi nhánh một khác). Logic thuần — test ở test/topping-refs.test.ts.
 */
import { looksLikeRef } from "./product-options";

export interface RefProduct {
  id: string;
  name: string;
  code?: string;
  isTopping?: boolean;
  storeCode?: string;
}

export interface RefCategory {
  id: string;
  name: string;
  storeCode?: string;
  allowedToppingIds?: string[];
}

const lc = (s: unknown) => String(s ?? "").trim().toLowerCase();

/** Đổi từng tham chiếu (khóa / mã / tên) sang tên món topping; mã không còn món thì bỏ; bỏ trùng */
export function toppingRefsToNames(refs: string[], products: RefProduct[], fallback: RefProduct[] = []): string[] {
  const find = (list: RefProduct[], ref: string) => {
    const r = lc(ref);
    const matches = list.filter((p) => String(p.id) === String(ref).trim() || (p.code && lc(p.code) === r) || lc(p.name) === r);
    return matches.find((p) => p.isTopping) ?? matches[0];
  };
  const out: string[] = [];
  for (const ref of refs) {
    if (!lc(ref)) continue;
    // Nhóm món lưu cho "tất cả chi nhánh" chép cùng khóa của chi nhánh khác → tra thêm [fallback] để lấy tên
    const hit = find(products, ref) ?? find(fallback, ref);
    const name = hit ? hit.name.trim() : looksLikeRef(ref) ? "" : String(ref).trim();
    if (name && !out.some((n) => lc(n) === lc(name))) out.push(name);
  }
  return out;
}

export interface ToppingRefFix {
  storeCode: string;
  categoryId: string;
  categoryName: string;
  from: string[];
  to: string[];
}

/** Các nhóm món đang lưu topping bằng mã (cần đổi sang tên) — tra món của chính chi nhánh trước, rồi mọi chi nhánh */
export function planToppingRefFixes(categories: RefCategory[], products: RefProduct[]): ToppingRefFix[] {
  const fixes: ToppingRefFix[] = [];
  for (const c of categories) {
    const from = c.allowedToppingIds ?? [];
    if (from.length === 0 || !c.storeCode) continue;
    const to = toppingRefsToNames(from, products.filter((p) => p.storeCode === c.storeCode), products);
    if (to.length === from.length && to.every((n, i) => n === from[i])) continue;
    fixes.push({ storeCode: c.storeCode, categoryId: c.id, categoryName: c.name, from, to });
  }
  return fixes;
}

/** Lệnh ghi RTDB cho các bản sửa (mảng rỗng → null để xóa trường) */
export function toppingRefFixUpdates(fixes: ToppingRefFix[]): Record<string, string[] | null> {
  return Object.fromEntries(fixes.map((f) => [`stores/${f.storeCode}/categories/${f.categoryId}/allowedToppingIds`, f.to.length ? f.to : null]));
}
