"use client";
import { useState } from "react";
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer,
} from "recharts";
import { format, startOfDay, endOfDay, startOfWeek, endOfWeek, startOfMonth, endOfMonth, startOfYear, endOfYear, subDays, subWeeks, subMonths, subYears } from "date-fns";
import { vi } from "date-fns/locale";
import { Download, TrendingUp, DollarSign, CreditCard, Banknote, Utensils, ShoppingBag } from "lucide-react";
import { exportRevenue } from "@/lib/export";
import { useDashboardData, TableItem } from "@/lib/data-context";

type TabType = "day" | "week" | "month" | "year";

function formatVND(amount: number) {
  return new Intl.NumberFormat("vi-VN", { style: "currency", currency: "VND" }).format(amount);
}

function getTableServingTotal(t: TableItem): number {
  if (!t.currentOrderJson) return 0;
  try {
    const items = typeof t.currentOrderJson === "string" ? JSON.parse(t.currentOrderJson) : t.currentOrderJson;
    if (!Array.isArray(items)) return 0;
    return items.reduce((sum: number, it: any) => {
      const qty = it.quantity || it.count || 1;
      let toppingSum = 0;
      if (Array.isArray(it.selectedToppings)) {
        toppingSum = it.selectedToppings.reduce((ts: number, tp: any) => ts + (tp.price || 0), 0);
      }
      return sum + ((Number(it.price) || 0) + toppingSum) * qty;
    }, 0);
  } catch {
    return 0;
  }
}

function getRange(tab: TabType, offset: number) {
  const now = new Date();
  switch (tab) {
    case "day":
      return { start: startOfDay(subDays(now, offset)), end: endOfDay(subDays(now, offset)), label: format(subDays(now, offset), "dd/MM/yyyy") };
    case "week":
      return { start: startOfWeek(subWeeks(now, offset), { weekStartsOn: 1 }), end: endOfWeek(subWeeks(now, offset), { weekStartsOn: 1 }), label: `Tuần ${format(subWeeks(now, offset), "w/yyyy")}` };
    case "month":
      return { start: startOfMonth(subMonths(now, offset)), end: endOfMonth(subMonths(now, offset)), label: format(subMonths(now, offset), "MM/yyyy") };
    case "year":
      return { start: startOfYear(subYears(now, offset)), end: endOfYear(subYears(now, offset)), label: format(subYears(now, offset), "yyyy") };
  }
}

