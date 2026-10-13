"use client";
import React, { createContext, useContext, useState, useEffect, useCallback } from "react";
import { db, auth, functions } from "./firebase";
import {
  mapChamCongError,
  parseChamCongSignInResponse,
  type ChamCongMethod,
  type ChamCongStoreOption,
} from "./chamcong";
import { authenticateChamCong, getCurrentChamCongIdToken, signOutChamCong } from "./chamcong-firebase";
import { ref, get, set, update } from "firebase/database";
import { httpsCallable } from "firebase/functions";
import { PERMISSION_CATALOG } from "./permission-catalog";
import { setExportGrants } from "./export-guard";
import { ROLE_OWNER, ROLE_MANAGER, ROLE_STAFF, ROLE_KITCHEN, normalizeRoleId } from "./roles";

export { normalizeRoleId, roleLabel, ROLE_OWNER, ROLE_MANAGER, ROLE_STAFF, ROLE_KITCHEN } from "./roles";
import {
  signInWithCustomToken,
  signOut,
  onAuthStateChanged,
  updatePassword,
  User as FirebaseUser,
} from "firebase/auth";

export interface User {
  id: string;
  uid: string;
  fullName: string;
  username: string;
  roleId: string;
  role: string;
  isRootOwner: boolean;
  customPermissions?: string[];
  isActive: boolean;
  phone?: string;
  storeCode: string;
  storeName?: string;
  createdAt?: number;
  lastLoginAt?: number;
  mustChangePassword?: boolean;
}

export type ChamCongLoginResult =
  | { success: true; mustChangePassword?: boolean }
  | { success: false; error: string; chooseStore?: undefined }
  | { success: false; error?: undefined; chooseStore: ChamCongStoreOption[] };

export interface AuthContextType {
  user: User | null;
  loading: boolean;
  storeCode: string;
  setStoreCode: (code: string) => void;
  login: (
    storeCode: string,
    username: string,
    password: string
  ) => Promise<{ success: boolean; error?: string; mustChangePassword?: boolean }>;
  /**
   * Đăng nhập bằng tài khoản Chấm Công Trạm. Nếu trả về `chooseStore`, hiển thị danh sách
   * và gọi lại với `storeCode` (phiên Chấm Công được giữ trong bộ nhớ, không mở lại popup).
   */
  signInWithChamCong: (method: ChamCongMethod, storeCode?: string) => Promise<ChamCongLoginResult>;
  logout: () => Promise<void>;
  refreshUser: () => Promise<void>;
  changeCurrentPassword: (newPassword: string) => Promise<{ success: boolean; error?: string }>;
}

// ---------------------------------------------------------------------------
// 1. Chuẩn hóa & Kiểm tra dữ liệu (Username & Email validation)
// ---------------------------------------------------------------------------

export function normalizeUsername(username: string): string {
  return username.trim().toLowerCase();
}

export function validateUsername(username: string): { valid: boolean; error?: string } {
  const clean = normalizeUsername(username);

  if (!clean) {
    return { valid: false, error: "Vui lòng nhập tên đăng nhập" };
  }
  if (/\s/.test(username)) {
    return { valid: false, error: "Tên đăng nhập không được chứa khoảng trắng" };
  }
  if (/\./.test(username)) {
    return { valid: false, error: "Tên đăng nhập không được chứa dấu chấm" };
  }
  if (clean.length < 3) {
    return { valid: false, error: "Tên đăng nhập phải có ít nhất 3 ký tự" };
  }
  if (clean.length > 30) {
    return { valid: false, error: "Tên đăng nhập tối đa 30 ký tự" };
  }
  // Cho phép chữ thường a-z, số 0-9, gạch dưới _, gạch ngang -
  const regex = /^[a-z0-9_-]{3,30}$/;
  if (!regex.test(clean)) {
    return {
      valid: false,
      error: "Tên đăng nhập chỉ gồm chữ thường (a-z), số (0-9), gạch dưới (_) hoặc gạch ngang (-)",
    };
  }

  return { valid: true };
}

export function generateEmail(username: string, storeCode: string): string {
  const cleanUser = normalizeUsername(username);
  const cleanStore = storeCode.trim().toLowerCase();
  return `${cleanUser}.${cleanStore}@tram.local`;
}

