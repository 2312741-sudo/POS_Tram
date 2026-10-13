/**
 * Thứ tự danh mục sản phẩm: stores/{code}/categories/{tên}/order (số nguyên, nhỏ đứng trước).
 * Danh mục chưa có `order` xếp sau các danh mục đã sắp xếp, rồi theo tên.
 * Bản Dart song song: app_flutter/lib/data/models/category_model.dart (compareCategories).
 */
export interface OrderedByName {
  name: string;
  order?: number | null;
}

export function compareCategories(a: OrderedByName, b: OrderedByName): number {
  const oa = typeof a.order === "number" ? a.order : null;
  const ob = typeof b.order === "number" ? b.order : null;
  if (oa !== null && ob !== null && oa !== ob) return oa - ob;
  if (oa !== null && ob === null) return -1;
  if (oa === null && ob !== null) return 1;
  return a.name.localeCompare(b.name, "vi");
}

export function sortCategories<T extends OrderedByName>(list: T[]): T[] {
  return [...list].sort(compareCategories);
}

/** Đổi chỗ phần tử tại `index` với láng giềng (delta -1 lên, +1 xuống); trả về null nếu không đổi được */
export function moveName(names: string[], index: number, delta: -1 | 1): string[] | null {
  const j = index + delta;
  if (index < 0 || index >= names.length || j < 0 || j >= names.length) return null;
  const next = [...names];
  [next[index], next[j]] = [next[j], next[index]];
  return next;
}

/** Cập nhật đa đường dẫn ghi `order` cho từng danh mục có trong chi nhánh (khóa node = tên danh mục) */
export function buildCategoryOrderUpdates(storeCode: string, orderedNames: string[], existing: Set<string>): Record<string, number> {
  const updates: Record<string, number> = {};
  let i = 0;
  for (const n of orderedNames) {
    if (!existing.has(n)) continue;
    updates[`stores/${storeCode}/categories/${n}/order`] = i++;
  }
  return updates;
}