export default function RevenuePage() {
  const { historyData, historyLoaded, tables } = useDashboardData();
  const loading = !historyLoaded && historyData.length === 0;
  const [tab, setTab] = useState<TabType>("day");
  const [offset, setOffset] = useState(0);

  const range = getRange(tab, offset);

  // Active serving tables (in use)
  const servingTables = tables.filter((t) => t.inUse && !t.mergedIntoTable);
  const servingCount = servingTables.length;
  const servingTotal = servingTables.reduce((sum, t) => sum + getTableServingTotal(t), 0);

  const filtered = historyData.filter((h) => {
    const ts = typeof h.timestamp === "number" ? h.timestamp : new Date(h.timestamp || 0).getTime();
    return ts >= range.start.getTime() && ts <= range.end.getTime();
  });

  const totalRevenue = filtered.reduce((s, h) => s + (Number(h.totalAmount) || 0), 0);
  const cashRevenue = filtered.filter(h => (h.paymentMethod || "").toLowerCase().includes("cash") || (h.paymentMethod || "").toLowerCase().includes("tiền mặt")).reduce((s, h) => s + (Number(h.totalAmount) || 0), 0);
  const transferRevenue = filtered.filter(h => (h.paymentMethod || "").toLowerCase().includes("transfer") || (h.paymentMethod || "").toLowerCase().includes("chuyển")).reduce((s, h) => s + (Number(h.totalAmount) || 0), 0);
  const avgPerOrder = filtered.length > 0 ? totalRevenue / filtered.length : 0;

  // Takeaway metrics
  const takeawayFiltered = filtered.filter((h) => {
    const t = (h.tableName || "").toLowerCase();
    const z = (h.zone || "").toLowerCase();
    return t.includes("mang về") || t.includes("mang ve") || z.includes("mang về") || z.includes("mang ve");
  });
  const takeawayCount = takeawayFiltered.length;
  const takeawayRevenue = takeawayFiltered.reduce((s, h) => s + (Number(h.totalAmount) || 0), 0);

  // Chart data
  let chartData: any[] = [];
  if (tab === "day") {
    // Hours
    chartData = Array.from({ length: 24 }, (_, h) => {
      const rev = filtered.filter((item) => {
        const ts = typeof item.timestamp === "number" ? item.timestamp : new Date(item.timestamp || 0).getTime();
        return new Date(ts).getHours() === h;
      }).reduce((s, item) => s + (Number(item.totalAmount) || 0), 0);
      return { label: `${h}h`, revenue: rev };
    });
  } else if (tab === "week") {
    // Days of week
    const days = ["T2", "T3", "T4", "T5", "T6", "T7", "CN"];
    chartData = Array.from({ length: 7 }, (_, i) => {
      const dayIndex = i + 1 === 7 ? 0 : i + 1;
      const rev = filtered.filter((item) => {
        const ts = typeof item.timestamp === "number" ? item.timestamp : new Date(item.timestamp || 0).getTime();
        return new Date(ts).getDay() === dayIndex;
      }).reduce((s, item) => s + (Number(item.totalAmount) || 0), 0);
      return { label: days[i], revenue: rev };
    });
  } else if (tab === "month") {
    // Days in month
    const daysInMonth = new Date(range.start.getFullYear(), range.start.getMonth() + 1, 0).getDate();
    chartData = Array.from({ length: daysInMonth }, (_, i) => {
      const day = i + 1;
      const rev = filtered.filter((item) => {
        const ts = typeof item.timestamp === "number" ? item.timestamp : new Date(item.timestamp || 0).getTime();
        return new Date(ts).getDate() === day;
      }).reduce((s, item) => s + (Number(item.totalAmount) || 0), 0);
      return { label: `${day}`, revenue: rev };
    });
  } else {
    // Months of year
    const months = ["T1", "T2", "T3", "T4", "T5", "T6", "T7", "T8", "T9", "T10", "T11", "T12"];
    chartData = months.map((m, i) => {
      const rev = filtered.filter((item) => {
        const ts = typeof item.timestamp === "number" ? item.timestamp : new Date(item.timestamp || 0).getTime();
        return new Date(ts).getMonth() === i;
      }).reduce((s, item) => s + (Number(item.totalAmount) || 0), 0);
      return { label: m, revenue: rev };
    });
  }

  const handleExport = () => {
    const rows = filtered.map((h) => ({
      date: h.timestamp ? format(new Date(typeof h.timestamp === "number" ? h.timestamp : new Date(h.timestamp || 0).getTime()), "dd/MM/yyyy HH:mm") : "",
      totalOrders: 1,
      totalRevenue: Number(h.totalAmount) || 0,
      cashRevenue: ((h.paymentMethod || "").toLowerCase().includes("cash") || (h.paymentMethod || "").toLowerCase().includes("tiền mặt")) ? Number(h.totalAmount) || 0 : 0,
      transferRevenue: ((h.paymentMethod || "").toLowerCase().includes("transfer") || (h.paymentMethod || "").toLowerCase().includes("chuyển")) ? Number(h.totalAmount) || 0 : 0,
      avgPerOrder: Number(h.totalAmount) || 0,
    }));
    exportRevenue(rows, `DoanhThu_${tab}`);
  };

  const CustomTooltip = ({ active, payload, label }: any) => {
    if (active && payload && payload.length) {
      return (
        <div style={{ background: "#FFFFFF", border: "1px solid #E6DEC8", borderRadius: "10px", padding: "10px 16px", boxShadow: "0 6px 20px rgba(0,0,0,0.08)" }}>
          <p style={{ color: "#5D5B63", fontSize: "12px", marginBottom: "4px" }}>{label}</p>
          <p style={{ color: "#7E2930", fontWeight: "700", fontSize: "14px" }}>{formatVND(payload[0].value)}</p>
        </div>
      );
    }
    return null;
  };

  const tabs: { key: TabType; label: string }[] = [
    { key: "day", label: "Ngày" },
    { key: "week", label: "Tuần" },
    { key: "month", label: "Tháng" },
    { key: "year", label: "Năm" },
  ];

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "24px" }}>
      {/* Header */}
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <div>
          <h1 className="section-title">Báo cáo Doanh thu 💰</h1>
          <p className="section-subtitle">Phân tích doanh thu & đối soát tài chính theo kỳ</p>
        </div>
        <button className="btn-primary" onClick={handleExport}>
          <Download size={16} />
          Xuất Excel
        </button>
      </div>

      {/* Tab + Navigation */}
      <div className="card" style={{ padding: "16px 20px" }}>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: "12px" }}>
          <div style={{ display: "flex", gap: "8px", flexWrap: "wrap" }}>
            {tabs.map((t) => (
              <button
                key={t.key}
                className={`tab-btn ${tab === t.key && (t.key !== "month" || (offset !== 0 && offset !== 1)) ? "active" : ""}`}
                onClick={() => { setTab(t.key); setOffset(0); }}
              >
                {t.label}
              </button>
            ))}
            <button
              className={`tab-btn ${tab === "month" && offset === 0 ? "active" : ""}`}
              onClick={() => { setTab("month"); setOffset(0); }}
            >
              📅 Tháng này
            </button>
            <button
              className={`tab-btn ${tab === "month" && offset === 1 ? "active" : ""}`}
              onClick={() => { setTab("month"); setOffset(1); }}
            >
              ⏪ Tháng trước
            </button>
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: "12px" }}>
            <button className="btn-secondary" onClick={() => setOffset(o => o + 1)} style={{ padding: "6px 12px" }}>‹ Trước</button>
            <span style={{ fontSize: "14px", fontWeight: "700", color: "#1C1A2D", minWidth: "140px", textAlign: "center" }}>
              {range.label}
            </span>
            <button className="btn-secondary" onClick={() => setOffset(o => Math.max(0, o - 1))} disabled={offset === 0} style={{ padding: "6px 12px", opacity: offset === 0 ? 0.4 : 1 }}>Sau ›</button>
          </div>
        </div>
      </div>

      {/* Summary cards */}
      <div style={{ display: "grid", gridTemplateColumns: tab === "day" ? "repeat(auto-fit, minmax(200px, 1fr))" : "repeat(auto-fit, minmax(220px, 1fr))", gap: "16px" }}>
        {[
          {
            label: "Tổng doanh thu",
            value: formatVND(totalRevenue),
            sub: `${filtered.length} hóa đơn đã thu`,
            icon: <DollarSign size={20} />,
            color: "#7E2930",
          },
          ...(tab === "day"
            ? [
                {
                  label: "Ước tính cả ngày",
                  value: formatVND(totalRevenue + servingTotal),
                  sub: "= Đã thu + Đang phục vụ",
                  icon: <TrendingUp size={20} />,
                  color: "#059669",
                },
                {
                  label: "Đang phục vụ",
                  value: formatVND(servingTotal),
                  sub: `${servingCount} bàn đang sử dụng`,
                  icon: <Utensils size={20} />,
                  color: "#2563EB",
                },
              ]
            : []),
          {
            label: "Mang về",
            value: formatVND(takeawayRevenue),
            sub: `${takeawayCount} hóa đơn mang về`,
            icon: <ShoppingBag size={20} />,
            color: "#8B5CF6",
          },
          {
            label: "Tiền mặt",
            value: formatVND(cashRevenue),
            sub: "Doanh thu tiền mặt",
            icon: <Banknote size={20} />,
            color: "#146A65",
          },
          {
            label: "Chuyển khoản (QR)",
            value: formatVND(transferRevenue),
            sub: "Chuyển khoản / QR",
            icon: <CreditCard size={20} />,
            color: "#1C4E6B",
          },
        ].map((card, i) => (
          <div key={i} className="stat-card">
            <div style={{ display: "flex", gap: "12px", alignItems: "center" }}>
              <div style={{ width: "42px", height: "42px", borderRadius: "10px", background: `${card.color}18`, display: "flex", alignItems: "center", justifyContent: "center", color: card.color, flexShrink: 0 }}>
                {card.icon}
              </div>
              <div style={{ overflow: "hidden" }}>
                <div style={{ fontSize: "17px", fontWeight: "800", color: "#1C1A2D", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{card.value}</div>
                <div style={{ fontSize: "12px", fontWeight: "600", color: "#5D5B63" }}>{card.label}</div>
                {card.sub && <div style={{ fontSize: "11px", color: "#8B8FA8" }}>{card.sub}</div>}
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* Serving Tables Details Banner for Day View */}
      {tab === "day" && servingCount > 0 && (
        <div style={{ background: "#EFF6FF", border: "1px solid #BFDBFE", borderRadius: "12px", padding: "14px 18px", display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: "12px" }}>
          <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
            <div style={{ width: "34px", height: "34px", borderRadius: "8px", background: "#DBEAFE", color: "#2563EB", display: "flex", alignItems: "center", justifyContent: "center" }}>
              <Utensils size={18} />
            </div>
            <div>
              <div style={{ fontWeight: "700", color: "#1E3A8A", fontSize: "14px" }}>
                Đang phục vụ: {servingCount} bàn chưa thanh toán
              </div>
              <div style={{ color: "#3B82F6", fontSize: "12px" }}>
                Tổng giá trị đang dùng dở: <strong style={{ color: "#1D4ED8" }}>{formatVND(servingTotal)}</strong>
              </div>
            </div>
          </div>
          <div style={{ display: "flex", gap: "8px", flexWrap: "wrap", alignItems: "center" }}>
            {servingTables.map((st) => (
              <span key={st.id || st.name} style={{ background: "#FFFFFF", border: "1px solid #93C5FD", borderRadius: "8px", padding: "4px 10px", fontSize: "12px", color: "#1E40AF", display: "flex", alignItems: "center", gap: "6px" }}>
                <span style={{ width: "6px", height: "6px", borderRadius: "50%", background: "#22C55E" }} />
                <strong>{st.name}</strong> ({st.zone}): <strong>{formatVND(getTableServingTotal(st))}</strong>
              </span>
            ))}
          </div>
        </div>
      )}

      {/* Bar chart */}
      <div className="card" style={{ padding: "20px" }}>
        <h2 style={{ fontSize: "16px", fontWeight: "700", color: "#1C1A2D", marginBottom: "20px" }}>
          Biểu đồ doanh thu
        </h2>
        <ResponsiveContainer width="100%" height={280}>
          <BarChart data={chartData}>
            <CartesianGrid strokeDasharray="3 3" stroke="#ECE5D8" />
            <XAxis dataKey="label" tick={{ fill: "#5D5B63", fontSize: 12 }} axisLine={false} tickLine={false} />
            <YAxis tick={{ fill: "#5D5B63", fontSize: 11 }} axisLine={false} tickLine={false} tickFormatter={(v) => `${(v / 1000).toFixed(0)}k`} />
            <Tooltip content={<CustomTooltip />} />
            <Bar dataKey="revenue" fill="#7E2930" radius={[6, 6, 0, 0]} maxBarSize={40} />
          </BarChart>
        </ResponsiveContainer>
      </div>

      {/* Detail table */}
      <div className="card" style={{ padding: "20px" }}>
        <h2 style={{ fontSize: "16px", fontWeight: "700", color: "#1C1A2D", marginBottom: "16px" }}>
          Chi tiết ({filtered.length} hóa đơn)
        </h2>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(4,1fr)", gap: "16px", padding: "16px", background: "#FAF7F2", border: "1px solid #ECE5D8", borderRadius: "10px", marginBottom: "16px" }}>
          <div>
            <div style={{ fontSize: "12px", color: "#5D5B63", marginBottom: "4px" }}>Tổng doanh thu</div>
            <div style={{ fontSize: "18px", fontWeight: "800", color: "#7E2930" }}>{formatVND(totalRevenue)}</div>
          </div>
          <div>
            <div style={{ fontSize: "12px", color: "#5D5B63", marginBottom: "4px" }}>Tiền mặt</div>
            <div style={{ fontSize: "18px", fontWeight: "800", color: "#146A65" }}>{formatVND(cashRevenue)}</div>
          </div>
          <div>
            <div style={{ fontSize: "12px", color: "#5D5B63", marginBottom: "4px" }}>Chuyển khoản</div>
            <div style={{ fontSize: "18px", fontWeight: "800", color: "#1C4E6B" }}>{formatVND(transferRevenue)}</div>
          </div>
          <div>
            <div style={{ fontSize: "12px", color: "#8B8FA8", marginBottom: "4px" }}>TB/Đơn</div>
            <div style={{ fontSize: "18px", fontWeight: "800", color: "#FFB627" }}>{formatVND(avgPerOrder)}</div>
          </div>
        </div>
      </div>
    </div>
  );
}
