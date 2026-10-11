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
import { useAuth } from "@/lib/auth";
import { useDashboardData } from "@/lib/data-context";
import { db } from "@/lib/firebase";
import { ref, onValue, update, get } from "firebase/database";
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
  buildNewCustomerNode,
  buildPointAdjustment,
  DEDUCT_ORDER_LABEL,
  buildPooledRedeemUpdates,
  buildSharedLoyaltyUpdates,
  hasCustomTiers,
  planPooledRedeem,
  poolCustomersByPhone,
  type DeductOrder,
  type PooledCustomer,
  validateTiers,
  type AdjustMode,
  type LoyaltyTier,
} from "@/lib/loyalty";
import { errorMessage } from "@/lib/errors";
import CustomerFormDialog from "@/components/CustomerFormDialog";
import PointAdjustDialog from "@/components/PointAdjustDialog";
import LoyaltyTierDialog from "@/components/LoyaltyTierDialog";
import ModalShell, { btnGhost, btnPrimary, errorBox, fieldInput, fieldLabel } from "@/components/ModalShell";

const DEFAULT_REDEEM_RATE = 1000;
const DEFAULT_EARN_RATE = 1.0;

export default function CustomersPage() {
  const { user } = useAuth();
  const { stores, currentStoreCode, updateStore } = useDashboardData();

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
  const [showPoolDialog, setShowPoolDialog] = useState(false);
  const [poolDeductOrder, setPoolDeductOrder] = useState<DeductOrder>("HOME_FIRST");
  const [redeemTarget, setRedeemTarget] = useState<PooledCustomer | null>(null);
  const [redeemPoints, setRedeemPoints] = useState("");
  const [redeemReason, setRedeemReason] = useState("");
  const [adjustTarget, setAdjustTarget] = useState<StoreCustomer | null>(null);
  const [opSaving, setOpSaving] = useState(false);
  const [opError, setOpError] = useState("");
  const [notice, setNotice] = useState<string | null>(null);
  const [editingRedeemRate, setEditingRedeemRate] = useState<string>(String(DEFAULT_REDEEM_RATE));
  const [editingEarnRate, setEditingEarnRate] = useState<string>(String(DEFAULT_EARN_RATE));
  const [isSavingConfig, setIsSavingConfig] = useState<boolean>(false);
  const [configSuccess, setConfigSuccess] = useState<string | null>(null);

  const canRead = canReadCustomers(user?.roleId || user?.role, user?.isRootOwner);
  // Rules: chỉ Chủ quán ghi storeInfo; cần chọn 1 chi nhánh cụ thể để lưu
  const canEditConfig = canEditPointConfig(user?.roleId || user?.role, user?.isRootOwner) && currentStoreCode !== "ALL";
  const isOwner = canEditPointConfig(user?.roleId || user?.role, user?.isRootOwner);
  // Rules: chỉ Chủ quán / Quản lý ghi trực tiếp số dư điểm
  const canAdjust = canAdjustPoints(user?.roleId || user?.role, user?.isRootOwner);
  const specificStore = currentStoreCode !== "ALL" && !!currentStoreCode;
  const sharedEnabled = stores.some((s) => s.sharedLoyalty?.enabled);

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
  const tiersByStore = useMemo(() => {
    const map: Record<string, LoyaltyTier[]> = {};
    stores.forEach((s) => (map[s.storeCode] = s.loyaltyTiers || DEFAULT_LOYALTY_TIERS));
    return map;
  }, [stores]);
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

  const pooled = useMemo(() => (sharedEnabled ? poolCustomersByPhone(customers) : []), [sharedEnabled, customers]);

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
    // "VIP" = khách ở hạng cao nhất của chi nhánh
    const vipCount = customers.filter((c) => {
      const t = tiersOf(c.storeCode);
      return t.length > 1 && c.hangThanhVien === t[t.length - 1].name;
    }).length;
    return { totalCustomers, totalPoints, totalPointValue, vipCount };
  }, [customers, ratesByStore, tiersOf]);

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
    const res = buildPointAdjustment({
      storeCode: adjustTarget.storeCode,
      customer: adjustTarget,
      mode,
      value,
      reason,
      actor,
      tiers: tiersOf(adjustTarget.storeCode),
      now: Date.now(),
    });
    if (!res.ok) {
      setOpError(res.error);
      return;
    }
    setOpSaving(true);
    setOpError("");
    try {
      await update(ref(db), res.updates);
      flash(`Đã chỉnh điểm ${adjustTarget.hoTen}: ${adjustTarget.diemHienTai} → ${res.after}`);
      setAdjustTarget(null);
    } catch (e) {
      setOpError(errorMessage(e, "Không chỉnh được điểm"));
    } finally {
      setOpSaving(false);
    }
  };

  const handleSaveTiers = async (next: LoyaltyTier[], applyAll: boolean) => {
    const err = validateTiers(next);
    if (err) return alert(err);
    setOpSaving(true);
    let res: { success: boolean; error?: string };
    if (applyAll) {
      try {
        const now = Date.now();
        const updates: Record<string, unknown> = {};
        for (const s of stores) {
          updates[`stores/${s.storeCode}/storeInfo/loyaltyTiers`] = next;
          updates[`stores/${s.storeCode}/audit_logs/log_${now}_tier_${s.storeCode}`] = {
            timestamp: now, username: actor.username, userFullName: actor.fullName || actor.username, userRole: actor.role || "",
            action: "LOYALTY_TIERS_UPDATE", targetType: "STORE", targetId: s.storeCode, storeCode: s.storeCode,
            details: `Chủ quán đặt mốc hạng: ${next.map((t) => `${t.name} ≥ ${t.minPoints}`).join("; ")}`,
          };
        }
        await update(ref(db), updates);
        res = { success: true };
      } catch (e) {
        res = { success: false, error: errorMessage(e, "Không lưu được cho tất cả chi nhánh") };
      }
    } else {
      res = await updateStore(currentStoreCode, { loyaltyTiers: next });
    }
    setOpSaving(false);
    if (!res.success) return alert(res.error || "Không lưu được cấu hình hạng");
    setShowTierDialog(false);
    flash("Đã lưu cấu hình điểm theo hạng");
  };

  const openRedeem = (p: PooledCustomer) => {
    setOpError("");
    setRedeemPoints("");
    setRedeemReason("");
    setRedeemTarget(p);
  };

  const poolOrder: DeductOrder = stores.find((s) => s.sharedLoyalty?.enabled)?.sharedLoyalty?.deductOrder || "HOME_FIRST";

  const redeemPreview = useMemo(() => {
    if (!redeemTarget) return null;
    const n = Number(redeemPoints);
    if (!Number.isInteger(n) || n <= 0) return null;
    return planPooledRedeem({
      holdings: redeemTarget.perStore.map((x) => ({ storeCode: x.storeCode, customerId: x.customerId, points: x.points })),
      points: n,
      homeStore: user?.storeCode,
      order: poolOrder,
    });
  }, [redeemTarget, redeemPoints, user?.storeCode, poolOrder]);

  const handlePoolRedeem = async () => {
    if (!redeemTarget) return;
    const n = Number(redeemPoints);
    setOpSaving(true);
    setOpError("");
    try {
      // Đọc lại số dư thật ở từng chi nhánh ngay trước khi ghi (POS có thể vừa đổi/tích điểm)
      const fresh = await Promise.all(
        redeemTarget.perStore.map(async (x) => {
          const snap = await get(ref(db, `stores/${x.storeCode}/customers/${x.customerId}`));
          const v = (snap.val() || {}) as Record<string, unknown>;
          const pts = Number(v.diem_hien_tai ?? v.currentPoints ?? 0);
          return { storeCode: x.storeCode, customerId: x.customerId, points: Number.isFinite(pts) ? Math.max(0, Math.trunc(pts)) : 0 };
        })
      );
      const plan = planPooledRedeem({ holdings: fresh, points: n, homeStore: user?.storeCode, order: poolOrder });
      if ("error" in plan) throw new Error(plan.error);
      const built = buildPooledRedeemUpdates({
        allocations: plan.allocations, customerName: redeemTarget.hoTen, phone: redeemTarget.phone,
        reason: redeemReason, actor, now: Date.now(),
      });
      if ("error" in built) throw new Error(built.error);
      await update(ref(db), built.updates);
      flash(`Đã trừ ${n} điểm dùng chung của ${redeemTarget.hoTen} tại ${plan.allocations.length} chi nhánh`);
      setRedeemTarget(null);
    } catch (e) {
      setOpError(errorMessage(e, "Không trừ được điểm dùng chung"));
    } finally {
      setOpSaving(false);
    }
  };

  const handleTogglePool = async (enabled: boolean) => {
    setOpSaving(true);
    setOpError("");
    try {
      await update(
        ref(db),
        buildSharedLoyaltyUpdates({ storeCodes: stores.map((s) => s.storeCode), enabled, deductOrder: poolDeductOrder, actor, now: Date.now() })
      );
      setShowPoolDialog(false);
      flash(enabled ? "Chủ quán đã xác nhận dùng chung điểm toàn hệ thống" : "Đã tắt dùng chung điểm");
    } catch (e) {
      setOpError(errorMessage(e, "Không lưu được cấu hình dùng chung"));
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
              disabled={!specificStore || !canRead}
              title={specificStore ? "Thêm khách hàng mới" : "Chọn 1 chi nhánh cụ thể để thêm khách"}
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

      {stores.length > 1 && (isOwner || sharedEnabled) && (
        <div
          style={{
            background: "var(--surface)", border: "1px solid var(--border)", borderRadius: 12, padding: "12px 16px", marginBottom: 16,
            display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12, flexWrap: "wrap",
          }}
        >
          <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
            <Globe2 size={18} color="var(--primary)" />
            <div>
              <div style={{ fontSize: 13, fontWeight: 700 }}>
                Điểm dùng chung toàn hệ thống: {sharedEnabled ? "ĐÃ BẬT" : "đang tắt"}
              </div>
              <div style={{ fontSize: 12, color: "var(--subtext)" }}>
                {sharedEnabled
                  ? `Chủ quán ${stores.find((s) => s.sharedLoyalty?.enabled)?.sharedLoyalty?.confirmedBy || ""} đã xác nhận. Khách được gộp theo SĐT ở chế độ "Tất cả chi nhánh" (${pooled.length} khách).`
                  : "Gộp điểm của khách theo số điện thoại giữa các chi nhánh. Cần Chủ quán bấm xác nhận."}
              </div>
            </div>
          </div>
          {isOwner && (
            <button style={btnPrimary} onClick={() => { setOpError(""); setShowPoolDialog(true); }}>
              {sharedEnabled ? "Tắt dùng chung" : "Xác nhận bật dùng chung"}
            </button>
          )}
        </div>
      )}

      {sharedEnabled && currentStoreCode === "ALL" && pooled.length > 0 && (
        <div style={{ background: "var(--surface)", border: "1px solid var(--border)", borderRadius: 12, padding: "12px 16px", marginBottom: 16, overflowX: "auto" }}>
          <div style={{ fontSize: 13, fontWeight: 700, marginBottom: 8 }}>Điểm toàn hệ thống theo số điện thoại (top 10) — thứ tự trừ: {DEDUCT_ORDER_LABEL[poolOrder]}</div>
          <table style={{ width: "100%", fontSize: 12, borderCollapse: "collapse" }}>
            <thead>
              <tr style={{ textAlign: "left", color: "var(--subtext)" }}>
                <th style={{ padding: "4px 8px" }}>SĐT</th>
                <th style={{ padding: "4px 8px" }}>Khách</th>
                <th style={{ padding: "4px 8px", textAlign: "right" }}>Tổng điểm hiện có</th>
                <th style={{ padding: "4px 8px" }}>Theo chi nhánh</th>
                {canAdjust && <th style={{ padding: "4px 8px" }} />}
              </tr>
            </thead>
            <tbody>
              {pooled.slice(0, 10).map((p) => (
                <tr key={p.phone} style={{ borderTop: "1px solid var(--border)" }}>
                  <td style={{ padding: "4px 8px", fontFamily: "monospace" }}>{p.phone}</td>
                  <td style={{ padding: "4px 8px" }}>{p.hoTen}</td>
                  <td style={{ padding: "4px 8px", textAlign: "right", fontWeight: 700 }}>{formatNumber(p.totalCurrent)}</td>
                  <td style={{ padding: "4px 8px", color: "var(--subtext)" }}>{p.perStore.map((x) => `${x.storeCode}: ${x.points}`).join(" • ")}</td>
                  {canAdjust && (
                    <td style={{ padding: "4px 8px", textAlign: "right" }}>
                      <button
                        onClick={() => openRedeem(p)}
                        disabled={p.totalCurrent <= 0}
                        style={{ padding: "4px 10px", borderRadius: 6, border: "1px solid var(--border)", background: "var(--bg)", color: "var(--primary)", fontSize: 12, fontWeight: 600, cursor: "pointer" }}
                      >
                        Trừ điểm
                      </button>
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
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
                          <Link
                            href={`/dashboard/reports/loyalty?store=${encodeURIComponent(c.storeCode)}&customer=${encodeURIComponent(c.id)}`}
                            style={{ fontSize: 12, fontWeight: 600, color: "var(--primary)" }}
                          >
                            Lịch sử
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
          storeCount={stores.length}
          onCancel={() => setShowTierDialog(false)}
          onSave={handleSaveTiers}
        />
      )}
      {showPoolDialog && (
        <ModalShell
          title={sharedEnabled ? "Tắt dùng chung điểm?" : "Xác nhận dùng chung điểm toàn hệ thống"}
          icon={<Globe2 size={18} color="var(--primary)" />}
          onClose={() => setShowPoolDialog(false)}
          footer={
            <>
              <button style={btnGhost} onClick={() => setShowPoolDialog(false)}>Hủy</button>
              <button style={btnPrimary} disabled={opSaving} onClick={() => handleTogglePool(!sharedEnabled)}>
                {opSaving ? "Đang lưu..." : sharedEnabled ? "Tắt" : "Chủ quán xác nhận"}
              </button>
            </>
          }
        >
          <p style={{ fontSize: 13, color: "var(--text)", margin: 0 }}>
            {sharedEnabled
              ? "Điểm của từng chi nhánh sẽ không còn được gộp theo số điện thoại."
              : `Điểm của cùng một số điện thoại ở ${stores.length} chi nhánh sẽ được tính là một nguồn điểm chung. Thao tác này được ghi vào Nhật ký kiểm soát với tên của bạn.`}
          </p>
          {!sharedEnabled && (
            <div style={{ marginTop: 12 }}>
              <label style={fieldLabel}>Khi trừ điểm dùng chung</label>
              <select style={fieldInput} value={poolDeductOrder} onChange={(e) => setPoolDeductOrder(e.target.value as DeductOrder)}>
                {(Object.keys(DEDUCT_ORDER_LABEL) as DeductOrder[]).map((k) => (
                  <option key={k} value={k}>{DEDUCT_ORDER_LABEL[k]}</option>
                ))}
              </select>
            </div>
          )}
          {opError && <p style={{ color: "var(--danger, #B3261E)", fontSize: 13 }}>{opError}</p>}
        </ModalShell>
      )}

      {redeemTarget && (
        <ModalShell
          title="Trừ điểm dùng chung"
          subtitle={`${redeemTarget.hoTen} • ${redeemTarget.phone} • còn ${redeemTarget.totalCurrent} điểm toàn hệ thống`}
          icon={<Coins size={18} color="var(--primary)" />}
          onClose={() => setRedeemTarget(null)}
          footer={
            <>
              <button style={btnGhost} onClick={() => setRedeemTarget(null)}>Hủy</button>
              <button
                style={{ ...btnPrimary, opacity: opSaving || !redeemPreview || "error" in redeemPreview ? 0.6 : 1 }}
                disabled={opSaving || !redeemPreview || "error" in redeemPreview || !redeemReason.trim()}
                onClick={handlePoolRedeem}
              >
                {opSaving ? "Đang trừ..." : "Xác nhận trừ điểm"}
              </button>
            </>
          }
        >
          {opError && <div style={errorBox}>{opError}</div>}
          <label style={fieldLabel}>Số điểm cần trừ</label>
          <input style={fieldInput} type="number" min={1} step={1} value={redeemPoints} onChange={(e) => setRedeemPoints(e.target.value)} autoFocus />
          <label style={{ ...fieldLabel, marginTop: 12 }}>Mã hóa đơn / lý do *</label>
          <input style={fieldInput} value={redeemReason} onChange={(e) => setRedeemReason(e.target.value)} placeholder="VD: HD-261011-0007" />
          {redeemPreview && (
            <div style={{ marginTop: 12, fontSize: 13 }}>
              {"error" in redeemPreview ? (
                <span style={{ color: "var(--danger, #B3261E)" }}>{redeemPreview.error}</span>
              ) : (
                <>
                  <div style={{ fontWeight: 700, marginBottom: 4 }}>Sẽ trừ:</div>
                  {redeemPreview.allocations.map((a) => (
                    <div key={a.storeCode}>
                      {a.storeCode}: −{a.take} ({a.before} → {a.after})
                    </div>
                  ))}
                </>
              )}
            </div>
          )}
          <p style={{ fontSize: 12, color: "var(--subtext)", marginTop: 12 }}>Thứ tự trừ: {DEDUCT_ORDER_LABEL[poolOrder]}. Tổng điểm tích lũy (hạng) không bị giảm.</p>
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
