"use client";
import { useEffect } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useAuth } from "@/lib/auth";
import Sidebar from "@/components/Sidebar";
import { DashboardDataProvider, useDashboardData } from "@/lib/data-context";
import { Store, ChevronRight, Settings } from "lucide-react";

function HeaderBar() {
  const { user } = useAuth();
  const { stores, currentStoreCode, setCurrentStoreCode } = useDashboardData();

  return (
    <header
      style={{
        height: "64px",
        background: "#FFFFFF",
        borderBottom: "1px solid #E6DEC8",
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        padding: "0 28px",
        position: "sticky",
        top: 0,
        zIndex: 10,
        boxShadow: "0 1px 4px rgba(28, 26, 45, 0.03)",
        gap: "16px",
      }}
    >
      {/* Left: Connection status */}
      <div style={{ display: "flex", alignItems: "center", gap: "10px", flexShrink: 0 }}>
        <div
          style={{
            width: "9px",
            height: "9px",
            borderRadius: "50%",
            background: "#146A65",
            boxShadow: "0 0 8px rgba(20,106,101,0.6)",
          }}
        />
        <span style={{ fontSize: "13px", fontWeight: "600", color: "#146A65" }}>
          Hệ thống Realtime POS Trạm
        </span>
      </div>

      {/* Center: Branch Selector */}
      <div style={{ display: "flex", alignItems: "center", gap: "10px", flex: 1, maxWidth: "520px", justifyContent: "center" }}>
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: "8px",
            background: "#F8F4EE",
            border: "1px solid #E6DEC8",
            borderRadius: "10px",
            padding: "4px 10px",
            width: "100%",
            maxWidth: "380px",
          }}
        >
          <Store size={16} style={{ color: "#7E2930", flexShrink: 0 }} />
          <select
            value={currentStoreCode}
            onChange={(e) => setCurrentStoreCode(e.target.value)}
            style={{
              background: "transparent",
              border: "none",
              outline: "none",
              fontSize: "13px",
              fontWeight: "700",
              color: "#1C1A2D",
              width: "100%",
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
          style={{
            display: "inline-flex",
            alignItems: "center",
            gap: "4px",
            fontSize: "12px",
            fontWeight: "600",
            color: "#7E2930",
            padding: "6px 10px",
            borderRadius: "8px",
            background: "#FBECEE",
            border: "1px solid #E8A2A8",
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
      <div style={{ display: "flex", alignItems: "center", gap: "14px", flexShrink: 0 }}>
        <div
          style={{
            width: "36px",
            height: "36px",
            borderRadius: "50%",
            background: "linear-gradient(135deg, #7E2930, #5C1F24)",
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
        <div>
          <div style={{ fontSize: "14px", fontWeight: "700", color: "#1C1A2D" }}>
            {user?.fullName}
          </div>
          <div style={{ fontSize: "12px", fontWeight: "600", color: "#7E2930" }}>
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
          background: "#F8F4EE",
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
      <div style={{ display: "flex", minHeight: "100vh", background: "#F8F4EE" }}>
        <Sidebar />
        <div
          style={{
            flex: 1,
            display: "flex",
            flexDirection: "column",
            overflow: "hidden",
            marginLeft: "250px",
          }}
        >
          {/* Top header bar with store switcher */}
          <HeaderBar />

          {/* Page content */}
          <main
            style={{
              flex: 1,
              padding: "28px",
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
