import type { Metadata } from "next";
import Link from "next/link";
import {
  HelpCircle,
  Phone,
  Mail,
  Clock,
  Printer,
  Smartphone,
  CreditCard,
  Users,
  ShieldAlert,
  ArrowRight,
  CheckCircle2,
  FileQuestion,
  Lock,
  UserX,
  RefreshCw,
  WifiOff,
} from "lucide-react";
import { PublicHeader } from "@/components/PublicHeader";
import { PublicFooter } from "@/components/PublicFooter";
import { LEGAL, privacyMailto } from "@/lib/legal-config";

export const metadata: Metadata = {
  title: "Hỗ Trợ Khách Hàng & Hướng Dẫn Sử Dụng • POS Trạm",
  description:
    "Trung tâm hỗ trợ kỹ thuật chính thức của POS Trạm. Giải đáp thắc mắc, hướng dẫn sử dụng, kết nối máy in và xử lý sự cố cho ứng dụng di động và trang quản trị.",
};

export default function SupportPage() {
  const supportEmail = LEGAL.contactEmail || "hotro.postram@gmail.com";
  const mailtoSupport = privacyMailto("Yêu cầu hỗ trợ kỹ thuật - POS Trạm") || `mailto:${supportEmail}?subject=${encodeURIComponent("Yêu cầu hỗ trợ kỹ thuật - POS Trạm")}`;

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
            <HelpCircle size={14} />
            <span>TRUNG TÂM HỖ TRỢ CHÍNH THỨC</span>
          </div>
          <h1
            style={{
              fontSize: "clamp(26px, 4vw, 36px)",
              fontWeight: 800,
              color: "var(--text)",
              letterSpacing: "-0.02em",
              margin: "0 0 12px",
            }}
          >
            Chúng tôi có thể giúp gì cho bạn?
          </h1>
          <p
            style={{
              fontSize: "clamp(14px, 2vw, 16px)",
              color: "var(--subtext)",
              maxWidth: 680,
              margin: "0 auto",
              lineHeight: 1.6,
            }}
          >
            Đội ngũ hỗ trợ kỹ thuật {LEGAL.appName} luôn sẵn sàng hỗ trợ chủ quán, quản lý và nhân viên vận hành hệ thống bán hàng thông suốt 24/7.
          </p>
        </div>

        {/* Support Channels Grid */}
        <section style={{ marginBottom: 48 }}>
          <h2 style={{ fontSize: 18, fontWeight: 700, color: "var(--text)", marginBottom: 16 }}>
            Kênh liên hệ hỗ trợ trực tiếp
          </h2>
          <div
            style={{
              display: "grid",
              gridTemplateColumns: "repeat(auto-fit, minmax(240px, 1fr))",
              gap: 16,
            }}
          >
            {/* Card 1: Hotline */}
            <div
              style={{
                background: "var(--surface)",
                padding: 20,
                borderRadius: "var(--radius-lg)",
                border: "1px solid var(--border)",
                boxShadow: "var(--shadow-sm)",
              }}
            >
              <div
                style={{
                  width: 40,
                  height: 40,
                  borderRadius: "var(--radius-md)",
                  background: "var(--primary-light)",
                  color: "var(--primary)",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  marginBottom: 12,
                }}
              >
                <Phone size={20} />
              </div>
              <h3 style={{ fontSize: 15, fontWeight: 700, margin: "0 0 4px", color: "var(--text)" }}>
                Hotline Hỗ Trợ Khẩn Cấp
              </h3>
              <p style={{ fontSize: 13, color: "var(--subtext)", margin: "0 0 10px" }}>
                Xử lý sự cố gián đoạn bán hàng, lỗi in hóa đơn tức thì.
              </p>
              <a
                href={LEGAL.hotlineTel}
                style={{
                  fontSize: 16,
                  fontWeight: 800,
                  color: "var(--primary)",
                  textDecoration: "none",
                  display: "inline-block",
                }}
              >
                {LEGAL.hotline}
              </a>
            </div>

            {/* Card 2: Email */}
            <div
              style={{
                background: "var(--surface)",
                padding: 20,
                borderRadius: "var(--radius-lg)",
                border: "1px solid var(--border)",
                boxShadow: "var(--shadow-sm)",
              }}
            >
              <div
                style={{
                  width: 40,
                  height: 40,
                  borderRadius: "var(--radius-md)",
                  background: "var(--info-bg)",
                  color: "var(--info)",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  marginBottom: 12,
                }}
              >
                <Mail size={20} />
              </div>
              <h3 style={{ fontSize: 15, fontWeight: 700, margin: "0 0 4px", color: "var(--text)" }}>
                Gửi Email Kỹ Thuật
              </h3>
              <p style={{ fontSize: 13, color: "var(--subtext)", margin: "0 0 10px" }}>
                Yêu cầu hướng dẫn, cấp lại quyền hoặc đóng góp ý kiến.
              </p>
              <a
                href={mailtoSupport}
                style={{
                  fontSize: 14,
                  fontWeight: 700,
                  color: "var(--info)",
                  textDecoration: "none",
                  wordBreak: "break-all",
                }}
              >
                {supportEmail}
              </a>
            </div>

            {/* Card 3: Hours */}
            <div
              style={{
                background: "var(--surface)",
                padding: 20,
                borderRadius: "var(--radius-lg)",
                border: "1px solid var(--border)",
                boxShadow: "var(--shadow-sm)",
              }}
            >
              <div
                style={{
                  width: 40,
                  height: 40,
                  borderRadius: "var(--radius-md)",
                  background: "var(--success-bg)",
                  color: "var(--success)",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  marginBottom: 12,
                }}
              >
                <Clock size={20} />
              </div>
              <h3 style={{ fontSize: 15, fontWeight: 700, margin: "0 0 4px", color: "var(--text)" }}>
                Thời Gian Làm Việc
              </h3>
              <p style={{ fontSize: 13, color: "var(--subtext)", margin: "0 0 4px" }}>
                Thứ 2 – Chủ Nhật: <strong>08:00 – 22:00</strong>
              </p>
              <span style={{ fontSize: 12, color: "var(--success)", fontWeight: 600 }}>
                Hỗ trợ xuyên suốt các ngày Lễ, Tết
              </span>
            </div>
          </div>
        </section>

        {/* FAQ Section */}
        <section id="faq" style={{ marginBottom: 48 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 20 }}>
            <FileQuestion size={22} color="var(--primary)" />
            <h2 style={{ fontSize: 20, fontWeight: 800, color: "var(--text)", margin: 0 }}>
              Câu hỏi thường gặp & Hướng dẫn xử lý (FAQs)
            </h2>
          </div>

          <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
            {/* Topic 1 */}
            <div
              style={{
                background: "var(--surface)",
                padding: "20px 24px",
                borderRadius: "var(--radius-lg)",
                border: "1px solid var(--border)",
              }}
            >
              <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 8, color: "var(--primary)" }}>
                <Smartphone size={18} />
                <h3 style={{ fontSize: 16, fontWeight: 700, margin: 0 }}>
                  1. Đăng nhập và Bắt đầu sử dụng
                </h3>
              </div>
              <div style={{ fontSize: 14, color: "var(--text)", lineHeight: 1.6 }}>
                <p style={{ margin: "6px 0" }}>
                  <strong>Làm thế nào để đăng nhập vào ứng dụng POS trên iPhone / iPad?</strong>
                </p>
                <p style={{ margin: "4px 0 10px", color: "var(--subtext)" }}>
                  Mở ứng dụng <strong>POS Trạm</strong>, chọn chi nhánh bằng cách nhập <em>Mã cửa hàng</em> (ví dụ: <code>TRAM01</code>), sau đó nhập tên đăng nhập và mật khẩu được cấp bởi Chủ quán hoặc Quản lý chi nhánh. Bạn cũng có thể sử dụng tính năng <em>Đăng nhập bằng Chấm Công Trạm</em> nếu cửa hàng đã liên kết.
                </p>
                <p style={{ margin: "6px 0" }}>
                  <strong>Tôi bị quên mật khẩu thì lấy lại bằng cách nào?</strong>
                </p>
                <p style={{ margin: "4px 0", color: "var(--subtext)" }}>
                  Nhân viên vui lòng liên hệ Chủ quán hoặc Quản lý có quyền Quản trị để đặt lại mật khẩu trong mục <em>Quản lý nhân viên</em> trên trang Web Admin hoặc App POS.
                </p>
              </div>
            </div>

            {/* Topic 2 */}
            <div
              id="printer"
              style={{
                background: "var(--surface)",
                padding: "20px 24px",
                borderRadius: "var(--radius-lg)",
                border: "1px solid var(--border)",
              }}
            >
              <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 8, color: "var(--primary)" }}>
                <Printer size={18} />
                <h3 style={{ fontSize: 16, fontWeight: 700, margin: 0 }}>
                  2. Kết nối Máy in nhiệt Hóa đơn & Phiếu Bếp (ESC/POS)
                </h3>
              </div>
              <div style={{ fontSize: 14, color: "var(--text)", lineHeight: 1.6 }}>
                <p style={{ margin: "6px 0" }}>
                  <strong>Ứng dụng hỗ trợ những loại máy in nào?</strong>
                </p>
                <p style={{ margin: "4px 0 10px", color: "var(--subtext)" }}>
                  Hệ thống hỗ trợ tiêu chuẩn máy in nhiệt ESC/POS khổ giấy K80 (80mm) và K58 (58mm) kết nối qua <strong>Mạng LAN / WiFi (Cổng TCP 9100)</strong> hoặc <strong>Bluetooth không dây</strong> (dành cho máy in di động cầm tay).
                </p>
                <p style={{ margin: "6px 0" }}>
                  <strong>Máy in không in được hoặc báo lỗi kết nối thì xử lý thế nào?</strong>
                </p>
                <ul style={{ margin: "4px 0", paddingLeft: 20, color: "var(--subtext)" }}>
                  <li>Kiểm tra xem máy in đã bật nguồn, đèn báo Ready sáng xanh và có giấy in hay chưa.</li>
                  <li>Đảm bảo iPad / iPhone đang kết nối cùng một mạng WiFi với máy in mạng LAN.</li>
                  <li>Vào mục <em>Cài đặt máy in</em> trong ứng dụng, kiểm tra đúng địa chỉ IP máy in (ví dụ: <code>192.168.1.200</code>) và bấm <em>In thử nghiệm</em>.</li>
                  <li>Nếu dùng máy in Bluetooth, hãy kiểm tra thiết bị đã ghép đôi (paired) trong mục Cài đặt Bluetooth của máy.</li>
                </ul>
              </div>
            </div>

            {/* Topic 3 */}
            <div
              style={{
                background: "var(--surface)",
                padding: "20px 24px",
                borderRadius: "var(--radius-lg)",
                border: "1px solid var(--border)",
              }}
            >
              <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 8, color: "var(--primary)" }}>
                <CreditCard size={18} />
                <h3 style={{ fontSize: 16, fontWeight: 700, margin: 0 }}>
                  3. Thanh toán VietQR & Quản lý Ca két Thu ngân
                </h3>
              </div>
              <div style={{ fontSize: 14, color: "var(--text)", lineHeight: 1.6 }}>
                <p style={{ margin: "6px 0" }}>
                  <strong>Mã VietQR hoạt động ra sao?</strong>
                </p>
                <p style={{ margin: "4px 0 10px", color: "var(--subtext)" }}>
                  Khi thu ngân bấm chọn hình thức <em>Chuyển khoản QR</em>, màn hình sẽ hiển thị mã VietQR Napas247 động gắn đúng số tiền hóa đơn và nội dung mã đơn. Khách hàng chỉ cần mở ứng dụng ngân hàng quét mã, không cần nhập tay số tiền, đảm bảo độ chính xác 100%.
                </p>
                <p style={{ margin: "6px 0" }}>
                  <strong>Quy trình đóng / mở ca két (Cash Shift Vault)?</strong>
                </p>
                <p style={{ margin: "4px 0", color: "var(--subtext)" }}>
                  Đầu ca, thu ngân nhập số tiền nạp đầu ca. Trong ca, các hóa đơn tiền mặt được cộng dồn tự động. Cuối ca, thu ngân đếm tiền thực tế trong két và nhập vào hệ thống để in biên bản bàn giao ca, ghi nhận rõ tiền chênh lệch (nếu có).
                </p>
              </div>
            </div>

            {/* Topic 4: Xóa tài khoản (Apple Review Guideline 5.1.1(v)) */}
            <div
              id="delete-account"
              style={{
                background: "var(--surface)",
                padding: "20px 24px",
                borderRadius: "var(--radius-lg)",
                border: "1px solid var(--border)",
              }}
            >
              <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 8, color: "var(--danger)" }}>
                <UserX size={18} />
                <h3 style={{ fontSize: 16, fontWeight: 700, margin: 0 }}>
                  4. Hướng dẫn Xóa tài khoản cá nhân trong ứng dụng (Account Deletion)
                </h3>
              </div>
              <div style={{ fontSize: 14, color: "var(--text)", lineHeight: 1.6 }}>
                <p style={{ margin: "6px 0", color: "var(--subtext)" }}>
                  Tuân thủ quy định bảo vệ quyền riêng tư của Apple App Store (Guideline 5.1.1(v)), người dùng có thể tự xóa tài khoản của mình trực tiếp bên trong ứng dụng bất cứ lúc nào:
                </p>
                <div
                  style={{
                    background: "var(--surface-muted)",
                    padding: "12px 16px",
                    borderRadius: "var(--radius-md)",
                    margin: "10px 0",
                    borderLeft: "4px solid var(--danger)",
                  }}
                >
                  <p style={{ margin: "0 0 6px", fontWeight: 700, color: "var(--text)" }}>
                    Các bước thực hiện trên ứng dụng:
                  </p>
                  <ol style={{ margin: 0, paddingLeft: 20, color: "var(--subtext)", fontSize: 13 }}>
                    <li>
                      <strong>Với nhân viên Thu ngân / Phục vụ:</strong> Tại màn hình Sơ đồ bàn, nhấn nút <em>Menu chức năng (⋮)</em> → Chọn <strong>Xóa tài khoản của tôi</strong>.
                    </li>
                    <li>
                      <strong>Với Quản lý / Chủ quán:</strong> Tại màn hình Trung tâm quản lý (Manager Hub), nhấn nút <em>Menu chức năng (⋮)</em> ở góc trên bên phải → Chọn <strong>Xóa tài khoản của tôi</strong>.
                    </li>
                    <li>
                      Hộp thoại giải thích sẽ hiện ra. Bạn gõ chính xác chữ <code>XOA</code> vào ô xác nhận và nhấn nút <strong>Xóa tài khoản</strong>.
                    </li>
                    <li>
                      Tài khoản đăng nhập của bạn sẽ bị xóa ngay lập tức khỏi hệ thống, thông tin cá nhân được ẩn danh hóa và ứng dụng sẽ tự động đăng xuất.
                    </li>
                  </ol>
                </div>
                <p style={{ margin: "6px 0", fontSize: 12, color: "var(--muted)" }}>
                  <em>Lưu ý: Đối với tài khoản Chủ quán gốc (Root Owner), để bảo vệ an toàn cho dữ liệu cửa hàng, vui lòng liên hệ đơn vị vận hành qua email để chuyển quyền trước khi tiến hành xóa tài khoản.</em>
                </p>
              </div>
            </div>

            {/* Topic 5: Mất mạng */}
            <div
              style={{
                background: "var(--surface)",
                padding: "20px 24px",
                borderRadius: "var(--radius-lg)",
                border: "1px solid var(--border)",
              }}
            >
              <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 8, color: "var(--primary)" }}>
                <WifiOff size={18} />
                <h3 style={{ fontSize: 16, fontWeight: 700, margin: 0 }}>
                  5. Xử lý khi mạng Internet tại cửa hàng bị gián đoạn
                </h3>
              </div>
              <div style={{ fontSize: 14, color: "var(--text)", lineHeight: 1.6 }}>
                <p style={{ margin: "4px 0", color: "var(--subtext)" }}>
                  Ứng dụng <strong>POS Trạm</strong> có cơ chế bộ đệm ngoại tuyến (Offline Persistence). Trong thời gian mất mạng Internet, thu ngân vẫn có thể tiếp tục thao tác mở bàn, chọn món và in bill qua mạng LAN nội bộ (nếu router WiFi tại quán vẫn cấp mạng LAN). Khi có kết nối Internet trở lại, dữ liệu sẽ tự động đồng bộ lên máy chủ đám mây.
                </p>
              </div>
            </div>
          </div>
        </section>

        {/* Commitment Banner */}
        <section
          style={{
            background: "linear-gradient(135deg, var(--surface) 0%, var(--surface-muted) 100%)",
            border: "1px solid var(--border)",
            borderRadius: "var(--radius-xl)",
            padding: 28,
            boxShadow: "var(--shadow-sm)",
          }}
        >
          <div style={{ display: "flex", alignItems: "flex-start", gap: 16, flexWrap: "wrap" }}>
            <div
              style={{
                width: 44,
                height: 44,
                borderRadius: "var(--radius-md)",
                background: "var(--primary)",
                color: "#FFFFFF",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                flexShrink: 0,
              }}
            >
              <CheckCircle2 size={24} />
            </div>
            <div style={{ flex: 1, minWidth: 260 }}>
              <h3 style={{ fontSize: 17, fontWeight: 800, margin: "0 0 6px", color: "var(--text)" }}>
                Cam kết chất lượng dịch vụ & Thời gian phản hồi (SLA)
              </h3>
              <p style={{ fontSize: 13, color: "var(--subtext)", margin: "0 0 12px", lineHeight: 1.6 }}>
                Chúng tôi hiểu rằng mỗi phút gián đoạn bán hàng đều ảnh hưởng trực tiếp đến doanh thu của quán. Đội ngũ kỹ thuật cam kết:
              </p>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(200px, 1fr))", gap: 10, fontSize: 13 }}>
                <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                  <span style={{ color: "var(--primary)", fontWeight: 700 }}>• Sự cố khẩn cấp:</span>
                  <span>Phản hồi trong <strong>15 phút</strong></span>
                </div>
                <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                  <span style={{ color: "var(--primary)", fontWeight: 700 }}>• Hỗ trợ vận hành:</span>
                  <span>Phản hồi trong <strong>1 - 2 giờ</strong></span>
                </div>
              </div>
            </div>
            <div>
              <a
                href={mailtoSupport}
                style={{
                  display: "inline-flex",
                  alignItems: "center",
                  gap: 8,
                  background: "var(--primary)",
                  color: "#FFFFFF",
                  padding: "10px 20px",
                  borderRadius: "var(--radius-md)",
                  fontWeight: 700,
                  fontSize: 13,
                  textDecoration: "none",
                  boxShadow: "0 4px 12px rgba(126, 41, 48, 0.25)",
                }}
              >
                <span>Gửi yêu cầu hỗ trợ</span>
                <ArrowRight size={14} />
              </a>
            </div>
          </div>
        </section>
      </main>

      <PublicFooter />
    </div>
  );
}
