import type { Metadata, Viewport } from "next";
import { Inter } from "next/font/google";
import Script from "next/script";
import "./globals.css";
import { AuthProvider } from "@/lib/auth";

// "vietnamese" để dấu tiếng Việt hiển thị bằng đúng font (trước đây chỉ có "latin")
const inter = Inter({ subsets: ["latin", "vietnamese"], variable: "--font-inter", display: "swap" });

export const metadata: Metadata = {
  title: "POS Trạm • Quản Trị Hệ Thống",
  description: "Hệ thống Quản lý Vận hành & Bán hàng POS Trạm",
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#7E2930" },
    { media: "(prefers-color-scheme: dark)", color: "#141218" },
  ],
};

// Áp dụng chế độ sáng/tối đã lưu trước khi vẽ trang (tránh nháy màu)
const themeInit = `try{var t=localStorage.getItem('tram-theme');if(t==='dark'||t==='light'){document.documentElement.setAttribute('data-theme',t);}}catch(e){}`;

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="vi" className={inter.variable} suppressHydrationWarning>
      <body style={{ background: "var(--bg)", minHeight: "100vh" }}>
        <Script id="tram-theme-init" strategy="beforeInteractive">
          {themeInit}
        </Script>
        <AuthProvider>{children}</AuthProvider>
      </body>
    </html>
  );
}
