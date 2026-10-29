/**
 * Tách một dòng món thành MÓN GỐC + từng TOPPING để báo cáo hàng hóa đếm số bán / doanh thu topping riêng.
 * Bản Dart song song: app_flutter/lib/core/reports/topping_split.dart (giữ cùng quy tắc).
 *
 * Dữ liệu dòng món: price (giá món), sizeExtraPrice, selectedToppings (tên, hoặc {name, price}),
 * toppingPrice (tổng tiền topping cho MỘT phần), quantity, giảm giá cả dòng (itemLineDiscount).
 *  - Món gốc = (price + sizeExtraPrice) × số lượng.
 *  - Mỗi topping = đơn giá topping × số lượng. Đơn giá: giá lưu trên dòng → giá món topping trong thực đơn (tra theo tên)
 *    → chia đều toppingPrice. Có toppingPrice thì các đơn giá được co giãn cho khớp đúng tổng đó.
 *  - Giảm giá cả dòng chia theo tỉ lệ tiền giữa món gốc và các topping (tổng không đổi).
 */
import { itemLineDiscount, type OrderItem } from "./reports";

export interface ToppingLookup {
  id?: string | number;
  code?: string;
  productCode?: string;
  price?: number;
  category?: string;
  costPrice?: number;
  unit?: string;
}

export interface LinePart {
  isTopping: boolean;
  /** Khóa gộp: món gốc = productId/tên; topping = id món topping hoặc "TOPPING:<tên>" */
  key: string;
  name: string;
  productId?: string | number;
  code: string;
  category: string;
  unit: string;
  quantity: number;
  grossRevenue: number;
  itemDiscount: number;
  costPrice: number;
  /** Topping: tên món gốc đi kèm */
  parentName?: string;
}

const num = (v: unknown) => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};

/** Tên topping (+ giá nếu dòng có lưu) */
export function toppingEntries(it: OrderItem): { name: string; price?: number }[] {
  const raw = it.selectedToppings ?? (it as { toppings?: unknown }).toppings;
  const list = Array.isArray(raw) ? raw : raw && typeof raw === "object" ? Object.values(raw as Record<string, unknown>) : [];
  const out: { name: string; price?: number }[] = [];
  for (const e of list) {
    if (e == null) continue;
    if (typeof e === "object") {
      const name = String((e as { name?: unknown }).name ?? "").trim();
      const p = (e as { price?: unknown }).price;
      if (name) out.push({ name, price: p == null ? undefined : num(p) });
    } else {
      const name = String(e).trim();
      if (name) out.push({ name });
    }
  }
  return out;
}

/** Chia [total] theo trọng số (làm tròn, phần dư dồn vào phần tử cuối) */
function allocate(total: number, weights: number[]): number[] {
  const sum = weights.reduce((s, w) => s + w, 0);
  if (weights.length === 0) return [];
  if (sum <= 0) {
    const each = Math.floor(total / weights.length);
    return weights.map((_, i) => (i === weights.length - 1 ? total - each * (weights.length - 1) : each));
  }
  let acc = 0;
  return weights.map((w, i) => {
    if (i === weights.length - 1) return total - acc;
    const v = Math.round((total * w) / sum);
    acc += v;
    return v;
  });
}

export function splitLineParts(
  it: OrderItem,
  lookupTopping?: (name: string) => ToppingLookup | undefined
): LinePart[] {
  const qty = num(it.quantity ?? it.count ?? 1) > 0 ? num(it.quantity ?? it.count ?? 1) : 1;
  const mainUnit = num(it.price) + num(it.sizeExtraPrice);
  const tops = toppingEntries(it);
  const lookups = tops.map((t) => lookupTopping?.(t.name));

  // Đơn giá từng topping cho MỘT phần
  const known = tops.map((t, i) => (t.price != null ? t.price : num(lookups[i]?.price)));
  const toppingUnitTotal = num(it.toppingPrice) > 0 ? num(it.toppingPrice) : known.reduce((s, p) => s + p, 0);
  const topUnits = tops.length ? allocate(toppingUnitTotal, known) : [];

  const topGross = topUnits.map((u) => u * qty);
  const topGrossSum = topGross.reduce((s, g) => s + g, 0);
  // Dữ liệu web có lineGrossAmount (đã gồm topping) → món gốc = phần còn lại
  const totalGross = it.lineGrossAmount != null ? num(it.lineGrossAmount) : mainUnit * qty + topGrossSum;
  const mainGross = Math.max(0, totalGross - topGrossSum);

  const discount = Math.min(Math.max(0, itemLineDiscount(it)), mainGross + topGrossSum);
  const discounts = allocate(discount, [mainGross, ...topGross]);

  // Giá vốn topping chuyển sang dòng topping. lineCostPrice / unitCost của dữ liệu đã GỒM topping → trừ ra cho món gốc;
  // costPrice là giá vốn riêng món gốc.
  const topCosts = tops.map((_, i) => num(lookups[i]?.costPrice) * qty);
  const topCostSum = topCosts.reduce((s, c) => s + c, 0);
  const mainCost = it.lineCostPrice != null
    ? Math.max(0, num(it.lineCostPrice) - topCostSum)
    : it.unitCost != null
      ? Math.max(0, num(it.unitCost) * qty - topCostSum)
      : num(it.costPrice) * qty;
  const parts: LinePart[] = [{
    isTopping: false,
    key: String(it.productId ?? it.name ?? "0"),
    name: it.name || "",
    productId: it.productId,
    code: "",
    category: it.category || "",
    unit: it.unit || "",
    quantity: qty,
    grossRevenue: mainGross,
    itemDiscount: discounts[0] ?? 0,
    costPrice: mainCost,
  }];
  tops.forEach((t, i) => {
    const lk = lookups[i];
    parts.push({
      isTopping: true,
      key: lk?.id != null ? `topping:id:${lk.id}` : `topping:${t.name.trim().toLowerCase().replace(/\s+/g, " ")}`,
      name: t.name,
      productId: lk?.id ?? 0,
      code: lk?.productCode || lk?.code || "",
      category: lk?.category && lk.category !== "Khác" ? lk.category : "Topping",
      unit: lk?.unit || "Phần",
      quantity: qty,
      grossRevenue: topGross[i],
      itemDiscount: discounts[i + 1] ?? 0,
      costPrice: topCosts[i],
      parentName: it.name || "",
    });
  });
  return parts;
}

/** Tra món topping trong thực đơn theo tên (không phân biệt hoa thường / khoảng trắng thừa) */
export function buildToppingLookup<T extends ToppingLookup & { name?: string; isTopping?: boolean }>(
  products: T[]
): (name: string) => T | undefined {
  const norm = (s: string) => s.normalize("NFC").trim().toLowerCase().replace(/\s+/g, " ");
  const byName = new Map<string, T>();
  // Ưu tiên món đánh dấu topping khi trùng tên với món thường
  for (const p of products) {
    if (!p?.name) continue;
    const k = norm(p.name);
    const cur = byName.get(k);
    if (!cur || (!cur.isTopping && p.isTopping)) byName.set(k, p);
  }
  return (name: string) => byName.get(norm(name));
}
