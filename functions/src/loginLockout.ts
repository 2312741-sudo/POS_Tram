/**
 * Logic khóa tạm đăng nhập (chống brute-force) thuần túy, độc lập Firebase runtime.
 *
 * Cơ chế "giữ chỗ trước" (reserve-then-verify):
 *  - Trước khi kiểm tra mật khẩu, mỗi yêu cầu phải "giữ chỗ" 1 lượt thử bằng transaction
 *    (tăng failedCount). Nhờ vậy dù gửi song song nhiều yêu cầu, tối đa chỉ có
 *    MAX_FAILED_ATTEMPTS lượt kiểm tra mật khẩu trong một cửa sổ khóa.
 *  - Đăng nhập thành công -> xóa bộ đếm.
 *  - Sai mật khẩu ở lượt thứ MAX_FAILED_ATTEMPTS -> khóa LOCKOUT_DURATION_MS.
 */

export const MAX_FAILED_ATTEMPTS = 5;

/**
 * Đường dẫn bộ đếm đăng nhập sai: nằm ở GỐC `login_attempts/{storeCode}/{username}`,
 * NGOÀI cây `stores/{storeCode}`. Lý do: trong RTDB quyền `.read` đã cấp ở nút cha sẽ lan xuống
 * mọi nút con (không thể chặn bằng `.read: false` ở con). Nút gốc này không có rule nào
 * nên client luôn bị từ chối; chỉ Admin SDK (Cloud Functions) đọc/ghi được.
 * Dữ liệu cũ tại `stores/{s}/login_attempts` không còn dùng và có thể xóa.
 */
export function loginAttemptPath(storeCode: string, username: string): string {
  return `login_attempts/${storeCode}/${username}`;
}
export const LOCKOUT_DURATION_MS = 15 * 60 * 1000; // 15 phút
/** Các lần sai cách nhau quá cửa sổ này sẽ được đếm lại từ đầu */
export const ATTEMPT_WINDOW_MS = 15 * 60 * 1000;

export interface LoginAttemptRecord {
  failedCount?: number;
  lockedUntil?: number | null;
  lastAttemptAt?: number;
}

export function isLocked(rec: LoginAttemptRecord | null | undefined, now: number): boolean {
  return !!rec && typeof rec.lockedUntil === "number" && rec.lockedUntil > now;
}

export function remainingLockSeconds(rec: LoginAttemptRecord | null | undefined, now: number): number {
  if (!isLocked(rec, now)) return 0;
  return Math.ceil(((rec as LoginAttemptRecord).lockedUntil as number - now) / 1000);
}

/** Số lần sai hiện hành (đã bỏ qua các lần sai quá cũ hoặc khóa đã hết hạn) */
export function effectiveFailedCount(rec: LoginAttemptRecord | null | undefined, now: number): number {
  if (!rec) return 0;
  if (typeof rec.lockedUntil === "number" && rec.lockedUntil > 0 && rec.lockedUntil <= now) {
    return 0; // Khóa cũ đã hết hạn -> bắt đầu lượt mới
  }
  if (typeof rec.lastAttemptAt === "number" && now - rec.lastAttemptAt > ATTEMPT_WINDOW_MS) {
    return 0;
  }
  return typeof rec.failedCount === "number" && rec.failedCount > 0 ? rec.failedCount : 0;
}

export interface ReserveResult {
  allowed: boolean;
  next: LoginAttemptRecord;
}

/**
 * Giữ chỗ 1 lượt thử. Trả về allowed=false nếu đang bị khóa hoặc đã dùng hết lượt.
 */
export function reserveAttempt(rec: LoginAttemptRecord | null | undefined, now: number): ReserveResult {
  if (isLocked(rec, now)) {
    return { allowed: false, next: { ...(rec as LoginAttemptRecord) } };
  }
  const count = effectiveFailedCount(rec, now);
  if (count >= MAX_FAILED_ATTEMPTS) {
    // Đã hết lượt (vd. các yêu cầu song song) -> khóa luôn
    return {
      allowed: false,
      next: { failedCount: count, lockedUntil: now + LOCKOUT_DURATION_MS, lastAttemptAt: now },
    };
  }
  return {
    allowed: true,
    next: { failedCount: count + 1, lockedUntil: null, lastAttemptAt: now },
  };
}

/**
 * Ghi nhận lượt vừa giữ chỗ là sai mật khẩu. Nếu đủ ngưỡng -> khóa tạm.
 * Trả về bản ghi mới và cờ justLocked.
 */
export function applyFailure(
  rec: LoginAttemptRecord | null | undefined,
  now: number
): { next: LoginAttemptRecord; justLocked: boolean } {
  if (isLocked(rec, now)) {
    return { next: { ...(rec as LoginAttemptRecord) }, justLocked: false };
  }
  const count = Math.max(effectiveFailedCount(rec, now), 1);
  if (count >= MAX_FAILED_ATTEMPTS) {
    return {
      next: { failedCount: count, lockedUntil: now + LOCKOUT_DURATION_MS, lastAttemptAt: now },
      justLocked: true,
    };
  }
  return { next: { failedCount: count, lockedUntil: null, lastAttemptAt: now }, justLocked: false };
}

/** Thông báo khóa tạm (tiếng Việt) dùng chung cho mọi client */
export function buildLockoutMessage(remainingSeconds: number): string {
  const minutes = Math.max(1, Math.ceil(remainingSeconds / 60));
  return `Tài khoản đã bị khóa tạm thời do nhập sai mật khẩu ${MAX_FAILED_ATTEMPTS} lần liên tiếp. Vui lòng thử lại sau ${minutes} phút hoặc liên hệ Quản lý.`;
}

/** Mã lỗi REST Identity Toolkit được coi là "sai thông tin đăng nhập" */
export function isInvalidCredentialError(code: string): boolean {
  const c = code.split(":")[0].trim();
  return (
    c === "INVALID_PASSWORD" ||
    c === "EMAIL_NOT_FOUND" ||
    c === "INVALID_LOGIN_CREDENTIALS" ||
    c === "INVALID_EMAIL"
  );
}
