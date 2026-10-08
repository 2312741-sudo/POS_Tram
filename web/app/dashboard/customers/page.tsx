"use client";
import React, { useState, useEffect, useMemo, useCallback } from "react";
import {
  Users,
  Search,
  FileSpreadsheet,
  Settings,
  Sparkles,
  Phone,
  CreditCard,
  Coins,
  Award,
  RefreshCw,
  Plus,
  Check,
  AlertCircle,
} from "lucide-react";
import { useAuth } from "@/lib/auth";
import { useDashboardData } from "@/lib/data-context";
import { db, firestore } from "@/lib/firebase";
import { collection, getDocs, doc, setDoc } from "firebase/firestore";
import { ref, get, update } from "firebase/database";
import { exportCustomersList, CustomerExportItem } from "@/lib/export";
import { formatVND, formatNumber } from "@/lib/reports";

export interface KmtCustomer {
  id: string;
  soDienThoai: string;
  hoTen: string;
  maKhachHang: string;
  diemHienTai: number;
  hangThanhVien: string;
  ngayTao?: string;
  tongChiTieu?: number;
  soDonDaMua?: number;
}

interface PointConfig {
  pointRedeemRate?: number;
  pointEarnRate?: number;
}

// Đọc cấu hình quy đổi điểm từ store_info (không setState — để effect/handler tự áp dụng)
async function fetchPointConfig(): Promise<PointConfig> {
  try {
    const snap = await get(ref(db, "store_info"));
    if (snap.exists()) {
      const val = snap.val();
      return {
        pointRedeemRate: val.pointRedeemRate != null ? Number(val.pointRedeemRate) : undefined,
        pointEarnRate: val.pointEarnRate != null ? Number(val.pointEarnRate) : undefined,
      };
    }
  } catch (e) {
    console.warn("Could not load point config from store_info:", e);
  }
  return {};
}

// Fetch all customers from Firestore kmt_customers with RTDB fallback
async function fetchCustomerList(): Promise<KmtCustomer[]> {
  const map = new Map<string, KmtCustomer>();

  // 1. Fetch from Firestore collection kmt_customers
  try {
    const colRef = collection(firestore, "kmt_customers");
    const snap = await getDocs(colRef);
    snap.forEach((docSnap) => {
      const data = docSnap.data();
      const phone = String(data.so_dien_thoai || data.phone || docSnap.id || "").trim();
      const code = String(data.ma_khach_hang || data.customer_code || docSnap.id || "").trim();
      const name = String(data.ho_ten || data.fullName || data.name || "Khách hàng KMT").trim();
      const points = Number(data.diem_hien_tai ?? data.current_points ?? data.points ?? 0);
      const tier = String(data.hang_thanh_vien || data.rank || (points >= 500 ? "Kim Cương" : points >= 200 ? "Vàng" : points >= 50 ? "Bạc" : "Thành viên"));
      const created = data.ngay_tao || data.createdAt ? new Date(data.ngay_tao || data.createdAt).toLocaleDateString("vi-VN") : undefined;

      if (phone || code) {
        const key = phone || code;
        map.set(key, {
          id: docSnap.id,
          soDienThoai: phone,
          maKhachHang: code,
          hoTen: name,
          diemHienTai: points,
          hangThanhVien: tier,
          ngayTao: created,
          tongChiTieu: Number(data.tong_chi_tieu || 0),
          soDonDaMua: Number(data.so_don || 0),
        });
      }
    });
  } catch (err) {
    console.warn("Firestore kmt_customers fetch fallback to RTDB:", err);
  }

  // 2. Fetch from RTDB customers fallback
  try {
    const rtdbSnap = await get(ref(db, "customers"));
    if (rtdbSnap.exists()) {
      const val = rtdbSnap.val();
      if (typeof val === "object" && val !== null) {
        Object.entries(val as Record<string, Record<string, unknown>>).forEach(([k, v]) => {
          const phone = String(v.phone || v.so_dien_thoai || k).trim();
          const code = String(v.customerCode || v.ma_khach_hang || k).trim();
          const key = phone || code;
          if (!map.has(key)) {
            const pts = Number(v.currentPoints ?? v.diem_hien_tai ?? 0);
            map.set(key, {
              id: k,
              soDienThoai: phone,
              maKhachHang: code,
              hoTen: String(v.fullName || v.ho_ten || "Khách lẻ"),
              diemHienTai: pts,
              hangThanhVien: String(v.tier || (pts >= 500 ? "Kim Cương" : pts >= 200 ? "Vàng" : pts >= 50 ? "Bạc" : "Thành viên")),
              ngayTao: v.createdAt ? new Date(v.createdAt as string | number).toLocaleDateString("vi-VN") : undefined,
              tongChiTieu: Number(v.totalSpent || 0),
              soDonDaMua: Number(v.orderCount || 0),
            });
          }
        });
      }
    }
  } catch (e) {
    console.warn("RTDB customers fetch error:", e);
  }

  return Array.from(map.values()).sort((a, b) => b.diemHienTai - a.diemHienTai);
}

