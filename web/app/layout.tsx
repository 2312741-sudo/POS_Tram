import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "./globals.css";
import { AuthProvider } from "@/lib/auth";

const inter = Inter({ subsets: ["latin"], variable: "--font-inter" });

export const metadata: Metadata = {
  title: "POS Trạm • Quản Trị Hệ Thống",
  description: "Hệ thống Quản lý Vận hành & Bán hàng POS Trạm",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="vi" className={inter.variable}>
      <body style={{ background: "#F8F4EE", minHeight: "100vh" }}>
        <AuthProvider>{children}</AuthProvider>
      </body>
    </html>
  );
}
