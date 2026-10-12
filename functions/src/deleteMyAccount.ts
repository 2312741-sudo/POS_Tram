/**
 * Cloud Function "Xóa tài khoản của tôi" (deleteMyAccount) — Apple Guideline 5.1.1(v).
 * Request: { confirm: "XOA" }. Yêu cầu đăng nhập. Logic thuần ở deleteMyAccountLogic.ts.
 *
 * Thứ tự an toàn:
 *   1. Kiểm tra chủ quán gốc ở mọi chi nhánh (chưa ghi gì) → ROOT_OWNER nếu có.
 *   2. Thu hồi refresh token (chặn phiên mới).
 *   3. Một lần update RTDB: ẩn danh hồ sơ, gỡ userIndex, gỡ chamcong_links/users, ghi audit.
 *   4. Xóa Firebase Auth user (bước cuối → nếu lỗi, gọi lại vẫn an toàn vì index đã gỡ).
 */
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {
  DELETE_CONFIRM_WORD,
  ROOT_OWNER_CODE,
  ROOT_OWNER_MESSAGE,
  ProfileLike,
  planAccountDeletion,
  storeCodesFromIndex,
  chamCongUidOf,
  buildAnonymisedProfile,
  buildSelfDeleteAudit,
  isConfirmed,
} from "./deleteMyAccountLogic";

const FUNCTION_REGION = "asia-southeast1";

// Lấy db/auth lười (index.ts gọi initializeApp trước khi hàm chạy)
const db = () => admin.database();
const auth = () => admin.auth();

export const deleteMyAccount = onCall({ region: FUNCTION_REGION }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Yêu cầu đăng nhập trước khi thực hiện.");
  }
  const data = (request.data || {}) as Record<string, unknown>;
  if (!isConfirmed(data.confirm)) {
    throw new HttpsError("invalid-argument", `Vui lòng nhập đúng từ khóa "${DELETE_CONFIRM_WORD}" để xác nhận.`);
  }

  const uid = request.auth.uid;

  // 1. Tìm mọi chi nhánh có hồ sơ của người gọi
  const indexSnap = await db().ref(`userIndex/${uid}`).get();
  const indexStores = storeCodesFromIndex(indexSnap.val());
  const profileSnaps = await Promise.all(indexStores.map((s) => db().ref(`stores/${s}/users/${uid}`).get()));
  const profiles: Record<string, ProfileLike | null> = {};
  indexStores.forEach((s, i) => {
    profiles[s] = profileSnaps[i].exists() ? (profileSnaps[i].val() as ProfileLike) : null;
  });

  const plan = planAccountDeletion(indexStores, profiles);
  if (plan.kind === "ROOT_OWNER") {
    throw new HttpsError("failed-precondition", ROOT_OWNER_MESSAGE, { code: ROOT_OWNER_CODE });
  }

  // 2. Chặn phiên mới (lỗi nếu user đã bị xóa trước đó → bỏ qua)
  await auth().revokeRefreshTokens(uid).catch(() => undefined);

  // 3. Ghi RTDB một lần
  const now = Date.now();
  const updates: Record<string, unknown> = {};
  try {
    for (const s of plan.anonymiseStores) {
      const profile = profiles[s] as ProfileLike;
      updates[`stores/${s}/users/${uid}`] = buildAnonymisedProfile(profile, uid, now);

      const ccUid = chamCongUidOf(profile, uid);
      if (ccUid) {
        const linkSnap = await db().ref(`chamcong_links/users/${s}/${ccUid}`).get();
        if (linkSnap.val() === uid) updates[`chamcong_links/users/${s}/${ccUid}`] = null;
      }

      const logId = `LOG_${now}_${Math.random().toString(36).substring(2, 7)}`;
      updates[`stores/${s}/audit_logs/${logId}`] = buildSelfDeleteAudit(uid, profile.roleId, now);
    }
    for (const s of plan.indexStores) {
      updates[`userIndex/${uid}/${s}`] = null;
    }
    if (Object.keys(updates).length > 0) {
      await db().ref().update(updates);
    }
  } catch (err: any) {
    console.error("deleteMyAccount: lỗi ghi RTDB", err?.message);
    throw new HttpsError("internal", "Không thể xóa tài khoản lúc này. Vui lòng thử lại sau ít phút.");
  }

  // 4. Xóa tài khoản đăng nhập (idempotent: không còn thì coi như xong)
  try {
    await auth().deleteUser(uid);
  } catch (err: any) {
    if (err?.code !== "auth/user-not-found") {
      console.error("deleteMyAccount: lỗi xóa Auth user", err?.message);
      throw new HttpsError(
        "internal",
        "Hồ sơ đã được xóa nhưng chưa xóa xong tài khoản đăng nhập. Vui lòng thử lại."
      );
    }
  }

  return { success: true };
});