export default function CustomersPage() {
  const { user } = useAuth();
  const { stores, currentStoreCode } = useDashboardData();

  const [customers, setCustomers] = useState<KmtCustomer[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [searchQuery, setSearchQuery] = useState<string>("");
  const [selectedTier, setSelectedTier] = useState<string>("ALL");

  // Point rate config
  const [pointRedeemRate, setPointRedeemRate] = useState<number>(1000);
  const [pointEarnRate, setPointEarnRate] = useState<number>(1.0);
  const [showConfigModal, setShowConfigModal] = useState<boolean>(false);
  const [editingRedeemRate, setEditingRedeemRate] = useState<string>("1000");
  const [editingEarnRate, setEditingEarnRate] = useState<string>("1.0");
  const [isSavingConfig, setIsSavingConfig] = useState<boolean>(false);
  const [configSuccess, setConfigSuccess] = useState<string | null>(null);

  const canManage = useMemo(() => {
    if (!user) return false;
    if (user.isRootOwner) return true;
    const r = (user.roleId || user.role || "").toUpperCase();
    return r.includes("OWNER") || r.includes("MANAGER");
  }, [user]);

  // Load point config from store info
  const applyPointConfig = useCallback((cfg: PointConfig) => {
    if (cfg.pointRedeemRate != null) {
      setPointRedeemRate(cfg.pointRedeemRate);
      setEditingRedeemRate(String(cfg.pointRedeemRate));
    }
    if (cfg.pointEarnRate != null) {
      setPointEarnRate(cfg.pointEarnRate);
      setEditingEarnRate(String(cfg.pointEarnRate));
    }
  }, []);

  const reloadAll = useCallback(() => {
    return Promise.all([fetchPointConfig(), fetchCustomerList()]);
  }, []);

  useEffect(() => {
    let active = true;
    reloadAll().then(([cfg, list]) => {
      if (!active) return;
      applyPointConfig(cfg);
      setCustomers(list);
      setLoading(false);
    });
    return () => {
      active = false;
    };
  }, [reloadAll, applyPointConfig]);

  // Filtered customer list
  const filteredCustomers = useMemo(() => {
    return customers.filter((c) => {
      if (selectedTier !== "ALL" && c.hangThanhVien !== selectedTier) {
        return false;
      }
      if (searchQuery.trim()) {
        const q = searchQuery.toLowerCase();
        const matchPhone = c.soDienThoai.toLowerCase().includes(q);
        const matchName = c.hoTen.toLowerCase().includes(q);
        const matchCode = c.maKhachHang.toLowerCase().includes(q);
        if (!matchPhone && !matchName && !matchCode) return false;
      }
      return true;
    });
  }, [customers, searchQuery, selectedTier]);

  // Aggregate KPI stats
  const kpiStats = useMemo(() => {
    const totalCustomers = customers.length;
    const totalPoints = customers.reduce((sum, c) => sum + c.diemHienTai, 0);
    const totalPointValue = totalPoints * pointRedeemRate;
    const vipCount = customers.filter((c) => c.diemHienTai >= 200).length;
    return { totalCustomers, totalPoints, totalPointValue, vipCount };
  }, [customers, pointRedeemRate]);

  // Export Excel
  const handleExportExcel = () => {
    const exportData: CustomerExportItem[] = filteredCustomers.map((c) => ({
      maKhachHang: c.maKhachHang,
      hoTen: c.hoTen,
      soDienThoai: c.soDienThoai,
      diemHienTai: c.diemHienTai,
      giaTriQuyDoi: c.diemHienTai * pointRedeemRate,
      hangThanhVien: c.hangThanhVien,
      ngayTao: c.ngayTao,
      tongChiTieu: c.tongChiTieu,
      soDonDaMua: c.soDonDaMua,
    }));
    exportCustomersList(exportData);
  };

  // Save point config
  const handleSaveConfig = async () => {
    const newRedeem = parseInt(editingRedeemRate.replace(/[^0-9]/g, ""), 10) || 1000;
    const newEarn = parseFloat(editingEarnRate) || 1.0;
    setIsSavingConfig(true);
    try {
      await update(ref(db, "store_info"), {
        pointRedeemRate: newRedeem,
        pointEarnRate: newEarn,
      });
      setPointRedeemRate(newRedeem);
      setPointEarnRate(newEarn);
      setConfigSuccess("Đã lưu tỷ lệ đổi điểm thành công!");
      setTimeout(() => {
        setConfigSuccess(null);
        setShowConfigModal(false);
      }, 1500);
    } catch (err) {
      alert("Lỗi lưu cấu hình: " + err);
    } finally {
      setIsSavingConfig(false);
    }
  };

  const tiers = ["ALL", "Thành viên", "Bạc", "Vàng", "Kim Cương"];

  return (
    <div style={{ padding: "24px 28px", maxWidth: "1280px", margin: "0 auto" }}>
      {/* Header */}
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
                Quản lý Khách hàng & Tích điểm CRM
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
                Khuyến Mãi Trạm (KMT)
              </span>
            </div>
            <p style={{ fontSize: "13px", color: "#666", marginTop: "4px", margin: 0 }}>
              Đồng bộ dữ liệu khách hàng đa nền tảng với ứng dụng Khuyến Mãi Trạm • Điểm đổi voucher khấu trừ doanh thu
            </p>
          </div>

          <div style={{ display: "flex", gap: "10px", flexWrap: "wrap" }}>
            <button
              onClick={() => {
                setLoading(true);
                reloadAll().then(([cfg, list]) => {
                  applyPointConfig(cfg);
                  setCustomers(list);
                  setLoading(false);
                });
              }}
              style={{
                display: "flex",
                alignItems: "center",
                gap: "6px",
                padding: "8px 14px",
                background: "#F8F4EE",
                border: "1px solid #E6DEC8",
                borderRadius: "8px",
                fontSize: "13px",
                fontWeight: "600",
                color: "#7E2930",
                cursor: "pointer",
              }}
            >
              <RefreshCw size={15} /> Làm mới
            </button>
            {canManage && (
              <button
                onClick={() => setShowConfigModal(true)}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: "6px",
                  padding: "8px 14px",
                  background: "#7E2930",
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

      {/* KPI Cards */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(240px, 1fr))", gap: "16px", marginBottom: "20px" }}>
        <div style={{ background: "#FFFFFF", borderRadius: "14px", padding: "18px 20px", border: "1px solid #E6DEC8" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <span style={{ fontSize: "13px", color: "#666", fontWeight: "600" }}>Tổng Khách Hàng CRM</span>
            <div style={{ padding: "8px", background: "#F5F0E6", borderRadius: "10px", color: "#7E2930" }}>
              <Users size={18} />
            </div>
          </div>
          <div style={{ fontSize: "24px", fontWeight: "800", color: "#1C1A2D", marginTop: "8px" }}>
            {formatNumber(kpiStats.totalCustomers)}
          </div>
          <div style={{ fontSize: "12px", color: "#8A5B00", marginTop: "4px" }}>
            {kpiStats.vipCount} khách hàng VIP (≥200 điểm)
          </div>
        </div>

        <div style={{ background: "#FFFFFF", borderRadius: "14px", padding: "18px 20px", border: "1px solid #E6DEC8" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <span style={{ fontSize: "13px", color: "#666", fontWeight: "600" }}>Tổng Điểm Lưu Hành</span>
            <div style={{ padding: "8px", background: "#E8F0FE", borderRadius: "10px", color: "#1877F2" }}>
              <Coins size={18} />
            </div>
          </div>
          <div style={{ fontSize: "24px", fontWeight: "800", color: "#1877F2", marginTop: "8px" }}>
            {formatNumber(kpiStats.totalPoints)} <span style={{ fontSize: "14px" }}>điểm</span>
          </div>
          <div style={{ fontSize: "12px", color: "#666", marginTop: "4px" }}>
            Tích lũy từ doanh số F&B
          </div>
        </div>

        <div style={{ background: "#FFFFFF", borderRadius: "14px", padding: "18px 20px", border: "1px solid #E6DEC8" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <span style={{ fontSize: "13px", color: "#666", fontWeight: "600" }}>Giá Trị Quy Đổi Điểm</span>
            <div style={{ padding: "8px", background: "#E6F4EA", borderRadius: "10px", color: "#137333" }}>
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

        <div style={{ background: "#FFFFFF", borderRadius: "14px", padding: "18px 20px", border: "1px solid #E6DEC8" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <span style={{ fontSize: "13px", color: "#666", fontWeight: "600" }}>Tỷ Lệ Đổi Điểm Hiện Tại</span>
            <div style={{ padding: "8px", background: "#FDF5F6", borderRadius: "10px", color: "#7E2930" }}>
              <Sparkles size={18} />
            </div>
          </div>
          <div style={{ fontSize: "20px", fontWeight: "800", color: "#7E2930", marginTop: "8px" }}>
            1 điểm = {formatVND(pointRedeemRate)}
          </div>
          <div style={{ fontSize: "12px", color: "#666", marginTop: "4px" }}>
            Tích {pointEarnRate}% doanh số hóa đơn
          </div>
        </div>
      </div>

      {/* Filter and Search Bar */}
      <div
        style={{
          background: "#FFFFFF",
          borderRadius: "14px",
          border: "1px solid #E6DEC8",
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
              background: "#F8F4EE",
              padding: "8px 14px",
              borderRadius: "8px",
              border: "1px solid #E6DEC8",
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
                  border: active ? "1px solid #7E2930" : "1px solid #E6DEC8",
                  background: active ? "#7E2930" : "#FFFFFF",
                  color: active ? "#FFFFFF" : "#555",
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
          background: "#FFFFFF",
          borderRadius: "14px",
          border: "1px solid #E6DEC8",
          overflow: "hidden",
          boxShadow: "0 2px 8px rgba(0,0,0,0.02)",
        }}
      >
        <div style={{ overflowX: "auto" }}>
          <table style={{ width: "100%", borderCollapse: "collapse", fontSize: "13px" }}>
            <thead>
              <tr style={{ background: "#F8F4EE", borderBottom: "1px solid #E6DEC8", textAlign: "left", color: "#1C1A2D" }}>
                <th style={{ padding: "12px 14px", width: "50px", textAlign: "center" }}>STT</th>
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
                  <td colSpan={8} style={{ padding: "40px", textAlign: "center", color: "#888" }}>
                    Đang tải danh sách khách hàng KMT...
                  </td>
                </tr>
              ) : filteredCustomers.length === 0 ? (
                <tr>
                  <td colSpan={8} style={{ padding: "40px", textAlign: "center", color: "#888" }}>
                    Không tìm thấy khách hàng nào phù hợp
                  </td>
                </tr>
              ) : (
                filteredCustomers.map((c, idx) => {
                  const redeemVal = c.diemHienTai * pointRedeemRate;
                  return (
                    <tr
                      key={c.id || c.soDienThoai || idx}
                      style={{ borderBottom: "1px solid #F0ECE1" }}
                    >
                      <td style={{ padding: "12px 14px", textAlign: "center", color: "#888" }}>{idx + 1}</td>
                      <td style={{ padding: "12px 14px", fontWeight: "700", color: "#1C1A2D" }}>
                        {c.hoTen}
                      </td>
                      <td style={{ padding: "12px 14px" }}>
                        <span style={{ display: "inline-flex", alignItems: "center", gap: "4px" }}>
                          <Phone size={13} color="#7E2930" />
                          <strong>{c.soDienThoai || "—"}</strong>
                        </span>
                      </td>
                      <td style={{ padding: "12px 14px", color: "#666", fontFamily: "monospace" }}>
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
                                ? "#E8F0FE"
                                : c.hangThanhVien === "Vàng"
                                ? "#FEF7E0"
                                : c.hangThanhVien === "Bạc"
                                ? "#F1F3F4"
                                : "#F8F4EE",
                            color:
                              c.hangThanhVien === "Kim Cương"
                                ? "#1877F2"
                                : c.hangThanhVien === "Vàng"
                                ? "#B06000"
                                : c.hangThanhVien === "Bạc"
                                ? "#5F6368"
                                : "#7E2930",
                          }}
                        >
                          {c.hangThanhVien}
                        </span>
                      </td>
                      <td style={{ padding: "12px 14px", textAlign: "center", color: "#888", fontSize: "12px" }}>
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
              background: "#FFFFFF",
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
              <h2 style={{ fontSize: "17px", fontWeight: "800", color: "#1C1A2D", margin: 0 }}>
                Cấu hình Tỷ Lệ Đổi Điểm KMT CRM
              </h2>
            </div>
            <p style={{ fontSize: "13px", color: "#666", marginBottom: "16px" }}>
              Chủ quán thiết lập giá trị quy đổi 1 điểm sang VNĐ khi khách thanh toán bằng điểm tích luỹ. Điểm dùng sẽ được trừ trực tiếp vào hoá đơn dưới dạng chiết khấu/khuyến mãi (không tính vào doanh thu thuần).
            </p>

            {configSuccess && (
              <div
                style={{
                  padding: "10px 14px",
                  background: "#E6F4EA",
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
                <label style={{ fontSize: "13px", fontWeight: "700", color: "#1C1A2D", display: "block", marginBottom: "6px" }}>
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
                  <span style={{ fontSize: "14px", fontWeight: "700", color: "#7E2930" }}>VNĐ / Điểm</span>
                </div>
              </div>

              <div>
                <label style={{ fontSize: "13px", fontWeight: "700", color: "#1C1A2D", display: "block", marginBottom: "6px" }}>
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
                  <span style={{ fontSize: "14px", fontWeight: "700", color: "#7E2930" }}>% Hoá đơn</span>
                </div>
              </div>
            </div>

            <div style={{ display: "flex", justifyContent: "flex-end", gap: "10px", marginTop: "24px" }}>
              <button
                onClick={() => setShowConfigModal(false)}
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
                Hủy
              </button>
              <button
                onClick={handleSaveConfig}
                disabled={isSavingConfig}
                style={{
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
                {isSavingConfig ? "Đang lưu..." : "Lưu cấu hình"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
