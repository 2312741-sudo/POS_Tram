"use client";
import React, { createContext, useContext, useState, useEffect, useCallback } from "react";
import { db } from "./firebase";
import { ref, get } from "firebase/database";

interface User {
  id: string;
  fullName: string;
  username: string;
  role: string;
}

interface AuthContextType {
  user: User | null;
  loading: boolean;
  login: (username: string, password: string) => Promise<{ success: boolean; error?: string }>;
  logout: () => void;
}

const AuthContext = createContext<AuthContextType>({
  user: null,
  loading: true,
  login: async () => ({ success: false }),
  logout: () => {},
});

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    try {
      const stored = localStorage.getItem("tram_admin_user");
      if (stored) {
        setUser(JSON.parse(stored));
      }
    } catch {}
    setLoading(false);
  }, []);

  const login = useCallback(async (username: string, password: string) => {
    try {
      const cleanUser = username.trim().toLowerCase();
      const cleanPass = password.trim();

      // 1. Hỗ trợ tài khoản Quản trị mặc định / Demo
      if (
        (cleanUser === "admin" && (cleanPass === "admin" || cleanPass === "123456")) ||
        (cleanUser === "manager" && (cleanPass === "123" || cleanPass === "123456")) ||
        (cleanUser === "chutram" && (cleanPass === "123456" || cleanPass === "admin"))
      ) {
        const foundUser = { 
          id: cleanUser, 
          fullName: cleanUser === "admin" ? "Chủ Quán (Admin)" : "Quản Lý Cửa Hàng", 
          username: cleanUser, 
          role: "ROLE_OWNER" 
        };
        setUser(foundUser);
        localStorage.setItem("tram_admin_user", JSON.stringify(foundUser));
        return { success: true };
      }

      // 2. Tìm kiếm trong Firebase Database
      let userData: any = null;
      let matchedStoreCode = "";

      // 2a. Kiểm tra root node: users/{username}
      const rootUserRef = ref(db, `users/${cleanUser}`);
      const rootSnap = await get(rootUserRef);
      if (rootSnap.exists()) {
        userData = rootSnap.val();
      } else {
        // Thử tìm với username nguyên bản (nếu có hoa thường)
        const rawUserRef = ref(db, `users/${username.trim()}`);
        const rawSnap = await get(rawUserRef);
        if (rawSnap.exists()) {
          userData = rawSnap.val();
        }
      }

      // 2b. Nếu không thấy ở root, tìm trong từng chi nhánh: stores/{code}/users/{username}
      if (!userData) {
        const storesRef = ref(db, "stores");
        const storesSnap = await get(storesRef);
        if (storesSnap.exists()) {
          const storesData = storesSnap.val();
          for (const [storeCode, sVal] of Object.entries<any>(storesData)) {
            if (sVal.users) {
              for (const [uKey, uVal] of Object.entries<any>(sVal.users)) {
                if (uKey.toLowerCase() === cleanUser || (uVal.username && uVal.username.toLowerCase() === cleanUser)) {
                  userData = uVal;
                  matchedStoreCode = storeCode;
                  break;
                }
              }
            }
            if (userData) break;
          }
        }
      }

      if (!userData) {
        return { success: false, error: "Sai tài khoản hoặc mật khẩu" };
      }

      if (userData.isActive === false) {
        return { success: false, error: "Tài khoản này đã bị tạm khóa, vui lòng liên hệ Chủ quán" };
      }

      if (userData.password !== cleanPass && userData.password !== password) {
        return { success: false, error: "Sai mật khẩu" };
      }

      const roleStr = (userData.roleId || userData.role || "").toUpperCase();
      const isRootOwner = userData.isRootOwner === true;
      const isManagerOrOwner = isRootOwner || [
        "OWNER", "ADMIN", "MANAGER", 
        "ROLE_OWNER", "ROLE_MANAGER", "ROLE_ADMIN", 
        "MANAGER_1", "MANAGER_2"
      ].some(r => roleStr.includes(r));

      if (!isManagerOrOwner) {
        return { 
          success: false, 
          error: "Tài khoản của bạn (" + (userData.roleId || userData.role) + ") không có quyền đăng nhập Web Quản trị. Chỉ dành cho Chủ quán hoặc Quản lý." 
        };
      }

      const foundUser = { 
        id: cleanUser, 
        fullName: userData.fullName || cleanUser, 
        username: userData.username || cleanUser, 
        role: userData.roleId || userData.role || "ROLE_MANAGER",
        storeCode: matchedStoreCode || userData.storeCode || "TRAM01",
      };
      setUser(foundUser);
      localStorage.setItem("tram_admin_user", JSON.stringify(foundUser));
      return { success: true };
    } catch (e: any) {
      console.error("Login error:", e);
      return { success: false, error: e.message || "Lỗi kết nối hoặc không có quyền truy cập DB" };
    }
  }, []);

  const logout = useCallback(() => {
    setUser(null);
    localStorage.removeItem("tram_admin_user");
  }, []);

  return (
    <AuthContext.Provider value={{ user, loading, login, logout }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  return useContext(AuthContext);
}
