/**
 * Cloud Function "Tạo chi nhánh mới" (createStore) — web admin không còn ghi trực tiếp stores/{mới}
 * (rules chặn vì chưa có userIndex/{uid}/{mới}). Request: { storeCode, storeName, address?, phone?,
 * bankId?, bankAccount?, accountName?, wifiName?, defaultVatRate?, allowStackPromotions?, copyZonesFrom? }.
 * Response: { success, storeCode, zonesFrom: string | null, warning? }.
 * Logic thuần ở createStoreLogic.ts. Sao chép THỰC ĐƠN vẫn do client làm sau khi hàm trả về.
 */
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { UserProfile } from "./permissions";
import { storeCodesFromIndex } from "./deleteMyAccountLogic";
import {
  StoreInfoInput,
  ZoneLayout,
  decideOwnerAccess,
  layoutFromSource,
  normalizeStoreCode,
  planCreateStore,
} from "./createStoreLogic";

const FUNCTION_REGION = "asia-southeast1";
const db = () => admin.database();

/** Hồ sơ của uid tại từng chi nhánh (null nếu không có). */
async function loadProfiles(stores: string[], uid: string): Promise<Record<string, UserProfile | null>> {
  const snaps = await Promise.all(stores.map((s) => db().ref(`stores/${s}/users/${uid}`).get()));
  const out: Record<string, UserProfile | null> = {};
  stores.forEach((s, i) => {
    out[s] = snaps[i].exists() ? (snaps[i].val() as UserProfile) : null;
  });
  return out;
}

export const createStore = onCall({ region: FUNCTION_REGION }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Yêu cầu đăng nhập trước khi thực hiện.");
  }
  const uid = request.auth.uid;
  const data = (request.data || {}) as Record<string, unknown>;

  // 1. Quyền: chủ quán (đang hoạt động) ở ít nhất một chi nhánh trong userIndex/{uid}
  const indexStores = storeCodesFromIndex((await db().ref(`userIndex/${uid}`).get()).val());
  const profiles = await loadProfiles(indexStores, uid);
  const access = decideOwnerAccess(indexStores, profiles);
  if (!access.allowed) {
    throw new HttpsError("permission-denied", "Chỉ chủ quán mới được tạo cửa hàng");
  }

  // 2. Mã chi nhánh
  const norm = normalizeStoreCode(data.storeCode);
  if ("error" in norm) {
    throw new HttpsError("invalid-argument", norm.error);
  }
  const code = norm.code;

  const existing = await db().ref(`stores/${code}/storeInfo`).get();
  if (existing.exists()) {
    throw new HttpsError("already-exists", `Mã chi nhánh "${code}" đã tồn tại`);
  }

  // 3. Sao chép khu/bàn từ chi nhánh nguồn (tùy chọn; chỉ khi người gọi cũng là chủ quán ở nguồn)
  let layout: ZoneLayout | null = null;
  let copiedFrom: string | null = null;
  let warning: string | undefined;
  if (typeof data.copyZonesFrom === "string" && data.copyZonesFrom.trim()) {
    const src = normalizeStoreCode(data.copyZonesFrom);
    if ("error" in src) {
      warning = "Mã chi nhánh nguồn không hợp lệ nên dùng khu vực mặc định.";
    } else if (!decideOwnerAccess([src.code], profiles).allowed) {
      warning = `Bạn không phải chủ quán ở chi nhánh ${src.code} nên không sao chép khu vực/bàn; dùng khu vực mặc định.`;
    } else {
      const [zonesSnap, tablesSnap] = await Promise.all([
        db().ref(`stores/${src.code}/zones`).get(),
        db().ref(`stores/${src.code}/tables`).get(),
      ]);
      const candidate = layoutFromSource(zonesSnap.val(), tablesSnap.val());
      if (Object.keys(candidate.zones).length > 0) {
        layout = candidate;
        copiedFrom = src.code;
      } else {
        warning = `Chi nhánh ${src.code} chưa có khu vực nên dùng khu vực mặc định.`;
      }
    }
  }

  // 4. Ghi atomic (một multi-path update)
  const now = Date.now();
  const plan = planCreateStore({
    code,
    uid,
    now,
    auditId: `LOG_${now}_${Math.random().toString(36).substring(2, 7)}`,
    input: data as StoreInfoInput,
    caller: access.profile,
    layout,
  });
  try {
    await db().ref().update(plan.updates);
  } catch (err: any) {
    console.error("createStore: lỗi ghi RTDB", err?.message);
    throw new HttpsError("internal", "Không thể tạo chi nhánh lúc này. Vui lòng thử lại sau ít phút.");
  }

  return {
    success: true,
    storeCode: code,
    zonesFrom: plan.zonesFrom === "copied" ? copiedFrom : null,
    ...(warning ? { warning } : {}),
  };
});
