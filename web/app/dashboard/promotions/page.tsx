"use client";
import { useState, useMemo, useEffect, useCallback } from "react";
import { Search, Plus, Tag, Ticket } from "lucide-react";
import { ref, onValue, set, update, get } from "firebase/database";
import { db } from "@/lib/firebase";
import { useDashboardData, type ProductItem } from "@/lib/data-context";
import { errorMessage } from "@/lib/errors";
import {
  CAMPAIGN_TYPE_LABELS, REWARD_BENEFIT_LABELS, buildBenefitFields, campaignToForm, describeCampaignBenefit,
  emptyCampaignForm, normalizeCampaignType, validateCampaignForm,
  type CampaignFormState, type RawBuyCondition, type RawTier, type RewardBenefit,
  normalizeStackingMode,
} from "@/lib/campaign-form";
import {
  buildVoucherCancelUpdate, buildVoucherCreateUpdates, canCancelVoucher, checkVoucher, filterVouchers,
  generateRandomCodes, newVoucherId, normalizeVoucherCode, parseVoucherCodes, toVoucherView,
  voucherStatusColor, voucherStatusText, voucherStats as computeVoucherStats, VOUCHER_CODE_RE,
  type VoucherCheckResult, type VoucherView,
} from "@/lib/campaign-vouchers";

function formatVND(amount: number | undefined) {
  if (amount === undefined) return "—";
  return new Intl.NumberFormat("vi-VN", { style: "currency", currency: "VND" }).format(amount);
}

function formatDate(ts: number | undefined) {
  if (!ts) return "—";
  const d = new Date(ts);
  return d.toLocaleDateString("vi-VN", { day: "2-digit", month: "2-digit", year: "numeric" });
}

function formatDateTime(ts: number | undefined) {
  if (!ts) return "—";
  return new Date(ts).toLocaleString("vi-VN", { hour: "2-digit", minute: "2-digit", day: "2-digit", month: "2-digit", year: "numeric" });
}

// ==================== TYPES ====================
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
  tiers: RawTier[];
  buyConditions: RawBuyCondition[];
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

