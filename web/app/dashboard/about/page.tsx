"use client";

import { useState } from "react";
import Image from "next/image";
import Link from "next/link";
import {
  Info,
  Phone,
  Mail,
  Clock,
  ShieldCheck,
  HelpCircle,
  ExternalLink,
  Copy,
  Check,
  Store,
  User,
  Activity,
  Layers,
  Smartphone,
  CheckCircle2,
  FileText,
  UserX,
  Sparkles,
} from "lucide-react";
import { useAuth } from "@/lib/auth";
import { useDashboardData } from "@/lib/data-context";
import { LEGAL } from "@/lib/legal-config";

export default function DashboardAboutPage() {
  const { user } = useAuth();
  const { stores, currentStoreCode } = useDashboardData();
  const [copiedKey, setCopiedKey] = useState<string | null>(null);

  const currentStore = stores.find((s) => s.storeCode === currentStoreCode);
  const currentStoreName = currentStore ? currentStore.storeName : "Tất cả chi nhánh";

  const handleCopy = (text: string, key: string) => {
    navigator.clipboard.writeText(text);
    setCopiedKey(key);
    setTimeout(() => setCopiedKey(null), 2000);
  };

  const getRoleBadge = () => {
    if (user?.isRootOwner) return { text: "👑 Chủ Quán (Root Owner)", bg: "var(--primary-light)", color: "var(--primary)" };
    const role = (user?.roleId || user?.role || "").toUpperCase();
    if (role.includes("OWNER")) return { text: "👑 Chủ Quán", bg: "var(--primary-light)", color: "var(--primary)" };
    if (role.includes("MANAGER")) return { text: "⭐ Quản Lý Chi Nhánh", bg: "var(--info-bg)", color: "var(--info)" };
    if (role.includes("KITCHEN")) return { text: "👨‍🍳 Bếp / Pha Chế", bg: "var(--warning-bg)", color: "var(--warning)" };
    return { text: "👤 Nhân Viên Vận Hành", bg: "var(--surface-muted)", color: "var(--text)" };
  };

  const roleBadge = getRoleBadge();

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "24px", maxWidth: "1100px", margin: "0 auto" }}>
      {/* Top Hero Banner */}
      <div
        style={{
          background: "linear-gradient(135deg, var(--surface) 0%, var(--surface-muted) 100%)",
          border: "1px solid var(--border)",
          borderRadius: "var(--radius-xl)",
          padding: "28px 24px",
          boxShadow: "var(--shadow-sm)",
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          flexWrap: "wrap",
          gap: "20px",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: "18px" }}>
          <div
            style={{
              width: "64px",
              height: "64px",
              borderRadius: "16px",
              background: "var(--surface)",
              padding: "4px",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              flexShrink: 0,
              boxShadow: "0 6px 16px rgba(126, 41, 48, 0.15)",
              border: "1px solid var(--border)",
              position: "relative",
              overflow: "hidden",
            }}
          >
            <Image
              src="/logo.jpg"
              alt="Logo POS Trạm"
              width={56}
              height={56}
              style={{ objectFit: "cover", borderRadius: "12px" }}
              priority
            />
          </div>
          <div>
            <div style={{ display: "flex", alignItems: "center", gap: "10px", flexWrap: "wrap", marginBottom: "4px" }}>
              <h1
                style={{
                  fontSize: "clamp(20px, 3vw, 24px)",
                  fontWeight: "800",
                  color: "var(--text)",
                  letterSpacing: "-0.02em",
                  margin: 0,
                }}
              >
                POS Trạm F&B System
              </h1>
              <span
                style={{
                  background: "var(--primary-light)",
                  color: "var(--primary)",
                  padding: "3px 10px",
                  borderRadius: "999px",
                  fontSize: "12px",
                  fontWeight: "800",
                }}
              >
                Phiên bản 1.0.3
              </span>
            </div>
            <p style={{ margin: 0, color: "var(--subtext)", fontSize: "14px" }}>
              Hệ thống Quản lý Bán hàng, Điều phối Phòng bàn, Báo bếp và Vận hành Chuỗi F&B Toàn diện
            </p>
          </div>
        </div>

        <div style={{ display: "flex", gap: "10px", flexWrap: "wrap" }}>
          <Link
            href="/support"
            className="btn-secondary"
            style={{
              display: "inline-flex",
              alignItems: "center",
              gap: "6px",
              padding: "9px 16px",
              borderRadius: "10px",
              fontSize: "13px",
              fontWeight: "600",
              textDecoration: "none",
            }}
          >
            <HelpCircle size={15} />
            <span>Trung tâm hỗ trợ</span>
          </Link>
          <a
            href={LEGAL.hotlineTel}
            className="btn-primary"
            style={{
              display: "inline-flex",
              alignItems: "center",
              gap: "6px",
              padding: "9px 16px",
              borderRadius: "10px",
              fontSize: "13px",
              fontWeight: "700",
              textDecoration: "none",
            }}
          >
            <Phone size={15} />
            <span>Hotline {LEGAL.hotline}</span>
          </a>
        </div>
      </div>

      {/* Grid: Session & Tech Specs */}
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fit, minmax(320px, 1fr))",
          gap: "20px",
        }}
      >
        {/* Card 1: Phiên làm việc hiện tại */}
        <div
          style={{
            background: "var(--surface)",
            border: "1px solid var(--border)",
            borderRadius: "var(--radius-lg)",
            padding: "22px",
            boxShadow: "var(--shadow-sm)",
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: "10px", marginBottom: "16px" }}>
            <div
              style={{
                width: "36px",
                height: "36px",
                borderRadius: "10px",
                background: "var(--primary-light)",
                color: "var(--primary)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              <User size={18} />
            </div>
            <div>
              <h2 style={{ fontSize: "16px", fontWeight: "700", margin: 0, color: "var(--text)" }}>
                Phiên làm việc & Tài khoản
              </h2>
              <span style={{ fontSize: "12px", color: "var(--subtext)" }}>Thông tin phiên đăng nhập trên thiết bị</span>
            </div>
          </div>

          <div style={{ display: "flex", flexDirection: "column", gap: "12px", fontSize: "13px" }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", paddingBottom: "10px", borderBottom: "1px dashed var(--border)" }}>
              <span style={{ color: "var(--subtext)" }}>Người dùng:</span>
              <span style={{ fontWeight: "700", color: "var(--text)" }}>
                {user?.fullName || user?.username || "Chưa xác định"}
              </span>
            </div>

            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", paddingBottom: "10px", borderBottom: "1px dashed var(--border)" }}>
              <span style={{ color: "var(--subtext)" }}>Tên đăng nhập:</span>
              <span style={{ fontWeight: "600", fontFamily: "monospace", color: "var(--text)" }}>
                {user?.username || "—"}
              </span>
            </div>

            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", paddingBottom: "10px", borderBottom: "1px dashed var(--border)" }}>
              <span style={{ color: "var(--subtext)" }}>Vai trò phân quyền:</span>
              <span
                style={{
                  background: roleBadge.bg,
                  color: roleBadge.color,
                  padding: "2px 8px",
                  borderRadius: "6px",
                  fontSize: "12px",
                  fontWeight: "700",
                }}
              >
                {roleBadge.text}
              </span>
            </div>

            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", paddingBottom: "10px", borderBottom: "1px dashed var(--border)" }}>
              <span style={{ color: "var(--subtext)" }}>Chi nhánh đang chọn:</span>
              <span style={{ fontWeight: "700", color: "var(--primary)", display: "flex", alignItems: "center", gap: "6px" }}>
                <Store size={14} />
                {currentStoreCode === "ALL" ? "Toàn bộ hệ thống" : `${currentStoreCode} - ${currentStoreName}`}
              </span>
            </div>

            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
              <span style={{ color: "var(--subtext)" }}>Trạng thái kết nối:</span>
              <span style={{ color: "var(--success)", fontWeight: "700", display: "flex", alignItems: "center", gap: "6px" }}>
                <span
                  style={{
                    width: "8px",
                    height: "8px",
                    borderRadius: "50%",
                    background: "var(--success)",
                    display: "inline-block",
                  }}
                />
                Trực tuyến (Realtime Sync)
              </span>
            </div>
          </div>
        </div>

        {/* Card 2: Thông số kỹ thuật & Phiên bản */}
        <div
          style={{
            background: "var(--surface)",
            border: "1px solid var(--border)",
            borderRadius: "var(--radius-lg)",
            padding: "22px",
            boxShadow: "var(--shadow-sm)",
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: "10px", marginBottom: "16px" }}>
            <div
              style={{
                width: "36px",
                height: "36px",
                borderRadius: "10px",
                background: "var(--info-bg)",
                color: "var(--info)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              <Layers size={18} />
            </div>
            <div>
              <h2 style={{ fontSize: "16px", fontWeight: "700", margin: 0, color: "var(--text)" }}>
                Hệ thống & Thông số Kỹ thuật
              </h2>
              <span style={{ fontSize: "12px", color: "var(--subtext)" }}>Thông tin phát hành và nền tảng cốt lõi</span>
            </div>
          </div>

          <div style={{ display: "flex", flexDirection: "column", gap: "12px", fontSize: "13px" }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", paddingBottom: "10px", borderBottom: "1px dashed var(--border)" }}>
              <span style={{ color: "var(--subtext)" }}>Phiên bản Web Admin:</span>
              <span style={{ fontWeight: "700", color: "var(--text)" }}>1.0.3</span>
            </div>

            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", paddingBottom: "10px", borderBottom: "1px dashed var(--border)" }}>
              <span style={{ color: "var(--subtext)" }}>Ứng dụng App POS (iOS/Android):</span>
              <span style={{ fontWeight: "700", color: "var(--text)" }}>1.0.3 (Build 4)</span>
            </div>

            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", paddingBottom: "10px", borderBottom: "1px dashed var(--border)" }}>
              <span style={{ color: "var(--subtext)" }}>Apple Bundle Identifier:</span>
              <span style={{ fontWeight: "600", fontFamily: "monospace", color: "var(--text)" }}>
                com.tramapp.tramFlutter
              </span>
            </div>

            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", paddingBottom: "10px", borderBottom: "1px dashed var(--border)" }}>
              <span style={{ color: "var(--subtext)" }}>Cơ sở dữ liệu đám mây:</span>
              <span style={{ fontWeight: "600", color: "var(--text)" }}>Firebase Realtime Database</span>
            </div>

            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
              <span style={{ color: "var(--subtext)" }}>Bản quyền phát hành:</span>
              <span style={{ fontWeight: "700", color: "var(--text)" }}>{LEGAL.copyright}</span>
            </div>
          </div>
        </div>
      </div>

      {/* Support & Contact Cards */}
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fit, minmax(280px, 1fr))",
          gap: "20px",
        }}
      >
        {/* Hotline */}
        <div
          style={{
            background: "var(--surface)",
            border: "1px solid var(--border)",
            borderRadius: "var(--radius-lg)",
            padding: "20px",
            boxShadow: "var(--shadow-sm)",
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: "10px", marginBottom: "12px" }}>
            <div
              style={{
                width: "36px",
                height: "36px",
                borderRadius: "10px",
                background: "var(--primary-light)",
                color: "var(--primary)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              <Phone size={18} />
            </div>
            <div>
              <h3 style={{ fontSize: "15px", fontWeight: "700", margin: 0, color: "var(--text)" }}>
                Hotline Hỗ Trợ 24/7
              </h3>
              <span style={{ fontSize: "12px", color: "var(--subtext)" }}>Xử lý sự cố vận hành khẩn cấp</span>
            </div>
          </div>
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginTop: "14px" }}>
            <a
              href={LEGAL.hotlineTel}
              style={{
                fontSize: "17px",
                fontWeight: "800",
                color: "var(--primary)",
                textDecoration: "none",
              }}
            >
              {LEGAL.hotline}
            </a>
            <button
              type="button"
              onClick={() => handleCopy("0865062205", "hotline")}
              className="btn-icon"
              title="Sao chép số Hotline"
              style={{ padding: "6px 10px", display: "flex", alignItems: "center", gap: "4px", fontSize: "12px" }}
            >
              {copiedKey === "hotline" ? <Check size={14} color="var(--success)" /> : <Copy size={14} />}
              <span>{copiedKey === "hotline" ? "Đã chép" : "Sao chép"}</span>
            </button>
          </div>
        </div>

        {/* Email */}
        <div
          style={{
            background: "var(--surface)",
            border: "1px solid var(--border)",
            borderRadius: "var(--radius-lg)",
            padding: "20px",
            boxShadow: "var(--shadow-sm)",
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: "10px", marginBottom: "12px" }}>
            <div
              style={{
                width: "36px",
                height: "36px",
                borderRadius: "10px",
                background: "var(--info-bg)",
                color: "var(--info)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              <Mail size={18} />
            </div>
            <div>
              <h3 style={{ fontSize: "15px", fontWeight: "700", margin: 0, color: "var(--text)" }}>
                Email Kỹ Thuật
              </h3>
              <span style={{ fontSize: "12px", color: "var(--subtext)" }}>Hỗ trợ nghiệp vụ & tính năng mới</span>
            </div>
          </div>
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginTop: "14px" }}>
            <a
              href={`mailto:${LEGAL.contactEmail || "hotro.postram@gmail.com"}`}
              style={{
                fontSize: "14px",
                fontWeight: "700",
                color: "var(--info)",
                textDecoration: "none",
              }}
            >
              {LEGAL.contactEmail || "hotro.postram@gmail.com"}
            </a>
            <button
              type="button"
              onClick={() => handleCopy(LEGAL.contactEmail || "hotro.postram@gmail.com", "email")}
              className="btn-icon"
              title="Sao chép Email"
              style={{ padding: "6px 10px", display: "flex", alignItems: "center", gap: "4px", fontSize: "12px" }}
            >
              {copiedKey === "email" ? <Check size={14} color="var(--success)" /> : <Copy size={14} />}
              <span>{copiedKey === "email" ? "Đã chép" : "Sao chép"}</span>
            </button>
          </div>
        </div>

        {/* Working Hours */}
        <div
          style={{
            background: "var(--surface)",
            border: "1px solid var(--border)",
            borderRadius: "var(--radius-lg)",
            padding: "20px",
            boxShadow: "var(--shadow-sm)",
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: "10px", marginBottom: "12px" }}>
            <div
              style={{
                width: "36px",
                height: "36px",
                borderRadius: "10px",
                background: "var(--success-bg)",
                color: "var(--success)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              <Clock size={18} />
            </div>
            <div>
              <h3 style={{ fontSize: "15px", fontWeight: "700", margin: 0, color: "var(--text)" }}>
                Khung Giờ Phục Vụ
              </h3>
              <span style={{ fontSize: "12px", color: "var(--subtext)" }}>Đội ngũ trực kỹ thuật hệ thống</span>
            </div>
          </div>
          <p style={{ margin: "14px 0 0", fontSize: "14px", fontWeight: "700", color: "var(--text)" }}>
            08:00 – 22:00 (Hàng ngày)
          </p>
          <span style={{ fontSize: "12px", color: "var(--success)", fontWeight: "600" }}>
            Phục vụ liên tục trong các dịp Lễ, Tết
          </span>
        </div>
      </div>

      {/* Legal & App Store Compliance Section */}
      <div
        style={{
          background: "var(--surface)",
          border: "1px solid var(--border)",
          borderRadius: "var(--radius-xl)",
          padding: "24px",
          boxShadow: "var(--shadow-sm)",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: "10px", marginBottom: "16px" }}>
          <ShieldCheck size={22} color="var(--primary)" />
          <h2 style={{ fontSize: "17px", fontWeight: "800", color: "var(--text)", margin: 0 }}>
            Chính Sách Pháp Lý & Tuân Thủ Apple App Store
          </h2>
        </div>

        <p style={{ fontSize: "14px", color: "var(--subtext)", margin: "0 0 18px", lineHeight: "1.6" }}>
          Hệ thống {LEGAL.appName} cam kết tuân thủ nghiêm ngặt các quy định về bảo vệ quyền riêng tư, an toàn dữ liệu khách hàng và quy định phát hành ứng dụng trên Apple App Store Review Guidelines.
        </p>

        <div
          style={{
            display: "grid",
            gridTemplateColumns: "repeat(auto-fit, minmax(260px, 1fr))",
            gap: "14px",
          }}
        >
          <Link
            href="/privacy"
            style={{
              padding: "16px",
              borderRadius: "var(--radius-md)",
              border: "1px solid var(--border)",
              background: "var(--surface-muted)",
              textDecoration: "none",
              display: "flex",
              alignItems: "flex-start",
              gap: "12px",
              transition: "border-color 0.15s ease",
            }}
          >
            <FileText size={20} color="var(--primary)" style={{ flexShrink: 0, marginTop: "2px" }} />
            <div>
              <div style={{ fontSize: "14px", fontWeight: "700", color: "var(--text)", marginBottom: "4px", display: "flex", alignItems: "center", gap: "6px" }}>
                <span>Chính sách quyền riêng tư</span>
                <ExternalLink size={13} color="var(--subtext)" />
              </div>
              <p style={{ fontSize: "12px", color: "var(--subtext)", margin: 0, lineHeight: 1.5 }}>
                Quy định minh bạch về thu thập, lưu trữ và bảo vệ dữ liệu bán hàng.
              </p>
            </div>
          </Link>

          <Link
            href="/privacy-choices"
            style={{
              padding: "16px",
              borderRadius: "var(--radius-md)",
              border: "1px solid var(--border)",
              background: "var(--surface-muted)",
              textDecoration: "none",
              display: "flex",
              alignItems: "flex-start",
              gap: "12px",
              transition: "border-color 0.15s ease",
            }}
          >
            <ShieldCheck size={20} color="var(--info)" style={{ flexShrink: 0, marginTop: "2px" }} />
            <div>
              <div style={{ fontSize: "14px", fontWeight: "700", color: "var(--text)", marginBottom: "4px", display: "flex", alignItems: "center", gap: "6px" }}>
                <span>Quyền lựa chọn về dữ liệu</span>
                <ExternalLink size={13} color="var(--subtext)" />
              </div>
              <p style={{ fontSize: "12px", color: "var(--subtext)", margin: 0, lineHeight: 1.5 }}>
                Tra cứu, xuất bản sao hoặc yêu cầu chỉnh sửa thông tin cá nhân.
              </p>
            </div>
          </Link>

          <Link
            href="/support#delete-account"
            style={{
              padding: "16px",
              borderRadius: "var(--radius-md)",
              border: "1px solid var(--border)",
              background: "var(--surface-muted)",
              textDecoration: "none",
              display: "flex",
              alignItems: "flex-start",
              gap: "12px",
              transition: "border-color 0.15s ease",
            }}
          >
            <UserX size={20} color="var(--danger)" style={{ flexShrink: 0, marginTop: "2px" }} />
            <div>
              <div style={{ fontSize: "14px", fontWeight: "700", color: "var(--text)", marginBottom: "4px", display: "flex", alignItems: "center", gap: "6px" }}>
                <span>Xóa tài khoản trong ứng dụng</span>
                <ExternalLink size={13} color="var(--subtext)" />
              </div>
              <p style={{ fontSize: "12px", color: "var(--subtext)", margin: 0, lineHeight: 1.5 }}>
                Tuân thủ Apple Guideline 5.1.1(v) cho phép nhân viên tự hủy tài khoản.
              </p>
            </div>
          </Link>
        </div>
      </div>
    </div>
  );
}
