"use client";
import Image from "next/image";
import Link from "next/link";
import { Suspense, useState, useMemo, useCallback, useEffect, type CSSProperties } from "react";
import { useSearchParams } from "next/navigation";
import { db } from "@/lib/firebase";
import { onValue, ref, update } from "firebase/database";
import {
  Search,
  Plus,
  Edit2,
  Trash2,
  X,
  Check,
  Users,
  Clock,
  Receipt,
  LayoutGrid,
  List,
  UtensilsCrossed,
  Printer,
  CheckCircle2,
  Banknote,
  QrCode,
  Bookmark,
  Phone,
  DollarSign,
  XCircle,
  Minus,
  Percent,
  ArrowRightLeft,
  GitMerge,
  KeyRound,
  Settings2,
  ChefHat,
} from "lucide-react";

interface OrderItem {
  id?: number;
  productId?: number;
  name: string;
  price: number;
  quantity?: number;
  count?: number;
  unit?: string;
  category?: string;
  selectedSize?: string;
  selectedToppings?: unknown[];
  sizeExtraPrice?: number;
  toppingPrice?: number;
  discountAmount?: number;
  note?: string;
  imageBase64?: string;
  isSentKitchen?: boolean;
}

interface Table {
  id: string;
  storeCode?: string;
  storeName?: string;
  name: string;
  zone: string;
  inUse: boolean;
  guestCount?: number;
  openedAt?: string | null;
  currentOrderJson?: string;
  currentBillId?: string | null;
  currentOrderCode?: string | null;
  actionLogsJson?: string | null;
  prePrintedAt?: number | null;
  prePrintedBy?: string | null;
  /** Khách tích điểm gắn với bàn (hợp đồng chung với Flutter) */
  customerId?: string | null;
  customerName?: string | null;
  customerPhone?: string | null;
  isReserved?: boolean;
  reservationCustomer?: string;
  reservationPhone?: string;
  reservationTime?: string;
  reservationDeposit?: number;
  [key: string]: unknown;
}

interface TableFormData {
  name: string;
  zone: string;
}

const emptyForm: TableFormData = {
  name: "",
  zone: "",
};

import { useDashboardData, resolveWriteStoreCode } from "@/lib/data-context";
import { errorMessage } from "@/lib/errors";
import { buildTableBillHtml } from "@/lib/print-html";
import { lineDiscountLabel, lineDiscountTotal, lineQuantity, lineUnitPrice, parseOrderJson, setLineQuantity, summarizeOrderLines, toppingLabel, type RawOrderLine } from "@/lib/order-math";
import PromotionPanel, { usePromotions } from "@/components/PromotionPanel";
import { deriveTableStatus, prePrintedAtOf, tableCustomerOf, TABLE_STATUS_META, TABLE_STATUS_ORDER, type TableStatus } from "@/lib/table-status";
import { hasPermission, useAuth } from "@/lib/auth";
import LineDiscountDialog from "@/components/LineDiscountDialog";
import DeleteItemDialog from "@/components/DeleteItemDialog";
import { applyLineRemoval, buildDeletionEntry, deletionDetails, type DeletedItemEntry } from "@/lib/item-deletion";
import ManagerPinDialog, { SetApprovalPinDialog } from "@/components/ManagerPinDialog";
import TableTransferDialog from "@/components/TableTransferDialog";
import ZoneSetupDialog from "@/components/ZoneSetupDialog";
import { parseZoneMeta, sortZoneNames, type ZoneMeta } from "@/lib/zones";
import WebOrderDialog from "@/components/WebOrderDialog";
import { useItemCatalog } from "@/lib/note-catalog";
import { canAdjustPoints as canManageLayout, canEditPointConfig, canReadCustomers } from "@/lib/customers";
import CustomerPickerDialog from "@/components/CustomerPickerDialog";
import LoyaltyPanel from "@/components/LoyaltyPanel";
import { useBranchLoyalty, useLoyaltyEarnRetry, useMemberBalance } from "@/lib/use-branch-loyalty";
import {
  buildPointsPreview,
  maxRedeemablePoints,
  tableCustomerPayload,
  toPickerCustomers,
  type BillCustomer,
  type PickerCustomer,
} from "@/lib/loyalty-checkout";
import { buildNewCustomerNode } from "@/lib/loyalty";
import { applyLoyaltyEarn } from "@/lib/loyalty-client";
import { earnQueueKey, earnWithRetry } from "@/lib/loyalty-earn-queue";
import {
  approverOptions,
  canUserApprove,
  isApprovalValid,
  withApprovalMeta,
  type ApprovalAction,
  type ManagerApproval,
} from "@/lib/manager-approval";

/** Thời điểm hiện tại cho các handler sự kiện (tách riêng để không bị coi là gọi hàm không thuần khi render) */
const nowMs = () => Date.now();

export default function TablesPage() {
  // useSearchParams (nút "Chế độ Order" ở thanh bên dùng ?order=1) cần Suspense để trang vẫn build tĩnh được
  return (
    <Suspense fallback={null}>
      <TablesPageContent />
    </Suspense>
  );
}

