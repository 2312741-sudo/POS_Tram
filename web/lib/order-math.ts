/**
 * Tính tiền dòng món đồng nhất với Flutter (OrderItemModel):
 *   unitPrice = price + sizeExtraPrice + toppingPrice
 *   itemTotal = unitPrice * quantity - discountAmount   (discountAmount là giảm giá CẢ DÒNG)
 * Dữ liệu cũ có thể lưu topping dạng object { price } thay vì toppingPrice — vẫn được hỗ trợ.
 */

export interface RawOrderLine {
  price?: number | string;
  quantity?: number | string;
  count?: number | string;
  sizeExtraPrice?: number | string;
  toppingPrice?: number | string;
  selectedToppings?: unknown[];
  discountAmount?: number | string;
  [key: string]: unknown;
}

function num(v: unknown): number {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

/** Số lượng của dòng món (mặc định 1) */
export function lineQuantity(it: RawOrderLine): number {
  const q = num(it.quantity ?? it.count ?? 1);
  return q > 0 ? q : 1;
}

/** Đơn giá một phần gồm size + topping */
export function lineUnitPrice(it: RawOrderLine): number {
  let topping = num(it.toppingPrice);
  if (topping <= 0 && Array.isArray(it.selectedToppings)) {
    topping = it.selectedToppings.reduce<number>((ts, tp) => {
      if (tp && typeof tp === "object" && "price" in tp) {
        return ts + num((tp as { price?: unknown }).price);
      }
      return ts;
    }, 0);
  }
  return num(it.price) + num(it.sizeExtraPrice) + topping;
}

/** Tổng tiền gốc (chưa giảm) của dòng */
export function lineGross(it: RawOrderLine): number {
  return lineUnitPrice(it) * lineQuantity(it);
}

/** Tổng hợp danh sách món: tạm tính và tổng giảm giá theo dòng */
export function summarizeOrderLines(items: RawOrderLine[]): { subTotal: number; itemDiscounts: number } {
  let subTotal = 0;
  let itemDiscounts = 0;
  for (const it of items) {
    const gross = lineGross(it);
    subTotal += gross;
    itemDiscounts += Math.min(Math.max(0, num(it.discountAmount)), gross);
  }
  return { subTotal, itemDiscounts };
}

/** Parse currentOrderJson của bàn an toàn — trả về mảng rỗng nếu lỗi */
export function parseOrderJson(json?: string | null): RawOrderLine[] {
  if (!json) return [];
  try {
    const parsed = JSON.parse(json);
    return Array.isArray(parsed) ? (parsed as RawOrderLine[]) : [];
  } catch {
    return [];
  }
}

/** Tên topping để hiển thị — Flutter lưu chuỗi, dữ liệu cũ có thể lưu object { name } */
export function toppingLabel(tp: unknown): string {
  if (typeof tp === "string") return tp;
  if (tp && typeof tp === "object" && "name" in tp) return String((tp as { name?: unknown }).name ?? "");
  return "";
}
