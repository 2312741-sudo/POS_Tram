/**
 * Danh mục món có 2 nơi chọn topping: ô cũ "Topping được phép" (allowedToppingIds) và "Nhóm topping".
 * Khi danh mục đã gắn nhóm topping, POS chỉ đọc nhóm — nên topping tích ở ô cũ phải được ghi vào nhóm
 * riêng của danh mục, nếu không sẽ "không tự link qua".
 */
import type { ToppingGroup } from "./item-options";

const norm = (s: string) => s.trim().toLowerCase();

/** Nhóm topping riêng của danh mục: nhóm duy nhất được gắn, hoặc nhóm tự sinh `legacy_cat_<TÊN>` */
export function ownToppingGroupId(categoryName: string, toppingGroupIds: readonly string[]): string | null {
  if (toppingGroupIds.length === 1) return toppingGroupIds[0];
  const legacy = `legacy_cat_${categoryName.trim().replace(/\s+/g, "_")}`;
  return toppingGroupIds.find((id) => id === legacy) ?? null;
}

/**
 * Nhóm topping sau khi đồng bộ theo danh sách topping đã tích (null = không cần / không được ghi).
 * Không ghi khi nhóm đang dùng chung với danh mục khác (sửa sẽ ảnh hưởng nhóm kia).
 */
export function syncCategoryToppingGroup(args: {
  categoryName: string;
  toppingGroupIds: readonly string[];
  allowedToppings: readonly string[];
  groups: readonly ToppingGroup[];
  otherCategoryGroupIds: readonly (readonly string[])[];
  products: readonly { id: string; name: string; price: number; code?: string }[];
}): ToppingGroup | null {
  // Ô cũ để trống = chưa dùng → giữ nguyên nhóm (không xóa sạch topping của nhóm)
  if (args.allowedToppings.length === 0) return null;
  const gid = ownToppingGroupId(args.categoryName, args.toppingGroupIds);
  const group = gid ? args.groups.find((g) => g.id === gid) : undefined;
  if (!group) return null;
  if (args.otherCategoryGroupIds.some((ids) => ids.includes(group.id))) return null;

  const names: { name: string; price: number }[] = [];
  for (const ref of args.allowedToppings) {
    const p = args.products.find((x) => x.id === ref || norm(x.name) === norm(ref) || (x.code && norm(x.code) === norm(ref)));
    const name = p?.name ?? ref;
    if (!name.trim() || names.some((n) => norm(n.name) === norm(name))) continue;
    names.push({ name, price: p ? p.price : 0 });
  }
  const used = new Set(group.items.map((i) => i.id));
  let seq = group.items.length;
  const items = names.map(({ name, price }) => {
    const old = group.items.find((i) => norm(i.name) === norm(name));
    if (old) return old;
    let id = `t${++seq}`;
    while (used.has(id)) id = `t${++seq}`;
    used.add(id);
    return { id, name, price };
  });
  const same = items.length === group.items.length && items.every((i, k) => i === group.items[k]);
  return same ? null : { ...group, items };
}
