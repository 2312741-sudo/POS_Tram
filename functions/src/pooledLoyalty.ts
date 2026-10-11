/**
 * @deprecated Thay bằng bản ghi điểm dùng chung duy nhất loyalty_members (xem sharedLoyalty.ts). Chỉ còn normalizePhone/planPull
 * cho test cũ; pullPooledPoints đã thành stub không ghi dữ liệu.
 *
 * (Mô tả cũ) Logic thuần cho điểm DÙNG CHUNG toàn hệ thống (Chủ quán đã xác nhận storeInfo.sharedLoyalty.enabled).
 *
 * POS chỉ đổi điểm trên node khách của CHÍNH chi nhánh (rules). Khi điểm tại chi nhánh không đủ,
 * callable `pullPooledPoints` CHUYỂN phần thiếu từ các chi nhánh khác (cùng số điện thoại) về node khách
 * của chi nhánh đang bán; sau đó luồng đổi điểm cũ (LoyaltyService.redeemForBill) chạy như bình thường.
 * totalPoints (xếp hạng) không đổi ở cả hai phía.
 */

export interface Holding {
  storeCode: string;
  customerId: string;
  points: number;
}

export interface PullAllocation extends Holding {
  take: number;
  after: number;
}

/** SĐT Việt Nam về dạng 0xxxxxxxxx; không hợp lệ → null (khớp web/lib/loyalty.ts normalizePhone) */
export function normalizePhone(raw: unknown): string | null {
  let p = String(raw ?? "").replace(/[\s.\-()]/g, "");
  if (p.startsWith("+84")) p = "0" + p.slice(3);
  else if (p.startsWith("84") && p.length === 11) p = "0" + p.slice(2);
  return /^0\d{9}$/.test(p) ? p : null;
}

/**
 * Chia số điểm cần kéo từ các chi nhánh KHÁC. `others` đã loại chi nhánh bán.
 * Trả lỗi nếu tổng không đủ.
 */
export function planPull(others: Holding[], needed: number): { error: string } | { allocations: PullAllocation[] } {
  if (!Number.isInteger(needed) || needed <= 0) return { error: "Số điểm cần kéo phải là số nguyên > 0" };
  const held = others.filter((h) => h.points > 0);
  const total = held.reduce((s, h) => s + h.points, 0);
  if (total < needed) return { error: `Các chi nhánh khác chỉ còn ${total} điểm, không đủ ${needed}` };
  // Chi nhánh bán ("nhà") đã được dùng trước ở phía POS; phần thiếu lấy từ chi nhánh nhiều điểm nhất.
  const sorted = [...held].sort((a, b) => b.points - a.points || a.storeCode.localeCompare(b.storeCode));
  let left = needed;
  const allocations: PullAllocation[] = [];
  for (const h of sorted) {
    if (left <= 0) break;
    const take = Math.min(h.points, left);
    allocations.push({ ...h, take, after: h.points - take });
    left -= take;
  }
  return { allocations };
}

/** Khóa idempotent theo hóa đơn: gọi lại cho cùng hóa đơn không kéo điểm lần nữa */
export function pullKey(billId: string): string {
  return `pull_${billId.replace(/[.#$[\]/]/g, "_")}`;
}
