"use client";
import React, { useState, useMemo } from "react";
import { useDashboardData, ProductItem } from "@/lib/data-context";
import {
  calculateProductReport,
  calculateCategoryReport,
  calculateGrossProfitReport,
  formatVND,
  formatNumber,
  getBillTimestamp,
  getUTC7Date,
  ProductReportItem,
  CategoryReportItem,
  GrossProfitReportResult,
} from "@/lib/reports";
import {
  exportProductSalesReport,
  exportCategorySalesReport,
  exportGrossProfitReport,
  ReportStoreInfo,
} from "@/lib/export";
import {
  Calendar,
  Store,
  Search,
  Download,
  Printer,
  Package,
  Layers,
  TrendingUp,
} from "lucide-react";

export default function ProductSalesReportPage() {
  const { stores, currentStoreCode, setCurrentStoreCode, historyData, products, categories } = useDashboardData();

  const [activeTab, setActiveTab] = useState<"product" | "category" | "profit">("product");
  const [dateRange, setDateRange] = useState<"TODAY" | "YESTERDAY" | "7DAYS" | "THIS_MONTH" | "LAST_MONTH" | "CUSTOM">("TODAY");
  const [customStart, setCustomStart] = useState("");
  const [customEnd, setCustomEnd] = useState("");
  const [searchQuery, setSearchQuery] = useState("");
  const [selectedCategory, setSelectedCategory] = useState("ALL");
  const [sortBy, setSortBy] = useState<"REV_DESC" | "QTY_DESC" | "NAME_ASC">("REV_DESC");

  // Current store info
  const currentStore = useMemo(() => {
    if (currentStoreCode === "ALL") return stores[0];
    return stores.find((s) => s.storeCode === currentStoreCode) || stores[0];
  }, [stores, currentStoreCode]);

  // Date range label
  const dateRangeLabel = useMemo(() => {
    const now = new Date();
    switch (dateRange) {
      case "TODAY":
        return `Hôm nay (${now.toLocaleDateString("vi-VN")})`;
      case "YESTERDAY": {
        const y = new Date(now);
        y.setDate(y.getDate() - 1);
        return `Hôm qua (${y.toLocaleDateString("vi-VN")})`;
      }
      case "7DAYS": {
        const s = new Date(now);
        s.setDate(s.getDate() - 7);
        return `7 ngày qua (${s.toLocaleDateString("vi-VN")} - ${now.toLocaleDateString("vi-VN")})`;
      }
      case "THIS_MONTH":
        return `Tháng ${now.getMonth() + 1}/${now.getFullYear()}`;
      case "LAST_MONTH": {
        const lm = new Date(now.getFullYear(), now.getMonth() - 1, 1);
        return `Tháng ${lm.getMonth() + 1}/${lm.getFullYear()}`;
      }
      case "CUSTOM":
        return customStart
          ? `Từ ${new Date(customStart).toLocaleDateString("vi-VN")} đến ${new Date(customEnd || customStart).toLocaleDateString("vi-VN")}`
          : "Tùy chọn ngày";
      default:
        return "Hôm nay";
    }
  }, [dateRange, customStart, customEnd]);

  // Date filtering logic (UTC+7)
  const filteredBills = useMemo(() => {
    const now = new Date();
    const nowUTC7 = getUTC7Date(now.getTime());
    const todayYear = nowUTC7.getUTCFullYear();
    const todayMonth = nowUTC7.getUTCMonth();
    const todayDate = nowUTC7.getUTCDate();

    return historyData.filter((b) => {
      if (currentStoreCode !== "ALL" && b.storeCode && b.storeCode !== currentStoreCode) return false;

      const ts = getBillTimestamp(b);
      const bDate = getUTC7Date(ts);
      const bYear = bDate.getUTCFullYear();
      const bMonth = bDate.getUTCMonth();
      const bDay = bDate.getUTCDate();

      switch (dateRange) {
        case "TODAY":
          return bYear === todayYear && bMonth === todayMonth && bDay === todayDate;
        case "YESTERDAY": {
          const yest = new Date(Date.UTC(todayYear, todayMonth, todayDate - 1));
          return bYear === yest.getUTCFullYear() && bMonth === yest.getUTCMonth() && bDay === yest.getUTCDate();
        }
        case "7DAYS": {
          const sevenDaysAgo = Date.UTC(todayYear, todayMonth, todayDate - 7);
          return ts >= sevenDaysAgo && ts <= now.getTime();
        }
        case "THIS_MONTH":
          return bYear === todayYear && bMonth === todayMonth;
        case "LAST_MONTH": {
          const lm = new Date(Date.UTC(todayYear, todayMonth - 1, 1));
          return bYear === lm.getUTCFullYear() && bMonth === lm.getUTCMonth();
        }
        case "CUSTOM": {
          if (!customStart) return true;
          const s = new Date(customStart + "T00:00:00").getTime();
          const e = customEnd ? new Date(customEnd + "T23:59:59").getTime() : new Date(customStart + "T23:59:59").getTime();
          return ts >= s && ts <= e;
        }
        default:
          return true;
      }
    });
  }, [historyData, currentStoreCode, dateRange, customStart, customEnd]);

  // Build products lookup map with costPrice
  const productsMap = useMemo(() => {
    const map: Record<string | number, ProductItem> = {};
    products.forEach((p) => {
      if (p.id != null) map[p.id] = p;
      const pid = (p as { productId?: string | number }).productId;
      if (pid != null) map[pid] = p;
      if (p.name) map[p.name] = p;
    });
    return map;
  }, [products]);

  // Pure report calculations
  const productReports = useMemo<ProductReportItem[]>(() => {
    const list = calculateProductReport(filteredBills, productsMap);
    let res = list;
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase();
      res = res.filter((p) => p.productName.toLowerCase().includes(q) || (p.productCode || "").toLowerCase().includes(q));
    }
    if (selectedCategory !== "ALL") {
      res = res.filter((p) => p.category === selectedCategory);
    }
    if (sortBy === "QTY_DESC") {
      res.sort((a, b) => b.quantity - a.quantity);
    } else if (sortBy === "REV_DESC") {
      res.sort((a, b) => b.netRevenue - a.netRevenue);
    } else {
      res.sort((a, b) => a.productName.localeCompare(b.productName));
    }
    return res;
  }, [filteredBills, productsMap, searchQuery, selectedCategory, sortBy]);

  const categoryReports = useMemo<CategoryReportItem[]>(() => {
    return calculateCategoryReport(filteredBills, productsMap);
  }, [filteredBills, productsMap]);

  const grossProfitReport = useMemo<GrossProfitReportResult>(() => {
    return calculateGrossProfitReport(filteredBills, productsMap);
  }, [filteredBills, productsMap]);

  // Summary Metrics
  const totalQuantity = useMemo(() => productReports.reduce((s, p) => s + p.quantity, 0), [productReports]);
  const totalNetRevenue = useMemo(() => productReports.reduce((s, p) => s + p.netRevenue, 0), [productReports]);
  const totalCOGS = useMemo(() => productReports.reduce((s, p) => s + p.costPrice, 0), [productReports]);
  const totalGrossProfit = totalNetRevenue - totalCOGS;
  const grossProfitMargin = totalNetRevenue > 0 ? Number(((totalGrossProfit / totalNetRevenue) * 100).toFixed(2)) : 0;

  // Export Handlers
  const handleExportExcel = () => {
    const storeInfo: ReportStoreInfo = {
      storeName: currentStore?.storeName || "POS Trạm",
      address: currentStore?.address || "Đà Lạt, Lâm Đồng",
      phone: currentStore?.phone || "0987.654.321",
      storeCode: currentStoreCode === "ALL" ? "ALL" : currentStore?.storeCode,
    };

    if (activeTab === "product") {
      exportProductSalesReport(productReports, storeInfo, dateRangeLabel).toExcel();
    } else if (activeTab === "category") {
      exportCategorySalesReport(categoryReports, storeInfo, dateRangeLabel).toExcel();
    } else {
      exportGrossProfitReport(grossProfitReport, storeInfo, dateRangeLabel).toExcel();
    }
  };

  const handlePrintPDF = () => {
    const storeInfo: ReportStoreInfo = {
      storeName: currentStore?.storeName || "POS Trạm",
      address: currentStore?.address || "Đà Lạt, Lâm Đồng",
      phone: currentStore?.phone || "0987.654.321",
      storeCode: currentStoreCode === "ALL" ? "ALL" : currentStore?.storeCode,
    };

    if (activeTab === "product") {
      exportProductSalesReport(productReports, storeInfo, dateRangeLabel).toPDF();
    } else if (activeTab === "category") {
      exportCategorySalesReport(categoryReports, storeInfo, dateRangeLabel).toPDF();
    } else {
      exportGrossProfitReport(grossProfitReport, storeInfo, dateRangeLabel).toPDF();
    }
  };

  return (
    <div style={{ padding: "24px 28px", maxWidth: "1280px", margin: "0 auto" }}>
      {/* Top Header Card */}
      <div
        style={{
          background: "var(--surface)",
          borderRadius: "16px",
          border: "1px solid var(--border)",
          padding: "20px 24px",
          marginBottom: "20px",
          boxShadow: "0 2px 10px rgba(0,0,0,0.03)",
        }}
      >
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: "16px" }}>
          <div>
            <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
              <h1 style={{ fontSize: "22px", fontWeight: "800", color: "var(--text)", margin: 0 }}>
                Báo cáo hàng hoá & Hiệu suất món ăn 🍹
              </h1>
              <span
                style={{
                  background: "var(--primary-light)",
                  color: "var(--primary)",
                  padding: "4px 10px",
                  borderRadius: "20px",
                  fontSize: "12px",
                  fontWeight: "700",
                }}
              >
                KiotViet Dual Parity
              </span>
            </div>
            <p style={{ fontSize: "13px", color: "var(--subtext)", marginTop: "4px", margin: 0 }}>
              Thống kê sản lượng tiêu thụ, doanh số nhóm hàng và biên lợi nhuận gộp theo giá vốn (COGS)
            </p>
          </div>

          {/* Action buttons & Filters */}
          <div style={{ display: "flex", alignItems: "center", gap: "10px", flexWrap: "wrap" }}>
            <button
              onClick={handlePrintPDF}
              style={{
                display: "flex",
                alignItems: "center",
                gap: "6px",
                background: "var(--primary)",
                color: "#FFFFFF",
                border: "none",
                borderRadius: "10px",
                padding: "8px 14px",
                fontSize: "13px",
                fontWeight: "700",
                cursor: "pointer",
              }}
            >
              <Printer size={15} /> In / PDF
            </button>

            <button
              onClick={handleExportExcel}
              style={{
                display: "flex",
                alignItems: "center",
                gap: "6px",
                background: "var(--success)",
                color: "#FFFFFF",
                border: "none",
                borderRadius: "10px",
                padding: "8px 14px",
                fontSize: "13px",
                fontWeight: "700",
                cursor: "pointer",
              }}
            >
              <Download size={15} /> Xuất Excel
            </button>

            {/* Date Range Selector */}
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: "8px",
                background: "var(--bg)",
                border: "1px solid var(--border)",
                borderRadius: "10px",
                padding: "6px 12px",
              }}
            >
              <Calendar size={16} color="#7E2930" />
              <select
                value={dateRange}
                onChange={(e) => setDateRange(e.target.value as typeof dateRange)}
                style={{
                  background: "transparent",
                  border: "none",
                  outline: "none",
                  fontSize: "13px",
                  fontWeight: "600",
                  color: "var(--text)",
                  cursor: "pointer",
                }}
              >
                <option value="TODAY">Hôm nay</option>
                <option value="YESTERDAY">Hôm qua</option>
                <option value="7DAYS">7 ngày qua</option>
                <option value="THIS_MONTH">Tháng này</option>
                <option value="LAST_MONTH">Tháng trước</option>
                <option value="CUSTOM">Tùy chọn ngày</option>
              </select>
            </div>

            {dateRange === "CUSTOM" && (
              <div style={{ display: "flex", alignItems: "center", gap: "6px" }}>
                <input
                  type="date"
                  value={customStart}
                  onChange={(e) => setCustomStart(e.target.value)}
                  style={{
                    padding: "6px 10px",
                    borderRadius: "8px",
                    border: "1px solid var(--border)",
                    fontSize: "12px",
                  }}
                />
                <span style={{ fontSize: "12px", color: "var(--subtext)" }}>đến</span>
                <input
                  type="date"
                  value={customEnd}
                  onChange={(e) => setCustomEnd(e.target.value)}
                  style={{
                    padding: "6px 10px",
                    borderRadius: "8px",
                    border: "1px solid var(--border)",
                    fontSize: "12px",
                  }}
                />
              </div>
            )}

            {/* Store Selector */}
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: "8px",
                background: "var(--bg)",
                border: "1px solid var(--border)",
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
                  color: "var(--text)",
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
          </div>
        </div>

        {/* 3 Tabs Bar */}
        <div style={{ display: "flex", gap: "8px", marginTop: "20px", borderBottom: "1px solid var(--border)", paddingBottom: "1px" }}>
          {[
            { id: "product", label: "Món ăn / Hàng hóa (BC 4)", icon: <Package size={16} /> },
            { id: "category", label: "Nhóm hàng / Danh mục (BC 3)", icon: <Layers size={16} /> },
            { id: "profit", label: "Lợi nhuận gộp & Giá vốn (BC 11)", icon: <TrendingUp size={16} /> },
          ].map((tab) => {
            const active = activeTab === tab.id;
            return (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id as typeof activeTab)}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: "6px",
                  padding: "10px 18px",
                  fontSize: "14px",
                  fontWeight: active ? "700" : "500",
                  color: active ? "var(--primary)" : "var(--subtext)",
                  borderBottom: active ? "3px solid var(--primary)" : "3px solid transparent",
                  background: "transparent",
                  borderTop: "none",
                  borderLeft: "none",
                  borderRight: "none",
                  cursor: "pointer",
                  transition: "all 0.2s",
                }}
              >
                {tab.icon}
                {tab.label}
              </button>
            );
          })}
        </div>
      </div>

      {/* KPI Summary Cards */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(min(220px, 100%), 1fr))", gap: "14px", marginBottom: "20px" }}>
        <div style={{ padding: "16px", background: "var(--surface)", borderRadius: "14px", border: "1px solid var(--border)", boxShadow: "0 2px 6px rgba(0,0,0,0.02)" }}>
          <div style={{ fontSize: "12px", color: "var(--subtext)", fontWeight: "600" }}>Tổng sản lượng bán</div>
          <div style={{ fontSize: "22px", fontWeight: "800", color: "var(--text)", marginTop: "4px" }}>
            {formatNumber(totalQuantity)} phần/ly
          </div>
          <div style={{ fontSize: "11px", color: "var(--muted)", marginTop: "2px" }}>
            {productReports.length} mặt hàng phát sinh
          </div>
        </div>

        <div style={{ padding: "16px", background: "var(--surface)", borderRadius: "14px", border: "1px solid var(--border)", boxShadow: "0 2px 6px rgba(0,0,0,0.02)" }}>
          <div style={{ fontSize: "12px", color: "var(--subtext)", fontWeight: "600" }}>Doanh thu thực tế</div>
          <div style={{ fontSize: "22px", fontWeight: "800", color: "var(--primary)", marginTop: "4px" }}>
            {formatVND(totalNetRevenue)}
          </div>
          <div style={{ fontSize: "11px", color: "var(--muted)", marginTop: "2px" }}>
            Đã trừ giảm giá dòng món
          </div>
        </div>

        <div style={{ padding: "16px", background: "var(--surface)", borderRadius: "14px", border: "1px solid var(--border)", boxShadow: "0 2px 6px rgba(0,0,0,0.02)" }}>
          <div style={{ fontSize: "12px", color: "var(--subtext)", fontWeight: "600" }}>Tổng giá vốn (COGS)</div>
          <div style={{ fontSize: "22px", fontWeight: "800", color: "var(--success)", marginTop: "4px" }}>
            {formatVND(totalCOGS)}
          </div>
          <div style={{ fontSize: "11px", color: "var(--muted)", marginTop: "2px" }}>
            Dựa trên costPrice của món
          </div>
        </div>

        <div style={{ padding: "16px", background: "var(--surface)", borderRadius: "14px", border: "1px solid var(--border)", boxShadow: "0 2px 6px rgba(0,0,0,0.02)" }}>
          <div style={{ fontSize: "12px", color: "var(--subtext)", fontWeight: "600" }}>Lợi nhuận gộp & Tỷ suất</div>
          <div style={{ fontSize: "22px", fontWeight: "800", color: "var(--warning)", marginTop: "4px" }}>
            {formatVND(totalGrossProfit)}
          </div>
          <div style={{ fontSize: "11px", color: "var(--muted)", marginTop: "2px" }}>
            Biên lợi nhuận: <strong style={{ color: "var(--warning)" }}>{grossProfitMargin}%</strong>
          </div>
        </div>
      </div>

      {/* ==================== TAB 1: MÓN ĂN / HÀNG HÓA ==================== */}
      {activeTab === "product" && (
        <div
          style={{
            background: "var(--surface)",
            borderRadius: "16px",
            border: "1px solid var(--border)",
            padding: "20px",
          }}
        >
          {/* Controls Bar */}
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: "12px", marginBottom: "16px" }}>
            <div style={{ display: "flex", alignItems: "center", gap: "10px", flex: 1, maxWidth: "420px" }}>
              <div
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: "8px",
                  background: "var(--bg)",
                  border: "1px solid var(--border)",
                  borderRadius: "10px",
                  padding: "6px 12px",
                  width: "100%",
                }}
              >
                <Search size={16} color="#666" />
                <input
                  type="text"
                  placeholder="Tìm kiếm theo mã món, tên món..."
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  style={{
                    background: "transparent",
                    border: "none",
                    outline: "none",
                    fontSize: "13px",
                    width: "100%",
                  }}
                />
              </div>
            </div>

            <div style={{ display: "flex", alignItems: "center", gap: "10px", flexWrap: "wrap" }}>
              {/* Category Filter */}
              <select
                value={selectedCategory}
                onChange={(e) => setSelectedCategory(e.target.value)}
                style={{
                  padding: "6px 12px",
                  borderRadius: "10px",
                  border: "1px solid var(--border)",
                  fontSize: "13px",
                  fontWeight: "600",
                  background: "var(--surface)",
                  cursor: "pointer",
                }}
              >
                <option value="ALL">📁 Tất cả nhóm hàng</option>
                {categories.map((c) => (
                  <option key={c.id || c.name} value={c.name}>
                    {c.name}
                  </option>
                ))}
              </select>

              {/* Sort by */}
              <select
                value={sortBy}
                onChange={(e) => setSortBy(e.target.value as typeof sortBy)}
                style={{
                  padding: "6px 12px",
                  borderRadius: "10px",
                  border: "1px solid var(--border)",
                  fontSize: "13px",
                  fontWeight: "600",
                  background: "var(--surface)",
                  cursor: "pointer",
                }}
              >
                <option value="REV_DESC">Doanh thu giảm dần</option>
                <option value="QTY_DESC">Số lượng bán giảm dần</option>
                <option value="NAME_ASC">Tên món A-Z</option>
              </select>
            </div>
          </div>

          {/* Table */}
          <div style={{ overflowX: "auto" }}>
            <table style={{ width: "100%", borderCollapse: "collapse", textAlign: "left", fontSize: "13px" }}>
              <thead>
                <tr style={{ borderBottom: "2px solid var(--border)", color: "var(--subtext)", background: "var(--surface-muted)" }}>
                  <th style={{ padding: "10px 12px" }}>Mã món</th>
                  <th style={{ padding: "10px 12px" }}>Tên món ăn / Đồ uống</th>
                  <th style={{ padding: "10px 12px" }}>Nhóm hàng</th>
                  <th style={{ padding: "10px 12px", textAlign: "center" }}>ĐVT</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Đơn giá</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>SL bán</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Doanh thu gộp</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Giảm giá món</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Doanh thu thực tế</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Giá vốn / ly</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Lợi nhuận gộp</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Tỷ suất LN</th>
                </tr>
              </thead>
              <tbody>
                {productReports.length === 0 ? (
                  <tr>
                    <td colSpan={12} style={{ textAlign: "center", padding: "36px", color: "var(--muted)" }}>
                      Không có sản phẩm nào bán ra trong khoảng thời gian đã chọn
                    </td>
                  </tr>
                ) : (
                  productReports.map((p, idx) => (
                    <tr key={String(p.productId) + '-' + idx} style={{ borderBottom: "1px solid #F0ECE1" }}>
                      <td style={{ padding: "10px 12px", fontFamily: "monospace", color: "var(--muted)" }}>
                        {p.productCode || "—"}
                      </td>
                      <td style={{ padding: "10px 12px", fontWeight: "700", color: "var(--text)" }}>{p.productName}</td>
                      <td style={{ padding: "10px 12px", color: "var(--subtext)" }}>{p.category}</td>
                      <td style={{ padding: "10px 12px", textAlign: "center" }}>{p.unit}</td>
                      <td style={{ padding: "10px 12px", textAlign: "right" }}>{formatVND(p.basePrice)}</td>
                      <td style={{ padding: "10px 12px", textAlign: "right", fontWeight: "700", color: "var(--text)" }}>
                        {p.quantity}
                      </td>
                      <td style={{ padding: "10px 12px", textAlign: "right" }}>{formatVND(p.grossRevenue)}</td>
                      <td style={{ padding: "10px 12px", textAlign: "right", color: p.itemDiscount > 0 ? "#C93B2B" : "var(--muted)" }}>
                        {formatVND(p.itemDiscount)}
                      </td>
                      <td style={{ padding: "10px 12px", textAlign: "right", fontWeight: "800", color: "var(--primary)", background: "var(--primary-light)" }}>
                        {formatVND(p.netRevenue)}
                      </td>
                      <td style={{ padding: "10px 12px", textAlign: "right", color: "var(--success)" }}>
                        {formatVND(p.quantity > 0 ? Math.round(p.costPrice / p.quantity) : 0)}
                      </td>
                      <td style={{ padding: "10px 12px", textAlign: "right", fontWeight: "700", color: p.grossProfit >= 0 ? "var(--success)" : "#C93B2B" }}>
                        {formatVND(p.grossProfit)}
                      </td>
                      <td style={{ padding: "10px 12px", textAlign: "right", color: "var(--subtext)" }}>
                        {p.grossProfitMarginPercent}%
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* ==================== TAB 2: NHÓM HÀNG / DANH MỤC ==================== */}
      {activeTab === "category" && (
        <div
          style={{
            background: "var(--surface)",
            borderRadius: "16px",
            border: "1px solid var(--border)",
            padding: "20px",
          }}
        >
          <div style={{ fontSize: "15px", fontWeight: "700", color: "var(--text)", marginBottom: "16px" }}>
            Báo cáo Doanh thu theo Nhóm hàng / Danh mục ({categoryReports.length} nhóm)
          </div>

          <div style={{ overflowX: "auto" }}>
            <table style={{ width: "100%", borderCollapse: "collapse", textAlign: "left", fontSize: "13px" }}>
              <thead>
                <tr style={{ borderBottom: "2px solid var(--border)", color: "var(--subtext)", background: "var(--surface-muted)" }}>
                  <th style={{ padding: "10px 12px" }}>STT</th>
                  <th style={{ padding: "10px 12px" }}>Nhóm hàng / Danh mục</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Số lượng bán</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Doanh thu gộp</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Giảm giá món</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Doanh thu thực tế</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Giá vốn (COGS)</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Lợi nhuận gộp</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Tỷ suất LN (%)</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Tỷ trọng (%)</th>
                </tr>
              </thead>
              <tbody>
                {categoryReports.length === 0 ? (
                  <tr>
                    <td colSpan={10} style={{ textAlign: "center", padding: "36px", color: "var(--muted)" }}>
                      Không có dữ liệu nhóm hàng trong khoảng thời gian đã chọn
                    </td>
                  </tr>
                ) : (
                  categoryReports.map((cat, idx) => (
                    <tr key={cat.category} style={{ borderBottom: "1px solid #F0ECE1" }}>
                      <td style={{ padding: "10px 12px", color: "var(--muted)" }}>{idx + 1}</td>
                      <td style={{ padding: "10px 12px", fontWeight: "700", color: "var(--text)" }}>{cat.category}</td>
                      <td style={{ padding: "10px 12px", textAlign: "right", fontWeight: "600" }}>{cat.quantity}</td>
                      <td style={{ padding: "10px 12px", textAlign: "right" }}>{formatVND(cat.grossRevenue)}</td>
                      <td style={{ padding: "10px 12px", textAlign: "right", color: cat.itemDiscount > 0 ? "#C93B2B" : "var(--muted)" }}>
                        {formatVND(cat.itemDiscount)}
                      </td>
                      <td style={{ padding: "10px 12px", textAlign: "right", fontWeight: "800", color: "var(--primary)", background: "var(--primary-light)" }}>
                        {formatVND(cat.netRevenue)}
                      </td>
                      <td style={{ padding: "10px 12px", textAlign: "right", color: "var(--success)" }}>{formatVND(cat.costPrice)}</td>
                      <td style={{ padding: "10px 12px", textAlign: "right", fontWeight: "700", color: cat.grossProfit >= 0 ? "var(--success)" : "#C93B2B" }}>
                        {formatVND(cat.grossProfit)}
                      </td>
                      <td style={{ padding: "10px 12px", textAlign: "right", color: "var(--subtext)" }}>{cat.grossProfitMarginPercent}%</td>
                      <td style={{ padding: "10px 12px", textAlign: "right", fontWeight: "600", color: "var(--subtext)" }}>
                        {cat.proportion}%
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* ==================== TAB 3: LỢI NHUẬN GỘP & GIÁ VỐN ==================== */}
      {activeTab === "profit" && (
        <div
          style={{
            background: "var(--surface)",
            borderRadius: "16px",
            border: "1px solid var(--border)",
            padding: "20px",
          }}
        >
          <div style={{ fontSize: "15px", fontWeight: "700", color: "var(--text)", marginBottom: "16px" }}>
            Báo cáo Phân tích Lợi nhuận gộp & Giá vốn hàng bán (COGS)
          </div>

          <div style={{ overflowX: "auto" }}>
            <table style={{ width: "100%", borderCollapse: "collapse", textAlign: "left", fontSize: "13px" }}>
              <thead>
                <tr style={{ borderBottom: "2px solid var(--border)", color: "var(--subtext)", background: "var(--surface-muted)" }}>
                  <th style={{ padding: "10px 12px" }}>Tên món ăn / Đồ uống</th>
                  <th style={{ padding: "10px 12px" }}>Nhóm hàng</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Số lượng bán</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Giá bán bình quân</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Giá vốn bình quân</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Doanh thu thực tế</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Tổng giá vốn (COGS)</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Lợi nhuận gộp</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Tỷ suất LN (%)</th>
                </tr>
              </thead>
              <tbody>
                {grossProfitReport.items.length === 0 ? (
                  <tr>
                    <td colSpan={9} style={{ textAlign: "center", padding: "36px", color: "var(--muted)" }}>
                      Không có dữ liệu lợi nhuận trong khoảng thời gian đã chọn
                    </td>
                  </tr>
                ) : (
                  grossProfitReport.items.map((it, idx) => (
                    <tr key={String(it.productId) + '-' + idx} style={{ borderBottom: "1px solid #F0ECE1" }}>
                      <td style={{ padding: "10px 12px", fontWeight: "700", color: "var(--text)" }}>{it.productName}</td>
                      <td style={{ padding: "10px 12px", color: "var(--subtext)" }}>{it.category}</td>
                      <td style={{ padding: "10px 12px", textAlign: "right", fontWeight: "600" }}>{it.quantity}</td>
                      <td style={{ padding: "10px 12px", textAlign: "right" }}>{formatVND(it.avgSellingPrice)}</td>
                      <td style={{ padding: "10px 12px", textAlign: "right", color: "var(--success)" }}>{formatVND(it.avgCostPrice)}</td>
                      <td style={{ padding: "10px 12px", textAlign: "right", fontWeight: "700", color: "var(--primary)" }}>
                        {formatVND(it.netRevenue)}
                      </td>
                      <td style={{ padding: "10px 12px", textAlign: "right", color: "var(--success)" }}>{formatVND(it.cogs)}</td>
                      <td style={{ padding: "10px 12px", textAlign: "right", fontWeight: "800", color: it.grossProfit >= 0 ? "var(--success)" : "#C93B2B", background: "var(--primary-light)" }}>
                        {formatVND(it.grossProfit)}
                      </td>
                      <td style={{ padding: "10px 12px", textAlign: "right", fontWeight: "700", color: "var(--warning)" }}>
                        {it.grossProfitMarginPercent}%
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
              {grossProfitReport.items.length > 0 && (
                <tfoot>
                  <tr style={{ background: "var(--bg)", fontWeight: "800", borderTop: "2px solid var(--primary)" }}>
                    <td style={{ padding: "12px", color: "var(--primary)" }}>TỔNG CỘNG</td>
                    <td style={{ padding: "12px" }}>—</td>
                    <td style={{ padding: "12px", textAlign: "right" }}>{formatNumber(grossProfitReport.summary.totalQuantity)}</td>
                    <td style={{ padding: "12px", textAlign: "right" }}>—</td>
                    <td style={{ padding: "12px", textAlign: "right" }}>—</td>
                    <td style={{ padding: "12px", textAlign: "right", color: "var(--primary)" }}>
                      {formatVND(grossProfitReport.summary.netRevenue)}
                    </td>
                    <td style={{ padding: "12px", textAlign: "right", color: "var(--success)" }}>
                      {formatVND(grossProfitReport.summary.totalCOGS)}
                    </td>
                    <td style={{ padding: "12px", textAlign: "right", color: "var(--success)" }}>
                      {formatVND(grossProfitReport.summary.grossProfit)}
                    </td>
                    <td style={{ padding: "12px", textAlign: "right", color: "var(--warning)" }}>
                      {grossProfitReport.summary.grossProfitMarginPercent}%
                    </td>
                  </tr>
                </tfoot>
              )}
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
