import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onValueWritten } from "firebase-functions/v2/database";
import { defineString } from "firebase-functions/params";
import * as admin from "firebase-admin";
import {
  canCallerManageUsers,
  canCallerCreateRole,
  canCallerResetPassword,
  canCallerSetDisabled,
  normalizeUsername,
  buildSyntheticEmail,
  canCallerImportCustomer,
  normalizeRoleId,
  resolveStaffAuthUid,
  isChamCongAccount,
  UserProfile,
  sanitizeCustomPermissions,
} from "./permissions";
import {
  AnyMap,
  isValidCustomerKey,
  isValidStoreCode,
  buildRtdbCustomerFromFirestore,
  decideImport,
  buildFirestoreMirror,
  shouldMirror,
  readCurrentPoints,
} from "./customerSync";
import {
  LoginAttemptRecord,
  reserveAttempt,
  applyFailure,
  remainingLockSeconds,
  buildLockoutMessage,
  loginAttemptPath,
  isInvalidCredentialError,
} from "./loginLockout";

if (!admin.apps.length) {
  admin.initializeApp({
    databaseURL: process.env.DATABASE_URL || "https://tramapp-36f53-default-rtdb.asia-southeast1.firebasedatabase.app",
  });
}

const db = admin.database();
const auth = admin.auth();

const FUNCTION_REGION = "asia-southeast1";

/**
 * Web API Key của project (không phải bí mật, nhưng KHÔNG hardcode trong mã nguồn).
 * Khai báo trong functions/.env (WEB_API_KEY=...) hoặc nhập khi `firebase deploy` hỏi.
 */
const WEB_API_KEY = defineString("WEB_API_KEY", {
  description: "Firebase Web API Key dùng để xác minh mật khẩu qua Identity Toolkit REST (signInWithPassword)",
});

/**
 * 1. Hàm tạo tài khoản nhân viên (createStaffAccount)
 */
