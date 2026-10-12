/**
 * Báo hết món — LOGIC THUẦN (không Firebase/UI), có test.
 * Bản Dart song song: app_flutter/lib/core/domain/product_availability.dart (giữ hai bản cùng quy tắc).
 *
 * Trường trên products/{key}: isAvailable (boolean), soldOutAt (epoch ms), soldOutBy (username),
 * soldOutUntil (epoch ms — tự bật lại khi now >= soldOutUntil, không cần job server).
 */

/** Các trường trạng thái báo hết — không sao chép sang chi nhánh khác. */
export const SOLD_OUT_FIELDS = ["soldOutAt", "soldOutBy", "soldOutUntil"] as const;

/** Giờ "đầu ngày" bán hàng: "Hết đến hết ngày" tự bật lại lúc 05:00. */
export const SOLD_OUT_RESET_HOUR = 5;

export interface AvailabilityFields {
  isAvailable?: boolean | null;
  soldOutAt?: number | null;
  soldOutBy?: string | null;
  soldOutUntil?: number | null;
}

/** Món bán được tại thời điểm `now` (epoch ms) hay không. */
export function isProductAvailable(p: AvailabilityFields | null | undefined, now: number = Date.now()): boolean {
  if (!p) return true;
  if (p.isAvailable !== false) return true; // thiếu trường / true => bán được (bỏ qua soldOutUntil cũ)
  const until = p.soldOutUntil;
  if (typeof until !== "number" || !Number.isFinite(until)) return false; // dữ liệu cũ: isAvailable=false vô thời hạn
  return now >= until;
}

/** Cờ hết hàng đã quá hạn nhưng vẫn nằm trong DB (nơi ghi sẽ dọn dần). */
export function isSoldOutStale(p: AvailabilityFields, now: number = Date.now()): boolean {
  return p.isAvailable === false && isProductAvailable(p, now);
}

/** 05:00 sáng tiếp theo theo giờ máy: sau 05:00 => 05:00 ngày mai; 00:00–04:59 => 05:00 hôm nay. */
export function nextSoldOutReset(now: number = Date.now()): number {
  const d = new Date(now);
  const today = new Date(d.getFullYear(), d.getMonth(), d.getDate(), SOLD_OUT_RESET_HOUR);
  if (now < today.getTime()) return today.getTime();
  return new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1, SOLD_OUT_RESET_HOUR).getTime();
}

/** Dữ liệu ghi vào products/{key} bằng update() (null = xóa trường). */
export function soldOutPatch(opts: { soldOut: boolean; by: string; now?: number; untilNextReset?: boolean }): Record<string, boolean | number | string | null> {
  const now = opts.now ?? Date.now();
  if (!opts.soldOut) return { isAvailable: true, soldOutAt: null, soldOutBy: null, soldOutUntil: null };
  return {
    isAvailable: false,
    soldOutAt: now,
    soldOutBy: opts.by.slice(0, 64),
    soldOutUntil: opts.untilNextReset ? nextSoldOutReset(now) : null,
  };
}

/** "Hết từ 14:05 · bep · tự bật lại sáng mai" */
export function soldOutNote(p: AvailabilityFields): string {
  if (p.isAvailable !== false) return "";
  const parts: string[] = [];
  if (typeof p.soldOutAt === "number") {
    const d = new Date(p.soldOutAt);
    parts.push(`Hết từ ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`);
  }
  if (p.soldOutBy) parts.push(p.soldOutBy);
  if (typeof p.soldOutUntil === "number") parts.push("tự bật lại sáng mai");
  return parts.join(" · ");
}
