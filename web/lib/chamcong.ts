/**
 * Helper thuần (không phụ thuộc Firebase SDK) cho tính năng
 * "Đăng nhập bằng Chấm Công Trạm" — chuẩn hóa phản hồi callable & thông báo lỗi tiếng Việt.
 *
 * Hợp đồng máy chủ (functions/, region asia-southeast1):
 *  - chamCongSignIn({ idToken, storeCode? })
 *      → { status: "OK", customToken, storeCode, uid, roleId, isNewAccount }
 *      → { status: "CHOOSE_STORE", stores: [{ storeCode, storeName }] }
 *  - linkChamCongStore({ storeCode, idToken, chamCongStoreId? })
 *      → { status: "CHOOSE_CHAMCONG_STORE", stores: [{ chamCongStoreId, name, code }] }
 *      → { status: "LINKED", chamCongStoreId, chamCongStoreName }
 *  - unlinkChamCongStore({ storeCode })
 *  - getChamCongLinkStatus({ storeCode })
 *      → { linked, chamCongStoreId?, chamCongStoreName?, linkedAt?, provisionedCount }
 */

export type ChamCongMethod = "google" | "apple" | { email: string; password: string };

export interface ChamCongStoreOption {
  storeCode: string;
  storeName: string;
}

export type ChamCongSignInResponse =
  | {
      status: "OK";
      customToken: string;
      storeCode: string;
      uid: string;
      roleId: string;
      isNewAccount: boolean;
    }
  | { status: "CHOOSE_STORE"; stores: ChamCongStoreOption[] };

export interface ChamCongWorkplace {
  chamCongStoreId: string;
  name: string;
  code: string;
}

export type LinkChamCongResponse =
  | { status: "CHOOSE_CHAMCONG_STORE"; stores: ChamCongWorkplace[] }
  | { status: "LINKED"; chamCongStoreId: string; chamCongStoreName: string };

export interface ChamCongLinkStatus {
  linked: boolean;
  chamCongStoreId?: string;
  chamCongStoreName?: string;
  linkedAt?: number;
  provisionedCount: number;
}

type Rec = Record<string, unknown>;

const isRec = (v: unknown): v is Rec => typeof v === "object" && v !== null && !Array.isArray(v);
const str = (v: unknown): string => (typeof v === "string" ? v : typeof v === "number" ? String(v) : "");

/** Kiểm tra đủ 4 biến môi trường cấu hình Firebase của dự án chamcongtram. */
export function hasChamCongConfig(cfg: {
  apiKey?: string;
  authDomain?: string;
  projectId?: string;
  appId?: string;
}): boolean {
  return [cfg.apiKey, cfg.authDomain, cfg.projectId, cfg.appId].every(
    (v) => typeof v === "string" && v.trim().length > 0
  );
}

export function parseChamCongSignInResponse(data: unknown): ChamCongSignInResponse | null {
  if (!isRec(data)) return null;
  if (data.status === "OK") {
    const customToken = str(data.customToken);
    const storeCode = str(data.storeCode).trim().toUpperCase();
    if (!customToken || !storeCode) return null;
    return {
      status: "OK",
      customToken,
      storeCode,
      uid: str(data.uid),
      roleId: str(data.roleId) || "ROLE_WAITER",
      isNewAccount: data.isNewAccount === true,
    };
  }
  if (data.status === "CHOOSE_STORE") {
    const raw = Array.isArray(data.stores) ? data.stores : [];
    const stores: ChamCongStoreOption[] = [];
    for (const s of raw) {
      if (!isRec(s)) continue;
      const storeCode = str(s.storeCode).trim().toUpperCase();
      if (!storeCode) continue;
      stores.push({ storeCode, storeName: str(s.storeName) || storeCode });
    }
    if (stores.length === 0) return null;
    return { status: "CHOOSE_STORE", stores };
  }
  return null;
}

