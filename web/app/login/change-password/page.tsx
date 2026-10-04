"use client";
import React, { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/lib/auth";
import { KeyRound, Eye, EyeOff, AlertCircle, CheckCircle2, LogOut } from "lucide-react";

export default function ChangePasswordPage() {
  const { user, loading, changeCurrentPassword, logout } = useAuth();
  const router = useRouter();

  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [showConfirmPassword, setShowConfirmPassword] = useState(false);
  const [error, setError] = useState("");
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (!loading) {
      if (!user) {
        router.replace("/login");
      } else if (!user.mustChangePassword) {
        // Nếu không cần đổi mật khẩu bắt buộc thì cho về dashboard
        router.replace("/dashboard");
      }
    }
  }, [user, loading, router]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");

    if (!newPassword.trim()) {
      setError("Vui lòng nhập mật khẩu mới");
      return;
    }
    if (newPassword.length < 6) {
      setError("Mật khẩu mới phải có tối thiểu 6 ký tự");
      return;
    }
    const hasLetter = /[a-zA-Z]/.test(newPassword);
    const hasDigit = /[0-9]/.test(newPassword);
    if (!hasLetter || !hasDigit) {
      setError("Mật khẩu mới phải bao gồm cả chữ cái và chữ số");
      return;
    }
    if (newPassword !== confirmPassword) {
      setError("Mật khẩu xác nhận không khớp");
      return;
    }

    setSubmitting(true);
    const res = await changeCurrentPassword(newPassword.trim());
    if (res.success) {
      router.replace("/dashboard");
    } else {
      setError(res.error || "Không thể cập nhật mật khẩu");
    }
    setSubmitting(false);
  };

  const handleLogout = async () => {
    await logout();
    router.replace("/login");
  };

  if (loading) {
    return (
      <div style={{ display: "flex", alignItems: "center", justifyContent: "center", height: "100vh" }}>
        <div className="spinner" />
      </div>
    );
  }

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
      <div
        style={{
          width: "100%",
          maxWidth: "440px",
          borderRadius: "22px",
          padding: "36px 32px",
          background: "#FFFFFF",
          border: "1.5px solid #E6DEC8",
          boxShadow: "0 16px 40px rgba(126, 41, 48, 0.08)",
          position: "relative",
          zIndex: 1,
        }}
      >
        {/* Header */}
        <div style={{ textAlign: "center", marginBottom: "24px" }}>
          <div
            style={{
              width: "60px",
              height: "60px",
              borderRadius: "16px",
              background: "rgba(126, 41, 48, 0.08)",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              margin: "0 auto 14px",
            }}
          >
            <KeyRound size={28} color="#7E2930" />
          </div>
          <h1
            style={{
              fontSize: "22px",
              fontWeight: "800",
              color: "#7E2930",
              marginBottom: "4px",
            }}
          >
            Đổi Mật Khẩu Bắt Buộc
          </h1>
          <p style={{ color: "#5D5B63", fontSize: "13px", lineHeight: "1.5" }}>
            Tài khoản <strong style={{ color: "#1C1A2D" }}>@{user?.username}</strong> đăng nhập lần đầu
            hoặc vừa được đặt lại mật khẩu. Vui lòng thiết lập mật khẩu mới an toàn để tiếp tục.
          </p>
        </div>

        <form onSubmit={handleSubmit} style={{ display: "flex", flexDirection: "column", gap: "16px" }}>
          {/* New Password */}
          <div>
            <label
              style={{
                display: "block",
                fontSize: "13px",
                fontWeight: "700",
                color: "#1C1A2D",
                marginBottom: "6px",
              }}
            >
              Mật khẩu mới *
            </label>
            <div style={{ position: "relative" }}>
              <input
                type={showPassword ? "text" : "password"}
                className="input-field"
                placeholder="Tối thiểu 6 ký tự, gồm cả chữ và số"
                value={newPassword}
                onChange={(e) => setNewPassword(e.target.value)}
                disabled={submitting}
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
                }}
              >
                {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
              </button>
            </div>
          </div>

          {/* Confirm Password */}
          <div>
            <label
              style={{
                display: "block",
                fontSize: "13px",
                fontWeight: "700",
                color: "#1C1A2D",
                marginBottom: "6px",
              }}
            >
              Xác nhận mật khẩu mới *
            </label>
            <div style={{ position: "relative" }}>
              <input
                type={showConfirmPassword ? "text" : "password"}
                className="input-field"
                placeholder="Nhập lại mật khẩu mới"
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                disabled={submitting}
                style={{ paddingRight: "44px" }}
              />
              <button
                type="button"
                onClick={() => setShowConfirmPassword(!showConfirmPassword)}
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
                }}
              >
                {showConfirmPassword ? <EyeOff size={18} /> : <Eye size={18} />}
              </button>
            </div>
          </div>

          {/* Requirements hint */}
          <div
            style={{
              padding: "10px 12px",
              background: "#FAF7F2",
              border: "1px solid #E6DEC8",
              borderRadius: "10px",
              fontSize: "12px",
              color: "#5D5B63",
              display: "flex",
              flexDirection: "column",
              gap: "4px",
            }}
          >
            <div style={{ display: "flex", alignItems: "center", gap: "6px" }}>
              <CheckCircle2
                size={14}
                color={newPassword.length >= 6 ? "#10B981" : "#8B8FA8"}
              />
              <span>Tối thiểu 6 ký tự</span>
            </div>
            <div style={{ display: "flex", alignItems: "center", gap: "6px" }}>
              <CheckCircle2
                size={14}
                color={/[a-zA-Z]/.test(newPassword) && /[0-9]/.test(newPassword) ? "#10B981" : "#8B8FA8"}
              />
              <span>Gồm cả chữ cái và chữ số</span>
            </div>
            <div style={{ display: "flex", alignItems: "center", gap: "6px" }}>
              <CheckCircle2
                size={14}
                color={newPassword && newPassword === confirmPassword ? "#10B981" : "#8B8FA8"}
              />
              <span>Mật khẩu xác nhận trùng khớp</span>
            </div>
          </div>

          {/* Error */}
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
              <div>{error}</div>
            </div>
          )}

          {/* Submit */}
          <button
            type="submit"
            className="btn-primary"
            disabled={submitting}
            style={{
              width: "100%",
              justifyContent: "center",
              padding: "13px",
              fontSize: "15px",
              marginTop: "4px",
              opacity: submitting ? 0.7 : 1,
            }}
          >
            {submitting ? (
              <>
                <div className="spinner" style={{ width: "16px", height: "16px" }} />
                Đang lưu mật khẩu...
              </>
            ) : (
              "Lưu mật khẩu & Đăng nhập"
            )}
          </button>
        </form>

        {/* Logout button */}
        <div style={{ marginTop: "20px", textAlign: "center" }}>
          <button
            onClick={handleLogout}
            style={{
              background: "none",
              border: "none",
              color: "#5D5B63",
              fontSize: "13px",
              cursor: "pointer",
              display: "inline-flex",
              alignItems: "center",
              gap: "6px",
            }}
          >
            <LogOut size={14} />
            Đăng xuất hoặc đổi tài khoản khác
          </button>
        </div>
      </div>
    </div>
  );
}
