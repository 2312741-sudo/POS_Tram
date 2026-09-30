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
      // 1. Hỗ trợ tài khoản Quản trị mặc định / Demo
      if (
        (username.toLowerCase() === "admin" && password === "123456") ||
        (username.toLowerCase() === "manager" && password === "123456") ||
        (username.toLowerCase() === "chutram" && password === "123456")
      ) {
        const foundUser = { 
          id: username, 
          fullName: username.toLowerCase() === "admin" ? "Chủ Quán (Admin)" : "Quản Lý Cửa Hàng", 
          username: username, 
          role: "MANAGER" 
        };
        setUser(foundUser);
        localStorage.setItem("tram_admin_user", JSON.stringify(foundUser));
        return { success: true };
      }

      // 2. Đọc trực tiếp node của user từ Firebase Database
      const userRef = ref(db, `users/${username}`);
      const snapshot = await get(userRef);
      
      if (!snapshot.exists()) {
        return { success: false, error: "Sai tài khoản hoặc mật khẩu" };
      }
      
      const data = snapshot.val();
      const role = (data.role || "").toUpperCase();
      const isManagerOrOwner = ["MANAGER", "OWNER", "ADMIN", "ROLE_OWNER", "ROLE_MANAGER"].includes(role);
      
      if (data.password === password && isManagerOrOwner) {
        const foundUser = { 
          id: username, 
          fullName: data.fullName || username, 
          username: data.username || username, 
          role: data.role 
        };
        setUser(foundUser);
        localStorage.setItem("tram_admin_user", JSON.stringify(foundUser));
        return { success: true };
      }
      
      return { success: false, error: "Sai mật khẩu hoặc không có quyền Quản lý/Chủ quán" };
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
