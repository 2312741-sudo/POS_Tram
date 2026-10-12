import Link from "next/link";
import { Coffee, Phone, Mail, Clock, ShieldCheck, HelpCircle } from "lucide-react";
import { LEGAL } from "@/lib/legal-config";

export function PublicFooter() {
  const currentYear = new Date().getFullYear();

  return (
    <footer
      style={{
        background: "var(--surface)",
        borderTop: "1px solid var(--border)",
        marginTop: 64,
        color: "var(--subtext)",
        fontSize: 13,
      }}
    >
      <div
        style={{
          maxWidth: 1120,
          margin: "0 auto",
          padding: "48px 16px 32px",
          display: "grid",
          gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))",
          gap: 32,
        }}
      >
        {/* Col 1: About */}
        <div>
          <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 12 }}>
            <div
              style={{
                width: 32,
                height: 32,
                borderRadius: "var(--radius-sm)",
                background: "var(--primary)",
                color: "#FFFFFF",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              <Coffee size={18} />
            </div>
            <span style={{ fontSize: 16, fontWeight: 800, color: "var(--primary)" }}>POS Trạm</span>
          </div>
          <p style={{ lineHeight: 1.6, margin: "0 0 16px", color: "var(--subtext)" }}>
            Giải pháp phần mềm quản lý vận hành bán hàng F&B chuyên nghiệp cho Quán Cà phê, Trà sữa, Nhà hàng và Chuỗi F&B đa chi nhánh.
          </p>
          <div style={{ display: "flex", flexDirection: "column", gap: 6, fontSize: 12 }}>
            <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
              <Clock size={14} color="var(--primary)" />
              <span>Hỗ trợ kỹ thuật: 08:00 - 22:00 (Hàng ngày)</span>
            </div>
            <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
              <Phone size={14} color="var(--primary)" />
              <a href={LEGAL.hotlineTel} style={{ color: "inherit", textDecoration: "none" }}>
                Hotline: {LEGAL.hotline}
              </a>
            </div>
            <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
              <Mail size={14} color="var(--primary)" />
              <span>{LEGAL.contactEmail || "hotro.postram@gmail.com"}</span>
            </div>
          </div>
        </div>

        {/* Col 2: Sản phẩm & Tính năng */}
        <div>
          <h4 style={{ fontSize: 14, fontWeight: 700, color: "var(--text)", margin: "0 0 14px" }}>
            Sản phẩm & Tính năng
          </h4>
          <ul style={{ listStyle: "none", padding: 0, margin: 0, display: "flex", flexDirection: "column", gap: 8 }}>
            <li>
              <Link href="/marketing" style={{ color: "var(--subtext)", textDecoration: "none" }}>
                POS Bán Hàng (Tablet & Mobile)
              </Link>
            </li>
            <li>
              <Link href="/marketing#features" style={{ color: "var(--subtext)", textDecoration: "none" }}>
                Sơ đồ phòng bàn thời gian thực
              </Link>
            </li>
            <li>
              <Link href="/marketing#features" style={{ color: "var(--subtext)", textDecoration: "none" }}>
                Báo bếp tự động (KDS) & In nhiệt
              </Link>
            </li>
            <li>
              <Link href="/marketing#features" style={{ color: "var(--subtext)", textDecoration: "none" }}>
                Thanh toán VietQR Napas247 động
              </Link>
            </li>
            <li>
              <Link href="/marketing#features" style={{ color: "var(--subtext)", textDecoration: "none" }}>
                Quản lý ca két & Chống thất thoát
              </Link>
            </li>
            <li>
              <Link href="/marketing#features" style={{ color: "var(--subtext)", textDecoration: "none" }}>
                Tích điểm đa chi nhánh (CRM)
              </Link>
            </li>
          </ul>
        </div>

        {/* Col 3: Hỗ trợ & Tài liệu */}
        <div>
          <h4 style={{ fontSize: 14, fontWeight: 700, color: "var(--text)", margin: "0 0 14px" }}>
            Hỗ trợ & Hướng dẫn
          </h4>
          <ul style={{ listStyle: "none", padding: 0, margin: 0, display: "flex", flexDirection: "column", gap: 8 }}>
            <li>
              <Link href="/support" style={{ color: "var(--subtext)", textDecoration: "none" }}>
                Trung tâm hỗ trợ khách hàng
              </Link>
            </li>
            <li>
              <Link href="/support#faq" style={{ color: "var(--subtext)", textDecoration: "none" }}>
                Câu hỏi thường gặp (FAQs)
              </Link>
            </li>
            <li>
              <Link href="/support#printer" style={{ color: "var(--subtext)", textDecoration: "none" }}>
                Hướng dẫn kết nối máy in hóa đơn
              </Link>
            </li>
            <li>
              <Link href="/support#account" style={{ color: "var(--subtext)", textDecoration: "none" }}>
                Quản lý tài khoản & Đổi mật khẩu
              </Link>
            </li>
            <li>
              <Link href="/support#contact" style={{ color: "var(--subtext)", textDecoration: "none" }}>
                Yêu cầu hỗ trợ kỹ thuật
              </Link>
            </li>
          </ul>
        </div>

        {/* Col 4: Pháp lý & Điều khoản */}
        <div>
          <h4 style={{ fontSize: 14, fontWeight: 700, color: "var(--text)", margin: "0 0 14px" }}>
            Pháp lý & Quyền riêng tư
          </h4>
          <ul style={{ listStyle: "none", padding: 0, margin: 0, display: "flex", flexDirection: "column", gap: 8 }}>
            <li>
              <Link href="/privacy" style={{ color: "var(--subtext)", textDecoration: "none" }}>
                Chính sách quyền riêng tư
              </Link>
            </li>
            <li>
              <Link href="/privacy-choices" style={{ color: "var(--subtext)", textDecoration: "none" }}>
                Quyền lựa chọn về dữ liệu cá nhân
              </Link>
            </li>
            <li>
              <Link href="/support#delete-account" style={{ color: "var(--subtext)", textDecoration: "none" }}>
                Xóa tài khoản trong ứng dụng
              </Link>
            </li>
            <li>
              <span style={{ color: "var(--muted)", fontSize: 12 }}>
                Tuân thủ Apple App Store Review Guidelines (1.5, 5.1.1)
              </span>
            </li>
          </ul>
        </div>
      </div>

      {/* Bottom Bar */}
      <div
        style={{
          borderTop: "1px solid var(--border)",
          padding: "16px",
          textAlign: "center",
          fontSize: 12,
          color: "var(--muted)",
          background: "var(--surface-sunken)",
        }}
      >
        <div style={{ maxWidth: 1120, margin: "0 auto", display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: 8 }}>
          <span>© {currentYear} {LEGAL.appName} ({LEGAL.host}). Bảo lưu mọi quyền.</span>
          <div style={{ display: "flex", gap: 16 }}>
            <Link href="/support" style={{ color: "var(--muted)", textDecoration: "none" }}>Hỗ trợ</Link>
            <Link href="/marketing" style={{ color: "var(--muted)", textDecoration: "none" }}>Giới thiệu</Link>
            <Link href="/privacy" style={{ color: "var(--muted)", textDecoration: "none" }}>Bảo mật</Link>
            <Link href="/login" style={{ color: "var(--muted)", textDecoration: "none" }}>Đăng nhập</Link>
          </div>
        </div>
      </div>
    </footer>
  );
}
