/**
 * Tùy chọn món khi gọi trên Web — cùng quy tắc với POS Flutter (order_cart_screen.dart):
 *  - size: product.sizes {S:0,M:5000,...}; thiếu thì mặc định S/M/L cho đồ uống
 *  - topping: ưu tiên category.allowedToppingIds → product.allowedToppings → mọi món topping → bộ topping mặc định
 *  - đường / đá: khi món là đồ uống (hasIceSugarOptions, có size hoặc danh mục đồ uống)
 */
import type { RawOrderLine } from "./order-math";
import { productIdValue, type OrderActor } from "./web-order";
import { isLegacyCatalog, noteChips, resolveItemOptions, type ItemCatalog, type ToppingGroup } from "./item-options";

export const SUGAR_OPTIONS = ["100% đường", "70% đường", "50% đường", "30% đường", "Không đường"];
export const ICE_OPTIONS = ["100% đá", "70% đá", "50% đá", "Không đá", "Uống nóng"];
export const DEFAULT_SUGAR = SUGAR_OPTIONS[0];
export const DEFAULT_ICE = ICE_OPTIONS[0];

export interface OptionProduct {
  id: string;
  name: string;
  price: number;
  code?: string;
  category?: string;
  unit?: string;
  isTopping?: boolean;
  sizes?: Record<string, number>;
  allowedToppings?: string[];
  hasIceSugarOptions?: boolean | null;
  /** Gắn danh mục note/topping (xem item-options.ts) */
  noteGroupIds?: string[];
  toppingGroupIds?: string[];
}

export interface OptionCategory {
  name: string;
  allowedToppingIds?: string[];
  noteGroupIds?: string[];
  toppingGroupIds?: string[];
}

export interface ToppingOption {
  name: string;
  price: number;
}

export interface SizeOption {
  name: string;
  extra: number;
}

export interface ProductOptions {
  sizes: SizeOption[];
  toppings: ToppingOption[];
  iceSugar: boolean;
  /** Chi nhánh đã cấu hình danh mục note/topping → chỉ hiện nhóm được gắn */
  catalogMode: boolean;
  /** Nhóm topping được gắn (chỉ khi catalogMode) — để hiển thị theo nhóm / luật chọn một, tối đa */
  toppingGroups: ToppingGroup[];
  /** Câu note nhanh từ các nhóm note được gắn (chỉ khi catalogMode) */
  noteChips: string[];
  /** Món có bất kỳ tùy chọn nào cần hỏi */
  hasAny: boolean;
}

export const DEFAULT_FNB_TOPPINGS: ToppingOption[] = [
  { name: "Trân châu đen", price: 5000 },
  { name: "Trân châu trắng", price: 6000 },
  { name: "Thạch phô mai", price: 8000 },
  { name: "Thạch củ năng", price: 7000 },
  { name: "Kem Cheese", price: 10000 },
  { name: "Pudding trứng", price: 7000 },
  { name: "Đào miếng", price: 8000 },
  { name: "Thạch chanh", price: 5000 },
];

const lc = (s: string | undefined) => (s ?? "").trim().toLowerCase();

/** Đồ uống theo quy tắc mặc định của ProductModel.fromMap */
function isDefaultDrink(category: string | undefined): boolean {
  const c = category ?? "";
  return c.includes("Trà") || c.includes("CAFE") || c.includes("Sữa") || c.includes("Bơ");
}

/** Đồ uống theo quy tắc hiển thị đường/đá của màn gọi món POS */
function isDrinkCategory(category: string | undefined): boolean {
  const c = lc(category);
  return ["trà", "tea", "cà phê", "cafe", "coffee", "nước", "uống", "sinh tố", "đá xay", "sữa", "matcha"].some((k) => c.includes(k));
}

