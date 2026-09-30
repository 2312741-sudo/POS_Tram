"use client";
import React, { useState, useMemo } from "react";
import { useDashboardData } from "@/lib/data-context";
import {
  Calendar,
  Store,
  ChevronRight,
  TrendingUp,
  Receipt,
  AlertCircle,
  HelpCircle,
  ArrowUpDown,
  Search,
  Download,
  UtensilsCrossed,
  Layers,
  Filter,
} from "lucide-react";

export default function EndOfDayReportPage() {
  const { stores, currentStoreCode, setCurrentStoreCode, historyData, tables } = useDashboardData();

  const [activeTab, setActiveTab] = useState<"tonghop" | "thuchi" | "hanghoa" | "phongban">("tonghop");
  const [dateRange, setDateRange] = useState<"TODAY" | "YESTERDAY" | "7DAYS" | "THIS_MONTH" | "CUSTOM">("TODAY");
  const [customStart, setCustomStart] = useState<string>("");
  const [customEnd, setCustomEnd] = useState<string>("");
  const [showServingModal, setShowServingModal] = useState<boolean>(false);

  // Tab Hàng hoá states
  const [productSearch, setProductSearch] = useState<string>("");
  const [productSortBy, setProductSortBy] = useState<"QTY_DESC" | "REV_DESC" | "NAME_ASC">("REV_DESC");
  const [productViewMode, setProductViewMode] = useState<"AMOUNT" | "QUANTITY">("AMOUNT");

  // Date filtering logic
  const filteredBills = useMemo(() => {
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());

    return historyData.filter((b) => {
      const dt = new Date(b.closedAt || b.createdAt || b.timestamp || Date.now());

      switch (dateRange) {
        case "TODAY":
          return (
            dt.getFullYear() === now.getFullYear() &&
            dt.getMonth() === now.getMonth() &&
            dt.getDate() === now.getDate()
          );
        case "YESTERDAY": {
          const yesterday = new Date(today);
          yesterday.setDate(yesterday.getDate() - 1);
          return (
            dt.getFullYear() === yesterday.getFullYear() &&
            dt.getMonth() === yesterday.getMonth() &&
            dt.getDate() === yesterday.getDate()
          );
        }
        case "7DAYS": {
          const sevenDaysAgo = new Date(today);
          sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);
          return dt >= sevenDaysAgo && dt <= now;
        }
        case "THIS_MONTH":
          return dt.getFullYear() === now.getFullYear() && dt.getMonth() === now.getMonth();
        case "CUSTOM": {
          if (!customStart) return true;
          const s = new Date(customStart + "T00:00:00");
          const e = customEnd ? new Date(customEnd + "T23:59:59") : new Date(customStart + "T23:59:59");
          return dt >= s && dt <= e;
        }
        default:
          return true;
      }
    });
  }, [historyData, dateRange, customStart, customEnd]);

  const paidBills = useMemo(() => filteredBills.filter((b) => b.status === "PAID"), [filteredBills]);
  const cancelledBills = useMemo(() => filteredBills.filter((b) => b.status === "CANCELLED"), [filteredBills]);

  // Serving tables logic
  const activeTables = useMemo(() => tables.filter((t) => t.inUse), [tables]);

  const servingMetrics = useMemo(() => {
    let totalItems = 0;
    let totalGuests = 0;
    let estimatedRevenue = 0;

    activeTables.forEach((t) => {
      totalGuests += t.guestCount || 1;
      let items: any[] = [];
      if (t.currentOrderJson) {
        try {
          const parsed = JSON.parse(t.currentOrderJson);
          if (Array.isArray(parsed)) items = parsed;
        } catch {}
      }
      items.forEach((it) => {
        const qty = it.quantity || it.count || 1;
        const price = Number(it.price || 0);
        let toppingSum = 0;
        if (Array.isArray(it.selectedToppings)) {
          toppingSum = it.selectedToppings.reduce((ts: number, tp: any) => ts + (tp.price || 0), 0);
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

  // Tab 1 calculations
  const grossRevenue = useMemo(() => {
    return paidBills.reduce((sum, b) => sum + (b.subTotal || b.totalAmount || 0), 0);
  }, [paidBills]);

  const itemDiscounts = useMemo(() => {
    return paidBills.reduce((sum, b) => {
      let bSum = 0;
      if (Array.isArray(b.items)) {
        b.items.forEach((it: any) => {
          if (it.discountAmount) bSum += Number(it.discountAmount) * (it.quantity || 1);
        });
      }
      return sum + bSum;
    }, 0);
  }, [paidBills]);

  const billDiscounts = useMemo(() => {
    return paidBills.reduce((sum, b) => {
      const totalDisc = b.discountAmount || 0;
      return sum + totalDisc;
    }, 0);
  }, [paidBills]);

  const netRevenue = useMemo(() => {
    return paidBills.reduce((sum, b) => sum + (b.totalAmount || 0), 0);
  }, [paidBills]);

  const vatTotal = useMemo(() => {
    // 8% VAT estimate if not explicitly set
    return Math.round(netRevenue * 0.08 / 1.08);
  }, [netRevenue]);

  const otherIncome = 0;
  const refundAmount = 0;
  const netRevenueWithOther = netRevenue + otherIncome - refundAmount;
  const netRevenueWithoutOther = netRevenue - refundAmount;

  const totalPaidGuests = useMemo(() => {
    return paidBills.reduce((sum, b) => sum + (b.guestCount || 1), 0);
  }, [paidBills]);

  const avgRevenuePerBill = useMemo(() => {
    if (paidBills.length === 0) return 0;
    return Math.round(netRevenue / paidBills.length);
  }, [netRevenue, paidBills.length]);

  const cancelledValue = useMemo(() => {
    return cancelledBills.reduce((sum, b) => sum + (b.totalAmount || b.subTotal || 0), 0);
  }, [cancelledBills]);

  // Tab 2: Thu chi
  const cashSales = useMemo(() => {
    return paidBills.filter((b) => b.paymentMethod === "CASH").reduce((sum, b) => sum + (b.totalAmount || 0), 0);
  }, [paidBills]);

  const transferSales = useMemo(() => {
    return paidBills.filter((b) => b.paymentMethod === "TRANSFER" || b.paymentMethod?.includes("QR")).reduce((sum, b) => sum + (b.totalAmount || 0), 0);
  }, [paidBills]);

  // Tab 3: Hàng hoá bán ra
  const productSalesList = useMemo(() => {
    const map = new Map<string, { name: string; quantity: number; revenue: number; unitPrice: number }>();

    paidBills.forEach((b) => {
      if (Array.isArray(b.items)) {
        b.items.forEach((it: any) => {
          const name = it.name || "Món không tên";
          const qty = it.quantity || it.count || 1;
          const price = Number(it.price || 0);
          let toppingSum = 0;
          if (Array.isArray(it.selectedToppings)) {
            toppingSum = it.selectedToppings.reduce((ts: number, tp: any) => ts + (tp.price || 0), 0);
          }
          const itemRev = (price + toppingSum) * qty - (it.discountAmount || 0);

          if (!map.has(name)) {
            map.set(name, { name, quantity: 0, revenue: 0, unitPrice: price + toppingSum });
          }
          const cur = map.get(name)!;
          cur.quantity += qty;
          cur.revenue += itemRev;
        });
      }
    });

    let list = Array.from(map.values());

    if (productSearch.trim()) {
      const q = productSearch.toLowerCase();
      list = list.filter((p) => p.name.toLowerCase().includes(q));
    }

    if (productSortBy === "QTY_DESC") {
      list.sort((a, b) => b.quantity - a.quantity);
    } else if (productSortBy === "REV_DESC") {
      list.sort((a, b) => b.revenue - a.revenue);
    } else if (productSortBy === "NAME_ASC") {
      list.sort((a, b) => a.name.localeCompare(b.name));
    } else {
      if (productViewMode === "AMOUNT") {
        list.sort((a, b) => b.revenue - a.revenue);
      } else {
        list.sort((a, b) => b.quantity - a.quantity);
      }
    }

    return list;
  }, [paidBills, productSearch, productSortBy, productViewMode]);

  const totalProductQty = useMemo(() => productSalesList.reduce((s, it) => s + it.quantity, 0), [productSalesList]);
  const totalProductRev = useMemo(() => productSalesList.reduce((s, it) => s + it.revenue, 0), [productSalesList]);

  // Tab 4: Phòng bàn
  const tableSalesList = useMemo(() => {
    const map = new Map<string, { zone: string; tableName: string; orderCount: number; revenue: number }>();

    paidBills.forEach((b) => {
      const zone = b.zone || "Khu A";
      const name = b.tableName || "Mang về";
      const key = `${zone}_${name}`;

      if (!map.has(key)) {
        map.set(key, { zone, tableName: name, orderCount: 0, revenue: 0 });
      }
      const cur = map.get(key)!;
      cur.orderCount += 1;
      cur.revenue += b.totalAmount || 0;
    });

    const list = Array.from(map.values());
    list.sort((a, b) => b.revenue - a.revenue);
    return list;
  }, [paidBills]);

  const exportProductSalesCSV = () => {
    const isAmt = productViewMode === "AMOUNT";
    const headers = `Xếp hạng,Tên món,Đơn giá,Số lượng bán,Doanh thu món,Tỷ trọng theo ${isAmt ? "doanh thu" : "số lượng"} (%)\n`;
    const rows = productSalesList
      .map((p, idx) => {
        const pct = isAmt
          ? (totalProductRev > 0 ? ((p.revenue / totalProductRev) * 100).toFixed(1) : "0.0")
          : (totalProductQty > 0 ? ((p.quantity / totalProductQty) * 100).toFixed(1) : "0.0");
        return `${idx + 1},"${p.name}",${p.unitPrice},${p.quantity},${p.revenue},${pct}%`;
      })
      .join("\n");
    const blob = new Blob([headers + rows], { type: "text/csv;charset=utf-8;" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.setAttribute("download", `Bao_Cao_Hang_Hoa_${isAmt ? "Doanh_Thu" : "So_Luong"}_${new Date().toISOString().slice(0, 10)}.csv`);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  const fmtVND = (num: number) => new Intl.NumberFormat("vi-VN").format(num) + "đ";

  return (
    <div style={{ padding: "24px 28px", maxWidth: "1280px", margin: "0 auto" }}>
      {/* Top Header Card with Title and Filter Dropdowns */}
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
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: "16px" }}>
          <div>
            <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
              <h1 style={{ fontSize: "22px", fontWeight: "800", color: "#1C1A2D", margin: 0 }}>
                Báo cáo tổng hợp cuối ngày
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
                KiotViet Dual Sync
              </span>
            </div>
            <p style={{ fontSize: "13px", color: "#666", marginTop: "4px", margin: 0 }}>
              Thống kê tổng kết bán hàng, thu chi, hàng hoá bán ra và hiệu suất phòng bàn theo thời gian thực
            </p>
          </div>

          {/* Filters: Date and Store */}
          <div style={{ display: "flex", alignItems: "center", gap: "10px", flexWrap: "wrap" }}>
            {/* Date Range Selector */}
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
              <Calendar size={16} color="#7E2930" />
              <select
                value={dateRange}
                onChange={(e: any) => setDateRange(e.target.value)}
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
                <option value="TODAY">Hôm nay</option>
                <option value="YESTERDAY">Hôm qua</option>
                <option value="7DAYS">7 ngày qua</option>
                <option value="THIS_MONTH">Tháng này</option>
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
                    border: "1px solid #E6DEC8",
                    fontSize: "12px",
                  }}
                />
                <span style={{ fontSize: "12px", color: "#666" }}>đến</span>
                <input
                  type="date"
                  value={customEnd}
                  onChange={(e) => setCustomEnd(e.target.value)}
                  style={{
                    padding: "6px 10px",
                    borderRadius: "8px",
                    border: "1px solid #E6DEC8",
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
          </div>
        </div>

        {/* 4 Tabs Bar matching mobile exact tabs */}
        <div style={{ display: "flex", gap: "8px", marginTop: "20px", borderBottom: "1px solid #E6DEC8", paddingBottom: "1px" }}>
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
                onClick={() => setActiveTab(tab.id as any)}
                style={{
                  padding: "10px 20px",
                  fontSize: "14px",
                  fontWeight: active ? "700" : "500",
                  color: active ? "#7E2930" : "#666",
                  borderBottom: active ? "3px solid #7E2930" : "3px solid transparent",
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
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(460px, 1fr))", gap: "20px" }}>
          {/* Card 1: TỔNG KẾT BÁN HÀNG */}
          <div
            style={{
              background: "#FFFFFF",
              borderRadius: "16px",
              border: "1px solid #E6DEC8",
              padding: "20px",
              boxShadow: "0 2px 8px rgba(0,0,0,0.02)",
            }}
          >
            <div style={{ fontSize: "13px", fontWeight: "700", color: "#777", textTransform: "uppercase", letterSpacing: "0.5px", marginBottom: "12px" }}>
              TỔNG KẾT BÁN HÀNG
            </div>
            <div style={{ display: "flex", flexDirection: "column" }}>
              <ReportRow label="Doanh thu tổng" value={fmtVND(grossRevenue)} />
              <ReportRow label="Tổng giảm giá món" value={fmtVND(itemDiscounts)} />
              <ReportRow label="Tổng giảm giá hóa đơn" value={fmtVND(billDiscounts)} />
              <ReportRow
                label="Doanh thu"
                value={fmtVND(netRevenue)}
                subtitle={`Bao gồm ${fmtVND(vatTotal)} tiền thuế`}
                valueColor="#7E2930"
                isBold
              />
              <ReportRow label="Thu khác" value={fmtVND(otherIncome)} />
              <ReportRow label="Trả hàng" value={fmtVND(refundAmount)} />
              <ReportRow
                label="Doanh thu thuần"
                subtitle="Bao gồm thu khác"
                value={fmtVND(netRevenueWithOther)}
                isBold
                valueColor="#146A65"
              />
              <ReportRow
                label="Doanh thu thuần"
                subtitle="Không bao gồm thu khác"
                value={fmtVND(netRevenueWithoutOther)}
                isBold
              />
            </div>
          </div>

          <div style={{ display: "flex", flexDirection: "column", gap: "20px" }}>
            {/* Card 2: ĐANG PHỤC VỤ > */}
            <div
              style={{
                background: "#FFFFFF",
                borderRadius: "16px",
                border: "1px solid #E6DEC8",
                padding: "20px",
                boxShadow: "0 2px 8px rgba(0,0,0,0.02)",
              }}
            >
              <div
                onClick={() => setShowServingModal(true)}
                style={{
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "space-between",
                  cursor: "pointer",
                  marginBottom: "12px",
                }}
              >
                <div style={{ fontSize: "13px", fontWeight: "700", color: "#777", textTransform: "uppercase", letterSpacing: "0.5px" }}>
                  ĐANG PHỤC VỤ
                </div>
                <div style={{ display: "flex", alignItems: "center", gap: "4px", fontSize: "12px", color: "#7E2930", fontWeight: "600" }}>
                  Xem chi tiết bàn <ChevronRight size={14} />
                </div>
              </div>

              <div style={{ display: "flex", flexDirection: "column" }}>
                <ReportRow label="Đơn đang phục vụ" value={`${servingMetrics.tableCount} bàn`} />
                <ReportRow label="Số lượng sản phẩm" value={`${servingMetrics.itemCount} món`} />
                <ReportRow label="Số khách" value={`${servingMetrics.guestCount} người`} />
                <ReportRow
                  label="Doanh thu ước tính"
                  value={fmtVND(servingMetrics.estimatedRevenue)}
                  valueColor="#C47820"
                  isBold
                />
                <ReportRow label="Thu khác" value="0đ" />
              </div>
            </div>

            {/* Card 3: HÓA ĐƠN */}
            <div
              style={{
                background: "#FFFFFF",
                borderRadius: "16px",
                border: "1px solid #E6DEC8",
                padding: "20px",
                boxShadow: "0 2px 8px rgba(0,0,0,0.02)",
              }}
            >
              <div style={{ fontSize: "13px", fontWeight: "700", color: "#777", textTransform: "uppercase", letterSpacing: "0.5px", marginBottom: "12px" }}>
                HÓA ĐƠN
              </div>
              <div style={{ display: "flex", flexDirection: "column" }}>
                <ReportRow label="Số hóa đơn" value={`${paidBills.length} đơn`} />
                <ReportRow label="Số khách" value={`${totalPaidGuests} người`} />
                <ReportRow label="Doanh thu TB/Đơn" value={fmtVND(avgRevenuePerBill)} isBold />
              </div>
            </div>

            {/* Card 4: HÓA ĐƠN ĐÃ HỦY */}
            <div
              style={{
                background: "#FFFFFF",
                borderRadius: "16px",
                border: "1px solid #E6DEC8",
                padding: "20px",
                boxShadow: "0 2px 8px rgba(0,0,0,0.02)",
              }}
            >
              <div style={{ fontSize: "13px", fontWeight: "700", color: "#777", textTransform: "uppercase", letterSpacing: "0.5px", marginBottom: "12px" }}>
                HÓA ĐƠN ĐÃ HỦY
              </div>
              <div style={{ display: "flex", flexDirection: "column" }}>
                <ReportRow label="Số lượng đơn hủy" value={`${cancelledBills.length} đơn`} />
                <ReportRow
                  label="Giá trị hủy"
                  value={fmtVND(cancelledValue)}
                  valueColor="#C93B2B"
                  isBold
                />
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ==================== TAB 2: THU CHI ==================== */}
      {activeTab === "thuchi" && (
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(460px, 1fr))", gap: "20px" }}>
          <div
            style={{
              background: "#FFFFFF",
              borderRadius: "16px",
              border: "1px solid #E6DEC8",
              padding: "20px",
            }}
          >
            <div style={{ fontSize: "13px", fontWeight: "700", color: "#777", textTransform: "uppercase", marginBottom: "14px" }}>
              PHƯƠNG THỨC THANH TOÁN BÁN HÀNG
            </div>
            <ReportRow label="Tiền mặt (CASH)" value={fmtVND(cashSales)} isBold valueColor="#146A65" />
            <ReportRow label="Chuyển khoản VietQR" value={fmtVND(transferSales)} isBold valueColor="#1877F2" />
            <ReportRow
              label="TỔNG THỰC THU BÁN HÀNG"
              value={fmtVND(netRevenue)}
              isBold
              valueColor="#7E2930"
            />
          </div>

          <div
            style={{
              background: "#FFFFFF",
              borderRadius: "16px",
              border: "1px solid #E6DEC8",
              padding: "20px",
            }}
          >
            <div style={{ fontSize: "13px", fontWeight: "700", color: "#777", textTransform: "uppercase", marginBottom: "14px" }}>
              ĐỐI SOÁT & THU THUẾ
            </div>
            <ReportRow label="Tiền thuế GTGT (VAT)" value={fmtVND(vatTotal)} />
            <ReportRow label="Tổng chiết khấu / Khuyến mãi" value={fmtVND(billDiscounts + itemDiscounts)} valueColor="#C93B2B" />
            <ReportRow label="Số lượng hóa đơn hợp lệ" value={`${paidBills.length} đơn`} isBold />
          </div>
        </div>
      )}

      {/* ==================== TAB 3: HÀNG HÓA (BÁO CÁO HÀNG HÓA BÁN RA) ==================== */}
      {activeTab === "hanghoa" && (
        <div
          style={{
            background: "#FFFFFF",
            borderRadius: "16px",
            border: "1px solid #E6DEC8",
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
                  background: "#F8F4EE",
                  border: "1px solid #E6DEC8",
                  borderRadius: "10px",
                  padding: "6px 12px",
                  width: "100%",
                }}
              >
                <Search size={16} color="#666" />
                <input
                  type="text"
                  placeholder="Tìm kiếm tên món..."
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
              <div style={{ display: "flex", border: "1px solid #E6DEC8", borderRadius: "10px", overflow: "hidden", background: "#F8F4EE" }}>
                <button
                  onClick={() => {
                    setProductViewMode("AMOUNT");
                    setProductSortBy("REV_DESC");
                  }}
                  style={{
                    padding: "6px 14px",
                    background: productViewMode === "AMOUNT" ? "#7E2930" : "transparent",
                    color: productViewMode === "AMOUNT" ? "#FFFFFF" : "#555",
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
                    background: productViewMode === "QUANTITY" ? "#7E2930" : "transparent",
                    color: productViewMode === "QUANTITY" ? "#FFFFFF" : "#555",
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

              <select
                value={productSortBy}
                onChange={(e: any) => setProductSortBy(e.target.value)}
                style={{
                  padding: "6px 12px",
                  borderRadius: "10px",
                  border: "1px solid #E6DEC8",
                  fontSize: "13px",
                  fontWeight: "600",
                  background: "#FFFFFF",
                  cursor: "pointer",
                }}
              >
                <option value="REV_DESC">Doanh thu giảm dần</option>
                <option value="QTY_DESC">Số lượng bán giảm dần</option>
                <option value="NAME_ASC">Tên món A-Z</option>
              </select>

              <button
                onClick={exportProductSalesCSV}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: "6px",
                  background: "#7E2930",
                  color: "#FFFFFF",
                  border: "none",
                  borderRadius: "10px",
                  padding: "7px 14px",
                  fontSize: "13px",
                  fontWeight: "600",
                  cursor: "pointer",
                }}
              >
                <Download size={14} /> Xuất Excel / CSV
              </button>
            </div>
          </div>

          {/* Stats Bar */}
          <div
            style={{
              display: "flex",
              gap: "24px",
              padding: "12px 16px",
              background: "#F8F4EE",
              borderRadius: "10px",
              marginBottom: "16px",
              fontSize: "13px",
            }}
          >
            <div>
              Tổng số mặt hàng bán ra: <strong>{productSalesList.length} món</strong>
            </div>
            <div>
              Tổng sản lượng: <strong style={{ color: productViewMode === "QUANTITY" ? "#7E2930" : "#1C1A2D" }}>{totalProductQty} phần</strong>
            </div>
            <div>
              Tổng doanh số món: <strong style={{ color: productViewMode === "AMOUNT" ? "#7E2930" : "#1C1A2D" }}>{fmtVND(totalProductRev)}</strong>
            </div>
          </div>

          {/* Table */}
          <div style={{ overflowX: "auto" }}>
            <table style={{ width: "100%", borderCollapse: "collapse", textAlign: "left", fontSize: "13px" }}>
              <thead>
                <tr style={{ borderBottom: "2px solid #E6DEC8", color: "#666" }}>
                  <th style={{ padding: "10px 12px" }}>Hạng</th>
                  <th style={{ padding: "10px 12px" }}>Tên sản phẩm</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Đơn giá</th>
                  <th
                    style={{
                      padding: "10px 12px",
                      textAlign: "right",
                      background: productViewMode === "QUANTITY" ? "#FBECEE" : "transparent",
                      color: productViewMode === "QUANTITY" ? "#7E2930" : "#666",
                    }}
                  >
                    Số lượng bán
                  </th>
                  <th
                    style={{
                      padding: "10px 12px",
                      textAlign: "right",
                      background: productViewMode === "AMOUNT" ? "#FBECEE" : "transparent",
                      color: productViewMode === "AMOUNT" ? "#7E2930" : "#666",
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
                    <td colSpan={6} style={{ textAlign: "center", padding: "30px", color: "#999" }}>
                      Không có sản phẩm nào bán ra trong khoảng thời gian đã chọn
                    </td>
                  </tr>
                ) : (
                  productSalesList.map((p, idx) => {
                    const isAmt = productViewMode === "AMOUNT";
                    const pct = isAmt
                      ? (totalProductRev > 0 ? ((p.revenue / totalProductRev) * 100).toFixed(1) : "0.0")
                      : (totalProductQty > 0 ? ((p.quantity / totalProductQty) * 100).toFixed(1) : "0.0");

                    return (
                      <tr key={p.name} style={{ borderBottom: "1px solid #F0ECE1" }}>
                        <td style={{ padding: "10px 12px", fontWeight: "700", color: idx < 3 ? "#7E2930" : "#555" }}>
                          #{idx + 1}
                        </td>
                        <td style={{ padding: "10px 12px", fontWeight: "600", color: "#1C1A2D" }}>{p.name}</td>
                        <td style={{ padding: "10px 12px", textAlign: "right" }}>{fmtVND(p.unitPrice)}</td>
                        <td
                          style={{
                            padding: "10px 12px",
                            textAlign: "right",
                            fontWeight: isAmt ? "600" : "800",
                            color: isAmt ? "#1C1A2D" : "#7E2930",
                            background: !isAmt ? "#FFF5F6" : "transparent",
                          }}
                        >
                          {p.quantity}
                        </td>
                        <td
                          style={{
                            padding: "10px 12px",
                            textAlign: "right",
                            fontWeight: isAmt ? "800" : "600",
                            color: isAmt ? "#7E2930" : "#1C1A2D",
                            background: isAmt ? "#FFF5F6" : "transparent",
                          }}
                        >
                          {fmtVND(p.revenue)}
                        </td>
                        <td style={{ padding: "10px 12px", textAlign: "right", color: "#666" }}>{pct}%</td>
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
            background: "#FFFFFF",
            borderRadius: "16px",
            border: "1px solid #E6DEC8",
            padding: "20px",
          }}
        >
          <div style={{ fontSize: "14px", fontWeight: "700", color: "#1C1A2D", marginBottom: "14px" }}>
            Hiệu suất doanh thu theo Khu vực & Phòng bàn
          </div>
          <div style={{ overflowX: "auto" }}>
            <table style={{ width: "100%", borderCollapse: "collapse", textAlign: "left", fontSize: "13px" }}>
              <thead>
                <tr style={{ borderBottom: "2px solid #E6DEC8", color: "#666" }}>
                  <th style={{ padding: "10px 12px" }}>Khu vực</th>
                  <th style={{ padding: "10px 12px" }}>Tên bàn</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Số lượt phục vụ</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Tổng doanh thu</th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>Tỷ trọng</th>
                </tr>
              </thead>
              <tbody>
                {tableSalesList.length === 0 ? (
                  <tr>
                    <td colSpan={5} style={{ textAlign: "center", padding: "30px", color: "#999" }}>
                      Không có dữ liệu bàn nào trong khoảng thời gian đã chọn
                    </td>
                  </tr>
                ) : (
                  tableSalesList.map((t) => {
                    const pct = netRevenue > 0 ? ((t.revenue / netRevenue) * 100).toFixed(1) : "0.0";
                    return (
                      <tr key={`${t.zone}_${t.tableName}`} style={{ borderBottom: "1px solid #F0ECE1" }}>
                        <td style={{ padding: "10px 12px" }}>
                          <span style={{ padding: "2px 8px", background: "#FBECEE", color: "#7E2930", borderRadius: "4px", fontSize: "11px", fontWeight: "700" }}>
                            {t.zone}
                          </span>
                        </td>
                        <td style={{ padding: "10px 12px", fontWeight: "700" }}>{t.tableName}</td>
                        <td style={{ padding: "10px 12px", textAlign: "right" }}>{t.orderCount} lượt</td>
                        <td style={{ padding: "10px 12px", textAlign: "right", fontWeight: "700", color: "#7E2930" }}>
                          {fmtVND(t.revenue)}
                        </td>
                        <td style={{ padding: "10px 12px", textAlign: "right", color: "#666" }}>{pct}%</td>
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
              background: "#FFFFFF",
              borderRadius: "16px",
              padding: "24px",
              maxWidth: "600px",
              width: "100%",
              maxHeight: "80vh",
              overflowY: "auto",
            }}
            onClick={(e) => e.stopPropagation()}
          >
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "16px" }}>
              <h3 style={{ fontSize: "18px", fontWeight: "700", color: "#1C1A2D", margin: 0 }}>
                Chi tiết bàn đang phục vụ ({activeTables.length} bàn)
              </h3>
              <button
                onClick={() => setShowServingModal(false)}
                style={{
                  background: "#F0ECE1",
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
              <p style={{ textAlign: "center", color: "#999", padding: "20px 0" }}>Hiện tại không có bàn nào đang mở</p>
            ) : (
              <div style={{ display: "flex", flexDirection: "column", gap: "10px" }}>
                {activeTables.map((t) => {
                  let items: any[] = [];
                  if (t.currentOrderJson) {
                    try {
                      const p = JSON.parse(t.currentOrderJson);
                      if (Array.isArray(p)) items = p;
                    } catch {}
                  }
                  const total = items.reduce((s, it) => s + (Number(it.price || 0) * (it.quantity || 1)), 0);

                  return (
                    <div
                      key={t.id}
                      style={{
                        padding: "12px",
                        border: "1px solid #E6DEC8",
                        borderRadius: "10px",
                        display: "flex",
                        justifyContent: "space-between",
                        alignItems: "center",
                      }}
                    >
                      <div>
                        <div style={{ fontWeight: "700", fontSize: "14px", color: "#1C1A2D" }}>
                          {t.name} ({t.zone})
                        </div>
                        <div style={{ fontSize: "12px", color: "#666" }}>
                          {t.guestCount || 1} khách • {items.length} món đang phục vụ
                        </div>
                      </div>
                      <div style={{ fontSize: "15px", fontWeight: "700", color: "#7E2930" }}>
                        {fmtVND(total)}
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
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        padding: "10px 0",
        borderBottom: "1px solid #F5F1E9",
      }}
    >
      <div>
        <div style={{ fontSize: "14px", fontWeight: isBold ? "700" : "500", color: "#1C1A2D" }}>{label}</div>
        {subtitle && <div style={{ fontSize: "11px", color: "#888", marginTop: "2px" }}>{subtitle}</div>}
      </div>
      <div style={{ fontSize: "14px", fontWeight: isBold ? "800" : "600", color: valueColor }}>{value}</div>
    </div>
  );
}