export function parseLinkChamCongResponse(data: unknown): LinkChamCongResponse | null {
  if (!isRec(data)) return null;
  if (data.status === "LINKED") {
    const chamCongStoreId = str(data.chamCongStoreId);
    if (!chamCongStoreId) return null;
    return { status: "LINKED", chamCongStoreId, chamCongStoreName: str(data.chamCongStoreName) || chamCongStoreId };
  }
  if (data.status === "CHOOSE_CHAMCONG_STORE") {
    const raw = Array.isArray(data.stores) ? data.stores : [];
    const stores: ChamCongWorkplace[] = [];
    for (const s of raw) {
      if (!isRec(s)) continue;
      const chamCongStoreId = str(s.chamCongStoreId);
      if (!chamCongStoreId) continue;
      stores.push({ chamCongStoreId, name: str(s.name) || chamCongStoreId, code: str(s.code) });
    }
    if (stores.length === 0) return null;
    return { status: "CHOOSE_CHAMCONG_STORE", stores };
  }
  return null;
}

export function parseChamCongLinkStatus(data: unknown): ChamCongLinkStatus {
  if (!isRec(data)) return { linked: false, provisionedCount: 0 };
  const linkedAtRaw = data.linkedAt;
  let linkedAt: number | undefined;
  if (typeof linkedAtRaw === "number" && Number.isFinite(linkedAtRaw)) linkedAt = linkedAtRaw;
  else if (typeof linkedAtRaw === "string" && linkedAtRaw) {
    const t = Date.parse(linkedAtRaw);
    if (!Number.isNaN(t)) linkedAt = t;
  }
  const count = Number(data.provisionedCount);
  return {
    linked: data.linked === true,
    chamCongStoreId: str(data.chamCongStoreId) || undefined,
    chamCongStoreName: str(data.chamCongStoreName) || undefined,
    linkedAt,
    provisionedCount: Number.isFinite(count) && count > 0 ? Math.floor(count) : 0,
  };
}

export const ROLE_LABELS_VI: Record<string, string> = {
  ROLE_OWNER: "Chủ quán",
  ROLE_MANAGER_1: "Quản lý 1",
  ROLE_MANAGER_2: "Quản lý 2",
  ROLE_MANAGER: "Quản lý",
  ROLE_CASHIER: "Thu ngân",
  ROLE_WAITER: "Phục vụ",
  ROLE_KITCHEN: "Bếp",
};

export function roleLabelVi(roleId: string): string {
  return ROLE_LABELS_VI[(roleId || "").toUpperCase()] || roleId || "Phục vụ";
}

/** Thông báo khi tài khoản Chấm Công đăng nhập được nhưng vai trò POS không vào được Web Quản trị. */
export function chamCongNotAdminMessage(roleId: string, isNewAccount: boolean): string {
  const role = roleLabelVi(roleId);
  const prefix = isNewAccount
    ? `Đã tạo tài khoản POS cho bạn với vai trò ${role}.`
    : `Tài khoản POS của bạn đang ở vai trò ${role}.`;
  return `${prefix} Web Quản trị chỉ dành cho Chủ quán hoặc Quản lý — nhờ chủ quán nâng quyền trong mục Nhân viên.`;
}

export const CHAMCONG_ERROR_MESSAGES: Record<string, string> = {
  INVALID_TOKEN: "Phiên đăng nhập Chấm Công không hợp lệ hoặc đã hết hạn. Vui lòng đăng nhập lại.",
  NOT_LINKED: "Cửa hàng chấm công của bạn chưa được liên kết với POS. Nhờ chủ quán liên kết trong Cài đặt.",
  NOT_ACTIVE_MEMBER: "Bạn chưa là nhân viên đang hoạt động của cửa hàng chấm công đã liên kết với POS.",
  POS_ACCOUNT_DISABLED: "Tài khoản POS của bạn đã bị chủ quán tạm khóa. Vui lòng liên hệ chủ quán.",
  ALREADY_LINKED: "Cửa hàng chấm công này đã được liên kết với một chi nhánh POS khác.",
  POS_ACCOUNT_CONFLICT: "Tài khoản Chấm Công này trùng với một tài khoản POS sẵn có. Vui lòng liên hệ chủ quán để xử lý.",
  NOT_STORE_OWNER: "Chỉ chủ cửa hàng bên Chấm Công Trạm mới được liên kết cửa hàng đó với POS.",
};

