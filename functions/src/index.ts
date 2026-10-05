import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {
  canCallerManageUsers,
  canCallerCreateRole,
  canCallerResetPassword,
  canCallerSetDisabled,
  normalizeUsername,
  buildSyntheticEmail,
  UserProfile,
} from "./permissions";

if (!admin.apps.length) {
  admin.initializeApp({
    databaseURL: process.env.DATABASE_URL || "https://tramapp-36f53-default-rtdb.asia-southeast1.firebasedatabase.app",
  });
}

const db = admin.database();
const auth = admin.auth();

const FUNCTION_REGION = "asia-southeast1";

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
    const callerSnap = await db.ref(`stores/${cleanStoreCode}/users/${callerUid}`).get();
    if (!callerSnap.exists()) {
      throw new HttpsError("permission-denied", "Bạn không thuộc chi nhánh này.");
    }

    const caller = callerSnap.val() as UserProfile;
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
        roleId: String(roleId),
        isRootOwner: false,
        isActive: true,
        phone: phone ? String(phone).trim() : "",
        customPermissions: Array.isArray(customPermissions) ? customPermissions : [],
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
    const callerSnap = await db.ref(`stores/${cleanStoreCode}/users/${callerUid}`).get();
    if (!callerSnap.exists()) {
      throw new HttpsError("permission-denied", "Bạn không thuộc chi nhánh này.");
    }

    // Lấy hồ sơ người bị tác động
    const targetSnap = await db.ref(`stores/${cleanStoreCode}/users/${targetUid}`).get();
    if (!targetSnap.exists()) {
      throw new HttpsError("not-found", "Không tìm thấy hồ sơ nhân viên trong quán.");
    }

    const caller = callerSnap.val() as UserProfile;
    const target = targetSnap.val() as UserProfile;
    const isSelf = callerUid === targetUid;

    if (!canCallerResetPassword(caller, target, isSelf)) {
      throw new HttpsError("permission-denied", "Bạn không có quyền đặt lại mật khẩu cho tài khoản này.");
    }

    // Cập nhật Auth
    await auth.updateUser(targetUid, {
      password: String(newPassword),
    });

    // Bật mustChangePassword trong RTDB
    await db.ref(`stores/${cleanStoreCode}/users/${targetUid}/mustChangePassword`).set(true);

    // Ghi audit log
    const logId = `LOG_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
    await db.ref(`stores/${cleanStoreCode}/audit_logs/${logId}`).set({
      timestamp: Date.now(),
      action: "RESET_STAFF_PASSWORD",
      staffUsername: caller.username || "unknown",
      staffFullName: caller.fullName || "Quản lý",
      details: `Đặt lại mật khẩu cho tài khoản @${target.username || targetUid} (Bắt buộc đổi mật khẩu lần tới)`,
    });

    return {
      success: true,
      message: "Đặt lại mật khẩu thành công.",
    };
  }
);

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
    const callerSnap = await db.ref(`stores/${cleanStoreCode}/users/${callerUid}`).get();
    if (!callerSnap.exists()) {
      throw new HttpsError("permission-denied", "Bạn không thuộc chi nhánh này.");
    }

    // Lấy hồ sơ người bị tác động
    const targetSnap = await db.ref(`stores/${cleanStoreCode}/users/${targetUid}`).get();
    if (!targetSnap.exists()) {
      throw new HttpsError("not-found", "Không tìm thấy hồ sơ nhân viên trong quán.");
    }

    const caller = callerSnap.val() as UserProfile;
    const target = targetSnap.val() as UserProfile;

    if (!canCallerSetDisabled(caller, target, targetUid, callerUid)) {
      throw new HttpsError("permission-denied", "Không thể thực hiện khóa/mở khóa tài khoản này.");
    }

    // 1. Cập nhật Auth
    await auth.updateUser(targetUid, { disabled });
    if (disabled) {
      // Hủy bỏ refresh token ngay lập tức
      await auth.revokeRefreshTokens(targetUid).catch(() => {});
    }

    // 2. Cập nhật isActive trong RTDB
    await db.ref(`stores/${cleanStoreCode}/users/${targetUid}/isActive`).set(!disabled);

    // 3. Ghi audit log
    const logId = `LOG_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
    await db.ref(`stores/${cleanStoreCode}/audit_logs/${logId}`).set({
      timestamp: Date.now(),
      action: disabled ? "LOCK_STAFF_ACCOUNT" : "UNLOCK_STAFF_ACCOUNT",
      staffUsername: caller.username || "unknown",
      staffFullName: caller.fullName || "Quản lý",
      details: `${disabled ? "Khóa" : "Mở khóa"} tài khoản @${target.username || targetUid}`,
    });

    return {
      success: true,
      message: `${disabled ? "Khóa" : "Mở khóa"} tài khoản thành công.`,
    };
  }
);
