"use client";
import React, { useState, useMemo } from "react";
import { useDashboardData, CashShiftItem } from "@/lib/data-context";
import {
  Calendar,
  Store,
  Search,
  Printer,
  ShieldCheck,
  Eye,
  EyeOff,
  CheckCircle2,
  Clock,
  AlertTriangle,
  Receipt,
  FileSpreadsheet,
} from "lucide-react";

export default function ShiftsPage() {
  const { stores, currentStoreCode, setCurrentStoreCode, cashShifts, updateStoreShiftDifferenceSetting } =
    useDashboardData();

  const [searchQuery, setSearchQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState<"ALL" | "OPEN" | "CLOSED">("ALL");
  const [selectedShift, setSelectedShift] = useState<CashShiftItem | null>(null);
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

  const filteredShifts = useMemo(() => {
    return cashShifts.filter((s) => {
      if (statusFilter === "OPEN" && s.status !== "OPEN") return false;
      if (statusFilter === "CLOSED" && s.status === "OPEN") return false;

      if (searchQuery.trim()) {
        const q = searchQuery.toLowerCase();
        const matchCode = (s.shiftCode || "").toLowerCase().includes(q);
        const matchStaff =
          (s.staffFullName || "").toLowerCase().includes(q) || (s.staffUsername || "").toLowerCase().includes(q);
        if (!matchCode && !matchStaff) return false;
      }
      return true;
    });
  }, [cashShifts, statusFilter, searchQuery]);

  const fmtVND = (num: number) => new Intl.NumberFormat("vi-VN").format(num) + "đ";

  const fmtDate = (timestamp?: number) => {
    if (!timestamp) return "Chưa đóng";
    const d = new Date(timestamp);
    return `${d.getHours().toString().padStart(2, "0")}:${d.getMinutes().toString().padStart(2, "0")} - ${d
      .getDate()
      .toString()
      .padStart(2, "0")}/${(d.getMonth() + 1).toString().padStart(2, "0")}/${d.getFullYear()}`;
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

          <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
            <div style={{ display: "flex", border: "1px solid #E6DEC8", borderRadius: "10px", overflow: "hidden" }}>
              {[
                { id: "ALL", label: "Tất cả" },
                { id: "OPEN", label: "Đang mở" },
                { id: "CLOSED", label: "Đã chốt ca" },
              ].map((item) => (
                <button
                  key={item.id}
                  onClick={() => setStatusFilter(item.id as any)}
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
                <th style={{ padding: "10px 12px", textAlign: "right" }}>Doanh thu ca</th>
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
                    <tr key={shift.id} style={{ borderBottom: "1px solid #F0ECE1" }}>
                      <td style={{ padding: "10px 12px", fontWeight: "700", color: "#7E2930" }}>
                        {shift.shiftCode}
                      </td>
                      <td style={{ padding: "10px 12px" }}>
                        <span style={{ padding: "2px 8px", background: "#F8F4EE", borderRadius: "4px", fontSize: "11px", fontWeight: "600" }}>
                          {shift.storeCode}
                        </span>
                      </td>
                      <td style={{ padding: "10px 12px" }}>
                        <div style={{ fontWeight: "600", color: "#1C1A2D" }}>{shift.staffFullName}</div>
                        <div style={{ fontSize: "11px", color: "#888" }}>@{shift.staffUsername}</div>
                      </td>
                      <td style={{ padding: "10px 12px", fontSize: "12px", color: "#666" }}>
                        <div>Mở: {fmtDate(shift.openedAt || shift.startTime)}</div>
                        <div>Đóng: {fmtDate(shift.closedAt || shift.endTime)}</div>
                      </td>
                      <td style={{ padding: "10px 12px", textAlign: "right" }}>
                        {fmtVND(shift.initialCash || 0)}
                      </td>
                      <td style={{ padding: "10px 12px", textAlign: "right", fontWeight: "700" }}>
                        {fmtVND(shift.totalRevenue || 0)}
                      </td>
                      <td style={{ padding: "10px 12px", textAlign: "right", fontWeight: "700" }}>
                        {isOpen ? <span style={{ color: "#999" }}>Đang mở</span> : fmtVND(shift.actualCash || 0)}
                      </td>
                      <td style={{ padding: "10px 12px", textAlign: "right", fontWeight: "700" }}>
                        {isOpen ? (
                          <span style={{ color: "#999" }}>-</span>
                        ) : (
                          <span style={{ color: diff === 0 ? "#146A65" : diff > 0 ? "#1877F2" : "#C93B2B" }}>
                            {diff >= 0 ? "+" : ""}
                            {fmtVND(diff)}
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
                POS TRẠM F&B - CHI NHÁNH {selectedShift.storeCode}
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
                Mở ca: {fmtDate(selectedShift.openedAt || selectedShift.startTime)}
              </div>
              <div style={{ fontSize: "11px", color: "#888" }}>
                Kết ca: {fmtDate(selectedShift.closedAt || selectedShift.endTime)}
              </div>
            </div>

            {/* Slip Paper Details */}
            <div style={{ display: "flex", flexDirection: "column", gap: "6px", fontSize: "13px" }}>
              <SlipLine label="1. Tiền mặt đầu ca:" value={fmtVND(selectedShift.initialCash || 0)} />
              <SlipLine label="2. Doanh số tiền mặt (+):" value={fmtVND(selectedShift.totalCashSales || 0)} color="#146A65" />
              <SlipLine label="3. Doanh số VietQR (+):" value={fmtVND(selectedShift.totalQrSales || 0)} color="#1877F2" />
              <SlipLine label="4. Tiền nộp thêm vào két (Cash In):" value={fmtVND(selectedShift.cashIn || 0)} />
              <SlipLine label="5. Tiền chi vặt từ két (Cash Out):" value={fmtVND(selectedShift.cashOut || 0)} color="#C93B2B" />
              <div style={{ borderBottom: "1px dashed #CCC", margin: "6px 0" }} />
              <SlipLine label="TỔNG DOANH THU CA:" value={fmtVND(selectedShift.totalRevenue || 0)} isBold />
              <div style={{ borderBottom: "1px dashed #CCC", margin: "6px 0" }} />
              <SlipLine label="TIỀN KÉT KỲ VỌNG (Lý thuyết):" value={fmtVND(selectedShift.expectedCash || 0)} isBold color="#7E2930" />
              <SlipLine label="TIỀN KIỂM ĐẾM THỰC TẾ:" value={fmtVND(selectedShift.actualCash || 0)} isBold />
              <SlipLine
                label="CHÊNH LỆCH KÉT:"
                value={`${(selectedShift.difference || 0) >= 0 ? "+" : ""}${fmtVND(selectedShift.difference || 0)}`}
                isBold
                color={(selectedShift.difference || 0) === 0 ? "#146A65" : (selectedShift.difference || 0) > 0 ? "#1877F2" : "#C93B2B"}
              />
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
            <div style={{ display: "flex", justifyContent: "flex-end", gap: "10px", marginTop: "24px", borderTop: "1px solid #EEE", paddingTop: "16px" }}>
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