// ---------------------------------------------------------------------------
// 2. Hệ thống phân quyền RBAC Matrix (theo AUTH_CONTRACT.md)
// ---------------------------------------------------------------------------

/**
 * Quyền mặc định theo vai trò — CHỈ có 4 mã vai trò chuẩn (xem lib/roles.ts):
 * ROLE_OWNER, ROLE_MANAGER (đã gộp QL1+QL2 = HỢP hai bộ quyền cũ), ROLE_STAFF (đã gộp Thu ngân+Phục vụ), ROLE_KITCHEN.
 * Mã cũ được chuẩn hóa bởi normalizeRoleId trước khi tra bảng. Nguồn song song: app_permissions.dart.
 */
export const ROLE_PERMISSIONS: Record<string, string[]> = {
  // Chủ quán có toàn quyền
  [ROLE_OWNER]: PERMISSION_CATALOG.map((p) => p.key),
  // Quản lý = hợp Quản lý 1 + Quản lý 2
  [ROLE_MANAGER]: [
    "VIEW_MENU", "EDIT_MENU", "CHANGE_PRICE", "MENU_MANAGEMENT", "OPEN_TABLE", "CHANGE_TABLE",
    "MERGE_SPLIT_TABLE", "SEND_KITCHEN", "CREATE_BILL", "EDIT_BILL",
    "APPLY_PROMOTION", "MANUAL_DISCOUNT", "DISCOUNT_ITEM", "PRINT_BILL",
    "REPRINT_BILL", "MANAGE_CASH_SHIFT", "ADJUST_CASH_SHIFT", "VIEW_REPORTS",
    "MANAGE_PROMOTIONS", "VIEW_INVENTORY", "EDIT_CATALOG_ITEM", "VIEW_COST_PRICE",
    "MANAGE_RECIPES", "VIEW_SUPPLIERS", "EDIT_SUPPLIERS", "CREATE_RECEIPT", "INVENTORY_STOCK_IN",
    "COMPLETE_RECEIPT", "CREATE_PURCHASE_RETURN", "RECORD_SUPPLIER_PAYMENT", "CREATE_STOCKTAKE",
    "APPROVE_STOCKTAKE", "CREATE_TRANSFER", "RECEIVE_TRANSFER", "CREATE_WASTE", "INVENTORY_WASTE",
    "CREATE_INTERNAL_USE", "INVENTORY_STOCK_OUT", "CREATE_PRODUCTION", "CREATE_CAMPAIGN",
    "EDIT_CAMPAIGN", "ACTIVATE_CAMPAIGN", "MANAGE_CODES", "COPY_MENU", "DELETE_ITEM",
    "MANAGE_TABLES", "REDEEM_POINTS", "VIEW_CUSTOMERS", "MANAGE_CUSTOMERS", "ADJUST_POINTS",
    "EXPORT_REPORTS", "EXPORT_DATA", "VIEW_CASH_SHIFTS", "VIEW_ONLINE_ORDERS",
    "MANAGE_ONLINE_ORDERS", "VIEW_KITCHEN", "MANAGE_MANAGER_PIN",
    "CREATE_SAMPLE_DATA", "VIEW_SHIFT_HANDOVER", "VIEW_ALL_SHIFTS", "VIEW_ALL_BILLS_HISTORY",
    "TOGGLE_ITEM_AVAILABILITY", "MANAGE_NOTE_CATALOG",
  ],
  // Nhân viên = hợp Thu ngân + Phục vụ
  [ROLE_STAFF]: [
    "VIEW_MENU", "OPEN_TABLE", "CHANGE_TABLE", "SEND_KITCHEN", "CREATE_BILL", "APPLY_PROMOTION",
    "PRINT_BILL", "DELETE_ITEM", "REDEEM_POINTS", "VIEW_CUSTOMERS", "MANAGE_CUSTOMERS",
    "VIEW_ONLINE_ORDERS", "MANAGE_ONLINE_ORDERS", "VIEW_KITCHEN", "MANAGE_CASH_SHIFT",
    "VIEW_CASH_SHIFTS", "TOGGLE_ITEM_AVAILABILITY",
  ],
  [ROLE_KITCHEN]: ["VIEW_MENU", "SEND_KITCHEN", "VIEW_KITCHEN", "TOGGLE_ITEM_AVAILABILITY"],
};

