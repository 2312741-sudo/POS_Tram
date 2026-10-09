"use client";
import { useEffect, useRef, useState } from "react";
import { AlertCircle, ArrowLeft, Building2, Mail, X } from "lucide-react";
import type { ChamCongMethod } from "@/lib/chamcong";

export interface ChamCongPickOption {
  id: string;
  label: string;
  sublabel?: string;
}

/** Kết quả một bước: lỗi, cần chọn từ danh sách, hoặc hoàn tất (void). */
export type ChamCongStepResult = { error: string } | { options: ChamCongPickOption[] } | void;

interface Props {
  title: string;
  description?: string;
  pickTitle: string;
  /** Gọi khi người dùng chọn Google / Apple / Email. */
  onMethod: (method: ChamCongMethod) => Promise<ChamCongStepResult>;
  /** Gọi khi người dùng chọn một mục trong danh sách (bước chọn cửa hàng). */
  onPick: (id: string) => Promise<ChamCongStepResult>;
  onClose: () => void;
  footer?: React.ReactNode;
}

type Busy = null | "google" | "apple" | "email" | string;

/**
 * Hộp thoại đăng nhập Chấm Công Trạm (Google / Apple / Email) + bước chọn cửa hàng.
 * Dùng chung cho trang đăng nhập POS và thẻ liên kết trong Quản lý chi nhánh.
 */
export default function ChamCongSignInDialog({ title, description, pickTitle, onMethod, onPick, onClose, footer }: Props) {
  const [step, setStep] = useState<"method" | "email" | "pick">("method");
  const [options, setOptions] = useState<ChamCongPickOption[]>([]);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState<Busy>(null);
  const [error, setError] = useState("");
  const dialogRef = useRef<HTMLDivElement>(null);

  const isBusy = busy !== null;

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape" && !isBusy) onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [isBusy, onClose]);

  useEffect(() => {
    const first = dialogRef.current?.querySelector<HTMLElement>("[data-autofocus]");
    first?.focus();
  }, [step]);

  const handle = async (key: Busy, fn: () => Promise<ChamCongStepResult>) => {
    setBusy(key);
    setError("");
    try {
      const res = await fn();
      if (res && "error" in res) {
        setError(res.error);
      } else if (res && "options" in res) {
        setOptions(res.options);
        setStep("pick");
      }
    } finally {
      setBusy(null);
    }
  };

  const submitEmail = (e: React.FormEvent) => {
    e.preventDefault();
    const cleanEmail = email.trim();
    if (!cleanEmail || !password) {
      setError("Vui lòng nhập email và mật khẩu Chấm Công.");
      return;
    }
    void handle("email", () => onMethod({ email: cleanEmail, password }));
  };

  const providerBtn: React.CSSProperties = {
    width: "100%",
    justifyContent: "center",
    minHeight: "46px",
    fontSize: "14px",
    gap: "10px",
  };

  const spinner = (
    <span
      className="spinner"
      aria-hidden="true"
      style={{ width: "16px", height: "16px", borderWidth: "2px" }}
    />
  );

  return (
    <div className="modal-overlay" style={{ zIndex: 1200 }} onClick={isBusy ? undefined : onClose}>
      <div
        ref={dialogRef}
        className="modal-content"
        role="dialog"
        aria-modal="true"
        aria-labelledby="chamcong-dialog-title"
        aria-describedby={description ? "chamcong-dialog-desc" : undefined}
        aria-busy={isBusy}
        style={{ maxWidth: "400px" }}
        onClick={(e) => e.stopPropagation()}
      >
        <div style={{ padding: "20px 24px 0", display: "flex", alignItems: "flex-start", justifyContent: "space-between", gap: "12px" }}>
          <div style={{ display: "flex", alignItems: "flex-start", gap: "8px" }}>
            {step !== "method" && (
              <button
                type="button"
                aria-label="Quay lại"
                disabled={isBusy}
                onClick={() => {
                  setStep("method");
                  setError("");
                }}
                style={{ background: "none", border: "none", color: "var(--subtext)", cursor: "pointer", padding: "2px" }}
              >
                <ArrowLeft size={18} />
              </button>
            )}
            <div>
              <h2 id="chamcong-dialog-title" style={{ fontSize: "17px", fontWeight: 800, color: "var(--text)" }}>
                {step === "pick" ? pickTitle : title}
              </h2>
              {description && step !== "pick" && (
                <p id="chamcong-dialog-desc" style={{ fontSize: "12.5px", color: "var(--subtext)", marginTop: "4px", lineHeight: 1.45 }}>
                  {description}
                </p>
              )}
            </div>
          </div>
          <button
            type="button"
            aria-label="Đóng"
            disabled={isBusy}
            onClick={onClose}
            style={{ background: "none", border: "none", color: "var(--subtext)", cursor: "pointer", padding: "2px" }}
          >
            <X size={20} />
          </button>
        </div>

        <div style={{ padding: "16px 24px 24px", display: "flex", flexDirection: "column", gap: "10px" }}>
          {step === "method" && (
            <>
              <button
                type="button"
                className="btn-secondary"
                data-autofocus
                disabled={isBusy}
                onClick={() => void handle("google", () => onMethod("google"))}
                style={providerBtn}
              >
                {busy === "google" ? spinner : <GoogleIcon />}
                Tiếp tục với Google
              </button>
              <button
                type="button"
                className="btn-secondary"
                disabled={isBusy}
                onClick={() => void handle("apple", () => onMethod("apple"))}
                style={providerBtn}
              >
                {busy === "apple" ? spinner : <AppleIcon />}
                Tiếp tục với Apple
              </button>
              <button
                type="button"
                className="btn-secondary"
                disabled={isBusy}
                onClick={() => {
                  setStep("email");
                  setError("");
                }}
                style={providerBtn}
              >
                <Mail size={18} aria-hidden="true" />
                Đăng nhập bằng Email
              </button>
            </>
          )}

          {step === "email" && (
            <form onSubmit={submitEmail} noValidate style={{ display: "flex", flexDirection: "column", gap: "12px" }}>
              <div>
                <label htmlFor="chamcong-email" className="field-label">
                  Email Chấm Công
                </label>
                <input
                  id="chamcong-email"
                  type="email"
                  className="input-field"
                  data-autofocus
                  autoComplete="email"
                  autoCapitalize="none"
                  spellCheck={false}
                  value={email}
                  disabled={isBusy}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="ban@vidu.com"
                />
              </div>
              <div>
                <label htmlFor="chamcong-password" className="field-label">
                  Mật khẩu
                </label>
                <input
                  id="chamcong-password"
                  type="password"
                  className="input-field"
                  autoComplete="current-password"
                  value={password}
                  disabled={isBusy}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="Mật khẩu Chấm Công Trạm"
                />
              </div>
              <button type="submit" className="btn-primary" disabled={isBusy} style={{ ...providerBtn, marginTop: "4px" }}>
                {busy === "email" && spinner}
                {busy === "email" ? "Đang xác thực..." : "Đăng nhập"}
              </button>
            </form>
          )}

          {step === "pick" && (
            <ul role="list" style={{ listStyle: "none", margin: 0, padding: 0, display: "flex", flexDirection: "column", gap: "8px" }}>
              {options.map((o, i) => (
                <li key={o.id}>
                  <button
                    type="button"
                    className="btn-secondary"
                    data-autofocus={i === 0 ? true : undefined}
                    disabled={isBusy}
                    onClick={() => void handle(o.id, () => onPick(o.id))}
                    style={{ width: "100%", justifyContent: "flex-start", textAlign: "left", minHeight: "52px", gap: "10px" }}
                  >
                    {busy === o.id ? spinner : <Building2 size={18} aria-hidden="true" style={{ color: "var(--primary)", flexShrink: 0 }} />}
                    <span style={{ display: "flex", flexDirection: "column" }}>
                      <span style={{ fontWeight: 700, color: "var(--text)" }}>{o.label}</span>
                      {o.sublabel && <span style={{ fontSize: "12px", color: "var(--subtext)", fontWeight: 500 }}>{o.sublabel}</span>}
                    </span>
                  </button>
                </li>
              ))}
            </ul>
          )}

          {error && (
            <div
              role="alert"
              style={{
                display: "flex",
                alignItems: "flex-start",
                gap: "8px",
                background: "var(--danger-bg)",
                color: "var(--danger)",
                border: "1px solid color-mix(in srgb, var(--danger) 30%, transparent)",
                borderRadius: "10px",
                padding: "10px 12px",
                fontSize: "13px",
                lineHeight: 1.45,
              }}
            >
              <AlertCircle size={16} style={{ flexShrink: 0, marginTop: "2px" }} aria-hidden="true" />
              <div>{error}</div>
            </div>
          )}

          {footer && <div style={{ fontSize: "12px", color: "var(--muted)", lineHeight: 1.45, marginTop: "4px" }}>{footer}</div>}
        </div>
      </div>
    </div>
  );
}

function GoogleIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 48 48" aria-hidden="true" focusable="false">
      <path fill="#FFC107" d="M43.6 20.5H42V20H24v8h11.3C33.7 32.7 29.2 36 24 36c-6.6 0-12-5.4-12-12s5.4-12 12-12c3.1 0 5.8 1.2 7.9 3.1l5.7-5.7C34 6.1 29.3 4 24 4 12.9 4 4 12.9 4 24s8.9 20 20 20 20-8.9 20-20c0-1.3-.1-2.4-.4-3.5z" />
      <path fill="#FF3D00" d="M6.3 14.7l6.6 4.8C14.7 15.1 19 12 24 12c3.1 0 5.8 1.2 7.9 3.1l5.7-5.7C34 6.1 29.3 4 24 4 16.3 4 9.7 8.3 6.3 14.7z" />
      <path fill="#4CAF50" d="M24 44c5.2 0 9.9-2 13.4-5.2l-6.2-5.2C29.2 35.1 26.7 36 24 36c-5.2 0-9.6-3.3-11.3-8l-6.5 5C9.5 39.6 16.2 44 24 44z" />
      <path fill="#1976D2" d="M43.6 20.5H42V20H24v8h11.3c-.8 2.2-2.2 4.2-4.1 5.6l6.2 5.2C37 39.2 44 34 44 24c0-1.3-.1-2.4-.4-3.5z" />
    </svg>
  );
}

function AppleIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" aria-hidden="true" focusable="false" fill="currentColor">
      <path d="M16.37 12.65c-.02-2.3 1.88-3.4 1.96-3.46-1.07-1.56-2.73-1.78-3.32-1.8-1.41-.14-2.76.83-3.47.83-.72 0-1.82-.81-2.99-.79-1.54.02-2.96.9-3.75 2.27-1.6 2.78-.41 6.89 1.15 9.14.76 1.1 1.67 2.34 2.86 2.3 1.15-.05 1.58-.74 2.97-.74 1.38 0 1.78.74 2.99.72 1.24-.02 2.02-1.12 2.77-2.23.87-1.28 1.23-2.52 1.25-2.58-.03-.01-2.4-.92-2.42-3.66zM14.1 5.9c.63-.77 1.06-1.83.94-2.9-.91.04-2.02.61-2.67 1.37-.58.67-1.09 1.76-.96 2.8 1.02.08 2.06-.52 2.69-1.27z" />
    </svg>
  );
}
