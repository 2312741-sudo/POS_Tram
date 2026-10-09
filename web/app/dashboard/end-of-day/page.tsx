"use client";
import React, { useState, useMemo } from "react";
import { useDashboardData, ProductItem } from "@/lib/data-context";
import {
  generateEndOfDayZReport,
  calculateCancellationReport,
  formatVND,
  getBillTimestamp,
  getUTC7Date,
} from "@/lib/reports";
import { exportEndOfDayZReport, exportProductSalesReport, ReportStoreInfo } from "@/lib/export";
import {
  Calendar,
  Store,
  ChevronRight,
  Search,
  Download,
  Printer,
  User,
} from "lucide-react";

export default function EndOfDayReportPage() {
  const { stores, currentStoreCode, setCurrentStoreCode, historyData, tables, usersList, cashShifts, products } = useDashboardData();

  const [activeTab, setActiveTab] = useState<"tonghop" | "thuchi" | "hanghoa" | "phongban">("tonghop");
  const [dateRange, setDateRange] = useState<"TODAY" | "YESTERDAY" | "7DAYS" | "THIS_MONTH" | "LAST_MONTH" | "CUSTOM">("TODAY");
  const [customStart, setCustomStart] = useState<string>("");
  const [customEnd, setCustomEnd] = useState<string>("");
  const [showServingModal, setShowServingModal] = useState<boolean>(false);

  // Tab Hàng hoá states
  const [productSearch, setProductSearch] = useState<string>("");
  const [productSortBy, setProductSortBy] = useState<"QTY_DESC" | "REV_DESC" | "NAME_ASC">("REV_DESC");
  const [productViewMode, setProductViewMode] = useState<"AMOUNT" | "QUANTITY">("AMOUNT");
  const [productStaffFilter, setProductStaffFilter] = useState<string>("ALL");

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

  // Filter bills by store and date (UTC+7)
  const filteredBills = useMemo(() => {
    const now = new Date();
    const nowUTC7 = getUTC7Date(now.getTime());
    const todayYear = nowUTC7.getUTCFullYear();
    const todayMonth = nowUTC7.getUTCMonth();
    const todayDate = nowUTC7.getUTCDate();

    return historyData.filter((b) => {
      if (currentStoreCode !== "ALL" && b.storeCode && b.storeCode !== currentStoreCode) {
        return false;
      }

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

  // Filter shifts by store and date
  const filteredShifts = useMemo(() => {
    return cashShifts.filter((s) => {
      if (currentStoreCode !== "ALL" && s.storeCode && s.storeCode !== currentStoreCode) {
        return false;
      }
      return true;
    });
  }, [cashShifts, currentStoreCode]);

  // Products lookup map
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

  // Current store metadata
  const currentStore = useMemo(() => {
    if (currentStoreCode === "ALL") return stores[0];
    return stores.find((s) => s.storeCode === currentStoreCode) || stores[0];
  }, [stores, currentStoreCode]);

  // Generate pure EndOfDay Z-Report
  const zReport = useMemo(() => {
    return generateEndOfDayZReport(
      filteredBills,
      filteredShifts,
      tables,
      productsMap,
      {
        date: dateRangeLabel,
        storeCode: currentStoreCode === "ALL" ? "ALL" : currentStore?.storeCode,
        storeName: currentStoreCode === "ALL" ? "Tất cả chi nhánh" : currentStore?.storeName,
      }
    );
  }, [filteredBills, filteredShifts, tables, productsMap, dateRangeLabel, currentStoreCode, currentStore]);

  // Cancellation audit stats
  const cancellationReport = useMemo(() => {
    return calculateCancellationReport(filteredBills);
  }, [filteredBills]);

  // Active serving tables metrics
  const activeTables = useMemo(() => {
    return tables.filter((t) => {
      if (currentStoreCode !== "ALL" && t.storeCode && t.storeCode !== currentStoreCode) return false;
      return t.inUse && !t.mergedIntoTable;
    });
  }, [tables, currentStoreCode]);

  const servingMetrics = useMemo(() => {
    let totalItems = 0;
    let totalGuests = 0;
    let estimatedRevenue = 0;

    activeTables.forEach((t) => {
      totalGuests += t.guestCount || 1;
      let items: Array<{ quantity?: number; count?: number; price?: number; selectedToppings?: Array<{ price?: number }> }> = [];
      if (t.currentOrderJson) {
        try {
          const parsed = typeof t.currentOrderJson === "string" ? JSON.parse(t.currentOrderJson) : t.currentOrderJson;
          if (Array.isArray(parsed)) items = parsed;
        } catch {
          // ignore parsing error
        }
      }
      items.forEach((it) => {
        const qty = it.quantity || it.count || 1;
        const price = Number(it.price || 0);
        let toppingSum = 0;
        if (Array.isArray(it.selectedToppings)) {
          toppingSum = it.selectedToppings.reduce((ts: number, tp) => ts + (tp.price || 0), 0);
        }
        totalItems += qty;
        estimatedRevenue += (price + toppingSum) * qty;
      });
    });

    return {
      tableCount: activeTables.length,
      itemCount: totalItems,
      guestCount: totalGuests,
      estimatedRevenue,
    };
  }, [activeTables]);

  // Extract available staff list
  const availableStaffList = useMemo(() => {
    const staffSet = new Set<string>();
    if (Array.isArray(usersList)) {
      usersList.forEach((u) => {
        const name = (u.fullName || u.username || "").trim();
        if (name) staffSet.add(name);
      });
    }
    historyData.forEach((b) => {
      const billStaff = (b.orderStaff || b.staffFullName || b.cashierName || b.creatorName || b.createdBy || b.username || "").trim();
      if (billStaff) staffSet.add(billStaff);
      if (Array.isArray(b.items)) {
        b.items.forEach((it) => {
          const itStaff = (it.orderedByName || it.orderedBy || "").trim();
          if (itStaff) staffSet.add(itStaff);
        });
      }
    });
    return Array.from(staffSet).filter(Boolean).sort((a, b) => a.localeCompare(b));
  }, [usersList, historyData]);

  // Tab 3: Filtered Product list
  const productSalesList = useMemo(() => {
    let list = [...zReport.tab3_hangHoa.products];

    if (productSearch.trim()) {
      const q = productSearch.toLowerCase();
      list = list.filter((p) => p.productName.toLowerCase().includes(q) || (p.productCode || "").toLowerCase().includes(q));
    }

    if (productSortBy === "QTY_DESC") {
      list.sort((a, b) => b.quantity - a.quantity);
    } else if (productSortBy === "REV_DESC") {
      list.sort((a, b) => b.netRevenue - a.netRevenue);
    } else if (productSortBy === "NAME_ASC") {
      list.sort((a, b) => a.productName.localeCompare(b.productName));
    }

    return list;
  }, [zReport.tab3_hangHoa.products, productSearch, productSortBy]);

  const totalProductQty = useMemo(() => productSalesList.reduce((s, it) => s + it.quantity, 0), [productSalesList]);
  const totalProductRev = useMemo(() => productSalesList.reduce((s, it) => s + it.netRevenue, 0), [productSalesList]);

  // Handle Export Excel & PDF
  const handleExportExcel = () => {
    const storeInfo: ReportStoreInfo = {
      storeName: currentStore?.storeName || "POS Trạm",
      address: currentStore?.address || "Đà Lạt, Lâm Đồng",
      phone: currentStore?.phone || "0987.654.321",
      storeCode: currentStoreCode === "ALL" ? "ALL" : currentStore?.storeCode,
    };
    exportEndOfDayZReport(zReport, storeInfo).toExcel();
  };

  const handlePrintPDF = () => {
    const storeInfo: ReportStoreInfo = {
      storeName: currentStore?.storeName || "POS Trạm",
      address: currentStore?.address || "Đà Lạt, Lâm Đồng",
      phone: currentStore?.phone || "0987.654.321",
      storeCode: currentStoreCode === "ALL" ? "ALL" : currentStore?.storeCode,
    };
    exportEndOfDayZReport(zReport, storeInfo).toPDF();
  };

  const handleExportProductSales = () => {
    const storeInfo: ReportStoreInfo = {
      storeName: currentStore?.storeName || "POS Trạm",
      address: currentStore?.address || "Đà Lạt, Lâm Đồng",
      phone: currentStore?.phone || "0987.654.321",
      storeCode: currentStoreCode === "ALL" ? "ALL" : currentStore?.storeCode,
    };
    exportProductSalesReport(productSalesList, storeInfo, dateRangeLabel).toExcel();
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
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: "16px" }}>
          <div>
            <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
              <h1 style={{ fontSize: "22px", fontWeight: "800", color: "var(--text)", margin: 0 }}>
                Báo cáo tổng hợp cuối ngày (Z-Report)
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
                KiotViet Dual Sync
              </span>
            </div>
            <p style={{ fontSize: "13px", color: "var(--subtext)", marginTop: "4px", margin: 0 }}>
              Thống kê tổng kết bán hàng, thu chi, hàng hoá bán ra và hiệu suất phòng bàn theo thời gian thực (UTC+7)
            </p>
          </div>

          {/* Action buttons & Filters */}
          <div style={{ display: "flex", alignItems: "center", gap: "10px", flexWrap: "wrap" }}>
            {/* Export buttons */}
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

        {/* 4 Tabs Bar */}
        <div style={{ display: "flex", gap: "8px", marginTop: "20px", borderBottom: "1px solid var(--border)", paddingBottom: "1px" }}>
          {[
            { id: "tonghop", label: "Tổng hợp" },
            { id: "thuchi", label: "Thu chi" },
            { id: "hanghoa", label: "Hàng hóa" },
            { id: "phongban", label: "Phòng bàn" },
          ].map((tab) => {
            const active = activeTab === tab.id;
            return (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id as typeof activeTab)}
                style={{
                  padding: "10px 20px",
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
                {tab.label}
              </button>
            );
          })}
        </div>
      </div>

      {/* ==================== TAB 1: TỔNG HỢP ==================== */}
      {activeTab === "tonghop" && (
        <div style={{ display: "flex", flexDirection: "column", gap: "20px" }}>
          {/* Ô DOANH THU ƯỚC TÍNH NGÀY */}
          <div
            style={{
              background: "linear-gradient(135deg, #FFF9F5 0%, var(--surface) 100%)",
              borderRadius: "16px",
              border: "2px solid var(--primary)",
              padding: "20px 24px",
              boxShadow: "0 4px 16px rgba(126, 41, 48, 0.08)",
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
              flexWrap: "wrap",
              gap: "16px",
            }}
          >
            <div>
              <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
                <span
                  style={{
                    background: "var(--primary)",
                    color: "#FFFFFF",
                    padding: "3px 8px",
                    borderRadius: "6px",
                    fontSize: "11px",
                    fontWeight: "800",
                    letterSpacing: "0.5px",
                  }}
                >
                  KPI TRỌNG TÂM
                </span>
                <span style={{ fontSize: "15px", fontWeight: "800", color: "var(--text)" }}>
                  DOANH THU ƯỚC TÍNH NGÀY
                </span>
              </div>
              <div style={{ fontSize: "13px", color: "var(--subtext)", marginTop: "6px" }}>
                Công thức: <strong>Tổng doanh thu</strong> ({formatVND(zReport.tab1_tongHop.netRevenue)}) + <strong>Đơn đang phục vụ</strong> ({formatVND(servingMetrics.estimatedRevenue)} từ {servingMetrics.tableCount} bàn)
              </div>
            </div>
            <div style={{ textAlign: "right" }}>
              <div style={{ fontSize: "28px", fontWeight: "900", color: "var(--primary)" }}>
                {formatVND(zReport.tab1_tongHop.netRevenue + servingMetrics.estimatedRevenue)}
              </div>
              <div style={{ fontSize: "12px", color: "var(--muted)", fontWeight: "600" }}>
                Tổng doanh thu thực tế + Giá trị bàn đang sử dụng
              </div>
            </div>
          </div>

          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(min(460px, 100%), 1fr))", gap: "20px" }}>
            {/* Card 1: TỔNG KẾT BÁN HÀNG */}
            <div
              style={{
                background: "var(--surface)",
                borderRadius: "16px",
                border: "1px solid var(--border)",
                padding: "20px",
                boxShadow: "0 2px 8px rgba(0,0,0,0.02)",
              }}
            >
              <div style={{ fontSize: "13px", fontWeight: "700", color: "var(--subtext)", textTransform: "uppercase", letterSpacing: "0.5px", marginBottom: "12px" }}>
                TỔNG KẾT BÁN HÀNG
              </div>
              <div style={{ display: "flex", flexDirection: "column" }}>
                <ReportRow label="Doanh thu gộp" value={formatVND(zReport.tab1_tongHop.grossRevenue)} />
                <ReportRow label="Tổng giảm giá món" value={formatVND(zReport.tab1_tongHop.itemDiscounts)} />
                <ReportRow label="Tổng giảm giá hóa đơn / Điểm" value={formatVND(zReport.tab1_tongHop.billDiscounts)} />
                <ReportRow label="Tổng tiền giảm giá" value={formatVND(zReport.tab1_tongHop.totalDiscount)} valueColor="#C93B2B" isBold />
                <ReportRow label="Doanh thu sau giảm giá (Pre-VAT)" value={formatVND(zReport.tab1_tongHop.afterDiscount)} />
                <ReportRow
                  label="Doanh thu (Đã thu)"
                  value={formatVND(zReport.tab1_tongHop.netRevenue)}
                  subtitle={`Bao gồm ${formatVND(zReport.tab1_tongHop.vatTotal)} tiền thuế VAT`}
                  valueColor="#7E2930"
                  isBold
                />
                <ReportRow
                  label="Doanh thu ước tính cả ngày"
                  subtitle="Tổng doanh thu + Đơn đang phục vụ"
                  value={formatVND(zReport.tab1_tongHop.netRevenue + servingMetrics.estimatedRevenue)}
                  valueColor="#C47820"
                  isBold
                />
                <ReportRow label="Thu khác" value="0đ" />
                <ReportRow label="Trả hàng / Hoàn tiền" value={formatVND(zReport.tab1_tongHop.refundAmount)} valueColor="#C93B2B" />
                <ReportRow
                  label="Doanh thu thực thu cuối ngày"
                  subtitle="Doanh thu thuần trừ tiền hoàn trả"
                  value={formatVND(zReport.tab1_tongHop.netRevenueWithoutRefund)}
                  isBold
                  valueColor="#146A65"
                />
              </div>
            </div>

            <div style={{ display: "flex", flexDirection: "column", gap: "20px" }}>
              {/* Card 2: ĐANG PHỤC VỤ */}
              <div
                style={{
                  background: "var(--surface)",
                  borderRadius: "16px",
                  border: "1px solid var(--border)",
                  padding: "20px",
                  boxShadow: "0 2px 8px rgba(0,0,0,0.02)",
                }}
              >
                <div
                  onClick={() => setShowServingModal(true)}
                  style={{
                    display: "flex", flexWrap: "wrap", rowGap: "8px",
                    alignItems: "center",
                    justifyContent: "space-between",
                    cursor: "pointer",
                    marginBottom: "12px",
                  }}
                >
                  <div style={{ fontSize: "13px", fontWeight: "700", color: "var(--subtext)", textTransform: "uppercase", letterSpacing: "0.5px" }}>
                    ĐANG PHỤC VỤ
                  </div>
                  <div style={{ display: "flex", alignItems: "center", gap: "4px", fontSize: "12px", color: "var(--primary)", fontWeight: "600" }}>
                    Xem chi tiết bàn <ChevronRight size={14} />
                  </div>
                </div>

                <div style={{ display: "flex", flexDirection: "column" }}>
                  <ReportRow label="Đơn đang phục vụ" value={`${servingMetrics.tableCount} bàn`} />
                  <ReportRow label="Số lượng sản phẩm" value={`${servingMetrics.itemCount} món`} />
                  <ReportRow label="Số khách" value={`${servingMetrics.guestCount} người`} />
                  <ReportRow
                    label="Doanh thu ước tính"
                    value={formatVND(servingMetrics.estimatedRevenue)}
                    valueColor="#C47820"
                    isBold
                  />
                </div>
              </div>

              {/* Card 3: HÓA ĐƠN */}
              <div
                style={{
                  background: "var(--surface)",
                  borderRadius: "16px",
                  border: "1px solid var(--border)",
                  padding: "20px",
                  boxShadow: "0 2px 8px rgba(0,0,0,0.02)",
                }}
              >
                <div style={{ fontSize: "13px", fontWeight: "700", color: "var(--subtext)", textTransform: "uppercase", letterSpacing: "0.5px", marginBottom: "12px" }}>
                  HÓA ĐƠN
                </div>
                <div style={{ display: "flex", flexDirection: "column" }}>
                  <ReportRow label="Số hóa đơn hoàn tất" value={`${zReport.tab1_tongHop.paidBillsCount} đơn`} isBold />
                  <ReportRow label="Số khách phục vụ" value={`${zReport.tab1_tongHop.totalGuests} người`} />
                  <ReportRow label="Doanh thu TB / Đơn" value={formatVND(zReport.tab1_tongHop.avgRevenuePerBill)} isBold />
                </div>
              </div>

              {/* Card 4: HÓA ĐƠN ĐÃ HỦY */}
              <div
                style={{
                  background: "var(--surface)",
                  borderRadius: "16px",
                  border: "1px solid var(--border)",
                  padding: "20px",
                  boxShadow: "0 2px 8px rgba(0,0,0,0.02)",
                }}
              >
                <div style={{ fontSize: "13px", fontWeight: "700", color: "var(--subtext)", textTransform: "uppercase", letterSpacing: "0.5px", marginBottom: "12px" }}>
                  HÓA ĐƠN ĐÃ HỦY (KIỂM TOÁN THẤT THOÁT)
                </div>
                <div style={{ display: "flex", flexDirection: "column" }}>
                  <ReportRow label="Số lượng đơn hủy" value={`${cancellationReport.cancelledBillsCount} đơn`} />
                  <ReportRow
                    label="Giá trị thất thoát"
                    value={formatVND(cancellationReport.totalLossValue)}
                    valueColor="#C93B2B"
                    isBold
                  />
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ==================== TAB 2: THU CHI ==================== */}
      {activeTab === "thuchi" && (
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(min(460px, 100%), 1fr))", gap: "20px" }}>
          <div
            style={{
              background: "var(--surface)",
              borderRadius: "16px",
              border: "1px solid var(--border)",
              padding: "20px",
            }}
          >
            <div style={{ fontSize: "13px", fontWeight: "700", color: "var(--subtext)", textTransform: "uppercase", marginBottom: "14px" }}>
              PHƯƠNG THỨC THANH TOÁN BÁN HÀNG
            </div>
            <ReportRow label="Tiền mặt (CASH)" value={formatVND(zReport.tab2_thuChi.cashSales)} isBold valueColor="#146A65" />
            <ReportRow label="Chuyển khoản VietQR" value={formatVND(zReport.tab2_thuChi.transferSales)} isBold valueColor="#1877F2" />
            <ReportRow label="Thẻ ngân hàng / POS" value={formatVND(zReport.tab2_thuChi.cardSales)} isBold valueColor="#D97706" />
            <ReportRow
              label="TỔNG THỰC THU BÁN HÀNG"
              value={formatVND(zReport.tab2_thuChi.totalRevenue)}
              isBold
              valueColor="#7E2930"
            />
          </div>

          <div
            style={{
              background: "var(--surface)",
              borderRadius: "16px",
              border: "1px solid var(--border)",
              padding: "20px",
            }}
          >
            <div style={{ fontSize: "13px", fontWeight: "700", color: "var(--subtext)", textTransform: "uppercase", marginBottom: "14px" }}>
              DÒNG TIỀN KÉT & THUẾ
            </div>
            <ReportRow label="Tiền nộp thêm vào két (Cash In)" value={formatVND(zReport.tab2_thuChi.cashInTotal)} />
            <ReportRow label="Tiền chi vặt từ két (Cash Out)" value={formatVND(zReport.tab2_thuChi.cashOutTotal)} valueColor="#C93B2B" />
            <ReportRow label="Tổng tiền hoàn lại khách (Refund)" value={formatVND(zReport.tab2_thuChi.refundTotal)} valueColor="#C93B2B" />
            <ReportRow label="Tiền thuế GTGT (VAT) chốt trên bill" value={formatVND(zReport.tab1_tongHop.vatTotal)} />
            <ReportRow label="Tổng chiết khấu / Khuyến mãi" value={formatVND(zReport.tab1_tongHop.totalDiscount)} valueColor="#C93B2B" />
          </div>
        </div>
      )}

      {/* ==================== TAB 3: HÀNG HÓA ==================== */}
      {activeTab === "hanghoa" && (
        <div
          style={{
            background: "var(--surface)",
            borderRadius: "16px",
            border: "1px solid var(--border)",
            padding: "20px",
          }}
        >
          {/* Header toolbar */}
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: "12px", marginBottom: "16px" }}>
            <div style={{ display: "flex", alignItems: "center", gap: "12px", flex: 1, maxWidth: "420px" }}>
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
                  placeholder="Tìm kiếm tên món, mã món..."
                  value={productSearch}
                  onChange={(e) => setProductSearch(e.target.value)}
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
              {/* Segmented View Mode Toggle */}
              <div style={{ display: "flex", border: "1px solid var(--border)", borderRadius: "10px", overflow: "hidden", background: "var(--bg)" }}>
                <button
                  onClick={() => {
                    setProductViewMode("AMOUNT");
                    setProductSortBy("REV_DESC");
                  }}
                  style={{
                    padding: "6px 14px",
                    background: productViewMode === "AMOUNT" ? "var(--primary)" : "transparent",
                    color: productViewMode === "AMOUNT" ? "#FFFFFF" : "var(--subtext)",
                    border: "none",
                    fontSize: "12px",
                    fontWeight: "700",
                    cursor: "pointer",
                    display: "flex",
                    alignItems: "center",
                    gap: "4px",
                    transition: "all 0.15s",
                  }}
                >
                  💰 Số tiền bán
                </button>
                <button
                  onClick={() => {
                    setProductViewMode("QUANTITY");
                    setProductSortBy("QTY_DESC");
                  }}
                  style={{
                    padding: "6px 14px",
                    background: productViewMode === "QUANTITY" ? "var(--primary)" : "transparent",
                    color: productViewMode === "QUANTITY" ? "#FFFFFF" : "var(--subtext)",
                    border: "none",
                    fontSize: "12px",
                    fontWeight: "700",
                    cursor: "pointer",
                    display: "flex",
                    alignItems: "center",
                    gap: "4px",
                    transition: "all 0.15s",
                  }}
                >
                  📦 Số lượng bán
                </button>
              </div>

              {/* Staff Filter Dropdown */}
              <div
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: "6px",
                  background: "var(--bg)",
                  border: "1px solid var(--border)",
                  borderRadius: "10px",
                  padding: "6px 10px",
                }}
              >
                <User size={15} color="#7E2930" />
                <select
                  value={productStaffFilter}
                  onChange={(e) => setProductStaffFilter(e.target.value)}
                  style={{
                    background: "transparent",
                    border: "none",
                    outline: "none",
                    fontSize: "12px",
                    fontWeight: "600",
                    color: "var(--text)",
                    cursor: "pointer",
                  }}
                >
                  <option value="ALL">👤 Tất cả nhân viên</option>
                  {availableStaffList.map((st) => (
                    <option key={st} value={st}>
                      👤 {st}
                    </option>
                  ))}
                </select>
              </div>

              <select
                value={productSortBy}
                onChange={(e) => setProductSortBy(e.target.value as typeof productSortBy)}
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

              <button
                onClick={handleExportProductSales}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: "6px",
                  background: "var(--primary)",
                  color: "#FFFFFF",
                  border: "none",
                  borderRadius: "10px",
                  padding: "7px 14px",
                  fontSize: "13px",
                  fontWeight: "600",
                  cursor: "pointer",
                }}
              >
                <Download size={14} /> Xuất Excel Hàng hóa
              </button>
            </div>
          </div>

          {/* Stats Bar */}
          <div
            style={{
              display: "flex",
              gap: "24px",
              padding: "12px 16px",
              background: "var(--bg)",
              borderRadius: "10px",
              marginBottom: "16px",
              fontSize: "13px",
            }}
          >
            <div>
              Tổng số mặt hàng bán ra: <strong>{productSalesList.length} món</strong>
            </div>
            <div>
              Tổng sản lượng: <strong style={{ color: productViewMode === "QUANTITY" ? "var(--primary)" : "var(--text)" }}>{totalProductQty} phần</strong>
            </div>
            <div>
              Tổng doanh số món: <strong style={{ color: productViewMode === "AMOUNT" ? "var(--primary)" : "var(--text)" }}>{formatVND(totalProductRev)}</strong>
            </div>
          </div>

          {/* Table */}
          <div style={{ overflowX: "auto" }}>
            <table style={{ width: "100%", borderCollapse: "collapse", textAlign: "left", fontSize: "13px" }}>
              <thead>
                <tr style={{ borderBottom: "2px solid var(--border)", color: "var(--subtext)" }}>
                  <th style={{ padding: "10px 12px" }}>Hạng</th>
                  <th style={{ padding: "10px 12px" }}>Mã món</th>
                  <th style={{ padding: "10px 12px" }}>Tên sản phẩm</th>
                  <th style={{ padding: "10px 12px" }}>Nhóm hàng</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Đơn giá</th>
                  <th
                    style={{
                      padding: "10px 12px",
                      textAlign: "right",
                      background: productViewMode === "QUANTITY" ? "var(--primary-light)" : "transparent",
                      color: productViewMode === "QUANTITY" ? "var(--primary)" : "var(--subtext)",
                    }}
                  >
                    Số lượng bán
                  </th>
                  <th
                    style={{
                      padding: "10px 12px",
                      textAlign: "right",
                      background: productViewMode === "AMOUNT" ? "var(--primary-light)" : "transparent",
                      color: productViewMode === "AMOUNT" ? "var(--primary)" : "var(--subtext)",
                    }}
                  >
                    Doanh thu
                  </th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>
                    Tỷ trọng ({productViewMode === "AMOUNT" ? "Doanh thu" : "Số lượng"})
                  </th>
                </tr>
              </thead>
              <tbody>
                {productSalesList.length === 0 ? (
                  <tr>
                    <td colSpan={8} style={{ textAlign: "center", padding: "30px", color: "var(--muted)" }}>
                      Không có sản phẩm nào bán ra trong khoảng thời gian đã chọn
                    </td>
                  </tr>
                ) : (
                  productSalesList.map((p, idx) => {
                    const isAmt = productViewMode === "AMOUNT";
                    const pct = isAmt
                      ? (totalProductRev > 0 ? ((p.netRevenue / totalProductRev) * 100).toFixed(1) : "0.0")
                      : (totalProductQty > 0 ? ((p.quantity / totalProductQty) * 100).toFixed(1) : "0.0");

                    return (
                      <tr key={String(p.productId) + '-' + idx} style={{ borderBottom: "1px solid #F0ECE1" }}>
                        <td style={{ padding: "10px 12px", fontWeight: "700", color: idx < 3 ? "var(--primary)" : "var(--subtext)" }}>
                          #{idx + 1}
                        </td>
                        <td style={{ padding: "10px 12px", fontFamily: "monospace", color: "var(--muted)" }}>
                          {p.productCode || "—"}
                        </td>
                        <td style={{ padding: "10px 12px", fontWeight: "600", color: "var(--text)" }}>{p.productName}</td>
                        <td style={{ padding: "10px 12px", color: "var(--subtext)" }}>{p.category}</td>
                        <td style={{ padding: "10px 12px", textAlign: "right" }}>{formatVND(p.basePrice)}</td>
                        <td
                          style={{
                            padding: "10px 12px",
                            textAlign: "right",
                            fontWeight: isAmt ? "600" : "800",
                            color: isAmt ? "var(--text)" : "var(--primary)",
                            background: !isAmt ? "var(--primary-light)" : "transparent",
                          }}
                        >
                          {p.quantity} {p.unit}
                        </td>
                        <td
                          style={{
                            padding: "10px 12px",
                            textAlign: "right",
                            fontWeight: isAmt ? "800" : "600",
                            color: isAmt ? "var(--primary)" : "var(--text)",
                            background: isAmt ? "var(--primary-light)" : "transparent",
                          }}
                        >
                          {formatVND(p.netRevenue)}
                        </td>
                        <td style={{ padding: "10px 12px", textAlign: "right", color: "var(--subtext)" }}>{pct}%</td>
                      </tr>
                    );
                  })
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* ==================== TAB 4: PHÒNG BÀN ==================== */}
      {activeTab === "phongban" && (
        <div
          style={{
            background: "var(--surface)",
            borderRadius: "16px",
            border: "1px solid var(--border)",
            padding: "20px",
          }}
        >
          <div style={{ fontSize: "14px", fontWeight: "700", color: "var(--text)", marginBottom: "14px" }}>
            Hiệu suất doanh thu theo Khu vực & Phòng bàn
          </div>
          <div style={{ overflowX: "auto" }}>
            <table style={{ width: "100%", borderCollapse: "collapse", textAlign: "left", fontSize: "13px" }}>
              <thead>
                <tr style={{ borderBottom: "2px solid var(--border)", color: "var(--subtext)" }}>
                  <th style={{ padding: "10px 12px" }}>Khu vực</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Số lượt hóa đơn</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Tổng doanh thu</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Tỷ trọng</th>
                </tr>
              </thead>
              <tbody>
                {zReport.tab4_phongBan.zones.length === 0 ? (
                  <tr>
                    <td colSpan={4} style={{ textAlign: "center", padding: "30px", color: "var(--muted)" }}>
                      Không có dữ liệu bàn nào trong khoảng thời gian đã chọn
                    </td>
                  </tr>
                ) : (
                  zReport.tab4_phongBan.zones.map((z) => {
                    const totalZRev = zReport.tab1_tongHop.netRevenue;
                    const pct = totalZRev > 0 ? ((z.netRevenue / totalZRev) * 100).toFixed(1) : "0.0";
                    return (
                      <tr key={z.zone} style={{ borderBottom: "1px solid #F0ECE1" }}>
                        <td style={{ padding: "10px 12px" }}>
                          <span style={{ padding: "3px 10px", background: "var(--primary-light)", color: "var(--primary)", borderRadius: "6px", fontSize: "12px", fontWeight: "700" }}>
                            {z.zone}
                          </span>
                        </td>
                        <td style={{ padding: "10px 12px", textAlign: "right", fontWeight: "600" }}>{z.billCount} hóa đơn</td>
                        <td style={{ padding: "10px 12px", textAlign: "right", fontWeight: "700", color: "var(--primary)" }}>
                          {formatVND(z.netRevenue)}
                        </td>
                        <td style={{ padding: "10px 12px", textAlign: "right", color: "var(--subtext)" }}>{pct}%</td>
                      </tr>
                    );
                  })
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Serving Tables Details Modal */}
      {showServingModal && (
        <div
          style={{
            position: "fixed",
            inset: 0,
            background: "rgba(0,0,0,0.5)",
            zIndex: 100,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            padding: "20px",
          }}
          onClick={() => setShowServingModal(false)}
        >
          <div
            style={{
              background: "var(--surface)",
              borderRadius: "16px",
              padding: "24px",
              maxWidth: "600px",
              width: "100%",
              maxHeight: "80vh",
              overflowY: "auto",
            }}
            onClick={(e) => e.stopPropagation()}
          >
            <div style={{ display: "flex", flexWrap: "wrap", rowGap: "8px", justifyContent: "space-between", alignItems: "center", marginBottom: "16px" }}>
              <h3 style={{ fontSize: "18px", fontWeight: "700", color: "var(--text)", margin: 0 }}>
                Chi tiết bàn đang phục vụ ({activeTables.length} bàn)
              </h3>
              <button
                onClick={() => setShowServingModal(false)}
                style={{
                  background: "var(--surface-muted)",
                  border: "none",
                  borderRadius: "50%",
                  width: "28px",
                  height: "28px",
                  cursor: "pointer",
                }}
              >
                ✕
              </button>
            </div>

            {activeTables.length === 0 ? (
              <p style={{ textAlign: "center", color: "var(--muted)", padding: "20px 0" }}>Hiện tại không có bàn nào đang mở</p>
            ) : (
              <div style={{ display: "flex", flexDirection: "column", gap: "10px" }}>
                {activeTables.map((t) => {
                  let items: Array<{ quantity?: number; count?: number; price?: number }> = [];
                  if (t.currentOrderJson) {
                    try {
                      const p = typeof t.currentOrderJson === "string" ? JSON.parse(t.currentOrderJson) : t.currentOrderJson;
                      if (Array.isArray(p)) items = p;
                    } catch {
                      // ignore
                    }
                  }
                  const total = items.reduce((s, it) => s + (Number(it.price || 0) * (it.quantity || it.count || 1)), 0);

                  return (
                    <div
                      key={t.id}
                      style={{
                        padding: "12px",
                        border: "1px solid var(--border)",
                        borderRadius: "10px",
                        display: "flex", flexWrap: "wrap", rowGap: "8px",
                        justifyContent: "space-between",
                        alignItems: "center",
                      }}
                    >
                      <div>
                        <div style={{ fontWeight: "700", fontSize: "14px", color: "var(--text)" }}>
                          {t.name} ({t.zone})
                        </div>
                        <div style={{ fontSize: "12px", color: "var(--subtext)" }}>
                          {t.guestCount || 1} khách • {items.length} món đang phục vụ
                        </div>
                      </div>
                      <div style={{ fontSize: "15px", fontWeight: "700", color: "var(--primary)" }}>
                        {formatVND(total)}
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

function ReportRow({
  label,
  value,
  subtitle,
  isBold = false,
  valueColor = "#1C1A2D",
}: {
  label: string;
  value: string;
  subtitle?: string;
  isBold?: boolean;
  valueColor?: string;
}) {
  return (
    <div
      style={{
        display: "flex", flexWrap: "wrap", rowGap: "8px",
        alignItems: "center",
        justifyContent: "space-between",
        padding: "10px 0",
        borderBottom: "1px solid #F5F1E9",
      }}
    >
      <div>
        <div style={{ fontSize: "14px", fontWeight: isBold ? "700" : "500", color: "var(--text)" }}>{label}</div>
        {subtitle && <div style={{ fontSize: "11px", color: "var(--muted)", marginTop: "2px" }}>{subtitle}</div>}
      </div>
      <div style={{ fontSize: "14px", fontWeight: isBold ? "800" : "600", color: valueColor }}>{value}</div>
    </div>
  );
}
