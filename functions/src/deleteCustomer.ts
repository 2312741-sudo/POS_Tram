/**
 * Cloud Function "Xóa khách hàng" (deleteCustomer). Request: { storeCode, customerId, confirm: "XOA" }.
 * Response: { success: true, removedMember: boolean }. Logic thuần ở deleteCustomerLogic.ts.
 *
 * - Chỉ Chủ quán / Quản lý đang hoạt động của chi nhánh.
 * - Xóa stores/{s}/customers/{id} + gỡ liên kết chi nhánh trong loyalty_members (một multi-path update).
 * - Nếu khách không còn ở chi nhánh nào: xóa luôn loyalty_members, loyalty_ledger và chỉ mục sổ cái (không còn SĐT).
 *   Nếu còn chi nhánh khác: giữ điểm/sổ cái chung, chỉ gỡ liên kết chi nhánh này.
 * - Hóa đơn cũ giữ nguyên (kế toán). Bản sao Firestore kmt_customers xóa theo kiểu best-effort.
 */
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { UserProfile } from "./permissions";
import { isValidCustomerKey, isValidStoreCode } from "./customerSync";
import {
  DELETE_CUSTOMER_CONFIRM,
  buildDeleteAuditDetails,
  canCallerDeleteCustomer,
  isDeleteConfirmed,
  planDeleteCustomer,
} from "./deleteCustomerLogic";
import { TRAM_CHAIN_STORES, isTramChainStore } from "./sharedLoyalty";

const FUNCTION_REGION = "asia-southeast1";
const db = () => admin.database();
type AnyMap = Record<string, unknown>;

export const deleteCustomer = onCall({ region: FUNCTION_REGION }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Yêu cầu đăng nhập trước khi thực hiện.");
  }
  const data = (request.data || {}) as Record<string, unknown>;
  const storeCode = typeof data.storeCode === "string" ? data.storeCode.trim().toUpperCase() : "";
  const customerId = typeof data.customerId === "string" ? data.customerId : "";
  if (!isValidStoreCode(storeCode)) throw new HttpsError("invalid-argument", "Mã chi nhánh không hợp lệ.");
  if (!isValidCustomerKey(customerId)) throw new HttpsError("invalid-argument", "Mã khách hàng không hợp lệ.");
  if (!isDeleteConfirmed(data.confirm)) {
    throw new HttpsError("invalid-argument", `Vui lòng nhập đúng từ khóa "${DELETE_CUSTOMER_CONFIRM}" để xác nhận.`);
  }

  const uid = request.auth.uid;
  const [callerSnap, indexSnap] = await Promise.all([
    db().ref(`stores/${storeCode}/users/${uid}`).get(),
    db().ref(`userIndex/${uid}/${storeCode}`).get(),
  ]);
  const caller = (callerSnap.exists() ? callerSnap.val() : null) as UserProfile | null;
  if (!canCallerDeleteCustomer(caller, indexSnap.val() === true)) {
    throw new HttpsError("permission-denied", "Chỉ Chủ quán hoặc Quản lý mới được xóa khách hàng.");
  }

  const customerSnap = await db().ref(`stores/${storeCode}/customers/${customerId}`).get();
  if (!customerSnap.exists()) {
    throw new HttpsError("not-found", "Không tìm thấy khách hàng (có thể đã bị xóa).");
  }
  const customer = (customerSnap.val() || {}) as AnyMap;

  // Đọc member (và sổ cái nếu cần) để quyết định có xóa dữ liệu dùng chung không
  const memberKey = planDeleteCustomer({ storeCode, customerId, customer, member: null, ledger: null }).memberKey;
  const memberSnap = await db().ref(`loyalty_members/${memberKey}`).get();
  const member = (memberSnap.exists() ? memberSnap.val() : null) as AnyMap | null;
  let ledger: Record<string, AnyMap> | null = null;
  const first = planDeleteCustomer({ storeCode, customerId, customer, member, ledger: null });
  if (first.removedMember) {
    const ls = await db().ref(`loyalty_ledger/${memberKey}`).get();
    ledger = (ls.exists() ? ls.val() : null) as Record<string, AnyMap> | null;
  }
  const plan = planDeleteCustomer({ storeCode, customerId, customer, member, ledger });

  const now = Date.now();
  const logId = `LOG_${now}_${Math.random().toString(36).substring(2, 7)}`;
  const updates: Record<string, unknown> = {
    ...plan.updates,
    [`stores/${storeCode}/audit_logs/${logId}`]: {
      timestamp: now,
      action: "DELETE_CUSTOMER",
      username: caller?.username || "unknown",
      userFullName: caller?.fullName || "",
      userRole: caller?.roleId || "",
      targetType: "CUSTOMER",
      targetId: customerId,
      details: buildDeleteAuditDetails(customer.ho_ten ?? customer.name, customer.so_dien_thoai ?? customer.phone, plan.removedMember),
    },
  };
  if (isTramChainStore(storeCode)) {
    for (const other of TRAM_CHAIN_STORES) {
      if (other !== storeCode) {
        updates[`stores/${other}/customers/${customerId}`] = null;
        if (memberKey) {
          updates[`loyalty_members/${memberKey}/branches/${other}/${customerId}`] = null;
        }
      }
    }
  }
  await db().ref().update(updates);

  // Bản sao Firestore (best-effort): chỉ xóa khi bản sao đúng của chi nhánh này
  try {
    const ref = admin.firestore().collection("kmt_customers").doc(customerId);
    const doc = await ref.get();
    if (doc.exists && (doc.data() || {}).pointsSource === `rtdb:stores/${storeCode}/customers`) await ref.delete();
  } catch (e) {
    console.error("deleteCustomer: xóa kmt_customers lỗi", storeCode, customerId, e);
  }

  return { success: true, removedMember: plan.removedMember };
});
