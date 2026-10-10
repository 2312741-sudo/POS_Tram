"use client";
import React, { useEffect } from "react";
import Link from "next/link";
import Image from "next/image";
import { usePathname } from "next/navigation";
import { useAuth, canAccessRoute } from "@/lib/auth";
import {
  LayoutDashboard,
  TrendingUp,
  ShoppingBag,
  Package,
  Users,
  Shield,
  BarChart3,
  LogOut,
  X,
  LayoutGrid,
  Store,
  ClipboardCheck,
  Receipt,
  ShoppingCart,
  Warehouse,
  Tag,
  BadgePercent,
} from "lucide-react";

const navItems = [
  { href: "/dashboard", label: "Tổng quan", icon: LayoutDashboard },
  { href: "/dashboard/end-of-day", label: "Báo cáo Cuối ngày", icon: ClipboardCheck },
  { href: "/dashboard/shifts", label: "Phiếu Bàn Giao Ca", icon: Receipt },
  { href: "/dashboard/customers", label: "Khách hàng CRM (KMT)", icon: Users },
  { href: "/dashboard/product-sales", label: "Hàng hoá Bán ra", icon: ShoppingCart },
  { href: "/dashboard/stores", label: "Hệ thống Chi nhánh", icon: Store },
  { href: "/dashboard/tables", label: "Sơ đồ Phòng/Bàn", icon: LayoutGrid },
  { href: "/dashboard/orders", label: "Giao dịch / Hóa đơn", icon: ShoppingBag },
  { href: "/dashboard/revenue", label: "Báo cáo Doanh thu", icon: TrendingUp },
  { href: "/dashboard/products", label: "Thực đơn & Sản phẩm", icon: Package },
  { href: "/dashboard/inventory", label: "Kho hàng & NVL", icon: Warehouse },
  { href: "/dashboard/promotions", label: "Khuyến mãi & Voucher", icon: Tag },
  { href: "/dashboard/reports/promotions", label: "Báo cáo khuyến mãi", icon: BadgePercent },
  { href: "/dashboard/reports/inventory", label: "Báo cáo Kho hàng", icon: ClipboardCheck },
  { href: "/dashboard/users", label: "Nhân viên và phân quyền", icon: Users },
  { href: "/dashboard/audit", label: "Nhật ký Kiểm soát", icon: Shield },
  { href: "/dashboard/analytics", label: "Phân tích Kinh doanh", icon: BarChart3 },
];

type SidebarProps = {
  /** Trạng thái mở trên màn hình < 1024px (off-canvas) */
  open?: boolean;
  onClose?: () => void;
};

