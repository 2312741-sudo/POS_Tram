"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useAuth } from "@/lib/auth";
import {
  LayoutDashboard,
  TrendingUp,
  ShoppingBag,
  Package,
  Users,
  Shield,
  BarChart3,
  LogOut,
  LayoutGrid,
  Store,
  ClipboardCheck,
  Receipt,
  ShoppingCart,
} from "lucide-react";

const navItems = [
  { href: "/dashboard", label: "Tổng quan", icon: LayoutDashboard },
  { href: "/dashboard/end-of-day", label: "Báo cáo Cuối ngày", icon: ClipboardCheck },
  { href: "/dashboard/shifts", label: "Phiếu Bàn Giao Ca", icon: Receipt },
  { href: "/dashboard/product-sales", label: "Hàng hoá Bán ra", icon: ShoppingCart },
  { href: "/dashboard/stores", label: "Hệ thống Chi nhánh", icon: Store },
  { href: "/dashboard/tables", label: "Sơ đồ Phòng/Bàn", icon: LayoutGrid },
  { href: "/dashboard/orders", label: "Giao dịch / Hóa đơn", icon: ShoppingBag },
  { href: "/dashboard/revenue", label: "Báo cáo Doanh thu", icon: TrendingUp },
  { href: "/dashboard/products", label: "Thực đơn & Sản phẩm", icon: Package },
  { href: "/dashboard/users", label: "Nhân viên & Ca trực", icon: Users },
  { href: "/dashboard/audit", label: "Nhật ký Kiểm soát", icon: Shield },
  { href: "/dashboard/analytics", label: "Phân tích Kinh doanh", icon: BarChart3 },
];

export default function Sidebar() {
  const pathname = usePathname();
  const { user, logout } = useAuth();

  const isActive = (href: string) => {
    if (href === "/dashboard") return pathname === "/dashboard";
    return pathname.startsWith(href);
  };

  return (
    <aside
      style={{
        width: "250px",
        height: "100vh",
        background: "linear-gradient(180deg, #7E2930 0%, #5C1F24 100%)",
        borderRight: "1px solid rgba(255, 255, 255, 0.1)",
        display: "flex",
        flexDirection: "column",
        position: "fixed",
        left: 0,
        top: 0,
        zIndex: 20,
        overflow: "hidden",
        boxShadow: "4px 0 20px rgba(0, 0, 0, 0.1)",
      }}
    >
      {/* Brand Header */}
      <div
        style={{
          padding: "20px 20px",
          borderBottom: "1px solid rgba(255, 255, 255, 0.12)",
          display: "flex",
          alignItems: "center",
          gap: "12px",
        }}
      >
        <div
          style={{
            width: "42px",
            height: "42px",
            borderRadius: "12px",
            background: "#FFFFFF",
            padding: "3px",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            flexShrink: 0,
            boxShadow: "0 4px 12px rgba(0, 0, 0, 0.2)",
            overflow: "hidden",
          }}
        >
          <img src="/logo.jpg" alt="Trạm Logo" style={{ width: "100%", height: "100%", objectFit: "cover", borderRadius: "9px" }} />
        </div>
        <div>
          <div
            style={{
              fontSize: "17px",
              fontWeight: "800",
              color: "#FFFFFF",
              letterSpacing: "0.02em",
              lineHeight: 1.2,
            }}
          >
            POS TRẠM
          </div>
          <div style={{ fontSize: "11px", color: "rgba(255, 255, 255, 0.7)", fontWeight: "500", marginTop: "2px" }}>
            Hệ thống Quản lý Vận hành
          </div>
        </div>
      </div>

      {/* User Info */}
      <div
        style={{
          padding: "14px 20px",
          borderBottom: "1px solid rgba(255, 255, 255, 0.1)",
          background: "rgba(0, 0, 0, 0.12)",
          display: "flex",
          alignItems: "center",
          gap: "12px",
        }}
      >
        <div
          style={{
            width: "36px",
            height: "36px",
            borderRadius: "50%",
            background: "#FFFFFF",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontSize: "14px",
            fontWeight: "800",
            color: "#7E2930",
            flexShrink: 0,
            boxShadow: "0 2px 6px rgba(0, 0, 0, 0.2)",
          }}
        >
          {user?.fullName?.[0]?.toUpperCase() || "M"}
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div
            style={{
              fontSize: "13px",
              fontWeight: "700",
              color: "#FFFFFF",
              overflow: "hidden",
              textOverflow: "ellipsis",
              whiteSpace: "nowrap",
            }}
          >
            {user?.fullName || "Quản Lý Ca"}
          </div>
          <div
            style={{
              display: "inline-flex",
              alignItems: "center",
              gap: "4px",
              fontSize: "10px",
              fontWeight: "700",
              color: "#FFFFFF",
              background: "rgba(255, 255, 255, 0.2)",
              borderRadius: "4px",
              padding: "1px 6px",
              marginTop: "2px",
            }}
          >
            {user?.role === "OWNER" ? "👑 CHỦ QUÁN" : "⭐ QUẢN LÝ"}
          </div>
        </div>
      </div>

      {/* Navigation */}
      <nav style={{ flex: 1, padding: "16px 12px", overflowY: "auto", display: "flex", flexDirection: "column", gap: "5px" }}>
        <div style={{ fontSize: "10px", fontWeight: "700", color: "rgba(255, 255, 255, 0.5)", textTransform: "uppercase", letterSpacing: "0.08em", padding: "4px 8px", marginBottom: "4px" }}>
          DANH MỤC QUẢN TRỊ
        </div>
        {navItems.map((item) => {
          const Icon = item.icon;
          const active = isActive(item.href);
          return (
            <Link
              key={item.href}
              href={item.href}
              className={`sidebar-link ${active ? "active" : ""}`}
            >
              <Icon
                size={18}
                style={{
                  flexShrink: 0,
                  color: active ? "#7E2930" : "rgba(255, 255, 255, 0.75)",
                }}
              />
              <span>{item.label}</span>
              {active && (
                <div
                  style={{
                    marginLeft: "auto",
                    width: "7px",
                    height: "7px",
                    borderRadius: "50%",
                    background: "#7E2930",
                  }}
                />
              )}
            </Link>
          );
        })}
      </nav>

      {/* Logout */}
      <div style={{ padding: "14px", borderTop: "1px solid rgba(255, 255, 255, 0.1)", background: "rgba(0,0,0,0.1)" }}>
        <button
          onClick={logout}
          style={{
            width: "100%",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            gap: "10px",
            padding: "10px 14px",
            borderRadius: "10px",
            background: "rgba(255, 255, 255, 0.1)",
            border: "1px solid rgba(255, 255, 255, 0.15)",
            color: "#FFFFFF",
            cursor: "pointer",
            fontSize: "13px",
            fontWeight: "600",
            transition: "all 0.2s",
          }}
          onMouseEnter={(e) => {
            (e.currentTarget as HTMLButtonElement).style.background = "rgba(255, 255, 255, 0.2)";
          }}
          onMouseLeave={(e) => {
            (e.currentTarget as HTMLButtonElement).style.background = "rgba(255, 255, 255, 0.1)";
          }}
        >
          <LogOut size={16} />
          Đăng xuất hệ thống
        </button>
      </div>
    </aside>
  );
}