/**
 * Chuyển lỗi (Firebase Auth phía chamcongtram hoặc callable của POS) thành thông báo tiếng Việt.
 * @param host tên miền hiện tại (dùng trong thông báo unauthorized-domain).
 */
export function mapChamCongError(err: unknown, host?: string): string {
  const e = (isRec(err) ? err : {}) as { code?: unknown; message?: unknown; details?: unknown };
  const details = isRec(e.details) ? e.details : {};
  const serverCode = str(details.code).toUpperCase();
  if (serverCode && CHAMCONG_ERROR_MESSAGES[serverCode]) return CHAMCONG_ERROR_MESSAGES[serverCode];

  const code = str(e.code);
  const message = str(e.message);
  switch (code) {
    case "auth/popup-blocked":
      return "Trình duyệt đã chặn cửa sổ đăng nhập. Hãy cho phép cửa sổ bật lên (popup) cho trang này rồi thử lại.";
    case "auth/popup-closed-by-user":
    case "auth/cancelled-popup-request":
    case "auth/user-cancelled":
      return "Bạn đã đóng cửa sổ đăng nhập trước khi hoàn tất.";
    case "auth/unauthorized-domain": {
      const d = host ? `"${host}"` : "hiện tại";
      return `Tên miền ${d} chưa được phép đăng nhập Chấm Công Trạm. Quản trị viên cần thêm tên miền này vào Firebase Console → dự án chamcongtram → Authentication → Settings → Authorized domains.`;
    }
    case "auth/operation-not-allowed":
      return "Phương thức đăng nhập này chưa được bật cho Chấm Công Trạm.";
    case "auth/invalid-credential":
    case "auth/invalid-login-credentials":
    case "auth/wrong-password":
    case "auth/user-not-found":
      return "Email hoặc mật khẩu Chấm Công không đúng.";
    case "auth/invalid-email":
      return "Địa chỉ email không hợp lệ.";
    case "auth/missing-password":
      return "Vui lòng nhập mật khẩu.";
    case "auth/user-disabled":
      return "Tài khoản Chấm Công này đã bị vô hiệu hóa.";
    case "auth/account-exists-with-different-credential":
      return "Email này đã đăng ký Chấm Công bằng phương thức khác. Hãy thử đăng nhập bằng phương thức bạn đã dùng trước đó.";
    case "auth/too-many-requests":
      return "Bạn đã thử quá nhiều lần. Vui lòng đợi ít phút rồi thử lại.";
    case "auth/network-request-failed":
    case "functions/unavailable":
    case "functions/deadline-exceeded":
    case "unavailable":
    case "deadline-exceeded":
      return "Không thể kết nối đến máy chủ. Vui lòng kiểm tra kết nối mạng và thử lại.";
    case "functions/unauthenticated":
    case "unauthenticated":
      return "Phiên đăng nhập không hợp lệ. Vui lòng thử lại.";
    case "functions/permission-denied":
    case "permission-denied":
      return message || "Bạn không có quyền thực hiện thao tác này.";
    case "functions/not-found":
    case "not-found":
      return message || "Không tìm thấy dữ liệu cần thiết.";
    case "functions/internal":
    case "internal":
      return "Máy chủ chưa được cấu hình kết nối Chấm Công Trạm. Vui lòng liên hệ chủ quán.";
    case "functions/invalid-argument":
    case "functions/failed-precondition":
    case "invalid-argument":
    case "failed-precondition":
      return message || "Yêu cầu không hợp lệ.";
    default:
      return "Không thể đăng nhập bằng Chấm Công Trạm. Vui lòng thử lại sau.";
  }
}
