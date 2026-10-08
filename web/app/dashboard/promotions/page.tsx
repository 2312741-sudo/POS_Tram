"use client";
import { useState, useMemo, useEffect, useCallback } from "react";
import { Search, Plus, Tag, Ticket, ChevronRight, Settings } from "lucide-react";
import { ref, onValue, set, push, remove, update } from "firebase/database";
import { db } from "@/lib/firebase";
import { useDashboardData } from "@/lib/data-context";
import { errorMessage } from "@/lib/errors";

function formatVND(amount: number | undefined) {
  if (amount === undefined) return "—";
  return new Intl.NumberFormat("vi-VN", { style: "currency", currency: "VND" }).format(amount);
}

function formatDate(ts: number | undefined) {
  if (!ts) return "—";
  const d = new Date(ts);
  return d.toLocaleDateString("vi-VN", { day: "2-digit", month: "2-digit", year: "numeric" });
}

// ==================== TYPES ====================
// Bậc ưu đãi của chiến dịch (đồng bộ với Flutter PromotionModel)
interface CampaignTier {
  tierId?: string;
  tierIndex?: number;
  threshold?: number;
  thresholdValue?: number;
  thresholdType?: string;
  conditionBasis?: string;
  benefitType?: string;
  benefitMode?: string;
  benefitValue?: number;
  value?: number;
  maxBenefitValue?: number;
  maxDiscountMoney?: number;
  sortOrder?: number;
  [key: string]: unknown;
}

interface CampaignItem {
  campaignId: string;
  programCode: string;
  name: string;
  description: string;
  campaignType: string;
  active: boolean;
  schedule: {
    absoluteStart?: number;
    absoluteEnd?: number;
    timeSlots?: { startTime: string; endTime: string }[];
    daysOfWeek?: number[];
  };
  branchIds: string[];
  includedCustomerIds?: string[];
  excludedCustomerIds?: string[];
  includedItemIds?: string[];
  includedGroupIds?: string[];
  excludedItemIds?: string[];
  tiers: CampaignTier[];
  buyConditions: Record<string, unknown>[];
  budgetMoney?: number;
  maxUses?: number;
  maxUsesPerCustomer?: number;
  hasCodes: boolean;
  autoApply: boolean;
  requireStaffNote?: boolean;
  stackingMode: string;
  priority: number;
  createdAt: number;
  updatedAt: number;
  createdBy: string;
}

interface CampaignCounters {
  spentMoney: number;
  committedUseCount: number;
}

interface VoucherItem {
  voucherId: string;
  campaignId: string;
  code: string;
  status: string; // ISSUED, USED, CANCELLED
  usedBy?: string;
  usedAt?: number;
}

const typeLabels: Record<string, string> = {
  BILLDISCOUNT: 'Giảm giá đơn hàng',
  ORDERVALUEITEMBENEFIT: 'Giảm/tặng món theo GTĐ',
  BUYXGETY: 'Mua X tặng Y',
  ITEMPRICERULE: 'Đồng giá/đồng giảm giá',
};

