import type { Metadata } from "next";
import Link from "next/link";
import Image from "next/image";
import {
  Info,
  Phone,
  Mail,
  Clock,
  ShieldCheck,
  Smartphone,
  Tablet,
  CheckCircle2,
  ArrowRight,
  ExternalLink,
  Store,
  Layers,
  Sparkles,
} from "lucide-react";
import { PublicHeader } from "@/components/PublicHeader";
import { PublicFooter } from "@/components/PublicFooter";
import { LEGAL } from "@/lib/legal-config";

export const metadata: Metadata = {
  title: "Giới Thiệu & Thông Tin Ứng Dụng • POS Trạm F&B",
  description:
    "Thông tin chính thức về hệ thống POS Trạm: phiên bản 1.0.3, hỗ trợ kỹ thuật, hotline 0865062205, tiêu chuẩn bảo mật và giải pháp quản lý bán hàng cho chuỗi F&B.",
};

export default function PublicAboutPage() {
  return (
    <div style={{ background: "var(--bg)", minHeight: "100vh", display: "flex", flexDirection: "column" }}>
      <PublicHeader />

      <main style={{ flex: 1, maxWidth: 1040, margin: "0 auto", padding: "36px 16px 64px", width: "100%" }}>
        {/* Hero Section */}
        <div style={{ textAlign: "center", marginBottom: 40 }}>
          <div
            style={{
              display: "inline-flex",
              alignItems: "center",
              gap: 6,
              background: "var(--primary-light)",
              color: "var(--primary)",
              padding: "6px 14px",
              borderRadius: "999px",
              fontSize: 12,
              fontWeight: 700,
              marginBottom: 14,
            }}
          >
            <Info size={14} />
            <span>THÔNG TIN ỨNG DỤNG CHÍNH THỨC</span>
          </div>

          <div style={{ display: "flex", justifyContent: "center", marginBottom: 16 }}>
            <div
              style={{
                width: 72,
                height: 72,
                borderRadius: 18,
                background: "var(--surface)",
                padding: 4,
                boxShadow: "0 8px 24px rgba(126, 41, 48, 0.2)",
                border: "1px solid var(--border)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                overflow: "hidden",
              }}
            >
              <Image
                src="/logo.jpg"
                alt="Logo POS Trạm"
                width={64}
                height={64}
                style={{ objectFit: "cover", borderRadius: 14 }}
                priority
              />
            </div>
          </div>

          <h1
            style={{
              fontSize: "clamp(26px, 4vw, 36px)",
              fontWeight: 800,
              color: "var(--text)",
              letterSpacing: "-0.02em",
              margin: "0 0 10px",
            }}
          >
            Hệ Thống Bán Hàng & Vận Hành POS Trạm
          </h1>

          <div style={{ display: "flex", alignItems: "center", justifyContent: "center", gap: 10, flexWrap: "wrap", marginBottom: 14 }}>
            <span
              style={{
                background: "var(--primary)",
                color: "#FFFFFF",
                padding: "4px 12px",
                borderRadius: "999px",
                fontSize: 13,
                fontWeight: 700,
              }}
            >
              Phiên bản 1.0.3 (Build 4)
            </span>
            <span style={{ fontSize: 13, color: "var(--subtext)" }}>
              Năm phát hành: <strong>2026</strong>
            </span>
            <span style={{ fontSize: 13, color: "var(--subtext)" }}>•</span>
            <span style={{ fontSize: 13, color: "var(--subtext)" }}>
              Bản quyền: <strong>{LEGAL.copyright}</strong>
            </span>
          </div>

          <p
            style={{
              fontSize: "clamp(14px, 2vw, 16px)",
              color: "var(--subtext)",
              maxWidth: 720,
              margin: "0 auto",
              lineHeight: 1.6,
            }}
          >
            Giải pháp chuyên sâu cho Quán Cà phê, Trà sữa, Nhà hàng và Chuỗi F&B với hệ sinh thái kết nối thời gian thực giữa Ứng dụng Di động POS (iPad/iPhone) và Trung tâm Quản trị Web Admin.
          </p>
        </div>

        {/* Specs & Channels */}
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(280px, 1fr))", gap: 20, marginBottom: 40 }}>
          {/* Support Hotline */}
          <div
            style={{
              background: "var(--surface)",
              border: "1px solid var(--border)",
              borderRadius: "var(--radius-lg)",
              padding: 24,
              boxShadow: "var(--shadow-sm)",
            }}
          >
            <div
              style={{
                width: 40,
                height: 40,
                borderRadius: 10,
                background: "var(--primary-light)",
                color: "var(--primary)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                marginBottom: 14,
              }}
            >
              <Phone size={20} />
            </div>
            <h3 style={{ fontSize: 16, fontWeight: 700, margin: "0 0 6px", color: "var(--text)" }}>
              Hotline Kỹ Thuật 24/7
            </h3>
            <p style={{ fontSize: 13, color: "var(--subtext)", margin: "0 0 14px", lineHeight: 1.5 }}>
              Tiếp nhận và xử lý sự cố gián đoạn bán hàng, hỗ trợ in hóa đơn tức thì.
            </p>
            <a
              href={LEGAL.hotlineTel}
              style={{
                fontSize: 18,
                fontWeight: 800,
                color: "var(--primary)",
                textDecoration: "none",
                display: "inline-block",
              }}
            >
              {LEGAL.hotline}
            </a>
          </div>

          {/* Email */}
          <div
            style={{
              background: "var(--surface)",
              border: "1px solid var(--border)",
              borderRadius: "var(--radius-lg)",
              padding: 24,
              boxShadow: "var(--shadow-sm)",
            }}
          >
            <div
              style={{
                width: 40,
                height: 40,
                borderRadius: 10,
                background: "var(--info-bg)",
                color: "var(--info)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                marginBottom: 14,
              }}
            >
              <Mail size={20} />
            </div>
            <h3 style={{ fontSize: 16, fontWeight: 700, margin: "0 0 6px", color: "var(--text)" }}>
              Hòm Thư Hỗ Trợ
            </h3>
            <p style={{ fontSize: 13, color: "var(--subtext)", margin: "0 0 14px", lineHeight: 1.5 }}>
              Yêu cầu tính năng, hướng dẫn nghiệp vụ và bàn giao tài khoản quản trị.
            </p>
            <a
              href={`mailto:${LEGAL.contactEmail || "hotro.postram@gmail.com"}`}
              style={{
                fontSize: 15,
                fontWeight: 700,
                color: "var(--info)",
                textDecoration: "none",
                wordBreak: "break-all",
                display: "inline-block",
              }}
            >
              {LEGAL.contactEmail || "hotro.postram@gmail.com"}
            </a>
          </div>

          {/* Hours & SLA */}
          <div
            style={{
              background: "var(--surface)",
              border: "1px solid var(--border)",
              borderRadius: "var(--radius-lg)",
              padding: 24,
              boxShadow: "var(--shadow-sm)",
            }}
          >
            <div
              style={{
                width: 40,
                height: 40,
                borderRadius: 10,
                background: "var(--success-bg)",
                color: "var(--success)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                marginBottom: 14,
              }}
            >
              <Clock size={20} />
            </div>
            <h3 style={{ fontSize: 16, fontWeight: 700, margin: "0 0 6px", color: "var(--text)" }}>
              Thời Gian Làm Việc & SLA
            </h3>
            <p style={{ fontSize: 13, color: "var(--subtext)", margin: "0 0 6px" }}>
              Hàng ngày: <strong>08:00 – 22:00</strong>
            </p>
            <p style={{ fontSize: 12, color: "var(--success)", fontWeight: 600, margin: 0 }}>
              Sự cố khẩn cấp phản hồi trong 15 phút
            </p>
          </div>
        </div>

        {/* System Specifications Section */}
        <section
          style={{
            background: "var(--surface)",
            border: "1px solid var(--border)",
            borderRadius: "var(--radius-xl)",
            padding: 28,
            marginBottom: 36,
            boxShadow: "var(--shadow-sm)",
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 20 }}>
            <Layers size={22} color="var(--primary)" />
            <h2 style={{ fontSize: 18, fontWeight: 800, margin: 0, color: "var(--text)" }}>
              Thông Số Ứng Dụng & Bản Quyền Phát Hành
            </h2>
          </div>

          <div
            style={{
              display: "grid",
              gridTemplateColumns: "repeat(auto-fit, minmax(240px, 1fr))",
              gap: 16,
              fontSize: 13,
            }}
          >
            <div style={{ padding: "12px 16px", background: "var(--surface-muted)", borderRadius: "var(--radius-md)" }}>
              <div style={{ color: "var(--subtext)", marginBottom: 4 }}>Tên ứng dụng:</div>
              <div style={{ fontWeight: 700, color: "var(--text)", fontSize: 14 }}>POS Trạm (TramApp)</div>
            </div>

            <div style={{ padding: "12px 16px", background: "var(--surface-muted)", borderRadius: "var(--radius-md)" }}>
              <div style={{ color: "var(--subtext)", marginBottom: 4 }}>Phiên bản hiện tại:</div>
              <div style={{ fontWeight: 700, color: "var(--text)", fontSize: 14 }}>1.0.3 (Build 4)</div>
            </div>

            <div style={{ padding: "12px 16px", background: "var(--surface-muted)", borderRadius: "var(--radius-md)" }}>
              <div style={{ color: "var(--subtext)", marginBottom: 4 }}>Apple Bundle ID:</div>
              <div style={{ fontWeight: 600, fontFamily: "monospace", color: "var(--text)", fontSize: 13 }}>
                com.tramapp.tramFlutter
              </div>
            </div>

            <div style={{ padding: "12px 16px", background: "var(--surface-muted)", borderRadius: "var(--radius-md)" }}>
              <div style={{ color: "var(--subtext)", marginBottom: 4 }}>Apple Developer Team:</div>
              <div style={{ fontWeight: 600, fontFamily: "monospace", color: "var(--text)", fontSize: 13 }}>
                W97CS7VC54
              </div>
            </div>

            <div style={{ padding: "12px 16px", background: "var(--surface-muted)", borderRadius: "var(--radius-md)" }}>
              <div style={{ color: "var(--subtext)", marginBottom: 4 }}>Bản quyền phát hành:</div>
              <div style={{ fontWeight: 700, color: "var(--text)", fontSize: 13 }}>
                {LEGAL.copyright}
              </div>
            </div>
          </div>
        </section>

        {/* Quick Links to Legal & Support */}
        <section
          style={{
            background: "linear-gradient(135deg, var(--surface) 0%, var(--surface-muted) 100%)",
            border: "1px solid var(--border)",
            borderRadius: "var(--radius-xl)",
            padding: 28,
            boxShadow: "var(--shadow-sm)",
          }}
        >
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: 16 }}>
            <div>
              <h3 style={{ fontSize: 17, fontWeight: 800, margin: "0 0 6px", color: "var(--text)" }}>
                Tuân Thủ Quy Định & Chính Sách Apple App Store
              </h3>
              <p style={{ fontSize: 13, color: "var(--subtext)", margin: 0 }}>
                Xem chi tiết các tài liệu pháp lý, quyền dữ liệu người dùng và chính sách bảo mật của chúng tôi.
              </p>
            </div>

            <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
              <Link
                href="/privacy"
                style={{
                  display: "inline-flex",
                  alignItems: "center",
                  gap: 6,
                  padding: "10px 16px",
                  borderRadius: "var(--radius-md)",
                  border: "1px solid var(--border)",
                  background: "var(--surface)",
                  color: "var(--text)",
                  fontSize: 13,
                  fontWeight: 600,
                  textDecoration: "none",
                }}
              >
                <span>Chính sách quyền riêng tư</span>
                <ExternalLink size={13} color="var(--subtext)" />
              </Link>

              <Link
                href="/support"
                style={{
                  display: "inline-flex",
                  alignItems: "center",
                  gap: 6,
                  padding: "10px 18px",
                  borderRadius: "var(--radius-md)",
                  background: "var(--primary)",
                  color: "#FFFFFF",
                  fontSize: 13,
                  fontWeight: 700,
                  textDecoration: "none",
                  boxShadow: "0 4px 12px rgba(126, 41, 48, 0.2)",
                }}
              >
                <span>Trung tâm hỗ trợ</span>
                <ArrowRight size={14} />
              </Link>
            </div>
          </div>
        </section>
      </main>

      <PublicFooter />
    </div>
  );
}
