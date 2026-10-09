/**
 * Firebase app phụ "chamcong" (dự án chamcongtram) — chỉ dùng để lấy ID token Chấm Công,
 * sau đó máy chủ POS (callable chamCongSignIn / linkChamCongStore) đổi sang phiên POS.
 *
 * Auth dùng inMemoryPersistence nên phiên Chấm Công không bao giờ lưu lại trong trình duyệt.
 */
import { initializeApp, getApps, type FirebaseApp } from "firebase/app";
import {
  initializeAuth,
  getAuth,
  inMemoryPersistence,
  browserPopupRedirectResolver,
  GoogleAuthProvider,
  OAuthProvider,
  signInWithPopup,
  signInWithEmailAndPassword,
  signOut,
  type Auth,
} from "firebase/auth";
import { hasChamCongConfig, type ChamCongMethod } from "./chamcong";

const APP_NAME = "chamcong";

// Next.js chỉ inline biến NEXT_PUBLIC_* khi truy cập trực tiếp theo tên.
const chamCongConfig = {
  apiKey: process.env.NEXT_PUBLIC_CHAMCONG_API_KEY || "",
  authDomain: process.env.NEXT_PUBLIC_CHAMCONG_AUTH_DOMAIN || "",
  projectId: process.env.NEXT_PUBLIC_CHAMCONG_PROJECT_ID || "",
  appId: process.env.NEXT_PUBLIC_CHAMCONG_APP_ID || "",
};

export function isChamCongConfigured(): boolean {
  return hasChamCongConfig(chamCongConfig);
}

let cachedAuth: Auth | null = null;

export function getChamCongAuth(): Auth {
  if (cachedAuth) return cachedAuth;
  if (!isChamCongConfigured()) {
    throw new Error("Chưa cấu hình kết nối Chấm Công Trạm (NEXT_PUBLIC_CHAMCONG_*).");
  }
  const existing = getApps().find((a) => a.name === APP_NAME);
  const app: FirebaseApp = existing ?? initializeApp(chamCongConfig, APP_NAME);
  try {
    cachedAuth = initializeAuth(app, {
      persistence: inMemoryPersistence,
      popupRedirectResolver: browserPopupRedirectResolver,
    });
  } catch {
    // Đã khởi tạo trước đó (HMR) — dùng lại instance hiện có.
    cachedAuth = getAuth(app);
  }
  return cachedAuth;
}

/** Đăng nhập vào Chấm Công Trạm và trả về ID token (phiên chỉ nằm trong bộ nhớ). */
export async function authenticateChamCong(method: ChamCongMethod): Promise<string> {
  const auth = getChamCongAuth();
  let cred;
  if (method === "google") {
    const provider = new GoogleAuthProvider();
    provider.addScope("email");
    provider.addScope("profile");
    provider.setCustomParameters({ prompt: "select_account" });
    cred = await signInWithPopup(auth, provider);
  } else if (method === "apple") {
    const provider = new OAuthProvider("apple.com");
    provider.addScope("email");
    provider.addScope("name");
    cred = await signInWithPopup(auth, provider);
  } else {
    cred = await signInWithEmailAndPassword(auth, method.email.trim().toLowerCase(), method.password);
  }
  return cred.user.getIdToken();
}

/** ID token của phiên Chấm Công còn trong bộ nhớ (dùng cho bước chọn cửa hàng), hoặc null. */
export async function getCurrentChamCongIdToken(): Promise<string | null> {
  if (!isChamCongConfigured()) return null;
  const user = getChamCongAuth().currentUser;
  if (!user) return null;
  try {
    return await user.getIdToken();
  } catch {
    return null;
  }
}

export async function signOutChamCong(): Promise<void> {
  if (!cachedAuth) return;
  try {
    await signOut(cachedAuth);
  } catch {}
}