/** Mã vai trò (đã chuẩn hóa) của người dùng. */
export function userRoleId(user: { roleId?: string; role?: string } | null | undefined): string {
  return normalizeRoleId(user?.roleId || user?.role || "");
}

export function hasPermission(user: User | null, permission: string): boolean {
  if (!user) return false;

  // Sovereign Owner Rule: Chủ quán tối cao luôn có mọi quyền
  if (user.isRootOwner) return true;
  const roleKey = userRoleId(user);
  if (roleKey === ROLE_OWNER) return true;

  const userPerms = Array.isArray(user.customPermissions) ? user.customPermissions : [];
  const checkSingle = (p: string) => {
    if (userPerms.includes(p)) return true;
    const perms = ROLE_PERMISSIONS[roleKey] || [];
    return perms.includes(p);
  };

  if (checkSingle(permission)) return true;

  // Đồng bộ các mã quyền tương đương
  const aliases: Record<string, string[]> = {
    INVENTORY_STOCK_IN: ["CREATE_RECEIPT"],
    CREATE_RECEIPT: ["INVENTORY_STOCK_IN"],
    INVENTORY_STOCK_OUT: ["CREATE_INTERNAL_USE"],
    CREATE_INTERNAL_USE: ["INVENTORY_STOCK_OUT"],
    INVENTORY_WASTE: ["CREATE_WASTE"],
    CREATE_WASTE: ["INVENTORY_WASTE"],
    DISCOUNT_ITEM: ["MANUAL_DISCOUNT"],
    // Chỉ EDIT_MENU thay thế được MENU_MANAGEMENT — VIEW_MENU (xem thực đơn khi gọi món) KHÔNG đủ để quản lý thực đơn.
    MENU_MANAGEMENT: ["EDIT_MENU"],
  };

  if (aliases[permission]) {
    for (const alt of aliases[permission]) {
      if (checkSingle(alt)) return true;
    }
  }

  return false;
}

export function isWebAdminRole(roleId: string, isRootOwner?: boolean): boolean {
  if (isRootOwner) return true;
  const r = normalizeRoleId(roleId);
  return r === ROLE_OWNER || r === ROLE_MANAGER;
}

/** Trang đáp sau đăng nhập: Chủ / Quản lý → Tổng quan; vai trò khác → trang đầu tiên được phép */
export function homePathFor(user: User | null): string {
  if (!user) return "/login";
  if (canAccessRoute(user, "/dashboard")) return "/dashboard";
  for (const p of ["/dashboard/tables", "/dashboard/kitchen", "/dashboard/orders"]) {
    if (canAccessRoute(user, p)) return p;
  }
  return "/dashboard";
}

export function canAccessRoute(user: User | null, pathname: string): boolean {
  if (!user) return false;
  if (user.isRootOwner) return true;
  if (userRoleId(user) === ROLE_OWNER) return true;

  if (pathname.startsWith("/dashboard/users")) {
    return hasPermission(user, "MANAGE_USERS");
  }
  if (pathname.startsWith("/dashboard/stores")) {
    return hasPermission(user, "MANAGE_STORE_SETTINGS");
  }
  if (pathname.startsWith("/dashboard/audit") || pathname.startsWith("/dashboard/action-codes")) {
    return hasPermission(user, "VIEW_AUDIT_LOGS");
  }
  if (pathname.startsWith("/dashboard/inventory") || pathname.startsWith("/dashboard/reports/inventory")) {
    return hasPermission(user, "VIEW_INVENTORY");
  }
  if (pathname.startsWith("/dashboard/promotions")) {
    return hasPermission(user, "MANAGE_PROMOTIONS");
  }
  if (
    pathname.startsWith("/dashboard/revenue") ||
    pathname.startsWith("/dashboard/analytics") ||
    pathname.startsWith("/dashboard/end-of-day") ||
    pathname.startsWith("/dashboard/product-sales") ||
    pathname.startsWith("/dashboard/reports/promotions") ||
    pathname.startsWith("/dashboard/reports/loyalty")
  ) {
    return hasPermission(user, "VIEW_REPORTS");
  }
  if (pathname.startsWith("/dashboard/shifts")) {
    // Phiếu bàn giao ca: chỉ Chủ/Quản lý (hoặc tài khoản được cấp) — Nhân viên mặc định KHÔNG thấy
    return (
      hasPermission(user, "VIEW_SHIFT_HANDOVER") ||
      hasPermission(user, "VIEW_ALL_SHIFTS") ||
      hasPermission(user, "VIEW_REPORTS")
    );
  }
  if (pathname.startsWith("/dashboard/customers")) {
    return hasPermission(user, "VIEW_CUSTOMERS") || hasPermission(user, "VIEW_REPORTS");
  }
  if (pathname.startsWith("/dashboard/products")) {
    // Quản lý thực đơn / danh mục / topping: cần quyền quản lý, VIEW_MENU (xem khi gọi món) KHÔNG đủ
    return hasPermission(user, "MENU_MANAGEMENT");
  }
  if (pathname.startsWith("/dashboard/tables")) {
    return hasPermission(user, "OPEN_TABLE");
  }
  if (pathname.startsWith("/dashboard/kitchen")) {
    return hasPermission(user, "VIEW_KITCHEN");
  }
  if (pathname.startsWith("/dashboard/orders")) {
    return hasPermission(user, "CREATE_BILL");
  }

  return isWebAdminRole(user.roleId || user.role, user.isRootOwner);
}