function TablesPageContent() {
  const {
    tables,
    loading: ctxLoading,
    currentStoreCode,
    currentStore,
    stores,
    checkoutAndFreeTable,
    cancelActiveTable,
    saveTable,
    deleteTable,
    updateTableOrderItems,
    submitWebOrder,
    products,
    allCategories,
    transferTable,
    mergeTables,
    markTablePrePrinted,
    usersList,
  } = useDashboardData();
  const { user } = useAuth();
  // Giống Flutter: giảm giá dòng cần DISCOUNT_ITEM (alias MANUAL_DISCOUNT);
  // giảm số lượng món đã gửi bếp cần CANCEL_KITCHEN_ITEM.
  const canDiscountItem = hasPermission(user, "DISCOUNT_ITEM");
  const canCancelKitchenItem = hasPermission(user, "CANCEL_KITCHEN_ITEM");
  // Giống Flutter: chuyển bàn = CHANGE_TABLE ("Đổi bàn / Chuyển khu vực"), gộp bàn = MERGE_SPLIT_TABLE
  const canTransferTable = hasPermission(user, "CHANGE_TABLE");
  const canMergeTable = hasPermission(user, "MERGE_SPLIT_TABLE");
  // Bấm đơn trên web (dự phòng POS): mở bàn/gọi món = OPEN_TABLE, gửi bếp = SEND_KITCHEN
  const canOrderOnWeb = hasPermission(user, "OPEN_TABLE");
  const canSendKitchenFromWeb = hasPermission(user, "SEND_KITCHEN");
  // Quản lý / chủ quán có thể tự đặt PIN duyệt
  const canSetApprovalPin = !!user && canUserApprove({ ...user }, "DISCOUNT_ITEM") && hasPermission(user, "MANAGE_MANAGER_PIN");
  const canDeleteItem = hasPermission(user, "DELETE_ITEM");
  const loading = ctxLoading && tables.length === 0;
  const [selectedZone, setSelectedZone] = useState<string>("ALL");
  const [statusFilter, setStatusFilter] = useState<"ALL" | TableStatus>("ALL");
  const [viewMode, setViewMode] = useState<"grid" | "list">("grid");
  const [search, setSearch] = useState("");
  
  // Ghim / thứ tự khu (stores/{code}/zones) — đồng bộ với app; "ALL" (nhiều chi nhánh) thì xếp theo tên
  const [zoneMeta, setZoneMeta] = useState<ZoneMeta[]>([]);
  useEffect(() => {
    setZoneMeta([]);
    if (!currentStoreCode || currentStoreCode === "ALL") return;
    const off = onValue(
      ref(db, `stores/${currentStoreCode}/zones`),
      (snap) => setZoneMeta(parseZoneMeta(snap.val())),
      () => setZoneMeta([])
    );
    return () => off();
  }, [currentStoreCode]);

  const zones = useMemo(() => {
    const unique = Array.from(new Set(tables.map((t) => t.zone).filter(Boolean))) as string[];
    return sortZoneNames(unique, zoneMeta);
  }, [tables, zoneMeta]);
  
  // Modals
  const [showModal, setShowModal] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [form, setForm] = useState<TableFormData>(emptyForm);
  const [saving, setSaving] = useState(false);
  const [deleteId, setDeleteId] = useState<string | null>(null);
  const [error, setError] = useState("");

  // Order Details Modal & Payment
  const [pickedTableForOrder, setSelectedTableForOrder] = useState<Table | null>(null);
  const [completingPayment, setCompletingPayment] = useState(false);
  const [paymentMethod, setPaymentMethod] = useState<"CASH" | "TRANSFER">("CASH");
  const [checkoutToast, setCheckoutToast] = useState<string | null>(null);
  // Giảm giá dòng: chụp lại JSON đơn lúc mở hộp thoại để ghi đúng dòng (và phát hiện xung đột)
  const [discountTarget, setDiscountTarget] = useState<{ orderJson: string; index: number } | null>(null);
  const [lineSaving, setLineSaving] = useState(false);
  const [lineError, setLineError] = useState("");
  // Quản lý duyệt bằng PIN (khi thiếu DISCOUNT_ITEM / CANCEL_KITCHEN_ITEM)
  const [discountApproval, setDiscountApproval] = useState<ManagerApproval | null>(null);
  const [pinRequest, setPinRequest] = useState<{
    action: ApprovalAction;
    storeCode: string;
    context: string;
    onApproved: (a: ManagerApproval) => void;
  } | null>(null);
  const [showSetPin, setShowSetPin] = useState(false);
  const [showZoneSetup, setShowZoneSetup] = useState(false);
  // Chế độ Order: chạm vào bàn là mở ngay màn gọi món (bàn trống → mở bàn, bàn có khách → thêm món)
  const orderParam = useSearchParams().get("order");
  const [orderModeOverride, setOrderModeOverride] = useState<boolean | null>(null);
  const orderModeStored = (() => {
    try {
      return typeof window !== "undefined" && window.localStorage.getItem("tram_order_mode") === "1";
    } catch {
      return false;
    }
  })();
  const orderMode = canOrderOnWeb && (orderModeOverride ?? (orderParam === "1" || (orderParam === null && orderModeStored)));
  const toggleOrderMode = () => {
    const next = !orderMode;
    setOrderModeOverride(next);
    try {
      window.localStorage.setItem("tram_order_mode", next ? "1" : "0");
    } catch {
      // trình duyệt chặn lưu — vẫn đổi chế độ trong phiên này
    }
  };
  const [orderTarget, setOrderTarget] = useState<Table | null>(null);
  const [orderSaving, setOrderSaving] = useState(false);
  const [orderError, setOrderError] = useState("");
  // Xóa món / giảm số lượng (bắt buộc lý do — hợp đồng chung với Flutter)
  const [removalTarget, setRemovalTarget] = useState<{ table: Table; orderJson: string; index: number; initialQty: number } | null>(null);
  // Chuyển / gộp bàn
  const [tableOp, setTableOp] = useState<{ kind: "TRANSFER" | "MERGE"; source: Table } | null>(null);
  const [tableOpBusy, setTableOpBusy] = useState(false);
  const [tableOpError, setTableOpError] = useState("");

  // Bàn đang xem luôn lấy bản mới nhất từ danh sách realtime; bàn đã được giải phóng thì đóng modal
  const selectedTableForOrder = useMemo<Table | null>(() => {
    if (!pickedTableForOrder) return null;
    const updated = tables.find((t) => t.id === pickedTableForOrder.id || t.name === pickedTableForOrder.name);
    if (!updated) return pickedTableForOrder;
    return updated.inUse ? updated : null;
  }, [pickedTableForOrder, tables]);

  // Khuyến mãi / voucher cho bàn đang thanh toán (nhân viên tự chọn hoặc nhập mã — không tự áp dụng)
  const promoStoreCode = selectedTableForOrder ? selectedTableForOrder.storeCode || resolveWriteStoreCode(currentStoreCode) : "";
  const promoItems = useMemo(() => parseOrderJson(selectedTableForOrder?.currentOrderJson), [selectedTableForOrder?.currentOrderJson]);
  const categoryById = useMemo(() => new Map(products.map((p) => [String(p.id), p.category])), [products]);
  const promoGroupOf = useCallback(
    (it: RawOrderLine) => categoryById.get(String(it.productId ?? it.id ?? "")) ?? (typeof it.category === "string" ? it.category : null),
    [categoryById]
  );
  const promoStore = stores.find((s) => s.storeCode === promoStoreCode) || currentStore;
  const promo = usePromotions({
    storeCode: promoStoreCode,
    tableKey: selectedTableForOrder ? `${promoStoreCode}/${selectedTableForOrder.id}` : "",
    items: promoItems,
    groupOf: promoGroupOf,
    guestCount: selectedTableForOrder?.guestCount,
    allowStack: promoStore?.allowStackPromotions ?? true,
  });
  const canApplyPromotion = hasPermission(user, "APPLY_PROMOTION");

  // Khách hàng + tích điểm (giống giỏ hàng Flutter): chọn khách gắn vào bàn, xem điểm sẽ tích, dùng điểm
  const canViewCustomers = hasPermission(user, "VIEW_CUSTOMERS");
  const canManageCustomers = hasPermission(user, "MANAGE_CUSTOMERS");
  const canRedeemPoints = hasPermission(user, "REDEEM_POINTS");
  const roleReadsCustomers = canReadCustomers(user?.roleId || user?.role, user?.isRootOwner);
  const loyaltyAvailable = (canViewCustomers || canManageCustomers) && roleReadsCustomers;
  const isLoyaltyOwner = canEditPointConfig(user?.roleId || user?.role, user?.isRootOwner) && hasPermission(user, "MANAGE_LOYALTY");
  const loy = useBranchLoyalty({ storeCode: promoStoreCode, enabled: !!selectedTableForOrder && loyaltyAvailable, store: promoStore });
  const tableCust = selectedTableForOrder ? tableCustomerOf(selectedTableForOrder) : {};
  const billCustomer: BillCustomer | null = tableCust.customerId
    ? { id: tableCust.customerId, name: tableCust.customerName, phone: tableCust.customerPhone }
    : null;
  const localCustomer = billCustomer ? loy.customers.find((c) => c.id === billCustomer.id) : undefined;
  const [balanceTick, setBalanceTick] = useState(0);
  const balance = useMemberBalance(
    promoStoreCode,
    loyaltyAvailable && billCustomer ? billCustomer.id : "",
    localCustomer?.diemHienTai ?? 0,
    localCustomer?.tongDiem ?? 0,
    balanceTick
  );
  const [pointsState, setPointsState] = useState<{ key: string; n: number }>({ key: "", n: 0 });
  const pointsKey = selectedTableForOrder && billCustomer ? `${promoStoreCode}/${selectedTableForOrder.id}/${billCustomer.id}` : "";
  const amountBeforePoints = Math.max(0, calculateTableTotalFor(selectedTableForOrder) - promo.total);
  const pointsUsedNow =
    canRedeemPoints && loyaltyAvailable && billCustomer && pointsState.key === pointsKey
      ? Math.min(pointsState.n, maxRedeemablePoints(balance.points, amountBeforePoints, loy.rates.redeemRate))
      : 0;
  const pointsDiscountNow = pointsUsedNow * loy.rates.redeemRate;
  const [showCustomerPicker, setShowCustomerPicker] = useState(false);
  const [loyaltyBusy, setLoyaltyBusy] = useState(false);
  const [loyaltyWarn, setLoyaltyWarn] = useState<string | null>(null);
  useLoyaltyEarnRetry(user?.username, (n) => {
    setCheckoutToast(`Đã cộng bù điểm cho ${n} hóa đơn trước đó.`);
    setTimeout(() => setCheckoutToast(null), 6000);
  });

  const filtered = useMemo(() => {
    return tables.filter((t) => {
      const matchZone = selectedZone === "ALL" || t.zone === selectedZone;
      const matchSearch =
        !search ||
        t.name.toLowerCase().includes(search.toLowerCase()) ||
        (t.zone && t.zone.toLowerCase().includes(search.toLowerCase()));
      const matchStatus = statusFilter === "ALL" || deriveTableStatus(t) === statusFilter;
      return matchZone && matchSearch && matchStatus;
    });
  }, [tables, selectedZone, search, statusFilter]);

  // Statistics
  const inUseCount = useMemo(() => tables.filter((t) => t.inUse).length, [tables]);
  const statusCounts = useMemo(() => {
    const c: Record<TableStatus, number> = { EMPTY: 0, IN_USE: 0, RESERVED: 0, AWAITING_PAYMENT: 0 };
    for (const t of tables) c[deriveTableStatus(t)] += 1;
    return c;
  }, [tables]);
  const totalGuests = useMemo(
    () =>
      tables
        .filter((t) => t.inUse)
        .reduce((sum, t) => sum + (t.guestCount && t.guestCount > 0 ? t.guestCount : 1), 0),
    [tables]
  );

  function calculateTableTotalFor(t: Table | null): number {
    if (!t) return 0;
    const { subTotal, itemDiscounts } = summarizeOrderLines(parseOrderJson(t.currentOrderJson));
    return Math.max(0, subTotal - itemDiscounts);
  }

  const parseOrderItems = (json?: string): OrderItem[] => {
    if (!json || json.trim() === "" || json === "[]") return [];
    try {
      const parsed = JSON.parse(json);
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  };

  // Tổng tiền tạm tính giống hệt cách tính khi thanh toán (size + topping - giảm giá dòng)
  const calculateTableTotal = (items: OrderItem[]): number => {
    const { subTotal, itemDiscounts } = summarizeOrderLines(items as unknown as RawOrderLine[]);
    return Math.max(0, subTotal - itemDiscounts);
  };

  /** Tổng giảm từ khuyến mãi / voucher đã chọn — chỉ áp dụng cho bàn đang mở ở màn thanh toán */
  const promoDiscountOf = (t: Table): number =>
    selectedTableForOrder && t.id === selectedTableForOrder.id ? promo.total + pointsDiscountNow : 0;

  const getElapsedMinutes = (openedAt?: string | null): string => {
    if (!openedAt) return "< 1";
    try {
      const start = new Date(openedAt).getTime();
      const now = new Date().getTime();
      const diffMin = Math.max(0, Math.floor((now - start) / (1000 * 60)));
      if (diffMin < 60) return `${diffMin}`;
      const hours = Math.floor(diffMin / 60);
      const mins = diffMin % 60;
      return `${hours}h ${mins}m`;
    } catch {
      return "—";
    }
  };

  const qtyBtnStyle: CSSProperties = {
    width: "26px",
    height: "26px",
    borderRadius: "6px",
    border: "1px solid var(--border)",
    background: "var(--surface-muted)",
    color: "var(--text)",
    display: "inline-flex",
    alignItems: "center",
    justifyContent: "center",
    cursor: "pointer",
    padding: 0,
  };

  const formatVND = (amount: number) => {
    return new Intl.NumberFormat("vi-VN").format(amount);
  };

  const openAdd = () => {
    setEditId(null);
    setForm(emptyForm);
    setError("");
    setShowModal(true);
  };

  const openEdit = (t: Table) => {
    setEditId(t.id);
    setForm({ name: t.name, zone: t.zone || "" });
    setError("");
    setShowModal(true);
  };

  const closeModal = () => {
    setShowModal(false);
    setEditId(null);
    setForm(emptyForm);
    setError("");
  };

  const handleSave = async () => {
    if (!form.name.trim()) {
      setError("Vui lòng nhập tên bàn");
      return;
    }
    setSaving(true);
    setError("");
    try {
      const name = form.name.trim();
      const zone = form.zone.trim() || "Khu A";
      const tableKey = `${zone}_${name}`;

      const res = await saveTable({
        id: editId || tableKey,
        name,
        zone,
      });
      if (!res.success) {
        setError(res.error || "Lỗi lưu dữ liệu");
      } else {
        closeModal();
      }
    } catch (e) {
      setError(errorMessage(e) || "Lỗi lưu dữ liệu");
    }
    setSaving(false);
  };

  const handleDelete = async (id: string) => {
    try {
      const res = await deleteTable(id);
      if (!res.success) {
        alert("Lỗi khi xóa bàn: " + res.error);
      }
      setDeleteId(null);
    } catch (e) {
      alert("Lỗi xóa bàn: " + errorMessage(e));
    }
  };

  const handleCheckoutAndFreeTable = async (t: Table) => {
    const items = parseOrderItems(t.currentOrderJson);
    const total = Math.max(0, calculateTableTotal(items) - promoDiscountOf(t));
    const methodText = paymentMethod === "CASH" ? "Tiền mặt" : "Chuyển khoản VietQR";

    const isSel = !!selectedTableForOrder && t.id === selectedTableForOrder.id;
    const usedPts = isSel ? pointsUsedNow : 0;
    if (!confirm(`Xác nhận hoàn tất thanh toán (${methodText}) và trả ${t.name} (Tổng tiền: ${formatVND(total)} VNĐ)?${usedPts > 0 ? `\nSẽ trừ ${formatVND(usedPts)} điểm của khách.` : ""}`)) return;

    setCompletingPayment(true);
    try {
      const res = await checkoutAndFreeTable(t, {
        paymentMethod,
        promotions: selectedTableForOrder && t.id === selectedTableForOrder.id ? promo.applied : [],
        staffName: user?.fullName,
        pointsUsed: usedPts,
        pointRedeemRate: loy.rates.redeemRate,
      });
      if (res.success) {
        setCheckoutToast(`✅ Đã thanh toán hóa đơn ${res.billCode || res.billId} và trả bàn ${t.name} thành công!`);
        setTimeout(() => setCheckoutToast(null), 5000);
        // Tích điểm SAU khi hóa đơn PAID (máy chủ tính từ finalAmount); lỗi → hàng đợi thử lại, không im lặng
        if (res.customerId && res.billId) {
          const storeCode = t.storeCode || resolveWriteStoreCode(currentStoreCode);
          const billId = res.billId;
          let storage: Storage | null = null;
          try {
            storage = window.localStorage;
          } catch {}
          const r = await earnWithRetry(storage, earnQueueKey(user?.username || "", storeCode), { billId, billCode: res.billCode }, (id) => applyLoyaltyEarn(storeCode, id));
          if (!r.ok) {
            setLoyaltyWarn("Chưa cộng được điểm, sẽ thử lại");
            setTimeout(() => setLoyaltyWarn(null), 10000);
          }
        }
        setSelectedTableForOrder(null);
      } else {
        alert("Lỗi khi trả bàn: " + (res.error || "Không xác định"));
      }
    } catch (e) {
      alert("Lỗi khi trả bàn: " + errorMessage(e));
    }
    setCompletingPayment(false);
  };

  // ----- Khách hàng của bàn (lưu ngay trên bàn: POS Flutter và web thấy cùng một khách) -----
  const attachCustomer = async (table: Table, c: BillCustomer | null) => {
    await writeTableFields(table, tableCustomerPayload(c));
    setPointsState({ key: "", n: 0 });
    setBalanceTick((n) => n + 1);
    if (c) {
      // Đánh dấu "ghé gần đây" để lần sau khách này nằm đầu danh sách (không ảnh hưởng điểm; lỗi bỏ qua)
      const storeCode = table.storeCode || resolveWriteStoreCode(currentStoreCode);
      void update(ref(db), { [`stores/${storeCode}/customers/${c.id}/lastVisitAt`]: nowMs() }).catch(() => undefined);
    }
  };

  const createBranchCustomer = async (storeCode: string, name: string, phone: string): Promise<BillCustomer> => {
    const now = nowMs();
    const id = `CUST_${now}`;
    await update(ref(db), {
      [`stores/${storeCode}/customers/${id}`]: buildNewCustomerNode(id, { name, phone }, now),
      [`stores/${storeCode}/audit_logs/log_${now}_cust`]: {
        timestamp: now,
        username: user?.username || "admin_web",
        userFullName: user?.fullName || user?.username || "",
        userRole: user?.roleId || user?.role || "",
        action: "CUSTOMER_CREATE",
        targetType: "CUSTOMER",
        targetId: id,
        storeCode,
        details: `Tạo khách hàng ${name} (${phone}) từ màn gọi món Web`,
      },
    });
    return { id, name, phone };
  };

  const handlePickCustomer = async (table: Table, c: PickerCustomer): Promise<string | null> => {
    const storeCode = table.storeCode || resolveWriteStoreCode(currentStoreCode);
    let picked: BillCustomer = { id: c.id, name: c.name, phone: c.phone };
    if (c.remote || !c.id) {
      if (!canManageCustomers) return "Khách này ở chi nhánh khác. Cần quyền Quản lý khách hàng (MANAGE_CUSTOMERS) để thêm vào chi nhánh này.";
      picked = await createBranchCustomer(storeCode, c.name, c.phone);
    }
    await attachCustomer(table, picked);
    setShowCustomerPicker(false);
    return null;
  };

  const handleCreateCustomer = async (table: Table, name: string, phone: string): Promise<string | null> => {
    if (!canManageCustomers) return "Bạn không có quyền tạo khách hàng (MANAGE_CUSTOMERS).";
    const storeCode = table.storeCode || resolveWriteStoreCode(currentStoreCode);
    const created = await createBranchCustomer(storeCode, name, phone);
    await attachCustomer(table, created);
    setShowCustomerPicker(false);
    return null;
  };

  const handleRemoveCustomer = async (table: Table) => {
    setLoyaltyBusy(true);
    try {
      await attachCustomer(table, null);
    } catch (e) {
      alert("Lỗi bỏ khách khỏi bàn: " + errorMessage(e));
    }
    setLoyaltyBusy(false);
  };

  const handleCancelActiveTable = async (t: Table) => {
    const reason = prompt(`Nhập lý do hủy đơn bàn ${t.name}:`, "Khách đổi ý hủy bàn");
    if (!reason || !reason.trim()) return;

    if (!confirm(`Xác nhận HỦY TOÀN BỘ đơn và TRẢ BÀN TRỐNG cho ${t.name}?\nLý do: ${reason.trim()}`)) return;

    setCompletingPayment(true);
    try {
      const res = await cancelActiveTable(t, reason.trim());
      if (res.success) {
        setCheckoutToast(`✅ Đã hủy đơn bàn ${t.name} và trả bàn trống thành công!`);
        setTimeout(() => setCheckoutToast(null), 5000);
        setSelectedTableForOrder(null);
      } else {
        alert("Lỗi khi hủy đơn bàn: " + (res.error || "Không xác định"));
      }
    } catch (e) {
      alert("Lỗi khi hủy đơn bàn: " + errorMessage(e));
    }
    setCompletingPayment(false);
  };

  // Ghi các trường của bàn bằng MỘT update() đa đường dẫn (khóa chính + khóa chuẩn {zone}_{name} nếu tồn tại).
  // Lỗi được ném ra để handler hiển thị cho người dùng, không bị nuốt.
  const writeTableFields = async (table: Table, payload: Record<string, unknown>) => {
    const targetStoreCode = table.storeCode || resolveWriteStoreCode(currentStoreCode);
    const stdKey = `${table.zone}_${table.name}`;
    const keys = [table.id];
    if (stdKey !== table.id && tables.some((t) => t.id === stdKey && (t.storeCode || targetStoreCode) === targetStoreCode)) {
      keys.push(stdKey);
    }
    const updates: Record<string, unknown> = {};
    for (const key of keys) {
      for (const [field, value] of Object.entries(payload)) {
        updates[`stores/${targetStoreCode}/tables/${key}/${field}`] = value;
      }
    }
    await update(ref(db), updates);
  };

  const handleUpdateGuestCount = async (table: Table, count: number) => {
    try {
      await writeTableFields(table, { guestCount: count });
      setSelectedTableForOrder((prev) => (prev ? { ...prev, guestCount: count } : null));
    } catch (e) {
      console.error("Lỗi cập nhật số khách:", e);
      alert("Lỗi cập nhật số khách: " + errorMessage(e, "Không xác định"));
    }
  };

  const handleCheckInReservation = async (table: Table) => {
    if (!confirm(`Xác nhận nhận khách vào ${table.name}?`)) return;
    try {
      const payload = {
        inUse: true,
        isReserved: false,
        openedAt: new Date().toISOString(),
        guestCount: 2,
        reservationCustomer: null,
        reservationPhone: null,
        reservationTime: null,
        reservationDeposit: 0,
      };
      await writeTableFields(table, payload);
      setCheckoutToast(`✅ Đã nhận khách vào ${table.name}!`);
      setTimeout(() => setCheckoutToast(null), 4000);
    } catch (e) {
      alert("Lỗi nhận bàn: " + errorMessage(e));
    }
  };

  const handleCancelReservation = async (table: Table) => {
    if (!confirm(`Xác nhận hủy đặt trước cho bàn ${table.name}?`)) return;
    try {
      const payload = {
        isReserved: false,
        reservationCustomer: null,
        reservationPhone: null,
        reservationTime: null,
        reservationDeposit: 0,
      };
      await writeTableFields(table, payload);
      setCheckoutToast(`Đã hủy đặt trước bàn ${table.name}!`);
      setTimeout(() => setCheckoutToast(null), 4000);
    } catch (e) {
      alert("Lỗi hủy đặt bàn: " + errorMessage(e));
    }
  };

  const printBill = (table: Table) => {
    const items = parseOrderItems(table.currentOrderJson);
    if (items.length === 0) {
      alert("Bàn chưa có món để in tạm tính");
      return;
    }
    const subtotal = calculateTableTotal(items);
    const promotions = selectedTableForOrder && table.id === selectedTableForOrder.id ? promo.applied : [];
    const total = Math.max(0, subtotal - promoDiscountOf(table));
    const isSel = !!selectedTableForOrder && table.id === selectedTableForOrder.id;
    const printCust = isSel ? billCustomer : null;
    const printLoyalty = printCust
      ? {
          customer: { name: printCust.name, phone: printCust.phone },
          ...(pointsUsedNow > 0 ? { pointsRedeemed: { points: pointsUsedNow, amount: pointsDiscountNow } } : {}),
          pointsEarn: buildPointsPreview({ balance: balance.points, totalPoints: balance.total, payable: total, pointsUsed: pointsUsedNow, rates: loy.rates, tiers: loy.tiers }).earn,
        }
      : {};
    const printWindow = window.open("", "_blank");
    if (!printWindow) {
      alert("Vui lòng cho phép mở cửa sổ popup để in hóa đơn");
      return;
    }

    printWindow.document.write(
      buildTableBillHtml({
        tableName: table.name,
        zone: table.zone,
        items,
        total,
        promotions: promotions.map((d) => ({ name: d.campaignName, code: d.voucherCode, amount: d.amount })),
        ...printLoyalty,
        printedAt: new Date().toLocaleString("vi-VN"),
      })
    );
    printWindow.document.close();
    // Đánh dấu "Chờ thanh toán" (prePrintedAt) — tự xóa khi món thay đổi / thanh toán / hủy
    void markTablePrePrinted(table, user?.username).then((res) => {
      if (!res.success) alert("Đã in nhưng không cập nhật được trạng thái chờ thanh toán: " + (res.error || ""));
    });
  };

  // Ghi lại danh sách món của bàn (dựa trên JSON đã chụp, để không ghi nhầm dòng nếu POS vừa sửa đơn)
  const writeOrderLines = async (
    table: Table,
    orderJson: string,
    nextItems: RawOrderLine[],
    action: string,
    details: string,
    approval?: ManagerApproval | null,
    deletions?: DeletedItemEntry[]
  ): Promise<string | null> => {
    const res = await updateTableOrderItems({ ...table, currentOrderJson: orderJson }, nextItems, {
      action,
      details,
      staffUsername: user?.username,
      staffFullName: user?.fullName,
      staffRole: user?.roleId || user?.role,
      approval: approval ?? null,
      deletions,
    });
    const err = res.success ? null : res.error || "Không lưu được thay đổi";
    setLineError(err || "");
    return err;
  };

  const tableStoreCode = (t: Table) => t.storeCode || resolveWriteStoreCode(currentStoreCode);

  /** Mở hộp thoại PIN quản lý cho thao tác thiếu quyền */
  const requestManagerPin = (table: Table, action: ApprovalAction, context: string, onApproved: (a: ManagerApproval) => void) => {
    setPinRequest({ action, storeCode: tableStoreCode(table), context, onApproved });
  };

  const openLineDiscount = (table: Table, index: number) => {
    setLineError("");
    const orderJson = table.currentOrderJson || "";
    if (canDiscountItem) {
      setDiscountApproval(null);
      setDiscountTarget({ orderJson, index });
      return;
    }
    const line = (parseOrderItems(orderJson) as unknown as RawOrderLine[])[index];
    requestManagerPin(table, "DISCOUNT_ITEM", `Giảm giá "${String(line?.name ?? "")}" tại ${table.name}`, (a) => {
      setDiscountApproval(a);
      setDiscountTarget({ orderJson, index });
    });
  };

  const closeLineDiscount = () => {
    setDiscountTarget(null);
    setDiscountApproval(null);
    setLineError("");
  };

  const handleSaveLineDiscount = async (table: Table, rawNextLine: RawOrderLine) => {
    if (!discountTarget) return;
    const approval = canDiscountItem ? null : discountApproval;
    if (!canDiscountItem && !isApprovalValid(approval, "DISCOUNT_ITEM")) {
      setLineError("Lần duyệt PIN đã hết hạn. Vui lòng đóng và nhờ Quản lý duyệt lại.");
      return;
    }
    const items = parseOrderItems(discountTarget.orderJson) as unknown as RawOrderLine[];
    const prevLine = items[discountTarget.index];
    if (!prevLine) return;
    const nextLine = withApprovalMeta(rawNextLine, approval, lineDiscountTotal(rawNextLine) > 0);
    const nextItems = items.map((it, i) => (i === discountTarget.index ? nextLine : it));
    const label = lineDiscountLabel(nextLine, (n) => `${formatVND(n)}đ`);
    const details = label
      ? `${label} cho "${String(prevLine.name ?? "")}" (-${formatVND(lineDiscountTotal(nextLine))}đ)`
      : `Bỏ giảm giá "${String(prevLine.name ?? "")}"`;
    setLineSaving(true);
    const err = await writeOrderLines(table, discountTarget.orderJson, nextItems, "DISCOUNT_ITEM", details, approval);
    setLineSaving(false);
    if (!err) closeLineDiscount();
  };

  /** Tăng 1 phần (món chưa gửi bếp); giảm → mở hộp thoại xóa món bắt buộc lý do */
  const handleChangeLineQuantity = async (table: Table, index: number, delta: number) => {
    const orderJson = table.currentOrderJson || "";
    const items = parseOrderItems(orderJson) as unknown as RawOrderLine[];
    const line = items[index];
    if (!line) return;
    if (delta < 0) {
      openRemoval(table, index, 1);
      return;
    }
    // Web không gửi phiếu bếp — thêm phần cho món đã gửi bếp phải làm trên POS
    if (line.isSentKitchen === true) return;
    const qty = lineQuantity(line);
    const nextLine = setLineQuantity(line, qty + delta);
    const nextItems = items.map((it, i) => (i === index ? nextLine : it));
    setLineSaving(true);
    const err = await writeOrderLines(
      table,
      orderJson,
      nextItems,
      "UPDATE_ITEM_QTY",
      `Đổi số lượng "${String(line.name ?? "")}" ${qty} → ${lineQuantity(nextLine)}`
    );
    setLineSaving(false);
    if (err) alert(err);
  };

  const openRemoval = (table: Table, index: number, initialQty: number) => {
    if (!canDeleteItem) {
      alert("Bạn không có quyền xóa món khỏi đơn (DELETE_ITEM).");
      return;
    }
    setLineError("");
    setRemovalTarget({ table, orderJson: table.currentOrderJson || "", index, initialQty });
  };

  /** Xóa removeQty phần của dòng trên đúng bản đơn đã chụp; món đã gửi bếp thiếu quyền → Quản lý duyệt PIN */
  const confirmRemoval = (removeQty: number, reason: string) => {
    const target = removalTarget;
    if (!target) return;
    const { table, orderJson, index } = target;
    const items = parseOrderItems(orderJson) as unknown as RawOrderLine[];
    const line = items[index];
    if (!line) return;
    const sent = line.isSentKitchen === true;
    const commit = async (approval: ManagerApproval | null) => {
      if (approval && !isApprovalValid(approval, "CANCEL_KITCHEN_ITEM")) {
        setLineError("Lần duyệt PIN đã hết hạn. Vui lòng thử lại.");
        return;
      }
      const entry = buildDeletionEntry({
        line,
        removeQty,
        reason,
        staffUsername: user?.username,
        staffFullName: user?.fullName,
        now: Date.now(),
      });
      const nextItems = applyLineRemoval(items, index, entry.quantity, setLineQuantity);
      setLineSaving(true);
      const err = await writeOrderLines(
        table,
        orderJson,
        nextItems,
        sent ? "CANCEL_KITCHEN_ITEM" : "DELETE_ITEM",
        deletionDetails(entry, table.name),
        approval,
        [entry]
      );
      if (!err && nextItems.length === 0) {
        // Xóa hết món đã lưu → ghi hóa đơn CANCELLED (kèm deletedItems) và trả bàn — giống Flutter
        const res = await cancelActiveTable(
          { ...table, currentOrderJson: JSON.stringify(nextItems) },
          `Xóa hết món — ${reason}`,
          user?.fullName
        );
        setLineSaving(false);
        if (!res.success) {
          setLineError(res.error || "Đã xóa món nhưng không hủy được đơn của bàn");
          return;
        }
        setRemovalTarget(null);
        setSelectedTableForOrder(null);
        return;
      }
      setLineSaving(false);
      if (!err) setRemovalTarget(null);
    };
    if (sent && !canCancelKitchenItem) {
      requestManagerPin(table, "CANCEL_KITCHEN_ITEM", `Xóa ${removeQty} x "${String(line.name ?? "")}" tại ${table.name}`, (a) => {
        void commit(a);
      });
      return;
    }
    void commit(null);
  };

  const orderActor = {
    username: user?.username || "admin_web",
    fullName: user?.fullName,
    role: user?.roleId || user?.role,
  };

  const orderableProducts = useMemo(
    () =>
      orderTarget
        ? products
            .filter((p) => (p.storeCode || currentStoreCode) === (orderTarget.storeCode || currentStoreCode))
            .map((p) => ({
              id: p.id, name: p.name, price: p.price, code: p.code, category: p.category, unit: p.unit, isTopping: p.isTopping,
              sizes: p.sizes, allowedToppings: p.allowedToppings, hasIceSugarOptions: p.hasIceSugarOptions,
              noteGroupIds: p.noteGroupIds, toppingGroupIds: p.toppingGroupIds,
              isAvailable: p.isAvailable, soldOutUntil: p.soldOutUntil,
            }))
        : [],
    [products, orderTarget, currentStoreCode]
  );
  // Danh mục note & topping của chi nhánh của bàn đang gọi món (chỉ nghe khi mở hộp thoại gọi món)
  const { catalog: orderCatalog } = useItemCatalog(orderTarget ? orderTarget.storeCode || currentStoreCode : null);
  const orderableCategories = useMemo(
    () =>
      orderTarget
        ? allCategories
            .filter((c) => (c.storeCode || currentStoreCode) === (orderTarget.storeCode || currentStoreCode))
            .map((c) => ({ name: c.name, allowedToppingIds: c.allowedToppingIds, noteGroupIds: c.noteGroupIds, toppingGroupIds: c.toppingGroupIds }))
        : [],
    [allCategories, orderTarget, currentStoreCode]
  );

  /** Chạm vào bàn: Chế độ Order → mở gọi món; ngược lại → xem chi tiết như cũ */
  const handleTableTap = (t: Table) => {
    if (orderMode && !(t.isReserved && !t.inUse)) openOrderDialog(t);
    else if (t.inUse) setSelectedTableForOrder(t);
  };

  const openOrderDialog = (t: Table) => {
    setOrderError("");
    setOrderTarget(t);
  };

  const handleSubmitWebOrder = async (
    lines: RawOrderLine[],
    opts: { sendKitchen: boolean; guestCount: number; kitchenNote: string }
  ) => {
    if (!orderTarget) return;
    setOrderSaving(true);
    setOrderError("");
    const res = await submitWebOrder(orderTarget, lines, {
      sendKitchen: opts.sendKitchen && canSendKitchenFromWeb,
      guestCount: opts.guestCount,
      kitchenNote: opts.kitchenNote,
      actor: orderActor,
    });
    setOrderSaving(false);
    if (!res.success) {
      setOrderError(res.error || "Không lưu được đơn");
      return;
    }
    setOrderTarget(null);
    setCheckoutToast(
      res.sentCount ? `Đã lưu đơn ${orderTarget.name} và gửi ${res.sentCount} dòng món cho bếp` : `Đã lưu đơn ${orderTarget.name}`
    );
    setTimeout(() => setCheckoutToast(null), 4000);
  };

  const openTableOp = (kind: "TRANSFER" | "MERGE", source: Table) => {
    setTableOpError("");
    setTableOp({ kind, source });
  };

  const tableOpCandidates = (kind: "TRANSFER" | "MERGE", source: Table): Table[] => {
    const sc = tableStoreCode(source);
    return tables
      .filter((t) => t.id !== source.id && tableStoreCode(t) === sc)
      .filter((t) => (kind === "TRANSFER" ? !t.inUse && t.isReserved !== true : t.inUse))
      .sort((a, b) => (a.zone || "").localeCompare(b.zone || "", "vi") || a.name.localeCompare(b.name, "vi", { numeric: true }));
  };

  const handlePickTableOpTarget = async (target: Table) => {
    if (!tableOp) return;
    const { kind, source } = tableOp;
    const msg =
      kind === "TRANSFER"
        ? `Chuyển toàn bộ đơn từ ${source.name} sang ${target.name}?`
        : `Gộp hóa đơn của ${source.name} vào ${target.name}? ${source.name} sẽ được trả về trống.`;
    if (!confirm(msg)) return;
    setTableOpBusy(true);
    setTableOpError("");
    const actor = { username: user?.username, fullName: user?.fullName, roleId: user?.roleId };
    const res = kind === "TRANSFER" ? await transferTable(source, target, actor) : await mergeTables(source, target, actor);
    setTableOpBusy(false);
    if (!res.success) {
      setTableOpError(res.error || "Không thực hiện được");
      return;
    }
    setTableOp(null);
    setSelectedTableForOrder(target);
    setCheckoutToast(
      kind === "TRANSFER"
        ? `✅ Đã chuyển toàn bộ món từ ${source.name} sang ${target.name}!`
        : `✅ Đã gộp hóa đơn của ${source.name} vào ${target.name}!`
    );
    setTimeout(() => setCheckoutToast(null), 5000);
  };

  const myProfile = usersList.find((u) => u.uid === user?.uid);

  if (loading) {
    return (
      <div style={{ display: "flex", alignItems: "center", justifyContent: "center", height: "60vh" }}>
        <div className="spinner" />
      </div>
    );
  }

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "24px" }}>
      {loyaltyWarn && (
        <div
          role="alert"
          style={{ background: "var(--warning-bg, #FFF4E5)", border: "1.5px solid var(--warning, #F59E0B)", borderRadius: "12px", padding: "12px 18px", color: "var(--text)", fontWeight: 600, display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10 }}
        >
          <span>⚠ {loyaltyWarn}</span>
          <button onClick={() => setLoyaltyWarn(null)} aria-label="Đóng" style={{ background: "transparent", border: "none", cursor: "pointer", color: "var(--text)" }}>
            <X size={16} />
          </button>
        </div>
      )}
      {/* Toast feedback */}
      {checkoutToast && (
        <div
          style={{
            background: "var(--success-bg)",
            border: "1.5px solid #10B981",
            borderRadius: "12px",
            padding: "14px 18px",
            color: "#065F46",
            fontWeight: "600",
            display: "flex", flexWrap: "wrap", rowGap: "8px",
            alignItems: "center",
            justifyContent: "space-between",
            boxShadow: "0 4px 12px rgba(16, 185, 129, 0.15)",
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
            <CheckCircle2 size={20} color="#10B981" />
            <span>{checkoutToast}</span>
          </div>
          <button
            onClick={() => setCheckoutToast(null)}
            style={{ background: "transparent", border: "none", cursor: "pointer", color: "#065F46" }}
          >
            <X size={16} />
          </button>
        </div>
      )}

      {/* Header */}
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: "16px" }}>
        <div>
          <h1 className="section-title">Sơ đồ Phòng / Bàn 🪑</h1>
          <p className="section-subtitle">
            Hệ sinh thái POS Trạm • Đồng bộ trực tiếp với ứng dụng phục vụ
          </p>
        </div>
        <div style={{ display: "flex", gap: "10px" }}>
          {/* Switch View Mode */}
          <div
            style={{
              display: "flex",
              background: "var(--surface)",
              border: "1px solid var(--border)",
              borderRadius: "10px",
              padding: "3px",
            }}
          >
            <button
              onClick={() => setViewMode("grid")}
              style={{
                display: "flex",
                alignItems: "center",
                gap: "6px",
                padding: "6px 12px",
                borderRadius: "8px",
                border: "none",
                background: viewMode === "grid" ? "var(--primary)" : "transparent",
                color: viewMode === "grid" ? "#FFFFFF" : "var(--subtext)",
                fontWeight: "600",
                fontSize: "13px",
                cursor: "pointer",
                transition: "all 0.2s",
              }}
            >
              <LayoutGrid size={15} />
              Sơ đồ bàn
            </button>
            <button
              onClick={() => setViewMode("list")}
              style={{
                display: "flex",
                alignItems: "center",
                gap: "6px",
                padding: "6px 12px",
                borderRadius: "8px",
                border: "none",
                background: viewMode === "list" ? "var(--primary)" : "transparent",
                color: viewMode === "list" ? "#FFFFFF" : "var(--subtext)",
                fontWeight: "600",
                fontSize: "13px",
                cursor: "pointer",
                transition: "all 0.2s",
              }}
            >
              <List size={15} />
              Danh sách
            </button>
          </div>

          {canSetApprovalPin && (
            <button className="btn-secondary" onClick={() => setShowSetPin(true)} title="Đặt PIN để duyệt thao tác cho nhân viên">
              <KeyRound size={16} />
              PIN duyệt
            </button>
          )}
          {orderMode && (
            <Link href="/dashboard/my-orders" className="btn-secondary" title="Lịch sử các đơn do tài khoản của bạn lập">
              <Receipt size={16} />
              Đơn của tôi
            </Link>
          )}
          {canOrderOnWeb && (
            <button
              className={orderMode ? "btn-primary" : "btn-secondary"}
              onClick={toggleOrderMode}
              aria-pressed={orderMode}
              title="Bật để chạm vào bàn là gọi món ngay (dự phòng khi app POS sự cố)"
            >
              <ChefHat size={16} />
              Chế độ Order: {orderMode ? "BẬT" : "TẮT"}
            </button>
          )}
          {canManageLayout(user?.roleId || user?.role, user?.isRootOwner) && hasPermission(user, "MANAGE_TABLES") && (
            <button
              className="btn-secondary"
              onClick={() => setShowZoneSetup(true)}
              title="Thêm, đổi tên, xóa khu vực và thêm bàn theo khu (chi nhánh đang chọn)"
            >
              <Settings2 size={16} />
              Thiết lập khu vực
            </button>
          )}
          <button className="btn-primary" onClick={openAdd}>
            <Plus size={16} />
            Thêm bàn mới
          </button>
        </div>
      </div>

      {/* Statistics Cards */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(min(210px, 100%), 1fr))", gap: "16px" }}>
        <div className="stat-card">
          <div style={{ fontSize: "13px", fontWeight: "600", color: "var(--subtext)", marginBottom: "8px" }}>
            TỔNG SỐ BÀN
          </div>
          <div style={{ fontSize: "28px", fontWeight: "800", color: "var(--text)" }}>
            {tables.length} <span style={{ fontSize: "14px", fontWeight: "500", color: "var(--subtext)" }}>bàn</span>
          </div>
          <div style={{ fontSize: "12px", color: "var(--subtext)", marginTop: "4px" }}>
            Toàn bộ các khu vực
          </div>
        </div>

        <div
          className="stat-card"
          style={{
            borderLeft: "4px solid var(--primary)",
            background: inUseCount > 0 ? "linear-gradient(135deg, var(--surface) 0%, var(--primary-light) 100%)" : "var(--surface)",
          }}
        >
          <div style={{ fontSize: "13px", fontWeight: "700", color: "var(--primary)", marginBottom: "8px" }}>
            ĐANG CÓ KHÁCH (IN USE)
          </div>
          <div style={{ fontSize: "28px", fontWeight: "800", color: "var(--primary)" }}>
            {inUseCount} <span style={{ fontSize: "14px", fontWeight: "600", color: "var(--primary)" }}>bàn</span>
          </div>
          <div style={{ fontSize: "12px", color: "var(--primary)", marginTop: "4px", fontWeight: "600" }}>
            {statusCounts.AWAITING_PAYMENT > 0 ? (
              <span style={{ color: "var(--table-awaiting)" }}>
                {statusCounts.AWAITING_PAYMENT} bàn chờ thanh toán (đã in tạm tính)
              </span>
            ) : (
              "🔴 Đã gửi bếp & đang phục vụ"
            )}
          </div>
        </div>

        <div
          className="stat-card"
          style={{
            borderLeft: "4px solid var(--success)",
            background: "linear-gradient(135deg, var(--surface) 0%, var(--success-bg) 100%)",
          }}
        >
          <div style={{ fontSize: "13px", fontWeight: "700", color: "var(--success)", marginBottom: "8px" }}>
            BÀN TRỐNG (AVAILABLE)
          </div>
          <div style={{ fontSize: "28px", fontWeight: "800", color: "var(--success)" }}>
            {statusCounts.EMPTY} <span style={{ fontSize: "14px", fontWeight: "600", color: "var(--success)" }}>bàn</span>
          </div>
          <div style={{ fontSize: "12px", color: "var(--success)", marginTop: "4px", fontWeight: "600" }}>
            🟢 Sẵn sàng nhận khách mới
          </div>
        </div>

        <div className="stat-card" style={{ borderLeft: "4px solid var(--warning)" }}>
          <div style={{ fontSize: "13px", fontWeight: "700", color: "var(--warning)", marginBottom: "8px" }}>
            TỔNG SỐ KHÁCH HIỆN TẠI
          </div>
          <div style={{ fontSize: "28px", fontWeight: "800", color: "var(--warning)" }}>
            {totalGuests} <span style={{ fontSize: "14px", fontWeight: "600", color: "var(--warning)" }}>khách</span>
          </div>
          <div style={{ fontSize: "12px", color: "#805214", marginTop: "4px" }}>
            Đang ngồi tại {inUseCount} bàn
          </div>
        </div>

        <div
          className="stat-card"
          style={{
            borderLeft: "4px solid #B45309",
            background: statusCounts.RESERVED > 0 ? "linear-gradient(135deg, var(--surface) 0%, var(--warning-bg) 100%)" : "var(--surface)",
          }}
        >
          <div style={{ fontSize: "13px", fontWeight: "700", color: "#B45309", marginBottom: "8px" }}>
            ĐẶT TRƯỚC (RESERVED)
          </div>
          <div style={{ fontSize: "28px", fontWeight: "800", color: "#B45309" }}>
            {statusCounts.RESERVED} <span style={{ fontSize: "14px", fontWeight: "600", color: "#B45309" }}>bàn</span>
          </div>
          <div style={{ fontSize: "12px", color: "#B45309", marginTop: "4px", fontWeight: "600" }}>
            🟡 Đã có khách hẹn
          </div>
        </div>
      </div>

      {/* Zone Tabs & Search Bar */}
      <div
        className="card"
        style={{
          padding: "16px 20px",
          display: "flex",
          flexDirection: "column",
          gap: "14px",
        }}
      >
        <div
          style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            flexWrap: "wrap",
            gap: "14px",
          }}
        >
          {/* Zone Tabs */}
          <div style={{ display: "flex", gap: "8px", flexWrap: "wrap" }}>
            <button
              className={`tab-btn ${selectedZone === "ALL" ? "active" : ""}`}
              onClick={() => setSelectedZone("ALL")}
            >
              Tất cả ({tables.length})
            </button>
            {zones.map((z) => {
              const countInZone = tables.filter((t) => t.zone === z).length;
              const inUseInZone = tables.filter((t) => t.zone === z && t.inUse).length;
              return (
                <button
                  key={z}
                  className={`tab-btn ${selectedZone === z ? "active" : ""}`}
                  onClick={() => setSelectedZone(z)}
                  style={{ display: "flex", alignItems: "center", gap: "6px" }}
                >
                  <span>{z}</span>
                  <span
                    style={{
                      fontSize: "11px",
                      padding: "1px 6px",
                      borderRadius: "10px",
                      background: selectedZone === z ? "rgba(255,255,255,0.25)" : "rgba(0,0,0,0.06)",
                    }}
                  >
                    {inUseInZone > 0 ? `${inUseInZone}/` : ""}
                    {countInZone}
                  </span>
                </button>
              );
            })}
          </div>

          {/* Search Input */}
          <div style={{ position: "relative", minWidth: "260px" }}>
            <Search
              size={16}
              style={{
                position: "absolute",
                left: "14px",
                top: "50%",
                transform: "translateY(-50%)",
                color: "var(--muted)",
              }}
            />
            <input
              className="input-field"
              placeholder="Tìm theo tên bàn, khu vực..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              style={{ paddingLeft: "40px" }}
            />
          </div>
        </div>

        {/* Status Filter Chips */}
        <div style={{ display: "flex", alignItems: "center", gap: "8px", flexWrap: "wrap", borderTop: "1px dashed var(--border-light)", paddingTop: "12px" }}>
          <span style={{ fontSize: "12px", fontWeight: "700", color: "var(--subtext)", marginRight: "4px" }}>
            Trạng thái bàn:
          </span>
          <button
            type="button"
            aria-pressed={statusFilter === "ALL"}
            onClick={() => setStatusFilter("ALL")}
            style={{
              minHeight: "32px",
              padding: "6px 12px",
              borderRadius: "14px",
              fontSize: "12px",
              fontWeight: statusFilter === "ALL" ? "700" : "500",
              background: statusFilter === "ALL" ? "var(--text)" : "var(--surface-muted)",
              color: statusFilter === "ALL" ? "var(--surface)" : "var(--subtext)",
              border: "none",
              cursor: "pointer",
            }}
          >
            Tất cả ({tables.length})
          </button>
          {TABLE_STATUS_ORDER.map((st) => {
            const meta = TABLE_STATUS_META[st];
            const active = statusFilter === st;
            return (
              <button
                key={st}
                type="button"
                aria-pressed={active}
                onClick={() => setStatusFilter(st)}
                style={{
                  minHeight: "32px",
                  padding: "6px 12px",
                  borderRadius: "14px",
                  fontSize: "12px",
                  fontWeight: active ? "700" : "500",
                  background: active ? meta.color : meta.bg,
                  color: active ? "var(--surface)" : meta.color,
                  border: `1px solid color-mix(in srgb, ${meta.color} 30%, transparent)`,
                  cursor: "pointer",
                  display: "inline-flex",
                  alignItems: "center",
                  gap: "6px",
                }}
              >
                <span
                  aria-hidden="true"
                  style={{ width: "10px", height: "10px", borderRadius: "3px", background: active ? "var(--surface)" : meta.color }}
                />
                {meta.label} ({statusCounts[st]})
              </button>
            );
          })}
        </div>
      </div>

      {/* Content: Floor Grid Mode */}
      {viewMode === "grid" ? (
        filtered.length === 0 ? (
          <div
            className="card"
            style={{
              textAlign: "center",
              padding: "60px 20px",
              color: "var(--subtext)",
            }}
          >
            <div style={{ fontSize: "48px", marginBottom: "12px" }}>🪑</div>
            <div style={{ fontSize: "16px", fontWeight: "700", color: "var(--text)", marginBottom: "6px" }}>
              Không tìm thấy bàn nào
            </div>
            <p style={{ fontSize: "14px" }}>
              Thử tìm kiếm với từ khóa khác hoặc nhấn &quot;Thêm bàn mới&quot; để tạo bàn.
            </p>
          </div>
        ) : (
          <div
            style={{
              display: "grid",
              gridTemplateColumns: "repeat(auto-fill, minmax(min(280px, 100%), 1fr))",
              gap: "20px",
            }}
          >
            {filtered.map((t) => {
              const orderItems = parseOrderItems(t.currentOrderJson);
              const orderTotal = calculateTableTotal(orderItems);
              const elapsedMinutes = getElapsedMinutes(t.openedAt);

              if (t.inUse) {
                // Thẻ bàn ĐANG CÓ KHÁCH (Màu đỏ mận Trạm) — đã in tạm tính: CHỜ THANH TOÁN (màu tím)
                const awaiting = deriveTableStatus(t) === "AWAITING_PAYMENT";
                const accent = awaiting ? "var(--table-awaiting)" : "var(--primary)";
                return (
                  <div
                    key={t.id}
                    onClick={() => handleTableTap(t)}
                    style={{
                      background: "var(--surface)",
                      borderRadius: "16px",
                      border: `2px solid ${accent}`,
                      boxShadow: "0 6px 18px rgba(126, 41, 48, 0.15)",
                      overflow: "hidden",
                      cursor: "pointer",
                      display: "flex",
                      flexDirection: "column",
                      transition: "transform 0.2s, box-shadow 0.2s",
                      position: "relative",
                    }}
                    onMouseEnter={(e) => {
                      e.currentTarget.style.transform = "translateY(-4px)";
                      e.currentTarget.style.boxShadow = "0 10px 24px rgba(126, 41, 48, 0.25)";
                    }}
                    onMouseLeave={(e) => {
                      e.currentTarget.style.transform = "translateY(0)";
                      e.currentTarget.style.boxShadow = "0 6px 18px rgba(126, 41, 48, 0.15)";
                    }}
                  >
                    {/* Header bàn */}
                    <div
                      style={{
                        background: awaiting
                          ? "linear-gradient(135deg, var(--table-awaiting) 0%, color-mix(in srgb, var(--table-awaiting) 72%, black) 100%)"
                          : "linear-gradient(135deg, var(--primary) 0%, var(--primary-dark) 100%)",
                        padding: "14px 16px",
                        display: "flex", flexWrap: "wrap", rowGap: "8px",
                        alignItems: "center",
                        justifyContent: "space-between",
                        color: "#FFFFFF",
                      }}
                    >
                      <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
                        <div
                          style={{
                            width: "10px",
                            height: "10px",
                            borderRadius: "50%",
                            background: "#EF4444",
                            boxShadow: "0 0 8px #EF4444",
                            animation: "pulse 1.5s infinite",
                          }}
                        />
                        <span style={{ fontSize: "14px", fontWeight: "700", lineHeight: 1.25, wordBreak: "break-word" }}>
                          {t.name}
                        </span>
                      </div>
                      <span
                        style={{
                          fontSize: "11px",
                          fontWeight: "700",
                          padding: "3px 8px",
                          borderRadius: "6px",
                          background: "rgba(255, 255, 255, 0.2)",
                          color: "#FFFFFF",
                        }}
                      >
                        {t.zone}
                      </span>
                    </div>

                    {/* Thân thẻ bàn */}
                    <div style={{ padding: "16px", flex: 1, display: "flex", flexDirection: "column", gap: "10px" }}>
                      {/* Trạng thái & Thời gian */}
                      <div style={{ display: "flex", flexWrap: "wrap", rowGap: "8px", alignItems: "center", justifyContent: "space-between" }}>
                        {awaiting ? (
                          <span
                            className="badge badge-awaiting"
                            title={t.prePrintedBy ? `In tạm tính bởi ${t.prePrintedBy}` : undefined}
                          >
                            <Printer size={13} />
                            Chờ thanh toán
                          </span>
                        ) : (
                          <span className="badge badge-danger">
                            <CheckCircle2 size={13} />
                            Đang có khách
                          </span>
                        )}
                        <div style={{ display: "flex", alignItems: "center", gap: "10px", fontSize: "12px", color: "var(--subtext)" }}>
                          <span style={{ display: "flex", alignItems: "center", gap: "4px" }}>
                            <Users size={14} color="#7E2930" />
                            <strong>{t.guestCount || 1} khách</strong>
                          </span>
                          <span style={{ display: "flex", alignItems: "center", gap: "4px" }}>
                            <Clock size={14} color="#7E2930" />
                            <strong>{elapsedMinutes} ph</strong>
                          </span>
                        </div>
                      </div>

                      {/* Mã Hóa Đơn & Mã Đặt Món */}
                      {(t.currentBillId || t.currentOrderCode) && (
                        <div style={{ display: "flex", flexWrap: "wrap", alignItems: "center", gap: "6px" }}>
                          {t.currentBillId && (
                            <span
                              style={{
                                fontSize: "11px",
                                fontWeight: "700",
                                color: "var(--primary)",
                                background: "var(--primary-light)",
                                padding: "2px 8px",
                                borderRadius: "4px",
                                border: "1px solid rgba(126, 41, 48, 0.2)",
                                letterSpacing: "0.02em",
                              }}
                            >
                              HĐ: {t.currentBillId}
                            </span>
                          )}
                          {t.currentOrderCode && (
                            <span
                              style={{
                                fontSize: "11px",
                                fontWeight: "700",
                                color: "var(--success)",
                                background: "var(--success-bg)",
                                padding: "2px 8px",
                                borderRadius: "4px",
                                border: "1px solid rgba(20, 106, 101, 0.2)",
                                letterSpacing: "0.02em",
                              }}
                            >
                              Đơn: {t.currentOrderCode}
                            </span>
                          )}
                        </div>
                      )}

                      {/* Danh sách món tóm tắt */}
                      <div
                        style={{
                          background: "var(--primary-light)",
                          borderRadius: "10px",
                          padding: "10px 12px",
                          border: "1px dashed rgba(126, 41, 48, 0.25)",
                          minHeight: "70px",
                          display: "flex",
                          flexDirection: "column",
                          justifyContent: "center",
                        }}
                      >
                        {orderItems.length > 0 ? (
                          <>
                            <div style={{ fontSize: "12px", fontWeight: "700", color: "var(--primary)", marginBottom: "4px" }}>
                              {orderItems.length} món đã gửi bếp:
                            </div>
                            <div style={{ fontSize: "13px", color: "var(--text)", lineHeight: 1.4 }}>
                              {orderItems.slice(0, 2).map((item, idx) => (
                                <div key={idx} style={{ display: "flex", flexWrap: "wrap", rowGap: "8px", justifyContent: "space-between" }}>
                                  <span style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", maxWidth: "160px" }}>
                                    • {item.name}
                                  </span>
                                  <span style={{ fontWeight: "600", color: "var(--primary)" }}>
                                    x{item.quantity || item.count || 1}
                                  </span>
                                </div>
                              ))}
                              {orderItems.length > 2 && (
                                <span style={{ fontSize: "11px", color: "var(--primary)", fontWeight: "600" }}>
                                  + {orderItems.length - 2} món khác...
                                </span>
                              )}
                            </div>
                          </>
                        ) : (
                          <div style={{ textAlign: "center", fontSize: "12px", color: "var(--primary)", fontStyle: "italic" }}>
                            Bàn đang mở • Chưa có món
                          </div>
                        )}
                      </div>

                      {/* Tổng tiền & Nút xem */}
                      <div
                        style={{
                          marginTop: "auto",
                          paddingTop: "10px",
                          borderTop: "1px solid var(--border-light)",
                          display: "flex", flexWrap: "wrap", rowGap: "8px",
                          alignItems: "center",
                          justifyContent: "space-between",
                        }}
                      >
                        <div>
                          <div style={{ fontSize: "11px", color: "var(--subtext)", textTransform: "uppercase" }}>
                            Tạm tính
                          </div>
                          <div style={{ fontSize: "17px", fontWeight: "800", color: "var(--primary)" }}>
                            {formatVND(orderTotal)} <span style={{ fontSize: "12px" }}>đ</span>
                          </div>
                        </div>

                        <button
                          className="btn-primary"
                          style={{ padding: "6px 12px", fontSize: "12px" }}
                          onClick={(e) => {
                            e.stopPropagation();
                            setSelectedTableForOrder(t);
                          }}
                        >
                          <Receipt size={14} />
                          Xem chi tiết
                        </button>
                      </div>
                    </div>
                  </div>
                );
              } else if (t.isReserved) {
                // Thẻ bàn ĐẶT TRƯỚC (Màu vàng hổ phách / Amber)
                return (
                  <div
                    key={t.id}
                    style={{
                      background: "var(--surface)",
                      borderRadius: "16px",
                      border: "2px solid var(--warning)",
                      boxShadow: "0 6px 18px rgba(217, 119, 6, 0.15)",
                      overflow: "hidden",
                      display: "flex",
                      flexDirection: "column",
                      transition: "transform 0.2s, box-shadow 0.2s",
                      position: "relative",
                    }}
                    onMouseEnter={(e) => {
                      e.currentTarget.style.transform = "translateY(-4px)";
                      e.currentTarget.style.boxShadow = "0 10px 24px rgba(217, 119, 6, 0.25)";
                    }}
                    onMouseLeave={(e) => {
                      e.currentTarget.style.transform = "translateY(0)";
                      e.currentTarget.style.boxShadow = "0 6px 18px rgba(217, 119, 6, 0.15)";
                    }}
                  >
                    {/* Header bàn đặt trước */}
                    <div
                      style={{
                        background: "linear-gradient(135deg, var(--warning) 0%, #B45309 100%)",
                        padding: "14px 16px",
                        display: "flex", flexWrap: "wrap", rowGap: "8px",
                        alignItems: "center",
                        justifyContent: "space-between",
                        color: "#FFFFFF",
                      }}
                    >
                      <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
                        <Bookmark size={18} color="#FFFFFF" />
                        <span style={{ fontSize: "14px", fontWeight: "700", lineHeight: 1.25, wordBreak: "break-word" }}>
                          {t.name}
                        </span>
                      </div>
                      <span
                        style={{
                          fontSize: "11px",
                          fontWeight: "700",
                          padding: "3px 8px",
                          borderRadius: "6px",
                          background: "rgba(255, 255, 255, 0.25)",
                          color: "#FFFFFF",
                        }}
                      >
                        {t.zone}
                      </span>
                    </div>

                    {/* Thân thẻ bàn đặt trước */}
                    <div style={{ padding: "16px", flex: 1, display: "flex", flexDirection: "column", gap: "10px" }}>
                      <div style={{ display: "flex", flexWrap: "wrap", rowGap: "8px", alignItems: "center", justifyContent: "space-between" }}>
                        <span className="badge badge-warning" style={{ background: "var(--warning-bg)", color: "#B45309", border: "1px solid #FDE68A" }}>
                          <Clock size={13} />
                          Đặt trước
                        </span>
                        {t.reservationTime && (
                          <span style={{ fontSize: "12px", color: "#B45309", fontWeight: "700", display: "flex", alignItems: "center", gap: "4px" }}>
                            <Clock size={14} /> {t.reservationTime}
                          </span>
                        )}
                      </div>

                      <div
                        style={{
                          background: "var(--warning-bg)",
                          borderRadius: "10px",
                          padding: "12px",
                          border: "1px dashed rgba(217, 119, 6, 0.35)",
                          display: "flex",
                          flexDirection: "column",
                          gap: "6px",
                          fontSize: "13px",
                        }}
                      >
                        <div style={{ display: "flex", alignItems: "center", gap: "6px", color: "var(--text)" }}>
                          <Users size={14} color="#D97706" />
                          <span>Khách: <strong>{t.reservationCustomer || "Khách hẹn"}</strong></span>
                        </div>
                        {t.reservationPhone && (
                          <div style={{ display: "flex", alignItems: "center", gap: "6px", color: "var(--subtext)", fontSize: "12px" }}>
                            <Phone size={13} color="#D97706" />
                            <span>SĐT: <strong>{t.reservationPhone}</strong></span>
                          </div>
                        )}
                        {t.reservationDeposit && t.reservationDeposit > 0 ? (
                          <div style={{ display: "flex", alignItems: "center", gap: "6px", color: "#065F46", fontSize: "12px", fontWeight: "700" }}>
                            <DollarSign size={13} color="#059669" />
                            <span>Tiền cọc: {formatVND(t.reservationDeposit)} đ</span>
                          </div>
                        ) : null}
                      </div>

                      {/* Thao tác nhận bàn / hủy đặt */}
                      <div
                        style={{
                          marginTop: "auto",
                          paddingTop: "10px",
                          borderTop: "1px solid var(--border-light)",
                          display: "flex", flexWrap: "wrap",
                          alignItems: "center",
                          justifyContent: "space-between",
                          gap: "8px",
                        }}
                      >
                        <button
                          onClick={() => handleCancelReservation(t)}
                          style={{
                            padding: "6px 10px",
                            borderRadius: "8px",
                            background: "rgba(180, 35, 44, 0.08)",
                            border: "1px solid rgba(180, 35, 44, 0.2)",
                            color: "var(--danger)",
                            fontSize: "12px",
                            fontWeight: "600",
                            cursor: "pointer",
                          }}
                        >
                          Hủy đặt
                        </button>
                        <button
                          className="btn-primary"
                          style={{ padding: "6px 14px", fontSize: "12px", background: "var(--warning)", borderColor: "#B45309" }}
                          onClick={() => handleCheckInReservation(t)}
                        >
                          <Check size={14} />
                          Nhận bàn
                        </button>
                      </div>
                    </div>
                  </div>
                );
              } else {
                // Thẻ bàn TRỐNG (Màu xanh ngọc / trung tính)
                return (
                  <div
                    key={t.id}
                    style={{
                      background: "var(--surface)",
                      borderRadius: "16px",
                      border: "1.5px solid var(--border)",
                      boxShadow: "0 2px 8px rgba(28, 26, 45, 0.04)",
                      overflow: "hidden",
                      display: "flex",
                      flexDirection: "column",
                      transition: "all 0.2s",
                    }}
                    onMouseEnter={(e) => {
                      e.currentTarget.style.borderColor = "#146A65";
                      e.currentTarget.style.transform = "translateY(-3px)";
                      e.currentTarget.style.boxShadow = "0 6px 16px rgba(20, 106, 101, 0.12)";
                    }}
                    onMouseLeave={(e) => {
                      e.currentTarget.style.borderColor = "#E6DEC8";
                      e.currentTarget.style.transform = "translateY(0)";
                      e.currentTarget.style.boxShadow = "0 2px 8px rgba(28, 26, 45, 0.04)";
                    }}
                  >
                    {/* Header bàn trống */}
                    <div
                      style={{
                        background: "var(--surface-muted)",
                        padding: "14px 16px",
                        display: "flex", flexWrap: "wrap", rowGap: "8px",
                        alignItems: "center",
                        justifyContent: "space-between",
                        borderBottom: "1px solid var(--border)",
                      }}
                    >
                      <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
                        <div
                          style={{
                            width: "9px",
                            height: "9px",
                            borderRadius: "50%",
                            background: "var(--success)",
                          }}
                        />
                        <span style={{ fontSize: "14px", fontWeight: "700", lineHeight: 1.25, wordBreak: "break-word", color: "var(--text)" }}>
                          {t.name}
                        </span>
                      </div>
                      <span
                        style={{
                          fontSize: "11px",
                          fontWeight: "600",
                          padding: "3px 8px",
                          borderRadius: "6px",
                          background: "var(--surface)",
                          border: "1px solid var(--border)",
                          color: "var(--subtext)",
                        }}
                      >
                        {t.zone}
                      </span>
                    </div>

                    {/* Thân bàn trống */}
                    <div style={{ padding: "16px", flex: 1, display: "flex", flexDirection: "column", gap: "14px" }}>
                      <div style={{ display: "flex", flexWrap: "wrap", rowGap: "8px", alignItems: "center", justifyContent: "space-between" }}>
                        <span className="badge badge-success">
                          <CheckCircle2 size={13} />
                          Bàn trống
                        </span>
                        <span style={{ fontSize: "12px", color: "var(--success)", fontWeight: "600" }}>
                          Sẵn sàng
                        </span>
                      </div>

                      <div
                        style={{
                          background: "var(--success-bg)",
                          borderRadius: "10px",
                          padding: "12px",
                          display: "flex",
                          alignItems: "center",
                          justifyContent: "center",
                          gap: "8px",
                          color: "var(--success)",
                          fontSize: "13px",
                          fontWeight: "500",
                        }}
                      >
                        <UtensilsCrossed size={16} />
                        Chưa có khách ngồi
                      </div>

                      {/* Thao tác quản lý */}
                      <div
                        style={{
                          marginTop: "auto",
                          paddingTop: "10px",
                          borderTop: "1px solid var(--border-light)",
                          display: "flex",
                          alignItems: "center",
                          justifyContent: "flex-end",
                          gap: "8px",
                        }}
                      >
                        {canOrderOnWeb && (
                          <button
                            className="btn-primary"
                            style={{ padding: "6px 12px", fontSize: "12px" }}
                            onClick={() => openOrderDialog(t)}
                          >
                            <ChefHat size={14} />
                            Gọi món
                          </button>
                        )}
                        <button
                          onClick={() => openEdit(t)}
                          style={{
                            padding: "6px 12px",
                            borderRadius: "8px",
                            background: "rgba(18, 108, 195, 0.08)",
                            border: "1px solid rgba(18, 108, 195, 0.2)",
                            color: "#126CC3",
                            fontSize: "12px",
                            fontWeight: "600",
                            cursor: "pointer",
                            display: "flex",
                            alignItems: "center",
                            gap: "4px",
                          }}
                        >
                          <Edit2 size={13} />
                          Sửa
                        </button>
                        <button
                          onClick={() => setDeleteId(t.id)}
                          style={{
                            padding: "6px 12px",
                            borderRadius: "8px",
                            background: "rgba(180, 35, 44, 0.08)",
                            border: "1px solid rgba(180, 35, 44, 0.2)",
                            color: "var(--danger)",
                            fontSize: "12px",
                            fontWeight: "600",
                            cursor: "pointer",
                            display: "flex",
                            alignItems: "center",
                            gap: "4px",
                          }}
                        >
                          <Trash2 size={13} />
                          Xóa
                        </button>
                      </div>
                    </div>
                  </div>
                );
              }
            })}
          </div>
        )
      ) : (
        /* Content: List Mode */
        <div className="table-wrapper">
          <table>
            <thead>
              <tr>
                <th>#</th>
                <th>Tên bàn</th>
                <th>Khu vực</th>
                <th>Trạng thái</th>
                <th>Khách / Thời gian</th>
                <th>Món đang gọi</th>
                <th>Tạm tính</th>
                <th>Thao tác</th>
              </tr>
            </thead>
            <tbody>
              {filtered.length === 0 ? (
                <tr>
                  <td colSpan={8} style={{ textAlign: "center", padding: "48px", color: "var(--subtext)" }}>
                    Không có dữ liệu bàn
                  </td>
                </tr>
              ) : (
                filtered.map((t, i) => {
                  const orderItems = parseOrderItems(t.currentOrderJson);
                  const orderTotal = calculateTableTotal(orderItems);
                  return (
                    <tr key={t.id}>
                      <td style={{ color: "var(--subtext)" }}>{i + 1}</td>
                      <td style={{ fontWeight: "700", color: "var(--text)", fontSize: "15px" }}>
                        <div>{t.name}</div>
                        {t.currentBillId && (
                          <div style={{ fontSize: "11px", fontWeight: "600", color: "var(--primary)", marginTop: "2px" }}>
                            HĐ: {t.currentBillId}
                          </div>
                        )}
                        {t.currentOrderCode && (
                          <div style={{ fontSize: "11px", fontWeight: "600", color: "var(--success)", marginTop: "1px" }}>
                            Đơn: {t.currentOrderCode}
                          </div>
                        )}
                      </td>
                      <td>
                        <span
                          className="badge"
                          style={{
                            background: "var(--surface-muted)",
                            color: "var(--text)",
                            border: "1px solid var(--border)",
                          }}
                        >
                          {t.zone}
                        </span>
                      </td>
                      <td>
                        {(() => {
                          const st = deriveTableStatus(t);
                          const cls =
                            st === "AWAITING_PAYMENT" ? "badge badge-awaiting" : st === "IN_USE" ? "badge badge-danger" : st === "RESERVED" ? "badge badge-warning" : "badge badge-success";
                          return <span className={cls}>{TABLE_STATUS_META[st].label}</span>;
                        })()}
                      </td>
                      <td>
                        {t.inUse ? (
                          <div style={{ fontSize: "13px" }}>
                            <div>👥 {t.guestCount || 1} khách</div>
                            <div style={{ fontSize: "11px", color: "var(--subtext)" }}>
                              ⏱ {getElapsedMinutes(t.openedAt)} phút
                            </div>
                          </div>
                        ) : t.isReserved ? (
                          <div style={{ fontSize: "12px", color: "#B45309" }}>
                            <div style={{ fontWeight: "700" }}>👤 {t.reservationCustomer || "Khách hẹn"}</div>
                            <div style={{ fontSize: "11px", color: "#78350F" }}>
                              {t.reservationTime ? `⏰ ${t.reservationTime}` : ""} {t.reservationPhone ? `• 📞 ${t.reservationPhone}` : ""}
                            </div>
                          </div>
                        ) : (
                          <span style={{ color: "var(--muted)" }}>—</span>
                        )}
                      </td>
                      <td>
                        {t.inUse && orderItems.length > 0 ? (
                          <span style={{ fontWeight: "600", color: "var(--primary)" }}>
                            {orderItems.length} món
                          </span>
                        ) : (
                          <span style={{ color: "var(--muted)" }}>—</span>
                        )}
                      </td>
                      <td>
                        {t.inUse ? (
                          <span style={{ fontWeight: "700", color: "var(--primary)" }}>
                            {formatVND(orderTotal)} đ
                          </span>
                        ) : (
                          <span style={{ color: "var(--muted)" }}>—</span>
                        )}
                      </td>
                      <td>
                        <div style={{ display: "flex", gap: "8px" }}>
                          {t.inUse && (
                            <button
                              onClick={() => handleTableTap(t)}
                              style={{
                                padding: "6px 10px",
                                borderRadius: "8px",
                                background: "var(--primary-light)",
                                border: "1px solid rgba(126, 41, 48, 0.3)",
                                color: "var(--primary)",
                                cursor: "pointer",
                                fontSize: "12px",
                                fontWeight: "600",
                                display: "flex",
                                alignItems: "center",
                                gap: "4px",
                              }}
                            >
                              <Receipt size={14} />
                              Hóa đơn
                            </button>
                          )}
                          {t.isReserved && (
                            <button
                              onClick={() => handleCheckInReservation(t)}
                              style={{
                                padding: "6px 10px",
                                borderRadius: "8px",
                                background: "var(--warning-bg)",
                                border: "1px solid #FDE68A",
                                color: "#B45309",
                                cursor: "pointer",
                                fontSize: "12px",
                                fontWeight: "600",
                                display: "flex",
                                alignItems: "center",
                                gap: "4px",
                              }}
                              title="Nhận khách vào bàn"
                            >
                              <Check size={14} />
                              Nhận bàn
                            </button>
                          )}
                          <button
                            onClick={() => openEdit(t)}
                            style={{
                              padding: "6px",
                              borderRadius: "8px",
                              background: "rgba(18, 108, 195, 0.08)",
                              border: "1px solid rgba(18, 108, 195, 0.2)",
                              color: "#126CC3",
                              cursor: "pointer",
                            }}
                            title="Sửa tên bàn / khu vực"
                          >
                            <Edit2 size={15} />
                          </button>
                          <button
                            onClick={() => setDeleteId(t.id)}
                            disabled={t.inUse}
                            style={{
                              padding: "6px",
                              borderRadius: "8px",
                              background: t.inUse ? "rgba(0,0,0,0.03)" : "rgba(180, 35, 44, 0.08)",
                              border: "1px solid",
                              borderColor: t.inUse ? "rgba(0,0,0,0.08)" : "rgba(180, 35, 44, 0.2)",
                              color: t.inUse ? "#9E9CA3" : "var(--danger)",
                              cursor: t.inUse ? "not-allowed" : "pointer",
                            }}
                            title={t.inUse ? "Không thể xóa bàn đang có khách" : "Xóa bàn"}
                          >
                            <Trash2 size={15} />
                          </button>
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

      {/* Modal: Xem chi tiết hóa đơn bàn (Table Order Details) */}
      {selectedTableForOrder && (
        <div className="modal-overlay" onClick={() => setSelectedTableForOrder(null)}>
          <div
            className="modal-content"
            style={{ maxWidth: "600px" }}
            onClick={(e) => e.stopPropagation()}
          >
            {/* Modal Header */}
            <div
              style={{
                padding: "20px 24px",
                background: "linear-gradient(135deg, var(--primary) 0%, var(--primary-dark) 100%)",
                color: "#FFFFFF",
                display: "flex", flexWrap: "wrap", rowGap: "8px",
                alignItems: "center",
                justifyContent: "space-between",
                borderRadius: "19px 19px 0 0",
              }}
            >
              <div>
                <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
                  <span style={{ fontSize: "20px", fontWeight: "800" }}>
                    {selectedTableForOrder.name}
                  </span>
                  <span
                    style={{
                      fontSize: "12px",
                      padding: "2px 8px",
                      borderRadius: "6px",
                      background: "rgba(255,255,255,0.2)",
                    }}
                  >
                    {selectedTableForOrder.zone}
                  </span>
                  {prePrintedAtOf(selectedTableForOrder) != null ? (
                    <span
                      style={{
                        fontSize: "12px",
                        padding: "2px 8px",
                        borderRadius: "6px",
                        background: "var(--table-awaiting)",
                        color: "var(--surface)",
                        fontWeight: 700,
                      }}
                    >
                      Chờ thanh toán
                    </span>
                  ) : (
                    <span
                      style={{
                        fontSize: "12px",
                        padding: "2px 8px",
                        borderRadius: "6px",
                        background: "var(--success)",
                      }}
                    >
                      Đang phục vụ
                    </span>
                  )}
                </div>
                <div style={{ display: "flex", alignItems: "center", gap: "12px", marginTop: "6px", flexWrap: "wrap" }}>
                  <div style={{ display: "flex", alignItems: "center", gap: "6px", background: "rgba(255,255,255,0.2)", borderRadius: "8px", padding: "2px 8px" }}>
                    <span style={{ fontSize: "12px" }}>👥 Số khách:</span>
                    <button
                      type="button"
                      onClick={() => handleUpdateGuestCount(selectedTableForOrder, Math.max(1, (selectedTableForOrder.guestCount || 1) - 1))}
                      style={{ background: "rgba(255,255,255,0.3)", border: "none", color: "#fff", width: "22px", height: "22px", borderRadius: "4px", cursor: "pointer", fontWeight: "bold", fontSize: "14px" }}
                      title="Giảm số khách"
                    >
                      -
                    </button>
                    <span style={{ fontSize: "13px", fontWeight: "800", minWidth: "18px", textAlign: "center" }}>
                      {selectedTableForOrder.guestCount || 1}
                    </span>
                    <button
                      type="button"
                      onClick={() => handleUpdateGuestCount(selectedTableForOrder, (selectedTableForOrder.guestCount || 1) + 1)}
                      style={{ background: "rgba(255,255,255,0.3)", border: "none", color: "#fff", width: "22px", height: "22px", borderRadius: "4px", cursor: "pointer", fontWeight: "bold", fontSize: "14px" }}
                      title="Tăng số khách"
                    >
                      +
                    </button>
                  </div>
                  <div style={{ fontSize: "12px", color: "rgba(255,255,255,0.85)" }}>
                    ⏱ Đã ngồi: <strong>{getElapsedMinutes(selectedTableForOrder.openedAt)} phút</strong>
                  </div>
                </div>
              </div>

              <button
                onClick={() => setSelectedTableForOrder(null)}
                style={{
                  background: "rgba(255,255,255,0.15)",
                  border: "none",
                  color: "#FFFFFF",
                  width: "32px",
                  height: "32px",
                  borderRadius: "50%",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  cursor: "pointer",
                }}
              >
                <X size={18} />
              </button>
            </div>

            {/* Modal Body: Danh sách món */}
            <div style={{ padding: "20px 24px" }}>
              {(() => {
                const at = prePrintedAtOf(selectedTableForOrder);
                if (at == null) return null;
                return (
                  <div
                    role="status"
                    style={{
                      background: "var(--table-awaiting-bg)",
                      color: "var(--table-awaiting)",
                      border: "1px solid color-mix(in srgb, var(--table-awaiting) 35%, transparent)",
                      borderRadius: "10px",
                      padding: "8px 12px",
                      fontSize: "12px",
                      fontWeight: 600,
                      marginBottom: "12px",
                    }}
                  >
                    🖨 Đã in tạm tính lúc {new Date(at).toLocaleTimeString("vi-VN", { hour: "2-digit", minute: "2-digit" })}
                    {selectedTableForOrder.prePrintedBy ? ` bởi ${selectedTableForOrder.prePrintedBy}` : ""} — sửa món sẽ hủy trạng thái chờ thanh toán.
                  </div>
                );
              })()}
              <div style={{ fontSize: "14px", fontWeight: "700", color: "var(--text)", marginBottom: "12px" }}>
                Danh sách món đã gửi bếp từ POS:
              </div>
              {!canDiscountItem && (
                <div style={{ fontSize: "11px", color: "var(--subtext)", marginBottom: "8px" }}>
                  Bạn không có quyền &quot;Giảm giá món&quot; — bấm nút giảm giá để nhờ Quản lý duyệt bằng PIN.
                </div>
              )}

              {parseOrderItems(selectedTableForOrder.currentOrderJson).length === 0 ? (
                <div
                  style={{
                    padding: "36px",
                    textAlign: "center",
                    color: "var(--subtext)",
                    background: "var(--bg)",
                    borderRadius: "12px",
                  }}
                >
                  <UtensilsCrossed size={32} style={{ margin: "0 auto 8px", color: "var(--primary)" }} />
                  <div>Chưa có dữ liệu món ăn được gửi bếp.</div>
                </div>
              ) : (
                <div
                  style={{
                    border: "1px solid var(--border)",
                    borderRadius: "12px",
                    overflowX: "auto",
                    marginBottom: "18px",
                  }}
                >
                  <table style={{ width: "100%", fontSize: "13px" }}>
                    <thead>
                      <tr style={{ background: "var(--surface-muted)" }}>
                        <th style={{ padding: "10px 14px" }}>Món ăn / Đồ uống</th>
                        <th style={{ padding: "10px 14px", textAlign: "center" }}>SL</th>
                        <th style={{ padding: "10px 14px", textAlign: "right" }}>Đơn giá</th>
                        <th style={{ padding: "10px 14px", textAlign: "right" }}>Thành tiền</th>
                        <th style={{ padding: "10px 8px", textAlign: "center" }}>
                          <span className="sr-only">Giảm giá / Xóa món</span>
                        </th>
                      </tr>
                    </thead>
                    <tbody>
                      {parseOrderItems(selectedTableForOrder.currentOrderJson).map((item, idx) => {
                        const line = item as unknown as RawOrderLine;
                        const qty = lineQuantity(line);
                        const itemPriceWithTopping = lineUnitPrice(line);
                        // Giảm giá dòng chỉ áp cho số phần được chọn (lineDiscountTotal; dữ liệu cũ: discountAmount cả dòng)
                        const lineTotal = Math.max(0, itemPriceWithTopping * qty - lineDiscountTotal(line));
                        const discountLabel = lineDiscountLabel(line, (n) => `${formatVND(n)}đ`);

                        return (
                          <tr key={idx} style={{ borderBottom: "1px solid var(--border-light)" }}>
                            <td style={{ padding: "12px 14px" }}>
                              <div style={{ fontWeight: "700", color: "var(--text)" }}>{item.name}</div>
                              {item.selectedSize && (
                                <div style={{ fontSize: "11px", color: "var(--subtext)" }}>
                                  Size: <span style={{ fontWeight: "600" }}>{item.selectedSize}</span>
                                </div>
                              )}
                              {Array.isArray(item.selectedToppings) &&
                                item.selectedToppings.length > 0 && (
                                  <div style={{ fontSize: "11px", color: "var(--success)" }}>
                                    + {item.selectedToppings.map(toppingLabel).filter(Boolean).join(", ")}
                                  </div>
                                )}
                              {item.note && (
                                <div style={{ fontSize: "11px", color: "var(--warning)", fontStyle: "italic" }}>
                                  Ghi chú: {item.note}
                                </div>
                              )}
                              {discountLabel && (
                                <div style={{ fontSize: "11px", color: "var(--danger)" }}>
                                  {discountLabel} (-{formatVND(lineDiscountTotal(line))}đ)
                                </div>
                              )}
                            </td>
                            <td style={{ padding: "12px 8px", textAlign: "center", fontWeight: "700" }}>
                              <div style={{ display: "inline-flex", alignItems: "center", gap: "6px" }}>
                                <button
                                  type="button"
                                  aria-label={`Giảm số lượng ${item.name}`}
                                  title={
                                    item.isSentKitchen && !canCancelKitchenItem
                                      ? "Món đã gửi bếp — cần Quản lý duyệt bằng PIN"
                                      : qty <= 1
                                        ? "Xóa món (cần lý do)"
                                        : "Giảm 1 phần (cần lý do)"
                                  }
                                  disabled={lineSaving}
                                  onClick={() => handleChangeLineQuantity(selectedTableForOrder, idx, -1)}
                                  style={qtyBtnStyle}
                                >
                                  <Minus size={13} />
                                </button>
                                <span style={{ minWidth: "18px" }}>{qty}</span>
                                <button
                                  type="button"
                                  aria-label={`Tăng số lượng ${item.name}`}
                                  title={item.isSentKitchen ? "Món đã gửi bếp — thêm phần trên POS để in phiếu bếp" : "Tăng 1 phần"}
                                  disabled={lineSaving || item.isSentKitchen === true}
                                  onClick={() => handleChangeLineQuantity(selectedTableForOrder, idx, 1)}
                                  style={qtyBtnStyle}
                                >
                                  <Plus size={13} />
                                </button>
                              </div>
                            </td>
                            <td style={{ padding: "12px 14px", textAlign: "right", color: "var(--subtext)" }}>
                              {formatVND(itemPriceWithTopping)}đ
                            </td>
                            <td style={{ padding: "12px 14px", textAlign: "right", fontWeight: "800", color: "var(--primary)" }}>
                              {formatVND(lineTotal)}đ
                            </td>
                            <td style={{ padding: "12px 8px", textAlign: "center" }}>
                              <div style={{ display: "inline-flex", gap: "6px" }}>
                              <button
                                type="button"
                                aria-label={`Giảm giá ${item.name}`}
                                title={canDiscountItem ? "Giảm giá món" : "Giảm giá món — Quản lý duyệt bằng PIN"}
                                disabled={lineSaving}
                                onClick={() => openLineDiscount(selectedTableForOrder, idx)}
                                style={{
                                  ...qtyBtnStyle,
                                  width: "32px",
                                  height: "32px",
                                  color: discountLabel ? "var(--danger)" : "var(--primary)",
                                }}
                              >
                                <Percent size={14} />
                              </button>
                              <button
                                type="button"
                                aria-label={`Xóa món ${item.name}`}
                                title={item.isSentKitchen && !canCancelKitchenItem ? "Xóa món đã gửi bếp — cần Quản lý duyệt bằng PIN" : "Xóa món (cần lý do)"}
                                disabled={lineSaving}
                                onClick={() => openRemoval(selectedTableForOrder, idx, qty)}
                                style={{ ...qtyBtnStyle, width: "32px", height: "32px", color: "var(--danger)" }}
                              >
                                <Trash2 size={14} />
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

              {/* Khách hàng & tích điểm */}
              <LoyaltyPanel
                customer={billCustomer}
                available={loyaltyAvailable && !loy.denied}
                unavailableReason={
                  loyaltyAvailable && loy.denied
                    ? "Vai trò hiện tại không đọc được danh sách khách của chi nhánh này."
                    : !roleReadsCustomers
                      ? "Vai trò hiện tại không được xem khách hàng của chi nhánh."
                      : undefined
                }
                showFullPhone={canViewCustomers || canManageCustomers}
                canRedeem={canRedeemPoints}
                isOwner={isLoyaltyOwner}
                balance={balance}
                rates={loy.rates}
                tiers={loy.tiers}
                amountBeforePoints={amountBeforePoints}
                pointsUsed={pointsUsedNow}
                onPointsChange={(n) => setPointsState({ key: pointsKey, n })}
                onPick={() => setShowCustomerPicker(true)}
                onRemove={() => handleRemoveCustomer(selectedTableForOrder)}
                busy={loyaltyBusy || completingPayment}
              />

              {/* Khuyến mãi & Voucher — nhân viên chọn chương trình hoặc nhập mã */}
              <PromotionPanel
                state={promo}
                storeCode={promoStoreCode}
                canApply={canApplyPromotion}
                billId={selectedTableForOrder.currentBillId || undefined}
              />

              {/* Total Calculation */}
              <div
                style={{
                  background: "var(--primary-light)",
                  borderRadius: "12px",
                  padding: "16px 20px",
                  border: "1.5px solid rgba(126, 41, 48, 0.2)",
                  display: "flex", flexWrap: "wrap", rowGap: "8px",
                  alignItems: "center",
                  justifyContent: "space-between",
                  marginBottom: "16px",
                }}
              >
                <div>
                  <div style={{ fontSize: "12px", color: "var(--subtext)", textTransform: "uppercase", fontWeight: "600" }}>
                    Tổng tiền tạm tính của bàn
                  </div>
                  <div style={{ fontSize: "11px", color: "var(--primary)", marginTop: "2px" }}>
                    {promo.applied.length > 0
                      ? `Đã trừ khuyến mãi: -${formatVND(promo.total)} VNĐ (${promo.applied.map((d) => d.campaignName).join(", ")})`
                      : "Chưa bao gồm khuyến mãi / VAT (nếu có khi thanh toán)"}
                    {pointsUsedNow > 0 && ` • Đã trừ ${formatVND(pointsUsedNow)} điểm: -${formatVND(pointsDiscountNow)} VNĐ`}
                  </div>
                </div>
                <div style={{ fontSize: "24px", fontWeight: "800", color: "var(--primary)" }}>
                  {formatVND(
                    Math.max(0, calculateTableTotal(parseOrderItems(selectedTableForOrder.currentOrderJson)) - promo.total - pointsDiscountNow)
                  )}{" "}
                  <span style={{ fontSize: "15px" }}>VNĐ</span>
                </div>
              </div>

              {/* Phương thức thanh toán */}
              <div style={{ marginBottom: "18px" }}>
                <div style={{ fontSize: "12px", fontWeight: "700", color: "var(--text)", marginBottom: "8px" }}>
                  Phương thức thanh toán:
                </div>
                <div className="grid-stack-sm" style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "10px" }}>
                  <button
                    type="button"
                    onClick={() => setPaymentMethod("CASH")}
                    style={{
                      padding: "10px 14px",
                      borderRadius: "10px",
                      border: paymentMethod === "CASH" ? "2px solid var(--primary)" : "1px solid var(--border)",
                      background: paymentMethod === "CASH" ? "var(--primary-light)" : "var(--surface)",
                      color: paymentMethod === "CASH" ? "var(--primary)" : "var(--subtext)",
                      fontWeight: paymentMethod === "CASH" ? "700" : "500",
                      fontSize: "13px",
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "center",
                      gap: "8px",
                      cursor: "pointer",
                      transition: "all 0.15s ease",
                    }}
                  >
                    <Banknote size={17} />
                    Tiền mặt
                  </button>
                  <button
                    type="button"
                    onClick={() => setPaymentMethod("TRANSFER")}
                    style={{
                      padding: "10px 14px",
                      borderRadius: "10px",
                      border: paymentMethod === "TRANSFER" ? "2px solid var(--success)" : "1px solid var(--border)",
                      background: paymentMethod === "TRANSFER" ? "var(--success-bg)" : "var(--surface)",
                      color: paymentMethod === "TRANSFER" ? "var(--success)" : "var(--subtext)",
                      fontWeight: paymentMethod === "TRANSFER" ? "700" : "500",
                      fontSize: "13px",
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "center",
                      gap: "8px",
                      cursor: "pointer",
                      transition: "all 0.15s ease",
                    }}
                  >
                    <QrCode size={17} />
                    Chuyển khoản VietQR
                  </button>
                </div>

                {/* Khối VietQR nếu chọn Chuyển khoản */}
                {paymentMethod === "TRANSFER" && (() => {
                  const targetStore =
                    stores.find(
                      (s) => s.storeCode === (selectedTableForOrder.storeCode || currentStoreCode)
                    ) || currentStore;
                  const bankId = targetStore?.bankId || "MB";
                  const bankAccount = targetStore?.bankAccount || "0987654321";
                  const accountName = targetStore?.accountName || "CHU CUA HANG TRAM FNB";
                  const orderTotal = Math.max(
                    0,
                    calculateTableTotal(parseOrderItems(selectedTableForOrder.currentOrderJson)) - promo.total - pointsDiscountNow
                  );
                  const qrUrl = `https://img.vietqr.io/image/${bankId}-${bankAccount}-compact2.png?amount=${orderTotal}&addInfo=${encodeURIComponent(
                    `TT BAN ${selectedTableForOrder.name}`
                  )}&accountName=${encodeURIComponent(accountName)}`;

                  return (
                    <div
                      style={{
                        marginTop: "12px",
                        padding: "12px 14px",
                        borderRadius: "12px",
                        background: "var(--surface-muted)",
                        border: "1.5px dashed var(--success)",
                        display: "flex",
                        alignItems: "center",
                        gap: "14px",
                      }}
                    >
                      <Image
                        src={qrUrl}
                        alt="Mã VietQR thanh toán"
                        width={90}
                        height={90}
                        unoptimized
                        style={{
                          width: "90px",
                          height: "90px",
                          borderRadius: "8px",
                          border: "1px solid var(--border)",
                          objectFit: "contain",
                          background: "#FFFFFF", // QR luôn cần nền trắng để quét được
                        }}
                      />
                      <div style={{ fontSize: "12px", lineHeight: "1.6", color: "var(--text)", flex: 1 }}>
                        <div style={{ fontWeight: "700", color: "var(--success)", marginBottom: "2px" }}>
                          Quét mã VietQR để thanh toán:
                        </div>
                        <div>
                          Ngân hàng: <strong>{bankId}</strong> • STK: <strong>{bankAccount}</strong>
                        </div>
                        <div>
                          Chủ TK: <strong>{accountName}</strong>
                        </div>
                        <div style={{ color: "var(--primary)", fontWeight: "700", marginTop: "2px" }}>
                          Số tiền: {formatVND(orderTotal)} VNĐ
                        </div>
                      </div>
                    </div>
                  );
                })()}
              </div>

              {/* Actions */}
              {(canTransferTable || canMergeTable || canOrderOnWeb) && (
                <div style={{ display: "flex", gap: "10px", flexWrap: "wrap", marginBottom: "10px" }}>
                  {canOrderOnWeb && (
                    <button
                      className="btn-primary"
                      onClick={() => openOrderDialog(selectedTableForOrder)}
                      disabled={completingPayment}
                      style={{ flex: 1, minWidth: "130px", justifyContent: "center" }}
                    >
                      <ChefHat size={16} />
                      Thêm món
                    </button>
                  )}
                  {canTransferTable && (
                    <button
                      className="btn-secondary"
                      onClick={() => openTableOp("TRANSFER", selectedTableForOrder)}
                      disabled={completingPayment}
                      style={{ flex: 1, minWidth: "130px", justifyContent: "center" }}
                    >
                      <ArrowRightLeft size={16} />
                      Chuyển bàn
                    </button>
                  )}
                  {canMergeTable && (
                    <button
                      className="btn-secondary"
                      onClick={() => openTableOp("MERGE", selectedTableForOrder)}
                      disabled={completingPayment}
                      style={{ flex: 1, minWidth: "130px", justifyContent: "center" }}
                    >
                      <GitMerge size={16} />
                      Gộp bàn
                    </button>
                  )}
                </div>
              )}
              <div style={{ display: "flex", gap: "10px", flexWrap: "wrap" }}>
                <button
                  className="btn-secondary"
                  onClick={() => printBill(selectedTableForOrder)}
                  style={{ flex: 1, minWidth: "110px", justifyContent: "center" }}
                >
                  <Printer size={16} />
                  In tạm tính
                </button>
                <button
                  className="btn-secondary"
                  onClick={() => handleCancelActiveTable(selectedTableForOrder)}
                  disabled={completingPayment}
                  style={{
                    flex: 1,
                    minWidth: "125px",
                    justifyContent: "center",
                    color: "#ef4444",
                    borderColor: "#fca5a5",
                    backgroundColor: "var(--danger-bg)",
                  }}
                >
                  <XCircle size={16} />
                  Hủy đơn bàn
                </button>
                <button
                  className="btn-primary"
                  onClick={() => handleCheckoutAndFreeTable(selectedTableForOrder)}
                  disabled={completingPayment}
                  style={{ flex: 1.5, minWidth: "160px", justifyContent: "center", opacity: completingPayment ? 0.7 : 1 }}
                >
                  <CheckCircle2 size={16} />
                  {completingPayment ? "Đang xử lý..." : "Thanh toán & Trả bàn"}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {showCustomerPicker && selectedTableForOrder && (
        <CustomerPickerDialog
          storeCode={promoStoreCode}
          customers={toPickerCustomers(loy.customers)}
          tiers={loy.tiers}
          loading={loy.loading}
          showFullPhone={canViewCustomers || canManageCustomers}
          canCreate={canManageCustomers}
          onSelect={(c) => handlePickCustomer(selectedTableForOrder, c)}
          onCreate={(name, phone) => handleCreateCustomer(selectedTableForOrder, name, phone)}
          onClose={() => setShowCustomerPicker(false)}
        />
      )}

      {orderTarget && (
        <WebOrderDialog
          tableName={orderTarget.name}
          zone={orderTarget.zone}
          opening={!orderTarget.inUse}
          existingCount={parseOrderItems(orderTarget.currentOrderJson).length}
          products={orderableProducts}
          categories={orderableCategories}
          catalog={orderCatalog}
          actor={orderActor}
          canSendKitchen={canSendKitchenFromWeb}
          saving={orderSaving}
          error={orderError}
          onCancel={() => setOrderTarget(null)}
          onSubmit={handleSubmitWebOrder}
        />
      )}

      {showZoneSetup && (
        <ZoneSetupDialog
          storeCode={currentStoreCode}
          actor={{ username: user?.username || "admin_web", fullName: user?.fullName, role: user?.roleId || user?.role }}
          onClose={() => setShowZoneSetup(false)}
        />
      )}

      {selectedTableForOrder && discountTarget && (() => {
        const line = (parseOrderItems(discountTarget.orderJson) as unknown as RawOrderLine[])[discountTarget.index];
        if (!line) return null;
        return (
          <LineDiscountDialog
            key={`${discountTarget.index}-${discountTarget.orderJson.length}`}
            line={line}
            saving={lineSaving}
            error={lineError}
            approval={canDiscountItem ? null : discountApproval}
            onCancel={closeLineDiscount}
            onSave={(next) => handleSaveLineDiscount(selectedTableForOrder, next)}
          />
        );
      })()}

      {removalTarget && (() => {
        const line = (parseOrderItems(removalTarget.orderJson) as unknown as RawOrderLine[])[removalTarget.index];
        if (!line) return null;
        return (
          <DeleteItemDialog
            key={`${removalTarget.index}-${removalTarget.orderJson.length}`}
            line={line}
            tableName={removalTarget.table.name}
            initialQty={removalTarget.initialQty}
            saving={lineSaving}
            error={lineError}
            needsPin={line.isSentKitchen === true && !canCancelKitchenItem}
            onCancel={() => {
              if (!lineSaving) setRemovalTarget(null);
            }}
            onConfirm={confirmRemoval}
          />
        );
      })()}

      {pinRequest && (
        <ManagerPinDialog
          storeCode={pinRequest.storeCode}
          action={pinRequest.action}
          context={pinRequest.context}
          approvers={approverOptions(
            usersList.filter((u) => (u.storeCode || pinRequest.storeCode) === pinRequest.storeCode),
            pinRequest.action,
            user?.uid
          )}
          onCancel={() => setPinRequest(null)}
          onApproved={(a) => {
            const cb = pinRequest.onApproved;
            setPinRequest(null);
            cb(a);
          }}
        />
      )}

      {showSetPin && (
        <SetApprovalPinDialog
          storeCode={user?.storeCode || resolveWriteStoreCode(currentStoreCode)}
          hasPin={myProfile?.hasApprovalPin === true}
          onClose={() => setShowSetPin(false)}
        />
      )}

      {tableOp && (
        <TableTransferDialog
          kind={tableOp.kind}
          source={tableOp.source}
          candidates={tableOpCandidates(tableOp.kind, tableOp.source)}
          busy={tableOpBusy}
          error={tableOpError}
          onPick={(t) => void handlePickTableOpTarget(t)}
          onCancel={() => {
            if (!tableOpBusy) setTableOp(null);
          }}
        />
      )}

      {/* Modal: Thêm / Sửa bàn */}
      {showModal && (
        <div className="modal-overlay" onClick={closeModal}>
          <div className="modal-content" style={{ maxWidth: "420px" }} onClick={(e) => e.stopPropagation()}>
            <div
              style={{
                padding: "20px 24px 0",
                display: "flex", flexWrap: "wrap", rowGap: "8px",
                alignItems: "center",
                justifyContent: "space-between",
                marginBottom: "20px",
              }}
            >
              <h2 style={{ fontSize: "18px", fontWeight: "800", color: "var(--text)" }}>
                {editId ? "Chỉnh sửa bàn" : "Thêm bàn mới"}
              </h2>
              <button
                onClick={closeModal}
                style={{ background: "none", border: "none", color: "var(--subtext)", cursor: "pointer" }}
              >
                <X size={20} />
              </button>
            </div>
            <div style={{ padding: "0 24px 24px", display: "flex", flexDirection: "column", gap: "16px" }}>
              <div>
                <label style={{ display: "block", fontSize: "13px", fontWeight: "700", color: "var(--text)", marginBottom: "6px" }}>
                  Tên bàn *
                </label>
                <input
                  type="text"
                  className="input-field"
                  placeholder="Ví dụ: Bàn 01, A1, B3..."
                  value={form.name}
                  onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))}
                />
              </div>

              <div>
                <label style={{ display: "block", fontSize: "13px", fontWeight: "700", color: "var(--text)", marginBottom: "6px" }}>
                  Khu vực
                </label>
                <input
                  type="text"
                  className="input-field"
                  placeholder="Ví dụ: Tầng 1, Tầng 2, Khu A, Sân Vườn..."
                  value={form.zone}
                  onChange={(e) => setForm((f) => ({ ...f, zone: e.target.value }))}
                  list="zone-suggestions"
                />
                <datalist id="zone-suggestions">
                  {zones.map((z, i) => (
                    <option key={z + "-" + i} value={z} />
                  ))}
                </datalist>
                <p style={{ fontSize: "11px", color: "var(--subtext)", marginTop: "4px" }}>
                  Chọn khu vực có sẵn hoặc nhập tên khu vực mới để hệ thống tự tạo nhóm.
                </p>
              </div>

              {error && (
                <div
                  style={{
                    background: "rgba(180, 35, 44, 0.1)",
                    border: "1px solid rgba(180, 35, 44, 0.3)",
                    borderRadius: "8px",
                    padding: "10px 14px",
                    color: "var(--danger)",
                    fontSize: "13px",
                  }}
                >
                  {error}
                </div>
              )}

              <div style={{ display: "flex", gap: "10px", marginTop: "8px" }}>
                <button className="btn-secondary" onClick={closeModal} style={{ flex: 1, justifyContent: "center" }}>
                  Hủy
                </button>
                <button
                  className="btn-primary"
                  onClick={handleSave}
                  disabled={saving}
                  style={{ flex: 1, justifyContent: "center", opacity: saving ? 0.7 : 1 }}
                >
                  {saving ? (
                    <div className="spinner" style={{ width: "16px", height: "16px" }} />
                  ) : (
                    <Check size={16} />
                  )}
                  {editId ? "Cập nhật" : "Thêm mới"}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Delete Confirm Modal */}
      {deleteId && (
        <div className="modal-overlay" onClick={() => setDeleteId(null)}>
          <div className="modal-content" style={{ maxWidth: "380px" }} onClick={(e) => e.stopPropagation()}>
            <div style={{ padding: "28px", textAlign: "center" }}>
              <div style={{ fontSize: "44px", marginBottom: "14px" }}>🗑️</div>
              <h2 style={{ fontSize: "18px", fontWeight: "800", color: "var(--text)", marginBottom: "8px" }}>
                Xác nhận xóa bàn
              </h2>
              <p style={{ color: "var(--subtext)", fontSize: "14px", marginBottom: "24px" }}>
                Bạn có chắc chắn muốn xóa bàn này khỏi hệ thống? Thao tác này không thể hoàn tác.
              </p>
              <div style={{ display: "flex", gap: "10px" }}>
                <button className="btn-secondary" onClick={() => setDeleteId(null)} style={{ flex: 1, justifyContent: "center" }}>
                  Hủy
                </button>
                <button className="btn-danger" onClick={() => handleDelete(deleteId)} style={{ flex: 1, justifyContent: "center" }}>
                  <Trash2 size={16} />
                  Xóa bàn
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
