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
  RefreshCw,
  Check,
  UserPlus,
  Award,
  History,
  Globe2,
} from "lucide-react";
import Link from "next/link";
import { useAuth, hasPermission } from "@/lib/auth";
import { useDashboardData } from "@/lib/data-context";
import { db } from "@/lib/firebase";
import { ref, onValue, update } from "firebase/database";
import { exportCustomersList, CustomerExportItem } from "@/lib/export";
import { formatVND, formatNumber } from "@/lib/reports";
import {
  StoreCustomer,
  canAdjustPoints,
  canEditPointConfig,
  canReadCustomers,
  parseStoreCustomers,
} from "@/lib/customers";
import {
  DEFAULT_LOYALTY_TIERS,
  LEDGER_TYPE_LABEL,
  buildNewCustomerNode,
  effectiveConfig,
  hasCustomTiers,
  parseChainConfig,
  parseLedgerEntries,
  totalsByMember,
  validateAdjustInput,
  validateTiers,
  type AdjustMode,
  type ChainLoyaltyConfig,
  type LedgerRow,
  type LoyaltyTier,
} from "@/lib/loyalty";
import { adjustLoyaltyPoints, getMemberLedger, setLoyaltyConfig } from "@/lib/loyalty-client";
import { searchCustomers } from "@/lib/customer-search";
import { errorMessage } from "@/lib/errors";
import CustomerFormDialog from "@/components/CustomerFormDialog";
import PointAdjustDialog from "@/components/PointAdjustDialog";
import LoyaltyTierDialog from "@/components/LoyaltyTierDialog";
import ModalShell, { btnGhost, btnPrimary, errorBox } from "@/components/ModalShell";

const DEFAULT_REDEEM_RATE = 1000;
const DEFAULT_EARN_RATE = 1.0;