/**
 * Chuyển lỗi từ Cloud Function staffSignIn thành thông báo tiếng Việt.
 */
export function mapStaffSignInError(err: unknown): string {
  const e = err as { code?: string; message?: string; details?: { remainingSeconds?: number } };
  const code = (e?.code || "").replace(/^functions\//, "");
  switch (code) {
    case "resource-exhausted": {
      const seconds = typeof e.details?.remainingSeconds === "number" ? e.details.remainingSeconds : 0;
      if (seconds > 0) {
        const minutes = Math.max(1, Math.ceil(seconds / 60));
        return `Tài khoản đã bị khóa tạm thời do nhập sai mật khẩu 5 lần liên tiếp. Vui lòng thử lại sau ${minutes} phút hoặc liên hệ Quản lý.`;
      }
      return e.message || "Hệ thống đang tạm hạn chế đăng nhập. Vui lòng thử lại sau ít phút.";
    }
    case "unauthenticated":
      return "Sai tài khoản hoặc mật khẩu.";
    case "permission-denied":
    case "invalid-argument":
    case "failed-precondition":
      return e.message || "Đăng nhập thất bại.";
    case "unavailable":
    case "deadline-exceeded":
      return "Không thể kết nối đến máy chủ. Vui lòng kiểm tra kết nối mạng và thử lại.";
    default:
      return "Không thể đăng nhập. Vui lòng kiểm tra lại thông tin hoặc thử lại sau.";
  }
}

// ---------------------------------------------------------------------------
// 3. React Auth Context & Provider
// ---------------------------------------------------------------------------

const AuthContext = createContext<AuthContextType>({
  user: null,
  loading: true,
  storeCode: "TRAM01",
  setStoreCode: () => {},
  login: async () => ({ success: false }),
  signInWithChamCong: async () => ({ success: false, error: "Chưa sẵn sàng" }),
  logout: async () => {},
  refreshUser: async () => {},
  changeCurrentPassword: async () => ({ success: false }),
});

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);

  // Cập nhật chốt chặn quyền xuất file theo người đang đăng nhập (xem lib/export-guard.ts)
  useEffect(() => {
    setExportGrants(
      user
        ? {
            EXPORT_REPORTS: hasPermission(user, "EXPORT_REPORTS"),
            EXPORT_AUDIT_LOGS: hasPermission(user, "EXPORT_AUDIT_LOGS"),
            EXPORT_DATA: hasPermission(user, "EXPORT_DATA"),
          }
        : null
    );
  }, [user]);
  const [storeCode, setStoreCodeState] = useState<string>(() => {
    if (typeof window !== "undefined") {
      try {
        const stored = localStorage.getItem("tram_store_code");
        if (stored) return stored.trim().toUpperCase();
      } catch {}
    }
    return "TRAM01";
  });

  const setStoreCode = useCallback((code: string) => {
    const clean = code.trim().toUpperCase() || "TRAM01";
    setStoreCodeState(clean);
    try {
      localStorage.setItem("tram_store_code", clean);
    } catch {}
  }, []);

  const loadUserProfile = useCallback(
    async (fbUser: FirebaseUser, targetStore: string): Promise<User | null> => {
      const cleanStore = targetStore.trim().toUpperCase() || "TRAM01";

      // 1. Thử lấy từ stores/{storeCode}/users/{uid} (theo AUTH_CONTRACT chuẩn)
      const uidRef = ref(db, `stores/${cleanStore}/users/${fbUser.uid}`);
      const uidSnap = await get(uidRef);

      let profileData: Record<string, unknown> | null = null;
      const matchedUid = fbUser.uid;

      if (uidSnap.exists()) {
        profileData = uidSnap.val() as Record<string, unknown>;
      } else {
        // Fallback: Tìm theo username từ email (chuẩn {username}.{storeCode}@tram.local)
        const email = fbUser.email || "";
        const usernamePart = email.split(".")[0];
        if (usernamePart) {
          const userLegacyRef = ref(db, `stores/${cleanStore}/users/${usernamePart}`);
          const legacySnap = await get(userLegacyRef);
          if (legacySnap.exists()) {
            profileData = legacySnap.val() as Record<string, unknown>;
          }
        }
      }

      if (!profileData) {
        return null;
      }

      const rawRoleId = String(profileData.roleId || profileData.role || "ROLE_STAFF");
      const isOwnerRole = rawRoleId.toUpperCase().includes("OWNER");
      const isRoot = profileData.isRootOwner === true || isOwnerRole;

      return {
        id: String(profileData.username || matchedUid),
        uid: matchedUid,
        fullName: String(profileData.fullName || profileData.username || "Nhân viên"),
        username: String(profileData.username || fbUser.email?.split(".")[0] || "user"),
        roleId: rawRoleId,
        role: rawRoleId,
        isRootOwner: isRoot,
        customPermissions: Array.isArray(profileData.customPermissions)
          ? (profileData.customPermissions as string[])
          : [],
        isActive: profileData.isActive !== false,
        phone: typeof profileData.phone === "string" ? profileData.phone : "",
        storeCode: cleanStore,
        storeName: typeof profileData.storeName === "string" ? profileData.storeName : undefined,
        createdAt: typeof profileData.createdAt === "number" ? profileData.createdAt : undefined,
        lastLoginAt: typeof profileData.lastLoginAt === "number" ? profileData.lastLoginAt : undefined,
        mustChangePassword: Boolean(profileData.mustChangePassword),
      };
    },
    []
  );

  // Lắng nghe trạng thái Firebase Authentication
  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, async (fbUser) => {
      // Đọc mã chi nhánh tại thời điểm sự kiện để khớp với lần đăng nhập vừa thực hiện.
      let savedStore = "TRAM01";
      try {
        const stored = localStorage.getItem("tram_store_code");
        if (stored) {
          savedStore = stored.trim().toUpperCase();
        }
      } catch {}
      if (fbUser) {
        try {
          const profile = await loadUserProfile(fbUser, savedStore);
          if (profile && profile.isActive) {
            setUser(profile);
          } else {
            // Tài khoản không tồn tại hoặc đã bị khóa
            await signOut(auth);
            setUser(null);
          }
        } catch {
          setUser(null);
        }
      } else {
        setUser(null);
      }
      setLoading(false);
    });

    return () => unsubscribe();
  }, [loadUserProfile]);

  /**
   * Phần chung sau khi máy chủ cấp Custom Token (mật khẩu POS hoặc Chấm Công Trạm):
   * đăng nhập Firebase, nạp hồ sơ, kiểm tra trạng thái & quyền Web Quản trị, ghi lastLoginAt + audit log.
   */
  const completeSignIn = useCallback(
    async (
      token: string,
      cleanStore: string,
      opts: { via: "password"; username: string } | { via: "chamcong"; isNewAccount: boolean }
    ): Promise<{ success: boolean; error?: string; mustChangePassword?: boolean }> => {
      // Ghi trước để onAuthStateChanged nạp hồ sơ đúng chi nhánh.
      try {
        localStorage.setItem("tram_store_code", cleanStore);
      } catch {}

      let cred;
      try {
        cred = await signInWithCustomToken(auth, token);
      } catch (authError: unknown) {
        return { success: false, error: mapStaffSignInError(authError) };
      }

      // 5. Nạp hồ sơ người dùng từ RTDB
      const userProfile = await loadUserProfile(cred.user, cleanStore);
      if (!userProfile) {
        await signOut(auth);
        return {
          success: false,
          error:
            opts.via === "password"
              ? `Không tìm thấy thông tin nhân viên @${opts.username} tại chi nhánh ${cleanStore}.`
              : `Không tìm thấy hồ sơ nhân viên POS tại chi nhánh ${cleanStore}.`,
        };
      }

      // 6. Kiểm tra trạng thái tài khoản
      if (!userProfile.isActive) {
        await signOut(auth);
        return {
          success: false,
          error: "Tài khoản đã bị tạm khóa bởi chủ quán.",
        };
      }

      // 7. Mọi vai trò đang hoạt động đều đăng nhập được Web; trang nào xem được do canAccessRoute quyết định
      //    (Phục vụ / Thu ngân: Sơ đồ bàn & Giao dịch; Bếp: Màn hình Bếp — xem homePathFor).

      // 8. Cập nhật lastLoginAt và ghi Audit Log
      const nowMs = Date.now();
      const username = opts.via === "password" ? opts.username : userProfile.username;
      await update(ref(db, `stores/${cleanStore}/users/${cred.user.uid}`), {
        lastLoginAt: nowMs,
      }).catch(() => {});

      const loginLogId = `LOG_${nowMs}_${Math.floor(Math.random() * 1000)}`;
      await set(ref(db, `stores/${cleanStore}/audit_logs/${loginLogId}`), {
        action: "LOGIN",
        targetType: "USER",
        targetId: cred.user.uid,
        username,
        userFullName: userProfile.fullName,
        userRole: userProfile.roleId,
        details:
          opts.via === "chamcong"
            ? `Đăng nhập Web Quản trị qua Chấm Công Trạm: ${userProfile.fullName} (@${username})`
            : `Đăng nhập Web Quản trị thành công: ${userProfile.fullName} (@${username})`,
        timestamp: nowMs,
      }).catch(() => {});

      // Lưu storeCode vào localStorage và context
      // Tài khoản Chấm Công không có mật khẩu POS → không áp dụng bắt buộc đổi mật khẩu.
      const mustChangePassword = opts.via === "password" ? userProfile.mustChangePassword : false;
      setStoreCode(cleanStore);
      setUser({ ...userProfile, lastLoginAt: nowMs, mustChangePassword });

      return {
        success: true,
        mustChangePassword,
      };
    },
    [loadUserProfile, setStoreCode]
  );

  const login = useCallback(
    async (
      inputStoreCode: string,
      inputUsername: string,
      inputPassword: string
    ): Promise<{ success: boolean; error?: string; mustChangePassword?: boolean }> => {
      try {
        const cleanStore = inputStoreCode.trim().toUpperCase();
        if (!cleanStore) {
          return { success: false, error: "Vui lòng nhập mã chi nhánh cửa hàng (vd: TRAM01)" };
        }

        const userValidation = validateUsername(inputUsername);
        if (!userValidation.valid) {
          return { success: false, error: userValidation.error };
        }

        const cleanUser = normalizeUsername(inputUsername);
        const cleanPass = inputPassword.trim();
        if (!cleanPass) {
          return { success: false, error: "Vui lòng nhập mật khẩu" };
        }

        // 1-4. Xác thực phía máy chủ qua Cloud Function staffSignIn:
        //      kiểm tra khóa tạm (5 lần sai -> khóa 15 phút), xác minh mật khẩu,
        //      ghi bộ đếm login_attempts (chỉ Admin SDK) rồi trả về Custom Token.
        let token: string | undefined;
        try {
          const staffSignIn = httpsCallable<
            { storeCode: string; username: string; password: string },
            { token?: string }
          >(functions, "staffSignIn");
          const res = await staffSignIn({ storeCode: cleanStore, username: cleanUser, password: cleanPass });
          token = res.data?.token;
        } catch (authError: unknown) {
          return { success: false, error: mapStaffSignInError(authError) };
        }
        if (!token) {
          return { success: false, error: "Máy chủ không trả về phiên đăng nhập hợp lệ. Vui lòng thử lại." };
        }

        return await completeSignIn(token, cleanStore, { via: "password", username: cleanUser });
      } catch (e: unknown) {
        const msg = (e as Error)?.message || "Lỗi kết nối máy chủ";
        return { success: false, error: msg };
      }
    },
    [completeSignIn]
  );

  const signInWithChamCong = useCallback(
    async (method: ChamCongMethod, inputStoreCode?: string): Promise<ChamCongLoginResult> => {
      const host = typeof window !== "undefined" ? window.location.host : undefined;
      const chosenStore = inputStoreCode?.trim().toUpperCase() || undefined;
      try {
        // Bước chọn cửa hàng: dùng lại phiên Chấm Công trong bộ nhớ thay vì mở lại popup.
        let idToken = chosenStore ? await getCurrentChamCongIdToken() : null;
        if (!idToken) idToken = await authenticateChamCong(method);

        const call = httpsCallable<{ idToken: string; storeCode?: string }, unknown>(functions, "chamCongSignIn");
        const res = await call(chosenStore ? { idToken, storeCode: chosenStore } : { idToken });
        const parsed = parseChamCongSignInResponse(res.data);
        if (!parsed) {
          await signOutChamCong();
          return { success: false, error: "Máy chủ trả về phản hồi không hợp lệ. Vui lòng thử lại." };
        }
        if (parsed.status === "CHOOSE_STORE") {
          return { success: false, chooseStore: parsed.stores };
        }

        await signOutChamCong();
        const result = await completeSignIn(parsed.customToken, parsed.storeCode, {
          via: "chamcong",
          isNewAccount: parsed.isNewAccount,
        });
        if (result.success) return { success: true, mustChangePassword: result.mustChangePassword };
        return { success: false, error: result.error || "Đăng nhập thất bại." };
      } catch (err: unknown) {
        await signOutChamCong();
        return { success: false, error: mapChamCongError(err, host) };
      }
    },
    [completeSignIn]
  );

  const logout = useCallback(async () => {
    try {
      await signOut(auth);
    } catch {}
    setUser(null);
  }, []);

  const refreshUser = useCallback(async () => {
    if (auth.currentUser) {
      const p = await loadUserProfile(auth.currentUser, storeCode);
      if (p) setUser(p);
    }
  }, [loadUserProfile, storeCode]);

  const changeCurrentPassword = useCallback(
    async (newPassword: string): Promise<{ success: boolean; error?: string }> => {
      if (!auth.currentUser || !user) {
        return { success: false, error: "Bạn chưa đăng nhập" };
      }

      if (newPassword.length < 6) {
        return { success: false, error: "Mật khẩu mới phải có tối thiểu 6 ký tự" };
      }

      const hasLetter = /[a-zA-Z]/.test(newPassword);
      const hasDigit = /[0-9]/.test(newPassword);
      if (!hasLetter || !hasDigit) {
        return { success: false, error: "Mật khẩu mới phải bao gồm cả chữ cái và chữ số" };
      }

      try {
        await updatePassword(auth.currentUser, newPassword);

        // Cập nhật cờ mustChangePassword = false
        const targetStore = user.storeCode || storeCode || "TRAM01";
        await update(ref(db, `stores/${targetStore}/users/${user.uid}`), {
          mustChangePassword: false,
          lastPasswordChangedAt: Date.now(),
        }).catch(() => {});

        // Ghi Audit log
        const logId = `LOG_${Date.now()}_${Math.floor(Math.random() * 1000)}`;
        await set(ref(db, `stores/${targetStore}/audit_logs/${logId}`), {
          action: "CHANGE_PASSWORD_MANDATORY_SUCCESS",
          targetType: "USER",
          targetId: user.uid,
          username: user.username,
          userFullName: user.fullName,
          userRole: user.roleId,
          details: `Đổi mật khẩu thành công cho tài khoản @${user.username}`,
          timestamp: Date.now(),
        }).catch(() => {});

        setUser((prev) => (prev ? { ...prev, mustChangePassword: false } : null));

        return { success: true };
      } catch (err: unknown) {
        const code = (err as { code?: string })?.code;
        if (code === "auth/requires-recent-login") {
          return {
            success: false,
            error: "Phiên làm việc đã hết hạn. Vui lòng đăng xuất và đăng nhập lại để đổi mật khẩu.",
          };
        }
        return { success: false, error: (err as Error)?.message || "Không thể cập nhật mật khẩu" };
      }
    },
    [user, storeCode]
  );

  return (
    <AuthContext.Provider
      value={{
        user,
        loading,
        storeCode,
        setStoreCode,
        login,
        signInWithChamCong,
        logout,
        refreshUser,
        changeCurrentPassword,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  return useContext(AuthContext);
}