export const createStaffAccount = onCall(
  { region: FUNCTION_REGION },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Yêu cầu đăng nhập trước khi thực hiện.");
    }

    const {
      storeCode,
      username,
      fullName,
      roleId,
      tempPassword,
      phone,
      customPermissions,
    } = request.data || {};

    if (!storeCode || !username || !fullName || !roleId || !tempPassword) {
      throw new HttpsError("invalid-argument", "Thiếu thông tin bắt buộc để tạo tài khoản.");
    }

    if (String(tempPassword).length < 6) {
      throw new HttpsError("invalid-argument", "Mật khẩu tạm phải có độ dài tối thiểu 6 ký tự.");
    }

    const callerUid = request.auth.uid;
    const cleanStoreCode = String(storeCode).trim().toUpperCase();
    const cleanUser = normalizeUsername(String(username));

    if (!cleanUser) {
      throw new HttpsError("invalid-argument", "Tên đăng nhập không hợp lệ sau khi chuẩn hóa.");
    }

    // Lấy hồ sơ người gọi
    const callerNode = await findCallerNode(cleanStoreCode, callerUid);
    if (!callerNode) {
      throw new HttpsError("permission-denied", "Bạn không thuộc chi nhánh này.");
    }

    const caller = callerNode.record;
    if (!canCallerManageUsers(caller)) {
      throw new HttpsError("permission-denied", "Bạn không có quyền quản lý nhân viên.");
    }

    if (!canCallerCreateRole(caller, roleId)) {
      throw new HttpsError("permission-denied", "Quản lý không được phép tạo tài khoản có vai trò Chủ quán.");
    }

    // Kiểm tra trùng username trong quán
    const storeUsersSnap = await db.ref(`stores/${cleanStoreCode}/users`).get();
    if (storeUsersSnap.exists()) {
      const usersMap = storeUsersSnap.val();
      for (const u of Object.values(usersMap) as UserProfile[]) {
        if (u.username && normalizeUsername(u.username) === cleanUser) {
          throw new HttpsError("already-exists", `Tên đăng nhập "${cleanUser}" đã tồn tại trong quán.`);
        }
      }
    }

    const syntheticEmail = buildSyntheticEmail(cleanUser, cleanStoreCode);
    let newUid = "";

    try {
      // 1. Tạo Firebase Auth user
      const userRecord = await auth.createUser({
        email: syntheticEmail,
        password: String(tempPassword),
        displayName: String(fullName),
        disabled: false,
      });
      newUid = userRecord.uid;

      // 2. Ghi hồ sơ RTDB tại stores/{storeCode}/users/{uid}
      const userProfile: Record<string, unknown> = {
        uid: newUid,
        username: cleanUser,
        fullName: String(fullName).trim(),
        roleId: normalizeRoleId(String(roleId)),
        isRootOwner: false,
        isActive: true,
        phone: phone ? String(phone).trim() : "",
        customPermissions: sanitizeCustomPermissions(caller, customPermissions),
        createdAt: Date.now(),
        mustChangePassword: true,
      };

      await db.ref(`stores/${cleanStoreCode}/users/${newUid}`).set(userProfile);

      // 3. Ghi index userIndex/{uid}/{storeCode} = true
      await db.ref(`userIndex/${newUid}/${cleanStoreCode}`).set(true);

      // 4. Ghi audit log
      const logId = `LOG_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
      await db.ref(`stores/${cleanStoreCode}/audit_logs/${logId}`).set({
        timestamp: Date.now(),
        action: "CREATE_STAFF_ACCOUNT",
        staffUsername: caller.username || "unknown",
        staffFullName: caller.fullName || "Quản lý",
        details: `Tạo tài khoản nhân viên @${cleanUser} (${fullName}) với vai trò ${roleId}`,
      });

      return {
        success: true,
        uid: newUid,
        email: syntheticEmail,
        message: "Tạo tài khoản nhân viên thành công.",
      };
    } catch (err: any) {
      // Rollback: Xóa auth user nếu ghi RTDB lỗi
      if (newUid) {
        await auth.deleteUser(newUid).catch(() => {});
      }
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", err?.message || "Lỗi tạo tài khoản nhân viên.");
    }
  }
);

/**
 * 2. Hàm đặt lại mật khẩu nhân viên (resetStaffPassword)
 */
export const resetStaffPassword = onCall(
  { region: FUNCTION_REGION },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Yêu cầu đăng nhập trước khi thực hiện.");
    }

    const { storeCode, targetUid, newPassword } = request.data || {};
    if (!storeCode || !targetUid || !newPassword) {
      throw new HttpsError("invalid-argument", "Thiếu thông tin bắt buộc để đặt lại mật khẩu.");
    }

    if (String(newPassword).length < 6) {
      throw new HttpsError("invalid-argument", "Mật khẩu mới phải có tối thiểu 6 ký tự.");
    }

    const callerUid = request.auth.uid;
    const cleanStoreCode = String(storeCode).trim().toUpperCase();

    // Lấy hồ sơ người gọi
    const callerNode = await findCallerNode(cleanStoreCode, callerUid);
    if (!callerNode) {
      throw new HttpsError("permission-denied", "Bạn không thuộc chi nhánh này.");
    }

    // Lấy hồ sơ người bị tác động (chấp nhận khóa nút, trường uid hoặc tên đăng nhập)
    const found = await findStaffNode(cleanStoreCode, String(targetUid));
    if (!found) {
      throw new HttpsError("not-found", "Không tìm thấy hồ sơ nhân viên trong quán.");
    }
    const { nodeKey, record: target } = found;
    const caller = callerNode.record;
    const authUidGuess = resolveStaffAuthUid(nodeKey, target);
    const isSelf = callerUid === authUidGuess || callerUid === nodeKey;

    if (!canCallerResetPassword(caller, target, isSelf)) {
      throw new HttpsError(
        "permission-denied",
        "Bạn không có quyền đặt lại mật khẩu cho tài khoản này (Quản lý không đặt lại được mật khẩu của Chủ quán hoặc Quản lý khác)."
      );
    }

    if (isChamCongAccount(nodeKey, target)) {
      throw new HttpsError(
        "failed-precondition",
        "Tài khoản này đăng nhập bằng Chấm Công Trạm nên không có mật khẩu POS để đặt lại."
      );
    }

    // Cập nhật Auth (khóa nút cũ theo tên đăng nhập → thử tra uid thật qua email tổng hợp)
    let authUid = authUidGuess;
    try {
      await auth.updateUser(authUid, { password: String(newPassword) });
    } catch (err: any) {
      const code = String(err?.code || "");
      if (code === "auth/user-not-found" || code === "auth/invalid-uid") {
        const email = target.username ? buildSyntheticEmail(String(target.username), cleanStoreCode) : "";
        let resolved: string | null = null;
        if (email) {
          resolved = await auth.getUserByEmail(email).then((u) => u.uid).catch(() => null);
        }
        if (!resolved) {
          throw new HttpsError(
            "not-found",
            "Tài khoản này chưa có đăng nhập Firebase (hồ sơ cũ). Hãy xóa và tạo lại tài khoản nhân viên."
          );
        }
        authUid = resolved;
        await auth.updateUser(authUid, { password: String(newPassword) }).catch((e2: any) => {
          throw new HttpsError("internal", e2?.message || "Không cập nhật được mật khẩu.");
        });
      } else if (code === "auth/invalid-password" || code === "auth/weak-password") {
        throw new HttpsError("invalid-argument", "Mật khẩu mới không hợp lệ (tối thiểu 6 ký tự).");
      } else {
        throw new HttpsError("internal", err?.message || "Không cập nhật được mật khẩu.");
      }
    }

    // Bật mustChangePassword trong RTDB (trên đúng nút hồ sơ)
    await db.ref(`stores/${cleanStoreCode}/users/${nodeKey}/mustChangePassword`).set(true);

    // Ghi audit log
    const logId = `LOG_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
    await db.ref(`stores/${cleanStoreCode}/audit_logs/${logId}`).set({
      timestamp: Date.now(),
      action: "RESET_STAFF_PASSWORD",
      staffUsername: caller.username || "unknown",
      staffFullName: caller.fullName || "Quản lý",
      details: `Đặt lại mật khẩu cho tài khoản @${target.username || nodeKey} (Bắt buộc đổi mật khẩu lần tới)`,
    });

    return {
      success: true,
      message: "Đặt lại mật khẩu thành công.",
    };
  }
);

