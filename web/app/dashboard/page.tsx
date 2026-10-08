"use client";
import { useEffect, useState } from "react";
import { db } from "@/lib/firebase";
import { ref, onValue } from "firebase/database";
import {
  LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer,
} from "recharts";
import { format, subDays, startOfDay, endOfDay } from "date-fns";
import { vi } from "date-fns/locale";
import {
  DollarSign, ShoppingBag, LayoutGrid, Clock,
  TrendingUp, Users, Utensils,
} from "lucide-react";
import Link from "next/link";

function formatVND(amount: number) {
  return new Intl.NumberFormat("vi-VN", { style: "currency", currency: "VND" }).format(amount);
}

interface StatCard {
  title: string;
  value: string;
  subtitle: string;
  icon: React.ReactNode;
  color: string;
  bgColor: string;
}

import { useDashboardData } from "@/lib/data-context";
import { parseOrderJson, summarizeOrderLines } from "@/lib/order-math";

// Tooltip biểu đồ — khai báo ngoài component để không bị tạo lại mỗi lần render
interface ChartTooltipProps {
  active?: boolean;
  payload?: ReadonlyArray<{ value?: unknown }>;
  label?: string | number;
}

const CustomTooltip = ({ active, payload, label }: ChartTooltipProps) => {
  if (active && payload && payload.length) {
    return (
      <div
        style={{
          background: "#FFFFFF",
          border: "1px solid #E6DEC8",
          borderRadius: "10px",
          padding: "10px 16px",
          boxShadow: "0 6px 20px rgba(0,0,0,0.1)",
        }}
      >
        <p style={{ color: "#5D5B63", fontSize: "12px", marginBottom: "4px" }}>{label}</p>
        <p style={{ color: "#7E2930", fontWeight: "800", fontSize: "15px" }}>
          {formatVND(Number(payload[0].value || 0))}
        </p>
      </div>
    );
  }
  return null;
};

