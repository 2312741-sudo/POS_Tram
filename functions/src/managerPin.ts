/**
 * Callable "Quản lý duyệt bằng PIN" (verifyManagerPin) và đặt PIN duyệt (setManagerPin).
 *
 * Lưu trữ (chỉ Admin SDK — nằm ngoài stores/{storeCode} nên quyền đọc cấp ở cấp cửa hàng
 * KHÔNG lan xuống; rules gốc mặc định từ chối):
 *   manager_pins/{storeCode}/{uid}          = { algo, salt, hash, updatedAt }
 *   manager_pin_attempts/{storeCode}/{uid}  = bộ đếm sai PIN theo NGƯỜI GỌI (khóa tạm 15 phút sau 5 lần)
 * Cờ hiển thị (không nhạy cảm): stores/{storeCode}/users/{uid}/hasApprovalPin = true
 */
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { UserProfile } from "./permissions";
import { LoginAttemptRecord, applyFailure, reserveAttempt, remainingLockSeconds } from "./loginLockout";
import {
  ACTION_LABELS,
  APPROVAL_TTL_MS,
  PinCandidate,
  StoredPin,
  hashPin,
  isApprovableAction,
  isApproverEligible,
  matchApprover,
  sanitizeContext,
  validatePinFormat,
} from "./managerPinLogic";

const FUNCTION_REGION = "asia-southeast1";

// Lấy db lười (index.ts gọi initializeApp sau khi import module này)
const db = () => admin.database();

function cleanStore(raw: unknown): string {
  const s = typeof raw === "string" ? raw.trim().toUpperCase() : "";
  if (!/^[A-Z0-9_-]{2,30}$/.test(s)) throw new HttpsError("invalid-argument", "Mã cửa hàng không hợp lệ.");
  return s;
}

async function loadMember(storeCode: string, uid: string): Promise<UserProfile> {
  const [profileSnap, indexSnap] = await Promise.all([
    db().ref(`stores/${storeCode}/users/${uid}`).get(),
    db().ref(`userIndex/${uid}/${storeCode}`).get(),
  ]);
  if (!profileSnap.exists() || indexSnap.val() !== true) {
    throw new HttpsError("permission-denied", "Bạn không thuộc chi nhánh này.");
  }
  const profile = profileSnap.val() as UserProfile;
  if (profile.isActive === false) throw new HttpsError("permission-denied", "Tài khoản đã bị khóa.");
  return profile;
}

function lockMessage(seconds: number): string {
  const minutes = Math.max(1, Math.ceil(seconds / 60));
  return `Nhập sai PIN quá nhiều lần. Chức năng duyệt bằng PIN bị khóa tạm ${minutes} phút.`;
}

const newLogId = () => `LOG_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`;

/**
 * verifyManagerPin({ storeCode, pin, action, approverUid?, context? })
 * → { approvalId, approverUid, approverName, approverUsername, action, approvedAt, expiresAt }
 */