/**
 * Hồ sơ NGƯỜI GỌI: khóa nút = uid, hoặc (nút cũ khóa theo tên đăng nhập) nút có trường `uid` đúng bằng uid đăng nhập.
 * Không khớp theo username để tránh mạo danh.
 */
async function findCallerNode(storeCode: string, callerUid: string): Promise<{ nodeKey: string; record: UserProfile } | null> {
  const direct = await db.ref(`stores/${storeCode}/users/${callerUid}`).get();
  if (direct.exists()) return { nodeKey: callerUid, record: direct.val() as UserProfile };
  const all = await db.ref(`stores/${storeCode}/users`).get();
  if (!all.exists()) return null;
  for (const [nodeKey, rec] of Object.entries(all.val() as Record<string, UserProfile>)) {
    if (rec && typeof rec === "object" && rec.uid === callerUid) return { nodeKey, record: rec };
  }
  return null;
}

/** Tìm nút hồ sơ nhân viên: theo khóa nút, rồi theo trường uid / username. */
async function findStaffNode(storeCode: string, key: string): Promise<{ nodeKey: string; record: UserProfile } | null> {
  const direct = await db.ref(`stores/${storeCode}/users/${key}`).get();
  if (direct.exists()) return { nodeKey: key, record: direct.val() as UserProfile };
  const all = await db.ref(`stores/${storeCode}/users`).get();
  if (!all.exists()) return null;
  const lower = key.toLowerCase();
  for (const [nodeKey, rec] of Object.entries(all.val() as Record<string, UserProfile>)) {
    if (!rec || typeof rec !== "object") continue;
    if (rec.uid === key || String(rec.username || "").toLowerCase() === lower) {
      return { nodeKey, record: rec };
    }
  }
  return null;
}

