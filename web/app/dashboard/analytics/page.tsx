"use client";
import React, { useEffect, useMemo, useState } from "react";
import {
  PieChart,
  Pie,
  Cell,
  Tooltip,
  ResponsiveContainer,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
} from "recharts";
import {
  TrendingUp,
  PieChart as PieIcon,
  BarChart2,
  Store,
  FileSpreadsheet,
  Printer,
  Users,
  Clock,
  DollarSign,
  ShieldAlert,
  Percent,
  Receipt,
  Layers,
} from "lucide-react";
import { useDashboardData } from "@/lib/data-context";
import {
  calculateOverviewReport,
  calculateHourlyReport,
  calculateStaffPerformance,
  calculatePaymentMethodsReport,
  getBillTimestamp,
  getUTC7Date,
  formatVND,
  formatNumber,
} from "@/lib/reports";
import {
  exportOverviewReport,
  exportHourlyReport,
  exportStaffPerformanceReport,
} from "@/lib/export";

const PIE_COLORS = ["#146A65", "#1877F2", "#8B5CF6", "#D97706", "#EC4899"];

export default function AnalyticsPage() {
  const {
    stores,
    currentStoreCode,
    setCurrentStoreCode,
    historyData,
    historyLoaded,
  } = useDashboardData();

  const loading = !historyLoaded && historyData.length === 0;
  const [period, setPeriod] = useState<"ALL" | "TODAY" | "YESTERDAY" | "7DAYS" | "THIS_MONTH" | "LAST_MONTH">("THIS_MONTH");
  const [activeTab, setActiveTab] = useState<"OVERVIEW" | "HOURLY" | "STAFF" | "PRODUCTS">("OVERVIEW");

  // Helper for UTC+7 date parts
  const toDateParts = (d: Date) => {
    const year = d.getUTCFullYear();
    const month = d.getUTCMonth() + 1;
    const day = d.getUTCDate();
    const dateStr = `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
    return { year, month, day, dateStr };
  };

  // Mốc "hiện tại" giữ trong state (không gọi Date.now() trong render), tự làm mới mỗi phút
  const [nowTs, setNowTs] = useState(() => Date.now());
  useEffect(() => {
    const timer = setInterval(() => setNowTs(Date.now()), 60_000);
    return () => clearInterval(timer);
  }, []);

  // UTC+7 filtering
  const filteredHistory = useMemo(() => {
    const nowParts = toDateParts(getUTC7Date(nowTs));

    return historyData.filter((h) => {
      if (currentStoreCode !== "ALL" && h.storeCode && h.storeCode !== currentStoreCode) {
        return false;
      }
      if (period === "ALL") return true;

      const ts = getBillTimestamp(h);
      if (!ts) return false;
      const bParts = toDateParts(getUTC7Date(ts));

      if (period === "TODAY") {
        return bParts.dateStr === nowParts.dateStr;
      }
      if (period === "YESTERDAY") {
        const yestParts = toDateParts(getUTC7Date(nowTs - 24 * 60 * 60 * 1000));
        return bParts.dateStr === yestParts.dateStr;
      }
      if (period === "7DAYS") {
        const d7Ts = nowTs - 7 * 24 * 60 * 60 * 1000;
        return ts >= d7Ts && ts <= nowTs;
      }
      if (period === "THIS_MONTH") {
        return bParts.year === nowParts.year && bParts.month === nowParts.month;
      }
      if (period === "LAST_MONTH") {
        const targetMonth = nowParts.month === 1 ? 12 : nowParts.month - 1;
        const targetYear = nowParts.month === 1 ? nowParts.year - 1 : nowParts.year;
        return bParts.year === targetYear && bParts.month === targetMonth;
      }
      return true;
    });
  }, [historyData, currentStoreCode, period, nowTs]);

  // Pure report calculations
  const overviewReport = useMemo(() => {
    return calculateOverviewReport(filteredHistory);
  }, [filteredHistory]);

  const hourlyReport = useMemo(() => {
    return calculateHourlyReport(filteredHistory);
  }, [filteredHistory]);

  const staffReport = useMemo(() => {
    return calculateStaffPerformance(filteredHistory);
  }, [filteredHistory]);

  const paymentReport = useMemo(() => {
    return calculatePaymentMethodsReport(filteredHistory);
  }, [filteredHistory]);

  // Payment chart data
  const paymentChartData = useMemo(() => {
    return Object.entries(paymentReport).map(([method, data]) => {
      const labelMap: Record<string, string> = {
        CASH: "Tiền mặt",
        TRANSFER_QR: "Chuyển khoản QR",
        CARD: "Thẻ / Khác",
      };
      return {
        name: labelMap[method] || method,
        value: data.finalAmount,
        bills: data.billCount,
        proportion: data.proportion,
      };
    });
  }, [paymentReport]);

  // Top products from filtered history
  const topProducts = useMemo(() => {
    const map = new Map<string, { name: string; qty: number; netRevenue: number }>();
    filteredHistory.forEach((h) => {
      if ((h.status || "PAID").toUpperCase() !== "PAID") return;
      const items = h.items || [];
      items.forEach((it) => {
        // Dữ liệu cũ có thể dùng productName / qty
        const legacy = it as { productName?: string; qty?: number };
        const n = it.name || legacy.productName || "Món chưa đặt tên";
        const q = Number(it.quantity || legacy.qty || 1);
        const price = Number(it.price || 0);
        const disc = Number(it.discountAmount || 0);
        const net = Math.max(0, price - disc) * q;
        if (!map.has(n)) {
          map.set(n, { name: n, qty: 0, netRevenue: 0 });
        }
        const entry = map.get(n)!;
        entry.qty += q;
        entry.netRevenue += net;
      });
    });
    return Array.from(map.values())
      .sort((a, b) => b.qty - a.qty)
      .slice(0, 10);
  }, [filteredHistory]);

  const dateRangeLabel = useMemo(() => {
    const map: Record<string, string> = {
      TODAY: "Hôm nay",
      YESTERDAY: "Hôm qua",
      "7DAYS": "7 ngày gần nhất",
      THIS_MONTH: "Tháng này",
      LAST_MONTH: "Tháng trước",
      ALL: "Toàn thời gian",
    };
    return map[period] || period;
  }, [period]);

  const targetStoreInfo = useMemo(() => {
    if (currentStoreCode === "ALL") {
      return { storeName: "Tất cả chi nhánh", storeCode: "ALL" };
    }
    return (
      stores.find((s) => s.storeCode === currentStoreCode) || {
        storeName: "POS Trạm",
        storeCode: currentStoreCode,
      }
    );
  }, [stores, currentStoreCode]);

  // Export handlers
  const handleExportExcel = () => {
    if (activeTab === "OVERVIEW") {
      exportOverviewReport(overviewReport, targetStoreInfo, dateRangeLabel).toExcel();
    } else if (activeTab === "HOURLY") {
      exportHourlyReport(hourlyReport, targetStoreInfo, dateRangeLabel).toExcel();
    } else if (activeTab === "STAFF") {
      exportStaffPerformanceReport(staffReport, targetStoreInfo, dateRangeLabel).toExcel();
    }
  };

  const handleExportPDF = () => {
    if (activeTab === "OVERVIEW") {
      exportOverviewReport(overviewReport, targetStoreInfo, dateRangeLabel).toPDF();
    } else if (activeTab === "HOURLY") {
      exportHourlyReport(hourlyReport, targetStoreInfo, dateRangeLabel).toPDF();
    } else if (activeTab === "STAFF") {
      exportStaffPerformanceReport(staffReport, targetStoreInfo, dateRangeLabel).toPDF();
    }
  };

  if (loading) {
    return (
      <div style={{ display: "flex", alignItems: "center", justifyContent: "center", height: "60vh" }}>
        <div style={{ color: "#7E2930", fontWeight: "700" }}>Đang tải dữ liệu phân tích...</div>
      </div>
    );
  }

  return (
    <div style={{ padding: "24px 28px", maxWidth: "1280px", margin: "0 auto" }}>
      {/* Top Header Card */}
      <div
        style={{
          background: "#FFFFFF",
          borderRadius: "16px",
          border: "1px solid #E6DEC8",
          padding: "20px 24px",
          marginBottom: "20px",
          boxShadow: "0 2px 10px rgba(0,0,0,0.03)",
        }}
      >
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: "16px" }}>
          <div>
            <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
              <h1 style={{ fontSize: "22px", fontWeight: "800", color: "#1C1A2D", margin: 0 }}>
                Phân tích & Quản trị Bán hàng
              </h1>
              <span
                style={{
                  background: "#FBECEE",
                  color: "#7E2930",
                  padding: "4px 10px",
                  borderRadius: "20px",
                  fontSize: "12px",
                  fontWeight: "700",
                }}
              >
                Executive BI Dashboard
              </span>
            </div>
            <p style={{ fontSize: "13px", color: "#666", marginTop: "4px", margin: 0 }}>
              20 chỉ số tài chính, nhiệt độ kinh doanh theo khung giờ và năng suất bán hàng nhân viên
            </p>
          </div>

          <div style={{ display: "flex", alignItems: "center", gap: "10px", flexWrap: "wrap" }}>
            {/* Store Switcher */}
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: "8px",
                background: "#F8F4EE",
                border: "1px solid #E6DEC8",
                borderRadius: "10px",
                padding: "6px 12px",
              }}
            >
              <Store size={16} color="#7E2930" />
              <select
                value={currentStoreCode}
                onChange={(e) => setCurrentStoreCode(e.target.value)}
                style={{
                  background: "transparent",
                  border: "none",
                  outline: "none",
                  fontSize: "13px",
                  fontWeight: "600",
                  color: "#1C1A2D",
                  cursor: "pointer",
                }}
              >
                <option value="ALL">🌐 Tất cả chi nhánh</option>
                {stores.map((s) => (
                  <option key={s.storeCode} value={s.storeCode}>
                    🏪 {s.storeCode} - {s.storeName}
                  </option>
                ))}
              </select>
            </div>

            {/* Export buttons */}
            {activeTab !== "PRODUCTS" && (
              <div style={{ display: "flex", gap: "8px" }}>
                <button
                  onClick={handleExportExcel}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: "6px",
                    padding: "7px 14px",
                    background: "#107C41",
                    color: "#FFFFFF",
                    border: "none",
                    borderRadius: "8px",
                    fontSize: "12px",
                    fontWeight: "600",
                    cursor: "pointer",
                  }}
                >
                  <FileSpreadsheet size={15} /> Xuất Excel
                </button>
                <button
                  onClick={handleExportPDF}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: "6px",
                    padding: "7px 14px",
                    background: "#7E2930",
                    color: "#FFFFFF",
                    border: "none",
                    borderRadius: "8px",
                    fontSize: "12px",
                    fontWeight: "600",
                    cursor: "pointer",
                  }}
                >
                  <Printer size={15} /> In / PDF
                </button>
              </div>
            )}
          </div>
        </div>

        {/* Period Selector Tabs */}
        <div style={{ display: "flex", gap: "8px", marginTop: "16px", flexWrap: "wrap" }}>
          {[
            { id: "TODAY", label: "Hôm nay" },
            { id: "YESTERDAY", label: "Hôm qua" },
            { id: "7DAYS", label: "7 ngày gần nhất" },
            { id: "THIS_MONTH", label: "Tháng này" },
            { id: "LAST_MONTH", label: "Tháng trước" },
            { id: "ALL", label: "Toàn bộ" },
          ].map((p) => (
            <button
              key={p.id}
              onClick={() => setPeriod(p.id as "ALL" | "TODAY" | "YESTERDAY" | "7DAYS" | "THIS_MONTH" | "LAST_MONTH")}
              style={{
                padding: "6px 14px",
                borderRadius: "8px",
                border: "1px solid #E6DEC8",
                background: period === p.id ? "#7E2930" : "#FFFFFF",
                color: period === p.id ? "#FFFFFF" : "#555",
                fontSize: "12px",
                fontWeight: "600",
                cursor: "pointer",
              }}
            >
              {p.label}
            </button>
          ))}
        </div>
      </div>

      {/* Primary 4 KPI Metric Cards */}
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))",
          gap: "16px",
          marginBottom: "20px",
        }}
      >
        <div style={{ background: "#FFFFFF", border: "1px solid #E6DEC8", borderRadius: "14px", padding: "16px 20px" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", color: "#666", fontSize: "13px" }}>
            <span>Doanh thu thuần</span>
            <DollarSign size={18} color="#7E2930" />
          </div>
          <div style={{ fontSize: "24px", fontWeight: "800", color: "#7E2930", marginTop: "8px" }}>
            {formatVND(overviewReport.netRevenue)}
          </div>
          <div style={{ fontSize: "12px", color: "#666", marginTop: "4px" }}>
            Gộp: {formatVND(overviewReport.grossRevenue)}
          </div>
        </div>

        <div style={{ background: "#FFFFFF", border: "1px solid #E6DEC8", borderRadius: "14px", padding: "16px 20px" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", color: "#666", fontSize: "13px" }}>
            <span>Tổng chiết khấu & Giảm giá</span>
            <Percent size={18} color="#C93B2B" />
          </div>
          <div style={{ fontSize: "24px", fontWeight: "800", color: "#C93B2B", marginTop: "8px" }}>
            {formatVND(overviewReport.totalDiscount)}
          </div>
          <div style={{ fontSize: "12px", color: "#666", marginTop: "4px" }}>
            Món: {formatVND(overviewReport.itemDiscounts)} • Đơn/Voucher: {formatVND(overviewReport.billDiscounts)}
          </div>
        </div>

        <div style={{ background: "#FFFFFF", border: "1px solid #E6DEC8", borderRadius: "14px", padding: "16px 20px" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", color: "#666", fontSize: "13px" }}>
            <span>Lợi nhuận gộp</span>
            <TrendingUp size={18} color="#146A65" />
          </div>
          <div style={{ fontSize: "24px", fontWeight: "800", color: "#146A65", marginTop: "8px" }}>
            {formatVND(overviewReport.grossProfit)}
          </div>
          <div style={{ fontSize: "12px", color: "#666", marginTop: "4px" }}>
            Tỷ suất LN: <strong>{overviewReport.grossProfitMarginPercent}%</strong> (Giá vốn: {formatVND(overviewReport.totalCostPrice)})
          </div>
        </div>

        <div style={{ background: "#FFFFFF", border: "1px solid #E6DEC8", borderRadius: "14px", padding: "16px 20px" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", color: "#666", fontSize: "13px" }}>
            <span>Hóa đơn hoàn tất</span>
            <Receipt size={18} color="#1877F2" />
          </div>
          <div style={{ fontSize: "24px", fontWeight: "800", color: "#1C1A2D", marginTop: "8px" }}>
            {formatNumber(overviewReport.paidBillsCount)} đơn
          </div>
          <div style={{ fontSize: "12px", color: "#666", marginTop: "4px" }}>
            TB/đơn: {formatVND(overviewReport.avgRevenuePerPaidBill)} • Khách: {overviewReport.totalGuests}
          </div>
        </div>
      </div>

      {/* Navigation Sub-Tabs */}
      <div
        style={{
          display: "flex",
          borderBottom: "2px solid #E6DEC8",
          marginBottom: "20px",
          gap: "8px",
        }}
      >
        {[
          { id: "OVERVIEW", label: "📊 20 Chỉ số Quản trị", icon: Layers },
          { id: "HOURLY", label: "⏰ Phân bổ 24 Khung giờ", icon: Clock },
          { id: "STAFF", label: "👥 Năng suất Nhân viên", icon: Users },
          { id: "PRODUCTS", label: "🍵 Mặt hàng & Thanh toán", icon: BarChart2 },
        ].map((tab) => {
          const isActive = activeTab === tab.id;
          return (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id as "OVERVIEW" | "HOURLY" | "STAFF" | "PRODUCTS")}
              style={{
                padding: "10px 18px",
                border: "none",
                borderBottom: isActive ? "3px solid #7E2930" : "3px solid transparent",
                background: "transparent",
                color: isActive ? "#7E2930" : "#666",
                fontWeight: isActive ? "700" : "500",
                fontSize: "14px",
                cursor: "pointer",
                marginBottom: "-2px",
                transition: "all 0.2s",
              }}
            >
              {tab.label}
            </button>
          );
        })}
      </div>

      {/* TAB 1: 20 CHỈ SỐ QUẢN TRỊ */}
      {activeTab === "OVERVIEW" && (
        <div
          style={{
            background: "#FFFFFF",
            borderRadius: "16px",
            border: "1px solid #E6DEC8",
            padding: "20px",
            boxShadow: "0 2px 10px rgba(0,0,0,0.02)",
          }}
        >
          <div style={{ fontSize: "16px", fontWeight: "800", color: "#1C1A2D", marginBottom: "16px" }}>
            Bảng kê 20 Chỉ số Quản trị Tài chính & Vận hành ({dateRangeLabel})
          </div>
          <table style={{ width: "100%", borderCollapse: "collapse", fontSize: "13px" }}>
            <thead>
              <tr style={{ borderBottom: "2px solid #E6DEC8", color: "#666" }}>
                <th style={{ padding: "10px 12px", textAlign: "left" }}>STT</th>
                <th style={{ padding: "10px 12px", textAlign: "left" }}>Tên chỉ số quản trị</th>
                <th style={{ padding: "10px 12px", textAlign: "right" }}>Giá trị ghi nhận</th>
                <th style={{ padding: "10px 12px", textAlign: "left" }}>Ghi chú công thức & Ý nghĩa</th>
              </tr>
            </thead>
            <tbody>
              {[
                { stt: 1, name: "Tổng số hóa đơn phát sinh trong kỳ", val: formatNumber(overviewReport.totalBillsCount), note: "Bao gồm cả đơn hoàn tất, hủy và hoàn tiền" },
                { stt: 2, name: "Số hóa đơn hoàn tất thanh toán (PAID)", val: formatNumber(overviewReport.paidBillsCount), note: "Hóa đơn đã thu tiền thành công" },
                { stt: 3, name: "Số hóa đơn bị hủy bỏ (CANCELLED)", val: formatNumber(overviewReport.cancelledBillsCount), note: "Hóa đơn hủy món / bàn" },
                { stt: 4, name: "Số hóa đơn hoàn tiền (REFUNDED)", val: formatNumber(overviewReport.refundedBillsCount), note: "Hóa đơn hoàn tiền cho khách" },
                { stt: 5, name: "Tổng số lượt khách phục vụ", val: formatNumber(overviewReport.totalGuests) + " khách", note: "Tổng số lượng khách tại bàn" },
                { stt: 6, name: "Doanh thu gộp (Gross Revenue)", val: formatVND(overviewReport.grossRevenue), note: "Tổng tiền hàng theo menu trước giảm giá" },
                { stt: 7, name: "Giảm giá theo từng món (Item Discount)", val: formatVND(overviewReport.itemDiscounts), note: "Chiết khấu trực tiếp trên món ăn" },
                { stt: 8, name: "Giảm giá hóa đơn (Bill Discount / Voucher)", val: formatVND(overviewReport.billDiscounts), note: "Khuyến mãi voucher hoặc chiết khấu % tổng đơn" },
                { stt: 9, name: "Giảm giá đổi điểm tích lũy", val: formatVND(overviewReport.pointsDiscounts), note: "Trừ điểm thưởng thành viên" },
                { stt: 10, name: "Tổng giá trị giảm giá (Total Discount)", val: formatVND(overviewReport.totalDiscount), note: "Món + Hóa đơn + Đổi điểm" },
                { stt: 11, name: "Doanh thu sau giảm giá (After Discount)", val: formatVND(overviewReport.afterDiscount), note: "Doanh thu gộp - Tổng giảm giá" },
                { stt: 12, name: "Tổng thuế giá trị gia tăng (VAT)", val: formatVND(overviewReport.vatTotal), note: "Thuế GTGT ghi nhận trên bill" },
                { stt: 13, name: "Doanh thu thuần (Net Revenue)", val: formatVND(overviewReport.netRevenue), note: "Doanh thu sau giảm giá + Thuế VAT" },
                { stt: 14, name: "Tiền hoàn trả lại khách (Refund)", val: formatVND(overviewReport.refundAmount), note: "Số tiền đã trả lại cho các đơn hoàn" },
                { stt: 15, name: "Doanh thu thuần sau hoàn trả", val: formatVND(overviewReport.netRevenueWithoutRefund), note: "Doanh thu thuần - Tiền hoàn trả" },
                { stt: 16, name: "Giá trị trung bình / đơn hoàn tất", val: formatVND(overviewReport.avgRevenuePerPaidBill), note: "Doanh thu thuần / Số đơn PAID" },
                { stt: 17, name: "Tổng giá trị thất thoát đơn hủy", val: formatVND(overviewReport.cancelledTotalValue), note: "Giá trị hàng của các đơn bị hủy" },
                { stt: 18, name: "Tổng giá vốn hàng bán (COGS)", val: formatVND(overviewReport.totalCostPrice), note: "Giá vốn thực tế của các sản phẩm đã bán" },
                { stt: 19, name: "Lợi nhuận gộp (Gross Profit)", val: formatVND(overviewReport.grossProfit), note: "Doanh thu sau giảm giá - Tổng giá vốn" },
                { stt: 20, name: "Tỷ suất lợi nhuận gộp (%)", val: `${overviewReport.grossProfitMarginPercent}%`, note: "Lợi nhuận gộp / Doanh thu sau giảm giá" },
              ].map((row) => (
                <tr key={row.stt} style={{ borderBottom: "1px solid #F0ECE1" }}>
                  <td style={{ padding: "10px 12px", color: "#888" }}>{row.stt}</td>
                  <td style={{ padding: "10px 12px", fontWeight: "600", color: "#1C1A2D" }}>{row.name}</td>
                  <td style={{ padding: "10px 12px", textAlign: "right", fontWeight: "700", color: "#7E2930" }}>
                    {row.val}
                  </td>
                  <td style={{ padding: "10px 12px", color: "#666", fontSize: "12px" }}>{row.note}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* TAB 2: PHÂN BỔ THEO 24 KHUNG GIỜ */}
      {activeTab === "HOURLY" && (
        <div style={{ display: "flex", flexDirection: "column", gap: "20px" }}>
          {/* Chart */}
          <div
            style={{
              background: "#FFFFFF",
              borderRadius: "16px",
              border: "1px solid #E6DEC8",
              padding: "20px",
              boxShadow: "0 2px 10px rgba(0,0,0,0.02)",
            }}
          >
            <div style={{ display: "flex", alignItems: "center", gap: "8px", marginBottom: "16px" }}>
              <Clock size={18} color="#D97706" />
              <h2 style={{ fontSize: "16px", fontWeight: "700", color: "#1C1A2D", margin: 0 }}>
                Biểu đồ Doanh thu theo 24 Khung giờ ({dateRangeLabel})
              </h2>
            </div>
            <ResponsiveContainer width="100%" height={260}>
              <BarChart data={hourlyReport}>
                <CartesianGrid strokeDasharray="3 3" stroke="#ECE5D8" />
                <XAxis dataKey="hourLabel" tick={{ fill: "#5D5B63", fontSize: 10 }} interval={1} />
                <YAxis
                  tick={{ fill: "#5D5B63", fontSize: 10 }}
                  tickFormatter={(v) => `${(v / 1000).toFixed(0)}k`}
                />
                <Tooltip
                  formatter={(value) => [formatVND(Number(value)), "Doanh thu thuần"]}
                  labelFormatter={(label) => `Khung giờ: ${label}`}
                />
                <Bar dataKey="netRevenue" fill="#7E2930" radius={[4, 4, 0, 0]} maxBarSize={28} />
              </BarChart>
            </ResponsiveContainer>
          </div>

          {/* Table */}
          <div
            style={{
              background: "#FFFFFF",
              borderRadius: "16px",
              border: "1px solid #E6DEC8",
              padding: "20px",
              boxShadow: "0 2px 10px rgba(0,0,0,0.02)",
              overflowX: "auto",
            }}
          >
            <table style={{ width: "100%", borderCollapse: "collapse", fontSize: "13px" }}>
              <thead>
                <tr style={{ borderBottom: "2px solid #E6DEC8", color: "#666" }}>
                  <th style={{ padding: "10px 12px", textAlign: "left" }}>Khung giờ</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Số hóa đơn</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Doanh thu gộp</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Tổng giảm giá</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Thuế VAT</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Doanh thu thuần</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Tỷ trọng ngày</th>
                </tr>
              </thead>
              <tbody>
                {hourlyReport.map((h) => (
                  <tr key={h.hour} style={{ borderBottom: "1px solid #F0ECE1" }}>
                    <td style={{ padding: "8px 12px", fontWeight: "600", color: "#1C1A2D" }}>{h.hourLabel}</td>
                    <td style={{ padding: "8px 12px", textAlign: "right" }}>{h.billCount}</td>
                    <td style={{ padding: "8px 12px", textAlign: "right" }}>{formatVND(h.grossRevenue)}</td>
                    <td style={{ padding: "8px 12px", textAlign: "right", color: "#C93B2B" }}>{formatVND(h.totalDiscount)}</td>
                    <td style={{ padding: "8px 12px", textAlign: "right" }}>{formatVND(h.vatAmount)}</td>
                    <td style={{ padding: "8px 12px", textAlign: "right", fontWeight: "700", color: "#7E2930" }}>
                      {formatVND(h.netRevenue)}
                    </td>
                    <td style={{ padding: "8px 12px", textAlign: "right", fontWeight: "600" }}>{h.proportion || 0}%</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* TAB 3: NĂNG SUẤT NHÂN VIÊN */}
      {activeTab === "STAFF" && (
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "20px" }}>
          {/* Order Staff */}
          <div
            style={{
              background: "#FFFFFF",
              borderRadius: "16px",
              border: "1px solid #E6DEC8",
              padding: "20px",
              boxShadow: "0 2px 10px rgba(0,0,0,0.02)",
            }}
          >
            <div style={{ display: "flex", alignItems: "center", gap: "8px", marginBottom: "16px" }}>
              <Users size={18} color="#146A65" />
              <h2 style={{ fontSize: "16px", fontWeight: "700", color: "#1C1A2D", margin: 0 }}>
                Năng suất Nhân viên Order ({staffReport.orderStaff.length} nhân viên)
              </h2>
            </div>
            <table style={{ width: "100%", borderCollapse: "collapse", fontSize: "13px" }}>
              <thead>
                <tr style={{ borderBottom: "2px solid #E6DEC8", color: "#666" }}>
                  <th style={{ padding: "10px 12px", textAlign: "left" }}>Nhân viên</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Số món gọi</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Doanh thu thuần</th>
                </tr>
              </thead>
              <tbody>
                {staffReport.orderStaff.length === 0 ? (
                  <tr>
                    <td colSpan={3} style={{ textAlign: "center", padding: "20px", color: "#999" }}>
                      Chưa có dữ liệu ghi nhận
                    </td>
                  </tr>
                ) : (
                  staffReport.orderStaff.map((s) => (
                    <tr key={s.staffUsername} style={{ borderBottom: "1px solid #F0ECE1" }}>
                      <td style={{ padding: "10px 12px" }}>
                        <div style={{ fontWeight: "700", color: "#1C1A2D" }}>{s.staffFullName}</div>
                        <div style={{ fontSize: "11px", color: "#888" }}>@{s.staffUsername}</div>
                      </td>
                      <td style={{ padding: "10px 12px", textAlign: "right", fontWeight: "600" }}>{s.itemsCount}</td>
                      <td style={{ padding: "10px 12px", textAlign: "right", fontWeight: "700", color: "#146A65" }}>
                        {formatVND(s.netRevenue)}
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>

          {/* Cashier Staff */}
          <div
            style={{
              background: "#FFFFFF",
              borderRadius: "16px",
              border: "1px solid #E6DEC8",
              padding: "20px",
              boxShadow: "0 2px 10px rgba(0,0,0,0.02)",
            }}
          >
            <div style={{ display: "flex", alignItems: "center", gap: "8px", marginBottom: "16px" }}>
              <Receipt size={18} color="#7E2930" />
              <h2 style={{ fontSize: "16px", fontWeight: "700", color: "#1C1A2D", margin: 0 }}>
                Năng suất Thu ngân chốt Bill ({staffReport.cashierStaff.length} thu ngân)
              </h2>
            </div>
            <table style={{ width: "100%", borderCollapse: "collapse", fontSize: "13px" }}>
              <thead>
                <tr style={{ borderBottom: "2px solid #E6DEC8", color: "#666" }}>
                  <th style={{ padding: "10px 12px", textAlign: "left" }}>Thu ngân</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Số hóa đơn</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Doanh số thực thu</th>
                </tr>
              </thead>
              <tbody>
                {staffReport.cashierStaff.length === 0 ? (
                  <tr>
                    <td colSpan={3} style={{ textAlign: "center", padding: "20px", color: "#999" }}>
                      Chưa có dữ liệu ghi nhận
                    </td>
                  </tr>
                ) : (
                  staffReport.cashierStaff.map((s) => (
                    <tr key={s.staffUsername} style={{ borderBottom: "1px solid #F0ECE1" }}>
                      <td style={{ padding: "10px 12px" }}>
                        <div style={{ fontWeight: "700", color: "#1C1A2D" }}>{s.staffFullName}</div>
                        <div style={{ fontSize: "11px", color: "#888" }}>@{s.staffUsername}</div>
                      </td>
                      <td style={{ padding: "10px 12px", textAlign: "right", fontWeight: "600" }}>{s.billCount}</td>
                      <td style={{ padding: "10px 12px", textAlign: "right", fontWeight: "700", color: "#7E2930" }}>
                        {formatVND(s.netRevenue)}
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* TAB 4: MẶT HÀNG & THANH TOÁN */}
      {activeTab === "PRODUCTS" && (
        <div style={{ display: "grid", gridTemplateColumns: "1fr 2fr", gap: "20px" }}>
          {/* Payment Method Pie */}
          <div
            style={{
              background: "#FFFFFF",
              borderRadius: "16px",
              border: "1px solid #E6DEC8",
              padding: "20px",
              boxShadow: "0 2px 10px rgba(0,0,0,0.02)",
            }}
          >
            <div style={{ display: "flex", alignItems: "center", gap: "8px", marginBottom: "16px" }}>
              <PieIcon size={18} color="#7E2930" />
              <h2 style={{ fontSize: "16px", fontWeight: "700", color: "#1C1A2D", margin: 0 }}>
                Tỷ trọng Hình thức Thanh toán
              </h2>
            </div>
            {paymentChartData.length === 0 ? (
              <div style={{ textAlign: "center", color: "#999", padding: "40px" }}>Không có dữ liệu</div>
            ) : (
              <>
                <ResponsiveContainer width="100%" height={200}>
                  <PieChart>
                    <Pie
                      data={paymentChartData}
                      cx="50%"
                      cy="50%"
                      innerRadius={55}
                      outerRadius={80}
                      dataKey="value"
                      paddingAngle={4}
                    >
                      {paymentChartData.map((_, index) => (
                        <Cell key={index} fill={PIE_COLORS[index % PIE_COLORS.length]} stroke="none" />
                      ))}
                    </Pie>
                    <Tooltip formatter={(value) => [formatVND(Number(value)), "Doanh thu"]} />
                  </PieChart>
                </ResponsiveContainer>
                <div style={{ display: "flex", flexDirection: "column", gap: "8px", marginTop: "12px" }}>
                  {paymentChartData.map((d, i) => (
                    <div key={i} style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
                      <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
                        <div
                          style={{
                            width: "10px",
                            height: "10px",
                            borderRadius: "50%",
                            background: PIE_COLORS[i % PIE_COLORS.length],
                          }}
                        />
                        <span style={{ fontSize: "13px", color: "#5D5B63" }}>{d.name}</span>
                      </div>
                      <span style={{ fontSize: "13px", fontWeight: "700", color: "#1C1A2D" }}>
                        {formatVND(d.value)} ({d.proportion || 0}%)
                      </span>
                    </div>
                  ))}
                </div>
              </>
            )}
          </div>

          {/* Top 10 Best Sellers */}
          <div
            style={{
              background: "#FFFFFF",
              borderRadius: "16px",
              border: "1px solid #E6DEC8",
              padding: "20px",
              boxShadow: "0 2px 10px rgba(0,0,0,0.02)",
            }}
          >
            <div style={{ display: "flex", alignItems: "center", gap: "8px", marginBottom: "16px" }}>
              <BarChart2 size={18} color="#146A65" />
              <h2 style={{ fontSize: "16px", fontWeight: "700", color: "#1C1A2D", margin: 0 }}>
                Top 10 Món Bán Chạy Nhất Trong Kỳ
              </h2>
            </div>
            {topProducts.length === 0 ? (
              <div style={{ textAlign: "center", color: "#999", padding: "40px" }}>Không có dữ liệu</div>
            ) : (
              <ResponsiveContainer width="100%" height={260}>
                <BarChart data={topProducts} layout="vertical" margin={{ left: 20 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#ECE5D8" horizontal={false} />
                  <XAxis type="number" tick={{ fill: "#5D5B63", fontSize: 11 }} />
                  <YAxis
                    type="category"
                    dataKey="name"
                    tick={{ fill: "#1C1A2D", fontSize: 12 }}
                    width={140}
                  />
                  <Tooltip
                    formatter={(value, name) => [
                      name === "qty" ? `${value} phần` : formatVND(Number(value)),
                      name === "qty" ? "Số lượng bán" : "Doanh thu",
                    ]}
                  />
                  <Bar dataKey="qty" fill="#146A65" radius={[0, 6, 6, 0]} maxBarSize={20} />
                </BarChart>
              </ResponsiveContainer>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
