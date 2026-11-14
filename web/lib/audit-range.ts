/**
 * Khoảng ngày cho Nhật ký thao tác. Màn nhật ký mặc định chỉ có 150 thao tác MỚI NHẤT mỗi chi nhánh (tải sẵn cho nhẹ);
 * chọn khoảng ngày thì tải ĐỦ mọi thao tác trong khoảng (truy vấn audit_logs theo timestamp — đã có chỉ mục).
 * Ngày tính theo giờ Việt Nam (UTC+7), không phụ thuộc múi giờ máy.
 */
export type AuditRangePreset = "RECENT" | "TODAY" | "YESTERDAY" | "7DAYS" | "THIS_MONTH" | "LAST_MONTH" | "CUSTOM";

export const AUDIT_RANGE_LABELS: Record<AuditRangePreset, string> = {
  RECENT: "150 thao tác gần nhất / chi nhánh",
  TODAY: "Hôm nay",
  YESTERDAY: "Hôm qua",
  "7DAYS": "7 ngày qua",
  THIS_MONTH: "Tháng này",
  LAST_MONTH: "Tháng trước",
  CUSTOM: "Tùy chọn ngày…",
};

const VN = 7 * 3600_000;
const DAY = 86_400_000;

/** 0h (giờ VN) của ngày chứa [ms] */
function vnDayStart(ms: number): number {
  return Math.floor((ms + VN) / DAY) * DAY - VN;
}

/** "YYYY-MM-DD" (giờ VN) → 0h ngày đó */
function vnDateStart(ymd: string): number | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(ymd);
  if (!m) return null;
  return Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])) - VN;
}

/** Khoảng [from, to] (ms, gồm cả hai đầu); null = chế độ 150 thao tác gần nhất / khoảng không hợp lệ */
export function auditRange(preset: AuditRangePreset, nowMs: number, customFrom = "", customTo = ""): { from: number; to: number } | null {
  const today = vnDayStart(nowMs);
  const vnNow = new Date(nowMs + VN);
  const monthStart = (y: number, mo: number) => Date.UTC(y, mo, 1) - VN;
  switch (preset) {
    case "TODAY":
      return { from: today, to: today + DAY - 1 };
    case "YESTERDAY":
      return { from: today - DAY, to: today - 1 };
    case "7DAYS":
      return { from: today - 6 * DAY, to: today + DAY - 1 };
    case "THIS_MONTH":
      return { from: monthStart(vnNow.getUTCFullYear(), vnNow.getUTCMonth()), to: today + DAY - 1 };
    case "LAST_MONTH": {
      const y = vnNow.getUTCFullYear();
      const mo = vnNow.getUTCMonth();
      return { from: monthStart(mo === 0 ? y - 1 : y, mo === 0 ? 11 : mo - 1), to: monthStart(y, mo) - 1 };
    }
    case "CUSTOM": {
      const f = vnDateStart(customFrom);
      const t = vnDateStart(customTo || customFrom);
      if (f == null || t == null || t < f) return null;
      return { from: f, to: t + DAY - 1 };
    }
    default:
      return null;
  }
}