const typeLabels: Record<string, string> = CAMPAIGN_TYPE_LABELS;

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
  const [voucherState, setVoucherState] = useState<{ campaignId: string; list: VoucherView[] } | null>(null);
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
  const [campaignForm, setCampaignForm] = useState<CampaignFormState>(emptyCampaignForm);

  // Voucher form state (dùng chung cho modal phát hành mã và khối "Phát hành mã" trong form KM)
  const emptyVoucherForm = { mode: "LIST" as "LIST" | "RANDOM", codesText: "", quantity: "10", prefix: "" };
  const [voucherForm, setVoucherForm] = useState(emptyVoucherForm);
  const [voucherSearch, setVoucherSearch] = useState("");
  const [checkCode, setCheckCode] = useState("");
  const [checkResult, setCheckResult] = useState<VoucherCheckResult | null>(null);
  const [checking, setChecking] = useState(false);

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
          autoApply: v.autoApply ?? false, stackingMode: normalizeStackingMode(v.stackingMode), priority: v.priority || 0,
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
        const vs: VoucherView[] = [];
        snap.forEach((child) => {
          vs.push(toVoucherView(child.key!, selectedVoucherCampaign, child.val()));
        });
        vs.sort((x, y) => (y.createdAt || 0) - (x.createdAt || 0) || x.code.localeCompare(y.code));
        setVoucherState({ campaignId: selectedVoucherCampaign, list: vs });
      });
      return () => unsub();
    }
  }, [activeTab, selectedVoucherCampaign, targetStoreCode]);

  const vouchers = useMemo<VoucherView[]>(() => {
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
    const matchType = !filterType || normalizeCampaignType(c.campaignType) === filterType;
    const status = getCampaignStatus(c);
    const matchStatus = filterStatus === "ALL" || status === filterStatus;
    return matchSearch && matchType && matchStatus;
  }), [campaigns, search, filterType, filterStatus, getCampaignStatus]);

  // Vouchers stats
  const voucherStats = useMemo(() => computeVoucherStats(vouchers), [vouchers]);
  const visibleVouchers = useMemo(() => filterVouchers(vouchers, voucherSearch), [vouchers, voucherSearch]);

  // Xem trước danh sách mã sẽ tạo (chỉ đối chiếu trùng với mã đã nạp; khi lưu sẽ kiểm tra lại trên server)
  const voucherPreview = useMemo(() => {
    if (voucherForm.mode !== "LIST") return null;
    return parseVoucherCodes(voucherForm.codesText, vouchers.map((v) => v.code));
  }, [voucherForm.mode, voucherForm.codesText, vouchers]);

  /** Mã đã tồn tại trong chương trình (đọc server) hoặc đã được dùng ở chương trình khác (voucher_lookup). */
  const findTakenCodes = async (campaignId: string, codes: string[]): Promise<Set<string>> => {
    const taken = new Set<string>();
    const camSnap = await get(ref(db, `stores/${targetStoreCode}/vouchers/${campaignId}`));
    camSnap.forEach((child) => {
      const v = toVoucherView(child.key!, campaignId, child.val());
      if (v.code) taken.add(v.code);
    });
    const lookups = await Promise.all(
      codes.filter((c) => !taken.has(c)).map(async (c) => [c, (await get(ref(db, `stores/${targetStoreCode}/voucher_lookup/${c}`))).exists()] as const),
    );
    for (const [c, exists] of lookups) if (exists) taken.add(c);
    return taken;
  };

  /** Lấy danh sách mã từ voucherForm (dán danh sách hoặc sinh ngẫu nhiên), loại mã trùng. */
  const collectVoucherCodes = async (campaignId: string): Promise<{ codes: string[]; error?: string; notes: string[] }> => {
    const notes: string[] = [];
    if (voucherForm.mode === "LIST") {
      const parsed = parseVoucherCodes(voucherForm.codesText);
      if (parsed.invalid.length) return { codes: [], notes, error: `Mã sai định dạng: ${parsed.invalid.slice(0, 10).join(", ")}${parsed.invalid.length > 10 ? "…" : ""} (chỉ gồm chữ không dấu, số, - hoặc _, 3–32 ký tự)` };
      if (parsed.duplicateInInput.length) notes.push(`Bỏ qua ${parsed.duplicateInInput.length} mã lặp trong danh sách`);
      if (parsed.codes.length === 0) return { codes: [], notes, error: "Vui lòng dán ít nhất 1 mã" };
      const taken = await findTakenCodes(campaignId, parsed.codes);
      const dup = parsed.codes.filter((c) => taken.has(c));
      if (dup.length) return { codes: [], notes, error: `Các mã đã tồn tại, vui lòng bỏ ra: ${dup.slice(0, 10).join(", ")}${dup.length > 10 ? "…" : ""}` };
      return { codes: parsed.codes, notes };
    }
    const qty = parseInt(voucherForm.quantity);
    if (isNaN(qty) || qty <= 0 || qty > 1000) return { codes: [], notes, error: "Số lượng không hợp lệ (1 - 1000)" };
    const prefix = normalizeVoucherCode(voucherForm.prefix);
    if (prefix && !/^[A-Z0-9_-]{1,20}$/.test(prefix)) return { codes: [], notes, error: "Tiền tố chỉ gồm chữ không dấu, số, - hoặc _ (tối đa 20 ký tự)" };
    let codes = generateRandomCodes(qty, prefix, vouchers.map((v) => v.code));
    const taken = await findTakenCodes(campaignId, codes);
    if (taken.size) {
      codes = codes.filter((c) => !taken.has(c));
      codes = codes.concat(generateRandomCodes(qty - codes.length, prefix, [...taken, ...codes]));
    }
    return { codes, notes };
  };

  const writeVoucherCodes = async (campaignId: string, codes: string[]) => {
    const now = Date.now();
    await update(ref(db, `stores/${targetStoreCode}`), buildVoucherCreateUpdates(campaignId, codes, now, (i) => newVoucherId(now, i)));
  };

  // Handle Save Campaign
  const handleSaveCampaign = async () => {
    const err = validateCampaignForm(campaignForm);
    if (err) { setFormError(err); return; }
    const wantsCodes = campaignForm.hasCodes && (voucherForm.mode === "RANDOM" ? !!voucherForm.quantity.trim() && voucherForm.quantity.trim() !== "0" : !!voucherForm.codesText.trim());

    setSaving(true); setFormError("");
    try {
      const now = Date.now();
      const campaignId = editingCampaign?.campaignId || `CAM_${now}_${Math.random().toString(36).slice(2, 6)}`;
      const programCode = editingCampaign?.programCode || campaignForm.programCode.trim() || `KM${String(campaigns.length + 1).padStart(4, "0")}`;

      // Kiểm tra mã trước khi ghi chương trình để không lưu dở dang
      let codes: string[] = [];
      if (wantsCodes) {
        const res = await collectVoucherCodes(campaignId);
        if (res.error) { setFormError(res.error); setSaving(false); return; }
        codes = res.codes;
      }

      const benefit = buildBenefitFields(campaignForm, editingCampaign ?? undefined);

      const schedule: NonNullable<CampaignItem["schedule"]> & { timezone: string } = { timezone: "Asia/Ho_Chi_Minh" };
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
        includedItemIds: benefit.includedItemIds,
        includedGroupIds: benefit.includedGroupIds,
        tiers: benefit.tiers,
        buyConditions: benefit.buyConditions,
        budgetMoney: Number(campaignForm.budgetMoney) || 0,
        maxUses: Number(campaignForm.maxUses) || 0,
        hasCodes: campaignForm.hasCodes,
        autoApply: campaignForm.autoApply,
        requireStaffNote: campaignForm.requireStaffNote,
        stackingMode: normalizeStackingMode(campaignForm.stackingMode),
        priority: Number(campaignForm.priority) || 0,
        createdAt: editingCampaign?.createdAt || now,
        updatedAt: now,
        createdBy: editingCampaign?.createdBy || "Admin"
      };

      const camRef = ref(db, `stores/${targetStoreCode}/campaigns/${campaignId}`);
      // Sửa: update để giữ các trường do Flutter ghi mà web không quản lý (excludedItemIds, version...)
      if (editingCampaign) await update(camRef, data);
      else await set(camRef, data);
      if (codes.length > 0) await writeVoucherCodes(campaignId, codes);
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
      const res = await collectVoucherCodes(selectedVoucherCampaign);
      if (res.error) { setFormError(res.error); setSaving(false); return; }
      if (res.codes.length === 0) { setFormError("Không có mã nào để tạo"); setSaving(false); return; }
      await writeVoucherCodes(selectedVoucherCampaign, res.codes);
      setShowVoucherModal(false);
    } catch (e) { setFormError(errorMessage(e) || "Lỗi tạo mã"); }
    setSaving(false);
  };

  const handleCancelVoucher = async (v: VoucherView) => {
    if (!window.confirm(`Hủy mã ${v.code}? Mã đã hủy không thể dùng lại.`)) return;
    try {
      await update(ref(db, `stores/${targetStoreCode}/vouchers/${v.campaignId}/${v.voucherId}`), buildVoucherCancelUpdate());
    } catch (e) {
      window.alert(errorMessage(e) || "Không hủy được mã");
    }
  };

  const handleCheckCode = async () => {
    const code = normalizeVoucherCode(checkCode);
    const now = Date.now();
    if (!code) { setCheckResult(null); return; }
    if (!VOUCHER_CODE_RE.test(code)) { setCheckResult(checkVoucher(code, null, null, now)); return; }
    setChecking(true);
    try {
      const lookup = await get(ref(db, `stores/${targetStoreCode}/voucher_lookup/${code}`));
      let voucher: VoucherView | null = null;
      if (lookup.exists()) {
        const { campaignId, voucherId } = lookup.val() as { campaignId: string; voucherId: string };
        const vs = await get(ref(db, `stores/${targetStoreCode}/vouchers/${campaignId}/${voucherId}`));
        if (vs.exists()) voucher = toVoucherView(voucherId, campaignId, vs.val());
      }
      const cam = voucher ? campaigns.find((c) => c.campaignId === voucher.campaignId) ?? null : null;
      setCheckResult(checkVoucher(code, voucher, cam, now));
    } catch (e) {
      setCheckResult({ kind: "NOT_FOUND", ok: false, message: errorMessage(e) || "Lỗi kiểm tra mã" });
    }
    setChecking(false);
  };

  const openEditCampaign = (cam: CampaignItem) => {
    setEditingCampaign(cam);
    setCampaignForm(campaignToForm(cam));
    setVoucherForm(emptyVoucherForm);
    setFormError("");
    setShowCampaignModal(true);
  };

  const openAddCampaign = () => {
    setEditingCampaign(null);
    setCampaignForm(emptyCampaignForm());
    setVoucherForm(emptyVoucherForm);
    setFormError("");
    setShowCampaignModal(true);
  };

  const toggleCampaignActive = async (cam: CampaignItem) => {
    await update(ref(db, `stores/${targetStoreCode}/campaigns/${cam.campaignId}`), { active: !cam.active, updatedAt: Date.now() });
  };

  // Ô nhập mã: dán danh sách hoặc sinh ngẫu nhiên (dùng trong form KM và modal thêm mã)
  const renderVoucherCodeInputs = () => (
    <div>
      <div style={{ display: "flex", gap: "8px", marginBottom: "12px" }}>
        {([["LIST", "📋 Dán danh sách mã"], ["RANDOM", "⚡ Sinh mã ngẫu nhiên"]] as const).map(([mode, label]) => {
          const on = voucherForm.mode === mode;
          return (
            <button key={mode} type="button" onClick={() => setVoucherForm({ ...voucherForm, mode })}
              aria-pressed={on}
              style={{
                flex: 1, padding: "8px 12px", borderRadius: "8px", fontSize: "13px", cursor: "pointer",
                border: on ? "2px solid var(--primary)" : "1px solid #ddd",
                background: on ? "#fdf2f2" : "var(--surface)", color: on ? "var(--primary)" : "var(--subtext)", fontWeight: on ? 700 : 500,
              }}>{label}</button>
          );
        })}
      </div>
      {voucherForm.mode === "LIST" ? (
        <div>
          <label style={labelStyle} htmlFor="voucher-codes-text">Danh sách mã (mỗi dòng 1 mã, hoặc cách nhau bằng dấu phẩy)</label>
          <textarea id="voucher-codes-text" value={voucherForm.codesText}
            onChange={(e) => setVoucherForm({ ...voucherForm, codesText: e.target.value })}
            rows={6} placeholder={"CHAOBAN20\nGIAM10K\nTRAMVIP"}
            style={{ ...inputStyle, fontFamily: "monospace", resize: "vertical" }} />
          {voucherPreview && voucherForm.codesText.trim() && (
            <div style={{ fontSize: "12px", marginTop: "4px", display: "flex", flexWrap: "wrap", gap: "10px" }}>
              <span style={{ color: "#15803d", fontWeight: 600 }}>✔ {voucherPreview.codes.length} mã mới</span>
              {voucherPreview.duplicateInInput.length > 0 && <span style={{ color: "#a16207" }}>Lặp trong danh sách: {voucherPreview.duplicateInInput.join(", ")}</span>}
              {voucherPreview.existing.length > 0 && <span style={{ color: "var(--danger)" }}>Đã tồn tại: {voucherPreview.existing.join(", ")}</span>}
              {voucherPreview.invalid.length > 0 && <span style={{ color: "var(--danger)" }}>Sai định dạng: {voucherPreview.invalid.join(", ")}</span>}
            </div>
          )}
          <div style={{ fontSize: "12px", color: "var(--subtext)", marginTop: "4px" }}>Mã được chuyển thành chữ in hoa; chỉ gồm chữ không dấu, số, - hoặc _ (3–32 ký tự).</div>
        </div>
      ) : (
        <div className="grid-stack-sm" style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "12px" }}>
          <FormField label="Số lượng mã *" value={voucherForm.quantity} onChange={(v) => setVoucherForm({ ...voucherForm, quantity: v })} type="number" />
          <FormField label="Tiền tố mã (VD: TRAM)" value={voucherForm.prefix} onChange={(v) => setVoucherForm({ ...voucherForm, prefix: v.toUpperCase() })} />
          <div style={{ gridColumn: "1 / -1", fontSize: "12px", color: "var(--subtext)" }}>Mã được tạo ngẫu nhiên theo định dạng: <b>{normalizeVoucherCode(voucherForm.prefix)}XXXXXX</b></div>
        </div>
      )}
    </div>
  );

  const tabs = [
    { key: "campaigns" as const, label: "Chương trình KM", icon: Tag, count: campaigns.length },
    { key: "vouchers" as const, label: "Mã Voucher", icon: Ticket, count: 0 },
  ];

  // Chưa có chi nhánh hợp lệ -> không đọc/ghi mặc định vào chi nhánh khác
  if (!targetStoreCode) {
    return (
      <div style={{ padding: "24px", color: "var(--subtext)" }}>Chưa xác định được chi nhánh. Vui lòng chọn một chi nhánh cụ thể.</div>
    );
  }

  return (
    <div style={{ padding: "24px" }}>
      {/* Header */}
      <div style={{ display: "flex", flexWrap: "wrap", rowGap: "8px", justifyContent: "space-between", alignItems: "center", marginBottom: "24px" }}>
        <div>
          <h1 style={{ fontSize: "24px", fontWeight: "800", color: "var(--text)", margin: 0 }}>
            🎉 Quản lý Khuyến mãi
          </h1>
          <p style={{ fontSize: "14px", color: "var(--subtext)", margin: "4px 0 0" }}>
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
                border: targetStoreCode === s.storeCode ? "2px solid var(--primary)" : "1px solid #ddd",
                background: targetStoreCode === s.storeCode ? "var(--primary)" : "var(--surface)",
                color: targetStoreCode === s.storeCode ? "#fff" : "var(--text)",
              }}>
              {s.storeName || s.storeCode}
            </button>
          ))}
        </div>
      )}

      {/* Tabs */}
      <div style={{ display: "flex", gap: "4px", marginBottom: "20px", borderBottom: "2px solid var(--border-light)", paddingBottom: "0" }}>
        {tabs.map((tab) => {
          const Icon = tab.icon;
          const isActive = activeTab === tab.key;
          return (
            <button key={tab.key} onClick={() => { setActiveTab(tab.key); setSearch(""); }}
              style={{
                display: "flex", alignItems: "center", gap: "6px", padding: "10px 16px",
                fontSize: "13px", fontWeight: isActive ? "700" : "500", cursor: "pointer",
                border: "none", borderBottom: isActive ? "3px solid var(--primary)" : "3px solid transparent",
                background: "transparent", color: isActive ? "var(--primary)" : "var(--subtext)", marginBottom: "-2px",
              }}>
              <Icon size={16} />
              {tab.label}
              {tab.key === "campaigns" && (
                <span style={{
                  background: isActive ? "var(--primary)" : "var(--border)", color: isActive ? "#fff" : "var(--subtext)",
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
        <div style={{ textAlign: "center", padding: "60px", color: "var(--muted)" }}>⏳ Đang tải dữ liệu...</div>
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
                      background: filterStatus === st ? "var(--primary)" : "#f1f1f1", color: filterStatus === st ? "#fff" : "var(--text)", whiteSpace: "nowrap"
                    }}>
                      {st === "ALL" ? "Tất cả" : st}
                    </button>
                  ))}
                </div>
                <div style={{ flex: 1, position: "relative", minWidth: "200px" }}>
                  <Search size={16} style={{ position: "absolute", left: "12px", top: "50%", transform: "translateY(-50%)", color: "var(--muted)" }} />
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
                <div style={{ borderRadius: "12px", border: "1px solid var(--border)", overflowX: "auto" }}>
                  <table style={{ width: "100%", borderCollapse: "collapse" }}>
                    <thead>
                      <tr style={{ background: "var(--surface-muted)" }}>
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
                        const benefitText = describeCampaignBenefit(cam);

                        return (
                          <tr key={cam.campaignId} style={{ borderBottom: "1px solid var(--border-light)" }}>
                            <td style={tdStyle} onClick={() => openEditCampaign(cam)}>
                              <span style={{ fontFamily: "monospace", fontSize: "12px", color: "var(--primary)", fontWeight: "600", cursor: "pointer" }}>{cam.programCode}</span>
                            </td>
                            <td style={{ ...tdStyle, cursor: "pointer" }} onClick={() => openEditCampaign(cam)}>
                              <div style={{ fontWeight: "600", fontSize: "14px", color: "var(--text)", marginBottom: "4px" }}>{cam.name}</div>
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
                                <span style={badgeStyle("#8b5cf6")}>{typeLabels[normalizeCampaignType(cam.campaignType)] || cam.campaignType}</span>
                                {benefitText && (
                                  <span style={{ fontSize: "12px", fontWeight: "700", color: "var(--danger)" }}>{benefitText}</span>
                                )}
                              </div>
                            </td>
                            <td style={tdStyle}>
                              <div style={{ fontSize: "12px", display: "flex", flexDirection: "column", gap: "2px" }}>
                                {cam.schedule.absoluteStart || cam.schedule.absoluteEnd ? (
                                  <div>
                                    {formatDate(cam.schedule.absoluteStart)} - {formatDate(cam.schedule.absoluteEnd)}
                                  </div>
                                ) : <div style={{ color: "var(--muted)" }}>Không giới hạn ngày</div>}

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
                                  <div style={{ width: "100%", height: "4px", background: "var(--border)", borderRadius: "2px", overflow: "hidden" }}>
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
                                  <div style={{ width: "36px", height: "20px", background: cam.active ? "#10b981" : "var(--border)", borderRadius: "10px", position: "relative", transition: "0.2s" }}>
                                    <div style={{ width: "16px", height: "16px", background: "var(--surface)", borderRadius: "50%", position: "absolute", top: "2px", left: cam.active ? "18px" : "2px", transition: "0.2s" }} />
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
                                    background: "var(--surface-muted)",
                                    color: "var(--subtext)",
                                    border: "1px solid var(--border)",
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
              {/* Kiểm tra mã nhanh (tra toàn cửa hàng) */}
              <div style={{ background: "var(--surface-muted)", border: "1px solid var(--border)", borderRadius: "12px", padding: "12px 14px", marginBottom: "16px" }}>
                <div style={{ fontSize: "13px", fontWeight: "700", color: "var(--text)", marginBottom: "8px" }}>🔎 Kiểm tra mã</div>
                <form onSubmit={(e) => { e.preventDefault(); void handleCheckCode(); }} style={{ display: "flex", gap: "8px", flexWrap: "wrap" }}>
                  <input value={checkCode} onChange={(e) => { setCheckCode(e.target.value.toUpperCase()); setCheckResult(null); }}
                    placeholder="Nhập mã voucher, VD: TRAM8K2D"
                    aria-label="Mã voucher cần kiểm tra"
                    style={{ ...inputStyle, flex: 1, minWidth: "180px", fontFamily: "monospace", letterSpacing: "1px" }} />
                  <button type="submit" disabled={checking || !checkCode.trim()} style={btnPrimary}>{checking ? "Đang kiểm tra..." : "Kiểm tra"}</button>
                </form>
                {checkResult && (
                  <div role="status" style={{
                    marginTop: "8px", padding: "8px 12px", borderRadius: "8px", fontSize: "13px", fontWeight: "600",
                    background: checkResult.ok ? "var(--success-bg)" : "var(--danger-bg)",
                    color: checkResult.ok ? "#15803d" : "var(--danger)",
                  }}>
                    {checkResult.ok ? "✅ " : "⛔ "}{checkResult.message}
                  </div>
                )}
              </div>

              <div style={{ display: "flex", gap: "12px", marginBottom: "16px", alignItems: "center", flexWrap: "wrap" }}>
                <select value={selectedVoucherCampaign} onChange={(e) => { setSelectedVoucherCampaign(e.target.value); setVoucherSearch(""); }}
                  style={{ padding: "10px 12px", borderRadius: "8px", border: "1px solid #ddd", fontSize: "14px", flex: 1, minWidth: "220px", fontWeight: "600" }}>
                  <option value="">-- Chọn chương trình khuyến mãi để quản lý mã --</option>
                  {campaigns.map(c => (
                    <option key={c.campaignId} value={c.campaignId}>{c.programCode} - {c.name} {c.hasCodes ? "(Đã có mã)" : ""}</option>
                  ))}
                </select>
                <button onClick={() => {
                  setVoucherForm(emptyVoucherForm);
                  setFormError(""); setShowVoucherModal(true);
                }} style={btnPrimary} disabled={!selectedVoucherCampaign}>
                  <Plus size={16} /> Thêm mã voucher
                </button>
              </div>

              {selectedVoucherCampaign ? (
                <>
                  <div className="grid-2-sm" style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: "16px", marginBottom: "20px" }}>
                    <div style={{ background: "var(--surface-muted)", padding: "16px", borderRadius: "12px", border: "1px solid var(--border)" }}>
                      <div style={{ fontSize: "13px", color: "var(--muted)", fontWeight: "600" }}>Tổng mã</div>
                      <div style={{ fontSize: "24px", fontWeight: "800", color: "var(--text)" }}>{voucherStats.total}</div>
                    </div>
                    <div style={{ background: "var(--success-bg)", padding: "16px", borderRadius: "12px", border: "1px solid #bbf7d0" }}>
                      <div style={{ fontSize: "13px", color: "#166534", fontWeight: "600" }}>Chưa dùng</div>
                      <div style={{ fontSize: "24px", fontWeight: "800", color: "#15803d" }}>{voucherStats.unused}</div>
                    </div>
                    <div style={{ background: "var(--warning-bg)", padding: "16px", borderRadius: "12px", border: "1px solid #fef08a" }}>
                      <div style={{ fontSize: "13px", color: "#854d0e", fontWeight: "600" }}>Đã dùng</div>
                      <div style={{ fontSize: "24px", fontWeight: "800", color: "#a16207" }}>{voucherStats.used}</div>
                    </div>
                    <div style={{ background: "var(--danger-bg)", padding: "16px", borderRadius: "12px", border: "1px solid #fecaca" }}>
                      <div style={{ fontSize: "13px", color: "#991b1b", fontWeight: "600" }}>Đã hủy</div>
                      <div style={{ fontSize: "24px", fontWeight: "800", color: "var(--danger)" }}>{voucherStats.cancelled}</div>
                    </div>
                  </div>

                  <div style={{ position: "relative", marginBottom: "12px" }}>
                    <Search size={16} style={{ position: "absolute", left: "12px", top: "50%", transform: "translateY(-50%)", color: "var(--muted)" }} />
                    <input value={voucherSearch} onChange={(e) => setVoucherSearch(e.target.value)}
                      placeholder="Tìm mã voucher hoặc mã đơn..."
                      aria-label="Tìm mã voucher"
                      style={{ width: "100%", padding: "10px 12px 10px 36px", borderRadius: "8px", border: "1px solid #ddd", fontSize: "14px", boxSizing: "border-box" }} />
                  </div>

                  <div style={{ borderRadius: "12px", border: "1px solid var(--border)", overflowX: "auto" }}>
                    <table style={{ width: "100%", borderCollapse: "collapse" }}>
                      <thead>
                        <tr style={{ background: "var(--surface-muted)" }}>
                          {["Mã Voucher", "Trạng thái", "Đơn hàng", "Bàn", "Nhân viên", "Thời gian dùng", "Thao tác"].map((h) => (
                            <th key={h} style={thStyle}>{h}</th>
                          ))}
                        </tr>
                      </thead>
                      <tbody>
                        {visibleVouchers.map(v => {
                          const used = v.state === "REDEEMED";
                          return (
                            <tr key={v.voucherId} style={{ borderBottom: "1px solid var(--border-light)" }}>
                              <td style={tdStyle}><span style={{ fontFamily: "monospace", fontSize: "14px", fontWeight: "700", letterSpacing: "1px", color: "var(--primary)" }}>{v.code}</span></td>
                              <td style={tdStyle}>
                                <span style={badgeStyle(voucherStatusColor(v, nowTs))}>{voucherStatusText(v, nowTs)}</span>
                                {v.state === "CANCELLED" && v.cancelledAt ? <div style={{ fontSize: "11px", color: "var(--muted)", marginTop: "2px" }}>{formatDateTime(v.cancelledAt)}</div> : null}
                              </td>
                              <td style={tdStyle}>{used ? <span style={{ fontFamily: "monospace", fontWeight: 600 }}>{v.billRef || "—"}</span> : "—"}</td>
                              <td style={tdStyle}>{used ? (v.tableName || "—") : "—"}</td>
                              <td style={tdStyle}>{used ? (v.redeemedBy || "—") : "—"}</td>
                              <td style={tdStyle}>{used ? formatDateTime(v.redeemedAt) : "—"}</td>
                              <td style={tdStyle}>
                                {canCancelVoucher(v, nowTs) && (
                                  <button onClick={() => handleCancelVoucher(v)}
                                    style={{ padding: "4px 8px", fontSize: "12px", borderRadius: "4px", background: "var(--danger-bg)", color: "#ef4444", border: "none", cursor: "pointer" }}>Hủy mã</button>
                                )}
                              </td>
                            </tr>
                          );
                        })}
                        {visibleVouchers.length === 0 && (
                          <tr><td colSpan={7} style={{ textAlign: "center", padding: "24px", color: "var(--muted)" }}>{vouchers.length === 0 ? "Chưa có mã voucher nào." : "Không tìm thấy mã phù hợp."}</td></tr>
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
          <div className="grid-stack-sm" style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "12px", maxHeight: "72vh", overflowY: "auto", paddingRight: "8px" }}>
            <div style={{ gridColumn: "1 / -1" }}>
              <FormField label="Tên chương trình *" value={campaignForm.name} onChange={(v) => setCampaignForm({ ...campaignForm, name: v })} placeholder="VD: Khuyến mãi Trà Sữa Giờ Vàng" />
            </div>
            <FormField label="Mã KM (tự động nếu để trống)" value={campaignForm.programCode} onChange={(v) => setCampaignForm({ ...campaignForm, programCode: v })} disabled={!!editingCampaign} placeholder="VD: KM0001" />
            <div>
              <label style={labelStyle}>Loại KM</label>
              <select value={campaignForm.campaignType} onChange={(e) => setCampaignForm({ ...campaignForm, campaignType: normalizeCampaignType(e.target.value) })} style={inputStyle} disabled={!!editingCampaign}>
                {Object.entries(typeLabels).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
              </select>
            </div>
            
            {/* 1. Cấu hình Ưu đãi & Giảm giá */}
            <div style={{ gridColumn: "1 / -1", borderTop: "1px solid #eee", paddingTop: "12px", marginTop: "4px" }}>
              <div style={{ fontSize: "14px", fontWeight: "700", marginBottom: "8px", color: "var(--primary)" }}>🎁 Cấu hình Ưu đãi & Giảm giá</div>
              {campaignForm.campaignType === "BILLDISCOUNT" && (
                <div className="grid-stack-sm" style={benefitBox}>
                  <div style={{ gridColumn: "1 / -1", fontSize: "12px", color: "var(--subtext)" }}>
                    Áp dụng cho toàn bộ hóa đơn (không cần chọn hàng hóa).
                  </div>
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
                    placeholder={campaignForm.discountType === "PERCENT" ? "VD: 10 (có thể 2.5)" : "VD: 20000"}
                  />
                  <FormField
                    label="Giảm tối đa (VND — để trống nếu không giới hạn)"
                    value={campaignForm.maxDiscount}
                    onChange={(v) => setCampaignForm({ ...campaignForm, maxDiscount: v })}
                    type="number"
                    placeholder="VD: 50000"
                  />
                  <FormField
                    label="Đơn hàng từ (VND — để trống nếu mọi đơn)"
                    value={campaignForm.threshold}
                    onChange={(v) => setCampaignForm({ ...campaignForm, threshold: v })}
                    type="number"
                    placeholder="VD: 100000"
                  />
                </div>
              )}
              {campaignForm.campaignType === "ITEMPRICERULE" && (
                <div style={{ background: "var(--surface-muted)", padding: "12px", borderRadius: "8px", border: "1px solid #fecdd3" }}>
                  <FormField label="Giá đồng giá (VND) *" value={campaignForm.fixedPriceValue} onChange={(v) => setCampaignForm({ ...campaignForm, fixedPriceValue: v })} type="number" placeholder="VD: 25000" />
                </div>
              )}
              {campaignForm.campaignType === "ORDERVALUEITEMBENEFIT" && (
                <div className="grid-stack-sm" style={benefitBox}>
                  <div style={{ gridColumn: "1 / -1" }}>
                    <FormField
                      label="Áp dụng khi đơn hàng từ (VND) *"
                      value={campaignForm.threshold}
                      onChange={(v) => setCampaignForm({ ...campaignForm, threshold: v })}
                      type="number"
                      placeholder="VD: 200000"
                    />
                  </div>
                  <RewardEditor form={campaignForm} setForm={setCampaignForm} products={products} title="Món được tặng/giảm giá" />
                </div>
              )}
              {campaignForm.campaignType === "BUYXGETY" && (
                <div className="grid-stack-sm" style={benefitBox}>
                  <div style={{ gridColumn: "1 / -1" }}>
                    <ItemMultiPicker
                      label={`🛒 Món mua X (${campaignForm.buyItemIds.length}) *`}
                      color="#1e40af"
                      products={products}
                      selected={campaignForm.buyItemIds}
                      onChange={(ids) => setCampaignForm(prev => ({ ...prev, buyItemIds: ids }))}
                      emptyText="Chưa chọn món X"
                    />
                  </div>
                  <FormField label="Số lượng X cần mua *" value={campaignForm.buyQty} onChange={(v) => setCampaignForm({ ...campaignForm, buyQty: v })} type="number" placeholder="VD: 2" />
                  <div />
                  <RewardEditor form={campaignForm} setForm={setCampaignForm} products={products} title="Món Y được tặng/giảm giá" />
                  <label style={{ gridColumn: "1 / -1", display: "flex", alignItems: "flex-start", gap: "10px", cursor: "pointer" }}>
                    <input type="checkbox" checked={campaignForm.multiplyByBundle}
                      onChange={(e) => setCampaignForm({ ...campaignForm, multiplyByBundle: e.target.checked })}
                      style={{ marginTop: "3px", width: "16px", height: "16px" }} />
                    <div>
                      <div style={{ fontSize: "13px", fontWeight: "700", color: "var(--text)" }}>Áp dụng số món Y tặng theo số món X bán ra</div>
                      <div style={{ fontSize: "12px", color: "var(--subtext)", marginTop: "2px" }}>
                        {campaignForm.multiplyByBundle
                          ? `Đang tích: cứ mỗi ${campaignForm.buyQty || "?"} X sẽ được ${campaignForm.rewardQty || "?"} Y (mua gấp đôi X → được gấp đôi Y).`
                          : `Bỏ tích: mua ${campaignForm.buyQty || "?"} hay nhiều X hơn cũng chỉ được tặng/giảm ${campaignForm.rewardQty || "?"} Y trên mỗi hóa đơn.`}
                      </div>
                    </div>
                  </label>
                </div>
              )}
            </div>

            {/* 2. Phạm vi áp dụng món & nhóm hàng — chỉ cho Đồng giá (Giảm giá đơn hàng áp dụng toàn bộ hóa đơn) */}
            {campaignForm.campaignType === "ITEMPRICERULE" && (
            <div style={{ gridColumn: "1 / -1", borderTop: "1px solid #eee", paddingTop: "12px", marginTop: "4px" }}>
              <div style={{ fontSize: "14px", fontWeight: "700", marginBottom: "8px", color: "#1e3a8a" }}>📦 Phạm vi áp dụng món / nhóm hàng</div>
              <div style={{ fontSize: "12px", color: "var(--muted)", marginBottom: "8px" }}>
                Nếu để trống cả 2 mục, ưu đãi sẽ được áp dụng cho toàn bộ menu.
              </div>

              {/* Nhóm hàng */}
              <div style={{ marginBottom: "12px", background: "var(--surface-muted)", padding: "10px", borderRadius: "8px", border: "1px solid var(--border)" }}>
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
                      style={{ padding: "6px 12px", fontSize: "12px", border: "1px solid var(--border)", borderRadius: "6px", background: "var(--surface)", cursor: "pointer", color: "var(--muted)" }}
                    >
                      Bỏ chọn tất cả
                    </button>
                  )}
                </div>
                {campaignForm.includedGroupIds.length > 0 ? (
                  <div style={{ display: "flex", flexWrap: "wrap", gap: "6px" }}>
                    {campaignForm.includedGroupIds.map(g => (
                      <span key={g} style={{ display: "inline-flex", alignItems: "center", gap: "6px", padding: "4px 10px", background: "var(--info-bg)", color: "#1e40af", borderRadius: "16px", fontSize: "12px", fontWeight: "600" }}>
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
                  <div style={{ fontSize: "12px", color: "var(--muted)", fontStyle: "italic" }}>Tất cả nhóm hàng (mặc định)</div>
                )}
              </div>

              {/* Món hàng */}
              <ItemMultiPicker
                label={`📦 Món hàng áp dụng (${campaignForm.includedItemIds.length})`}
                color="#b45309"
                products={products}
                selected={campaignForm.includedItemIds}
                onChange={(ids) => setCampaignForm(prev => ({ ...prev, includedItemIds: ids }))}
                emptyText="Tất cả món hàng (mặc định)"
              />
            </div>
            )}

            {/* 3. Lịch trình, Ngày trong tuần & Happy Hours */}
            <div style={{ gridColumn: "1 / -1", borderTop: "1px solid #eee", paddingTop: "12px", marginTop: "4px" }}>
              <div style={{ fontSize: "14px", fontWeight: "700", marginBottom: "8px", color: "#065f46" }}>⏰ Lịch trình & Khung giờ áp dụng (Happy hours)</div>
            </div>
            <FormField label="Ngày bắt đầu" value={campaignForm.startDate} onChange={(v) => setCampaignForm({ ...campaignForm, startDate: v })} type="datetime-local" />
            <FormField label="Ngày kết thúc" value={campaignForm.endDate} onChange={(v) => setCampaignForm({ ...campaignForm, endDate: v })} type="datetime-local" />

            {/* Ngày trong tuần */}
            <div style={{ gridColumn: "1 / -1", background: "var(--success-bg)", padding: "12px", borderRadius: "8px", border: "1px solid #bbf7d0" }}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "8px", flexWrap: "wrap", gap: "4px" }}>
                <label style={{ ...labelStyle, color: "#166534", margin: 0 }}>
                  📅 Ngày áp dụng trong tuần: {campaignForm.daysOfWeek.length === 0 || campaignForm.daysOfWeek.length === 7 ? "Tất cả các ngày (T2 - CN)" : `${campaignForm.daysOfWeek.length} ngày đã chọn`}
                </label>
                <div style={{ display: "flex", gap: "6px" }}>
                  <button
                    type="button"
                    onClick={() => setCampaignForm(prev => ({ ...prev, daysOfWeek: [1, 2, 3, 4, 5, 6, 7] }))}
                    style={{ padding: "3px 8px", fontSize: "11px", borderRadius: "4px", border: "1px solid #86efac", background: "var(--surface)", cursor: "pointer", color: "#15803d" }}
                  >
                    Tất cả (T2-CN)
                  </button>
                  <button
                    type="button"
                    onClick={() => setCampaignForm(prev => ({ ...prev, daysOfWeek: [1, 2, 3, 4, 5] }))}
                    style={{ padding: "3px 8px", fontSize: "11px", borderRadius: "4px", border: "1px solid #86efac", background: "var(--surface)", cursor: "pointer", color: "#15803d" }}
                  >
                    T2 - T6
                  </button>
                  <button
                    type="button"
                    onClick={() => setCampaignForm(prev => ({ ...prev, daysOfWeek: [6, 7] }))}
                    style={{ padding: "3px 8px", fontSize: "11px", borderRadius: "4px", border: "1px solid #86efac", background: "var(--surface)", cursor: "pointer", color: "#15803d" }}
                  >
                    Cuối tuần (T7, CN)
                  </button>
                  <button
                    type="button"
                    onClick={() => setCampaignForm(prev => ({ ...prev, daysOfWeek: [] }))}
                    style={{ padding: "3px 8px", fontSize: "11px", borderRadius: "4px", border: "1px solid var(--border)", background: "var(--surface)", cursor: "pointer", color: "var(--muted)" }}
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
                        border: isSelected ? "2px solid #16a34a" : "1px solid var(--border)",
                        background: isSelected ? "#16a34a" : "var(--surface)",
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
            <div style={{ gridColumn: "1 / -1", background: "var(--info-bg)", padding: "12px", borderRadius: "8px", border: "1px solid #ddd6fe" }}>
              <div style={{ display: "flex", flexWrap: "wrap", rowGap: "8px", justifyContent: "space-between", alignItems: "center", marginBottom: "8px" }}>
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
                    <div key={idx} style={{ display: "flex", alignItems: "center", gap: "10px", background: "var(--surface)", padding: "8px 12px", borderRadius: "6px", border: "1px solid #e9d5ff" }}>
                      <span style={{ fontSize: "13px", fontWeight: "600", color: "#6b21a8", minWidth: "60px" }}>Ca #{idx + 1}</span>
                      <div style={{ display: "flex", alignItems: "center", gap: "6px" }}>
                        <span style={{ fontSize: "12px", color: "var(--subtext)" }}>Từ:</span>
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
                        <span style={{ fontSize: "12px", color: "var(--subtext)" }}>Đến:</span>
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
                        style={{ marginLeft: "auto", padding: "4px 8px", background: "var(--danger-bg)", color: "#ef4444", border: "none", borderRadius: "4px", fontSize: "12px", cursor: "pointer" }}
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
            <div style={{ gridColumn: "1 / -1", background: "var(--warning-bg)", border: "1px solid #fef08a", borderRadius: "8px", padding: "12px 14px", marginTop: "4px" }}>
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
                Phát hành mã (khách nhập mã voucher)
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
            
            {campaignForm.hasCodes && (
              <div style={{ gridColumn: "1 / -1", background: "var(--surface-muted)", border: "1px solid var(--border)", borderRadius: "8px", padding: "12px" }}>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: "8px", marginBottom: "8px" }}>
                  <div style={{ fontSize: "13px", fontWeight: "700", color: "var(--text)" }}>🎫 Mã voucher của chương trình</div>
                  {editingCampaign && (
                    <button type="button" onClick={() => { setShowCampaignModal(false); setSelectedVoucherCampaign(editingCampaign.campaignId); setActiveTab("vouchers"); }}
                      style={{ padding: "4px 10px", fontSize: "12px", borderRadius: "6px", border: "1px solid var(--border)", background: "var(--surface)", cursor: "pointer", color: "var(--primary)", fontWeight: 600 }}>
                      Xem danh sách mã đã phát hành →
                    </button>
                  )}
                </div>
                <div style={{ fontSize: "12px", color: "var(--subtext)", marginBottom: "8px" }}>
                  {editingCampaign ? "Thêm mã mới (để trống nếu không thêm). " : "Có thể để trống và thêm mã sau ở tab Mã Voucher. "}
                  Mã trùng với mã đã có sẽ bị từ chối.
                </div>
                {renderVoucherCodeInputs()}
              </div>
            )}

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
        <Modal title="Thêm mã Voucher" onClose={() => setShowVoucherModal(false)}>
          {renderVoucherCodeInputs()}
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
/** Chọn nhiều món (select + chip). */
function ItemMultiPicker({ label, color, products, selected, onChange, emptyText }: {
  label: string; color: string; products: ProductItem[]; selected: string[];
  onChange: (ids: string[]) => void; emptyText: string;
}) {
  return (
    <div style={{ background: "var(--surface-muted)", padding: "10px", borderRadius: "8px", border: "1px solid var(--border)" }}>
      <label style={{ ...labelStyle, color }}>{label}</label>
      <div style={{ display: "flex", gap: "8px", alignItems: "center", marginBottom: "8px" }}>
        <select
          style={{ ...inputStyle, flex: 1 }}
          value=""
          aria-label={label}
          onChange={(e) => {
            const id = String(e.target.value);
            if (id && !selected.includes(id)) onChange([...selected, id]);
          }}
        >
          <option value="">-- Bấm để thêm món --</option>
          {products.filter(p => !selected.includes(String(p.id))).map(p => (
            <option key={p.id} value={String(p.id)}>{p.name} {p.price ? `(${formatVND(p.price)})` : ""} {p.category ? `• ${p.category}` : ""}</option>
          ))}
        </select>
        {selected.length > 0 && (
          <button type="button" onClick={() => onChange([])}
            style={{ padding: "6px 12px", fontSize: "12px", border: "1px solid var(--border)", borderRadius: "6px", background: "var(--surface)", cursor: "pointer", color: "var(--muted)" }}>
            Bỏ chọn tất cả
          </button>
        )}
      </div>
      {selected.length > 0 ? (
        <div style={{ display: "flex", flexWrap: "wrap", gap: "6px", maxHeight: "120px", overflowY: "auto" }}>
          {selected.map(id => {
            const prod = products.find(p => String(p.id) === String(id));
            return (
              <span key={id} style={{ display: "inline-flex", alignItems: "center", gap: "6px", padding: "4px 10px", background: "var(--warning-bg)", color: "#92400e", borderRadius: "16px", fontSize: "12px", fontWeight: "600" }}>
                📦 {prod ? prod.name : id}
                <button type="button" aria-label={`Bỏ ${prod ? prod.name : id}`} onClick={() => onChange(selected.filter(x => x !== id))}
                  style={{ border: "none", background: "none", cursor: "pointer", color: "#92400e", fontWeight: "bold", fontSize: "14px", lineHeight: 1 }}>×</button>
              </span>
            );
          })}
        </div>
      ) : (
        <div style={{ fontSize: "12px", color: "var(--muted)", fontStyle: "italic" }}>{emptyText}</div>
      )}
    </div>
  );
}

/** Món thưởng Y + số lượng + hình thức (tặng / giảm % / giảm tiền) — dùng cho GTĐ và Mua X. */
function RewardEditor({ form, setForm, products, title }: {
  form: CampaignFormState;
  setForm: React.Dispatch<React.SetStateAction<CampaignFormState>>;
  products: ProductItem[];
  title: string;
}) {
  return (
    <>
      <div style={{ gridColumn: "1 / -1" }}>
        <ItemMultiPicker
          label={`🎁 ${title} (${form.rewardItemIds.length}) *`}
          color="#b45309"
          products={products}
          selected={form.rewardItemIds}
          onChange={(ids) => setForm(prev => ({ ...prev, rewardItemIds: ids }))}
          emptyText="Chưa chọn món"
        />
      </div>
      <FormField label="Số lượng món được tặng/giảm *" value={form.rewardQty} onChange={(v) => setForm(prev => ({ ...prev, rewardQty: v }))} type="number" placeholder="VD: 1" />
      <div>
        <label style={labelStyle}>Hình thức ưu đãi *</label>
        <select value={form.rewardBenefit} onChange={(e) => setForm(prev => ({ ...prev, rewardBenefit: e.target.value as RewardBenefit }))} style={inputStyle}>
          {(Object.keys(REWARD_BENEFIT_LABELS) as RewardBenefit[]).map(k => <option key={k} value={k}>{REWARD_BENEFIT_LABELS[k]}</option>)}
        </select>
      </div>
      {form.rewardBenefit !== "FREEITEM" && (
        <FormField
          label={form.rewardBenefit === "PERCENT" ? "Giảm (%) mỗi món *" : "Giảm (VND) mỗi món *"}
          value={form.rewardValue}
          onChange={(v) => setForm(prev => ({ ...prev, rewardValue: v }))}
          type="number"
          placeholder={form.rewardBenefit === "PERCENT" ? "VD: 50" : "VD: 10000"}
        />
      )}
    </>
  );
}

function EmptyState({ icon, text, sub }: { icon: string; text: string; sub: string }) {
  return (
    <div style={{ textAlign: "center", padding: "60px 20px" }}>
      <div style={{ fontSize: "48px", marginBottom: "12px" }}>{icon}</div>
      <div style={{ fontSize: "16px", fontWeight: "600", color: "var(--text)" }}>{text}</div>
      <div style={{ fontSize: "13px", color: "var(--muted)", marginTop: "6px" }}>{sub}</div>
    </div>
  );
}

function Modal({ title, children, onClose }: { title: string; children: React.ReactNode; onClose: () => void }) {
  return (
    <div style={{ position: "fixed", inset: 0, background: "rgba(0,0,0,0.5)", display: "flex", alignItems: "center", justifyContent: "center", zIndex: 100 }} onClick={onClose}>
      <div style={{ background: "var(--surface)", borderRadius: "16px", padding: "24px", width: "90%", maxWidth: "780px", maxHeight: "90vh", display: "flex", flexDirection: "column", boxShadow: "0 20px 60px rgba(0,0,0,0.3)" }} onClick={(e) => e.stopPropagation()}>
        <h3 style={{ fontSize: "18px", fontWeight: "700", marginBottom: "16px", color: "var(--text)" }}>{title}</h3>
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
const benefitBox: React.CSSProperties = {
  display: "grid", gridTemplateColumns: "1fr 1fr", gap: "12px", background: "var(--surface-muted)",
  padding: "12px", borderRadius: "8px", border: "1px solid #fecdd3",
};
