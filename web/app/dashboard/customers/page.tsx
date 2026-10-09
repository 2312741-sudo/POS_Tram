"use client";
import React, { useState, useEffect, useMemo } from "react";
import {
  Users,
  Search,
  FileSpreadsheet,
  Settings,
  Sparkles,
  Phone,
  CreditCard,
  Coins,
  RefreshCw,
  Check,
} from "lucide-react";
import { useAuth } from "@/lib/auth";
import { useDashboardData } from "@/lib/data-context";
import { db } from "@/lib/firebase";
import { ref, onValue } from "firebase/database";
import { exportCustomersList, CustomerExportItem } from "@/lib/export";
import { formatVND, formatNumber } from "@/lib/reports";
import {
  CUSTOMER_TIERS,
  StoreCustomer,
  canEditPointConfig,
  canReadCustomers,
  parseStoreCustomers,
} from "@/lib/customers";

const DEFAULT_REDEEM_RATE = 1000;
const DEFAULT_EARN_RATE = 1.0;

export default function CustomersPage() {
  const { user } = useAuth();
  const { stores, currentStoreCode, updateStore } = useDashboardData();

  // Dữ liệu khách theo từng chi nhánh: stores/{code}/customers (lắng nghe realtime)
  const [customersByStore, setCustomersByStore] = useState<Record<string, StoreCustomer[]>>({});
  const [loadedStores, setLoadedStores] = useState<Record<string, true>>({});
  const [deniedStores, setDeniedStores] = useState<string[]>([]);
  const [reloadKey, setReloadKey] = useState<number>(0);
  const [searchQuery, setSearchQuery] = useState<string>("");
  const [selectedTier, setSelectedTier] = useState<string>("ALL");

  const [showConfigModal, setShowConfigModal] = useState<boolean>(false);
  const [editingRedeemRate, setEditingRedeemRate] = useState<string>(String(DEFAULT_REDEEM_RATE));
  const [editingEarnRate, setEditingEarnRate] = useState<string>(String(DEFAULT_EARN_RATE));
  const [isSavingConfig, setIsSavingConfig] = useState<boolean>(false);
  const [configSuccess, setConfigSuccess] = useState<string | null>(null);

  const canRead = canReadCustomers(user?.roleId || user?.role, user?.isRootOwner);
  // Rules: chỉ Chủ quán ghi storeInfo; cần chọn 1 chi nhánh cụ thể để lưu
  const canEditConfig = canEditPointConfig(user?.roleId || user?.role, user?.isRootOwner) && currentStoreCode !== "ALL";

  // Chi nhánh cần đọc: "ALL" → mọi chi nhánh truy cập được; ngược lại chỉ chi nhánh đang chọn
  const targetCodes = useMemo(() => {
    if (currentStoreCode !== "ALL") return currentStoreCode ? [currentStoreCode] : [];
    return stores.map((s) => s.storeCode).filter(Boolean);
  }, [stores, currentStoreCode]);
  const targetKey = targetCodes.join(",");

  // Tỷ lệ quy đổi theo từng chi nhánh (storeInfo.pointRedeemRate / pointEarnRate)
  const ratesByStore = useMemo(() => {
    const map: Record<string, { redeem: number; earn: number }> = {};
    stores.forEach((s) => {
      map[s.storeCode] = {
        redeem: typeof s.pointRedeemRate === "number" && s.pointRedeemRate > 0 ? s.pointRedeemRate : DEFAULT_REDEEM_RATE,
        earn: typeof s.pointEarnRate === "number" ? s.pointEarnRate : DEFAULT_EARN_RATE,
      };
    });
    return map;
  }, [stores]);
  const redeemRateOf = (storeCode: string) => ratesByStore[storeCode]?.redeem ?? DEFAULT_REDEEM_RATE;
  const displayRates = currentStoreCode !== "ALL"
    ? ratesByStore[currentStoreCode] || { redeem: DEFAULT_REDEEM_RATE, earn: DEFAULT_EARN_RATE }
    : null;

  useEffect(() => {
    if (!canRead) return;
    const codes = targetKey ? targetKey.split(",") : [];
    const unsubs = codes.map((code) =>
      onValue(
        ref(db, `stores/${code}/customers`),
        (snap) => {
          setCustomersByStore((prev) => ({ ...prev, [code]: parseStoreCustomers(code, snap.val()) }));
          setLoadedStores((prev) => (prev[code] ? prev : { ...prev, [code]: true }));
          setDeniedStores((prev) => (prev.includes(code) ? prev.filter((c) => c !== code) : prev));
        },
        (error) => {
          console.warn(`[customers] Không thể đọc stores/${code}/customers:`, error.message);
          setCustomersByStore((prev) => ({ ...prev, [code]: [] }));
          setLoadedStores((prev) => (prev[code] ? prev : { ...prev, [code]: true }));
          setDeniedStores((prev) => (prev.includes(code) ? prev : [...prev, code]));
        }
      )
    );
    return () => unsubs.forEach((u) => u());
  }, [canRead, targetKey, reloadKey]);

  const loading = canRead && targetCodes.some((c) => !loadedStores[c]);

  const customers = useMemo(() => {
    const list: StoreCustomer[] = [];
    targetCodes.forEach((code) => list.push(...(customersByStore[code] || [])));
    return list.sort((a, b) => b.diemHienTai - a.diemHienTai);
  }, [customersByStore, targetCodes]);

  // Filtered customer list
  const filteredCustomers = useMemo(() => {
    const q = searchQuery.trim().toLowerCase();
    return customers.filter((c) => {
      if (selectedTier !== "ALL" && c.hangThanhVien !== selectedTier) return false;
      if (q) {
        const match =
          c.soDienThoai.toLowerCase().includes(q) ||
          c.hoTen.toLowerCase().includes(q) ||
          c.maKhachHang.toLowerCase().includes(q);
        if (!match) return false;
      }
      return true;
    });
  }, [customers, searchQuery, selectedTier]);

  // Aggregate KPI stats (giá trị quy đổi theo tỷ lệ của từng chi nhánh)
  const kpiStats = useMemo(() => {
    const totalCustomers = customers.length;
    const totalPoints = customers.reduce((sum, c) => sum + c.diemHienTai, 0);
    const totalPointValue = customers.reduce(
      (sum, c) => sum + c.diemHienTai * (ratesByStore[c.storeCode]?.redeem ?? DEFAULT_REDEEM_RATE),
      0
    );
    const vipCount = customers.filter((c) => c.diemHienTai >= 200).length;
    return { totalCustomers, totalPoints, totalPointValue, vipCount };
  }, [customers, ratesByStore]);

  // Export Excel
  const handleExportExcel = () => {
    const exportData: CustomerExportItem[] = filteredCustomers.map((c) => ({
      maKhachHang: c.maKhachHang,
      hoTen: c.hoTen,
      soDienThoai: c.soDienThoai,
      diemHienTai: c.diemHienTai,
      giaTriQuyDoi: c.diemHienTai * redeemRateOf(c.storeCode),
      hangThanhVien: c.hangThanhVien,
      ngayTao: c.ngayTao,
      tongChiTieu: c.tongChiTieu,
      soDonDaMua: c.soDonDaMua,
    }));
    exportCustomersList(exportData);
  };

  const openConfigModal = () => {
    if (displayRates) {
      setEditingRedeemRate(String(displayRates.redeem));
      setEditingEarnRate(String(displayRates.earn));
    }
    setShowConfigModal(true);
  };

  // Save point config → stores/{code}/storeInfo (chỉ Chủ quán, theo rules)
  const handleSaveConfig = async () => {
    if (!canEditConfig) return;
    const newRedeem = parseInt(editingRedeemRate.replace(/[^0-9]/g, ""), 10) || DEFAULT_REDEEM_RATE;
    const parsedEarn = parseFloat(editingEarnRate);
    const newEarn = Number.isFinite(parsedEarn) && parsedEarn >= 0 ? parsedEarn : DEFAULT_EARN_RATE;
    setIsSavingConfig(true);
    try {
      const res = await updateStore(currentStoreCode, { pointRedeemRate: newRedeem, pointEarnRate: newEarn });
      if (!res.success) throw new Error(res.error || "Không lưu được cấu hình");
      setConfigSuccess("Đã lưu tỷ lệ đổi điểm thành công!");
      setTimeout(() => {
        setConfigSuccess(null);
        setShowConfigModal(false);
      }, 1500);
    } catch (err) {
      alert("Lỗi lưu cấu hình: " + (err instanceof Error ? err.message : String(err)));
    } finally {
      setIsSavingConfig(false);
    }
  };

  const tiers = ["ALL", ...CUSTOMER_TIERS];
  const showStoreColumn = currentStoreCode === "ALL";
  const columnCount = showStoreColumn ? 9 : 8;

  return (
    <div style={{ padding: "24px 28px", maxWidth: "1280px", margin: "0 auto" }}>
      {/* Header */}
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
                Quản lý Khách hàng & Tích điểm CRM
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
                Khuyến Mãi Trạm (KMT)
              </span>
            </div>
            <p style={{ fontSize: "13px", color: "var(--subtext)", marginTop: "4px", margin: 0 }}>
              Số dư điểm lấy trực tiếp từ POS theo từng chi nhánh • Đồng bộ sang Khuyến Mãi Trạm • Điểm đổi voucher khấu trừ doanh thu
            </p>
          </div>

          <div style={{ display: "flex", gap: "10px", flexWrap: "wrap" }}>
            <button
              onClick={() => {
                setLoadedStores({});
                setReloadKey((k) => k + 1);
              }}
              style={{
                display: "flex",
                alignItems: "center",
                gap: "6px",
                padding: "8px 14px",
                background: "var(--bg)",
                border: "1px solid var(--border)",
                borderRadius: "8px",
                fontSize: "13px",
                fontWeight: "600",
                color: "var(--primary)",
                cursor: "pointer",
              }}
            >
              <RefreshCw size={15} /> Làm mới
            </button>
            {canEditConfig && (
              <button
                onClick={openConfigModal}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: "6px",
                  padding: "8px 14px",
                  background: "var(--primary)",
                  color: "#FFFFFF",
                  border: "none",
                  borderRadius: "8px",
                  fontSize: "13px",
                  fontWeight: "600",
                  cursor: "pointer",
                }}
              >
                <Settings size={15} /> Cấu hình đổi điểm
              </button>
            )}
            <button
              onClick={handleExportExcel}
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
              <FileSpreadsheet size={15} /> Xuất Excel Khách hàng
            </button>
          </div>
        </div>
      </div>

      {deniedStores.length > 0 && (
        <div
          style={{
            background: "var(--warning-bg, #FEF7E0)",
            color: "#8A5B00",
            border: "1px solid var(--border)",
            borderRadius: "12px",
            padding: "10px 14px",
            fontSize: "13px",
            marginBottom: "16px",
          }}
        >
          Không có quyền đọc khách hàng của chi nhánh: {deniedStores.join(", ")}
        </div>
      )}

      {/* KPI Cards */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(min(240px, 100%), 1fr))", gap: "16px", marginBottom: "20px" }}>
        <div style={{ background: "var(--surface)", borderRadius: "14px", padding: "18px 20px", border: "1px solid var(--border)" }}>
          <div style={{ display: "flex", flexWrap: "wrap", rowGap: "8px", justifyContent: "space-between", alignItems: "center" }}>
            <span style={{ fontSize: "13px", color: "var(--subtext)", fontWeight: "600" }}>Tổng Khách Hàng CRM</span>
            <div style={{ padding: "8px", background: "var(--surface-muted)", borderRadius: "10px", color: "var(--primary)" }}>
              <Users size={18} />
            </div>
          </div>
          <div style={{ fontSize: "24px", fontWeight: "800", color: "var(--text)", marginTop: "8px" }}>
            {formatNumber(kpiStats.totalCustomers)}
          </div>
          <div style={{ fontSize: "12px", color: "#8A5B00", marginTop: "4px" }}>
            {kpiStats.vipCount} khách hàng VIP (≥200 điểm)
          </div>
        </div>

        <div style={{ background: "var(--surface)", borderRadius: "14px", padding: "18px 20px", border: "1px solid var(--border)" }}>
          <div style={{ display: "flex", flexWrap: "wrap", rowGap: "8px", justifyContent: "space-between", alignItems: "center" }}>
            <span style={{ fontSize: "13px", color: "var(--subtext)", fontWeight: "600" }}>Tổng Điểm Lưu Hành</span>
            <div style={{ padding: "8px", background: "var(--info-bg)", borderRadius: "10px", color: "#1877F2" }}>
              <Coins size={18} />
            </div>
          </div>
          <div style={{ fontSize: "24px", fontWeight: "800", color: "#1877F2", marginTop: "8px" }}>
            {formatNumber(kpiStats.totalPoints)} <span style={{ fontSize: "14px" }}>điểm</span>
          </div>
          <div style={{ fontSize: "12px", color: "var(--subtext)", marginTop: "4px" }}>
            Tích lũy từ doanh số F&B
          </div>
        </div>

        <div style={{ background: "var(--surface)", borderRadius: "14px", padding: "18px 20px", border: "1px solid var(--border)" }}>
          <div style={{ display: "flex", flexWrap: "wrap", rowGap: "8px", justifyContent: "space-between", alignItems: "center" }}>
            <span style={{ fontSize: "13px", color: "var(--subtext)", fontWeight: "600" }}>Giá Trị Quy Đổi Điểm</span>
            <div style={{ padding: "8px", background: "var(--success-bg)", borderRadius: "10px", color: "#137333" }}>
              <CreditCard size={18} />
            </div>
          </div>
          <div style={{ fontSize: "24px", fontWeight: "800", color: "#137333", marginTop: "8px" }}>
            {formatVND(kpiStats.totalPointValue)}
          </div>
          <div style={{ fontSize: "12px", color: "#137333", marginTop: "4px" }}>
            Quy đổi theo tỷ lệ thiết lập
          </div>
        </div>

        <div style={{ background: "var(--surface)", borderRadius: "14px", padding: "18px 20px", border: "1px solid var(--border)" }}>
          <div style={{ display: "flex", flexWrap: "wrap", rowGap: "8px", justifyContent: "space-between", alignItems: "center" }}>
            <span style={{ fontSize: "13px", color: "var(--subtext)", fontWeight: "600" }}>Tỷ Lệ Đổi Điểm Hiện Tại</span>
            <div style={{ padding: "8px", background: "var(--primary-light)", borderRadius: "10px", color: "var(--primary)" }}>
              <Sparkles size={18} />
            </div>
          </div>
          <div style={{ fontSize: "20px", fontWeight: "800", color: "var(--primary)", marginTop: "8px" }}>
            {displayRates ? `1 điểm = ${formatVND(displayRates.redeem)}` : "Theo từng chi nhánh"}
          </div>
          <div style={{ fontSize: "12px", color: "var(--subtext)", marginTop: "4px" }}>
            {displayRates ? `Tích ${displayRates.earn}% doanh số hóa đơn` : "Chọn 1 chi nhánh để xem / sửa tỷ lệ"}
          </div>
        </div>
      </div>

      {/* Filter and Search Bar */}
      <div
        style={{
          background: "var(--surface)",
          borderRadius: "14px",
          border: "1px solid var(--border)",
          padding: "16px 20px",
          marginBottom: "16px",
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          flexWrap: "wrap",
          gap: "14px",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: "10px", flex: 1, minWidth: "260px" }}>
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: "8px",
              background: "var(--bg)",
              padding: "8px 14px",
              borderRadius: "8px",
              border: "1px solid var(--border)",
              width: "100%",
              maxWidth: "360px",
            }}
          >
            <Search size={16} color="#888" />
            <input
              type="text"
              placeholder="Tìm theo Tên, SĐT hoặc Mã khách..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              style={{
                border: "none",
                background: "transparent",
                outline: "none",
                fontSize: "13px",
                width: "100%",
              }}
            />
          </div>
        </div>

        {/* Tier filter chips */}
        <div style={{ display: "flex", gap: "6px", flexWrap: "wrap" }}>
          {tiers.map((t) => {
            const active = selectedTier === t;
            return (
              <button
                key={t}
                onClick={() => setSelectedTier(t)}
                style={{
                  padding: "6px 14px",
                  borderRadius: "20px",
                  border: active ? "1px solid var(--primary)" : "1px solid var(--border)",
                  background: active ? "var(--primary)" : "var(--surface)",
                  color: active ? "#FFFFFF" : "var(--subtext)",
                  fontSize: "12px",
                  fontWeight: active ? "700" : "500",
                  cursor: "pointer",
                }}
              >
                {t === "ALL" ? "Tất cả hạng" : t}
              </button>
            );
          })}
        </div>
      </div>

      {/* Customers Table */}
      <div
        style={{
          background: "var(--surface)",
          borderRadius: "14px",
          border: "1px solid var(--border)",
          overflow: "hidden",
          boxShadow: "0 2px 8px rgba(0,0,0,0.02)",
        }}
      >
        <div style={{ overflowX: "auto" }}>
          <table style={{ width: "100%", borderCollapse: "collapse", fontSize: "13px" }}>
            <thead>
              <tr style={{ background: "var(--bg)", borderBottom: "1px solid var(--border)", textAlign: "left", color: "var(--text)" }}>
                <th style={{ padding: "12px 14px", width: "50px", textAlign: "center" }}>STT</th>
                {showStoreColumn && <th style={{ padding: "12px 14px" }}>Chi nhánh</th>}
                <th style={{ padding: "12px 14px" }}>Khách hàng</th>
                <th style={{ padding: "12px 14px" }}>Số điện thoại</th>
                <th style={{ padding: "12px 14px" }}>Mã khách hàng</th>
                <th style={{ padding: "12px 14px", textAlign: "right" }}>Điểm tích lũy</th>
                <th style={{ padding: "12px 14px", textAlign: "right" }}>Giá trị đổi thưởng</th>
                <th style={{ padding: "12px 14px", textAlign: "center" }}>Hạng</th>
                <th style={{ padding: "12px 14px", textAlign: "center" }}>Ngày tham gia</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr>
                  <td colSpan={columnCount} style={{ padding: "40px", textAlign: "center", color: "var(--muted)" }}>
                    Đang tải danh sách khách hàng...
                  </td>
                </tr>
              ) : !canRead ? (
                <tr>
                  <td colSpan={columnCount} style={{ padding: "40px", textAlign: "center", color: "var(--muted)" }}>
                    Vai trò của bạn không có quyền xem danh sách khách hàng
                  </td>
                </tr>
              ) : filteredCustomers.length === 0 ? (
                <tr>
                  <td colSpan={columnCount} style={{ padding: "40px", textAlign: "center", color: "var(--muted)" }}>
                    Không tìm thấy khách hàng nào phù hợp
                  </td>
                </tr>
              ) : (
                filteredCustomers.map((c, idx) => {
                  const redeemVal = c.diemHienTai * redeemRateOf(c.storeCode);
                  return (
                    <tr
                      key={`${c.storeCode}:${c.id}`}
                      style={{ borderBottom: "1px solid #F0ECE1" }}
                    >
                      <td style={{ padding: "12px 14px", textAlign: "center", color: "var(--muted)" }}>{idx + 1}</td>
                      {showStoreColumn && (
                        <td style={{ padding: "12px 14px", color: "var(--subtext)", fontFamily: "monospace" }}>{c.storeCode}</td>
                      )}
                      <td style={{ padding: "12px 14px", fontWeight: "700", color: "var(--text)" }}>
                        {c.hoTen}
                      </td>
                      <td style={{ padding: "12px 14px" }}>
                        <span style={{ display: "inline-flex", alignItems: "center", gap: "4px" }}>
                          <Phone size={13} color="#7E2930" />
                          <strong>{c.soDienThoai || "—"}</strong>
                        </span>
                      </td>
                      <td style={{ padding: "12px 14px", color: "var(--subtext)", fontFamily: "monospace" }}>
                        {c.maKhachHang || "—"}
                      </td>
                      <td style={{ padding: "12px 14px", textAlign: "right", fontWeight: "800", color: "#1877F2" }}>
                        {formatNumber(c.diemHienTai)} pt
                      </td>
                      <td style={{ padding: "12px 14px", textAlign: "right", fontWeight: "700", color: "#137333" }}>
                        {formatVND(redeemVal)}
                      </td>
                      <td style={{ padding: "12px 14px", textAlign: "center" }}>
                        <span
                          style={{
                            padding: "3px 10px",
                            borderRadius: "12px",
                            fontSize: "11px",
                            fontWeight: "700",
                            background:
                              c.hangThanhVien === "Kim Cương"
                                ? "var(--info-bg)"
                                : c.hangThanhVien === "Vàng"
                                ? "#FEF7E0"
                                : c.hangThanhVien === "Bạc"
                                ? "#F1F3F4"
                                : "var(--bg)",
                            color:
                              c.hangThanhVien === "Kim Cương"
                                ? "#1877F2"
                                : c.hangThanhVien === "Vàng"
                                ? "#B06000"
                                : c.hangThanhVien === "Bạc"
                                ? "#5F6368"
                                : "var(--primary)",
                          }}
                        >
                          {c.hangThanhVien}
                        </span>
                      </td>
                      <td style={{ padding: "12px 14px", textAlign: "center", color: "var(--muted)", fontSize: "12px" }}>
                        {c.ngayTao || "—"}
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Modal Configure Point Conversion Rate */}
      {showConfigModal && (
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
          onClick={() => setShowConfigModal(false)}
        >
          <div
            style={{
              background: "var(--surface)",
              borderRadius: "16px",
              padding: "24px 28px",
              maxWidth: "480px",
              width: "100%",
              boxShadow: "0 10px 30px rgba(0,0,0,0.2)",
            }}
            onClick={(e) => e.stopPropagation()}
          >
            <div style={{ display: "flex", alignItems: "center", gap: "8px", marginBottom: "16px" }}>
              <Settings size={20} color="#7E2930" />
              <h2 style={{ fontSize: "17px", fontWeight: "800", color: "var(--text)", margin: 0 }}>
                Cấu hình Tỷ Lệ Đổi Điểm KMT CRM
              </h2>
            </div>
            <p style={{ fontSize: "13px", color: "var(--subtext)", marginBottom: "16px" }}>
              Chủ quán thiết lập giá trị quy đổi 1 điểm sang VNĐ khi khách thanh toán bằng điểm tích luỹ. Điểm dùng sẽ được trừ trực tiếp vào hoá đơn dưới dạng chiết khấu/khuyến mãi (không tính vào doanh thu thuần).
            </p>

            {configSuccess && (
              <div
                style={{
                  padding: "10px 14px",
                  background: "var(--success-bg)",
                  color: "#137333",
                  borderRadius: "8px",
                  fontSize: "13px",
                  fontWeight: "600",
                  marginBottom: "14px",
                  display: "flex",
                  alignItems: "center",
                  gap: "6px",
                }}
              >
                <Check size={16} /> {configSuccess}
              </div>
            )}

            <div style={{ display: "flex", flexDirection: "column", gap: "14px" }}>
              <div>
                <label style={{ fontSize: "13px", fontWeight: "700", color: "var(--text)", display: "block", marginBottom: "6px" }}>
                  Giá trị quy đổi: 1 Điểm = ? VNĐ (Mặc định 1.000đ)
                </label>
                <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
                  <input
                    type="number"
                    value={editingRedeemRate}
                    onChange={(e) => setEditingRedeemRate(e.target.value)}
                    style={{
                      flex: 1,
                      padding: "10px 14px",
                      borderRadius: "8px",
                      border: "1px solid #CCC",
                      fontSize: "14px",
                      fontWeight: "700",
                    }}
                  />
                  <span style={{ fontSize: "14px", fontWeight: "700", color: "var(--primary)" }}>VNĐ / Điểm</span>
                </div>
              </div>

              <div>
                <label style={{ fontSize: "13px", fontWeight: "700", color: "var(--text)", display: "block", marginBottom: "6px" }}>
                  Tỷ lệ tích điểm: % Doanh số hoá đơn (Mặc định 1.0%)
                </label>
                <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
                  <input
                    type="number"
                    step="0.1"
                    value={editingEarnRate}
                    onChange={(e) => setEditingEarnRate(e.target.value)}
                    style={{
                      flex: 1,
                      padding: "10px 14px",
                      borderRadius: "8px",
                      border: "1px solid #CCC",
                      fontSize: "14px",
                      fontWeight: "700",
                    }}
                  />
                  <span style={{ fontSize: "14px", fontWeight: "700", color: "var(--primary)" }}>% Hoá đơn</span>
                </div>
              </div>
            </div>

            <div style={{ display: "flex", justifyContent: "flex-end", gap: "10px", marginTop: "24px" }}>
              <button
                onClick={() => setShowConfigModal(false)}
                style={{
                  padding: "8px 16px",
                  background: "var(--surface-muted)",
                  border: "none",
                  borderRadius: "8px",
                  fontSize: "13px",
                  fontWeight: "600",
                  cursor: "pointer",
                }}
              >
                Hủy
              </button>
              <button
                onClick={handleSaveConfig}
                disabled={isSavingConfig}
                style={{
                  padding: "8px 18px",
                  background: "var(--primary)",
                  color: "#FFFFFF",
                  border: "none",
                  borderRadius: "8px",
                  fontSize: "13px",
                  fontWeight: "600",
                  cursor: "pointer",
                }}
              >
                {isSavingConfig ? "Đang lưu..." : "Lưu cấu hình"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
