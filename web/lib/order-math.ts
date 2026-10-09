/**
 * Tính tiền dòng món đồng nhất với Flutter (OrderItemModel):
 *   unitPrice = price + sizeExtraPrice + toppingPrice
 *   itemTotal = unitPrice * quantity - lineDiscountTotal
 *
 * Giảm giá theo món áp dụng cho SỐ PHẦN được chọn trong dòng:
 *   discountedQuantity (0..quantity), và mỗi phần được giảm:
 *     PERCENT: discountPercent % trên unitPrice
 *     AMOUNT : discountUnitAmount đ / phần
 *   lineDiscountTotal = min(unitPrice*quantity,
 *       PERCENT ? round(unitPrice * percent * dq / 100) : min(unitAmount, unitPrice) * dq)
 * Tổng giảm được LƯU tường minh trên dòng (lineDiscountTotal, và discountAmount cùng giá trị
 * cho client cũ) — báo cáo đọc giá trị lưu, không tính lại.
 *
 * Dữ liệu cũ (không có lineDiscountTotal/discountedQuantity): discountAmount là giảm giá CẢ DÒNG
 * (Flutter cũ và web cũ đều thu tiền như vậy) — KHÔNG nhân với quantity.
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
  lineDiscountTotal?: number | string;
  discountedQuantity?: number | string;
  discountPercent?: number | string;
  discountUnitAmount?: number | string;
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

/** Tính tổng giảm của dòng theo số phần được giảm (hàm thuần — khớp Flutter computeLineDiscount) */
export function computeLineDiscount(args: {
  unitPrice: number;
  quantity: number;
  discountedQuantity: number;
  percent?: number;
  unitAmount?: number;
}): number {
  const { unitPrice, quantity } = args;
  if (quantity <= 0 || unitPrice <= 0) return 0;
  const gross = unitPrice * quantity;
  const dq = Math.min(Math.max(0, Math.trunc(args.discountedQuantity)), quantity);
  const percent = Math.min(Math.max(0, Math.trunc(args.percent ?? 0)), 100);
  const unitAmount = Math.max(0, Math.trunc(args.unitAmount ?? 0));
  let d = 0;
  if (percent > 0) {
    d = Math.round((unitPrice * percent * dq) / 100);
  } else if (unitAmount > 0) {
    d = Math.min(unitAmount, unitPrice) * dq;
  }
  return Math.min(Math.max(0, d), gross);
}

/**
 * Tổng giảm ĐÃ LƯU của dòng, chặn trong [0, tiền gốc dòng].
 * Ưu tiên lineDiscountTotal; dữ liệu cũ: discountAmount = giảm CẢ DÒNG.
 */
export function lineDiscountTotal(it: RawOrderLine): number {
  const stored = it.lineDiscountTotal != null ? num(it.lineDiscountTotal) : num(it.discountAmount);
  return Math.min(Math.max(0, stored), lineGross(it));
}

/** Số phần được giảm của dòng; dữ liệu cũ có giảm giá → coi như giảm tất cả các phần */
export function lineDiscountedQuantity(it: RawOrderLine): number {
  const qty = lineQuantity(it);
  if (it.discountedQuantity != null) return Math.min(Math.max(0, Math.trunc(num(it.discountedQuantity))), qty);
  return lineDiscountTotal(it) > 0 ? qty : 0;
}

/** Mô tả giảm giá dòng, VD "Giảm 10% × 2/5 món" — chuỗi rỗng nếu không giảm */
export function lineDiscountLabel(it: RawOrderLine, fmt: (n: number) => string): string {
  const total = lineDiscountTotal(it);
  if (total <= 0) return "";
  const qty = lineQuantity(it);
  const dq = lineDiscountedQuantity(it);
  const part = dq < qty ? ` × ${dq}/${qty} món` : qty > 1 ? ` × ${qty} món` : "";
  const pct = num(it.discountPercent);
  const unitAmt = num(it.discountUnitAmount);
  if (pct > 0) return `Giảm ${pct}%${part}`;
  if (unitAmt > 0) return `Giảm ${fmt(unitAmt)}${part}`;
  return `Giảm ${fmt(total)}`;
}

/**
 * Đặt giảm giá cho dòng (percent hoặc unitAmount mỗi phần, cho discountedQuantity phần).
 * Trả về bản sao dòng đã ghi đủ các trường lưu trữ (discountAmount = lineDiscountTotal).
 */
export function applyLineDiscount<T extends RawOrderLine>(
  it: T,
  opts: { percent?: number; unitAmount?: number; discountedQuantity: number }
): T {
  const qty = lineQuantity(it);
  const percent = Math.min(Math.max(0, Math.trunc(opts.percent ?? 0)), 100);
  const unitAmount = percent > 0 ? 0 : Math.max(0, Math.trunc(opts.unitAmount ?? 0));
  const dq = Math.min(Math.max(0, Math.trunc(opts.discountedQuantity)), qty);
  const total = computeLineDiscount({ unitPrice: lineUnitPrice(it), quantity: qty, discountedQuantity: dq, percent, unitAmount });
  const next: T = { ...it };
  delete next.discountPercent;
  delete next.discountUnitAmount;
  if (total > 0 && percent > 0) next.discountPercent = percent;
  if (total > 0 && unitAmount > 0) next.discountUnitAmount = unitAmount;
  next.discountedQuantity = total > 0 ? dq : 0;
  next.lineDiscountTotal = total;
  next.discountAmount = total;
  return next;
}

/**
 * Đổi số lượng dòng: chặn discountedQuantity trong [0, số lượng mới] và tính lại tổng giảm.
 * Dòng cũ giảm số tiền cố định cả dòng (không có % / đơn giá giảm) giữ nguyên số tiền (chặn theo tiền dòng).
 */
export function setLineQuantity<T extends RawOrderLine>(it: T, quantity: number): T {
  const q = Math.max(1, Math.trunc(quantity));
  const dq = Math.min(lineDiscountedQuantity(it), q);
  const stored = it.lineDiscountTotal != null ? num(it.lineDiscountTotal) : num(it.discountAmount);
  const base: T = { ...it, quantity: q };
  const pct = num(it.discountPercent);
  const unitAmt = num(it.discountUnitAmount);
  if (pct > 0 || unitAmt > 0) {
    return applyLineDiscount(base, { percent: pct, unitAmount: unitAmt, discountedQuantity: dq });
  }
  if (stored > 0) {
    const total = Math.min(stored, lineGross(base));
    return { ...base, discountedQuantity: dq, lineDiscountTotal: total, discountAmount: total };
  }
  return base;
}

/** Tổng hợp danh sách món: tạm tính và tổng giảm giá theo dòng */
export function summarizeOrderLines(items: RawOrderLine[]): { subTotal: number; itemDiscounts: number } {
  let subTotal = 0;
  let itemDiscounts = 0;
  for (const it of items) {
    subTotal += lineGross(it);
    itemDiscounts += lineDiscountTotal(it);
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
