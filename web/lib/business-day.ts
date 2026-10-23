/**
 * NGÀY KINH DOANH: cửa hàng hoạt động qua 0h có thể đặt "giờ bắt đầu ngày kinh doanh" (vd. 04:00).
 * Hóa đơn chốt trước giờ này tính vào ngày kinh doanh TRƯỚC (vd. 01:30 sáng 23/10 → ngày 22/10).
 *
 * Cách làm: lùi mốc thời gian của hóa đơn đi [cutoff] phút rồi dùng lại logic "ngày theo giờ Việt Nam" sẵn có.
 * Cấu hình: stores/{store}/storeInfo/businessDayStartMinute (số phút từ 0h, 0..720; 0 = như cũ, ngày bắt đầu 00:00).
 * Bản Dart song song: ReportDateUtils.businessDayStartMinutes (app_flutter/lib/core/reports/report_date_utils.dart).
 */

export const MAX_BUSINESS_DAY_START_MINUTE = 12 * 60;

/** Chuẩn hóa giá trị cấu hình về số nguyên phút trong [0, 720] (sai/thiếu → 0) */
export function normalizeBusinessDayStart(v: unknown): number {
  const n = Number(v);
  if (!Number.isFinite(n)) return 0;
  return Math.min(MAX_BUSINESS_DAY_START_MINUTE, Math.max(0, Math.trunc(n)));
}

/** "HH:mm" → số phút (rỗng/sai định dạng → null) */
export function parseTimeToMinutes(text: string): number | null {
  const m = /^(\d{1,2}):(\d{2})$/.exec(String(text).trim());
  if (!m) return null;
  const h = Number(m[1]);
  const mi = Number(m[2]);
  if (h > 23 || mi > 59) return null;
  return h * 60 + mi;
}

export function formatMinutesAsTime(min: number): string {
  const v = normalizeBusinessDayStart(min);
  return `${String(Math.floor(v / 60)).padStart(2, "0")}:${String(v % 60).padStart(2, "0")}`;
}

/** Mốc thời gian dùng để xếp NGÀY KINH DOANH (lùi [startMinute] phút) */
export function businessTimestamp(ts: number, startMinute: number): number {
  return ts - normalizeBusinessDayStart(startMinute) * 60_000;
}

/** Ngày kinh doanh "YYYY-MM-DD" của một thời điểm */
export function businessDateOf(ts: number, startMinute: number): string {
  return new Date(businessTimestamp(ts, startMinute) + 7 * 3600_000).toISOString().slice(0, 10);
}

/** Khoảng [bắt đầu, kết thúc) theo ms của ngày kinh doanh "YYYY-MM-DD" */
export function businessDayRange(ymd: string, startMinute: number): { start: number; end: number } {
  const [y, m, d] = ymd.split("-").map(Number);
  const start = Date.UTC(y, m - 1, d, 0, 0, 0) - 7 * 3600_000 + normalizeBusinessDayStart(startMinute) * 60_000;
  return { start, end: start + 86_400_000 };
}

// ---- Bảng cấu hình theo cửa hàng (nạp từ data-context khi tải danh sách chi nhánh) ----
let byStore: Record<string, number> = {};
let fallback = 0;

export function setBusinessDayConfig(map: Record<string, number>, defaultStartMinute = 0) {
  byStore = { ...map };
  fallback = normalizeBusinessDayStart(defaultStartMinute);
}

/** Giờ bắt đầu ngày (phút) của một cửa hàng; không rõ cửa hàng → giá trị mặc định (cửa hàng đầu tiên) */
export function businessDayStartFor(storeCode?: string | null): number {
  if (storeCode && storeCode !== "ALL" && storeCode in byStore) return byStore[storeCode];
  return fallback;
}