export const verifyManagerPin = onCall({ region: FUNCTION_REGION }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Yêu cầu đăng nhập trước khi thực hiện.");
  const data = (request.data || {}) as Record<string, unknown>;
  const storeCode = cleanStore(data.storeCode);
  const pin = typeof data.pin === "string" ? data.pin.trim() : "";
  const action = data.action;
  const approverUid = typeof data.approverUid === "string" && data.approverUid ? data.approverUid : null;
  const context = sanitizeContext(data.context);
  if (!isApprovableAction(action)) throw new HttpsError("invalid-argument", "Hành động không hỗ trợ duyệt bằng PIN.");
  if (!/^\d{4,8}$/.test(pin)) throw new HttpsError("invalid-argument", "PIN phải gồm 4–8 chữ số.");

  const callerUid = request.auth.uid;
  const caller = await loadMember(storeCode, callerUid);

  // 1. Giữ chỗ 1 lượt thử (transaction — an toàn khi gửi song song)
  const attemptRef = db().ref(`manager_pin_attempts/${storeCode}/${callerUid}`);
  let allowed = false;
  const reserveTx = await attemptRef.transaction((cur: LoginAttemptRecord | null) => {
    const r = reserveAttempt(cur, Date.now());
    allowed = r.allowed;
    return r.next;
  });
  if (!allowed) {
    const rec = (reserveTx.snapshot.val() || null) as LoginAttemptRecord | null;
    const remaining = Math.max(remainingLockSeconds(rec, Date.now()), 1);
    throw new HttpsError("resource-exhausted", lockMessage(remaining), { reason: "LOCKED_OUT", remainingSeconds: remaining });
  }

  // 2. So PIN với hồ sơ quản lý / chủ quán
  const [usersSnap, pinsSnap] = await Promise.all([
    db().ref(`stores/${storeCode}/users`).get(),
    db().ref(`manager_pins/${storeCode}`).get(),
  ]);
  const users = (usersSnap.val() || {}) as Record<string, UserProfile>;
  const pins = (pinsSnap.val() || {}) as Record<string, StoredPin>;
  const candidates: PinCandidate[] = Object.entries(users)
    .filter(([uid]) => pins[uid])
    .map(([uid, profile]) => ({ uid, profile, stored: pins[uid] }));
  const result = matchApprover(candidates, pin, action, approverUid);

  const now = Date.now();
  if (!result.ok) {
    if (result.reason === "AMBIGUOUS") {
      throw new HttpsError("failed-precondition", "Vui lòng chọn người duyệt rồi nhập lại PIN.", { reason: "AMBIGUOUS" });
    }
    let justLocked = false;
    let rec: LoginAttemptRecord | null = null;
    await attemptRef.transaction((cur: LoginAttemptRecord | null) => {
      const r = applyFailure(cur, Date.now());
      justLocked = r.justLocked;
      rec = r.next;
      return r.next;
    });
    if (justLocked) {
      await db()
        .ref(`stores/${storeCode}/audit_logs/${newLogId()}`)
        .set({
          timestamp: now,
          action: "MANAGER_PIN_LOCKED_OUT",
          username: caller.username || callerUid,
          userFullName: caller.fullName || caller.username || "Nhân viên",
          userRole: caller.roleId || "UNKNOWN",
          targetType: "APPROVAL",
          targetId: action,
          isSuspicious: true,
          details: `Nhập sai PIN quản lý nhiều lần (${ACTION_LABELS[action]}) — khóa duyệt PIN 15 phút${context ? `. ${context}` : ""}`,
        })
        .catch(() => undefined);
      const remaining = Math.max(remainingLockSeconds(rec, now), 1);
      throw new HttpsError("resource-exhausted", lockMessage(remaining), { reason: "LOCKED_OUT", remainingSeconds: remaining });
    }
    throw new HttpsError("permission-denied", "PIN không đúng hoặc người duyệt không có quyền cho thao tác này.");
  }

  // 3. Thành công: xóa bộ đếm, ghi nhật ký duyệt (phía máy chủ, không giả mạo được người duyệt)
  await attemptRef.remove().catch(() => undefined);
  const approver = result.profile;
  const approverName = String(approver.fullName || approver.username || "Quản lý");
  const approvalId = newLogId();
  const expiresAt = now + APPROVAL_TTL_MS;
  await db()
    .ref(`stores/${storeCode}/audit_logs/${approvalId}`)
    .set({
      timestamp: now,
      action: "MANAGER_PIN_APPROVED",
      username: caller.username || callerUid,
      userFullName: caller.fullName || caller.username || "Nhân viên",
      userRole: caller.roleId || "UNKNOWN",
      targetType: "APPROVAL",
      targetId: action,
      approvedBy: result.uid,
      approvedByName: approverName,
      approvedByUsername: approver.username || null,
      approvalAction: action,
      expiresAt,
      details: `${approverName} duyệt bằng PIN: ${ACTION_LABELS[action]} cho ${caller.fullName || caller.username || "nhân viên"}${context ? ` — ${context}` : ""}`,
    });

  return {
    approvalId,
    approverUid: result.uid,
    approverName,
    approverUsername: approver.username || null,
    action,
    approvedAt: now,
    expiresAt,
  };
});

/**
 * setManagerPin({ storeCode, pin })  — quản lý/chủ quán đặt (hoặc xóa khi pin = null) PIN duyệt của CHÍNH MÌNH.
 */
export const setManagerPin = onCall({ region: FUNCTION_REGION }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Yêu cầu đăng nhập trước khi thực hiện.");
  const data = (request.data || {}) as Record<string, unknown>;
  const storeCode = cleanStore(data.storeCode);
  const uid = request.auth.uid;
  const caller = await loadMember(storeCode, uid);
  if (!isApproverEligible(caller)) {
    throw new HttpsError("permission-denied", "Chỉ Chủ quán hoặc Quản lý mới được đặt PIN duyệt.");
  }

  const now = Date.now();
  const clearing = data.pin === null;
  if (!clearing) {
    const err = validatePinFormat(typeof data.pin === "string" ? data.pin.trim() : data.pin);
    if (err) throw new HttpsError("invalid-argument", err);
  }

  const updates: Record<string, unknown> = {};
  updates[`manager_pins/${storeCode}/${uid}`] = clearing
    ? null
    : { ...hashPin(String(data.pin).trim()), updatedAt: now };
  updates[`stores/${storeCode}/users/${uid}/hasApprovalPin`] = clearing ? null : true;
  updates[`stores/${storeCode}/audit_logs/${newLogId()}`] = {
    timestamp: now,
    action: clearing ? "CLEAR_MANAGER_PIN" : "SET_MANAGER_PIN",
    username: caller.username || uid,
    userFullName: caller.fullName || caller.username || "Quản lý",
    userRole: caller.roleId || "UNKNOWN",
    targetType: "USER",
    targetId: uid,
    details: clearing ? "Xóa PIN duyệt quản lý" : "Đặt/đổi PIN duyệt quản lý",
  };
  await db().ref().update(updates);
  return { success: true, hasPin: !clearing };
});