/**
 * 3. Hàm khóa / mở khóa tài khoản nhân viên (setStaffDisabled)
 */
export const setStaffDisabled = onCall(
  { region: FUNCTION_REGION },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Yêu cầu đăng nhập trước khi thực hiện.");
    }

    const { storeCode, targetUid, disabled } = request.data || {};
    if (!storeCode || !targetUid || typeof disabled !== "boolean") {
      throw new HttpsError("invalid-argument", "Thiếu thông tin bắt buộc để khóa/mở tài khoản.");
    }

    const callerUid = request.auth.uid;
    const cleanStoreCode = String(storeCode).trim().toUpperCase();

    // Lấy hồ sơ người gọi
    const callerNode = await findCallerNode(cleanStoreCode, callerUid);
    if (!callerNode) {
      throw new HttpsError("permission-denied", "Bạn không thuộc chi nhánh này.");
    }

    // Lấy hồ sơ người bị tác động
    const found = await findStaffNode(cleanStoreCode, String(targetUid));
    if (!found) {
      throw new HttpsError("not-found", "Không tìm thấy hồ sơ nhân viên trong quán.");
    }
    const { nodeKey, record: target } = found;
    const authUid = resolveStaffAuthUid(nodeKey, target);

    const caller = callerNode.record;

    if (!canCallerSetDisabled(caller, target, authUid, callerUid)) {
      throw new HttpsError("permission-denied", "Không thể thực hiện khóa/mở khóa tài khoản này.");
    }

    // 1. Cập nhật Auth
    await auth.updateUser(authUid, { disabled }).catch((e: any) => {
      if (String(e?.code) === "auth/user-not-found") return; // hồ sơ cũ không có Auth: vẫn cập nhật isActive
      throw e;
    });
    if (disabled) {
      // Hủy bỏ refresh token ngay lập tức
      await auth.revokeRefreshTokens(authUid).catch(() => {});
    }

    // 2. Cập nhật isActive trong RTDB
    await db.ref(`stores/${cleanStoreCode}/users/${nodeKey}/isActive`).set(!disabled);

    // 3. Ghi audit log
    const logId = `LOG_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
    await db.ref(`stores/${cleanStoreCode}/audit_logs/${logId}`).set({
      timestamp: Date.now(),
      action: disabled ? "LOCK_STAFF_ACCOUNT" : "UNLOCK_STAFF_ACCOUNT",
      staffUsername: caller.username || "unknown",
      staffFullName: caller.fullName || "Quản lý",
      details: `${disabled ? "Khóa" : "Mở khóa"} tài khoản @${target.username || nodeKey}`,
    });

    return {
      success: true,
      message: `${disabled ? "Khóa" : "Mở khóa"} tài khoản thành công.`,
    };
  }
);


/**
 * Xác minh mật khẩu qua Identity Toolkit REST (signInWithPassword).
 * Trả về uid nếu đúng, ném lỗi kèm mã lỗi REST nếu sai.
 */
async function verifyPasswordViaRest(email: string, password: string): Promise<{ ok: true; uid: string } | { ok: false; code: string }> {
  const emulatorHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  const base = emulatorHost
    ? `http://${emulatorHost}/identitytoolkit.googleapis.com`
    : "https://identitytoolkit.googleapis.com";
  const apiKey = WEB_API_KEY.value() || (emulatorHost ? "fake-api-key" : "");
  if (!apiKey) {
    throw new HttpsError("failed-precondition", "Máy chủ chưa cấu hình WEB_API_KEY cho chức năng đăng nhập.");
  }

  const resp = await fetch(`${base}/v1/accounts:signInWithPassword?key=${encodeURIComponent(apiKey)}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password, returnSecureToken: false }),
  });
  const body = (await resp.json().catch(() => ({}))) as { localId?: string; error?: { message?: string } };
  if (resp.ok && body.localId) {
    return { ok: true, uid: body.localId };
  }
  return { ok: false, code: body.error?.message || `HTTP_${resp.status}` };
}

/**
 * 4. Đăng nhập nhân viên có khóa tạm chống brute-force (staffSignIn)
 *
 * - Kiểm tra & ghi bộ đếm sai tại login_attempts/{storeCode}/{username} ở GỐC (ngoài stores/{s} để không bị
 *   quyền đọc của thành viên quán lan xuống; rules chặn hoàn toàn, chỉ Admin SDK truy cập được).
 * - Xác minh mật khẩu phía máy chủ qua Identity Toolkit REST.
 * - Thành công: trả về Custom Token để client gọi signInWithCustomToken.
 * - Sai {MAX_FAILED_ATTEMPTS} lần liên tiếp: khóa tạm 15 phút (mã lỗi resource-exhausted).
 * - Không tạo bản ghi đếm cho username không tồn tại (tránh rác dữ liệu / dò tài khoản hàng loạt).
 */
export const staffSignIn = onCall(
  { region: FUNCTION_REGION },
  async (request) => {
    const { storeCode, username, password } = (request.data || {}) as {
      storeCode?: unknown;
      username?: unknown;
      password?: unknown;
    };

    if (typeof storeCode !== "string" || typeof username !== "string" || typeof password !== "string") {
      throw new HttpsError("invalid-argument", "Thiếu mã cửa hàng, tên đăng nhập hoặc mật khẩu.");
    }

    const cleanStoreCode = storeCode.trim().toUpperCase();
    const cleanUser = normalizeUsername(username);
    if (!/^[A-Z0-9_-]{2,30}$/.test(cleanStoreCode)) {
      throw new HttpsError("invalid-argument", "Mã cửa hàng không hợp lệ.");
    }
    if (!/^[a-z0-9_-]{3,30}$/.test(cleanUser)) {
      throw new HttpsError("invalid-argument", "Tên đăng nhập không hợp lệ.");
    }
    if (!password || password.length > 256) {
      throw new HttpsError("invalid-argument", "Mật khẩu không hợp lệ.");
    }

    const INVALID_MSG = "Sai tài khoản hoặc mật khẩu.";
    let email = buildSyntheticEmail(cleanUser, cleanStoreCode);

    // 1. Tài khoản không tồn tại -> trả lỗi chung, KHÔNG ghi bộ đếm
    try {
      await auth.getUserByEmail(email);
    } catch (e: unknown) {
      if ((e as { code?: string })?.code !== "auth/user-not-found") {
        throw new HttpsError("internal", "Không thể kiểm tra tài khoản. Vui lòng thử lại sau.");
      }
      // Chủ nhiều chi nhánh dùng MỘT tài khoản Auth (email theo chi nhánh đầu tiên) nhưng có hồ sơ ở nhiều quán:
      // tìm hồ sơ theo tên đăng nhập trong quán đang đăng nhập rồi dùng email thật của tài khoản đó.
      let resolved: string | null = null;
      try {
        // Không dùng orderByChild (RTDB chưa khai báo .indexOn cho username) — quán chỉ có vài chục tài khoản
        const all = (await db.ref(`stores/${cleanStoreCode}/users`).get()).val() as Record<string, UserProfile> | null;
        const found =
          Object.entries(all || {}).find(([, u]) => u && u.username && normalizeUsername(u.username) === cleanUser)?.[0] ??
          null;
        if (found) resolved = (await auth.getUser(found)).email ?? null;
      } catch {
        resolved = null;
      }
      if (!resolved) throw new HttpsError("unauthenticated", INVALID_MSG);
      email = resolved;
    }

    // 2. Giữ chỗ 1 lượt thử bằng transaction (an toàn khi gửi song song)
    const attemptRef = db.ref(loginAttemptPath(cleanStoreCode, cleanUser));
    let allowed = false;
    const reserveTx = await attemptRef.transaction((current: LoginAttemptRecord | null) => {
      const r = reserveAttempt(current, Date.now());
      allowed = r.allowed;
      return r.next;
    });
    const afterReserve = (reserveTx.snapshot.val() || null) as LoginAttemptRecord | null;
    if (!allowed) {
      const remaining = Math.max(remainingLockSeconds(afterReserve, Date.now()), 1);
      throw new HttpsError("resource-exhausted", buildLockoutMessage(remaining), {
        reason: "LOCKED_OUT",
        remainingSeconds: remaining,
        lockedUntil: afterReserve?.lockedUntil ?? null,
      });
    }

    // 3. Xác minh mật khẩu
    const result = await verifyPasswordViaRest(email, password).catch((e: unknown) => {
      if (e instanceof HttpsError) throw e;
      throw new HttpsError("unavailable", "Không thể kết nối máy chủ xác thực. Vui lòng thử lại.");
    });

    if (!result.ok) {
      if (result.code.startsWith("USER_DISABLED")) {
        throw new HttpsError("permission-denied", "Tài khoản đã bị tạm khóa bởi chủ quán.");
      }
      if (!isInvalidCredentialError(result.code)) {
        // Lỗi hạ tầng (quota, cấu hình...) -> trả lại lượt đã giữ chỗ
        await attemptRef
          .transaction((current: LoginAttemptRecord | null) => {
            if (!current || typeof current.failedCount !== "number") return current;
            return { ...current, failedCount: Math.max(current.failedCount - 1, 0) };
          })
          .catch(() => undefined);
        if (result.code.startsWith("TOO_MANY_ATTEMPTS")) {
          throw new HttpsError("resource-exhausted", "Hệ thống đang tạm hạn chế đăng nhập do quá nhiều yêu cầu. Vui lòng thử lại sau ít phút.");
        }
        throw new HttpsError("internal", "Đăng nhập thất bại do lỗi máy chủ xác thực.");
      }

      let justLocked = false;
      let lockedRec: LoginAttemptRecord | null = null;
      await attemptRef.transaction((current: LoginAttemptRecord | null) => {
        const r = applyFailure(current, Date.now());
        justLocked = r.justLocked;
        lockedRec = r.next;
        return r.next;
      });

      if (justLocked) {
        const now = Date.now();
        const logId = `LOG_${now}_${Math.random().toString(36).substring(2, 7)}`;
        await db
          .ref(`stores/${cleanStoreCode}/audit_logs/${logId}`)
          .set({
            timestamp: now,
            action: "LOGIN_ATTEMPT_LOCKED_OUT",
            username: cleanUser,
            userFullName: cleanUser,
            userRole: "UNKNOWN",
            targetType: "AUTH",
            targetId: cleanUser,
            isSuspicious: true,
            details: `Tài khoản @${cleanUser} bị khóa tạm 15 phút do nhập sai mật khẩu nhiều lần liên tiếp`,
          })
          .catch(() => undefined);
        const remaining = Math.max(remainingLockSeconds(lockedRec, now), 1);
        throw new HttpsError("resource-exhausted", buildLockoutMessage(remaining), {
          reason: "LOCKED_OUT",
          remainingSeconds: remaining,
        });
      }
      throw new HttpsError("unauthenticated", INVALID_MSG);
    }

    // 4. Mật khẩu đúng -> xóa bộ đếm
    const uid = result.uid;
    await attemptRef.remove().catch(() => undefined);

    // 5. Kiểm tra hồ sơ & quyền thuộc quán (userIndex chỉ Admin SDK ghi được)
    const [profileSnap, indexSnap] = await Promise.all([
      db.ref(`stores/${cleanStoreCode}/users/${uid}`).get(),
      db.ref(`userIndex/${uid}/${cleanStoreCode}`).get(),
    ]);
    if (!profileSnap.exists() || indexSnap.val() !== true) {
      throw new HttpsError(
        "permission-denied",
        `Không tìm thấy thông tin tài khoản nhân viên tại chi nhánh ${cleanStoreCode}. Vui lòng liên hệ Quản lý.`
      );
    }
    const profile = profileSnap.val() as UserProfile;
    if (profile.isActive === false) {
      throw new HttpsError("permission-denied", "Tài khoản đã bị tạm khóa bởi chủ quán.");
    }

    // 6. Cấp Custom Token
    let token: string;
    try {
      token = await auth.createCustomToken(uid);
    } catch {
      // Thường do service account của Functions thiếu quyền iam.serviceAccounts.signBlob
      throw new HttpsError("internal", "Máy chủ chưa đủ quyền cấp phiên đăng nhập (Service Account Token Creator).");
    }
    await db.ref(`stores/${cleanStoreCode}/users/${uid}/lastLoginAt`).set(Date.now()).catch(() => undefined);

    return {
      success: true,
      token,
      uid,
      mustChangePassword: profile.mustChangePassword === true,
    };
  }
);

/**
 * 5. Nhập khách hàng từ Firestore kmt_customers vào RTDB của quán (importCustomerToStore)
 *
 * - Thu ngân trở lên, đang hoạt động, thuộc quán (userIndex) mới được gọi.
 * - Đọc Firestore bằng Admin SDK, ghi RTDB với SỐ DƯ THẬT (client không tự sao chép được nữa:
 *   rules chỉ cho Thu ngân tạo khách với 0 điểm).
 * - Idempotent: node RTDB đã có → giữ nguyên, trả về created=false (RTDB là nguồn chuẩn).
 * - Ghi audit log IMPORT_CUSTOMER khi thực sự tạo mới.
 */
export const importCustomerToStore = onCall(
  { region: FUNCTION_REGION },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Yêu cầu đăng nhập trước khi thực hiện.");
    }
    const { storeCode, customerId } = (request.data || {}) as { storeCode?: unknown; customerId?: unknown };
    if (!isValidStoreCode(storeCode) || !isValidCustomerKey(customerId)) {
      throw new HttpsError("invalid-argument", "Mã cửa hàng hoặc mã khách hàng không hợp lệ.");
    }
    const cleanStoreCode = storeCode.trim().toUpperCase();
    const callerUid = request.auth.uid;

    const [callerSnap, indexSnap] = await Promise.all([
      db.ref(`stores/${cleanStoreCode}/users/${callerUid}`).get(),
      db.ref(`userIndex/${callerUid}/${cleanStoreCode}`).get(),
    ]);
    const caller = (callerSnap.exists() ? callerSnap.val() : null) as UserProfile | null;
    if (!canCallerImportCustomer(caller, indexSnap.val() === true)) {
      throw new HttpsError("permission-denied", "Bạn không có quyền nhập khách hàng cho chi nhánh này.");
    }

    const customerRef = db.ref(`stores/${cleanStoreCode}/customers/${customerId}`);
    const existing = await customerRef.get();
    if (existing.exists()) {
      return { success: true, created: false, currentPoints: readCurrentPoints(existing.val() as AnyMap) };
    }

    const doc = await admin.firestore().collection("kmt_customers").doc(customerId).get();
    if (!doc.exists) {
      throw new HttpsError("not-found", `Không tìm thấy khách hàng ${customerId} trên hệ thống Khuyến Mãi Trạm.`);
    }
    const seed = buildRtdbCustomerFromFirestore((doc.data() || {}) as AnyMap, customerId, Date.now());

    let created = false;
    const tx = await customerRef.transaction((current: unknown) => {
      const d = decideImport(current, seed);
      created = d.action === "create";
      return d.action === "create" ? d.value : undefined; // undefined = hủy, giữ nguyên dữ liệu hiện có
    });
    const finalVal = (tx.snapshot.val() || null) as AnyMap | null;

    if (created && tx.committed) {
      const now = Date.now();
      const logId = `LOG_${now}_${Math.random().toString(36).substring(2, 7)}`;
      await db
        .ref(`stores/${cleanStoreCode}/audit_logs/${logId}`)
        .set({
          timestamp: now,
          action: "IMPORT_CUSTOMER",
          username: caller?.username || "unknown",
          userFullName: caller?.fullName || "",
          userRole: caller?.roleId || "",
          targetType: "CUSTOMER",
          targetId: customerId,
          details: `Nhập khách ${seed.ho_ten || customerId} (${customerId}) từ kmt_customers với ${seed.currentPoints} điểm`,
        })
        .catch(() => undefined);
    }

    return { success: true, created: created && tx.committed, currentPoints: readCurrentPoints(finalVal) };
  }
);

/**
 * 6. Đồng bộ một chiều RTDB → Firestore kmt_customers (mirrorCustomerToFirestore)
 *
 * Điểm chuẩn nằm ở RTDB loyalty_members/{memberKey}; stores/{s}/customers/{id} là cache do trigger mirrorMemberToBranches
 * cập nhật; Firestore chỉ là bản sao để
 * hệ sinh thái Khuyến Mãi Trạm / web đọc. Client KHÔNG ghi điểm vào Firestore nữa.
 * - Doc id Firestore = customerId (khóa RTDB).
 * - Ghi lịch sử kmt_point_history với doc id cố định (chạy lại không trùng).
 * - Xóa khách trên RTDB không xóa Firestore (giữ lịch sử cho hệ thống khác).
 */
export const mirrorCustomerToFirestore = onValueWritten(
  { ref: "/stores/{storeCode}/customers/{customerId}", region: FUNCTION_REGION },
  async (event) => {
    const { storeCode, customerId } = event.params;
    const before = (event.data.before.exists() ? event.data.before.val() : null) as AnyMap | null;
    const after = (event.data.after.exists() ? event.data.after.val() : null) as AnyMap | null;
    if (!after || !shouldMirror(before, after)) return;
    if (!isValidCustomerKey(customerId)) return;

    const fs = admin.firestore();
    const now = Date.now();
    await fs.collection("kmt_customers").doc(customerId).set(buildFirestoreMirror(after, storeCode, now), { merge: true });

    // Lịch sử điểm (kmt_point_history) KHÔNG ghi ở đây nữa: điểm đổi ở bản ghi dùng chung nên mỗi dòng
    // sổ cái loyalty_ledger/{memberKey}/{opId} sinh đúng 1 bản ghi lịch sử (mirrorLedgerToHistory).
  }
);

// Quản lý duyệt bằng PIN (xem managerPin.ts)
export { verifyManagerPin, setManagerPin } from "./managerPin";

// Đăng nhập bằng Chấm Công Trạm (xem chamCong.ts, docs/CHAMCONG_SSO.md)
export { chamCongSignIn, linkChamCongStore, unlinkChamCongStore, getChamCongLinkStatus } from "./chamCong";

// Tự xóa tài khoản (Apple 5.1.1(v)) — xem deleteMyAccount.ts, docs/APP_REVIEW.md
export { deleteMyAccount } from "./deleteMyAccount";

// Tạo chi nhánh mới (chủ quán) — xem createStore.ts, createStoreLogic.ts
export { createStore } from "./createStore";

// Điểm DÙNG CHUNG toàn chuỗi: bản ghi loyalty_members + callable/trigger (xem sharedLoyaltyHandlers.ts)
export {
  applyLoyaltyEarn,
  redeemLoyaltyPoints,
  refundLoyaltyPoints,
  adjustLoyaltyPoints,
  lookupMember,
  getMemberLedger,
  listLoyaltyLedger,
  setLoyaltyConfig,
  mirrorMemberToBranches,
  linkBranchCustomer,
  mirrorLedgerToHistory,
} from "./sharedLoyaltyHandlers";

/**
 * @deprecated Đã bị thay bằng bản ghi điểm dùng chung duy nhất (loyalty_members). KHÔNG còn chuyển điểm giữa
 * các chi nhánh nữa: hàm giữ lại để app cũ chưa cập nhật không bị lỗi 404, luôn trả pulled = 0 / othersPoints = 0
 * và KHÔNG ghi dữ liệu. Có thể xóa sau khi mọi POS đã cập nhật.
 */
export const pullPooledPoints = onCall({ region: FUNCTION_REGION }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Yêu cầu đăng nhập trước khi thực hiện.");
  }
  return { success: true, pulled: 0, othersPoints: 0, alreadyApplied: true, deprecated: true };
});

// Xóa khách hàng (Chủ quán/Quản lý) — xem deleteCustomer.ts, deleteCustomerLogic.ts
export { deleteCustomer } from "./deleteCustomer";
