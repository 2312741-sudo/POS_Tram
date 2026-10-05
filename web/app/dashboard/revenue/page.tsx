"use client";
import React, { useState, useMemo } from "react";
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer,
} from "recharts";
import { Download, Printer, DollarSign, CreditCard, Banknote, Utensils, Store } from "lucide-react";
import {
  calculateRevenueByPeriod,
  calculatePaymentMethodsReport,
  formatVND,
  formatNumber,
  PeriodType,
  PeriodRevenueItem,
} from "@/lib/reports";
import {
  exportRevenueByPeriodReport,
  exportPaymentMethodsReport,
  ReportStoreInfo,
} from "@/lib/export";
import { useDashboardData, TableItem } from "@/lib/data-context";

function getTableServingTotal(t: TableItem): number {
  if (!t.currentOrderJson) return 0;
  try {
    const items = typeof t.currentOrderJson === "string" ? JSON.parse(t.currentOrderJson) : t.currentOrderJson;
    if (!Array.isArray(items)) return 0;
    return items.reduce((sum: number, it: { quantity?: number; count?: number; price?: number; selectedToppings?: Array<{ price?: number }> }) => {
      const qty = it.quantity || it.count || 1;
      let toppingSum = 0;
      if (Array.isArray(it.selectedToppings)) {
        toppingSum = it.selectedToppings.reduce((ts: number, tp) => ts + (tp.price || 0), 0);
      }
      return sum + ((Number(it.price) || 0) + toppingSum) * qty;
    }, 0);
  } catch {
    return 0;
  }
}

