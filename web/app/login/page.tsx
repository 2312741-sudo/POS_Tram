"use client";
import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/lib/auth";
import { Eye, EyeOff, LogIn, AlertCircle, Info } from "lucide-react";

export default function LoginPage() {
  const { login, user, loading } = useAuth();
  const router = useRouter();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState("");
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (!loading && user) {
      router.replace("/dashboard");
    }
  }, [user, loading, router]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    if (!username.trim() || !password.trim()) {
      setError("Vui lòng nhập đầy đủ tài khoản và mật khẩu");
      return;
    }
    setSubmitting(true);
    const result = await login(username.trim(), password);
    if (result.success) {
      router.replace("/dashboard");
    } else {
      setError(result.error || "Đăng nhập thất bại");
    }
    setSubmitting(false);
  };

  return (
    <div
      style={{
        minHeight: "100vh",
        background: "linear-gradient(135deg, #F8F4EE 0%, #F6EFDF 50%, #F8F4EE 100%)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        padding: "24px",
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
          maxWidth: "430px",
          borderRadius: "22px",
          padding: "40px",
          background: "#FFFFFF",
          border: "1.5px solid #E6DEC8",
          boxShadow: "0 16px 40px rgba(126, 41, 48, 0.08)",
          position: "relative",
          zIndex: 1,
        }}
      >
        {/* Logo/Title */}
        <div style={{ textAlign: "center", marginBottom: "32px" }}>
          <div
            style={{
              width: "68px",
              height: "68px",
              borderRadius: "18px",
              background: "#FFFFFF",
              border: "1.5px solid #E6DEC8",
              padding: "4px",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              margin: "0 auto 16px",
              boxShadow: "0 6px 16px rgba(126, 41, 48, 0.15)",
              overflow: "hidden",
            }}
          >
            <img src="/logo.jpg" alt="Logo" style={{ width: "100%", height: "100%", objectFit: "cover", borderRadius: "14px" }} />
          </div>
          <h1
            style={{
              fontSize: "24px",
              fontWeight: "800",
              color: "#7E2930",
              letterSpacing: "0.02em",
              marginBottom: "4px",
            }}
          >
            POS TRẠM
          </h1>
          <p style={{ color: "#5D5B63", fontSize: "14px", fontWeight: "500" }}>
            Hệ thống Quản lý Vận hành & Bán hàng
          </p>
        </div>

        <form onSubmit={handleSubmit} style={{ display: "flex", flexDirection: "column", gap: "16px" }}>
          <div>
            <label
              style={{ display: "block", fontSize: "13px", fontWeight: "700", color: "#1C1A2D", marginBottom: "6px" }}
            >
              Tài khoản
            </label>
            <input
              type="text"
              className="input-field"
              placeholder="Nhập tên tài khoản (vd: admin, quanly)"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              disabled={submitting}
              autoComplete="username"
            />
          </div>

          <div>
            <label
              style={{ display: "block", fontSize: "13px", fontWeight: "700", color: "#1C1A2D", marginBottom: "6px" }}
            >
              Mật khẩu
            </label>
            <div style={{ position: "relative" }}>
              <input
                type={showPassword ? "text" : "password"}
                className="input-field"
                placeholder="Nhập mật khẩu (vd: 123456)"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                disabled={submitting}
                autoComplete="current-password"
                style={{ paddingRight: "44px" }}
              />
              <button
                type="button"
                onClick={() => setShowPassword(!showPassword)}
                style={{
                  position: "absolute",
                  right: "12px",
                  top: "50%",
                  transform: "translateY(-50%)",
                  background: "none",
                  border: "none",
                  color: "#5D5B63",
                  cursor: "pointer",
                  padding: "4px",
                  display: "flex",
                  alignItems: "center",
                }}
              >
                {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
              </button>
            </div>
          </div>

          {error && (
            <div
              style={{
                display: "flex",
                alignItems: "flex-start",
                gap: "8px",
                background: "rgba(180, 35, 44, 0.08)",
                border: "1px solid rgba(180, 35, 44, 0.25)",
                borderRadius: "10px",
                padding: "12px",
                color: "#B4232C",
                fontSize: "13px",
              }}
            >
              <AlertCircle size={16} style={{ flexShrink: 0, marginTop: "2px" }} />
              {error}
            </div>
          )}

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
              opacity: submitting ? 0.7 : 1,
            }}
          >
            {submitting ? (
              <>
                <div className="spinner" style={{ width: "16px", height: "16px" }} />
                Đang đăng nhập...
              </>
            ) : (
              <>
                <LogIn size={18} />
                Đăng nhập hệ thống
              </>
            )}
          </button>
        </form>

        {/* Quick hint box */}
        <div
          style={{
            marginTop: "24px",
            padding: "12px 14px",
            background: "#FAF7F2",
            border: "1px solid #E6DEC8",
            borderRadius: "10px",
            display: "flex",
            alignItems: "flex-start",
            gap: "8px",
            fontSize: "12px",
            color: "#5D5B63",
          }}
        >
          <Info size={16} color="#7E2930" style={{ flexShrink: 0, marginTop: "1px" }} />
          <div>
            Tài khoản mẫu: <strong>admin</strong> | Mật khẩu: <strong>123456</strong>
            <br />
            Phân quyền: <span style={{ color: "#7E2930", fontWeight: "700" }}>CHỦ QUÁN / QUẢN LÝ CA</span>
          </div>
        </div>
      </div>
    </div>
  );
}
