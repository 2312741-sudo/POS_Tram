"use client";
import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useAuth } from "@/lib/auth";
import Sidebar from "@/components/Sidebar";
import { DashboardDataProvider, useDashboardData } from "@/lib/data-context";
import { Store, Settings, Menu, Moon, Sun } from "lucide-react";

type ThemeMode = "light" | "dark";

/** Nút chuyển giao diện sáng/tối (lưu vào localStorage, áp dụng qua data-theme). */
function ThemeToggle() {
  const [mode, setMode] = useState<ThemeMode | null>(null);

  useEffect(() => {
    const attr = document.documentElement.getAttribute("data-theme");
    const current: ThemeMode =
      attr === "dark" || attr === "light"
        ? attr
        : window.matchMedia("(prefers-color-scheme: dark)").matches
          ? "dark"
          : "light";
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setMode(current);
  }, []);

  const toggle = () => {
    const next: ThemeMode = mode === "dark" ? "light" : "dark";
    document.documentElement.setAttribute("data-theme", next);
    try {
      localStorage.setItem("tram-theme", next);
    } catch {
      /* bỏ qua khi trình duyệt chặn localStorage */
    }
    setMode(next);
  };

  const label = mode === "dark" ? "Chuyển sang giao diện sáng" : "Chuyển sang giao diện tối";
  return (
    <button type="button" className="btn-icon" onClick={toggle} aria-label={label} title={label}>
      {mode === "dark" ? <Sun size={17} /> : <Moon size={17} />}
    </button>
  );
}

function HeaderBar({ onOpenMenu }: { onOpenMenu: () => void }) {
  const { user } = useAuth();
  const { stores, currentStoreCode, setCurrentStoreCode } = useDashboardData();

  return (
    <header
      className="app-header"
      style={{
        height: "64px",
        background: "var(--surface)",
        borderBottom: "1px solid var(--border)",
        display: "flex", flexWrap: "wrap",
        alignItems: "center",
        justifyContent: "space-between",
        position: "sticky",
        top: 0,
        zIndex: 10,
        boxShadow: "0 1px 4px rgba(28, 26, 45, 0.03)",
        gap: "12px",
      }}
    >
      <button type="button" className="btn-icon mobile-only" onClick={onOpenMenu} aria-label="Mở menu điều hướng">
        <Menu size={18} />
      </button>

      {/* Left: Connection status */}
      <div className="desktop-only" style={{ display: "flex", alignItems: "center", gap: "10px", flexShrink: 0 }}>
        <div
          style={{
            width: "9px",
            height: "9px",
            borderRadius: "50%",
            background: "var(--success)",
            boxShadow: "0 0 8px rgba(20,106,101,0.6)",
          }}
        />
        <span style={{ fontSize: "13px", fontWeight: "600", color: "var(--success)" }}>
          Hệ thống Realtime POS Trạm
        </span>
      </div>

      {/* Center: Branch Selector */}
      <div style={{ display: "flex", alignItems: "center", gap: "10px", flex: 1, minWidth: 0, maxWidth: "520px", justifyContent: "center" }}>
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: "8px",
            background: "var(--bg)",
            border: "1px solid var(--border)",
            borderRadius: "10px",
            padding: "4px 10px",
            width: "100%",
            maxWidth: "380px",
            minWidth: 0,
          }}
        >
          <Store size={16} style={{ color: "var(--primary)", flexShrink: 0 }} aria-hidden="true" />
          <select
            aria-label="Chọn chi nhánh"
            value={currentStoreCode}
            onChange={(e) => setCurrentStoreCode(e.target.value)}
            style={{
              background: "transparent",
              border: "none",
              outline: "none",
              fontSize: "13px",
              fontWeight: "700",
              color: "var(--text)",
              width: "100%",
              minWidth: 0,
              minHeight: "32px",
              cursor: "pointer",
            }}
          >
            <option value="ALL">🌐 Tất cả chi nhánh (Toàn hệ thống)</option>
            {stores.map((s) => (
              <option key={s.storeCode} value={s.storeCode}>
                🏪 {s.storeCode} - {s.storeName}
              </option>
            ))}
          </select>
        </div>

        <Link
          href="/dashboard/stores"
          className="hide-sm"
          style={{
            display: "inline-flex",
            alignItems: "center",
            gap: "4px",
            fontSize: "12px",
            fontWeight: "600",
            color: "var(--primary)",
            padding: "6px 10px",
            borderRadius: "8px",
            background: "var(--primary-light)",
            border: "1px solid color-mix(in srgb, var(--primary) 35%, transparent)",
            textDecoration: "none",
            whiteSpace: "nowrap",
          }}
          title="Quản lý danh sách chi nhánh"
        >
          <Settings size={13} />
          Chi nhánh ({stores.length})
        </Link>
      </div>

      {/* Right: User Profile */}
      <div style={{ display: "flex", alignItems: "center", gap: "12px", flexShrink: 0 }}>
        <ThemeToggle />
        <div
          aria-hidden="true"
          style={{
            width: "36px",
            height: "36px",
            borderRadius: "50%",
            background: "linear-gradient(135deg, var(--primary), var(--primary-dark))",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontSize: "14px",
            fontWeight: "700",
            color: "white",
            boxShadow: "0 2px 6px rgba(126, 41, 48, 0.25)",
          }}
        >
          {user?.fullName?.[0]?.toUpperCase() || "M"}
        </div>
        <div className="desktop-only">
          <div style={{ fontSize: "14px", fontWeight: "700", color: "var(--text)", maxWidth: 180, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
            {user?.fullName}
          </div>
          <div style={{ fontSize: "12px", fontWeight: "600", color: "var(--primary)" }}>
            {user?.role}
          </div>
        </div>
      </div>
    </header>
  );
}

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const { user, loading } = useAuth();
  const router = useRouter();
  const [menuOpen, setMenuOpen] = useState(false);
  const closeMenu = useCallback(() => setMenuOpen(false), []);

  useEffect(() => {
    if (!loading && !user) {
      router.replace("/login");
    }
  }, [user, loading, router]);

  if (loading) {
    return (
      <div
        style={{
          minHeight: "100vh",
          background: "var(--bg)",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        <div className="spinner" />
      </div>
    );
  }

  if (!user) return null;

  return (
    <DashboardDataProvider>
      <div style={{ display: "flex", minHeight: "100vh", background: "var(--bg)" }}>
        <Sidebar open={menuOpen} onClose={closeMenu} />
        <div
          className="app-main"
          style={{
            flex: 1,
            display: "flex",
            flexDirection: "column",
            overflow: "hidden",
          }}
        >
          {/* Top header bar with store switcher */}
          <HeaderBar onOpenMenu={() => setMenuOpen(true)} />

          {/* Page content */}
          <main
            id="main-content"
            className="app-content"
            style={{
              flex: 1,
              minWidth: 0,
              overflowY: "auto",
            }}
          >
            {children}
          </main>
        </div>
      </div>
    </DashboardDataProvider>
  );
}