// ==================== MAIN COMPONENT ====================
export default function PromotionsPage() {
  const { stores, currentStoreCode, setCurrentStoreCode, products = [], categories = [] } = useDashboardData();
  const [activeTab, setActiveTab] = useState<"campaigns" | "vouchers">("campaigns");
  const [search, setSearch] = useState("");
  const [filterStatus, setFilterStatus] = useState("ALL");
  const [filterType, setFilterType] = useState("");

  const [selectedVoucherCampaign, setSelectedVoucherCampaign] = useState("");

  // Firebase data state
  const [campaigns, setCampaigns] = useState<CampaignItem[]>([]);
  const [countersMap, setCountersMap] = useState<Record<string, CampaignCounters>>({});
  // Danh sách voucher kèm campaignId đã nạp — danh sách hiển thị được suy ra bên dưới
  const [voucherState, setVoucherState] = useState<{ campaignId: string; list: VoucherItem[] } | null>(null);
  // Mã chi nhánh đã nạp xong campaigns — loading được suy ra, không setState đồng bộ trong effect
  const [loadedStoreCode, setLoadedStoreCode] = useState<string | null>(null);
  // Mốc thời gian hiện tại cho trạng thái chiến dịch (không gọi Date.now() khi render), làm mới mỗi phút
  const [nowTs, setNowTs] = useState(() => Date.now());

  // Modal state for add/edit campaign
  const [showCampaignModal, setShowCampaignModal] = useState(false);
  const [editingCampaign, setEditingCampaign] = useState<CampaignItem | null>(null);
  
  // Modal for vouchers
  const [showVoucherModal, setShowVoucherModal] = useState(false);

  const [saving, setSaving] = useState(false);
  const [formError, setFormError] = useState("");

  // Campaign form state
  const [campaignForm, setCampaignForm] = useState({
    name: "", programCode: "", description: "", campaignType: "BILLDISCOUNT",
    active: true, startDate: "", endDate: "", budgetMoney: "", maxUses: "",
    hasCodes: false, autoApply: true, requireStaffNote: false, stackingMode: "STACKABLE", priority: "0",
    discountThreshold: "", discountType: "PERCENT" as "PERCENT" | "AMOUNT", discountValue: "", maxDiscount: "",
    fixedPriceValue: "",
    includedItemIds: [] as string[],
    includedGroupIds: [] as string[],
    daysOfWeek: [] as number[],
    timeSlots: [] as { startTime: string; endTime: string }[]
  });

  // Voucher form state
  const [voucherForm, setVoucherForm] = useState({ quantity: "10", prefix: "", customCode: "", isCustom: false });

  // Ở chế độ "ALL" dùng chi nhánh đầu tiên thực tế (không hardcode TRAM01)
  const targetStoreCode = currentStoreCode === "ALL" ? (stores[0]?.storeCode || "") : currentStoreCode;
  const loading = !!targetStoreCode && loadedStoreCode !== targetStoreCode;

  useEffect(() => {
    const timer = setInterval(() => setNowTs(Date.now()), 60_000);
    return () => clearInterval(timer);
  }, []);

  // Load data from Firebase
  useEffect(() => {
    if (!targetStoreCode) return;
    const unsubs: (() => void)[] = [];

    // Campaigns
    const camRef = ref(db, `stores/${targetStoreCode}/campaigns`);
    unsubs.push(onValue(camRef, (snap) => {
      const cams: CampaignItem[] = [];
      snap.forEach((child) => {
        const v = child.val();
        cams.push({
          campaignId: child.key!, programCode: v.programCode || "", name: v.name || "",
          description: v.description || "", campaignType: v.campaignType || "BILLDISCOUNT",
          active: v.active ?? false, schedule: v.schedule || {}, branchIds: v.branchIds || [],
          includedItemIds: v.includedItemIds || [], includedGroupIds: v.includedGroupIds || [],
          requireStaffNote: v.requireStaffNote ?? false,
          tiers: v.tiers || [], buyConditions: v.buyConditions || [], budgetMoney: v.budgetMoney || 0,
          maxUses: v.maxUses || 0, maxUsesPerCustomer: v.maxUsesPerCustomer || 0, hasCodes: v.hasCodes ?? false,
          autoApply: v.autoApply ?? false, stackingMode: v.stackingMode || "STACKABLE", priority: v.priority || 0,
          createdAt: v.createdAt || 0, updatedAt: v.updatedAt || 0, createdBy: v.createdBy || ""
        });
      });
      setCampaigns(cams.sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0)));
      setLoadedStoreCode(targetStoreCode);
    }));

    // Counters
    const countersRef = ref(db, `stores/${targetStoreCode}/campaign_counters`);
    unsubs.push(onValue(countersRef, (snap) => {
      const map: Record<string, CampaignCounters> = {};
      snap.forEach((child) => {
        const v = child.val();
        map[child.key!] = { spentMoney: v.spentMoney || 0, committedUseCount: v.committedUseCount || 0 };
      });
      setCountersMap(map);
    }));

    return () => unsubs.forEach((u) => u());
  }, [targetStoreCode]);

  useEffect(() => {
    if (activeTab === "vouchers" && selectedVoucherCampaign) {
      const vRef = ref(db, `stores/${targetStoreCode}/vouchers/${selectedVoucherCampaign}`);
      const unsub = onValue(vRef, (snap) => {
        const vs: VoucherItem[] = [];
        snap.forEach((child) => {
          const val = child.val();
          vs.push({
            voucherId: child.key!, campaignId: selectedVoucherCampaign,
            code: val.code || val.normalizedCode || "",
            status: val.status || (val.state === "REDEEMED" ? "USED" : val.state === "CANCELLED" ? "CANCELLED" : "ISSUED"),
            usedBy: val.usedBy || val.redeemedBy,
            usedAt: val.usedAt || val.redeemedAt
          });
        });
        setVoucherState({ campaignId: selectedVoucherCampaign, list: vs });
      });
      return () => unsub();
    }
  }, [activeTab, selectedVoucherCampaign, targetStoreCode]);

  const vouchers = useMemo<VoucherItem[]>(() => {
    if (activeTab !== "vouchers" || !selectedVoucherCampaign) return [];
    return voucherState?.campaignId === selectedVoucherCampaign ? voucherState.list : [];
  }, [activeTab, selectedVoucherCampaign, voucherState]);

  const getCampaignStatus = useCallback((cam: CampaignItem) => {
    if (!cam.active) return "Tạm dừng";
    const now = nowTs;
    const start = cam.schedule?.absoluteStart || 0;
    const end = cam.schedule?.absoluteEnd || 0;
    if (end > 0 && now > end) return "Đã kết thúc";
    if (start > 0 && now < start) return "Sắp tới";

    // Kiểm tra ngày trong tuần (1..7: 1 = T2, 7 = CN)
    if (cam.schedule?.daysOfWeek && cam.schedule.daysOfWeek.length > 0) {
      const d = new Date(now);
      const day = d.getDay() === 0 ? 7 : d.getDay();
      if (!cam.schedule.daysOfWeek.includes(day)) {
        return "Ngoài khung giờ";
      }
    }

    // Kiểm tra khung giờ Happy Hours
    if (cam.schedule?.timeSlots && cam.schedule.timeSlots.length > 0) {
      const d = new Date(now);
      const curMinutes = d.getHours() * 60 + d.getMinutes();
      let inSlot = false;
      for (const slot of cam.schedule.timeSlots) {
        if (!slot.startTime || !slot.endTime) continue;
        const [sh, sm] = slot.startTime.split(":").map(Number);
        const [eh, em] = slot.endTime.split(":").map(Number);
        const startMin = (sh || 0) * 60 + (sm || 0);
        const endMin = (eh || 0) * 60 + (em || 0);
        if (startMin <= endMin) {
          if (curMinutes >= startMin && curMinutes <= endMin) {
            inSlot = true;
            break;
          }
        } else {
          // Ca qua đêm e.g. 22:00 -> 02:00
          if (curMinutes >= startMin || curMinutes <= endMin) {
            inSlot = true;
            break;
          }
        }
      }
      if (!inSlot) {
        return "Ngoài khung giờ";
      }
    }

    return "Đang chạy";
  }, [nowTs]);

  const getStatusColor = (status: string) => {
    switch (status) {
      case "Đang chạy": return "#10b981";
      case "Sắp tới": return "#3b82f6";
      case "Đã kết thúc": return "#9ca3af";
      case "Tạm dừng": return "#f59e0b";
      case "Ngoài khung giờ": return "#8b5cf6";
      default: return "#999";
    }
  };

  // Filtered campaigns
  const filteredCampaigns = useMemo(() => campaigns.filter((c) => {
    const matchSearch = !search || c.name.toLowerCase().includes(search.toLowerCase()) || c.programCode.toLowerCase().includes(search.toLowerCase());
    const matchType = !filterType || c.campaignType === filterType;
    const status = getCampaignStatus(c);
    const matchStatus = filterStatus === "ALL" || status === filterStatus;
    return matchSearch && matchType && matchStatus;
  }), [campaigns, search, filterType, filterStatus, getCampaignStatus]);

  // Vouchers stats
  const voucherStats = useMemo(() => {
    const total = vouchers.length;
    let issued = 0, used = 0, cancelled = 0;
    vouchers.forEach(v => {
      if (v.status === "ISSUED") issued++;
      else if (v.status === "USED") used++;
      else if (v.status === "CANCELLED") cancelled++;
    });
    return { total, issued, used, cancelled };
  }, [vouchers]);

  // Handle Save Campaign
  const handleSaveCampaign = async () => {
    if (!campaignForm.name.trim()) { setFormError("Tên chương trình là bắt buộc"); return; }
    
    if (campaignForm.campaignType === "BILLDISCOUNT") {
      const val = Number(campaignForm.discountValue) || 0;
      if (campaignForm.discountType === "PERCENT") {
        if (val <= 0 || val > 100) {
          setFormError("Tỷ lệ giảm giá (%) phải từ 1 đến 100");
          return;
        }
      } else {
        if (val <= 0) {
          setFormError("Số tiền giảm (VND) phải lớn hơn 0");
          return;
        }
      }
    }

    setSaving(true); setFormError("");
    try {
      const now = Date.now();
      const campaignId = editingCampaign?.campaignId || `CAM_${now}_${Math.random().toString(36).slice(2, 6)}`;
      const programCode = editingCampaign?.programCode || campaignForm.programCode.trim() || `KM${String(campaigns.length + 1).padStart(4, "0")}`;
      
      let tiers: CampaignTier[] = editingCampaign?.tiers ? [...editingCampaign.tiers] : [];
      if (campaignForm.campaignType === "BILLDISCOUNT") {
        const isPercent = campaignForm.discountType === "PERCENT";
        const val = Number(campaignForm.discountValue) || 0;
        const threshold = Number(campaignForm.discountThreshold) || 0;
        const maxDisc = Number(campaignForm.maxDiscount) || 0;
        tiers = [{
          tierId: editingCampaign?.tiers?.[0]?.tierId || "TIER_1",
          tierIndex: 0,
          threshold,
          thresholdValue: threshold,
          thresholdType: "ORDER_VALUE",
          conditionBasis: "TOTALAMOUNT",
          benefitType: isPercent ? "DISCOUNT_PERCENT" : "DISCOUNT_AMOUNT",
          benefitMode: isPercent ? "PERCENT" : "FIXED",
          benefitValue: val,
          value: isPercent ? Math.round(val * 100) : val,
          maxBenefitValue: isPercent ? maxDisc : 0,
          maxDiscountMoney: isPercent ? maxDisc : 0,
          sortOrder: 1
        }];
      } else if (campaignForm.campaignType === "ITEMPRICERULE") {
        const fixedVal = Number(campaignForm.fixedPriceValue) || 0;
        tiers = [{
          tierId: editingCampaign?.tiers?.[0]?.tierId || "TIER_1",
          tierIndex: 0,
          threshold: 0,
          thresholdValue: 0,
          thresholdType: "ORDER_VALUE",
          conditionBasis: "TOTALAMOUNT",
          benefitType: "FIXED_PRICE",
          benefitMode: "FIXEDPRICE",
          benefitValue: fixedVal,
          value: fixedVal,
          maxBenefitValue: 0,
          maxDiscountMoney: 0,
          sortOrder: 1
        }];
      }

      const schedule: NonNullable<CampaignItem["schedule"]> = {};
      if (campaignForm.startDate) schedule.absoluteStart = new Date(campaignForm.startDate).getTime();
      if (campaignForm.endDate) schedule.absoluteEnd = new Date(campaignForm.endDate).getTime();
      if (campaignForm.daysOfWeek.length > 0) schedule.daysOfWeek = campaignForm.daysOfWeek;
      if (campaignForm.timeSlots.length > 0) schedule.timeSlots = campaignForm.timeSlots;

      const data = {
        campaignId,
        programCode,
        name: campaignForm.name.trim(),
        description: campaignForm.description.trim(),
        campaignType: campaignForm.campaignType,
        active: campaignForm.active,
        schedule,
        branchIds: editingCampaign?.branchIds?.length ? editingCampaign.branchIds : [targetStoreCode],
        includedItemIds: campaignForm.includedItemIds,
        includedGroupIds: campaignForm.includedGroupIds,
        tiers,
        buyConditions: editingCampaign?.buyConditions || [],
        budgetMoney: Number(campaignForm.budgetMoney) || 0,
        maxUses: Number(campaignForm.maxUses) || 0,
        hasCodes: campaignForm.hasCodes,
        autoApply: campaignForm.autoApply,
        requireStaffNote: campaignForm.requireStaffNote,
        stackingMode: campaignForm.stackingMode,
        priority: Number(campaignForm.priority) || 0,
        createdAt: editingCampaign?.createdAt || now,
        updatedAt: now,
        createdBy: editingCampaign?.createdBy || "Admin"
      };

      await set(ref(db, `stores/${targetStoreCode}/campaigns/${campaignId}`), data);
      setShowCampaignModal(false);
      setEditingCampaign(null);
    } catch (e) {
      setFormError(errorMessage(e) || "Lỗi lưu KM");
    }
    setSaving(false);
  };

  const handleGenerateVouchers = async () => {
    if (!selectedVoucherCampaign) { setFormError("Vui lòng chọn chương trình"); return; }
    setSaving(true); setFormError("");
    try {
      const now = Date.now();
      const updates: Record<string, unknown> = {};

      if (voucherForm.isCustom) {
        const cleanCode = voucherForm.customCode.trim().toUpperCase();
        if (!cleanCode) {
          setFormError("Vui lòng nhập mã Voucher cụ thể");
          setSaving(false);
          return;
        }
        const vId = `VOU_${now}_${Math.random().toString(36).slice(2, 8).toUpperCase()}`;
        const vData = {
          voucherId: vId,
          campaignId: selectedVoucherCampaign,
          code: cleanCode,
          normalizedCode: cleanCode,
          status: "ISSUED",
          state: "RELEASED",
          tombstone: false,
          createdAt: now,
          version: 1,
        };
        updates[`vouchers/${selectedVoucherCampaign}/${vId}`] = vData;
        updates[`voucher_lookup/${cleanCode}`] = {
          campaignId: selectedVoucherCampaign,
          voucherId: vId,
        };
      } else {
        const qty = parseInt(voucherForm.quantity);
        if (isNaN(qty) || qty <= 0) { setFormError("Số lượng không hợp lệ (tối thiểu 1)"); setSaving(false); return; }
        const prefix = voucherForm.prefix.trim().toUpperCase();

        for (let i = 0; i < qty; i++) {
          const vId = `VOU_${now}_${Math.random().toString(36).slice(2, 8).toUpperCase()}_${i}`;
          const code = `${prefix}${Math.random().toString(36).slice(2, 8).toUpperCase()}`;
          const vData = {
            voucherId: vId,
            campaignId: selectedVoucherCampaign,
            code,
            normalizedCode: code,
            status: "ISSUED",
            state: "RELEASED",
            tombstone: false,
            createdAt: now,
            version: 1,
          };
          updates[`vouchers/${selectedVoucherCampaign}/${vId}`] = vData;
          updates[`voucher_lookup/${code}`] = {
            campaignId: selectedVoucherCampaign,
            voucherId: vId,
          };
        }
      }

      // Đánh dấu chương trình này có phát hành mã (hasCodes = true)
      updates[`campaigns/${selectedVoucherCampaign}/hasCodes`] = true;
      updates[`campaigns/${selectedVoucherCampaign}/updatedAt`] = now;

      await update(ref(db, `stores/${targetStoreCode}`), updates);
      setShowVoucherModal(false);
    } catch (e) { setFormError(errorMessage(e) || "Lỗi tạo mã"); }
    setSaving(false);
  };

  const openEditCampaign = (cam: CampaignItem) => {
    setEditingCampaign(cam);
    const startStr = cam.schedule?.absoluteStart ? new Date(cam.schedule.absoluteStart).toISOString().slice(0, 16) : "";
    const endStr = cam.schedule?.absoluteEnd ? new Date(cam.schedule.absoluteEnd).toISOString().slice(0, 16) : "";
    
    let discountThreshold = "";
    let discountType: "PERCENT" | "AMOUNT" = "PERCENT";
    let discountValue = "";
    let maxDiscount = "";
    let fixedPriceValue = "";

    if (cam.tiers && cam.tiers.length > 0) {
      const tier = cam.tiers[0];
      const isPercent = tier.benefitMode === "PERCENT" || tier.benefitType === "DISCOUNT_PERCENT" || tier.benefitType === "PERCENT";
      discountType = isPercent ? "PERCENT" : "AMOUNT";
      const rawVal = tier.value ?? tier.benefitValue ?? 0;
      const val = isPercent ? (rawVal > 100 ? rawVal / 100 : rawVal) : rawVal;
      discountValue = val > 0 ? String(val) : "";
      discountThreshold = String(tier.threshold ?? tier.thresholdValue ?? "");
      maxDiscount = String(tier.maxDiscountMoney ?? tier.maxBenefitValue ?? "");
      fixedPriceValue = String(rawVal > 0 ? rawVal : "");
    }

    setCampaignForm({
      name: cam.name,
      programCode: cam.programCode,
      description: cam.description || "",
      campaignType: cam.campaignType || "BILLDISCOUNT",
      active: cam.active,
      startDate: startStr,
      endDate: endStr,
      budgetMoney: String(cam.budgetMoney || ""),
      maxUses: String(cam.maxUses || ""),
      hasCodes: cam.hasCodes ?? false,
      autoApply: cam.autoApply ?? true,
      requireStaffNote: cam.requireStaffNote ?? false,
      stackingMode: cam.stackingMode || "STACKABLE",
      priority: String(cam.priority || 0),
      discountThreshold,
      discountType,
      discountValue,
      maxDiscount,
      fixedPriceValue,
      includedItemIds: Array.isArray(cam.includedItemIds) ? [...cam.includedItemIds] : [],
      includedGroupIds: Array.isArray(cam.includedGroupIds) ? [...cam.includedGroupIds] : [],
      daysOfWeek: Array.isArray(cam.schedule?.daysOfWeek) ? [...cam.schedule.daysOfWeek] : [],
      timeSlots: Array.isArray(cam.schedule?.timeSlots) ? [...cam.schedule.timeSlots] : []
    });
    setFormError("");
    setShowCampaignModal(true);
  };

  const openAddCampaign = () => {
    setEditingCampaign(null);
    setCampaignForm({
      name: "",
      programCode: "",
      description: "",
      campaignType: "BILLDISCOUNT",
      active: true,
      startDate: "",
      endDate: "",
      budgetMoney: "",
      maxUses: "",
      hasCodes: false,
      autoApply: true,
      requireStaffNote: false,
      stackingMode: "STACKABLE",
      priority: "0",
      discountThreshold: "",
      discountType: "PERCENT",
      discountValue: "",
      maxDiscount: "",
      fixedPriceValue: "",
      includedItemIds: [],
      includedGroupIds: [],
      daysOfWeek: [],
      timeSlots: []
    });
    setFormError("");
    setShowCampaignModal(true);
  };

  const toggleCampaignActive = async (cam: CampaignItem) => {
    await update(ref(db, `stores/${targetStoreCode}/campaigns/${cam.campaignId}`), { active: !cam.active, updatedAt: Date.now() });
  };

  const tabs = [
    { key: "campaigns" as const, label: "Chương trình KM", icon: Tag, count: campaigns.length },
    { key: "vouchers" as const, label: "Mã Voucher", icon: Ticket, count: 0 },
  ];

  // Chưa có chi nhánh hợp lệ -> không đọc/ghi mặc định vào chi nhánh khác
  if (!targetStoreCode) {
    return (
      <div style={{ padding: "24px", color: "#666" }}>Chưa xác định được chi nhánh. Vui lòng chọn một chi nhánh cụ thể.</div>
    );
  }

  return (
    <div style={{ padding: "24px" }}>
      {/* Header */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "24px" }}>
        <div>
          <h1 style={{ fontSize: "24px", fontWeight: "800", color: "#1a1a2e", margin: 0 }}>
            🎉 Quản lý Khuyến mãi
          </h1>
          <p style={{ fontSize: "14px", color: "#666", margin: "4px 0 0" }}>
            Tạo và quản lý các chương trình khuyến mãi, voucher
          </p>
        </div>
        <div style={{ display: "flex", gap: "8px" }}>
          {activeTab === "campaigns" && (
            <button onClick={openAddCampaign} style={btnPrimary}>
              <Plus size={16} /> Thêm KM
            </button>
          )}
        </div>
      </div>

      {/* Store Selector */}
      {stores.length > 1 && (
        <div style={{ marginBottom: "16px", display: "flex", gap: "8px", flexWrap: "wrap" }}>
          {stores.filter((s) => s.active !== false).map((s) => (
            <button key={s.storeCode} onClick={() => setCurrentStoreCode(s.storeCode)}
              style={{
                padding: "6px 14px", borderRadius: "8px", fontSize: "13px", fontWeight: "600", cursor: "pointer",
                border: targetStoreCode === s.storeCode ? "2px solid #7E2930" : "1px solid #ddd",
                background: targetStoreCode === s.storeCode ? "#7E2930" : "#fff",
                color: targetStoreCode === s.storeCode ? "#fff" : "#333",
              }}>
              {s.storeName || s.storeCode}
            </button>
          ))}
        </div>
      )}

      {/* Tabs */}
      <div style={{ display: "flex", gap: "4px", marginBottom: "20px", borderBottom: "2px solid #f0f0f0", paddingBottom: "0" }}>
        {tabs.map((tab) => {
          const Icon = tab.icon;
          const isActive = activeTab === tab.key;
          return (
            <button key={tab.key} onClick={() => { setActiveTab(tab.key); setSearch(""); }}
              style={{
                display: "flex", alignItems: "center", gap: "6px", padding: "10px 16px",
                fontSize: "13px", fontWeight: isActive ? "700" : "500", cursor: "pointer",
                border: "none", borderBottom: isActive ? "3px solid #7E2930" : "3px solid transparent",
                background: "transparent", color: isActive ? "#7E2930" : "#666", marginBottom: "-2px",
              }}>
              <Icon size={16} />
              {tab.label}
              {tab.key === "campaigns" && (
                <span style={{
                  background: isActive ? "#7E2930" : "#e5e7eb", color: isActive ? "#fff" : "#666",
                  fontSize: "11px", fontWeight: "700", padding: "1px 6px", borderRadius: "10px",
                }}>
                  {tab.count}
                </span>
              )}
            </button>
          );
        })}
      </div>

      {/* Content */}
      {loading ? (
        <div style={{ textAlign: "center", padding: "60px", color: "#999" }}>⏳ Đang tải dữ liệu...</div>
      ) : (
        <>
          {activeTab === "campaigns" && (
            <div>
              {/* Search & Filters */}
              <div style={{ display: "flex", gap: "12px", marginBottom: "16px", alignItems: "center", flexWrap: "wrap" }}>
                <div style={{ display: "flex", gap: "8px", overflowX: "auto" }}>
                  {["ALL", "Đang chạy", "Sắp tới", "Đã kết thúc", "Tạm dừng", "Ngoài khung giờ"].map(st => (
                    <button key={st} onClick={() => setFilterStatus(st)} style={{
                      padding: "6px 12px", borderRadius: "20px", fontSize: "13px", fontWeight: "600", cursor: "pointer", border: "none",
                      background: filterStatus === st ? "#7E2930" : "#f1f1f1", color: filterStatus === st ? "#fff" : "#333", whiteSpace: "nowrap"
                    }}>
                      {st === "ALL" ? "Tất cả" : st}
                    </button>
                  ))}
                </div>
                <div style={{ flex: 1, position: "relative", minWidth: "200px" }}>
                  <Search size={16} style={{ position: "absolute", left: "12px", top: "50%", transform: "translateY(-50%)", color: "#999" }} />
                  <input value={search} onChange={(e) => setSearch(e.target.value)}
                    placeholder="Tìm theo tên, mã KM..."
                    style={{ width: "100%", padding: "10px 12px 10px 36px", borderRadius: "8px", border: "1px solid #ddd", fontSize: "14px" }} />
                </div>
                <select value={filterType} onChange={(e) => setFilterType(e.target.value)}
                  style={{ padding: "10px 12px", borderRadius: "8px", border: "1px solid #ddd", fontSize: "13px", minWidth: "160px" }}>
                  <option value="">Tất cả loại KM</option>
                  {Object.entries(typeLabels).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                </select>
              </div>

              {filteredCampaigns.length === 0 ? (
                <EmptyState icon="🎁" text="Chưa có chương trình khuyến mãi" sub="Bấm 'Thêm KM' để tạo mới." />
              ) : (
                <div style={{ borderRadius: "12px", border: "1px solid #e5e7eb", overflow: "hidden" }}>
                  <table style={{ width: "100%", borderCollapse: "collapse" }}>
                    <thead>
                      <tr style={{ background: "#f9fafb" }}>
                        {["Mã KM", "Tên chương trình", "Loại & Giảm giá", "Thời gian & Khung giờ", "Ngân sách", "Lượt dùng", "Trạng thái", "Thao tác"].map((h) => (
                          <th key={h} style={thStyle}>{h}</th>
                        ))}
                      </tr>
                    </thead>
                    <tbody>
                      {filteredCampaigns.map((cam) => {
                        const status = getCampaignStatus(cam);
                        const cColor = getStatusColor(status);
                        const counters = countersMap[cam.campaignId] || { spentMoney: 0, committedUseCount: 0 };
                        const budgetProgress = cam.budgetMoney ? (counters.spentMoney / cam.budgetMoney) * 100 : 0;
                        const tier = cam.tiers?.[0];
                        const isPercent = tier?.benefitMode === "PERCENT" || tier?.benefitType === "DISCOUNT_PERCENT" || tier?.benefitType === "PERCENT";
                        const tierVal = tier?.value ?? tier?.benefitValue ?? 0;
                        const displayVal = isPercent ? (tierVal > 100 ? tierVal / 100 : tierVal) : tierVal;

                        return (
                          <tr key={cam.campaignId} style={{ borderBottom: "1px solid #f0f0f0" }}>
                            <td style={tdStyle} onClick={() => openEditCampaign(cam)}>
                              <span style={{ fontFamily: "monospace", fontSize: "12px", color: "#7E2930", fontWeight: "600", cursor: "pointer" }}>{cam.programCode}</span>
                            </td>
                            <td style={{ ...tdStyle, cursor: "pointer" }} onClick={() => openEditCampaign(cam)}>
                              <div style={{ fontWeight: "600", fontSize: "14px", color: "#111827", marginBottom: "4px" }}>{cam.name}</div>
                              <div style={{ display: "flex", flexWrap: "wrap", gap: "4px" }}>
                                {cam.requireStaffNote && (
                                  <span style={badgeStyle("#d97706")}>📝 Ghi chú NV</span>
                                )}
                                {cam.includedItemIds && cam.includedItemIds.length > 0 && (
                                  <span style={badgeStyle("#2563eb")}>📦 {cam.includedItemIds.length} món</span>
                                )}
                                {cam.includedGroupIds && cam.includedGroupIds.length > 0 && (
                                  <span style={badgeStyle("#0891b2")}>📁 {cam.includedGroupIds.length} nhóm</span>
                                )}
                              </div>
                            </td>
                            <td style={tdStyle}>
                              <div style={{ display: "flex", flexDirection: "column", gap: "2px" }}>
                                <span style={badgeStyle("#8b5cf6")}>{typeLabels[cam.campaignType] || cam.campaignType}</span>
                                {displayVal > 0 && (
                                  <span style={{ fontSize: "12px", fontWeight: "700", color: "#b91c1c" }}>
                                    {isPercent ? `Giảm ${displayVal}%` : `Giảm ${formatVND(displayVal)}`}
                                  </span>
                                )}
                              </div>
                            </td>
                            <td style={tdStyle}>
                              <div style={{ fontSize: "12px", display: "flex", flexDirection: "column", gap: "2px" }}>
                                {cam.schedule.absoluteStart || cam.schedule.absoluteEnd ? (
                                  <div>
                                    {formatDate(cam.schedule.absoluteStart)} - {formatDate(cam.schedule.absoluteEnd)}
                                  </div>
                                ) : <div style={{ color: "#6b7280" }}>Không giới hạn ngày</div>}

                                {cam.schedule.daysOfWeek && cam.schedule.daysOfWeek.length > 0 && (
                                  <div style={{ color: "#15803d", fontWeight: "600" }}>
                                    📅 {cam.schedule.daysOfWeek.length === 7 ? "Mỗi ngày" : cam.schedule.daysOfWeek.map(d => d === 7 ? "CN" : `T${d + 1}`).join(", ")}
                                  </div>
                                )}

                                {cam.schedule.timeSlots && cam.schedule.timeSlots.length > 0 && (
                                  <div style={{ color: "#7c3aed", fontWeight: "600" }}>
                                    ⏰ {cam.schedule.timeSlots.map(s => `${s.startTime}-${s.endTime}`).join(", ")}
                                  </div>
                                )}
                              </div>
                            </td>
                            <td style={tdStyle}>
                              {cam.budgetMoney ? (
                                <div>
                                  <div style={{ fontSize: "12px", marginBottom: "4px" }}>{formatVND(counters.spentMoney)} / {formatVND(cam.budgetMoney)}</div>
                                  <div style={{ width: "100%", height: "4px", background: "#e5e7eb", borderRadius: "2px", overflow: "hidden" }}>
                                    <div style={{ width: `${Math.min(budgetProgress, 100)}%`, height: "100%", background: budgetProgress > 90 ? "#ef4444" : "#10b981" }} />
                                  </div>
                                </div>
                              ) : "—"}
                            </td>
                            <td style={{ ...tdStyle, textAlign: "right" }}>{counters.committedUseCount} {cam.maxUses ? `/ ${cam.maxUses}` : ""}</td>
                            <td style={tdStyle}><span style={badgeStyle(cColor)}>{status}</span></td>
                            <td style={tdStyle}>
                              <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
                                <label style={{ display: "flex", alignItems: "center", cursor: "pointer" }} title="Bật/Tắt chương trình">
                                  <input type="checkbox" checked={cam.active} onChange={() => toggleCampaignActive(cam)} style={{ display: "none" }} />
                                  <div style={{ width: "36px", height: "20px", background: cam.active ? "#10b981" : "#d1d5db", borderRadius: "10px", position: "relative", transition: "0.2s" }}>
                                    <div style={{ width: "16px", height: "16px", background: "#fff", borderRadius: "50%", position: "absolute", top: "2px", left: cam.active ? "18px" : "2px", transition: "0.2s" }} />
                                  </div>
                                </label>
                                <button
                                  onClick={(e) => {
                                    e.stopPropagation();
                                    setSelectedVoucherCampaign(cam.campaignId);
                                    setActiveTab("vouchers");
                                  }}
                                  style={{
                                    display: "flex",
                                    alignItems: "center",
                                    gap: "4px",
                                    padding: "5px 10px",
                                    borderRadius: "6px",
                                    fontSize: "12px",
                                    fontWeight: "600",
                                    background: "#f3f4f6",
                                    color: "#374151",
                                    border: "1px solid #d1d5db",
                                    cursor: "pointer",
                                  }}
                                  title="Quản lý mã Voucher"
                                >
                                  <Ticket size={13} /> Mã KM
                                </button>
                              </div>
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          )}

          {activeTab === "vouchers" && (
            <div>
              <div style={{ display: "flex", gap: "12px", marginBottom: "16px", alignItems: "center" }}>
                <select value={selectedVoucherCampaign} onChange={(e) => setSelectedVoucherCampaign(e.target.value)}
                  style={{ padding: "10px 12px", borderRadius: "8px", border: "1px solid #ddd", fontSize: "14px", flex: 1, fontWeight: "600" }}>
                  <option value="">-- Chọn chương trình khuyến mãi để quản lý mã --</option>
                  {campaigns.map(c => (
                    <option key={c.campaignId} value={c.campaignId}>{c.programCode} - {c.name} {c.hasCodes ? "(Đã có mã)" : ""}</option>
                  ))}
                </select>
                <button onClick={() => {
                  setVoucherForm({ quantity: "10", prefix: "", customCode: "", isCustom: false });
                  setFormError(""); setShowVoucherModal(true);
                }} style={btnPrimary} disabled={!selectedVoucherCampaign}>
                  <Plus size={16} /> Tạo mã voucher
                </button>
              </div>

              {selectedVoucherCampaign ? (
                <>
                  <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: "16px", marginBottom: "20px" }}>
                    <div style={{ background: "#f8fafc", padding: "16px", borderRadius: "12px", border: "1px solid #e2e8f0" }}>
                      <div style={{ fontSize: "13px", color: "#64748b", fontWeight: "600" }}>Tổng mã</div>
                      <div style={{ fontSize: "24px", fontWeight: "800", color: "#0f172a" }}>{voucherStats.total}</div>
                    </div>
                    <div style={{ background: "#f0fdf4", padding: "16px", borderRadius: "12px", border: "1px solid #bbf7d0" }}>
                      <div style={{ fontSize: "13px", color: "#166534", fontWeight: "600" }}>Đã phát hành</div>
                      <div style={{ fontSize: "24px", fontWeight: "800", color: "#15803d" }}>{voucherStats.issued}</div>
                    </div>
                    <div style={{ background: "#fffbeb", padding: "16px", borderRadius: "12px", border: "1px solid #fef08a" }}>
                      <div style={{ fontSize: "13px", color: "#854d0e", fontWeight: "600" }}>Đã dùng</div>
                      <div style={{ fontSize: "24px", fontWeight: "800", color: "#a16207" }}>{voucherStats.used}</div>
                    </div>
                    <div style={{ background: "#fef2f2", padding: "16px", borderRadius: "12px", border: "1px solid #fecaca" }}>
                      <div style={{ fontSize: "13px", color: "#991b1b", fontWeight: "600" }}>Đã hủy</div>
                      <div style={{ fontSize: "24px", fontWeight: "800", color: "#b91c1c" }}>{voucherStats.cancelled}</div>
                    </div>
                  </div>

                  <div style={{ borderRadius: "12px", border: "1px solid #e5e7eb", overflow: "hidden" }}>
                    <table style={{ width: "100%", borderCollapse: "collapse" }}>
                      <thead>
                        <tr style={{ background: "#f9fafb" }}>
                          {["Mã Voucher", "Trạng thái", "Người dùng", "Ngày dùng", "Thao tác"].map((h) => (
                            <th key={h} style={thStyle}>{h}</th>
                          ))}
                        </tr>
                      </thead>
                      <tbody>
                        {vouchers.map(v => (
                          <tr key={v.voucherId} style={{ borderBottom: "1px solid #f0f0f0" }}>
                            <td style={tdStyle}><span style={{ fontFamily: "monospace", fontSize: "14px", fontWeight: "700", letterSpacing: "1px", color: "#7E2930" }}>{v.code}</span></td>
                            <td style={tdStyle}>
                              <span style={badgeStyle(v.status === "ISSUED" ? "#10b981" : v.status === "USED" ? "#f59e0b" : "#94a3b8")}>
                                {v.status === "ISSUED" ? "Đã phát hành" : v.status === "USED" ? "Đã dùng" : "Đã hủy"}
                              </span>
                            </td>
                            <td style={tdStyle}>{v.usedBy || "—"}</td>
                            <td style={tdStyle}>{v.usedAt ? formatDate(v.usedAt) : "—"}</td>
                            <td style={tdStyle}>
                              {v.status === "ISSUED" && (
                                <button onClick={async () => {
                                  await update(ref(db, `stores/${targetStoreCode}/vouchers/${selectedVoucherCampaign}/${v.voucherId}`), { status: "CANCELLED" });
                                }} style={{ padding: "4px 8px", fontSize: "12px", borderRadius: "4px", background: "#fee2e2", color: "#ef4444", border: "none", cursor: "pointer" }}>Hủy</button>
                              )}
                            </td>
                          </tr>
                        ))}
                        {vouchers.length === 0 && (
                          <tr><td colSpan={5} style={{ textAlign: "center", padding: "24px", color: "#999" }}>Chưa có mã voucher nào.</td></tr>
                        )}
                      </tbody>
                    </table>
                  </div>
                </>
              ) : (
                <EmptyState icon="🎫" text="Chọn chương trình" sub="Vui lòng chọn chương trình khuyến mãi có phát hành mã để xem chi tiết." />
              )}
            </div>
          )}
        </>
      )}

      {/* Add/Edit Campaign Modal */}
      {showCampaignModal && (
        <Modal title={editingCampaign ? "Sửa chương trình khuyến mãi" : "Thêm chương trình KM"} onClose={() => setShowCampaignModal(false)}>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "12px", maxHeight: "72vh", overflowY: "auto", paddingRight: "8px" }}>
            <div style={{ gridColumn: "1 / -1" }}>
              <FormField label="Tên chương trình *" value={campaignForm.name} onChange={(v) => setCampaignForm({ ...campaignForm, name: v })} placeholder="VD: Khuyến mãi Trà Sữa Giờ Vàng" />
            </div>
            <FormField label="Mã KM (tự động nếu để trống)" value={campaignForm.programCode} onChange={(v) => setCampaignForm({ ...campaignForm, programCode: v })} disabled={!!editingCampaign} placeholder="VD: KM0001" />
            <div>
              <label style={labelStyle}>Loại KM</label>
              <select value={campaignForm.campaignType} onChange={(e) => setCampaignForm({ ...campaignForm, campaignType: e.target.value })} style={inputStyle} disabled={!!editingCampaign}>
                {Object.entries(typeLabels).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
              </select>
            </div>
            
            {/* 1. Cấu hình Ưu đãi & Giảm giá */}
            <div style={{ gridColumn: "1 / -1", borderTop: "1px solid #eee", paddingTop: "12px", marginTop: "4px" }}>
              <div style={{ fontSize: "14px", fontWeight: "700", marginBottom: "8px", color: "#7E2930" }}>🎁 Cấu hình Ưu đãi & Giảm giá</div>
              {campaignForm.campaignType === "BILLDISCOUNT" && (
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "12px", background: "#fcf8f8", padding: "12px", borderRadius: "8px", border: "1px solid #fecdd3" }}>
                  <div>
                    <label style={labelStyle}>Hình thức giảm *</label>
                    <select value={campaignForm.discountType} onChange={(e) => setCampaignForm({ ...campaignForm, discountType: e.target.value as "PERCENT" | "AMOUNT" })} style={inputStyle}>
                      <option value="PERCENT">Giảm theo % (Phần trăm)</option>
                      <option value="AMOUNT">Giảm theo Số tiền (VND)</option>
                    </select>
                  </div>
                  <FormField
                    label={campaignForm.discountType === "PERCENT" ? "Tỷ lệ giảm (%) *" : "Số tiền giảm (VND) *"}
                    value={campaignForm.discountValue}
                    onChange={(v) => setCampaignForm({ ...campaignForm, discountValue: v })}
                    type="number"
                    placeholder={campaignForm.discountType === "PERCENT" ? "1 - 100" : "VD: 20000"}
                  />
                  {campaignForm.discountType === "PERCENT" ? (
                    <FormField
                      label="Trần giảm tối đa (VND - để trống nếu không giới hạn)"
                      value={campaignForm.maxDiscount}
                      onChange={(v) => setCampaignForm({ ...campaignForm, maxDiscount: v })}
                      type="number"
                      placeholder="VD: 50000"
                    />
                  ) : <div />}
                  <FormField
                    label="Ngưỡng đơn hàng tối thiểu (VND - để trống nếu 0đ)"
                    value={campaignForm.discountThreshold}
                    onChange={(v) => setCampaignForm({ ...campaignForm, discountThreshold: v })}
                    type="number"
                    placeholder="VD: 100000"
                  />
                </div>
              )}
              {campaignForm.campaignType === "ITEMPRICERULE" && (
                <div style={{ background: "#fcf8f8", padding: "12px", borderRadius: "8px", border: "1px solid #fecdd3" }}>
                  <FormField label="Giá đồng giá (VND) *" value={campaignForm.fixedPriceValue} onChange={(v) => setCampaignForm({ ...campaignForm, fixedPriceValue: v })} type="number" placeholder="VD: 25000" />
                </div>
              )}
            </div>

            {/* 2. Phạm vi áp dụng món & nhóm hàng */}
            <div style={{ gridColumn: "1 / -1", borderTop: "1px solid #eee", paddingTop: "12px", marginTop: "4px" }}>
              <div style={{ fontSize: "14px", fontWeight: "700", marginBottom: "8px", color: "#1e3a8a" }}>📦 Phạm vi áp dụng món / nhóm hàng</div>
              <div style={{ fontSize: "12px", color: "#64748b", marginBottom: "8px" }}>
                Nếu để trống cả 2 mục, ưu đãi sẽ được áp dụng cho toàn bộ menu.
              </div>

              {/* Nhóm hàng */}
              <div style={{ marginBottom: "12px", background: "#f8fafc", padding: "10px", borderRadius: "8px", border: "1px solid #e2e8f0" }}>
                <label style={{ ...labelStyle, color: "#1e40af" }}>📁 Nhóm hàng áp dụng ({campaignForm.includedGroupIds.length})</label>
                <div style={{ display: "flex", gap: "8px", alignItems: "center", marginBottom: "8px" }}>
                  <select
                    style={{ ...inputStyle, flex: 1 }}
                    value=""
                    onChange={(e) => {
                      if (e.target.value && !campaignForm.includedGroupIds.includes(e.target.value)) {
                        setCampaignForm(prev => ({ ...prev, includedGroupIds: [...prev.includedGroupIds, e.target.value] }));
                      }
                    }}
                  >
                    <option value="">-- Bấm để thêm nhóm hàng --</option>
                    {categories.filter(c => !campaignForm.includedGroupIds.includes(c.name)).map(c => (
                      <option key={c.id || c.name} value={c.name}>{c.name}</option>
                    ))}
                  </select>
                  {campaignForm.includedGroupIds.length > 0 && (
                    <button
                      type="button"
                      onClick={() => setCampaignForm(prev => ({ ...prev, includedGroupIds: [] }))}
                      style={{ padding: "6px 12px", fontSize: "12px", border: "1px solid #cbd5e1", borderRadius: "6px", background: "#fff", cursor: "pointer", color: "#64748b" }}
                    >
                      Bỏ chọn tất cả
                    </button>
                  )}
                </div>
                {campaignForm.includedGroupIds.length > 0 ? (
                  <div style={{ display: "flex", flexWrap: "wrap", gap: "6px" }}>
                    {campaignForm.includedGroupIds.map(g => (
                      <span key={g} style={{ display: "inline-flex", alignItems: "center", gap: "6px", padding: "4px 10px", background: "#dbeafe", color: "#1e40af", borderRadius: "16px", fontSize: "12px", fontWeight: "600" }}>
                        📁 {g}
                        <button
                          type="button"
                          onClick={() => setCampaignForm(prev => ({ ...prev, includedGroupIds: prev.includedGroupIds.filter(x => x !== g) }))}
                          style={{ border: "none", background: "none", cursor: "pointer", color: "#1e40af", fontWeight: "bold", fontSize: "14px", lineHeight: 1 }}
                        >×</button>
                      </span>
                    ))}
                  </div>
                ) : (
                  <div style={{ fontSize: "12px", color: "#94a3b8", fontStyle: "italic" }}>Tất cả nhóm hàng (mặc định)</div>
                )}
              </div>

              {/* Món hàng */}
              <div style={{ background: "#f8fafc", padding: "10px", borderRadius: "8px", border: "1px solid #e2e8f0" }}>
                <label style={{ ...labelStyle, color: "#b45309" }}>📦 Món hàng áp dụng ({campaignForm.includedItemIds.length})</label>
                <div style={{ display: "flex", gap: "8px", alignItems: "center", marginBottom: "8px" }}>
                  <select
                    style={{ ...inputStyle, flex: 1 }}
                    value=""
                    onChange={(e) => {
                      if (e.target.value && !campaignForm.includedItemIds.includes(String(e.target.value))) {
                        setCampaignForm(prev => ({ ...prev, includedItemIds: [...prev.includedItemIds, String(e.target.value)] }));
                      }
                    }}
                  >
                    <option value="">-- Bấm để thêm món áp dụng --</option>
                    {products.filter(p => !campaignForm.includedItemIds.includes(String(p.id))).map(p => (
                      <option key={p.id} value={String(p.id)}>{p.name} {p.price ? `(${formatVND(p.price)})` : ""} {p.category ? `• ${p.category}` : ""}</option>
                    ))}
                  </select>
                  {campaignForm.includedItemIds.length > 0 && (
                    <button
                      type="button"
                      onClick={() => setCampaignForm(prev => ({ ...prev, includedItemIds: [] }))}
                      style={{ padding: "6px 12px", fontSize: "12px", border: "1px solid #cbd5e1", borderRadius: "6px", background: "#fff", cursor: "pointer", color: "#64748b" }}
                    >
                      Bỏ chọn tất cả
                    </button>
                  )}
                </div>
                {campaignForm.includedItemIds.length > 0 ? (
                  <div style={{ display: "flex", flexWrap: "wrap", gap: "6px", maxHeight: "120px", overflowY: "auto" }}>
                    {campaignForm.includedItemIds.map(id => {
                      const prod = products.find(p => String(p.id) === String(id));
                      const name = prod ? prod.name : id;
                      return (
                        <span key={id} style={{ display: "inline-flex", alignItems: "center", gap: "6px", padding: "4px 10px", background: "#fef3c7", color: "#92400e", borderRadius: "16px", fontSize: "12px", fontWeight: "600" }}>
                          📦 {name}
                          <button
                            type="button"
                            onClick={() => setCampaignForm(prev => ({ ...prev, includedItemIds: prev.includedItemIds.filter(x => x !== id) }))}
                            style={{ border: "none", background: "none", cursor: "pointer", color: "#92400e", fontWeight: "bold", fontSize: "14px", lineHeight: 1 }}
                          >×</button>
                        </span>
                      );
                    })}
                  </div>
                ) : (
                  <div style={{ fontSize: "12px", color: "#94a3b8", fontStyle: "italic" }}>Tất cả món hàng (mặc định)</div>
                )}
              </div>
            </div>

            {/* 3. Lịch trình, Ngày trong tuần & Happy Hours */}
            <div style={{ gridColumn: "1 / -1", borderTop: "1px solid #eee", paddingTop: "12px", marginTop: "4px" }}>
              <div style={{ fontSize: "14px", fontWeight: "700", marginBottom: "8px", color: "#065f46" }}>⏰ Lịch trình & Khung giờ áp dụng (Happy hours)</div>
            </div>
            <FormField label="Ngày bắt đầu" value={campaignForm.startDate} onChange={(v) => setCampaignForm({ ...campaignForm, startDate: v })} type="datetime-local" />
            <FormField label="Ngày kết thúc" value={campaignForm.endDate} onChange={(v) => setCampaignForm({ ...campaignForm, endDate: v })} type="datetime-local" />

            {/* Ngày trong tuần */}
            <div style={{ gridColumn: "1 / -1", background: "#f0fdf4", padding: "12px", borderRadius: "8px", border: "1px solid #bbf7d0" }}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "8px", flexWrap: "wrap", gap: "4px" }}>
                <label style={{ ...labelStyle, color: "#166534", margin: 0 }}>
                  📅 Ngày áp dụng trong tuần: {campaignForm.daysOfWeek.length === 0 || campaignForm.daysOfWeek.length === 7 ? "Tất cả các ngày (T2 - CN)" : `${campaignForm.daysOfWeek.length} ngày đã chọn`}
                </label>
                <div style={{ display: "flex", gap: "6px" }}>
                  <button
                    type="button"
                    onClick={() => setCampaignForm(prev => ({ ...prev, daysOfWeek: [1, 2, 3, 4, 5, 6, 7] }))}
                    style={{ padding: "3px 8px", fontSize: "11px", borderRadius: "4px", border: "1px solid #86efac", background: "#fff", cursor: "pointer", color: "#15803d" }}
                  >
                    Tất cả (T2-CN)
                  </button>
                  <button
                    type="button"
                    onClick={() => setCampaignForm(prev => ({ ...prev, daysOfWeek: [1, 2, 3, 4, 5] }))}
                    style={{ padding: "3px 8px", fontSize: "11px", borderRadius: "4px", border: "1px solid #86efac", background: "#fff", cursor: "pointer", color: "#15803d" }}
                  >
                    T2 - T6
                  </button>
                  <button
                    type="button"
                    onClick={() => setCampaignForm(prev => ({ ...prev, daysOfWeek: [6, 7] }))}
                    style={{ padding: "3px 8px", fontSize: "11px", borderRadius: "4px", border: "1px solid #86efac", background: "#fff", cursor: "pointer", color: "#15803d" }}
                  >
                    Cuối tuần (T7, CN)
                  </button>
                  <button
                    type="button"
                    onClick={() => setCampaignForm(prev => ({ ...prev, daysOfWeek: [] }))}
                    style={{ padding: "3px 8px", fontSize: "11px", borderRadius: "4px", border: "1px solid #cbd5e1", background: "#fff", cursor: "pointer", color: "#64748b" }}
                  >
                    Xóa
                  </button>
                </div>
              </div>
              <div style={{ display: "flex", gap: "8px", flexWrap: "wrap" }}>
                {[
                  { d: 1, label: "Thứ 2" },
                  { d: 2, label: "Thứ 3" },
                  { d: 3, label: "Thứ 4" },
                  { d: 4, label: "Thứ 5" },
                  { d: 5, label: "Thứ 6" },
                  { d: 6, label: "Thứ 7" },
                  { d: 7, label: "Chủ nhật" },
                ].map(({ d, label }) => {
                  const isSelected = campaignForm.daysOfWeek.includes(d);
                  return (
                    <button
                      key={d}
                      type="button"
                      onClick={() => {
                        setCampaignForm(prev => {
                          const exists = prev.daysOfWeek.includes(d);
                          return {
                            ...prev,
                            daysOfWeek: exists ? prev.daysOfWeek.filter(x => x !== d) : [...prev.daysOfWeek, d].sort()
                          };
                        });
                      }}
                      style={{
                        padding: "6px 14px",
                        borderRadius: "8px",
                        fontSize: "13px",
                        fontWeight: "700",
                        cursor: "pointer",
                        border: isSelected ? "2px solid #16a34a" : "1px solid #cbd5e1",
                        background: isSelected ? "#16a34a" : "#fff",
                        color: isSelected ? "#fff" : "#334155",
                      }}
                    >
                      {label}
                    </button>
                  );
                })}
              </div>
            </div>

            {/* Happy Hours slots */}
            <div style={{ gridColumn: "1 / -1", background: "#f5f3ff", padding: "12px", borderRadius: "8px", border: "1px solid #ddd6fe" }}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "8px" }}>
                <div>
                  <label style={{ ...labelStyle, color: "#6b21a8", margin: 0 }}>
                    ⏰ Khung giờ Happy Hours ({campaignForm.timeSlots.length})
                  </label>
                  <div style={{ fontSize: "12px", color: "#7c3aed" }}>
                    Chương trình chỉ áp dụng trong các khung giờ này (để trống nếu áp dụng cả ngày).
                  </div>
                </div>
                <button
                  type="button"
                  onClick={() => {
                    setCampaignForm(prev => ({
                      ...prev,
                      timeSlots: [...prev.timeSlots, { startTime: "14:00", endTime: "17:00" }]
                    }));
                  }}
                  style={{
                    padding: "6px 12px",
                    background: "#7c3aed",
                    color: "#fff",
                    border: "none",
                    borderRadius: "6px",
                    fontSize: "12px",
                    fontWeight: "600",
                    cursor: "pointer"
                  }}
                >
                  + Thêm khung giờ
                </button>
              </div>

              {campaignForm.timeSlots.length === 0 ? (
                <div style={{ fontSize: "12px", color: "#8b5cf6", fontStyle: "italic" }}>
                  Áp dụng mọi khung giờ trong ngày (mặc định)
                </div>
              ) : (
                <div style={{ display: "flex", flexDirection: "column", gap: "8px" }}>
                  {campaignForm.timeSlots.map((slot, idx) => (
                    <div key={idx} style={{ display: "flex", alignItems: "center", gap: "10px", background: "#fff", padding: "8px 12px", borderRadius: "6px", border: "1px solid #e9d5ff" }}>
                      <span style={{ fontSize: "13px", fontWeight: "600", color: "#6b21a8", minWidth: "60px" }}>Ca #{idx + 1}</span>
                      <div style={{ display: "flex", alignItems: "center", gap: "6px" }}>
                        <span style={{ fontSize: "12px", color: "#555" }}>Từ:</span>
                        <input
                          type="time"
                          value={slot.startTime}
                          onChange={(e) => {
                            const val = e.target.value;
                            setCampaignForm(prev => {
                              const slots = [...prev.timeSlots];
                              slots[idx] = { ...slots[idx], startTime: val };
                              return { ...prev, timeSlots: slots };
                            });
                          }}
                          style={{ padding: "4px 8px", border: "1px solid #ccc", borderRadius: "4px", fontSize: "13px" }}
                        />
                      </div>
                      <div style={{ display: "flex", alignItems: "center", gap: "6px" }}>
                        <span style={{ fontSize: "12px", color: "#555" }}>Đến:</span>
                        <input
                          type="time"
                          value={slot.endTime}
                          onChange={(e) => {
                            const val = e.target.value;
                            setCampaignForm(prev => {
                              const slots = [...prev.timeSlots];
                              slots[idx] = { ...slots[idx], endTime: val };
                              return { ...prev, timeSlots: slots };
                            });
                          }}
                          style={{ padding: "4px 8px", border: "1px solid #ccc", borderRadius: "4px", fontSize: "13px" }}
                        />
                      </div>
                      <button
                        type="button"
                        onClick={() => {
                          setCampaignForm(prev => ({
                            ...prev,
                            timeSlots: prev.timeSlots.filter((_, i) => i !== idx)
                          }));
                        }}
                        style={{ marginLeft: "auto", padding: "4px 8px", background: "#fee2e2", color: "#ef4444", border: "none", borderRadius: "4px", fontSize: "12px", cursor: "pointer" }}
                      >
                        Xóa
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </div>

            {/* 4. Hạn mức */}
            <div style={{ gridColumn: "1 / -1", borderTop: "1px solid #eee", paddingTop: "12px", marginTop: "4px" }}>
              <div style={{ fontSize: "14px", fontWeight: "700", marginBottom: "8px" }}>💰 Hạn mức</div>
            </div>
            <FormField label="Ngân sách (VND)" value={campaignForm.budgetMoney} onChange={(v) => setCampaignForm({ ...campaignForm, budgetMoney: v })} type="number" />
            <FormField label="Giới hạn lượt dùng" value={campaignForm.maxUses} onChange={(v) => setCampaignForm({ ...campaignForm, maxUses: v })} type="number" />

            {/* 5. Bắt buộc nhân viên nhập ghi chú (Mục 2 của Module 1) */}
            <div style={{ gridColumn: "1 / -1", background: "#fffbeb", border: "1px solid #fef08a", borderRadius: "8px", padding: "12px 14px", marginTop: "4px" }}>
              <label style={{ display: "flex", alignItems: "flex-start", gap: "10px", cursor: "pointer" }}>
                <input
                  type="checkbox"
                  checked={campaignForm.requireStaffNote}
                  onChange={(e) => setCampaignForm({ ...campaignForm, requireStaffNote: e.target.checked })}
                  style={{ marginTop: "3px", width: "16px", height: "16px" }}
                />
                <div>
                  <div style={{ fontSize: "13px", fontWeight: "700", color: "#854d0e" }}>
                    📝 Bắt buộc nhân viên nhập ghi chú/lý do khi áp dụng mã tại POS
                  </div>
                  <div style={{ fontSize: "12px", color: "#a16207", marginTop: "2px" }}>
                    Khi bật tính năng này, màn hình thu ngân/POS sẽ hiển thị hộp thoại bắt buộc nhập lý do sử dụng ưu đãi trước khi thêm vào hóa đơn. Ghi chú sẽ được lưu vào lịch sử hóa đơn.
                  </div>
                </div>
              </label>
            </div>

            {/* 6. Cài đặt khác */}
            <div style={{ gridColumn: "1 / -1", borderTop: "1px solid #eee", paddingTop: "12px", marginTop: "4px" }}>
              <div style={{ fontSize: "14px", fontWeight: "700", marginBottom: "8px" }}>⚙️ Cài đặt khác</div>
            </div>
            <div style={{ gridColumn: "1 / -1", display: "flex", gap: "24px", flexWrap: "wrap" }}>
              <label style={{ display: "flex", alignItems: "center", gap: "8px", fontSize: "13px", fontWeight: "500", cursor: "pointer" }}>
                <input type="checkbox" checked={campaignForm.hasCodes} onChange={(e) => setCampaignForm({ ...campaignForm, hasCodes: e.target.checked })} />
                Yêu cầu mã Voucher
              </label>
              <label style={{ display: "flex", alignItems: "center", gap: "8px", fontSize: "13px", fontWeight: "500", cursor: "pointer" }}>
                <input type="checkbox" checked={campaignForm.autoApply} onChange={(e) => setCampaignForm({ ...campaignForm, autoApply: e.target.checked })} />
                Tự động áp dụng
              </label>
              <label style={{ display: "flex", alignItems: "center", gap: "8px", fontSize: "13px", fontWeight: "500", cursor: "pointer" }}>
                <input type="checkbox" checked={campaignForm.active} onChange={(e) => setCampaignForm({ ...campaignForm, active: e.target.checked })} />
                Kích hoạt
              </label>
            </div>
            
            <div style={{ gridColumn: "1 / -1" }}>
              <FormField label="Mô tả" value={campaignForm.description} onChange={(v) => setCampaignForm({ ...campaignForm, description: v })} placeholder="Ghi chú nội bộ về chương trình..." />
            </div>
          </div>
          {formError && <div style={{ color: "#ef4444", fontSize: "13px", marginTop: "8px" }}>{formError}</div>}
          <div style={{ display: "flex", justifyContent: "flex-end", gap: "8px", marginTop: "16px", paddingTop: "16px", borderTop: "1px solid #eee" }}>
            <button onClick={() => setShowCampaignModal(false)} style={btnSecondary}>Hủy</button>
            <button onClick={handleSaveCampaign} disabled={saving} style={btnPrimary}>{saving ? "Đang lưu..." : "Lưu KM"}</button>
          </div>
        </Modal>
      )}

      {/* Generate Vouchers Modal */}
      {showVoucherModal && (
        <Modal title="Phát hành mã Voucher" onClose={() => setShowVoucherModal(false)}>
          <div style={{ display: "flex", gap: "8px", marginBottom: "16px", borderBottom: "1px solid #eee", paddingBottom: "12px" }}>
            <button
              type="button"
              onClick={() => setVoucherForm({ ...voucherForm, isCustom: false })}
              style={{
                flex: 1,
                padding: "8px 12px",
                borderRadius: "8px",
                border: !voucherForm.isCustom ? "2px solid #7E2930" : "1px solid #ddd",
                background: !voucherForm.isCustom ? "#fdf2f2" : "#fff",
                color: !voucherForm.isCustom ? "#7E2930" : "#555",
                fontWeight: !voucherForm.isCustom ? "700" : "500",
                fontSize: "13px",
                cursor: "pointer",
              }}
            >
              ⚡ Tự động sinh hàng loạt
            </button>
            <button
              type="button"
              onClick={() => setVoucherForm({ ...voucherForm, isCustom: true })}
              style={{
                flex: 1,
                padding: "8px 12px",
                borderRadius: "8px",
                border: voucherForm.isCustom ? "2px solid #7E2930" : "1px solid #ddd",
                background: voucherForm.isCustom ? "#fdf2f2" : "#fff",
                color: voucherForm.isCustom ? "#7E2930" : "#555",
                fontWeight: voucherForm.isCustom ? "700" : "500",
                fontSize: "13px",
                cursor: "pointer",
              }}
            >
              🏷️ Nhập 1 mã cụ thể
            </button>
          </div>

          <div style={{ display: "grid", gap: "12px" }}>
            {voucherForm.isCustom ? (
              <div>
                <FormField
                  label="Mã Voucher cụ thể *"
                  value={voucherForm.customCode}
                  onChange={(v) => setVoucherForm({ ...voucherForm, customCode: v.toUpperCase() })}
                  placeholder="VD: CHAOBAN20, GIAM10K, TRAMVIP"
                />
                <div style={{ fontSize: "12px", color: "#666", marginTop: "4px" }}>
                  Mã sẽ được kích hoạt ngay lập tức và áp dụng tại máy POS.
                </div>
              </div>
            ) : (
              <>
                <FormField label="Số lượng mã *" value={voucherForm.quantity} onChange={(v) => setVoucherForm({ ...voucherForm, quantity: v })} type="number" />
                <FormField label="Tiền tố mã (VD: TRAM)" value={voucherForm.prefix} onChange={(v) => setVoucherForm({ ...voucherForm, prefix: v })} />
                <div style={{ fontSize: "12px", color: "#666" }}>Mã sẽ được tạo ngẫu nhiên theo định dạng: <b>{voucherForm.prefix.toUpperCase()}XXXXXX</b></div>
              </>
            )}
          </div>
          {formError && <div style={{ color: "#ef4444", fontSize: "13px", marginTop: "8px" }}>{formError}</div>}
          <div style={{ display: "flex", justifyContent: "flex-end", gap: "8px", marginTop: "16px" }}>
            <button onClick={() => setShowVoucherModal(false)} style={btnSecondary}>Hủy</button>
            <button onClick={handleGenerateVouchers} disabled={saving} style={btnPrimary}>{saving ? "Đang tạo..." : "Xác nhận tạo mã"}</button>
          </div>
        </Modal>
      )}
    </div>
  );
}

// ==================== UI HELPERS ====================
function EmptyState({ icon, text, sub }: { icon: string; text: string; sub: string }) {
  return (
    <div style={{ textAlign: "center", padding: "60px 20px" }}>
      <div style={{ fontSize: "48px", marginBottom: "12px" }}>{icon}</div>
      <div style={{ fontSize: "16px", fontWeight: "600", color: "#333" }}>{text}</div>
      <div style={{ fontSize: "13px", color: "#999", marginTop: "6px" }}>{sub}</div>
    </div>
  );
}

function Modal({ title, children, onClose }: { title: string; children: React.ReactNode; onClose: () => void }) {
  return (
    <div style={{ position: "fixed", inset: 0, background: "rgba(0,0,0,0.5)", display: "flex", alignItems: "center", justifyContent: "center", zIndex: 100 }} onClick={onClose}>
      <div style={{ background: "#fff", borderRadius: "16px", padding: "24px", width: "90%", maxWidth: "780px", maxHeight: "90vh", display: "flex", flexDirection: "column", boxShadow: "0 20px 60px rgba(0,0,0,0.3)" }} onClick={(e) => e.stopPropagation()}>
        <h3 style={{ fontSize: "18px", fontWeight: "700", marginBottom: "16px", color: "#1a1a2e" }}>{title}</h3>
        {children}
      </div>
    </div>
  );
}

function FormField({ label, value, onChange, type = "text", placeholder = "", disabled = false }: { label: string; value: string; onChange: (v: string) => void; type?: string; placeholder?: string; disabled?: boolean }) {
  return (
    <div>
      <label style={labelStyle}>{label}</label>
      <input type={type} value={value} onChange={(e) => onChange(e.target.value)} placeholder={placeholder} disabled={disabled} style={{ ...inputStyle, opacity: disabled ? 0.6 : 1 }} />
    </div>
  );
}

// Styles
const btnPrimary: React.CSSProperties = {
  display: "flex", alignItems: "center", gap: "6px", padding: "10px 18px",
  background: "#7E2930", color: "#fff", border: "none", borderRadius: "10px",
  fontSize: "13px", fontWeight: "700", cursor: "pointer",
};
const btnSecondary: React.CSSProperties = {
  padding: "10px 18px", background: "#f5f5f5", color: "#333", border: "1px solid #ddd",
  borderRadius: "10px", fontSize: "13px", fontWeight: "600", cursor: "pointer",
};
const thStyle: React.CSSProperties = {
  padding: "12px 14px", textAlign: "left", fontSize: "12px", fontWeight: "700",
  color: "#666", textTransform: "uppercase", letterSpacing: "0.03em",
};
const tdStyle: React.CSSProperties = {
  padding: "12px 14px", fontSize: "13px", color: "#333", verticalAlign: "middle"
};
const labelStyle: React.CSSProperties = {
  display: "block", fontSize: "12px", fontWeight: "600", color: "#555", marginBottom: "4px",
};
const inputStyle: React.CSSProperties = {
  width: "100%", padding: "8px 12px", borderRadius: "8px", border: "1px solid #ddd", fontSize: "14px", boxSizing: "border-box"
};
const badgeStyle = (color: string): React.CSSProperties => ({
  display: "inline-block", padding: "2px 8px", borderRadius: "6px", fontSize: "11px",
  fontWeight: "700", background: `${color}15`, color: color, whiteSpace: "nowrap",
});
