"use client";
import React, { useState, useEffect } from "react";
import Image from "next/image";
import { useRouter } from "next/navigation";
import { useAuth } from "@/lib/auth";
import { Eye, EyeOff, LogIn, AlertCircle, Store, User as UserIcon, Lock } from "lucide-react";

export default function LoginPage() {
  const { login, user, loading, storeCode: defaultStoreCode } = useAuth();
  const router = useRouter();

  const [storeCode, setStoreCode] = useState(defaultStoreCode || "TRAM01");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState("");
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (!loading && user) {
      if (user.mustChangePassword) {
        router.replace("/login/change-password");
      } else {
        router.replace("/dashboard");
      }
    }
  }, [user, loading, router]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");

    const cleanStore = storeCode.trim().toUpperCase();
    const cleanUser = username.trim().toLowerCase();
    const cleanPass = password.trim();

    if (!cleanStore) {
      setError("Vui lòng nhập mã chi nhánh cửa hàng (ví dụ: TRAM01)");
      return;
    }
    if (!cleanUser) {
      setError("Vui lòng nhập tên tài khoản");
      return;
    }
    if (!cleanPass) {
      setError("Vui lòng nhập mật khẩu");
      return;
    }

    setSubmitting(true);
    const result = await login(cleanStore, cleanUser, cleanPass);
    if (result.success) {
      if (result.mustChangePassword) {
        router.replace("/login/change-password");
      } else {
        router.replace("/dashboard");
      }
    } else {
      setError(result.error || "Đăng nhập thất bại. Vui lòng kiểm tra lại thông tin.");
    }
    setSubmitting(false);
  };

  return (
    <div
      style={{
        minHeight: "100vh",
        background: "linear-gradient(135deg, var(--bg) 0%, var(--surface-muted) 50%, var(--bg) 100%)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        padding: "24px 16px",
        position: "relative",
        overflow: "hidden",
      }}
    >
      {/* Background decoration */}
      <div
        style={{
          position: "absolute",
          top: "-150px",
          left: "-150px",
          width: "500px",
          height: "500px",
          borderRadius: "50%",
          background: "radial-gradient(circle, rgba(126,41,48,0.08) 0%, transparent 70%)",
          pointerEvents: "none",
        }}
      />
      <div
        style={{
          position: "absolute",
          bottom: "-150px",
          right: "-150px",
          width: "500px",
          height: "500px",
          borderRadius: "50%",
          background: "radial-gradient(circle, rgba(217,119,6,0.08) 0%, transparent 70%)",
          pointerEvents: "none",
        }}
      />

      <div
        style={{
          width: "100%",
          maxWidth: "440px",
          borderRadius: "22px",
          padding: "clamp(24px, 6vw, 40px)",
          background: "var(--surface)",
          border: "1.5px solid var(--border)",
          boxShadow: "0 16px 40px rgba(126, 41, 48, 0.08)",
          position: "relative",
          zIndex: 1,
        }}
      >
        {/* Logo / Header */}
        <div style={{ textAlign: "center", marginBottom: "28px" }}>
          <div
            style={{
              width: "68px",
              height: "68px",
              borderRadius: "18px",
              background: "var(--surface)",
              border: "1.5px solid var(--border)",
              padding: "4px",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              margin: "0 auto 16px",
              boxShadow: "0 6px 16px rgba(126, 41, 48, 0.15)",
              overflow: "hidden",
              position: "relative",
            }}
          >
            <Image
              src="/logo.jpg"
              alt="Logo POS Trạm"
              width={60}
              height={60}
              style={{ objectFit: "cover", borderRadius: "14px" }}
              priority
            />
          </div>
          <h1
            style={{
              fontSize: "24px",
              fontWeight: "800",
              color: "var(--primary)",
              letterSpacing: "0.02em",
              marginBottom: "4px",
            }}
          >
            POS TRẠM
          </h1>
          <p style={{ color: "var(--subtext)", fontSize: "14px", fontWeight: "500" }}>
            Hệ thống Quản lý Vận hành & Bán hàng
          </p>
        </div>

        <form onSubmit={handleSubmit} noValidate aria-busy={submitting} style={{ display: "flex", flexDirection: "column", gap: "16px" }}>
          {/* Store Code Field */}
          <div>
            <label
              htmlFor="login-store"
              style={{
                display: "flex",
                alignItems: "center",
                gap: "6px",
                fontSize: "13px",
                fontWeight: "700",
                color: "var(--text)",
                marginBottom: "6px",
              }}
            >
              <Store size={15} style={{ color: "var(--primary)" }} aria-hidden="true" />
              Mã cửa hàng / Chi nhánh
            </label>
            <input
              id="login-store"
              type="text"
              className="input-field"
              placeholder="Ví dụ: TRAM01"
              value={storeCode}
              onChange={(e) => setStoreCode(e.target.value.toUpperCase())}
              disabled={submitting}
              autoComplete="organization"
              style={{ textTransform: "uppercase", fontWeight: "600", letterSpacing: "0.05em" }}
            />
          </div>

          {/* Username Field */}
          <div>
            <label
              htmlFor="login-username"
              style={{
                display: "flex",
                alignItems: "center",
                gap: "6px",
                fontSize: "13px",
                fontWeight: "700",
                color: "var(--text)",
                marginBottom: "6px",
              }}
            >
              <UserIcon size={15} style={{ color: "var(--primary)" }} aria-hidden="true" />
              Tên tài khoản
            </label>
            <input
              id="login-username"
              type="text"
              className="input-field"
              autoCapitalize="none"
              spellCheck={false}
              placeholder="VD: thungan1, quanly"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              disabled={submitting}
              autoComplete="username"
            />
          </div>

          {/* Password Field */}
          <div>
            <label
              htmlFor="login-password"
              style={{
                display: "flex",
                alignItems: "center",
                gap: "6px",
                fontSize: "13px",
                fontWeight: "700",
                color: "var(--text)",
                marginBottom: "6px",
              }}
            >
              <Lock size={15} style={{ color: "var(--primary)" }} aria-hidden="true" />
              Mật khẩu
            </label>
            <div style={{ position: "relative" }}>
              <input
                id="login-password"
                type={showPassword ? "text" : "password"}
                className="input-field"
                placeholder="Nhập mật khẩu"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                disabled={submitting}
                autoComplete="current-password"
                style={{ paddingRight: "44px" }}
              />
              <button
                type="button"
                onClick={() => setShowPassword(!showPassword)}
                aria-label={showPassword ? "Ẩn mật khẩu" : "Hiện mật khẩu"}
                aria-pressed={showPassword}
                style={{
                  position: "absolute",
                  right: "12px",
                  top: "50%",
                  transform: "translateY(-50%)",
                  background: "none",
                  border: "none",
                  color: "var(--subtext)",
                  cursor: "pointer",
                  padding: "6px",
                  borderRadius: "8px",
                  display: "flex",
                  alignItems: "center",
                }}
              >
                {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
              </button>
            </div>
          </div>

          {/* Error Banner */}
          {error && (
            <div
              role="alert"
              style={{
                display: "flex",
                alignItems: "flex-start",
                gap: "10px",
                background: "var(--danger-bg)",
                border: "1px solid color-mix(in srgb, var(--danger) 30%, transparent)",
                borderRadius: "10px",
                padding: "12px",
                color: "var(--danger)",
                fontSize: "13px",
                lineHeight: "1.4",
              }}
            >
              <AlertCircle size={18} style={{ flexShrink: 0, marginTop: "1px" }} />
              <div>{error}</div>
            </div>
          )}

          {/* Submit Button */}
          <button
            type="submit"
            className="btn-primary"
            disabled={submitting}
            style={{
              width: "100%",
              justifyContent: "center",
              padding: "13px",
              fontSize: "15px",
              marginTop: "8px",
              minHeight: "48px",
              opacity: submitting ? 0.7 : 1,
            }}
          >
            {submitting ? (
              <>
                <div
                  className="spinner"
                  aria-hidden="true"
                  style={{ width: "16px", height: "16px", borderWidth: "2px", borderColor: "rgba(255,255,255,0.35)", borderTopColor: "var(--surface)" }}
                />
                Đang xác thực...
              </>
            ) : (
              <>
                <LogIn size={18} />
                Đăng nhập hệ thống
              </>
            )}
          </button>
        </form>

        <div
          style={{
            marginTop: "24px",
            textAlign: "center",
            fontSize: "12px",
            color: "var(--muted)",
          }}
        >
          Hệ thống bảo vệ đa tầng &bull; Khóa tạm sau 5 lần nhập sai liên tiếp
        </div>
      </div>
    </div>
  );
}