export function getProductOptions(
  product: OptionProduct,
  categories: OptionCategory[],
  allProducts: OptionProduct[],
  catalog?: ItemCatalog
): ProductOptions {
  if (product.isTopping) return { sizes: [], toppings: [], iceSugar: false, catalogMode: false, toppingGroups: [], noteChips: [], hasAny: false };

  // --- size
  let sizeMap: Record<string, number> = {};
  if (product.sizes && typeof product.sizes === "object") {
    for (const [k, v] of Object.entries(product.sizes)) sizeMap[k] = Math.max(0, Math.trunc(Number(v)) || 0);
  }
  if (Object.keys(sizeMap).length === 0 && isDefaultDrink(product.category)) sizeMap = { S: 0, M: 5000, L: 10000 };
  const sizes = Object.entries(sizeMap).map(([name, extra]) => ({ name, extra }));

  // --- topping
  const toppingProducts = allProducts.filter((p) => p.isTopping || lc(p.category).includes("topping"));
  const resolve = (ref: string): ToppingOption => {
    const r = lc(ref);
    const hit =
      allProducts.find((p) => p.id === ref || (p.code && lc(p.code) === r) || lc(p.name) === r) ??
      undefined;
    if (hit) return { name: hit.name, price: Math.max(0, Math.trunc(hit.price) || 0) };
    const def = DEFAULT_FNB_TOPPINGS.find((t) => lc(t.name) === r);
    return def ?? { name: ref, price: 5000 };
  };
  const cat = categories.find((c) => lc(c.name) === lc(product.category));
  const rawToppings = isDefaultDrink(product.category) && !(product.allowedToppings?.length) ? DEFAULT_FNB_TOPPINGS.map((t) => t.name) : product.allowedToppings ?? [];
  let toppings: ToppingOption[];
  if (cat?.allowedToppingIds && cat.allowedToppingIds.length > 0) toppings = cat.allowedToppingIds.map(resolve);
  else if (rawToppings.length > 0) toppings = rawToppings.map(resolve);
  else {
    toppings = toppingProducts.map((p) => ({ name: p.name, price: Math.max(0, Math.trunc(p.price) || 0) }));
    for (const t of DEFAULT_FNB_TOPPINGS) if (!toppings.some((x) => lc(x.name) === lc(t.name))) toppings.push(t);
  }
  // Chỉ hỏi topping với món đồ uống/có cấu hình topping — món ăn khác không bị hỏi topping mặc định
  const wantsToppings = isDrinkCategory(product.category) || isDefaultDrink(product.category) || !!cat?.allowedToppingIds?.length || !!product.allowedToppings?.length || sizes.length > 0;
  let uniq: ToppingOption[] = [];
  for (const t of wantsToppings ? toppings : []) if (!uniq.some((x) => lc(x.name) === lc(t.name))) uniq.push(t);

  // Đã cấu hình danh mục note/topping: chỉ hiện nhóm được gắn cho món / nhóm món (mặc định không có gì)
  const resolved = catalog && !isLegacyCatalog(catalog) ? resolveItemOptions(product, cat, catalog) : null;
  let toppingGroups: ToppingGroup[] = [];
  let chips: string[] = [];
  if (resolved) {
    toppingGroups = resolved.toppingGroups;
    chips = noteChips(resolved);
    uniq = [];
    for (const g of toppingGroups) for (const t of g.items) if (!uniq.some((x) => lc(x.name) === lc(t.name))) uniq.push({ name: t.name, price: t.price });
  }

  const iceSugar =
    product.hasIceSugarOptions === true ||
    (product.hasIceSugarOptions == null && isDefaultDrink(product.category)) ||
    sizes.length > 0 ||
    isDrinkCategory(product.category);

  return { sizes, toppings: uniq, iceSugar, catalogMode: !!resolved, toppingGroups, noteChips: chips, hasAny: sizes.length > 0 || uniq.length > 0 || iceSugar || chips.length > 0 };
}

export interface OptionSelection {
  size: string;
  sugar: string;
  ice: string;
  toppings: string[];
}

/** Lựa chọn mặc định: size nhỏ nhất (extra thấp nhất), 100% đường/đá */
export function defaultSelection(opts: ProductOptions): OptionSelection {
  const size = [...opts.sizes].sort((a, b) => a.extra - b.extra)[0]?.name ?? "";
  return { size, sugar: opts.iceSugar ? DEFAULT_SUGAR : "", ice: opts.iceSugar ? DEFAULT_ICE : "", toppings: [] };
}

/** Dòng món có tùy chọn — trường giống OrderItemModel.toMap() của POS */
export function makeConfiguredLine(
  product: OptionProduct,
  opts: ProductOptions,
  sel: OptionSelection,
  quantity: number,
  note: string,
  actor: OrderActor,
  now: number
): RawOrderLine {
  const size = opts.sizes.find((s) => s.name === sel.size);
  const picked = sel.toppings
    .map((n) => opts.toppings.find((t) => t.name === n))
    .filter((t): t is ToppingOption => !!t);
  const line: RawOrderLine = {
    productId: productIdValue(product.id),
    name: product.name,
    price: Math.max(0, Math.trunc(product.price) || 0),
    quantity: Math.max(1, Math.trunc(quantity) || 1),
    note: note.trim(),
    isSentKitchen: false,
    discountAmount: 0,
    lineDiscountTotal: 0,
    discountedQuantity: 0,
    orderedBy: actor.username,
    orderedByName: actor.fullName || actor.username,
    orderedAt: now,
  };
  if (product.category) line.category = product.category;
  if (product.unit) line.unit = product.unit;
  if (size) {
    line.selectedSize = size.name;
    if (size.extra > 0) line.sizeExtraPrice = size.extra;
  }
  if (opts.iceSugar) {
    if (sel.sugar) line.selectedSugar = sel.sugar;
    if (sel.ice) line.selectedIce = sel.ice;
  }
  if (picked.length > 0) {
    line.selectedToppings = picked.map((t) => t.name);
    const total = picked.reduce((s, t) => s + t.price, 0);
    if (total > 0) line.toppingPrice = total;
  }
  return line;
}

/** Mô tả ngắn các tùy chọn đã chọn: "Size M • 70% đường • 50% đá • + Trân châu đen" */
export function describeSelection(line: RawOrderLine): string {
  const parts: string[] = [];
  if (line.selectedSize) parts.push(`Size ${String(line.selectedSize)}`);
  if (line.selectedSugar) parts.push(String(line.selectedSugar));
  if (line.selectedIce) parts.push(String(line.selectedIce));
  if (Array.isArray(line.selectedToppings) && line.selectedToppings.length > 0) parts.push(`+ ${line.selectedToppings.map(String).join(", ")}`);
  return parts.join(" • ");
}