export default function CustomersPage() {
  const { user } = useAuth();
  const { stores, currentStoreCode } = useDashboardData();

  // Dữ liệu khách theo từng chi nhánh: stores/{code}/customers (lắng nghe realtime)
  const [rawByStore, setRawByStore] = useState<Record<string, unknown>>({});
  const [loadedStores, setLoadedStores] = useState<Record<string, true>>({});
  const [deniedStores, setDeniedStores] = useState<string[]>([]);
  const [reloadKey, setReloadKey] = useState<number>(0);
  const [searchQuery, setSearchQuery] = useState<string>("");
  const [selectedTier, setSelectedTier] = useState<string>("ALL");

  const [showConfigModal, setShowConfigModal] = useState<boolean>(false);
  const [showCustomerForm, setShowCustomerForm] = useState(false);
  const [showTierDialog, setShowTierDialog] = useState(false);
  // Cấu hình điểm TOÀN CHUỖI (loyalty_config, Chủ đặt qua callable) — ưu tiên hơn cấu hình riêng chi nhánh
  const [chainConfig, setChainConfig] = useState<ChainLoyaltyConfig>({});
  // Lịch sử điểm dùng chung (xuyên chi nhánh) của một khách
  const [historyTarget, setHistoryTarget] = useState<StoreCustomer | null>(null);
  const [historyRows, setHistoryRows] = useState<LedgerRow[]>([]);
  const [historyLoading, setHistoryLoading] = useState(false);
  const [historyError, setHistoryError] = useState("");
  const [adjustTarget, setAdjustTarget] = useState<StoreCustomer | null>(null);
  const [opSaving, setOpSaving] = useState(false);
  const [opError, setOpError] = useState("");
  const [notice, setNotice] = useState<string | null>(null);
  const [editingRedeemRate, setEditingRedeemRate] = useState<string>(String(DEFAULT_REDEEM_RATE));
  const [editingEarnRate, setEditingEarnRate] = useState<string>(String(DEFAULT_EARN_RATE));
  const [isSavingConfig, setIsSavingConfig] = useState<boolean>(false);
  const [configSuccess, setConfigSuccess] = useState<string | null>(null);

  const canRead =
    canReadCustomers(user?.roleId || user?.role, user?.isRootOwner) &&
    (hasPermission(user, "VIEW_CUSTOMERS") || hasPermission(user, "VIEW_REPORTS"));
  // Rules: chỉ Chủ quán ghi storeInfo; cần chọn 1 chi nhánh cụ thể để lưu
  const canEditConfig =
    canEditPointConfig(user?.roleId || user?.role, user?.isRootOwner) && hasPermission(user, "MANAGE_LOYALTY") && currentStoreCode !== "ALL";
  const isOwner = canEditPointConfig(user?.roleId || user?.role, user?.isRootOwner) && hasPermission(user, "MANAGE_LOYALTY");
  // Rules: chỉ Chủ quán / Quản lý ghi trực tiếp số dư điểm
  const canAdjust = canAdjustPoints(user?.roleId || user?.role, user?.isRootOwner) && hasPermission(user, "ADJUST_POINTS");
  const canManageCustomers = hasPermission(user, "MANAGE_CUSTOMERS");
  const specificStore = currentStoreCode !== "ALL" && !!currentStoreCode;

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
      const eff = effectiveConfig(s, chainConfig);
      map[s.storeCode] = {
        redeem: typeof eff.pointRedeemRate === "number" && eff.pointRedeemRate > 0 ? eff.pointRedeemRate : DEFAULT_REDEEM_RATE,
        earn: typeof eff.pointEarnRate === "number" ? eff.pointEarnRate : DEFAULT_EARN_RATE,
      };
    });
    return map;
  }, [stores, chainConfig]);
  const tiersByStore = useMemo(() => {
    const map: Record<string, LoyaltyTier[]> = {};
    stores.forEach((s) => (map[s.storeCode] = effectiveConfig(s, chainConfig).loyaltyTiers));
    return map;
  }, [stores, chainConfig]);
  const tiersOf = useCallback((storeCode: string) => tiersByStore[storeCode] || DEFAULT_LOYALTY_TIERS, [tiersByStore]);
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
          setRawByStore((prev) => ({ ...prev, [code]: snap.val() }));
          setLoadedStores((prev) => (prev[code] ? prev : { ...prev, [code]: true }));
          setDeniedStores((prev) => (prev.includes(code) ? prev.filter((c) => c !== code) : prev));
        },
        (error) => {
          console.warn(`[customers] Không thể đọc stores/${code}/customers:`, error.message);
          setRawByStore((prev) => ({ ...prev, [code]: null }));
          setLoadedStores((prev) => (prev[code] ? prev : { ...prev, [code]: true }));
          setDeniedStores((prev) => (prev.includes(code) ? prev : [...prev, code]));
        }
      )
    );
    return () => unsubs.forEach((u) => u());
  }, [canRead, targetKey, reloadKey]);

  useEffect(() => {
    if (!canRead) return;
    return onValue(
      ref(db, "loyalty_config"),
      (snap) => setChainConfig(parseChainConfig(snap.val())),
      () => setChainConfig({})
    );
  }, [canRead]);

  const loading = canRead && targetCodes.some((c) => !loadedStores[c]);

  // Phân tích dữ liệu thô theo cấu hình hạng của từng chi nhánh
  const customers = useMemo(() => {
    const list: StoreCustomer[] = [];
    targetCodes.forEach((code) => list.push(...parseStoreCustomers(code, rawByStore[code], tiersByStore[code] || DEFAULT_LOYALTY_TIERS)));
    return list.sort((a, b) => b.diemHienTai - a.diemHienTai);
  }, [rawByStore, targetCodes, tiersByStore]);

  const tierNames = useMemo(() => {
    const names: string[] = [];
    targetCodes.forEach((code) => tiersOf(code).forEach((t) => !names.includes(t.name) && names.push(t.name)));
    return names;
  }, [targetCodes, tiersOf]);

  // Khách cùng SĐT ở nhiều chi nhánh là MỘT khách với một số dư: không cộng trùng
  const memberTotals = useMemo(() => totalsByMember(customers), [customers]);

  // Filtered customer list
  const filteredCustomers = useMemo(() => {
    const q = searchQuery.trim();
    const byTier = customers.filter((c) => selectedTier === "ALL" || c.hangThanhVien === selectedTier);
    if (!q) return byTier;
    // Khớp theo SĐT đủ/4 số cuối/một phần, tên không dấu thứ tự từ bất kỳ; thêm khớp mã khách
    const hits = searchCustomers(
      byTier.map((c) => ({ id: `${c.storeCode}:${c.id}`, name: c.hoTen, phone: c.soDienThoai, points: c.diemHienTai })),
      q,
      byTier.length
    ).map((m) => m.customer.id);
    const ql = q.toLowerCase();
    const set = new Set(hits);
    return [
      ...hits.map((id) => byTier.find((c) => `${c.storeCode}:${c.id}` === id)!),
      ...byTier.filter((c) => !set.has(`${c.storeCode}:${c.id}`) && c.maKhachHang.toLowerCase().includes(ql)),
    ];
  }, [customers, searchQuery, selectedTier]);

  // Aggregate KPI stats (giá trị quy đổi theo tỷ lệ của từng chi nhánh)
  const kpiStats = useMemo(() => {
    const totalCustomers = memberTotals.members;
    const totalPoints = memberTotals.points;
    const seen = new Set<string>();
    let totalPointValue = 0;
    for (const c of customers) {
      const key = c.soDienThoai ? `p:${c.soDienThoai.replace(/\D/g, "")}` : `${c.storeCode}:${c.id}`;
      if (seen.has(key)) continue;
      seen.add(key);
      totalPointValue += c.diemHienTai * (ratesByStore[c.storeCode]?.redeem ?? DEFAULT_REDEEM_RATE);
    }
    // "VIP" = khách ở hạng cao nhất của chi nhánh
    const vipCount = customers.filter((c) => {
      const t = tiersOf(c.storeCode);
      return t.length > 1 && c.hangThanhVien === t[t.length - 1].name;
    }).length;
    return { totalCustomers, totalPoints, totalPointValue, vipCount };
  }, [customers, memberTotals, ratesByStore, tiersOf]);

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
      // Tỷ lệ áp dụng TOÀN CHUỖI (loyalty_config) qua Cloud Function; chi nhánh nào chưa có thì dùng giá trị này
      await setLoyaltyConfig(currentStoreCode, { pointRedeemRate: newRedeem, pointEarnRate: newEarn });
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

  const tiers = ["ALL", ...tierNames];
  const showStoreColumn = currentStoreCode === "ALL";
  const columnCount = (showStoreColumn ? 9 : 8) + (canAdjust ? 1 : 0);

  const actor = {
    username: user?.username || "admin_web",
    fullName: user?.fullName,
    role: user?.roleId || user?.role,
  };

  const flash = (msg: string) => {
    setNotice(msg);
    setTimeout(() => setNotice(null), 3500);
  };

  const handleCreateCustomer = async (v: { name: string; phone: string; gender: string; birthday: string }) => {
    if (!specificStore) return;
    setOpSaving(true);
    setOpError("");
    try {
      const now = Date.now();
      const id = `CUST_${now}`;
      await update(ref(db), {
        [`stores/${currentStoreCode}/customers/${id}`]: buildNewCustomerNode(id, v, now),
        [`stores/${currentStoreCode}/audit_logs/log_${now}_cust`]: {
          timestamp: now,
          username: actor.username,
          userFullName: actor.fullName || actor.username,
          userRole: actor.role || "",
          action: "CUSTOMER_CREATE",
          targetType: "CUSTOMER",
          targetId: id,
          storeCode: currentStoreCode,
          details: `Tạo khách hàng ${v.name} (${v.phone}) qua Web Admin`,
        },
      });
      setShowCustomerForm(false);
      flash(`Đã thêm khách hàng ${v.name}`);
    } catch (e) {
      setOpError(errorMessage(e, "Không tạo được khách hàng"));
    } finally {
      setOpSaving(false);
    }
  };

  const handleAdjustPoints = async (mode: AdjustMode, value: number, reason: string) => {
    if (!adjustTarget) return;
    const err = validateAdjustInput({ mode, value, reason, balance: adjustTarget.diemHienTai });
    if (err) {
      setOpError(err);
      return;
    }
    setOpSaving(true);
    setOpError("");
    try {
      // Điểm là bản ghi dùng chung cả chuỗi: chỉnh qua Cloud Function (transaction + sổ cái + nhật ký)
      const res = await adjustLoyaltyPoints(
        adjustTarget.storeCode,
        { customerId: adjustTarget.id },
        mode,
        value,
        reason,
        `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`
      );
      flash(`Đã chỉnh điểm ${adjustTarget.hoTen}: ${adjustTarget.diemHienTai} → ${res.after ?? res.points ?? "?"}`);
      setAdjustTarget(null);
    } catch (e) {
      setOpError(errorMessage(e, "Không chỉnh được điểm"));
    } finally {
      setOpSaving(false);
    }
  };

  const openHistory = async (c: StoreCustomer) => {
    setHistoryTarget(c);
    setHistoryRows([]);
    setHistoryError("");
    setHistoryLoading(true);
    try {
      const res = await getMemberLedger(c.storeCode, { customerId: c.id }, 100);
      setHistoryRows(parseLedgerEntries(res.entries));
    } catch (e) {
      setHistoryError(errorMessage(e, "Không tải được lịch sử điểm"));
    } finally {
      setHistoryLoading(false);
    }
  };

  const handleSaveTiers = async (next: LoyaltyTier[]) => {
    const err = validateTiers(next);
    if (err) return alert(err);
    setOpSaving(true);
    try {
      // Mốc hạng áp dụng cho TOÀN CHUỖI (chỉ Chủ quán, qua Cloud Function)
      await setLoyaltyConfig(currentStoreCode, { loyaltyTiers: next });
      setShowTierDialog(false);
      flash("Đã lưu mốc hạng toàn chuỗi");
    } catch (e) {
      alert(errorMessage(e, "Không lưu được cấu hình hạng"));
    } finally {
      setOpSaving(false);
    }
  };

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
            <button
              onClick={() => {
                setOpError("");
                setShowCustomerForm(true);
              }}
              disabled={!specificStore || !canRead || !canManageCustomers}
              title={!canManageCustomers ? "Bạn không có quyền thêm khách hàng" : specificStore ? "Thêm khách hàng mới" : "Chọn 1 chi nhánh cụ thể để thêm khách"}
              style={{
                display: "flex", alignItems: "center", gap: "6px", padding: "8px 14px", background: "var(--primary)", color: "#FFFFFF",
                border: "none", borderRadius: "8px", fontSize: "13px", fontWeight: "600",
                cursor: specificStore ? "pointer" : "not-allowed", opacity: specificStore ? 1 : 0.5,
              }}
            >
              <UserPlus size={15} /> Thêm khách hàng
            </button>
            <Link
              href="/dashboard/reports/loyalty"
              style={{
                display: "flex", alignItems: "center", gap: "6px", padding: "8px 14px", background: "var(--bg)",
                border: "1px solid var(--border)", borderRadius: "8px", fontSize: "13px", fontWeight: "600", color: "var(--primary)",
              }}
            >
              <History size={15} /> Lịch sử điểm
            </Link>
            {canEditConfig && (
              <button
                onClick={() => setShowTierDialog(true)}
                style={{
                  display: "flex", alignItems: "center", gap: "6px", padding: "8px 14px", background: "var(--bg)",
                  border: "1px solid var(--border)", borderRadius: "8px", fontSize: "13px", fontWeight: "600", color: "var(--primary)", cursor: "pointer",
                }}
              >
                <Award size={15} /> Điểm theo hạng
              </button>
            )}
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

      {notice && (
        <div style={{ background: "var(--success-bg)", color: "#137333", borderRadius: 12, padding: "10px 14px", fontSize: 13, fontWeight: 600, marginBottom: 16 }}>
          <Check size={14} style={{ verticalAlign: "-2px" }} /> {notice}
        </div>
      )}

      {isOwner && specificStore && !hasCustomTiers(tiersOf(currentStoreCode)) && (
        <div style={{ background: "#FEF7E0", color: "#8A5B00", borderRadius: 12, padding: "10px 14px", fontSize: 13, marginBottom: 16, display: "flex", justifyContent: "space-between", gap: 12, flexWrap: "wrap", alignItems: "center" }}>
          <span>Chưa đặt mốc hạng thành viên (Bạc, Vàng, ...). Tất cả khách đang ở hạng gốc.</span>
          <button style={btnPrimary} onClick={() => setShowTierDialog(true)}>Đặt mốc hạng</button>
        </div>
      )}

      {stores.length > 1 && (
        <div
          style={{
            background: "var(--surface)", border: "1px solid var(--border)", borderRadius: 12, padding: "12px 16px", marginBottom: 16,
            display: "flex", alignItems: "center", gap: 10,
          }}
        >
          <Globe2 size={18} color="var(--primary)" />
          <div>
            <div style={{ fontSize: 13, fontWeight: 700 }}>Điểm dùng chung toàn chuỗi (luôn bật)</div>
            <div style={{ fontSize: 12, color: "var(--subtext)" }}>
              Khách được nhận diện theo số điện thoại: một số dư và một lịch sử cho mọi chi nhánh
              {memberTotals.duplicateNodes > 0 ? ` (${memberTotals.duplicateNodes} hồ sơ trùng SĐT đã được gộp điểm)` : ""}. Tỷ lệ tích/đổi và mốc hạng do Chủ quán đặt cho cả chuỗi.
            </div>
          </div>
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
            {kpiStats.vipCount} khách hạng cao nhất
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
                {canAdjust && <th style={{ padding: "12px 14px", textAlign: "center" }}>Thao tác</th>}
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
                      {canAdjust && (
                        <td style={{ padding: "8px 14px", textAlign: "center", whiteSpace: "nowrap" }}>
                          <button
                            onClick={() => {
                              setOpError("");
                              setAdjustTarget(c);
                            }}
                            style={{ padding: "5px 10px", borderRadius: 6, border: "1px solid var(--border)", background: "var(--bg)", color: "var(--primary)", fontSize: 12, fontWeight: 600, cursor: "pointer", marginRight: 6 }}
                          >
                            Sửa điểm
                          </button>
                          <button
                            onClick={() => openHistory(c)}
                            style={{ padding: "5px 10px", borderRadius: 6, border: "1px solid var(--border)", background: "var(--bg)", color: "var(--primary)", fontSize: 12, fontWeight: 600, cursor: "pointer", marginRight: 6 }}
                          >
                            Lịch sử
                          </button>
                          <Link
                            href={`/dashboard/reports/loyalty?store=${encodeURIComponent(c.storeCode)}&customer=${encodeURIComponent(c.id)}`}
                            style={{ fontSize: 11, color: "var(--subtext)" }}
                            title="Sổ cũ trước khi gộp điểm chi nhánh"
                          >
                            Sổ cũ
                          </Link>
                        </td>
                      )}
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
      </div>

      {showCustomerForm && specificStore && (
        <CustomerFormDialog
          storeCode={currentStoreCode}
          existing={customers.filter((c) => c.storeCode === currentStoreCode)}
          saving={opSaving}
          error={opError}
          onCancel={() => setShowCustomerForm(false)}
          onSave={handleCreateCustomer}
        />
      )}
      {adjustTarget && (
        <PointAdjustDialog
          customer={adjustTarget}
          saving={opSaving}
          error={opError}
          onCancel={() => setAdjustTarget(null)}
          onSave={handleAdjustPoints}
        />
      )}
      {showTierDialog && canEditConfig && (
        <LoyaltyTierDialog
          storeCode={currentStoreCode}
          tiers={tiersOf(currentStoreCode)}
          saving={opSaving}
          onCancel={() => setShowTierDialog(false)}
          onSave={handleSaveTiers}
        />
      )}
      {historyTarget && (
        <ModalShell
          title="Lịch sử điểm dùng chung"
          subtitle={`${historyTarget.hoTen} • ${historyTarget.soDienThoai || historyTarget.maKhachHang} • mọi chi nhánh`}
          icon={<History size={18} color="var(--primary)" />}
          onClose={() => setHistoryTarget(null)}
          footer={<button style={btnGhost} onClick={() => setHistoryTarget(null)}>Đóng</button>}
        >
          {historyError && <div style={errorBox}>{historyError}</div>}
          {historyLoading ? (
            <p style={{ fontSize: 13, color: "var(--subtext)" }}>Đang tải...</p>
          ) : historyRows.length === 0 && !historyError ? (
            <p style={{ fontSize: 13, color: "var(--subtext)" }}>Chưa có biến động điểm nào.</p>
          ) : (
            <div style={{ overflowX: "auto" }}>
              <table style={{ width: "100%", fontSize: 12, borderCollapse: "collapse" }}>
                <thead>
                  <tr style={{ textAlign: "left", color: "var(--subtext)" }}>
                    <th style={{ padding: "4px 8px" }}>Thời gian</th>
                    <th style={{ padding: "4px 8px" }}>Cửa hàng</th>
                    <th style={{ padding: "4px 8px" }}>Nghiệp vụ</th>
                    <th style={{ padding: "4px 8px", textAlign: "right" }}>Điểm</th>
                    <th style={{ padding: "4px 8px", textAlign: "right" }}>Số dư sau</th>
                    <th style={{ padding: "4px 8px" }}>Ghi chú</th>
                  </tr>
                </thead>
                <tbody>
                  {historyRows.map((r) => (
                    <tr key={r.id} style={{ borderTop: "1px solid var(--border)" }}>
                      <td style={{ padding: "4px 8px", whiteSpace: "nowrap" }}>{r.at ? new Date(r.at).toLocaleString("vi-VN") : "—"}</td>
                      <td style={{ padding: "4px 8px" }}>
                        <div style={{ fontWeight: 600 }}>{(r.storeCode && stores.find((st) => st.storeCode === r.storeCode)?.storeName) || r.storeCode || "—"}</div>
                        {r.storeCode ? <div style={{ fontSize: 11, color: "var(--subtext)", fontFamily: "monospace" }}>{r.storeCode}</div> : null}
                      </td>
                      <td style={{ padding: "4px 8px" }}>{LEDGER_TYPE_LABEL[r.type]}</td>
                      <td style={{ padding: "4px 8px", textAlign: "right", fontWeight: 700, color: r.points < 0 ? "var(--danger, #B3261E)" : "#137333" }}>
                        {r.points > 0 ? "+" : ""}{formatNumber(r.points)}
                      </td>
                      <td style={{ padding: "4px 8px", textAlign: "right" }}>{formatNumber(r.balanceAfter)}</td>
                      <td style={{ padding: "4px 8px", color: "var(--subtext)" }}>{[r.billId && `HĐ ${r.billId}`, r.note, r.staff && `bởi ${r.staff}`].filter(Boolean).join(" • ")}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </ModalShell>
      )}

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
