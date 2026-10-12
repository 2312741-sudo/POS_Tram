import type { Metadata } from "next";
import Link from "next/link";
import {
  Sparkles,
  Zap,
  LayoutGrid,
  Printer,
  QrCode,
  ShieldCheck,
  Users,
  Store,
  Smartphone,
  Tablet,
  CheckCircle2,
  ArrowRight,
  TrendingUp,
  Clock,
  Layers,
  ChevronRight,
} from "lucide-react";
import { PublicHeader } from "@/components/PublicHeader";
import { PublicFooter } from "@/components/PublicFooter";
import { LEGAL } from "@/lib/legal-config";

export const metadata: Metadata = {
  title: "POS Trạm • Phần Mềm Quản Lý Bán Hàng & Chuỗi F&B Toàn Diện",
  description:
    "Hệ thống bán hàng POS chuyên nghiệp thế hệ mới cho Quán Cà phê, Trà sữa, Nhà hàng và Chuỗi F&B. Đồng bộ thời gian thực, sơ đồ phòng bàn, tự động in bếp, thanh toán VietQR và kiểm soát ca két chống thất thoát.",
};

export default function MarketingPage() {
  const features = [
    {
      icon: Smartphone,
      title: "POS Bán Hàng Di Động & Tablet",
      description:
        "Giao diện trực quan tối ưu cho màn hình cảm ứng iPad, Tablet và Điện thoại. Thao tác gọi món siêu tốc, tùy chọn kích cỡ (Size), mức đường, mức đá và Topping linh hoạt chỉ với một chạm.",
      badge: "Giao diện cảm ứng",
    },
    {
      icon: LayoutGrid,
      title: "Sơ Đồ Phòng Bàn Thời Gian Thực",
      description:
        "Trực quan hóa ma trận phòng bàn theo từng khu vực (Tầng 1, Sân vườn, Phòng VIP). Phân biệt rõ ràng 4 trạng thái: Bàn trống, Có khách, Đặt trước, Chờ thanh toán. Chuyển và gộp bàn trong 3 giây.",
      badge: "Realtime Sync",
    },
    {
      icon: Printer,
      title: "Báo Bếp/Bar Tự Động (KDS) & In Nhiệt",
      description:
        "Tự động gửi lệnh in phiếu pha chế và bếp ngay khi gọi món qua mạng LAN (Port 9100) hoặc Bluetooth SPP (khổ K80/K58). Loại bỏ hoàn toàn tình trạng thất lạc hoặc nhầm lẫn đơn gọi giờ cao điểm.",
      badge: "Chuẩn ESC/POS",
    },
    {
      icon: QrCode,
      title: "Thanh Toán Động VietQR Napas247",
      description:
        "Tự động sinh mã VietQR động chứa chính xác số tiền và mã hóa đơn từng đồng. Khách hàng quét mã chuyển khoản là tiền về thẳng tài khoản quán, loại bỏ hoàn toàn rủi ro khách gõ nhầm tiền.",
      badge: "Chính xác 100%",
    },
    {
      icon: ShieldCheck,
      title: "Quản Lý Ca Két & Chống Thất Thoát",
      description:
        "Kiểm soát chặt chẽ tiền mặt đầu ca, doanh thu trong ca và kết ca bàn giao cuối ngày. Ghi nhật ký kiểm toán (Audit Logs) mọi thao tác nhạy cảm: hủy món đã gửi bếp, sửa đơn, cấp quyền.",
      badge: "Minh bạch tài chính",
    },
    {
      icon: Users,
      title: "Tích Điểm Thành Viên Đa Chi Nhánh (CRM)",
      description:
        "Nhận diện khách hàng theo số điện thoại, tích điểm tự động theo doanh số hóa đơn. Phân hạng Bạc, Vàng, Kim Cương và hỗ trợ dùng chung ví điểm giữa tất cả chi nhánh trong cùng một chuỗi.",
      badge: "Giữ chân khách hàng",
    },
  ];

  const segments = [
    { title: "Quán Cà Phê & Trà Sữa", desc: "Gọi món tốc độ cao, đa dạng công thức đường đá, in tem nhãn dán ly dán túi mượt mà." },
    { title: "Nhà Hàng & Quán Ăn", desc: "Quản lý sơ đồ bàn nhiều tầng, tách/gộp bàn linh hoạt, phiếu báo bếp phân theo khu chế biến." },
    { title: "Tiệm Bánh & Tráng Miệng", desc: "Kiểm soát tồn kho nguyên vật liệu, quản lý combo khuyến mãi và chương trình khách thân thiết." },
    { title: "Chuỗi F&B Nhượng Quyền", desc: "Quản trị tập trung đa chi nhánh, phân quyền nhân sự theo vai trò và đối soát doanh thu toàn chuỗi." },
  ];

  return (
    <div style={{ background: "var(--bg)", minHeight: "100vh", display: "flex", flexDirection: "column" }}>
      <PublicHeader />

      <main style={{ flex: 1 }}>
        {/* Hero Section */}
        <section
          style={{
            maxWidth: 1120,
            margin: "0 auto",
            padding: "56px 16px 48px",
            textAlign: "center",
          }}
        >
          <div
            style={{
              display: "inline-flex",
              alignItems: "center",
              gap: 6,
              background: "var(--primary-light)",
              color: "var(--primary)",
              padding: "6px 16px",
              borderRadius: "999px",
              fontSize: 12,
              fontWeight: 700,
              marginBottom: 18,
            }}
          >
            <Sparkles size={14} />
            <span>GIẢI PHÁP VẬN HÀNH CHUỖI F&B CHUYÊN NGHIỆP</span>
          </div>

          <h1
            style={{
              fontSize: "clamp(32px, 5vw, 48px)",
              fontWeight: 900,
              color: "var(--text)",
              letterSpacing: "-0.03em",
              lineHeight: 1.15,
              maxWidth: 880,
              margin: "0 auto 18px",
            }}
          >
            Bán Hàng Thần Tốc. Quản Lý Toàn Diện.{" "}
            <span style={{ color: "var(--primary)" }}>Không Lo Thất Thoát.</span>
          </h1>

          <p
            style={{
              fontSize: "clamp(15px, 2.2vw, 18px)",
              color: "var(--subtext)",
              maxWidth: 720,
              margin: "0 auto 32px",
              lineHeight: 1.6,
            }}
          >
            <strong>{LEGAL.appName}</strong> là hệ thống quản lý bán hàng đa nền tảng kết hợp mượt mà giữa ứng dụng điểm bán trên Di động / Tablet và Hệ thống Quản trị Web trung tâm. Tối ưu thời gian phục vụ, kiểm soát chặt chẽ dòng tiền và mở rộng chuỗi không giới hạn.
          </p>

          <div
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              gap: 14,
              flexWrap: "wrap",
              marginBottom: 48,
            }}
          >
            <Link
              href="/login"
              style={{
                display: "inline-flex",
                alignItems: "center",
                gap: 8,
                background: "var(--primary)",
                color: "#FFFFFF",
                padding: "14px 28px",
                borderRadius: "var(--radius-md)",
                fontSize: 15,
                fontWeight: 700,
                textDecoration: "none",
                boxShadow: "0 6px 20px rgba(126, 41, 48, 0.3)",
              }}
            >
              <span>Trải Nghiệm Web Admin</span>
              <ArrowRight size={16} />
            </Link>

            <Link
              href="/support"
              style={{
                display: "inline-flex",
                alignItems: "center",
                gap: 8,
                background: "var(--surface)",
                color: "var(--text)",
                border: "1px solid var(--border)",
                padding: "14px 24px",
                borderRadius: "var(--radius-md)",
                fontSize: 15,
                fontWeight: 600,
                textDecoration: "none",
                boxShadow: "var(--shadow-sm)",
              }}
            >
              <span>Xem Hướng Dẫn & Hỗ Trợ</span>
            </Link>
          </div>

          {/* Quick Stats Banner */}
          <div
            style={{
              background: "var(--surface)",
              border: "1px solid var(--border)",
              borderRadius: "var(--radius-xl)",
              padding: "24px 16px",
              display: "grid",
              gridTemplateColumns: "repeat(auto-fit, minmax(200px, 1fr))",
              gap: 20,
              boxShadow: "var(--shadow-sm)",
            }}
          >
            <div>
              <div style={{ fontSize: 28, fontWeight: 900, color: "var(--primary)" }}>&lt; 100ms</div>
              <div style={{ fontSize: 13, color: "var(--subtext)", fontWeight: 500, marginTop: 4 }}>
                Đồng bộ dữ liệu thời gian thực
              </div>
            </div>
            <div>
              <div style={{ fontSize: 28, fontWeight: 900, color: "var(--primary)" }}>100%</div>
              <div style={{ fontSize: 13, color: "var(--subtext)", fontWeight: 500, marginTop: 4 }}>
                Hỗ trợ máy in nhiệt LAN & Bluetooth
              </div>
            </div>
            <div>
              <div style={{ fontSize: 28, fontWeight: 900, color: "var(--primary)" }}>Napas247</div>
              <div style={{ fontSize: 13, color: "var(--subtext)", fontWeight: 500, marginTop: 4 }}>
                Tích hợp VietQR động không sai sót
              </div>
            </div>
            <div>
              <div style={{ fontSize: 28, fontWeight: 900, color: "var(--primary)" }}>Multi-Store</div>
              <div style={{ fontSize: 13, color: "var(--subtext)", fontWeight: 500, marginTop: 4 }}>
                Mở rộng không giới hạn chi nhánh
              </div>
            </div>
          </div>
        </section>

        {/* Feature Grid */}
        <section
          id="features"
          style={{
            maxWidth: 1120,
            margin: "0 auto",
            padding: "48px 16px",
          }}
        >
          <div style={{ textAlign: "center", marginBottom: 40 }}>
            <h2
              style={{
                fontSize: "clamp(24px, 3.5vw, 32px)",
                fontWeight: 800,
                color: "var(--text)",
                letterSpacing: "-0.02em",
                margin: "0 0 10px",
              }}
            >
              Hệ Sinh Thái Tính Năng Đột Phá
            </h2>
            <p style={{ fontSize: 15, color: "var(--subtext)", maxWidth: 640, margin: "0 auto" }}>
              Được thiết kế tỉ mỉ bởi các chuyên gia trong ngành F&B, giải quyết triệt để từng điểm nghẽn trong vận hành quán.
            </p>
          </div>

          <div
            style={{
              display: "grid",
              gridTemplateColumns: "repeat(auto-fit, minmax(320px, 1fr))",
              gap: 24,
            }}
          >
            {features.map((feat, idx) => {
              const Icon = feat.icon;
              return (
                <div
                  key={idx}
                  style={{
                    background: "var(--surface)",
                    border: "1px solid var(--border)",
                    borderRadius: "var(--radius-lg)",
                    padding: 24,
                    display: "flex",
                    flexDirection: "column",
                    boxShadow: "var(--shadow-sm)",
                    transition: "transform 0.2s ease, box-shadow 0.2s ease",
                  }}
                >
                  <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 16 }}>
                    <div
                      style={{
                        width: 44,
                        height: 44,
                        borderRadius: "var(--radius-md)",
                        background: "var(--primary-light)",
                        color: "var(--primary)",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                      }}
                    >
                      <Icon size={22} />
                    </div>
                    <span
                      style={{
                        fontSize: 11,
                        fontWeight: 700,
                        color: "var(--primary)",
                        background: "var(--surface-muted)",
                        padding: "4px 10px",
                        borderRadius: "999px",
                        border: "1px solid var(--border)",
                      }}
                    >
                      {feat.badge}
                    </span>
                  </div>

                  <h3 style={{ fontSize: 17, fontWeight: 700, color: "var(--text)", margin: "0 0 10px" }}>
                    {feat.title}
                  </h3>

                  <p style={{ fontSize: 14, color: "var(--subtext)", lineHeight: 1.6, margin: 0, flex: 1 }}>
                    {feat.description}
                  </p>
                </div>
              );
            })}
          </div>
        </section>

        {/* Suitable For Segments */}
        <section
          style={{
            background: "var(--surface-muted)",
            borderTop: "1px solid var(--border)",
            borderBottom: "1px solid var(--border)",
            padding: "56px 16px",
          }}
        >
          <div style={{ maxWidth: 1120, margin: "0 auto" }}>
            <div style={{ textAlign: "center", marginBottom: 36 }}>
              <h2
                style={{
                  fontSize: "clamp(22px, 3vw, 28px)",
                  fontWeight: 800,
                  color: "var(--text)",
                  margin: "0 0 8px",
                }}
              >
                Giải Pháp Hoàn Hảo Cho Mọi Mô Hình F&B
              </h2>
              <p style={{ fontSize: 14, color: "var(--subtext)", margin: 0 }}>
                Linh hoạt tùy biến theo phong cách phục vụ và quy mô từng cửa hàng.
              </p>
            </div>

            <div
              style={{
                display: "grid",
                gridTemplateColumns: "repeat(auto-fit, minmax(240px, 1fr))",
                gap: 20,
              }}
            >
              {segments.map((seg, idx) => (
                <div
                  key={idx}
                  style={{
                    background: "var(--surface)",
                    padding: 20,
                    borderRadius: "var(--radius-md)",
                    border: "1px solid var(--border)",
                  }}
                >
                  <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 8 }}>
                    <CheckCircle2 size={18} color="var(--success)" />
                    <h3 style={{ fontSize: 15, fontWeight: 700, margin: 0, color: "var(--text)" }}>
                      {seg.title}
                    </h3>
                  </div>
                  <p style={{ fontSize: 13, color: "var(--subtext)", margin: 0, lineHeight: 1.5 }}>
                    {seg.desc}
                  </p>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* CTA Banner */}
        <section
          style={{
            maxWidth: 1120,
            margin: "56px auto 0",
            padding: "0 16px",
          }}
        >
          <div
            style={{
              background: "linear-gradient(135deg, var(--primary) 0%, var(--primary-dark) 100%)",
              borderRadius: "var(--radius-xl)",
              padding: "44px 28px",
              color: "#FFFFFF",
              textAlign: "center",
              boxShadow: "0 12px 36px rgba(126, 41, 48, 0.35)",
            }}
          >
            <h2 style={{ fontSize: "clamp(24px, 3.5vw, 32px)", fontWeight: 800, margin: "0 0 12px" }}>
              Sẵn Sàng Nâng Tầm Vận Hành Quán Của Bạn?
            </h2>
            <p
              style={{
                fontSize: 15,
                opacity: 0.9,
                maxWidth: 620,
                margin: "0 auto 28px",
                lineHeight: 1.6,
              }}
            >
              Khám phá sức mạnh quản lý bán hàng chuẩn chuỗi với POS Trạm ngay hôm nay. Hỗ trợ đầy đủ trên ứng dụng iPad, iPhone và hệ thống Quản trị Web.
            </p>
            <div style={{ display: "flex", justifyContent: "center", gap: 14, flexWrap: "wrap" }}>
              <Link
                href="/login"
                style={{
                  background: "#FFFFFF",
                  color: "var(--primary)",
                  padding: "12px 26px",
                  borderRadius: "var(--radius-md)",
                  fontWeight: 700,
                  fontSize: 14,
                  textDecoration: "none",
                  boxShadow: "0 4px 12px rgba(0, 0, 0, 0.15)",
                }}
              >
                Đăng Nhập Web Admin
              </Link>
              <Link
                href="/support"
                style={{
                  background: "rgba(255, 255, 255, 0.15)",
                  color: "#FFFFFF",
                  border: "1px solid rgba(255, 255, 255, 0.35)",
                  padding: "12px 24px",
                  borderRadius: "var(--radius-md)",
                  fontWeight: 600,
                  fontSize: 14,
                  textDecoration: "none",
                }}
              >
                Xem Trung Tâm Hỗ Trợ
              </Link>
            </div>
          </div>
        </section>
      </main>

      <PublicFooter />
    </div>
  );
}