export default function RevenuePage() {
  const { stores, currentStoreCode, setCurrentStoreCode, historyData, historyLoaded, tables } = useDashboardData();
  const loading = !historyLoaded && historyData.length === 0;

  const [period, setPeriod] = useState<PeriodType>("DAY");

  // Current store metadata
  const currentStore = useMemo(() => {
    if (currentStoreCode === "ALL") return stores[0];
    return stores.find((s) => s.storeCode === currentStoreCode) || stores[0];
  }, [stores, currentStoreCode]);

  // Filter bills by store
  const storeBills = useMemo(() => {
    if (currentStoreCode === "ALL") return historyData;
    return historyData.filter((b) => !b.storeCode || b.storeCode === currentStoreCode);
  }, [historyData, currentStoreCode]);

  // Calculate Revenue by Period using pure function
  const periodItems = useMemo<PeriodRevenueItem[]>(() => {
    return calculateRevenueByPeriod(storeBills, period);
  }, [storeBills, period]);

  // Calculate Payment Methods summary using pure function
  const paymentMethods = useMemo(() => {
    return calculatePaymentMethodsReport(storeBills);
  }, [storeBills]);

  // Active serving tables
  const servingTables = useMemo(() => {
    return tables.filter((t) => {
      if (currentStoreCode !== "ALL" && t.storeCode && t.storeCode !== currentStoreCode) return false;
      return t.inUse && !t.mergedIntoTable;
    });
  }, [tables, currentStoreCode]);

  const servingCount = servingTables.length;
  const servingTotal = useMemo(() => {
    return servingTables.reduce((sum, t) => sum + getTableServingTotal(t), 0);
  }, [servingTables]);

  // Aggregate totals across period items
  const summaryTotals = useMemo(() => {
    const totalBills = periodItems.reduce((s, i) => s + i.billCount, 0);
    const totalGross = periodItems.reduce((s, i) => s + i.grossRevenue, 0);
    const totalDiscount = periodItems.reduce((s, i) => s + i.discountAmount, 0);
    const totalVat = periodItems.reduce((s, i) => s + i.vatAmount, 0);
    const totalNet = periodItems.reduce((s, i) => s + i.netRevenue, 0);
    const totalCash = periodItems.reduce((s, i) => s + i.cashRevenue, 0);
    const totalQr = periodItems.reduce((s, i) => s + i.qrRevenue, 0);
    const totalCard = periodItems.reduce((s, i) => s + i.cardRevenue, 0);
    const avgPerOrder = totalBills > 0 ? Math.round(totalNet / totalBills) : 0;

    return {
      totalBills,
      totalGross,
      totalDiscount,
      totalVat,
      totalNet,
      totalCash,
      totalQr,
      totalCard,
      avgPerOrder,
    };
  }, [periodItems]);

  // Chart data
  const chartData = useMemo(() => {
    return periodItems.map((item) => ({
      label: item.periodLabel,
      netRevenue: item.netRevenue,
      grossRevenue: item.grossRevenue,
      cashRevenue: item.cashRevenue,
      qrRevenue: item.qrRevenue,
    }));
  }, [periodItems]);

  // Export handlers
  const handleExportExcel = () => {
    const storeInfo: ReportStoreInfo = {
      storeName: currentStore?.storeName || "POS Trạm",
      address: currentStore?.address || "Đà Lạt, Lâm Đồng",
      phone: currentStore?.phone || "0987.654.321",
      storeCode: currentStoreCode === "ALL" ? "ALL" : currentStore?.storeCode,
    };
    exportRevenueByPeriodReport(periodItems, storeInfo, `Kỳ: ${period}`).toExcel();
  };

  const handlePrintPDF = () => {
    const storeInfo: ReportStoreInfo = {
      storeName: currentStore?.storeName || "POS Trạm",
      address: currentStore?.address || "Đà Lạt, Lâm Đồng",
      phone: currentStore?.phone || "0987.654.321",
      storeCode: currentStoreCode === "ALL" ? "ALL" : currentStore?.storeCode,
    };
    exportRevenueByPeriodReport(periodItems, storeInfo, `Kỳ: ${period}`).toPDF();
  };

  const handleExportPaymentMethods = () => {
    const storeInfo: ReportStoreInfo = {
      storeName: currentStore?.storeName || "POS Trạm",
      address: currentStore?.address || "Đà Lạt, Lâm Đồng",
      phone: currentStore?.phone || "0987.654.321",
      storeCode: currentStoreCode === "ALL" ? "ALL" : currentStore?.storeCode,
    };
    exportPaymentMethodsReport(paymentMethods, storeInfo).toExcel();
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

  const periodOptions: { key: PeriodType; label: string }[] = [
    { key: "DAY", label: "Theo Ngày" },
    { key: "WEEK", label: "Theo Tuần" },
    { key: "MONTH", label: "Theo Tháng" },
    { key: "YEAR", label: "Theo Năm" },
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
      {/* Top Header */}
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: "16px" }}>
        <div>
          <h1 className="section-title">Báo cáo Doanh thu 💰</h1>
          <p className="section-subtitle">
            Phân tích doanh thu & đối soát tài chính theo kỳ (Chuẩn hóa UTC+7 & Báo cáo số 2/7)
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
              <option value="ALL">Tất cả chi nhánh</option>
              {stores.map((s) => (
                <option key={s.storeCode} value={s.storeCode}>
                  {s.storeName}
                </option>
              ))}
            </select>
          </div>

          <button className="btn-secondary" onClick={handleExportPaymentMethods}>
            <Download size={15} /> Xuất PTTT
          </button>

          <button className="btn-secondary" onClick={handlePrintPDF}>
            <Printer size={15} /> In / PDF
          </button>

          <button className="btn-primary" onClick={handleExportExcel}>
            <Download size={16} /> Xuất Excel
          </button>
        </div>
      </div>

      {/* Period Selector Card */}
      <div className="card" style={{ padding: "16px 20px" }}>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: "12px" }}>
          <div style={{ display: "flex", gap: "8px", flexWrap: "wrap" }}>
            {periodOptions.map((opt) => (
              <button
                key={opt.key}
                className={`tab-btn ${period === opt.key ? "active" : ""}`}
                onClick={() => setPeriod(opt.key)}
              >
                {opt.label}
              </button>
            ))}
          </div>

          <div style={{ fontSize: "13px", color: "#5D5B63", fontWeight: "600" }}>
            Ghi nhận: <strong>{summaryTotals.totalBills} hóa đơn hoàn tất</strong> • Đóng góp: <strong>{formatVND(summaryTotals.totalNet)}</strong>
          </div>
        </div>
      </div>

      {/* Summary KPI cards */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))", gap: "16px" }}>
        <div className="stat-card">
          <div style={{ display: "flex", gap: "12px", alignItems: "center" }}>
            <div style={{ width: "42px", height: "42px", borderRadius: "10px", background: "#7E293018", display: "flex", alignItems: "center", justifyContent: "center", color: "#7E2930", flexShrink: 0 }}>
              <DollarSign size={20} />
            </div>
            <div>
              <div style={{ fontSize: "17px", fontWeight: "800", color: "#1C1A2D" }}>{formatVND(summaryTotals.totalNet)}</div>
              <div style={{ fontSize: "12px", fontWeight: "600", color: "#5D5B63" }}>Doanh thu thuần</div>
              <div style={{ fontSize: "11px", color: "#8B8FA8" }}>{summaryTotals.totalBills} đơn đã thu</div>
            </div>
          </div>
        </div>

        <div className="stat-card">
          <div style={{ display: "flex", gap: "12px", alignItems: "center" }}>
            <div style={{ width: "42px", height: "42px", borderRadius: "10px", background: "#146A6518", display: "flex", alignItems: "center", justifyContent: "center", color: "#146A65", flexShrink: 0 }}>
              <Banknote size={20} />
            </div>
            <div>
              <div style={{ fontSize: "17px", fontWeight: "800", color: "#1C1A2D" }}>{formatVND(summaryTotals.totalCash)}</div>
              <div style={{ fontSize: "12px", fontWeight: "600", color: "#5D5B63" }}>Tiền mặt (CASH)</div>
              <div style={{ fontSize: "11px", color: "#8B8FA8" }}>
                {paymentMethods.CASH?.billCount || 0} đơn ({paymentMethods.CASH?.proportion || 0}%)
              </div>
            </div>
          </div>
        </div>

        <div className="stat-card">
          <div style={{ display: "flex", gap: "12px", alignItems: "center" }}>
            <div style={{ width: "42px", height: "42px", borderRadius: "10px", background: "#1877F218", display: "flex", alignItems: "center", justifyContent: "center", color: "#1877F2", flexShrink: 0 }}>
              <CreditCard size={20} />
            </div>
            <div>
              <div style={{ fontSize: "17px", fontWeight: "800", color: "#1C1A2D" }}>{formatVND(summaryTotals.totalQr)}</div>
              <div style={{ fontSize: "12px", fontWeight: "600", color: "#5D5B63" }}>Chuyển khoản (VietQR)</div>
              <div style={{ fontSize: "11px", color: "#8B8FA8" }}>
                {paymentMethods.TRANSFER_QR?.billCount || 0} đơn ({paymentMethods.TRANSFER_QR?.proportion || 0}%)
              </div>
            </div>
          </div>
        </div>

        <div className="stat-card">
          <div style={{ display: "flex", gap: "12px", alignItems: "center" }}>
            <div style={{ width: "42px", height: "42px", borderRadius: "10px", background: "#D9770618", display: "flex", alignItems: "center", justifyContent: "center", color: "#D97706", flexShrink: 0 }}>
              <CreditCard size={20} />
            </div>
            <div>
              <div style={{ fontSize: "17px", fontWeight: "800", color: "#1C1A2D" }}>{formatVND(summaryTotals.totalCard)}</div>
              <div style={{ fontSize: "12px", fontWeight: "600", color: "#5D5B63" }}>Thẻ POS / Ví điện tử</div>
              <div style={{ fontSize: "11px", color: "#8B8FA8" }}>
                {paymentMethods.CARD?.billCount || 0} đơn ({paymentMethods.CARD?.proportion || 0}%)
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Serving tables notification */}
      {servingCount > 0 && (
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
                Ước tính cả ngày: <strong>{formatVND(summaryTotals.totalNet + servingTotal)}</strong> (Đã thu: {formatVND(summaryTotals.totalNet)} + Đang dùng: {formatVND(servingTotal)})
              </div>
            </div>
          </div>
          <div style={{ display: "flex", gap: "8px", flexWrap: "wrap", alignItems: "center" }}>
            {servingTables.slice(0, 4).map((st) => (
              <span key={st.id || st.name} style={{ background: "#FFFFFF", border: "1px solid #93C5FD", borderRadius: "8px", padding: "4px 10px", fontSize: "12px", color: "#1E40AF" }}>
                {st.name} ({st.zone}): <strong>{formatVND(getTableServingTotal(st))}</strong>
              </span>
            ))}
          </div>
        </div>
      )}

      {/* Bar Chart */}
      <div className="card" style={{ padding: "20px" }}>
        <h2 style={{ fontSize: "16px", fontWeight: "700", color: "#1C1A2D", marginBottom: "20px" }}>
          Biểu đồ Doanh thu theo {period === "DAY" ? "Ngày" : period === "WEEK" ? "Tuần" : period === "MONTH" ? "Tháng" : "Năm"}
        </h2>
        {chartData.length === 0 ? (
          <div style={{ textAlign: "center", padding: "40px", color: "#8B8FA8" }}>
            Chưa có dữ liệu doanh thu cho kỳ này
          </div>
        ) : (
          <ResponsiveContainer width="100%" height={280}>
            <BarChart data={chartData}>
              <CartesianGrid strokeDasharray="3 3" stroke="#ECE5D8" />
              <XAxis dataKey="label" tick={{ fill: "#5D5B63", fontSize: 12 }} axisLine={false} tickLine={false} />
              <YAxis tick={{ fill: "#5D5B63", fontSize: 11 }} axisLine={false} tickLine={false} tickFormatter={(v) => `${(v / 1000).toFixed(0)}k`} />
              <Tooltip content={<CustomTooltip />} />
              <Bar dataKey="netRevenue" fill="#7E2930" radius={[6, 6, 0, 0]} maxBarSize={40} />
            </BarChart>
          </ResponsiveContainer>
        )}
      </div>

      {/* Detail Table */}
      <div className="card" style={{ padding: "20px" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "16px" }}>
          <h2 style={{ fontSize: "16px", fontWeight: "700", color: "#1C1A2D", margin: 0 }}>
            Chi tiết Doanh thu theo Kỳ ({periodItems.length} mốc)
          </h2>
          <span style={{ fontSize: "12px", color: "#8B8FA8" }}>Múi giờ chuẩn: UTC+7</span>
        </div>

        <div style={{ overflowX: "auto" }}>
          <table style={{ width: "100%", borderCollapse: "collapse", textAlign: "left", fontSize: "13px" }}>
            <thead>
              <tr style={{ borderBottom: "2px solid #E6DEC8", color: "#666", background: "#FAF7F2" }}>
                <th style={{ padding: "10px 12px" }}>Thời gian</th>
                <th style={{ padding: "10px 12px", textAlign: "right" }}>Số đơn</th>
                <th style={{ padding: "10px 12px", textAlign: "right" }}>Doanh thu gộp</th>
                <th style={{ padding: "10px 12px", textAlign: "right" }}>Giảm giá</th>
                <th style={{ padding: "10px 12px", textAlign: "right" }}>Tiền thuế VAT</th>
                <th style={{ padding: "10px 12px", textAlign: "right" }}>Doanh thu thuần</th>
                <th style={{ padding: "10px 12px", textAlign: "right" }}>Tiền mặt</th>
                <th style={{ padding: "10px 12px", textAlign: "right" }}>Chuyển khoản</th>
                <th style={{ padding: "10px 12px", textAlign: "right" }}>Thẻ POS</th>
                <th style={{ padding: "10px 12px", textAlign: "right" }}>Tỷ trọng</th>
              </tr>
            </thead>
            <tbody>
              {periodItems.length === 0 ? (
                <tr>
                  <td colSpan={10} style={{ textAlign: "center", padding: "32px", color: "#8B8FA8" }}>
                    Không có bản ghi doanh thu nào trong kỳ này
                  </td>
                </tr>
              ) : (
                periodItems.map((item) => (
                  <tr key={item.periodKey} style={{ borderBottom: "1px solid #F0ECE1" }}>
                    <td style={{ padding: "10px 12px", fontWeight: "700", color: "#1C1A2D" }}>
                      {item.periodLabel}
                    </td>
                    <td style={{ padding: "10px 12px", textAlign: "right" }}>{formatNumber(item.billCount)}</td>
                    <td style={{ padding: "10px 12px", textAlign: "right" }}>{formatVND(item.grossRevenue)}</td>
                    <td style={{ padding: "10px 12px", textAlign: "right", color: item.discountAmount > 0 ? "#C93B2B" : "#8B8FA8" }}>
                      {formatVND(item.discountAmount)}
                    </td>
                    <td style={{ padding: "10px 12px", textAlign: "right" }}>{formatVND(item.vatAmount)}</td>
                    <td style={{ padding: "10px 12px", textAlign: "right", fontWeight: "800", color: "#7E2930", background: "#FFF5F6" }}>
                      {formatVND(item.netRevenue)}
                    </td>
                    <td style={{ padding: "10px 12px", textAlign: "right", color: "#146A65", fontWeight: "600" }}>
                      {formatVND(item.cashRevenue)}
                    </td>
                    <td style={{ padding: "10px 12px", textAlign: "right", color: "#1877F2", fontWeight: "600" }}>
                      {formatVND(item.qrRevenue)}
                    </td>
                    <td style={{ padding: "10px 12px", textAlign: "right", color: "#D97706", fontWeight: "600" }}>
                      {formatVND(item.cardRevenue)}
                    </td>
                    <td style={{ padding: "10px 12px", textAlign: "right", color: "#5D5B63", fontWeight: "600" }}>
                      {item.proportion}%
                    </td>
                  </tr>
                ))
              )}
            </tbody>
            {periodItems.length > 0 && (
              <tfoot>
                <tr style={{ background: "#F8F4EE", fontWeight: "800", borderTop: "2px solid #7E2930" }}>
                  <td style={{ padding: "12px", color: "#7E2930" }}>TỔNG CỘNG</td>
                  <td style={{ padding: "12px", textAlign: "right" }}>{formatNumber(summaryTotals.totalBills)}</td>
                  <td style={{ padding: "12px", textAlign: "right" }}>{formatVND(summaryTotals.totalGross)}</td>
                  <td style={{ padding: "12px", textAlign: "right", color: "#C93B2B" }}>{formatVND(summaryTotals.totalDiscount)}</td>
                  <td style={{ padding: "12px", textAlign: "right" }}>{formatVND(summaryTotals.totalVat)}</td>
                  <td style={{ padding: "12px", textAlign: "right", color: "#7E2930" }}>{formatVND(summaryTotals.totalNet)}</td>
                  <td style={{ padding: "12px", textAlign: "right", color: "#146A65" }}>{formatVND(summaryTotals.totalCash)}</td>
                  <td style={{ padding: "12px", textAlign: "right", color: "#1877F2" }}>{formatVND(summaryTotals.totalQr)}</td>
                  <td style={{ padding: "12px", textAlign: "right", color: "#D97706" }}>{formatVND(summaryTotals.totalCard)}</td>
                  <td style={{ padding: "12px", textAlign: "right" }}>100%</td>
                </tr>
              </tfoot>
            )}
          </table>
        </div>
      </div>
    </div>
  );
}
