"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Coffee, HelpCircle, ShieldCheck, Sparkles, LogIn, Store } from "lucide-react";

export function PublicHeader() {
  const pathname = usePathname();

  const navItems = [
    { href: "/marketing", label: "Giới thiệu & Tính năng", icon: Sparkles },
    { href: "/support", label: "Hỗ trợ khách hàng", icon: HelpCircle },
    { href: "/privacy", label: "Quyền riêng tư", icon: ShieldCheck },
  ];

  return (
    <header
      style={{
        background: "var(--surface)",
        borderBottom: "1px solid var(--border)",
        position: "sticky",
        top: 0,
        zIndex: 50,
        boxShadow: "var(--shadow-sm)",
      }}
    >
      <div
        style={{
          maxWidth: 1120,
          margin: "0 auto",
          padding: "12px 16px",
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          flexWrap: "wrap",
          gap: 12,
        }}
      >
        {/* Brand Logo */}
        <Link
          href="/marketing"
          style={{
            display: "flex",
            alignItems: "center",
            gap: 10,
            textDecoration: "none",
            color: "var(--text)",
          }}
        >
          <div
            style={{
              width: 38,
              height: 38,
              borderRadius: "var(--radius-md)",
              background: "linear-gradient(135deg, var(--primary) 0%, var(--primary-dark) 100%)",
              color: "#FFFFFF",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              boxShadow: "0 2px 8px rgba(126, 41, 48, 0.25)",
            }}
          >
            <Coffee size={20} strokeWidth={2.5} />
          </div>
          <div>
            <div style={{ fontSize: 18, fontWeight: 800, letterSpacing: "-0.02em", color: "var(--primary)" }}>
              POS Trạm
            </div>
            <div style={{ fontSize: 11, color: "var(--subtext)", fontWeight: 500 }}>
              Hệ thống Quản lý F&B
            </div>
          </div>
        </Link>

        {/* Navigation Links */}
        <nav
          style={{
            display: "flex",
            alignItems: "center",
            gap: 6,
            flexWrap: "wrap",
          }}
        >
          {navItems.map((item) => {
            const Icon = item.icon;
            const isActive = pathname === item.href;
            return (
              <Link
                key={item.href}
                href={item.href}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 6,
                  padding: "8px 12px",
                  borderRadius: "var(--radius-sm)",
                  fontSize: 13,
                  fontWeight: isActive ? 700 : 500,
                  textDecoration: "none",
                  color: isActive ? "var(--primary)" : "var(--subtext)",
                  background: isActive ? "var(--primary-light)" : "transparent",
                  transition: "all 0.15s ease",
                }}
              >
                <Icon size={15} color={isActive ? "var(--primary)" : "var(--muted)"} />
                <span>{item.label}</span>
              </Link>
            );
          })}
        </nav>

        {/* Right CTA */}
        <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
          <Link
            href="/login"
            style={{
              display: "inline-flex",
              alignItems: "center",
              gap: 6,
              background: "var(--primary)",
              color: "var(--on-primary)",
              padding: "8px 16px",
              borderRadius: "var(--radius-sm)",
              fontSize: 13,
              fontWeight: 600,
              textDecoration: "none",
              boxShadow: "0 2px 6px rgba(126, 41, 48, 0.2)",
              transition: "background 0.15s ease",
            }}
          >
            <LogIn size={14} />
            <span>Đăng nhập Web</span>
          </Link>
        </div>
      </div>
    </header>
  );
}
