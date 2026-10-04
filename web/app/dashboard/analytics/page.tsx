"use client";
import { useMemo, useState } from "react";
import {
  PieChart, Pie, Cell, Tooltip, ResponsiveContainer,
  BarChart, Bar, XAxis, YAxis, CartesianGrid,
} from "recharts";
import { TrendingUp, PieChart as PieIcon, BarChart2, MapPin } from "lucide-react";
import { useDashboardData } from "@/lib/data-context";

function formatVND(amount: number) {
  return new Intl.NumberFormat("vi-VN", { style: "currency", currency: "VND" }).format(amount);
}

const COLORS = ["#7E2930", "#D97706", "#146A65", "#1C4E6B", "#8B5CF6", "#EC4899", "#14B8A6", "#F59E0B", "#B4232C", "#6366F1"];

export default function AnalyticsPage() {
  const { historyData, historyLoaded } = useDashboardData();
  const loading = !historyLoaded && historyData.length === 0;
  const [period, setPeriod] = useState<"ALL" | "TODAY" | "YESTERDAY" | "7DAYS" | "THIS_MONTH" | "LAST_MONTH">("THIS_MONTH");

  const filteredHistory = useMemo(() => {
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());

    return historyData.filter((h) => {
      if (period === "ALL") return true;
      const dt = new Date(typeof h.timestamp === "number" ? h.timestamp : new Date(h.timestamp || 0).getTime());
      if (period === "TODAY") {
        return dt.getFullYear() === now.getFullYear() && dt.getMonth() === now.getMonth() && dt.getDate() === now.getDate();
      }
      if (period === "YESTERDAY") {
        const yest = new Date(today);
        yest.setDate(yest.getDate() - 1);
        return dt.getFullYear() === yest.getFullYear() && dt.getMonth() === yest.getMonth() && dt.getDate() === yest.getDate();
      }
      if (period === "7DAYS") {
        const d7 = new Date(today);
        d7.setDate(d7.getDate() - 7);
        return dt >= d7 && dt <= now;
      }
      if (period === "THIS_MONTH") {
        return dt.getFullYear() === now.getFullYear() && dt.getMonth() === now.getMonth();
      }
      if (period === "LAST_MONTH") {
        const lm = new Date(now.getFullYear(), now.getMonth() - 1, 1);
        return dt.getFullYear() === lm.getFullYear() && dt.getMonth() === lm.getMonth();
      }
      return true;
    });
  }, [historyData, period]);

  // Payment method distribution
  const paymentData = useMemo(() => {
    const cash = filteredHistory.filter(h => (h.paymentMethod || "").toLowerCase().includes("cash") || (h.paymentMethod || "").toLowerCase().includes("tiền mặt")).length;
    const transfer = filteredHistory.filter(h => (h.paymentMethod || "").toLowerCase().includes("transfer") || (h.paymentMethod || "").toLowerCase().includes("chuyển")).length;
    const other = filteredHistory.length - cash - transfer;
    return [
      { name: "Tiền mặt", value: cash, color: "#22C55E" },
      { name: "Chuyển khoản", value: transfer, color: "#3B82F6" },
      { name: "Khác", value: other > 0 ? other : 0, color: "#FFB627" },
    ].filter(d => d.value > 0);
  }, [filteredHistory]);

  // Revenue by hour
  const hourlyData = useMemo(() => {
    return Array.from({ length: 24 }, (_, h) => {
      const rev = filteredHistory.filter(item => {
        const ts = typeof item.timestamp === "number" ? item.timestamp : new Date(item.timestamp || 0).getTime();
        return new Date(ts).getHours() === h;
      }).reduce((s, item) => s + (Number(item.totalAmount) || 0), 0);
      return { hour: `${h}h`, revenue: rev };
    });
  }, [filteredHistory]);

  // Top 10 best-selling products
  const topProducts = useMemo(() => {
    const productSales: Record<string, { name: string; qty: number; revenue: number }> = {};
    filteredHistory.forEach((h) => {
      try {
        const items = h.items || (typeof h.itemsJson === "string" ? JSON.parse(h.itemsJson) : h.itemsJson);
        if (Array.isArray(items)) {
          items.forEach((item: any) => {
            const name = item.name || item.productName || "Unknown";
            if (!productSales[name]) productSales[name] = { name, qty: 0, revenue: 0 };
            productSales[name].qty += Number(item.quantity || item.qty || 1);
            productSales[name].revenue += Number(item.price || 0) * Number(item.quantity || item.qty || 1);
          });
        }
      } catch {}
    });
    return Object.values(productSales).sort((a, b) => b.qty - a.qty).slice(0, 10);
  }, [filteredHistory]);

  // Revenue by zone
  const zoneData = useMemo(() => {
    const zoneMap: Record<string, number> = {};
    filteredHistory.forEach((h) => {
      const zone = h.tableZone || h.zone || "Không xác định";
      zoneMap[zone] = (zoneMap[zone] || 0) + (Number(h.totalAmount) || 0);
    });
    return Object.entries(zoneMap).map(([zone, revenue]) => ({ zone, revenue })).sort((a, b) => b.revenue - a.revenue);
  }, [filteredHistory]);

  const CustomTooltip = ({ active, payload, label }: any) => {
    if (active && payload && payload.length) {
      return (
        <div style={{ background: "#FFFFFF", border: "1px solid #E6DEC8", borderRadius: "10px", padding: "10px 16px", boxShadow: "0 6px 20px rgba(0,0,0,0.08)" }}>
          <p style={{ color: "#5D5B63", fontSize: "12px", marginBottom: "4px" }}>{label || payload[0].name}</p>
          <p style={{ color: "#7E2930", fontWeight: "700", fontSize: "14px" }}>
            {typeof payload[0].value === "number" && payload[0].value > 1000
              ? formatVND(payload[0].value)
              : payload[0].value}
          </p>
        </div>
      );
    }
    return null;
  };

  const PieCustomTooltip = ({ active, payload }: any) => {
    if (active && payload && payload.length) {
      return (
        <div style={{ background: "#FFFFFF", border: "1px solid #E6DEC8", borderRadius: "10px", padding: "10px 16px", boxShadow: "0 6px 20px rgba(0,0,0,0.08)" }}>
          <p style={{ color: payload[0].payload.color, fontWeight: "700", fontSize: "14px" }}>{payload[0].name}</p>
          <p style={{ color: "#1C1A2D", fontSize: "13px" }}>{payload[0].value} đơn</p>
        </div>
      );
    }
    return null;
  };

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
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: "12px" }}>
        <div>
          <h1 className="section-title">Phân tích Chi tiết 📈</h1>
          <p className="section-subtitle">Tổng quan {filteredHistory.length} giao dịch trong kỳ</p>
        </div>
        <div style={{ display: "flex", gap: "6px", flexWrap: "wrap" }}>
          {[
            { id: "TODAY", label: "Hôm nay" },
            { id: "YESTERDAY", label: "Hôm qua" },
            { id: "7DAYS", label: "7 ngày" },
            { id: "THIS_MONTH", label: "Tháng này" },
            { id: "LAST_MONTH", label: "Tháng trước" },
            { id: "ALL", label: "Tất cả" },
          ].map((p) => (
            <button
              key={p.id}
              onClick={() => setPeriod(p.id as any)}
              className={`tab-btn ${period === p.id ? "active" : ""}`}
              style={{ fontSize: "12px", padding: "6px 12px" }}
            >
              {p.label}
            </button>
          ))}
        </div>
      </div>

      {/* Row 1: Pie chart + Hourly chart */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 2fr", gap: "24px" }}>
        {/* Payment Pie */}
        <div className="card" style={{ padding: "20px" }}>
          <div style={{ display: "flex", alignItems: "center", gap: "8px", marginBottom: "20px" }}>
            <PieIcon size={18} style={{ color: "#7E2930" }} />
            <h2 style={{ fontSize: "16px", fontWeight: "700", color: "#1C1A2D" }}>Tỷ lệ Thanh toán</h2>
          </div>
          {paymentData.length === 0 ? (
            <div style={{ textAlign: "center", color: "#5D5B63", padding: "40px" }}>Không có dữ liệu</div>
          ) : (
            <>
              <ResponsiveContainer width="100%" height={200}>
                <PieChart>
                  <Pie data={paymentData} cx="50%" cy="50%" innerRadius={55} outerRadius={80} dataKey="value" paddingAngle={4}>
                    {paymentData.map((entry, index) => (
                      <Cell key={index} fill={entry.color} stroke="none" />
                    ))}
                  </Pie>
                  <Tooltip content={<PieCustomTooltip />} />
                </PieChart>
              </ResponsiveContainer>
              <div style={{ display: "flex", flexDirection: "column", gap: "8px", marginTop: "8px" }}>
                {paymentData.map((d, i) => (
                  <div key={i} style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
                    <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
                      <div style={{ width: "10px", height: "10px", borderRadius: "50%", background: d.color }} />
                      <span style={{ fontSize: "13px", color: "#5D5B63" }}>{d.name}</span>
                    </div>
                    <span style={{ fontSize: "13px", fontWeight: "700", color: "#1C1A2D" }}>
                      {d.value} ({historyData.length > 0 ? ((d.value / historyData.length) * 100).toFixed(1) : 0}%)
                    </span>
                  </div>
                ))}
              </div>
            </>
          )}
        </div>

        {/* Hourly revenue */}
        <div className="card" style={{ padding: "20px" }}>
          <div style={{ display: "flex", alignItems: "center", gap: "8px", marginBottom: "20px" }}>
            <TrendingUp size={18} style={{ color: "#D97706" }} />
            <h2 style={{ fontSize: "16px", fontWeight: "700", color: "#1C1A2D" }}>Doanh thu theo Giờ</h2>
          </div>
          <ResponsiveContainer width="100%" height={220}>
            <BarChart data={hourlyData}>
              <CartesianGrid strokeDasharray="3 3" stroke="#ECE5D8" />
              <XAxis dataKey="hour" tick={{ fill: "#5D5B63", fontSize: 10 }} axisLine={false} tickLine={false} interval={2} />
              <YAxis tick={{ fill: "#5D5B63", fontSize: 10 }} axisLine={false} tickLine={false} tickFormatter={(v) => `${(v / 1000).toFixed(0)}k`} />
              <Tooltip content={<CustomTooltip />} />
              <Bar dataKey="revenue" fill="#D97706" radius={[4, 4, 0, 0]} maxBarSize={28} />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </div>

      {/* Top 10 products */}
      <div className="card" style={{ padding: "20px" }}>
        <div style={{ display: "flex", alignItems: "center", gap: "8px", marginBottom: "20px" }}>
          <BarChart2 size={18} style={{ color: "#146A65" }} />
          <h2 style={{ fontSize: "16px", fontWeight: "700", color: "#1C1A2D" }}>Top 10 Món Bán Chạy</h2>
        </div>
        {topProducts.length === 0 ? (
          <div style={{ textAlign: "center", color: "#5D5B63", padding: "40px" }}>Không có dữ liệu</div>
        ) : (
          <ResponsiveContainer width="100%" height={300}>
            <BarChart data={topProducts} layout="vertical" margin={{ left: 20 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#ECE5D8" horizontal={false} />
              <XAxis type="number" tick={{ fill: "#5D5B63", fontSize: 11 }} axisLine={false} tickLine={false} />
              <YAxis type="category" dataKey="name" tick={{ fill: "#1C1A2D", fontSize: 12 }} axisLine={false} tickLine={false} width={140} />
              <Tooltip content={<CustomTooltip />} />
              <Bar dataKey="qty" fill="#146A65" radius={[0, 6, 6, 0]} maxBarSize={20} label={{ position: "right", fill: "#5D5B63", fontSize: 12 }} />
            </BarChart>
          </ResponsiveContainer>
        )}
      </div>

      {/* Revenue by zone */}
      {zoneData.length > 0 && (
        <div className="card" style={{ padding: "20px" }}>
          <div style={{ display: "flex", alignItems: "center", gap: "8px", marginBottom: "20px" }}>
            <MapPin size={18} style={{ color: "#7E2930" }} />
            <h2 style={{ fontSize: "16px", fontWeight: "700", color: "#1C1A2D" }}>Doanh thu theo Khu vực</h2>
          </div>
          <ResponsiveContainer width="100%" height={220}>
            <BarChart data={zoneData}>
              <CartesianGrid strokeDasharray="3 3" stroke="#ECE5D8" />
              <XAxis dataKey="zone" tick={{ fill: "#8B8FA8", fontSize: 12 }} axisLine={false} tickLine={false} />
              <YAxis tick={{ fill: "#8B8FA8", fontSize: 11 }} axisLine={false} tickLine={false} tickFormatter={(v) => `${(v / 1000).toFixed(0)}k`} />
              <Tooltip content={<CustomTooltip />} />
              <Bar dataKey="revenue" fill="#8B5CF6" radius={[6, 6, 0, 0]} maxBarSize={60}>
                {zoneData.map((_, i) => (
                  <Cell key={i} fill={COLORS[i % COLORS.length]} />
                ))}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        </div>
      )}
    </div>
  );
}
