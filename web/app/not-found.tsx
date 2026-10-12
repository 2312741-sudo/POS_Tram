import Link from "next/link";

/** Trang 404 dùng màu theo giao diện (trang mặc định của Next dùng chữ trắng nên không đọc được trên nền kem). */
export default function NotFound() {
  return (
    <main
      style={{
        minHeight: "100vh",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        gap: 12,
        padding: 24,
        textAlign: "center",
        color: "var(--text)",
      }}
    >
      <div style={{ fontSize: 56, fontWeight: 800, color: "var(--primary)", lineHeight: 1 }}>404</div>
      <h1 style={{ fontSize: 20, fontWeight: 700, margin: 0 }}>Không tìm thấy trang</h1>
      <p style={{ color: "var(--subtext)", margin: 0, maxWidth: 420 }}>
        Đường dẫn này không tồn tại hoặc trang đã được chuyển. Vui lòng kiểm tra lại địa chỉ.
      </p>
      <Link href="/" style={{ marginTop: 8, color: "var(--primary)", fontWeight: 700 }}>
        Về trang chủ
      </Link>
    </main>
  );
}
