"use client";
import React, { useState, useMemo } from "react";
import { useDashboardData } from "@/lib/data-context";
import {
  Calendar,
  Store,
  Search,
  Download,
  Package,
  ArrowUpDown,
  TrendingUp,
  BarChart2,
  PieChart,
  User,
  Users,
} from "lucide-react";

export default function ProductSalesReportPage() {
  const { stores, currentStoreCode, setCurrentStoreCode, historyData, categories, usersList } = useDashboardData();

  const [dateRange, setDateRange] = useState<"TODAY" | "YESTERDAY" | "7DAYS" | "THIS_MONTH" | "LAST_MONTH" | "CUSTOM">("TODAY");
  const [customStart, setCustomStart] = useState("");
  const [customEnd, setCustomEnd] = useState("");
  const [searchQuery, setSearchQuery] = useState("");
  const [selectedCategory, setSelectedCategory] = useState("ALL");
  const [selectedStaff, setSelectedStaff] = useState("ALL");
  const [viewGroupBy, setViewGroupBy] = useState<"PRODUCT" | "STAFF">("PRODUCT");
  const [productViewMode, setProductViewMode] = useState<"AMOUNT" | "QUANTITY">("AMOUNT");
  const [sortBy, setSortBy] = useState<"QTY_DESC" | "REV_DESC" | "NAME_ASC">("REV_DESC");

  // Date filtering logic
  const filteredBills = useMemo(() => {
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());

    return historyData.filter((b) => {
      if (currentStoreCode !== "ALL" && b.storeCode && b.storeCode !== currentStoreCode) return false;
      if (b.status !== "PAID") return false;
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
        case "LAST_MONTH": {
          const lm = new Date(now.getFullYear(), now.getMonth() - 1, 1);
          return dt.getFullYear() === lm.getFullYear() && dt.getMonth() === lm.getMonth();
        }
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
  }, [historyData, currentStoreCode, dateRange, customStart, customEnd]);

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
        b.items.forEach((it: any) => {
          const itStaff = (it.orderedByName || it.orderedBy || "").trim();
          if (itStaff) staffSet.add(itStaff);
        });
      }
    });
    return Array.from(staffSet).filter(Boolean).sort((a, b) => a.localeCompare(b));
  }, [usersList, historyData]);

  // Human-readable date range label
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

  // Aggregate product sales (filtered by staff if selected)
  const productList = useMemo(() => {
    const map = new Map<
      string,
      {
        name: string;
        category: string;
        quantity: number;
        revenue: number;
        unitPrice: number;
        ordersCount: number;
        staffSales: { [staff: string]: { quantity: number; revenue: number } };
      }
    >();

    filteredBills.forEach((b) => {
      const billStaff = (b.orderStaff || b.staffFullName || b.cashierName || b.creatorName || b.createdBy || b.username || "Nhân viên chung").trim();
      if (Array.isArray(b.items)) {
        b.items.forEach((it: any) => {
          const itemStaff = (it.orderedByName || it.orderedBy || billStaff).trim();
          if (selectedStaff !== "ALL" && itemStaff !== selectedStaff) {
            return;
          }

          const name = it.name || "Món không tên";
          const qty = it.quantity || it.count || 1;
          const price = Number(it.price || 0);
          let toppingSum = 0;
          if (Array.isArray(it.selectedToppings)) {
            toppingSum = it.selectedToppings.reduce((ts: number, tp: any) => ts + (tp.price || 0), 0);
          }
          const itemRev = (price + toppingSum) * qty - (it.discountAmount || 0);

          if (!map.has(name)) {
            map.set(name, {
              name,
              category: it.category || "Thực đơn chính",
              quantity: 0,
              revenue: 0,
              unitPrice: price + toppingSum,
              ordersCount: 0,
              staffSales: {},
            });
          }
          const cur = map.get(name)!;
          cur.quantity += qty;
          cur.revenue += itemRev;
          cur.ordersCount += 1;
          if (!cur.staffSales[itemStaff]) {
            cur.staffSales[itemStaff] = { quantity: 0, revenue: 0 };
          }
          cur.staffSales[itemStaff].quantity += qty;
          cur.staffSales[itemStaff].revenue += itemRev;
        });
      }
    });

    let list = Array.from(map.values());

    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase();
      list = list.filter((p) => p.name.toLowerCase().includes(q));
    }

    if (selectedCategory !== "ALL") {
      list = list.filter((p) => p.category === selectedCategory);
    }

    if (sortBy === "QTY_DESC") {
      list.sort((a, b) => b.quantity - a.quantity);
    } else if (sortBy === "REV_DESC") {
      list.sort((a, b) => b.revenue - a.revenue);
    } else {
      list.sort((a, b) => a.name.localeCompare(b.name));
    }

    return list;
  }, [filteredBills, searchQuery, selectedCategory, selectedStaff, sortBy]);

  // Aggregate by Staff (grouped view)
  const staffGroupedList = useMemo(() => {
    const staffMap = new Map<
      string,
      {
        staffName: string;
        totalQuantity: number;
        totalRevenue: number;
        products: Map<
          string,
          {
            name: string;
            category: string;
            quantity: number;
            revenue: number;
            unitPrice: number;
          }
        >;
      }
    >();

    filteredBills.forEach((b) => {
      const billStaff = (b.orderStaff || b.staffFullName || b.cashierName || b.creatorName || b.createdBy || b.username || "Nhân viên chung").trim();
      if (Array.isArray(b.items)) {
        b.items.forEach((it: any) => {
          const itemStaff = (it.orderedByName || it.orderedBy || billStaff).trim();
          if (selectedStaff !== "ALL" && itemStaff !== selectedStaff) return;

          const name = it.name || "Món không tên";
          const qty = it.quantity || it.count || 1;
          const price = Number(it.price || 0);
          let toppingSum = 0;
          if (Array.isArray(it.selectedToppings)) {
            toppingSum = it.selectedToppings.reduce((ts: number, tp: any) => ts + (tp.price || 0), 0);
          }
          const itemRev = (price + toppingSum) * qty - (it.discountAmount || 0);

          if (!staffMap.has(itemStaff)) {
            staffMap.set(itemStaff, {
              staffName: itemStaff,
              totalQuantity: 0,
              totalRevenue: 0,
              products: new Map(),
            });
          }
          const curStaff = staffMap.get(itemStaff)!;
          curStaff.totalQuantity += qty;
          curStaff.totalRevenue += itemRev;

          if (!curStaff.products.has(name)) {
            curStaff.products.set(name, {
              name,
              category: it.category || "Thực đơn chính",
              quantity: 0,
              revenue: 0,
              unitPrice: price + toppingSum,
            });
          }
          const curProd = curStaff.products.get(name)!;
          curProd.quantity += qty;
          curProd.revenue += itemRev;
        });
      }
    });

    const list = Array.from(staffMap.values()).map((s) => {
      let prods = Array.from(s.products.values());
      if (searchQuery.trim()) {
        const q = searchQuery.toLowerCase();
        prods = prods.filter((p) => p.name.toLowerCase().includes(q));
      }
      if (selectedCategory !== "ALL") {
        prods = prods.filter((p) => p.category === selectedCategory);
      }
      if (sortBy === "QTY_DESC") {
        prods.sort((a, b) => b.quantity - a.quantity);
      } else if (sortBy === "REV_DESC") {
        prods.sort((a, b) => b.revenue - a.revenue);
      } else {
        prods.sort((a, b) => a.name.localeCompare(b.name));
      }
      return {
        ...s,
        products: prods,
      };
    });

    if (sortBy === "QTY_DESC") {
      list.sort((a, b) => b.totalQuantity - a.totalQuantity);
    } else {
      list.sort((a, b) => b.totalRevenue - a.totalRevenue);
    }

    return list;
  }, [filteredBills, selectedStaff, searchQuery, selectedCategory, sortBy]);

  const totalSoldQty = useMemo(() => productList.reduce((s, p) => s + p.quantity, 0), [productList]);
  const totalRevenue = useMemo(() => productList.reduce((s, p) => s + p.revenue, 0), [productList]);

  const fmtVND = (num: number) => new Intl.NumberFormat("vi-VN").format(num) + "đ";

  // Excel / CSV Export with custom timeframe and staff
  const exportCSV = () => {
    const isAmt = productViewMode === "AMOUNT";
    const nowStr = new Date().toLocaleString("vi-VN");

    let content = "\uFEFF"; // UTF-8 BOM for Microsoft Excel
    content += `BÁO CÁO HÀNG HÓA BÁN RA THEO NHÂN VIÊN\n`;
    content += `Thời gian:,"${dateRangeLabel}"\n`;
    content += `Nhân viên:,"${selectedStaff === "ALL" ? "Tất cả nhân viên" : selectedStaff}"\n`;
    content += `Chi nhánh:,"${currentStoreCode === "ALL" ? "Tất cả chi nhánh" : currentStoreCode}"\n`;
    content += `Thời điểm xuất:,"${nowStr}"\n\n`;

    if (viewGroupBy === "STAFF") {
      content += `Nhân viên,Thứ hạng,Tên sản phẩm,Nhóm hàng,Đơn giá,Số lượng bán,Doanh thu món,Tỷ trọng NV (%)\n`;
      staffGroupedList.forEach((staffGroup) => {
        staffGroup.products.forEach((p, idx) => {
          const pct = isAmt
            ? (staffGroup.totalRevenue > 0 ? ((p.revenue / staffGroup.totalRevenue) * 100).toFixed(1) : "0.0")
            : (staffGroup.totalQuantity > 0 ? ((p.quantity / staffGroup.totalQuantity) * 100).toFixed(1) : "0.0");
          content += `"${staffGroup.staffName}",${idx + 1},"${p.name}","${p.category}",${p.unitPrice},${p.quantity},${p.revenue},${pct}%\n`;
        });
      });
    } else {
      content += `Thứ hạng,Tên sản phẩm,Nhóm hàng,Nhân viên bán,Đơn giá,Số lượng bán,Doanh thu món,Tỷ trọng (${isAmt ? "Doanh thu" : "Số lượng"}) (%)\n`;
      productList.forEach((p, idx) => {
        const pct = isAmt
          ? (totalRevenue > 0 ? ((p.revenue / totalRevenue) * 100).toFixed(1) : "0.0")
          : (totalSoldQty > 0 ? ((p.quantity / totalSoldQty) * 100).toFixed(1) : "0.0");

        let staffStr = "";
        if (selectedStaff !== "ALL") {
          staffStr = selectedStaff;
        } else {
          const staffEntries = Object.entries(p.staffSales || {});
          staffStr = staffEntries.map(([sName, sData]) => `${sName} (${sData.quantity})`).join("; ");
          if (!staffStr) staffStr = "Nhân viên chung";
        }

        content += `${idx + 1},"${p.name}","${p.category}","${staffStr}",${p.unitPrice},${p.quantity},${p.revenue},${pct}%\n`;
      });
    }

    const blob = new Blob([content], { type: "text/csv;charset=utf-8;" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    const safeStaff = selectedStaff === "ALL" ? "Tat_Ca_NV" : selectedStaff.replace(/[^a-zA-Z0-9]/g, "_");
    link.setAttribute("download", `Bao_Cao_Hang_Hoa_${safeStaff}_${dateRange}_${new Date().toISOString().slice(0, 10)}.csv`);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

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
                Báo cáo hàng hoá bán ra
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
                KiotViet Product Sales
              </span>
            </div>
            <p style={{ fontSize: "13px", color: "#666", marginTop: "4px", margin: 0 }}>
              Theo dõi chi tiết sản phẩm từng nhân viên bán được, số lượng tiêu thụ và doanh số theo mốc thời gian tự chọn
            </p>
          </div>

          {/* Filters */}
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
                <option value="LAST_MONTH">Tháng trước</option>
                <option value="CUSTOM">Tùy chọn ngày</option>
              </select>
            </div>

            {/* Custom Date Inputs if CUSTOM is selected */}
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
                    background: "#FFFFFF",
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
                    background: "#FFFFFF",
                  }}
                />
              </div>
            )}

            {/* Staff Selector */}
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
              <User size={16} color="#7E2930" />
              <select
                value={selectedStaff}
                onChange={(e) => setSelectedStaff(e.target.value)}
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
                <option value="ALL">👤 Tất cả nhân viên</option>
                {availableStaffList.map((staff) => (
                  <option key={staff} value={staff}>
                    👤 {staff}
                  </option>
                ))}
              </select>
            </div>

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
                <option value="ALL">🌐 Tất cả chi nhánh</option>
                {stores.map((s) => (
                  <option key={s.storeCode} value={s.storeCode}>
                    🏪 {s.storeCode} - {s.storeName}
                  </option>
                ))}
              </select>
            </div>
          </div>
        </div>

        {/* 3 KPI Summary Cards */}
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(240px, 1fr))", gap: "14px", marginTop: "18px" }}>
          <div style={{ padding: "14px", background: "#F8F4EE", borderRadius: "12px", border: "1px solid #E6DEC8" }}>
            <div style={{ fontSize: "12px", color: "#666", fontWeight: "600" }}>
              {selectedStaff === "ALL" ? "Mặt hàng tiêu thụ" : `Món của: ${selectedStaff}`}
            </div>
            <div style={{ fontSize: "20px", fontWeight: "800", color: "#1C1A2D", marginTop: "2px" }}>
              {productList.length} món
            </div>
            <div style={{ fontSize: "11px", color: "#888", marginTop: "2px" }}>
              {selectedStaff === "ALL" ? `${availableStaffList.length} nhân viên bán hàng` : `Nhân viên được chọn`}
            </div>
          </div>

          <div
            onClick={() => {
              setProductViewMode("QUANTITY");
              setSortBy("QTY_DESC");
            }}
            style={{
              padding: "14px",
              background: productViewMode === "QUANTITY" ? "#FBECEE" : "#F8F4EE",
              borderRadius: "12px",
              border: productViewMode === "QUANTITY" ? "2px solid #7E2930" : "1px solid #E6DEC8",
              cursor: "pointer",
              transition: "all 0.15s",
            }}
          >
            <div style={{ fontSize: "12px", color: productViewMode === "QUANTITY" ? "#7E2930" : "#666", fontWeight: "700" }}>
              Tổng sản lượng bán {productViewMode === "QUANTITY" ? "✓" : ""}
            </div>
            <div style={{ fontSize: "20px", fontWeight: "800", color: productViewMode === "QUANTITY" ? "#7E2930" : "#146A65", marginTop: "2px" }}>
              {totalSoldQty} phần
            </div>
            <div style={{ fontSize: "11px", color: "#888", marginTop: "2px" }}>
              {dateRangeLabel}
            </div>
          </div>

          <div
            onClick={() => {
              setProductViewMode("AMOUNT");
              setSortBy("REV_DESC");
            }}
            style={{
              padding: "14px",
              background: productViewMode === "AMOUNT" ? "#FBECEE" : "#F8F4EE",
              borderRadius: "12px",
              border: productViewMode === "AMOUNT" ? "2px solid #7E2930" : "1px solid #E6DEC8",
              cursor: "pointer",
              transition: "all 0.15s",
            }}
          >
            <div style={{ fontSize: "12px", color: productViewMode === "AMOUNT" ? "#7E2930" : "#666", fontWeight: "700" }}>
              Tổng doanh thu món {productViewMode === "AMOUNT" ? "✓" : ""}
            </div>
            <div style={{ fontSize: "20px", fontWeight: "800", color: "#7E2930", marginTop: "2px" }}>
              {fmtVND(totalRevenue)}
            </div>
            <div style={{ fontSize: "11px", color: "#888", marginTop: "2px" }}>
              Đã trừ giảm giá dòng món
            </div>
          </div>
        </div>
      </div>

      {/* Main Table & Grouping Card */}
      <div
        style={{
          background: "#FFFFFF",
          borderRadius: "16px",
          border: "1px solid #E6DEC8",
          padding: "20px",
          boxShadow: "0 2px 10px rgba(0,0,0,0.02)",
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
                placeholder="Tìm kiếm theo tên sản phẩm..."
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
            {/* View Grouping: By Product vs By Staff */}
            <div style={{ display: "flex", border: "1px solid #E6DEC8", borderRadius: "10px", overflow: "hidden", background: "#F8F4EE" }}>
              <button
                onClick={() => setViewGroupBy("PRODUCT")}
                style={{
                  padding: "6px 12px",
                  background: viewGroupBy === "PRODUCT" ? "#7E2930" : "transparent",
                  color: viewGroupBy === "PRODUCT" ? "#FFFFFF" : "#555",
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
                <Package size={14} /> Xem theo món
              </button>
              <button
                onClick={() => setViewGroupBy("STAFF")}
                style={{
                  padding: "6px 12px",
                  background: viewGroupBy === "STAFF" ? "#7E2930" : "transparent",
                  color: viewGroupBy === "STAFF" ? "#FFFFFF" : "#555",
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
                <Users size={14} /> Chi tiết theo nhân viên
              </button>
            </div>

            {/* Segmented View Mode Toggle: Amount vs Quantity */}
            <div style={{ display: "flex", border: "1px solid #E6DEC8", borderRadius: "10px", overflow: "hidden", background: "#F8F4EE" }}>
              <button
                onClick={() => {
                  setProductViewMode("AMOUNT");
                  setSortBy("REV_DESC");
                }}
                style={{
                  padding: "6px 12px",
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
                  setSortBy("QTY_DESC");
                }}
                style={{
                  padding: "6px 12px",
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
              value={sortBy}
              onChange={(e: any) => setSortBy(e.target.value)}
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
              onClick={exportCSV}
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

        {/* Mode 1: Table by Product */}
        {viewGroupBy === "PRODUCT" && (
          <div style={{ overflowX: "auto" }}>
            <table style={{ width: "100%", borderCollapse: "collapse", textAlign: "left", fontSize: "13px" }}>
              <thead>
                <tr style={{ borderBottom: "2px solid #E6DEC8", color: "#666" }}>
                  <th style={{ padding: "10px 12px" }}>Hạng</th>
                  <th style={{ padding: "10px 12px" }}>Tên sản phẩm</th>
                  <th style={{ padding: "10px 12px" }}>Nhóm hàng</th>
                  <th style={{ padding: "10px 12px" }}>Nhân viên bán</th>
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
                    Doanh thu món
                  </th>
                  <th style={{ padding: "10px 12px", textAlign: "right" }}>
                    Tỷ trọng ({productViewMode === "AMOUNT" ? "Doanh thu" : "Số lượng"})
                  </th>
                </tr>
              </thead>
              <tbody>
                {productList.length === 0 ? (
                  <tr>
                    <td colSpan={8} style={{ textAlign: "center", padding: "32px", color: "#999" }}>
                      Không có sản phẩm nào bán ra theo điều kiện lọc đã chọn
                    </td>
                  </tr>
                ) : (
                  productList.map((p, idx) => {
                    const isAmt = productViewMode === "AMOUNT";
                    const pct = isAmt
                      ? (totalRevenue > 0 ? ((p.revenue / totalRevenue) * 100).toFixed(1) : "0.0")
                      : (totalSoldQty > 0 ? ((p.quantity / totalSoldQty) * 100).toFixed(1) : "0.0");

                    const staffEntries = Object.entries(p.staffSales || {});

                    return (
                      <tr key={p.name} style={{ borderBottom: "1px solid #F0ECE1" }}>
                        <td style={{ padding: "10px 12px", fontWeight: "700", color: idx < 3 ? "#7E2930" : "#555" }}>
                          #{idx + 1}
                        </td>
                        <td style={{ padding: "10px 12px", fontWeight: "600", color: "#1C1A2D" }}>{p.name}</td>
                        <td style={{ padding: "10px 12px" }}>
                          <span style={{ padding: "2px 8px", background: "#F8F4EE", borderRadius: "4px", fontSize: "11px", fontWeight: "600" }}>
                            {p.category}
                          </span>
                        </td>
                        <td style={{ padding: "10px 12px", fontSize: "12px", color: "#555" }}>
                          {selectedStaff !== "ALL" ? (
                            <span style={{ color: "#7E2930", fontWeight: "700" }}>👤 {selectedStaff}</span>
                          ) : staffEntries.length === 0 ? (
                            <span style={{ color: "#888" }}>Nhân viên chung</span>
                          ) : (
                            <div style={{ display: "flex", flexWrap: "wrap", gap: "4px" }}>
                              {staffEntries.map(([sName, sData]) => (
                                <span
                                  key={sName}
                                  style={{
                                    background: "#F2EFE9",
                                    padding: "2px 6px",
                                    borderRadius: "4px",
                                    fontSize: "11px",
                                    whiteSpace: "nowrap",
                                  }}
                                >
                                  👤 {sName}: <b>{sData.quantity}</b>
                                </span>
                              ))}
                            </div>
                          )}
                        </td>
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
                        <td style={{ padding: "10px 12px", textAlign: "right" }}>
                          <div style={{ display: "flex", alignItems: "center", justifyContent: "flex-end", gap: "6px" }}>
                            <div
                              style={{
                                width: "48px",
                                height: "6px",
                                background: "#F0ECE1",
                                borderRadius: "3px",
                                overflow: "hidden",
                              }}
                            >
                              <div
                                style={{
                                  width: `${pct}%`,
                                  height: "100%",
                                  background: "#7E2930",
                                }}
                              />
                            </div>
                            <span>{pct}%</span>
                          </div>
                        </td>
                      </tr>
                    );
                  })
                )}
              </tbody>
            </table>
          </div>
        )}

        {/* Mode 2: Breakdown Grouped by Staff */}
        {viewGroupBy === "STAFF" && (
          <div style={{ display: "flex", flexDirection: "column", gap: "16px" }}>
            {staffGroupedList.length === 0 ? (
              <div style={{ textAlign: "center", padding: "32px", color: "#999" }}>
                Không có dữ liệu nhân viên bán hàng trong khoảng thời gian đã chọn
              </div>
            ) : (
              staffGroupedList.map((sg) => (
                <div
                  key={sg.staffName}
                  style={{
                    border: "1px solid #E6DEC8",
                    borderRadius: "12px",
                    overflow: "hidden",
                    background: "#FAFAF8",
                  }}
                >
                  <div
                    style={{
                      background: "#F8F4EE",
                      padding: "12px 16px",
                      display: "flex",
                      justifyContent: "space-between",
                      alignItems: "center",
                      borderBottom: "1px solid #E6DEC8",
                    }}
                  >
                    <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
                      <span style={{ fontSize: "16px" }}>👤</span>
                      <strong style={{ fontSize: "15px", color: "#1C1A2D" }}>{sg.staffName}</strong>
                      <span style={{ fontSize: "12px", color: "#777" }}>({sg.products.length} món đã bán)</span>
                    </div>
                    <div style={{ display: "flex", alignItems: "center", gap: "16px" }}>
                      <span style={{ fontSize: "13px", color: "#555" }}>
                        Tổng sản lượng: <b style={{ color: "#146A65" }}>{sg.totalQuantity} phần</b>
                      </span>
                      <span style={{ fontSize: "13px", color: "#555" }}>
                        Tổng doanh số: <b style={{ color: "#7E2930" }}>{fmtVND(sg.totalRevenue)}</b>
                      </span>
                    </div>
                  </div>

                  <div style={{ padding: "8px 16px", overflowX: "auto" }}>
                    <table style={{ width: "100%", borderCollapse: "collapse", fontSize: "13px" }}>
                      <thead>
                        <tr style={{ color: "#888", borderBottom: "1px solid #EDE8DC" }}>
                          <th style={{ padding: "8px", textAlign: "left" }}>Tên sản phẩm</th>
                          <th style={{ padding: "8px", textAlign: "left" }}>Nhóm hàng</th>
                          <th style={{ padding: "8px", textAlign: "right" }}>Đơn giá</th>
                          <th style={{ padding: "8px", textAlign: "right" }}>Số lượng</th>
                          <th style={{ padding: "8px", textAlign: "right" }}>Doanh thu</th>
                          <th style={{ padding: "8px", textAlign: "right" }}>Tỷ trọng cá nhân</th>
                        </tr>
                      </thead>
                      <tbody>
                        {sg.products.map((p) => {
                          const isAmt = productViewMode === "AMOUNT";
                          const pct = isAmt
                            ? (sg.totalRevenue > 0 ? ((p.revenue / sg.totalRevenue) * 100).toFixed(1) : "0.0")
                            : (sg.totalQuantity > 0 ? ((p.quantity / sg.totalQuantity) * 100).toFixed(1) : "0.0");

                          return (
                            <tr key={p.name} style={{ borderBottom: "1px solid #F5F1E9" }}>
                              <td style={{ padding: "8px", fontWeight: "600", color: "#1C1A2D" }}>{p.name}</td>
                              <td style={{ padding: "8px", color: "#666" }}>{p.category}</td>
                              <td style={{ padding: "8px", textAlign: "right" }}>{fmtVND(p.unitPrice)}</td>
                              <td style={{ padding: "8px", textAlign: "right", fontWeight: "700", color: "#146A65" }}>
                                {p.quantity}
                              </td>
                              <td style={{ padding: "8px", textAlign: "right", fontWeight: "700", color: "#7E2930" }}>
                                {fmtVND(p.revenue)}
                              </td>
                              <td style={{ padding: "8px", textAlign: "right" }}>{pct}%</td>
                            </tr>
                          );
                        })}
                      </tbody>
                    </table>
                  </div>
                </div>
              ))
            )}
          </div>
        )}
      </div>
    </div>
  );
}
