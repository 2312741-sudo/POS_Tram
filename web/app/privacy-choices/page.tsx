import type { Metadata } from "next";
import Link from "next/link";
import { Bullets, LegalPage, Section } from "@/components/LegalPage";
import { LEGAL, privacyMailto } from "@/lib/legal-config";

export const metadata: Metadata = {
  title: "Quyền lựa chọn về dữ liệu • POS Trạm",
  description: "Cách xem, sửa, xóa dữ liệu cá nhân và rút lại đồng ý khi dùng POS Trạm.",
};

const linkStyle = { color: "var(--primary)", fontWeight: 600 } as const;

function RequestButton({ subject, label }: { subject: string; label: string }) {
  const href = privacyMailto(subject);
  if (!href) return null;
  return (
    <a
      href={href}
      style={{
        display: "inline-block",
        marginTop: 8,
        padding: "10px 16px",
        borderRadius: 8,
        background: "var(--primary)",
        color: "#fff",
        fontWeight: 700,
        textDecoration: "none",
      }}
    >
      {label}
    </a>
  );
}

export default function PrivacyChoicesPage() {
  return (
    <LegalPage title="Quyền lựa chọn về dữ liệu của bạn" updated={LEGAL.effectiveDate}>
      <p>
        Trang này hướng dẫn cách thực hiện các quyền đối với dữ liệu cá nhân khi dùng {LEGAL.appName}. Xem thêm{" "}
        <Link href="/privacy" style={linkStyle}>Chính sách quyền riêng tư</Link>.
      </p>
      <p>
        <strong>Chúng tôi không dùng dữ liệu của bạn để quảng cáo hay theo dõi chéo ứng dụng</strong>, vì vậy không có
        mục “từ chối bán/chia sẻ dữ liệu” cần bật. Các lựa chọn bên dưới là các quyền bạn có thể thực hiện bất cứ lúc nào.
      </p>

      <Section title="1. Xem hoặc chỉnh sửa thông tin của bạn">
        <Bullets
          items={[
            "Nhân viên: xem và đổi mật khẩu trong ứng dụng; nhờ Chủ quán hoặc Quản lý chỉnh sửa họ tên, số điện thoại, vai trò ở mục Nhân viên.",
            "Khách hàng tích điểm: nhờ nhân viên cửa hàng cập nhật họ tên và số điện thoại ở mục Khách hàng, hoặc gửi yêu cầu theo mục 5.",
          ]}
        />
      </Section>

      <Section title="2. Xóa tài khoản hoặc dữ liệu">
        <Bullets
          items={[
            "Nhân viên: Chủ quán hoặc Quản lý xóa hồ sơ nhân viên (mục Nhân viên → Xóa). Hồ sơ biến mất khỏi danh sách và người đó không còn truy cập được cửa hàng.",
            "Khách hàng: yêu cầu xóa hồ sơ khách và điểm tích lũy; họ tên, số điện thoại sẽ được xóa hoặc ẩn danh.",
            "Hóa đơn đã phát sinh được giữ theo thời hạn pháp luật về kế toán và thuế, nhưng thông tin nhận dạng khách hàng trên hóa đơn sẽ được ẩn danh khi bạn yêu cầu.",
          ]}
        />
        <RequestButton subject="Yêu cầu xóa dữ liệu cá nhân - POS Trạm" label="Gửi yêu cầu xóa dữ liệu" />
      </Section>

      <Section title="3. Rút lại đồng ý">
        <Bullets
          items={[
            "Tham gia tích điểm: bạn có thể yêu cầu ngừng tích điểm và xóa hồ sơ khách hàng bất cứ lúc nào.",
            "Đăng nhập bằng Chấm Công Trạm: Chủ quán có thể hủy liên kết cửa hàng (mục Liên kết Chấm Công Trạm); bạn cũng có thể thu hồi quyền truy cập trong cài đặt tài khoản Google hoặc Apple của mình.",
            "Quyền trên thiết bị (Bluetooth, mạng nội bộ, ảnh, máy ảnh, micro): thay đổi bất cứ lúc nào trong Cài đặt → POS Trạm của iPhone/iPad.",
          ]}
        />
      </Section>

      <Section title="4. Đăng xuất và xóa dữ liệu trên thiết bị">
        <p>
          Đăng xuất khỏi ứng dụng để chấm dứt phiên làm việc. Gỡ cài đặt ứng dụng sẽ xóa dữ liệu lưu cục bộ trên thiết
          bị (như cấu hình máy in và hàng đợi cộng điểm chưa gửi).
        </p>
      </Section>

      <Section title="5. Gửi yêu cầu">
        {LEGAL.contactEmail ? (
          <>
            <p>
              Gửi email tới <a href={privacyMailto("Yêu cầu về dữ liệu cá nhân - POS Trạm")} style={linkStyle}>{LEGAL.contactEmail}</a> và
              nêu rõ: (1) yêu cầu của bạn (xem / sửa / xóa / rút đồng ý), (2) họ tên và số điện thoại hoặc tên đăng nhập, (3)
              cửa hàng liên quan. Chúng tôi có thể cần xác minh danh tính trước khi xử lý và sẽ phản hồi trong vòng 30 ngày.
            </p>
            <RequestButton subject="Yêu cầu về dữ liệu cá nhân - POS Trạm" label="Gửi email yêu cầu" />
          </>
        ) : (
          <p>
            Vui lòng liên hệ chủ cửa hàng nơi bạn sử dụng {LEGAL.appName} và nêu rõ: (1) yêu cầu của bạn (xem / sửa / xóa /
            rút đồng ý), (2) họ tên và số điện thoại hoặc tên đăng nhập. Chủ cửa hàng sẽ xử lý và chuyển cho đơn vị vận
            hành hệ thống khi cần.
          </p>
        )}
      </Section>

      <hr style={{ margin: "36px 0 20px", border: 0, borderTop: "1px solid var(--border)" }} />

      <Section title="Your Privacy Choices (English)">
        <Bullets
          items={[
            "We do not sell your data, run ads or track you across apps, so there is no opt-out toggle to set.",
            "Access or correct: staff can update their details in the app or ask a shop owner/manager; loyalty customers can ask shop staff.",
            "Delete: ask a shop owner/manager to remove a staff profile, or request deletion of a loyalty customer record. Bills required by accounting law are retained, with customer identity anonymised on request.",
            "Withdraw consent: stop loyalty participation, unlink the “Chấm Công Trạm” sign-in, or change device permissions in iOS Settings → POS Trạm at any time.",
            LEGAL.contactEmail
              ? `Contact: ${LEGAL.contactEmail}. We respond within 30 days.`
              : "Contact the shop owner where you use the service; they will handle your request and escalate to the platform operator if needed.",
          ]}
        />
      </Section>
    </LegalPage>
  );
}
