import type { Metadata } from "next";
import Link from "next/link";
import { Bullets, LegalPage, Section } from "@/components/LegalPage";
import { LEGAL, privacyMailto } from "@/lib/legal-config";

export const metadata: Metadata = {
  title: "Chính sách quyền riêng tư • POS Trạm",
  description: "Cách POS Trạm thu thập, sử dụng, lưu trữ và bảo vệ dữ liệu cá nhân.",
};

export default function PrivacyPolicyPage() {
  const mail = privacyMailto("Yêu cầu về dữ liệu cá nhân - POS Trạm");
  return (
    <LegalPage title="Chính sách quyền riêng tư" updated={LEGAL.effectiveDate}>
      <p>
        {LEGAL.appName} là hệ thống bán hàng (POS) dành cho quán cà phê, trà sữa và nhà hàng, gồm ứng dụng di động và
        trang quản trị web ({LEGAL.host}). Chính sách này giải thích chúng tôi thu thập dữ liệu nào, dùng để làm gì,
        lưu ở đâu và bạn có những quyền gì.
      </p>

      <Section title="1. Ai chịu trách nhiệm về dữ liệu">
        <p>
          Mỗi cửa hàng sử dụng {LEGAL.appName} là bên quyết định mục đích sử dụng dữ liệu khách hàng và nhân viên của
          chính cửa hàng đó. Đơn vị vận hành hệ thống cung cấp nền tảng kỹ thuật, bảo mật và lưu trữ cho các cửa hàng.
          Để thực hiện quyền về dữ liệu, bạn có thể liên hệ chủ cửa hàng nơi bạn làm việc hoặc mua hàng, hoặc liên hệ
          trực tiếp theo mục 9.
        </p>
      </Section>

      <Section title="2. Dữ liệu chúng tôi thu thập">
        <p><strong>Nhân viên và người quản lý (người dùng ứng dụng):</strong></p>
        <Bullets
          items={[
            "Tên đăng nhập, họ tên, số điện thoại (nếu được nhập), vai trò (Chủ quán, Quản lý, Nhân viên, Bếp/Bar), mã cửa hàng.",
            "Mật khẩu: được xử lý bởi Firebase Authentication; chúng tôi không đọc được và không lưu mật khẩu dạng chữ thường.",
            "Thời điểm đăng nhập, nhật ký thao tác (ví dụ thanh toán, hủy đơn, xóa món kèm lý do, đổi quyền) để kiểm soát thất thoát và an toàn hệ thống.",
            "Khi bạn chọn “Đăng nhập bằng Chấm Công Trạm”: họ tên, email, số điện thoại, ảnh đại diện, vai trò và trạng thái thành viên từ tài khoản Chấm Công Trạm của bạn, chỉ để tạo và đồng bộ tài khoản POS.",
          ]}
        />
        <p><strong>Khách hàng của cửa hàng (chương trình tích điểm):</strong></p>
        <Bullets
          items={[
            "Họ tên và số điện thoại do nhân viên nhập khi tạo khách hàng, số điểm hiện có, tổng điểm tích lũy, hạng thành viên và lịch sử tích/đổi điểm.",
            "Các hóa đơn có gắn khách hàng (số tiền, món, thời gian, chi nhánh).",
          ]}
        />
        <p><strong>Dữ liệu vận hành:</strong> bàn, đơn gọi món, hóa đơn, ca két, tồn kho, khuyến mãi, ảnh món do cửa hàng tải lên.</p>
        <p>
          <strong>Chúng tôi không thu thập:</strong> vị trí, danh bạ, dữ liệu sức khỏe, dữ liệu tài chính cá nhân (số thẻ
          ngân hàng), và không dùng quảng cáo hay công cụ theo dõi hành vi chéo ứng dụng.
        </p>
      </Section>

      <Section title="3. Quyền truy cập trên thiết bị">
        <Bullets
          items={[
            "Bluetooth và mạng nội bộ: chỉ để kết nối máy in hóa đơn và phiếu bếp.",
            "Thư viện ảnh và máy ảnh: chỉ khi bạn chọn hoặc chụp ảnh món cho thực đơn.",
            "Micro: chỉ khi bạn quay video bằng máy ảnh; ứng dụng không ghi âm trong lúc bán hàng.",
          ]}
        />
      </Section>

      <Section title="4. Mục đích sử dụng">
        <Bullets
          items={[
            "Xác thực người dùng và phân quyền theo vai trò.",
            "Vận hành bán hàng: gọi món, thanh toán, in hóa đơn, quản lý kho và khuyến mãi.",
            "Chương trình khách hàng thân thiết: tích điểm, đổi điểm, xếp hạng dùng chung giữa các chi nhánh của cùng một chuỗi.",
            "Báo cáo doanh thu, đơn hủy và kiểm toán thao tác cho chủ cửa hàng.",
            "Bảo mật, phát hiện gian lận và hỗ trợ kỹ thuật.",
          ]}
        />
      </Section>

      <Section title="5. Lưu trữ và bên xử lý dữ liệu">
        <p>Dữ liệu được lưu trên các dịch vụ đám mây sau (máy chủ chính đặt tại Singapore, khu vực asia-southeast1):</p>
        <Bullets
          items={[
            "Google Firebase (Authentication, Realtime Database, Cloud Functions, Firestore) — lưu trữ và xử lý dữ liệu ứng dụng.",
            "Vercel — lưu trữ trang quản trị web.",
            "Google Sign-In và Sign in with Apple — chỉ khi bạn chọn các phương thức đăng nhập này.",
          ]}
        />
        <p>Chúng tôi không bán dữ liệu cá nhân và không chia sẻ cho bên thứ ba vì mục đích quảng cáo.</p>
      </Section>

      <Section title="6. Thời gian lưu giữ">
        <p>
          Dữ liệu tài khoản được giữ trong thời gian tài khoản còn hoạt động. Hóa đơn và chứng từ bán hàng được giữ theo
          thời hạn mà pháp luật về kế toán và thuế yêu cầu. Khi bạn yêu cầu xóa, chúng tôi xóa hoặc ẩn danh dữ liệu cá
          nhân trừ phần pháp luật bắt buộc phải lưu.
        </p>
      </Section>

      <Section title="7. Bảo mật">
        <Bullets
          items={[
            "Mọi kết nối dùng mã hóa HTTPS/TLS.",
            "Quy tắc truy cập cơ sở dữ liệu theo vai trò: nhân viên chỉ thấy dữ liệu cửa hàng của mình; thao tác nhạy cảm (điểm, quyền, mật khẩu) chỉ thực hiện qua máy chủ.",
            "Thao tác quan trọng được ghi nhật ký kiểm toán và duyệt bằng mã PIN quản lý được băm phía máy chủ.",
          ]}
        />
      </Section>

      <Section title="8. Quyền của bạn">
        <p>
          Theo quy định pháp luật Việt Nam về bảo vệ dữ liệu cá nhân (Nghị định 13/2023/NĐ-CP), bạn có quyền được biết,
          đồng ý hoặc rút lại đồng ý, truy cập, chỉnh sửa, xóa, hạn chế xử lý và phản đối việc xử lý dữ liệu của mình.
          Xem hướng dẫn thực hiện tại <Link href="/privacy-choices" style={{ color: "var(--primary)", fontWeight: 600 }}>trang quyền lựa chọn về dữ liệu</Link>.
        </p>
      </Section>

      <Section title="9. Liên hệ">
        {mail ? (
          <p>
            Gửi yêu cầu hoặc câu hỏi về quyền riêng tư tới{" "}
            <a href={mail} style={{ color: "var(--primary)", fontWeight: 600 }}>{LEGAL.contactEmail}</a>. Chúng tôi phản hồi
            trong vòng 30 ngày.
          </p>
        ) : (
          <p>
            Vui lòng liên hệ chủ cửa hàng nơi bạn sử dụng {LEGAL.appName}; chủ cửa hàng sẽ xử lý yêu cầu và chuyển cho đơn
            vị vận hành hệ thống khi cần.
          </p>
        )}
      </Section>

      <Section title="10. Thay đổi chính sách">
        <p>
          Khi có thay đổi quan trọng, chúng tôi cập nhật trang này và ngày “Cập nhật lần cuối”. Việc tiếp tục sử dụng dịch
          vụ sau khi cập nhật được hiểu là bạn đã xem thay đổi.
        </p>
      </Section>

      <hr style={{ margin: "36px 0 20px", border: 0, borderTop: "1px solid var(--border)" }} />

      <Section title="Summary (English)">
        <p>
          {LEGAL.appName} is a point-of-sale system for food and beverage shops. We collect staff account details
          (username, full name, optional phone, role), customer loyalty details entered by shop staff (name, phone, points,
          purchase history) and operational data (orders, bills, cash shifts, audit logs). When you choose to sign in with
          the “Chấm Công Trạm” time-keeping account, we receive your name, email, phone, avatar and membership role solely
          to create your POS account. We do not collect location, contacts or health data, we do not run ads and we do not
          track you across apps. Data is stored on Google Firebase (Singapore region) and the web console is hosted on
          Vercel. We do not sell personal data. Permissions requested on the device (Bluetooth, local network, photos,
          camera, microphone) are used only for printer connection and menu photos. You may request access, correction or
          deletion at any time — see the{" "}
          <Link href="/privacy-choices" style={{ color: "var(--primary)", fontWeight: 600 }}>Your Privacy Choices</Link> page.
        </p>
      </Section>
    </LegalPage>
  );
}
