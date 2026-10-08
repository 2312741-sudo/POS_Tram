import { describe, it, expect } from "vitest";
import {
  MAX_FAILED_ATTEMPTS,
  LOCKOUT_DURATION_MS,
  ATTEMPT_WINDOW_MS,
  LoginAttemptRecord,
  isLocked,
  remainingLockSeconds,
  reserveAttempt,
  applyFailure,
  buildLockoutMessage,
  isInvalidCredentialError,
} from "./loginLockout";

/** Mô phỏng 1 lần đăng nhập sai: giữ chỗ rồi ghi nhận thất bại */
function failOnce(rec: LoginAttemptRecord | null, now: number) {
  const r = reserveAttempt(rec, now);
  if (!r.allowed) return { rec: r.next, allowed: false, justLocked: false };
  const f = applyFailure(r.next, now);
  return { rec: f.next, allowed: true, justLocked: f.justLocked };
}

describe("Khóa tạm đăng nhập (staffSignIn)", () => {
  const now = 1_700_000_000_000;

  it("Khóa sau đúng MAX_FAILED_ATTEMPTS lần sai liên tiếp", () => {
    let rec: LoginAttemptRecord | null = null;
    for (let i = 1; i < MAX_FAILED_ATTEMPTS; i++) {
      const r = failOnce(rec, now + i);
      expect(r.allowed).toBe(true);
      expect(r.justLocked).toBe(false);
      rec = r.rec;
    }
    const last = failOnce(rec, now + 100);
    expect(last.allowed).toBe(true);
    expect(last.justLocked).toBe(true);
    expect(isLocked(last.rec, now + 101)).toBe(true);
    expect(remainingLockSeconds(last.rec, now + 100)).toBe(LOCKOUT_DURATION_MS / 1000);
  });

  it("Đang bị khóa thì không được giữ chỗ (không kiểm tra mật khẩu)", () => {
    const rec: LoginAttemptRecord = { failedCount: 5, lockedUntil: now + 60_000, lastAttemptAt: now };
    const r = reserveAttempt(rec, now);
    expect(r.allowed).toBe(false);
    // Không gia hạn khóa khi bị tấn công tiếp
    expect(r.next.lockedUntil).toBe(now + 60_000);
  });

  it("Yêu cầu song song không vượt quá số lượt cho phép", () => {
    let rec: LoginAttemptRecord | null = null;
    let allowedCount = 0;
    for (let i = 0; i < 20; i++) {
      const r = reserveAttempt(rec, now);
      if (r.allowed) allowedCount++;
      rec = r.next;
    }
    expect(allowedCount).toBe(MAX_FAILED_ATTEMPTS);
    expect(isLocked(rec, now + 1)).toBe(true);
  });

  it("Khóa hết hạn hoặc lần sai quá cũ thì đếm lại từ đầu", () => {
    const expired: LoginAttemptRecord = { failedCount: 5, lockedUntil: now - 1, lastAttemptAt: now - LOCKOUT_DURATION_MS };
    const r1 = reserveAttempt(expired, now);
    expect(r1.allowed).toBe(true);
    expect(r1.next.failedCount).toBe(1);

    const stale: LoginAttemptRecord = { failedCount: 4, lockedUntil: null, lastAttemptAt: now - ATTEMPT_WINDOW_MS - 1 };
    const r2 = reserveAttempt(stale, now);
    expect(r2.next.failedCount).toBe(1);
  });

  it("Thông báo khóa tiếng Việt và nhận diện mã lỗi REST", () => {
    expect(buildLockoutMessage(61)).toContain("2 phút");
    expect(buildLockoutMessage(0)).toContain("1 phút");
    expect(isInvalidCredentialError("INVALID_LOGIN_CREDENTIALS")).toBe(true);
    expect(isInvalidCredentialError("INVALID_PASSWORD : bad")).toBe(true);
    expect(isInvalidCredentialError("TOO_MANY_ATTEMPTS_TRY_LATER : x")).toBe(false);
  });
});