export default function DashboardPage() {
  const { historyData, tables: tablesData, onlineOrders, loading: ctxLoading } = useDashboardData();
  const loading = ctxLoading && tablesData.length === 0;

  const today = new Date();
  const todayStart = startOfDay(today).getTime();
  const todayEnd = endOfDay(today).getTime();

  const todayHistory = historyData.filter((h) => {
    const ts = typeof h.timestamp === "number" ? h.timestamp : new Date(h.timestamp || 0).getTime();
    return ts >= todayStart && ts <= todayEnd;
  });

  const todayRevenue = todayHistory.reduce((sum, h) => sum + (Number(h.totalAmount) || 0), 0);
  const todayOrders = todayHistory.length;
  const tablesInUse = tablesData.filter((t) => t.inUse).length;
  const pendingOnline = onlineOrders.filter((o) => o.status === "PENDING" || o.status === "pending").length;

  const todayServingTotal = tablesData
    .filter((t) => t.inUse && !t.mergedIntoTable)
    .reduce((sum, t) => {
      if (!t.currentOrderJson) return sum;
      // Cùng công thức với lúc thanh toán (size + topping - giảm giá dòng)
      const { subTotal, itemDiscounts } = summarizeOrderLines(parseOrderJson(t.currentOrderJson));
      return sum + Math.max(0, subTotal - itemDiscounts);
    }, 0);

  // 7-day revenue chart
  const chartData = Array.from({ length: 7 }, (_, i) => {
    const date = subDays(today, 6 - i);
    const dayStart = startOfDay(date).getTime();
    const dayEnd = endOfDay(date).getTime();
    const dayRevenue = historyData
      .filter((h) => {
        const ts = typeof h.timestamp === "number" ? h.timestamp : new Date(h.timestamp || 0).getTime();
        return ts >= dayStart && ts <= dayEnd;
      })
      .reduce((sum, h) => sum + (Number(h.totalAmount) || 0), 0);
    return {
      date: format(date, "dd/MM", { locale: vi }),
      revenue: dayRevenue,
    };
  });

  // Top products
  const productCountMap: { [key: string]: { name: string; count: number; total: number } } = {};
  historyData.forEach((order) => {
    if (order.items && Array.isArray(order.items)) {
      order.items.forEach((item) => {
        const key = String(item.productId || item.name);
        if (!productCountMap[key]) {
          productCountMap[key] = { name: item.name, count: 0, total: 0 };
        }
        productCountMap[key].count += item.quantity || 1;
        productCountMap[key].total += (item.price || 0) * (item.quantity || 1);
      });
    }
  });

  const topProducts = Object.values(productCountMap)
    .sort((a, b) => b.count - a.count)
    .slice(0, 5);

  const statCards: StatCard[] = [
    {
      title: "Ước tính cả ngày",
      value: formatVND(todayRevenue + todayServingTotal),
      subtitle: `${formatVND(todayRevenue)} đã thu + ${formatVND(todayServingTotal)} phục vụ`,
      icon: <TrendingUp size={22} />,
      color: "#059669",
      bgColor: "#ECFDF5",
    },
    {
      title: "Doanh thu hôm nay",
      value: formatVND(todayRevenue),
      subtitle: `${todayOrders} đơn hoàn tất`,
      icon: <DollarSign size={22} />,
      color: "#7E2930",
      bgColor: "#FBECEE",
    },
    {
      title: "Số hóa đơn",
      value: todayOrders.toString(),
      subtitle: "Hôm nay",
      icon: <ShoppingBag size={22} />,
      color: "#D97706",
      bgColor: "#FBEFD4",
    },
    {
      title: "Bàn đang dùng",
      value: `${tablesInUse}/${tablesData.length}`,
      subtitle: `${tablesInUse} bàn có khách`,
      icon: <LayoutGrid size={22} />,
      color: "#7E2930",
      bgColor: "#FFF0F2",
    },
    {
      title: "Bàn sẵn sàng",
      value: `${tablesData.length - tablesInUse}`,
      subtitle: "Bàn trống đón khách",
      icon: <Utensils size={22} />,
      color: "#146A65",
      bgColor: "#E6F4F2",
    },
  ];


  if (loading) {
    return (
      <div style={{ display: "flex", alignItems: "center", justifyContent: "center", height: "60vh" }}>
        <div className="spinner" />
      </div>
    );
  }

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "24px" }}>
      {/* Header */}
      <div>
        <h1 className="section-title" style={{ fontSize: "24px" }}>
          Tổng quan Hoạt động 📊
        </h1>
        <p className="section-subtitle">
          {format(today, "EEEE, dd MMMM yyyy", { locale: vi })} • Hệ thống POS Trạm
        </p>
      </div>

      {/* Stat Cards */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))", gap: "16px" }}>
        {statCards.map((card, i) => (
          <div key={i} className="stat-card">
            <div style={{ display: "flex", alignItems: "flex-start", justifyContent: "space-between", marginBottom: "16px" }}>
              <div
                style={{
                  width: "44px",
                  height: "44px",
                  borderRadius: "12px",
                  background: card.bgColor,
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  color: card.color,
                }}
              >
                {card.icon}
              </div>
              <TrendingUp size={16} style={{ color: "#146A65" }} />
            </div>
            <div style={{ fontSize: "22px", fontWeight: "800", color: "#1C1A2D", marginBottom: "4px" }}>
              {card.value}
            </div>
            <div style={{ fontSize: "12px", color: "#5D5B63" }}>
              <span style={{ fontWeight: "700", color: card.color }}>{card.title}</span> • {card.subtitle}
            </div>
          </div>
        ))}
      </div>

      {/* Charts & Top items */}
      <div style={{ display: "grid", gridTemplateColumns: "2fr 1fr", gap: "20px" }}>
        {/* Revenue chart */}
        <div className="card" style={{ padding: "20px" }}>
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: "20px" }}>
            <div>
              <h2 style={{ fontSize: "16px", fontWeight: "700", color: "#1C1A2D" }}>
                Doanh thu 7 ngày gần nhất
              </h2>
              <p style={{ fontSize: "12px", color: "#5D5B63" }}>Biểu đồ tăng trưởng doanh số</p>
            </div>
            <div
              style={{
                fontSize: "12px",
                fontWeight: "700",
                color: "#7E2930",
                background: "#FBECEE",
                border: "1px solid rgba(126, 41, 48, 0.2)",
                borderRadius: "6px",
                padding: "4px 10px",
              }}
            >
              7 ngày qua
            </div>
          </div>
          <div style={{ width: "100%", height: 260 }}>
            <ResponsiveContainer>
              <LineChart data={chartData}>
                <CartesianGrid strokeDasharray="3 3" stroke="#ECE5D8" />
                <XAxis dataKey="date" stroke="#5D5B63" fontSize={12} />
                <YAxis
                  stroke="#5D5B63"
                  fontSize={12}
                  tickFormatter={(v) => `${(v / 1000).toFixed(0)}k`}
                />
                <Tooltip content={<CustomTooltip />} />
                <Line
                  type="monotone"
                  dataKey="revenue"
                  stroke="#7E2930"
                  strokeWidth={3}
                  dot={{ fill: "#7E2930", strokeWidth: 2, r: 4 }}
                  activeDot={{ r: 6, fill: "#D97706" }}
                />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </div>

        {/* Top Products */}
        <div className="card" style={{ padding: "20px" }}>
          <div style={{ marginBottom: "16px" }}>
            <h2 style={{ fontSize: "16px", fontWeight: "700", color: "#1C1A2D" }}>
              Món bán chạy 🔥
            </h2>
            <p style={{ fontSize: "12px", color: "#5D5B63" }}>Theo số lượng bán ra</p>
          </div>
          {topProducts.length === 0 ? (
            <div style={{ textAlign: "center", color: "#5D5B63", padding: "40px 0", fontSize: "13px" }}>
              Chưa có dữ liệu giao dịch
            </div>
          ) : (
            <div style={{ display: "flex", flexDirection: "column", gap: "12px" }}>
              {topProducts.map((p, i) => (
                <div
                  key={i}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "space-between",
                    padding: "10px 12px",
                    background: "#FAF7F2",
                    borderRadius: "10px",
                    border: "1px solid #ECE5D8",
                  }}
                >
                  <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
                    <div
                      style={{
                        width: "24px",
                        height: "24px",
                        borderRadius: "6px",
                        background: i === 0 ? "#7E2930" : i === 1 ? "#D97706" : "#E6DEC8",
                        color: i < 2 ? "white" : "#1C1A2D",
                        fontSize: "12px",
                        fontWeight: "700",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                      }}
                    >
                      {i + 1}
                    </div>
                    <div>
                      <div style={{ fontSize: "13px", fontWeight: "700", color: "#1C1A2D" }}>
                        {p.name}
                      </div>
                      <div style={{ fontSize: "11px", color: "#5D5B63" }}>
                        {p.count} lượt gọi
                      </div>
                    </div>
                  </div>
                  <div style={{ fontSize: "13px", fontWeight: "700", color: "#7E2930" }}>
                    {formatVND(p.total)}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {/* Live tables overview */}
      <div className="card" style={{ padding: "20px" }}>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: "16px" }}>
          <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
            <LayoutGrid size={18} style={{ color: "#7E2930" }} />
            <h2 style={{ fontSize: "16px", fontWeight: "700", color: "#1C1A2D" }}>
              Trạng thái Phòng / Bàn trực tiếp (Live Sync)
            </h2>
            <div
              style={{
                width: "8px",
                height: "8px",
                borderRadius: "50%",
                background: "#146A65",
                boxShadow: "0 0 8px rgba(20,106,101,0.6)",
                marginLeft: "4px",
              }}
            />
          </div>
          <Link
            href="/dashboard/tables"
            style={{
              fontSize: "13px",
              fontWeight: "700",
              color: "#7E2930",
              textDecoration: "none",
            }}
          >
            Xem đầy đủ sơ đồ phòng bàn →
          </Link>
        </div>
        {tablesData.length === 0 ? (
          <div style={{ textAlign: "center", color: "#5D5B63", padding: "32px" }}>Không có dữ liệu bàn</div>
        ) : (
          <div
            style={{
              display: "grid",
              gridTemplateColumns: "repeat(auto-fill, minmax(130px, 1fr))",
              gap: "12px",
            }}
          >
            {tablesData.map((table, i) => (
              <Link
                key={table.id + "-" + i}
                href="/dashboard/tables"
                style={{
                  textDecoration: "none",
                  borderRadius: "12px",
                  padding: "12px 10px",
                  border: table.inUse ? "2px solid #7E2930" : "1px solid #E6DEC8",
                  background: table.inUse ? "#FFF0F2" : "#FFFFFF",
                  textAlign: "center",
                  boxShadow: table.inUse ? "0 4px 12px rgba(126, 41, 48, 0.15)" : "none",
                  display: "block",
                  transition: "transform 0.15s",
                }}
              >
                <div style={{ fontSize: "14px", fontWeight: "800", color: table.inUse ? "#7E2930" : "#1C1A2D", marginBottom: "2px" }}>
                  {table.name || table.id}
                </div>
                {table.zone && (
                  <div style={{ fontSize: "11px", color: "#5D5B63", marginBottom: "6px" }}>
                    {table.zone}
                  </div>
                )}
                <span
                  className={table.inUse ? "badge badge-danger" : "badge badge-success"}
                  style={{ fontSize: "11px", padding: "2px 8px" }}
                >
                  {table.inUse ? "Có khách" : "Trống"}
                </span>
              </Link>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