export default function Sidebar({ open = false, onClose }: SidebarProps) {
  const pathname = usePathname();
  const { user, logout, storeCode } = useAuth();

  // Đóng menu trên điện thoại sau khi chuyển trang
  useEffect(() => {
    onClose?.();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pathname]);

  // Phím Esc để đóng menu
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose?.();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onClose]);

  const isActive = (href: string) => {
    if (href === "/dashboard") return pathname === "/dashboard";
    return pathname.startsWith(href);
  };

  const getRoleLabel = () => {
    if (!user) return "Nhân viên";
    if (user.isRootOwner || (user.roleId || user.role || "").toUpperCase().includes("OWNER")) {
      return "👑 CHỦ QUÁN";
    }
    const r = (user.roleId || user.role || "").toUpperCase();
    if (r.includes("MANAGER_1")) return "⭐ QUẢN LÝ 1";
    if (r.includes("MANAGER_2") || r.includes("MANAGER")) return "⭐ QUẢN LÝ 2";
    return "👤 NHÂN VIÊN";
  };

  // Lọc danh mục hiển thị theo quyền người dùng (RBAC)
  const visibleNavItems = navItems.filter((item) => canAccessRoute(user, item.href));

  return (
    <>
    <div className={`sidebar-backdrop ${open ? "open" : ""}`} onClick={onClose} aria-hidden="true" />
    <aside
      className={`app-sidebar ${open ? "open" : ""}`}
      aria-label="Điều hướng quản trị"
      style={{
        width: "250px",
        maxWidth: "85vw",
        height: "100dvh",
        // Màu thương hiệu cố định (không đổi theo chế độ tối)
        background: "linear-gradient(180deg, var(--primary) 0%, var(--primary-dark) 100%)",
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
          padding: "20px",
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
            background: "var(--surface)",
            padding: "3px",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            flexShrink: 0,
            boxShadow: "0 4px 12px rgba(0, 0, 0, 0.2)",
            overflow: "hidden",
            position: "relative",
          }}
        >
          <Image
            src="/logo.jpg"
            alt="Trạm Logo"
            width={36}
            height={36}
            style={{ objectFit: "cover", borderRadius: "9px" }}
          />
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
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
        <button
          type="button"
          className="mobile-only"
          onClick={onClose}
          aria-label="Đóng menu"
          style={{
            width: 36,
            height: 36,
            alignItems: "center",
            justifyContent: "center",
            borderRadius: 10,
            border: "1px solid rgba(255,255,255,0.2)",
            background: "rgba(255,255,255,0.1)",
            color: "#FFFFFF",
          }}
        >
          <X size={18} />
        </button>
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
            background: "var(--surface)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontSize: "14px",
            fontWeight: "800",
            color: "var(--primary)",
            flexShrink: 0,
            boxShadow: "0 2px 6px rgba(0, 0, 0, 0.2)",
          }}
        >
          {user?.fullName?.[0]?.toUpperCase() || user?.username?.[0]?.toUpperCase() || "M"}
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
            {user?.fullName || user?.username || "Quản Trị Viên"}
          </div>
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: "6px",
              marginTop: "2px",
              flexWrap: "wrap",
            }}
          >
            <span
              style={{
                fontSize: "10px",
                fontWeight: "700",
                color: "#FFFFFF",
                background: "rgba(255, 255, 255, 0.2)",
                borderRadius: "4px",
                padding: "1px 6px",
              }}
            >
              {getRoleLabel()}
            </span>
            <span
              style={{
                fontSize: "10px",
                fontWeight: "700",
                color: "#FFEAA7",
                background: "rgba(0, 0, 0, 0.25)",
                borderRadius: "4px",
                padding: "1px 5px",
              }}
            >
              {user?.storeCode || storeCode || "TRAM01"}
            </span>
          </div>
        </div>
      </div>

      {/* Navigation */}
      <nav
        style={{
          flex: 1,
          padding: "16px 12px",
          overflowY: "auto",
          display: "flex",
          flexDirection: "column",
          gap: "5px",
        }}
      >
        <div
          style={{
            fontSize: "10px",
            fontWeight: "700",
            color: "rgba(255, 255, 255, 0.5)",
            textTransform: "uppercase",
            letterSpacing: "0.08em",
            padding: "4px 8px",
            marginBottom: "4px",
          }}
        >
          DANH MỤC QUẢN TRỊ
        </div>
        {visibleNavItems.map((item) => {
          const Icon = item.icon;
          const active = isActive(item.href);
          return (
            <Link
              key={item.href}
              href={item.href}
              className={`sidebar-link ${active ? "active" : ""}`}
              aria-current={active ? "page" : undefined}
            >
              <Icon
                size={18}
                style={{
                  flexShrink: 0,
                  color: active ? "var(--primary)" : "rgba(255, 255, 255, 0.8)",
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
                    background: "var(--primary)",
                  }}
                />
              )}
            </Link>
          );
        })}
      </nav>

      {/* Logout */}
      <div
        style={{
          padding: "14px",
          borderTop: "1px solid rgba(255, 255, 255, 0.1)",
          background: "rgba(0,0,0,0.1)",
        }}
      >
        <button
          type="button"
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
    </>
  );
}
