"use client";
import React, { useState, useMemo } from "react";
import { useDashboardData } from "@/lib/data-context";
import {
  calculateCashShiftReport,
  formatVND,
  formatNumber,
  extractBillItems,
  CashShiftAuditItem,
} from "@/lib/reports";
import { exportCashShiftReport, exportShiftPromotionsExcel } from "@/lib/export";
import {
  Store,
  Search,
  Printer,
  Eye,
  EyeOff,
  FileSpreadsheet,
  Coins,
  Wallet,
  ArrowUpDown,
  History,
} from "lucide-react";

export default function ShiftsPage() {
  const {
    stores,
    currentStoreCode,
    setCurrentStoreCode,
    cashShifts,
    historyData,
    updateStoreShiftDifferenceSetting,
  } = useDashboardData();

  const [searchQuery, setSearchQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState<"ALL" | "OPEN" | "CLOSED">("ALL");
  const [selectedShift, setSelectedShift] = useState<CashShiftAuditItem | null>(null);
  const [updatingSetting, setUpdatingSetting] = useState(false);

  // Current store info for setting toggle
  const targetStore = useMemo(() => {
    if (currentStoreCode === "ALL") return stores[0];
    return stores.find((s) => s.storeCode === currentStoreCode) || stores[0];
  }, [stores, currentStoreCode]);

  const allowDifference = targetStore?.allowStaffViewShiftDifference ?? true;

  const handleToggleDifference = async () => {
    if (!targetStore) return;
    setUpdatingSetting(true);
    await updateStoreShiftDifferenceSetting(targetStore.storeCode, !allowDifference);
    setUpdatingSetting(false);
  };

  // Run pure calculation function to audit cash shifts
  const auditedShifts = useMemo(() => {
    return calculateCashShiftReport(cashShifts, historyData);
  }, [cashShifts, historyData]);

  const filteredShifts = useMemo(() => {
    return auditedShifts.filter((s) => {
      if (statusFilter === "OPEN" && s.status !== "OPEN") return false;
      if (statusFilter === "CLOSED" && s.status === "OPEN") return false;
      if (currentStoreCode !== "ALL" && s.storeCode && s.storeCode !== currentStoreCode) return false;

      if (searchQuery.trim()) {
        const q = searchQuery.toLowerCase();
        const matchCode = (s.shiftCode || "").toLowerCase().includes(q);
        const matchStaff =
          (s.staffFullName || "").toLowerCase().includes(q) || (s.staffUsername || "").toLowerCase().includes(q);
        if (!matchCode && !matchStaff) return false;
      }
      return true;
    });
  }, [auditedShifts, statusFilter, currentStoreCode, searchQuery]);

  // Aggregate KPI summary
  const summaryKpi = useMemo(() => {
    const totalShifts = filteredShifts.length;
    const openShifts = filteredShifts.filter((s) => s.status === "OPEN").length;
    const totalCashSales = filteredShifts.reduce((acc, s) => acc + s.cashSales, 0);
    const totalActualCash = filteredShifts.reduce((acc, s) => acc + s.actualCash, 0);
    const totalDiff = filteredShifts.reduce((acc, s) => acc + s.difference, 0);

    return { totalShifts, openShifts, totalCashSales, totalActualCash, totalDiff };
  }, [filteredShifts]);

  const fmtDate = (timestamp?: number | null) => {
    if (!timestamp) return "Chưa đóng";
    const d = new Date(timestamp);
    return `${d.getHours().toString().padStart(2, "0")}:${d.getMinutes().toString().padStart(2, "0")} - ${d
      .getDate()
      .toString()
      .padStart(2, "0")}/${(d.getMonth() + 1).toString().padStart(2, "0")}/${d.getFullYear()}`;
  };

  const handleExportExcel = () => {
    const storeInfo =
      currentStoreCode === "ALL"
        ? { storeName: "Tất cả chi nhánh", storeCode: "ALL" }
        : stores.find((s) => s.storeCode === currentStoreCode) || {
            storeName: "POS Trạm",
            storeCode: currentStoreCode,
          };
    exportCashShiftReport(filteredShifts, storeInfo).toExcel();
  };

  const handleExportPDF = () => {
    const storeInfo =
      currentStoreCode === "ALL"
        ? { storeName: "Tất cả chi nhánh", storeCode: "ALL" }
        : stores.find((s) => s.storeCode === currentStoreCode) || {
            storeName: "POS Trạm",
            storeCode: currentStoreCode,
          };
    exportCashShiftReport(filteredShifts, storeInfo).toPDF();
  };

  // Shift bills & promotion stats for selected shift (Module 4)
  const selectedShiftBills = useMemo(() => {
    if (!selectedShift) return [];
    const sId = selectedShift.shiftId || (selectedShift as any).id || "";
    return historyData.filter((b) => {
      if (b.shiftId && sId) return b.shiftId === sId;
      const bTime = Number(b.closedAt || b.createdAt || b.timestamp || 0);
      const closeT = selectedShift.closedAt ? Number(selectedShift.closedAt) : Infinity;
      return selectedShift.openedAt <= bTime && bTime <= closeT;
    });
  }, [selectedShift, historyData]);

  const shiftPromoStats = useMemo(() => {
    const paidBills = selectedShiftBills.filter((b) => (b.status || "PAID").toUpperCase() === "PAID");
    let discountedItemsCount = 0;
    let discountedItemsTotal = 0;
    let voucherCount = 0;
    let voucherTotal = 0;
    let pointsUsedTotal = 0;
    let pointsDiscountTotal = 0;

    for (const b of paidBills) {
      const items = extractBillItems(b);
      for (const it of items) {
        const d = Number(it.discountAmount || 0);
        if (d > 0) {
          const q = Number(it.quantity || 1);
          discountedItemsCount += q;
          discountedItemsTotal += d * q;
        }
      }
      if (Array.isArray(b.discounts)) {
        for (const d of b.discounts) {
          voucherCount++;
          voucherTotal += Number(d.amount || 0);
        }
      }
      const pu = Number(b.pointsUsed || 0);
      const pd = Number(b.pointsDiscount || 0);
      if (pu > 0 || pd > 0) {
        pointsUsedTotal += pu;
        pointsDiscountTotal += pd;
      }
    }

    const totalPromoDiscount = discountedItemsTotal + voucherTotal + pointsDiscountTotal;
    return {
      discountedItemsCount,
      discountedItemsTotal,
      voucherCount,
      voucherTotal,
      pointsUsedTotal,
      pointsDiscountTotal,
      totalPromoDiscount,
    };
  }, [selectedShiftBills]);

  const handleExportShiftPromoExcel = () => {
    if (!selectedShift) return;
    const storeInfo =
      targetStore || {
        storeName: "POS Trạm",
        storeCode: selectedShift.storeCode || "TRAM01",
      };
    exportShiftPromotionsExcel(selectedShift, selectedShiftBills, storeInfo).toExcel();
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
                Phiếu bàn giao ca & Két tiền
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
                KiotViet Shift Handover
              </span>
            </div>
            <p style={{ fontSize: "13px", color: "#666", marginTop: "4px", margin: 0 }}>
              Quản lý các phiên giao két của nhân viên, đối soát chênh lệch kiểm đếm và in phiếu bàn giao ca
            </p>
          </div>

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
        </div>

        {/* Manager Toggle Setting Card */}
        <div
          style={{
            marginTop: "16px",
            padding: "14px 18px",
            background: allowDifference ? "#F2F9F7" : "#FFF8ED",
            border: `1px solid ${allowDifference ? "#B8E3D8" : "#F7E1B5"}`,
            borderRadius: "12px",
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            flexWrap: "wrap",
            gap: "14px",
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: "12px" }}>
            <div
              style={{
                width: "36px",
                height: "36px",
                borderRadius: "10px",
                background: allowDifference ? "#146A65" : "#C47820",
                color: "#FFFFFF",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              {allowDifference ? <Eye size={18} /> : <EyeOff size={18} />}
            </div>
            <div>
              <div style={{ fontSize: "14px", fontWeight: "700", color: "#1C1A2D" }}>
                Chế độ hiển thị chênh lệch tiền két khi nhân viên kết ca:{" "}
                <span style={{ color: allowDifference ? "#146A65" : "#C47820" }}>
                  {allowDifference ? "Đang BẬT (Công khai)" : "Đang TẮT (Kiểm đếm mù)"}
                </span>
              </div>
              <div style={{ fontSize: "12px", color: "#666", marginTop: "2px" }}>
                {allowDifference
                  ? "Nhân viên thu ngân được xem số dư lý thuyết và chênh lệch thừa/thiếu ngay trên app khi chốt ca."
                  : "Chế độ kiểm đếm mù: Nhân viên chỉ khai báo tiền mặt đếm được trong két, không biết trước số dư dự kiến. Quản lý kiểm tra đối soát trên Web."}
              </div>
            </div>
          </div>

          <button
            onClick={handleToggleDifference}
            disabled={updatingSetting}
            style={{
              padding: "8px 16px",
              background: allowDifference ? "#C93B2B" : "#146A65",
              color: "#FFFFFF",
              border: "none",
              borderRadius: "8px",
              fontSize: "13px",
              fontWeight: "600",
              cursor: updatingSetting ? "not-allowed" : "pointer",
              transition: "all 0.2s",
            }}
          >
            {updatingSetting ? "Đang cập nhật..." : allowDifference ? "Tắt xem chênh lệch (Bật đếm mù)" : "Bật cho nhân viên xem"}
          </button>
        </div>
      </div>

      {/* KPI Cards */}
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
            <span>Tổng số ca giao két</span>
            <History size={18} color="#7E2930" />
          </div>
          <div style={{ fontSize: "24px", fontWeight: "800", color: "#1C1A2D", marginTop: "8px" }}>
            {formatNumber(summaryKpi.totalShifts)}
          </div>
          <div style={{ fontSize: "12px", color: "#666", marginTop: "4px" }}>
            {summaryKpi.openShifts} ca đang mở
          </div>
        </div>

        <div style={{ background: "#FFFFFF", border: "1px solid #E6DEC8", borderRadius: "14px", padding: "16px 20px" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", color: "#666", fontSize: "13px" }}>
            <span>Doanh số tiền mặt ca</span>
            <Coins size={18} color="#146A65" />
          </div>
          <div style={{ fontSize: "24px", fontWeight: "800", color: "#146A65", marginTop: "8px" }}>
            {formatVND(summaryKpi.totalCashSales)}
          </div>
          <div style={{ fontSize: "12px", color: "#666", marginTop: "4px" }}>
            Tổng tiền mặt thu qua đơn
          </div>
        </div>

        <div style={{ background: "#FFFFFF", border: "1px solid #E6DEC8", borderRadius: "14px", padding: "16px 20px" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", color: "#666", fontSize: "13px" }}>
            <span>Tiền kiểm đếm thực tế</span>
            <Wallet size={18} color="#1877F2" />
          </div>
          <div style={{ fontSize: "24px", fontWeight: "800", color: "#1C1A2D", marginTop: "8px" }}>
            {formatVND(summaryKpi.totalActualCash)}
          </div>
          <div style={{ fontSize: "12px", color: "#666", marginTop: "4px" }}>
            Khai báo két khi chốt ca
          </div>
        </div>

        <div style={{ background: "#FFFFFF", border: "1px solid #E6DEC8", borderRadius: "14px", padding: "16px 20px" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", color: "#666", fontSize: "13px" }}>
            <span>Chênh lệch két ròng</span>
            <ArrowUpDown
              size={18}
              color={summaryKpi.totalDiff === 0 ? "#146A65" : summaryKpi.totalDiff > 0 ? "#1877F2" : "#C93B2B"}
            />
          </div>
          <div
            style={{
              fontSize: "24px",
              fontWeight: "800",
              color: summaryKpi.totalDiff === 0 ? "#146A65" : summaryKpi.totalDiff > 0 ? "#1877F2" : "#C93B2B",
              marginTop: "8px",
            }}
          >
            {summaryKpi.totalDiff >= 0 ? "+" : ""}
            {formatVND(summaryKpi.totalDiff)}
          </div>
          <div style={{ fontSize: "12px", color: "#666", marginTop: "4px" }}>
            {summaryKpi.totalDiff === 0 ? "Khớp chuẩn 100%" : summaryKpi.totalDiff > 0 ? "Thừa tiền két" : "Thiếu hụt két"}
          </div>
        </div>
      </div>

      {/* Shifts Filter & Table */}
      <div
        style={{
          background: "#FFFFFF",
          borderRadius: "16px",
          border: "1px solid #E6DEC8",
          padding: "20px",
          boxShadow: "0 2px 10px rgba(0,0,0,0.02)",
        }}
      >
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: "12px", marginBottom: "16px" }}>
          <div style={{ display: "flex", alignItems: "center", gap: "8px", flex: 1, maxWidth: "380px" }}>
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
                placeholder="Tìm mã ca, tên nhân viên..."
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
            <div style={{ display: "flex", border: "1px solid #E6DEC8", borderRadius: "10px", overflow: "hidden" }}>
              {[
                { id: "ALL", label: "Tất cả" },
                { id: "OPEN", label: "Đang mở" },
                { id: "CLOSED", label: "Đã chốt ca" },
              ].map((item) => (
                <button
                  key={item.id}
                  onClick={() => setStatusFilter(item.id as "ALL" | "OPEN" | "CLOSED")}
                  style={{
                    padding: "6px 12px",
                    background: statusFilter === item.id ? "#7E2930" : "#FFFFFF",
                    color: statusFilter === item.id ? "#FFFFFF" : "#666",
                    border: "none",
                    fontSize: "12px",
                    fontWeight: "600",
                    cursor: "pointer",
                  }}
                >
                  {item.label}
                </button>
              ))}
            </div>

            {/* Export Buttons */}
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
        </div>

        {/* Table */}
        <div style={{ overflowX: "auto" }}>
          <table style={{ width: "100%", borderCollapse: "collapse", textAlign: "left", fontSize: "13px" }}>
            <thead>
              <tr style={{ borderBottom: "2px solid #E6DEC8", color: "#666" }}>
                <th style={{ padding: "10px 12px" }}>Mã ca</th>
                <th style={{ padding: "10px 12px" }}>Chi nhánh</th>
                <th style={{ padding: "10px 12px" }}>Thu ngân</th>
                <th style={{ padding: "10px 12px" }}>Thời gian</th>
                <th style={{ padding: "10px 12px", textAlign: "right" }}>Tiền đầu ca</th>
                <th style={{ padding: "10px 12px", textAlign: "right" }}>Doanh số ca</th>
                <th style={{ padding: "10px 12px", textAlign: "right" }}>Tiền đếm thực</th>
                <th style={{ padding: "10px 12px", textAlign: "right" }}>Chênh lệch</th>
                <th style={{ padding: "10px 12px", textAlign: "center" }}>Trạng thái</th>
                <th style={{ padding: "10px 12px", textAlign: "center" }}>Phiếu giao ca</th>
              </tr>
            </thead>
            <tbody>
              {filteredShifts.length === 0 ? (
                <tr>
                  <td colSpan={10} style={{ textAlign: "center", padding: "32px", color: "#999" }}>
                    Không tìm thấy phiên giao két nào
                  </td>
                </tr>
              ) : (
                filteredShifts.map((shift) => {
                  const diff = shift.difference ?? 0;
                  const isOpen = shift.status === "OPEN";

                  return (
                    <tr key={shift.shiftId || shift.shiftCode} style={{ borderBottom: "1px solid #F0ECE1" }}>
                      <td style={{ padding: "10px 12px", fontWeight: "700", color: "#7E2930" }}>
                        {shift.shiftCode}
                      </td>
                      <td style={{ padding: "10px 12px" }}>
                        <span style={{ padding: "2px 8px", background: "#F8F4EE", borderRadius: "4px", fontSize: "11px", fontWeight: "600" }}>
                          {shift.storeCode || "TRAM01"}
                        </span>
                      </td>
                      <td style={{ padding: "10px 12px" }}>
                        <div style={{ fontWeight: "600", color: "#1C1A2D" }}>{shift.staffFullName}</div>
                        <div style={{ fontSize: "11px", color: "#888" }}>@{shift.staffUsername}</div>
                      </td>
                      <td style={{ padding: "10px 12px", fontSize: "12px", color: "#666" }}>
                        <div>Mở: {fmtDate(shift.openedAt)}</div>
                        <div>Đóng: {fmtDate(shift.closedAt)}</div>
                      </td>
                      <td style={{ padding: "10px 12px", textAlign: "right" }}>
                        {formatVND(shift.initialCash || 0)}
                      </td>
                      <td style={{ padding: "10px 12px", textAlign: "right", fontWeight: "700" }}>
                        {formatVND(shift.totalSales || 0)}
                      </td>
                      <td style={{ padding: "10px 12px", textAlign: "right", fontWeight: "700" }}>
                        {isOpen ? <span style={{ color: "#999" }}>Đang mở</span> : formatVND(shift.actualCash || 0)}
                      </td>
                      <td style={{ padding: "10px 12px", textAlign: "right", fontWeight: "700" }}>
                        {isOpen ? (
                          <span style={{ color: "#999" }}>—</span>
                        ) : (
                          <span style={{ color: diff === 0 ? "#146A65" : diff > 0 ? "#1877F2" : "#C93B2B" }}>
                            {diff >= 0 ? "+" : ""}
                            {formatVND(diff)}
                          </span>
                        )}
                      </td>
                      <td style={{ padding: "10px 12px", textAlign: "center" }}>
                        <span
                          style={{
                            padding: "3px 10px",
                            borderRadius: "12px",
                            fontSize: "11px",
                            fontWeight: "700",
                            background: isOpen ? "#E6F4EA" : "#F1F3F4",
                            color: isOpen ? "#137333" : "#5F6368",
                          }}
                        >
                          {isOpen ? "ĐANG MỞ" : "ĐÃ KẾT CA"}
                        </span>
                      </td>
                      <td style={{ padding: "10px 12px", textAlign: "center" }}>
                        <button
                          onClick={() => setSelectedShift(shift)}
                          style={{
                            padding: "5px 12px",
                            background: "#F8F4EE",
                            border: "1px solid #E6DEC8",
                            borderRadius: "8px",
                            fontSize: "12px",
                            fontWeight: "600",
                            color: "#7E2930",
                            cursor: "pointer",
                          }}
                        >
                          Xem phiếu
                        </button>
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Printable Shift Handover Slip Modal */}
      {selectedShift && (
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
          onClick={() => setSelectedShift(null)}
        >
          <div
            style={{
              background: "#FFFFFF",
              borderRadius: "16px",
              padding: "28px",
              maxWidth: "520px",
              width: "100%",
              maxHeight: "90vh",
              overflowY: "auto",
              boxShadow: "0 10px 30px rgba(0,0,0,0.2)",
            }}
            onClick={(e) => e.stopPropagation()}
          >
            {/* Slip Paper Header */}
            <div style={{ textAlign: "center", borderBottom: "1px dashed #CCC", paddingBottom: "16px", marginBottom: "16px" }}>
              <div style={{ fontSize: "16px", fontWeight: "800", color: "#1C1A2D", letterSpacing: "0.5px" }}>
                POS TRẠM F&B - CHI NHÁNH {selectedShift.storeCode || "TRAM01"}
              </div>
              <div style={{ fontSize: "18px", fontWeight: "800", color: "#7E2930", marginTop: "4px" }}>
                PHIẾU BÀN GIAO CA BÁN HÀNG
              </div>
              <div style={{ fontSize: "12px", color: "#666", marginTop: "4px" }}>
                Mã ca: <strong>{selectedShift.shiftCode}</strong>
              </div>
              <div style={{ fontSize: "12px", color: "#666" }}>
                Thu ngân: <strong>{selectedShift.staffFullName}</strong> (@{selectedShift.staffUsername})
              </div>
              <div style={{ fontSize: "11px", color: "#888", marginTop: "2px" }}>
                Mở ca: {fmtDate(selectedShift.openedAt)}
              </div>
              <div style={{ fontSize: "11px", color: "#888" }}>
                Kết ca: {fmtDate(selectedShift.closedAt)}
              </div>
            </div>

            {/* Slip Paper Details */}
            <div style={{ display: "flex", flexDirection: "column", gap: "6px", fontSize: "13px" }}>
              <SlipLine label="1. Tiền mặt đầu ca:" value={formatVND(selectedShift.initialCash || 0)} />
              <SlipLine label="2. Doanh số tiền mặt (+):" value={formatVND(selectedShift.cashSales || 0)} color="#146A65" />
              <SlipLine label="3. Doanh số VietQR (+):" value={formatVND(selectedShift.qrSales || 0)} color="#1877F2" />
              <SlipLine label="4. Doanh số Thẻ / Khác (+):" value={formatVND(selectedShift.cardSales || 0)} color="#8A5B00" />
              <SlipLine label="5. Tiền nộp thêm vào két (Cash In):" value={formatVND(selectedShift.cashIn || 0)} />
              <SlipLine label="6. Tiền chi vặt từ két (Cash Out):" value={formatVND(selectedShift.cashOut || 0)} color="#C93B2B" />
              {selectedShift.refundCash > 0 && (
                <SlipLine label="7. Tiền hoàn trả tiền mặt (-):" value={formatVND(selectedShift.refundCash || 0)} color="#C93B2B" />
              )}
              <div style={{ borderBottom: "1px dashed #CCC", margin: "6px 0" }} />
              <SlipLine label="TỔNG DOANH THU CA:" value={formatVND(selectedShift.totalSales || 0)} isBold />
              <div style={{ borderBottom: "1px dashed #CCC", margin: "6px 0" }} />
              <SlipLine label="TIỀN KÉT KỲ VỌNG (Lý thuyết):" value={formatVND(selectedShift.expectedCash || 0)} isBold color="#7E2930" />
              <SlipLine label="TIỀN KIỂM ĐẾM THỰC TẾ:" value={formatVND(selectedShift.actualCash || 0)} isBold />
              <SlipLine
                label="CHÊNH LỆCH KÉT:"
                value={`${(selectedShift.difference || 0) >= 0 ? "+" : ""}${formatVND(selectedShift.difference || 0)}`}
                isBold
                color={(selectedShift.difference || 0) === 0 ? "#146A65" : (selectedShift.difference || 0) > 0 ? "#1877F2" : "#C93B2B"}
              />
            </div>

            {/* Promotional Breakdown for Shift (Module 4) */}
            <div style={{ marginTop: "14px", padding: "12px", background: "#FDF5F6", borderRadius: "10px", border: "1px solid #F5D5D8" }}>
              <div style={{ fontSize: "12px", fontWeight: "800", color: "#7E2930", marginBottom: "8px", display: "flex", alignItems: "center", gap: "6px" }}>
                <span>🏷️ KHUYẾN MÃI & GIẢM GIÁ TRONG CA</span>
              </div>
              <div style={{ display: "flex", flexDirection: "column", gap: "4px", fontSize: "12px" }}>
                <SlipLine
                  label={`• Món giảm giá (${shiftPromoStats.discountedItemsCount} món):`}
                  value={`-${formatVND(shiftPromoStats.discountedItemsTotal)}`}
                  color="#C93B2B"
                />
                <SlipLine
                  label={`• Voucher / KM đơn (${shiftPromoStats.voucherCount} lượt):`}
                  value={`-${formatVND(shiftPromoStats.voucherTotal)}`}
                  color="#C93B2B"
                />
                <SlipLine
                  label={`• Điểm KMT đổi (${shiftPromoStats.pointsUsedTotal} điểm):`}
                  value={`-${formatVND(shiftPromoStats.pointsDiscountTotal)}`}
                  color="#C93B2B"
                />
                <div style={{ borderBottom: "1px dashed #F5D5D8", margin: "4px 0" }} />
                <SlipLine
                  label="TỔNG CHI PHÍ GIẢM GIÁ CA:"
                  value={`-${formatVND(shiftPromoStats.totalPromoDiscount)}`}
                  isBold
                  color="#7E2930"
                />
              </div>
            </div>

            {selectedShift.notes && (
              <div style={{ marginTop: "14px", padding: "10px", background: "#FFF8ED", borderRadius: "8px", fontSize: "12px", color: "#8A5B00" }}>
                <strong>Ghi chú:</strong> {selectedShift.notes}
              </div>
            )}

            {/* Signature Area */}
            <div style={{ display: "flex", justifyContent: "space-between", marginTop: "30px", textAlign: "center", fontSize: "12px", color: "#666" }}>
              <div>
                <strong>Người giao ca</strong>
                <div style={{ height: "45px" }} />
                <div>{selectedShift.staffFullName}</div>
              </div>
              <div>
                <strong>Người nhận / Quản lý</strong>
                <div style={{ height: "45px" }} />
                <div>(Ký và ghi rõ họ tên)</div>
              </div>
            </div>

            {/* Actions */}
            <div style={{ display: "flex", justifyContent: "flex-end", flexWrap: "wrap", gap: "10px", marginTop: "24px", borderTop: "1px solid #EEE", paddingTop: "16px" }}>
              <button
                onClick={() => setSelectedShift(null)}
                style={{
                  padding: "8px 16px",
                  background: "#F0ECE1",
                  border: "none",
                  borderRadius: "8px",
                  fontSize: "13px",
                  fontWeight: "600",
                  cursor: "pointer",
                }}
              >
                Đóng
              </button>
              <button
                onClick={handleExportShiftPromoExcel}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: "6px",
                  padding: "8px 14px",
                  background: "#137333",
                  color: "#FFFFFF",
                  border: "none",
                  borderRadius: "8px",
                  fontSize: "13px",
                  fontWeight: "600",
                  cursor: "pointer",
                }}
              >
                <FileSpreadsheet size={15} /> Xuất Excel KM ca
              </button>
              <button
                onClick={() => window.print()}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: "6px",
                  padding: "8px 18px",
                  background: "#7E2930",
                  color: "#FFFFFF",
                  border: "none",
                  borderRadius: "8px",
                  fontSize: "13px",
                  fontWeight: "600",
                  cursor: "pointer",
                }}
              >
                <Printer size={15} /> In phiếu bàn giao
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function SlipLine({
  label,
  value,
  isBold = false,
  color = "#1C1A2D",
}: {
  label: string;
  value: string;
  isBold?: boolean;
  color?: string;
}) {
  return (
    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: "3px 0" }}>
      <span style={{ fontWeight: isBold ? "700" : "400", color: isBold ? "#1C1A2D" : "#555" }}>{label}</span>
      <span style={{ fontWeight: isBold ? "800" : "600", color }}>{value}</span>
    </div>
  );
}
