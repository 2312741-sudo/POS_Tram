import type { ReactNode } from "react";
import Link from "next/link";

/** Khung trang pháp lý công khai: không cần đăng nhập, dùng được ở chế độ sáng/tối. */
export function LegalPage({ title, updated, children }: { title: string; updated: string; children: ReactNode }) {
  return (
    <main style={{ maxWidth: 820, margin: "0 auto", padding: "32px 16px 64px", color: "var(--text)", lineHeight: 1.65 }}>
      <nav style={{ display: "flex", gap: 16, flexWrap: "wrap", fontSize: 13, marginBottom: 24 }}>
        <Link href="/marketing" style={{ color: "var(--subtext)", fontWeight: 500, textDecoration: "none" }}>← Giới thiệu sản phẩm</Link>
        <Link href="/support" style={{ color: "var(--subtext)", fontWeight: 500, textDecoration: "none" }}>Trung tâm hỗ trợ</Link>
        <Link href="/privacy" style={{ color: "var(--primary)", fontWeight: 600 }}>Chính sách quyền riêng tư</Link>
        <Link href="/privacy-choices" style={{ color: "var(--primary)", fontWeight: 600 }}>Quyền lựa chọn về dữ liệu</Link>
      </nav>
      <h1 style={{ fontSize: 28, fontWeight: 800, margin: 0 }}>{title}</h1>
      <p style={{ color: "var(--subtext)", fontSize: 13, marginTop: 6 }}>Cập nhật lần cuối: {updated}</p>
      <div style={{ marginTop: 24 }}>{children}</div>
    </main>
  );
}

export function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section style={{ marginTop: 28 }}>
      <h2 style={{ fontSize: 18, fontWeight: 700, margin: "0 0 8px", color: "var(--primary)" }}>{title}</h2>
      {children}
    </section>
  );
}

export function Bullets({ items }: { items: ReactNode[] }) {
  return (
    <ul style={{ margin: "8px 0", paddingLeft: 22 }}>
      {items.map((it, i) => (
        <li key={i} style={{ margin: "4px 0" }}>{it}</li>
      ))}
    </ul>
  );
}
