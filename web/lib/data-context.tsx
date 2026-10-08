"use client";
import React, { createContext, useContext, useEffect, useState, useCallback, useMemo } from "react";
import { db, auth } from "./firebase";
import { ref, onValue, query, limitToLast, set, update, remove, get, push } from "firebase/database";
import { onAuthStateChanged } from "firebase/auth";
import { deduplicateBills } from "./reports";

export interface OrderActionLog {
  timestamp: number | string;
  staffUsername?: string;
  staffFullName?: string;
  action: string;
  details: string;
}

export interface OrderItem {
  id?: number | string;
  productId?: number | string;
  name: string;
  price: number;
  costPrice?: number;
  unitCost?: number;
  lineCostPrice?: number;
  quantity?: number;
  count?: number;
  unit?: string;
  category?: string;
  selectedSize?: string;
  selectedSugar?: string;
  selectedIce?: string;
  selectedToppings?: any[];
  toppingPrice?: number;
  sizeExtraPrice?: number;
  discountAmount?: number;
  lineGrossAmount?: number;
  lineTotal?: number;
  note?: string;
  orderedBy?: string;
  orderedByName?: string;
  orderedAt?: number | string;
  optionsSummary?: string;
}

export interface HistoryOrder {
  id: string;
  storeCode?: string;
  storeName?: string;
  billCode?: string;
  orderCode?: string;
  tableName?: string;
  zone?: string;
  guestCount?: number;
  paymentMethod?: string;
  status?: string;
  totalAmount?: number;
  subTotal?: number;
  finalAmount?: number;
  discountAmount?: number;
  totalDiscount?: number;
  itemDiscounts?: number;
  billDiscounts?: number;
  pointsDiscount?: number;
  pointsUsed?: number;
  vatRate?: number;
  vatAmount?: number;
  refundAmount?: number;
  cogs?: number;
  timestamp?: number | string;
  createdAt?: number | string;
  closedAt?: number | string;
  username?: string;
  createdBy?: string;
  creatorName?: string;
  staffFullName?: string;
  staffUsername?: string;
  cashierName?: string;
  orderStaff?: string;
  shiftId?: string;
  parentBillId?: string | null;
  mergedTableNames?: string[] | null;
  items?: OrderItem[];
  actionLogs?: OrderActionLog[];
  [key: string]: any;
}

export interface TableItem {
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
  [key: string]: any;
}

export interface ProductItem {
  id: string;
  storeCode?: string;
  storeName?: string;
  code?: string;
  productCode?: string;
  name: string;
  price: number;
  costPrice?: number;
  unit: string;
  category: string;
  imageBase64?: string;
  isTopping?: boolean;
}

export interface CategoryItem {
  id: string;
  storeCode?: string;
  storeName?: string;
  name: string;
  allowedToppingIds?: string[];
}

export interface UserItem {
  id: string;
  storeCode?: string;
  storeName?: string;
  fullName: string;
  username: string;
  role: string;
  roleId?: string;
  password?: string;
  phone?: string;
  isActive?: boolean;
  isRootOwner?: boolean;
  customPermissions?: string[];
  [key: string]: any;
}

export interface AuditLogItem {
  id: string;
  storeCode?: string;
  action: string;
  details?: string;
  timestamp?: number | string;
  username?: string;
  userFullName?: string;
  userRole?: string;
  targetType?: string;
  targetId?: string;
  isSuspicious?: boolean;
  beforeState?: Record<string, any>;
  afterState?: Record<string, any>;
  [key: string]: any;
}

export interface StoreItem {
  id: string;
  storeCode: string;
  storeName: string;
  address?: string;
  phone?: string;
  wifiName?: string;
  bankId?: string;
  bankAccount?: string;
  accountName?: string;
  defaultVatRate?: number;
  allowStackPromotions?: boolean;
  allowStaffViewShiftDifference?: boolean;
  active?: boolean;
  createdAt?: number | string;
  totalTables?: number;
  inUseTables?: number;
  totalRevenue?: number;
  totalOrders?: number;
  [key: string]: any;
}

export interface CashShiftItem {
  id: string;
  shiftCode: string;
  shiftName?: string;
  storeCode: string;
  staffUsername: string;
  staffFullName: string;
  openedAt: number;
  closedAt?: number;
  initialCash: number;
  totalCashSales: number;
  totalQrSales: number;
  totalCardSales: number;
  cashIn: number;
  cashOut: number;
  actualCash?: number;
  difference?: number;
  status: "OPEN" | "CLOSED";
  notes?: string;
  [key: string]: any;
}

interface DashboardContextType {
  stores: StoreItem[];
  currentStoreCode: string; // 'ALL' or specific storeCode (e.g. 'TRAM01')
  currentStore?: StoreItem;
  setCurrentStoreCode: (code: string) => void;
  createStore: (storeData: Partial<StoreItem>, copyMenuFrom?: string) => Promise<{ success: boolean; error?: string }>;
  updateStore: (storeCode: string, data: Partial<StoreItem>) => Promise<{ success: boolean; error?: string }>;
  deleteStore: (storeCode: string) => Promise<{ success: boolean; error?: string }>;
  updateStoreShiftDifferenceSetting: (storeCode: string, allow: boolean) => Promise<{ success: boolean; error?: string }>;

  checkoutAndFreeTable: (
    table: TableItem,
    options?: {
      paymentMethod?: "CASH" | "TRANSFER";
      staffName?: string;
      discountAmount?: number;
    }
  ) => Promise<{ success: boolean; billId?: string; error?: string }>;
  saveTable: (
    tableData: { id?: string; name: string; zone: string; inUse?: boolean },
    storeCode?: string
  ) => Promise<{ success: boolean; error?: string }>;
  deleteTable: (tableId: string, storeCode?: string) => Promise<{ success: boolean; error?: string }>;
  saveProduct: (
    productData: { id?: string; name: string; code?: string; price: number; costPrice?: number; unit?: string; category?: string; imageBase64?: string; isTopping?: boolean },
    storeCode?: string
  ) => Promise<{ success: boolean; error?: string }>;
  deleteProduct: (productId: string, storeCode?: string) => Promise<{ success: boolean; error?: string }>;
  saveCategory: (
    categoryName: string,
    storeCode?: string,
    oldCategoryName?: string,
    allowedToppingIds?: string[]
  ) => Promise<{ success: boolean; error?: string }>;
  deleteCategory: (
    categoryName: string,
    storeCode?: string
  ) => Promise<{ success: boolean; error?: string }>;
  saveUser: (
    userData: {
      username: string;
      fullName: string;
      password?: string;
      role: string;
      phone?: string;
      isActive?: boolean;
      storeCode?: string;
    },
    targetStoreCode?: string
  ) => Promise<{ success: boolean; error?: string }>;
  deleteUser: (username: string, storeCode?: string) => Promise<{ success: boolean; error?: string }>;
  cancelActiveTable: (
    table: TableItem,
    reason: string,
    staffName?: string
  ) => Promise<{ success: boolean; billId?: string; error?: string }>;
  cancelOrder: (orderId: string, reason: string, storeCode?: string) => Promise<{ success: boolean; error?: string }>;
  deleteOrder: (orderId: string, storeCode?: string) => Promise<{ success: boolean; error?: string }>;

  tables: TableItem[];
  allTables: TableItem[];
  historyData: HistoryOrder[];
  products: ProductItem[];
  allProducts: ProductItem[];
  categories: CategoryItem[];
  allCategories: CategoryItem[];
  usersList: UserItem[];
  allUsers: UserItem[];
  auditLogs: AuditLogItem[];
  onlineOrders: any[];
  cashShifts: CashShiftItem[];
  loading: boolean;
  historyLoaded: boolean;
  refreshAll: () => void;
}

const DashboardContext = createContext<DashboardContextType>({
  stores: [],
  currentStoreCode: "ALL",
  setCurrentStoreCode: () => {},
  createStore: async () => ({ success: false }),
  updateStore: async () => ({ success: false }),
  deleteStore: async () => ({ success: false }),
  updateStoreShiftDifferenceSetting: async () => ({ success: false }),

  checkoutAndFreeTable: async () => ({ success: false }),
  cancelActiveTable: async () => ({ success: false }),
  saveTable: async () => ({ success: false }),
  deleteTable: async () => ({ success: false }),
  saveProduct: async () => ({ success: false }),
  deleteProduct: async () => ({ success: false }),
  saveCategory: async () => ({ success: false }),
  deleteCategory: async () => ({ success: false }),
  saveUser: async () => ({ success: false }),
  deleteUser: async () => ({ success: false }),
  cancelOrder: async () => ({ success: false }),
  deleteOrder: async () => ({ success: false }),

  tables: [],
  allTables: [],
  historyData: [],
  products: [],
  allProducts: [],
  categories: [],
  allCategories: [],
  usersList: [],
  allUsers: [],
  auditLogs: [],
  onlineOrders: [],
  cashShifts: [],
  loading: true,
  historyLoaded: false,
  refreshAll: () => {},
});

// Helper to strip heavy base64 strings from history items to optimize memory & render speed
function sanitizeHistoryOrder(raw: any, id: string): HistoryOrder {
  const mapItem = (it: any): OrderItem => {
    const { imageBase64, ...rest } = it;
    return {
      ...rest,
      price: Number(rest.price || 0),
      quantity: Number(rest.quantity || rest.count || 1),
      costPrice: rest.costPrice != null ? Number(rest.costPrice) : (rest.unitCost != null ? Number(rest.unitCost) : 0),
      unitCost: rest.unitCost != null ? Number(rest.unitCost) : (rest.costPrice != null ? Number(rest.costPrice) : 0),
      lineCostPrice: rest.lineCostPrice != null ? Number(rest.lineCostPrice) : undefined,
      lineGrossAmount: rest.lineGrossAmount != null ? Number(rest.lineGrossAmount) : undefined,
      lineTotal: rest.lineTotal != null ? Number(rest.lineTotal) : undefined,
      discountAmount: Number(rest.discountAmount || 0),
    };
  };

  let items: OrderItem[] = [];
  if (Array.isArray(raw.items)) {
    items = raw.items.map(mapItem);
  } else if (raw.itemsJson) {
    try {
      const parsed = typeof raw.itemsJson === "string" ? JSON.parse(raw.itemsJson) : raw.itemsJson;
      if (Array.isArray(parsed)) {
        items = parsed.map(mapItem);
      }
    } catch {
      items = [];
    }
  }

  // Parse actionLogs
  let actionLogs: OrderActionLog[] = [];
  if (Array.isArray(raw.actionLogs)) {
    actionLogs = raw.actionLogs;
  } else if (raw.actionLogsJson) {
    try {
      const parsed = typeof raw.actionLogsJson === "string" ? JSON.parse(raw.actionLogsJson) : raw.actionLogsJson;
      if (Array.isArray(parsed)) {
        actionLogs = parsed;
      }
    } catch {
      actionLogs = [];
    }
  }

  // Determine orderStaff (Người nhận đơn / người nhận order)
  let orderStaff = raw.orderStaff || "";
  if (!orderStaff) {
    const staffSet = new Set<string>();
    items.forEach((it) => {
      if (it.orderedByName) staffSet.add(it.orderedByName);
    });
    if (staffSet.size > 0) {
      orderStaff = Array.from(staffSet).join(", ");
    } else {
      orderStaff = raw.staffFullName || raw.creatorName || raw.username || "Nhân viên Order";
    }
  }

  // Determine cashierName (Người thanh toán / thu ngân)
  const cashierName = raw.cashierName || raw.staffFullName || raw.username || raw.createdBy || "Thu ngân";

  // If actionLogs is empty, synthesize realistic logs based on order info for seamless display
  if (actionLogs.length === 0) {
    const timeCreated = raw.createdAt || raw.timestamp || Date.now();
    const timeClosed = raw.closedAt || raw.timestamp || Date.now();
    actionLogs = [
      {
        timestamp: timeCreated,
        staffFullName: orderStaff,
        action: "ADD_ITEMS",
        details: `${orderStaff} tạo order & nhận ${items.length || 1} món (${items.map((it) => it.name).join(", ") || "Order bàn"})`,
      },
      {
        timestamp: timeClosed,
        staffFullName: cashierName,
        action: "PAY_BILL",
        details: `${cashierName} thanh toán hóa đơn ${new Intl.NumberFormat("vi-VN", { style: "currency", currency: "VND" }).format(Number(raw.totalAmount || raw.finalAmount) || 0)} (${raw.paymentMethod || "Tiền mặt"})`,
      },
    ];
  }

  const storeCode = raw.storeCode || (raw.id && raw.id.includes("TRAM02") ? "TRAM02" : "TRAM01");
  const subTotal = Number(raw.subTotal != null ? raw.subTotal : (raw.totalAmount || 0));
  const finalAmount = Number(raw.finalAmount != null ? raw.finalAmount : (raw.totalAmount || 0));
  const totalAmount = finalAmount;
  const totalDiscount = Number(raw.totalDiscount != null ? raw.totalDiscount : (raw.discountAmount || 0));
  const discountAmount = totalDiscount;
  const vatAmount = Number(raw.vatAmount || 0);
  const vatRate = Number(raw.vatRate || 0);
  const pointsDiscount = Number(raw.pointsDiscount || 0);
  const pointsUsed = Number(raw.pointsUsed || 0);
  const refundAmount = Number(raw.refundAmount || 0);
  const guestCount = Number(raw.guestCount || 0);
  const cogs = Number(raw.cogs || 0);

  return {
    ...raw,
    id,
    storeCode,
    items,
    totalAmount,
    finalAmount,
    subTotal,
    totalDiscount,
    discountAmount,
    vatAmount,
    vatRate,
    pointsDiscount,
    pointsUsed,
    refundAmount,
    guestCount,
    cogs,
    orderStaff,
    cashierName,
    actionLogs,
    itemsJson: undefined,
  };
}

export function DashboardDataProvider({ children }: { children: React.ReactNode }) {
  // Store management state
  const [stores, setStores] = useState<StoreItem[]>([]);
  const [currentStoreCode, setCurrentStoreCodeState] = useState<string>(() => {
    if (typeof window === "undefined") return "ALL";
    try {
      return sessionStorage.getItem("tram_current_store") || "ALL";
    } catch {
      return "ALL";
    }
  });

  const setCurrentStoreCode = useCallback((code: string) => {
    setCurrentStoreCodeState(code);
    try {
      sessionStorage.setItem("tram_current_store", code);
    } catch {}
  }, []);

  // Pre-load from sessionStorage for instant (0ms) render if available
  const [rawTables, setRawTables] = useState<Record<string, TableItem[]>>({});
  const [allHistory, setAllHistory] = useState<HistoryOrder[]>([]);
  const [rawProductsMap, setRawProductsMap] = useState<Record<string, ProductItem[]>>({});
  const [rawCategoriesMap, setRawCategoriesMap] = useState<Record<string, CategoryItem[]>>({});
  const [rawUsersMap, setRawUsersMap] = useState<Record<string, UserItem[]>>({});
  const [rawAuditLogs, setRawAuditLogs] = useState<AuditLogItem[]>([]);
  const [onlineOrders, setOnlineOrders] = useState<any[]>([]);
  const [rawCashShifts, setRawCashShifts] = useState<Record<string, CashShiftItem[]>>({});

  const [loading, setLoading] = useState<boolean>(true);
  const [historyLoaded, setHistoryLoaded] = useState<boolean>(false);

  // Xử lý dữ liệu gom từ các chi nhánh được cấp quyền
  const processStoreDataMap = useCallback((dataMap: Record<string, any>) => {
    const entries = Object.entries(dataMap);
    if (entries.length === 0) {
      // Fallback default store nếu chưa có dữ liệu chi nhánh
      setStores([
        {
          id: "TRAM01",
          storeCode: "TRAM01",
          storeName: "POS Trạm - Trụ sở 01 (Đà Lạt)",
          address: "Số 123 Đường Ba Tháng Tư, Phường 3, TP. Đà Lạt",
          phone: "0987654321",
          bankId: "MB",
          bankAccount: "0987654321",
          accountName: "CHU CUA HANG TRAM FNB",
          defaultVatRate: 8,
          allowStackPromotions: true,
          allowStaffViewShiftDifference: true,
          active: true,
        }
      ]);
      setAllHistory([]);
      setHistoryLoaded(true);
      setRawAuditLogs([]);
      setOnlineOrders([]);
      setRawTables({});
      setRawCashShifts({});
      setRawProductsMap({});
      setRawCategoriesMap({});
      setRawUsersMap({});
      setLoading(false);
      return;
    }

    const list: StoreItem[] = [];
    const shiftsMap: Record<string, CashShiftItem[]> = {};
    const prodsMap: Record<string, ProductItem[]> = {};
    const catsMap: Record<string, CategoryItem[]> = {};
    const usersMap: Record<string, UserItem[]> = {};
    const branchTablesMap: Record<string, TableItem[]> = {};
    const historyList: HistoryOrder[] = [];
    const logsList: AuditLogItem[] = [];
    const onlineList: any[] = [];

    entries.forEach(([code, val]: [string, any]) => {
      if (!val) return;
      const info = val.storeInfo || val;
      list.push({
        id: code,
        storeCode: code,
        storeName: info.storeName || `POS Trạm (${code})`,
        address: info.address || "",
        phone: info.phone || "",
        wifiName: info.wifiName || "",
        bankId: info.bankId || "MB",
        bankAccount: info.bankAccount || "",
        accountName: info.accountName || "CHU QUAN FNB",
        defaultVatRate: info.defaultVatRate ?? 8,
        allowStackPromotions: info.allowStackPromotions ?? true,
        allowStaffViewShiftDifference: info.allowStaffViewShiftDifference ?? true,
        active: info.active ?? true,
        createdAt: info.createdAt || Date.now(),
      });

      if (val.cash_shifts) {
        const sList: CashShiftItem[] = [];
        Object.entries(val.cash_shifts).forEach(([id, s]: [string, any]) => {
          sList.push({
            ...s,
            id,
            storeCode: s.storeCode || code,
          });
        });
        shiftsMap[code] = sList;
      }

      if (val.products) {
        const pList: ProductItem[] = [];
        Object.entries(val.products).forEach(([id, p]: [string, any]) => {
          pList.push({
            ...p,
            id,
            price: Number(p.price || 0),
            costPrice: p.costPrice != null ? Number(p.costPrice) : 0,
            storeCode: code,
            storeName: info.storeName || code,
          });
        });
        prodsMap[code] = pList;
      }

      if (val.categories) {
        const cList: CategoryItem[] = [];
        Object.entries(val.categories).forEach(([id, c]: [string, any]) => {
          cList.push({
            id,
            name: typeof c === "string" ? c : (c.name || id),
            allowedToppingIds: typeof c === "object" && c !== null && Array.isArray(c.allowedToppingIds) ? c.allowedToppingIds : [],
            storeCode: code,
          });
        });
        catsMap[code] = cList;
      }

      if (val.users) {
        const uList: UserItem[] = [];
        Object.entries(val.users).forEach(([id, u]: [string, any]) => {
          const uName = u.username || id;
          uList.push({
            ...u,
            id: uName,
            username: uName,
            fullName: u.fullName || u.name || uName,
            role: u.roleId || u.role || "ROLE_WAITER",
            roleId: u.roleId || u.role || "ROLE_WAITER",
            phone: u.phone || "",
            password: u.password || "",
            isActive: u.isActive !== false,
            isRootOwner: u.isRootOwner === true || (u.roleId || u.role || "").toUpperCase().includes("OWNER"),
            storeCode: u.storeCode || code,
            storeName: info.storeName || code,
          });
        });
        usersMap[code] = uList;
      }

      if (val.tables) {
        const tArr: TableItem[] = [];
        Object.entries(val.tables).forEach(([id, v]: any) => {
          tArr.push({
            ...v,
            id,
            storeCode: code,
            storeName: info.storeName || code,
            inUse: Boolean(v.inUse),
          });
        });
        branchTablesMap[code] = tArr;
      }

      const historySource = val.history || val.bills;
      if (historySource) {
        Object.entries(historySource).forEach(([id, v]: any) => {
          const sanitized = sanitizeHistoryOrder(v, id);
          sanitized.storeCode = sanitized.storeCode || code;
          sanitized.storeName = sanitized.storeName || info.storeName || code;
          historyList.push(sanitized);
        });
      }

      if (val.audit_logs) {
        Object.entries(val.audit_logs).forEach(([id, v]: any) => {
          logsList.push({
            ...v,
            id,
            storeCode: v.storeCode || code,
            storeName: v.storeName || info.storeName || code,
          });
        });
      }

      if (val.online_orders) {
        Object.entries(val.online_orders).forEach(([id, v]: any) => {
          onlineList.push({
            ...v,
            id,
            storeCode: v.storeCode || code,
            storeName: v.storeName || info.storeName || code,
          });
        });
      }
    });

    list.sort((a, b) => a.storeCode.localeCompare(b.storeCode));
    setStores(list);
    setRawCashShifts(shiftsMap);
    setRawProductsMap(prodsMap);
    setRawCategoriesMap(catsMap);
    setRawUsersMap(usersMap);
    setRawTables(branchTablesMap);

    const dedupedHistory = deduplicateBills(historyList);
    dedupedHistory.sort((a, b) => {
      const ta = typeof a.timestamp === "number" ? a.timestamp : new Date(a.timestamp || 0).getTime();
      const tb = typeof b.timestamp === "number" ? b.timestamp : new Date(b.timestamp || 0).getTime();
      return tb - ta;
    });
    setAllHistory(dedupedHistory);
    setHistoryLoaded(true);

    logsList.sort((a, b) => {
      const ta = typeof a.timestamp === "number" ? a.timestamp : new Date(a.timestamp || 0).getTime();
      const tb = typeof b.timestamp === "number" ? b.timestamp : new Date(b.timestamp || 0).getTime();
      return tb - ta;
    });
    setRawAuditLogs(logsList);
    setOnlineOrders(onlineList);
    setLoading(false);
  }, []);

  // 1. Lắng nghe đa chi nhánh theo đúng phân quyền RBAC (stores/$storeCode)
  useEffect(() => {
    let isMounted = true;
    const storeListeners = new Map<string, () => void>();
    const storeDataMap: Record<string, any> = {};

    function updateStoreSubscriptions(storeCodes: string[]) {
      const uniqueCodes = Array.from(new Set(storeCodes.filter(Boolean)));
      if (uniqueCodes.length === 0) {
        uniqueCodes.push("TRAM01");
      }

      // 1. Hủy lắng nghe các store không còn trong danh sách
      for (const [code, unsub] of storeListeners.entries()) {
        if (!uniqueCodes.includes(code)) {
          unsub();
          storeListeners.delete(code);
          delete storeDataMap[code];
        }
      }

      // 2. Thêm listener cho các store mới
      uniqueCodes.forEach((code) => {
        if (!storeListeners.has(code)) {
          const storeRef = ref(db, `stores/${code}`);
          const unsub = onValue(
            storeRef,
            (snap) => {
              if (!isMounted) return;
              if (snap.exists()) {
                storeDataMap[code] = snap.val();
              } else {
                delete storeDataMap[code];
              }
              processStoreDataMap(storeDataMap);
            },
            (error) => {
              if (!isMounted) return;
              console.warn(`[data-context] Không thể đọc stores/${code}:`, error.message);
              delete storeDataMap[code];
              processStoreDataMap(storeDataMap);
            }
          );
          storeListeners.set(code, unsub);
        }
      });
    }

    let unsubUserIndex: (() => void) | null = null;

    const unsubAuth = onAuthStateChanged(auth, (fbUser) => {
      if (!isMounted) return;

      if (unsubUserIndex) {
        unsubUserIndex();
        unsubUserIndex = null;
      }

      if (!fbUser) {
        for (const unsub of storeListeners.values()) {
          unsub();
        }
        storeListeners.clear();
        processStoreDataMap({});
        return;
      }

      // Đăng nhập: Đọc userIndex/{uid} để lấy danh sách cửa hàng được cấp quyền
      const userIndexRef = ref(db, `userIndex/${fbUser.uid}`);
      unsubUserIndex = onValue(
        userIndexRef,
        (indexSnap) => {
          if (!isMounted) return;
          const userIndexStores = indexSnap.exists() ? Object.keys(indexSnap.val() || {}) : [];
          const candidateStores = Array.from(new Set([...userIndexStores, "TRAM01"]));
          updateStoreSubscriptions(candidateStores);
        },
        (error) => {
          if (!isMounted) return;
          console.warn("[data-context] Không thể đọc userIndex:", error.message);
          updateStoreSubscriptions(["TRAM01"]);
        }
      );
    });

    return () => {
      isMounted = false;
      unsubAuth();
      if (unsubUserIndex) unsubUserIndex();
      for (const unsub of storeListeners.values()) {
        unsub();
      }
      storeListeners.clear();
    };
  }, [processStoreDataMap]);

  // Compute allTables (Flattened from all branches)
  const allTables = useMemo(() => {
    const map = new Map<string, TableItem>();
    const tram01Tables = rawTables["TRAM01"] || [];
    tram01Tables.forEach((t) => map.set(`TRAM01_${t.name}`, { ...t, storeCode: "TRAM01" }));

    Object.entries(rawTables).forEach(([sCode, tList]) => {
      if (sCode !== "TRAM01") {
        tList.forEach((t) => map.set(`${sCode}_${t.name}`, { ...t, storeCode: sCode }));
      }
    });

    const list = Array.from(map.values());
    list.sort((a, b) => {
      if (a.storeCode !== b.storeCode) return (a.storeCode || "").localeCompare(b.storeCode || "");
      if (a.zone !== b.zone) return (a.zone || "").localeCompare(b.zone || "");
      return (a.name || "").localeCompare(b.name || "", undefined, { numeric: true });
    });
    return list;
  }, [rawTables]);

  // Compute scoped tables based on currentStoreCode
  const scopedTables = useMemo(() => {
    if (currentStoreCode === "ALL") return allTables;
    return allTables.filter((t) => t.storeCode === currentStoreCode);
  }, [allTables, currentStoreCode]);

  // Compute scoped history based on currentStoreCode
  const scopedHistory = useMemo(() => {
    if (currentStoreCode === "ALL") return allHistory;
    return allHistory.filter((o) => {
      const code = o.storeCode || "TRAM01";
      return code === currentStoreCode;
    });
  }, [allHistory, currentStoreCode]);

  // Compute scoped audit logs
  const scopedAuditLogs = useMemo(() => {
    if (currentStoreCode === "ALL") return rawAuditLogs;
    return rawAuditLogs.filter((l) => {
      if (l.storeCode) return l.storeCode === currentStoreCode;
      // If no storeCode, default to TRAM01
      return currentStoreCode === "TRAM01";
    });
  }, [rawAuditLogs, currentStoreCode]);

  // Compute scoped cash shifts
  const allCashShifts = useMemo(() => {
    const list: CashShiftItem[] = [];
    Object.values(rawCashShifts).forEach((shifts) => {
      list.push(...shifts);
    });
    list.sort((a, b) => (b.startTime || 0) - (a.startTime || 0));
    return list;
  }, [rawCashShifts]);

  const scopedCashShifts = useMemo(() => {
    if (currentStoreCode === "ALL") return allCashShifts;
    return allCashShifts.filter((s) => (s.storeCode || "TRAM01") === currentStoreCode);
  }, [allCashShifts, currentStoreCode]);

  // Compute products across all stores and scoped to currentStoreCode
  const allProducts = useMemo(() => {
    const list: ProductItem[] = [];
    Object.entries(rawProductsMap).forEach(([code, pList]) => {
      pList.forEach((p) => {
        list.push(p);
      });
    });
    list.sort((a, b) => (a.name || "").localeCompare(b.name || ""));
    return list;
  }, [rawProductsMap]);

  const scopedProducts = useMemo(() => {
    if (currentStoreCode === "ALL") return allProducts;
    return allProducts.filter((p) => p.storeCode === currentStoreCode);
  }, [allProducts, currentStoreCode]);

  // Compute categories across all stores and scoped to currentStoreCode
  const allCategories = useMemo(() => {
    const list: CategoryItem[] = [];
    Object.entries(rawCategoriesMap).forEach(([code, cList]) => {
      cList.forEach((c) => {
        list.push(c);
      });
    });
    return list;
  }, [rawCategoriesMap]);

  const scopedCategories = useMemo(() => {
    if (currentStoreCode === "ALL") {
      const map = new Map<string, CategoryItem>();
      allCategories.forEach((c) => {
        if (c.name && !map.has(c.name)) {
          map.set(c.name, c);
        }
      });
      return Array.from(map.values());
    }
    return allCategories.filter((c) => c.storeCode === currentStoreCode);
  }, [allCategories, currentStoreCode]);

  // Compute users across all stores and scoped to currentStoreCode
  const allUsers = useMemo(() => {
    const list: UserItem[] = [];
    const seen = new Set<string>();

    // Add store-scoped users
    Object.entries(rawUsersMap).forEach(([code, uList]) => {
      uList.forEach((u) => {
        const uName = (u.username || u.id || "").toLowerCase().trim();
        const key = `${code}_${uName}`;
        if (!seen.has(key)) {
          seen.add(key);
          list.push({
            ...u,
            id: u.id || uName,
            username: u.username || uName,
            storeCode: code,
            isActive: u.isActive !== false,
          });
        }
      });
    });

    list.sort((a, b) => (a.fullName || a.username || "").localeCompare(b.fullName || b.username || ""));
    return list;
  }, [rawUsersMap]);

  const scopedUsers = useMemo(() => {
    if (currentStoreCode === "ALL") return allUsers;
    return allUsers.filter((u) => u.storeCode === currentStoreCode || u.isRootOwner);
  }, [allUsers, currentStoreCode]);

  // Compute store stats (tables count, in-use count, orders count, total revenue)
  const enrichedStores = useMemo(() => {
    return stores.map((s) => {
      const sTables = allTables.filter((t) => t.storeCode === s.storeCode);
      const sOrders = allHistory.filter((o) => (o.storeCode || "TRAM01") === s.storeCode);
      const totalRev = sOrders.reduce((sum, o) => sum + (o.totalAmount || 0), 0);
      return {
        ...s,
        totalTables: sTables.length,
        inUseTables: sTables.filter((t) => t.inUse).length,
        totalOrders: sOrders.length,
        totalRevenue: totalRev,
      };
    });
  }, [stores, allTables, allHistory]);

  const currentStore = useMemo(() => {
    if (currentStoreCode === "ALL") return undefined;
    return enrichedStores.find((s) => s.storeCode === currentStoreCode);
  }, [enrichedStores, currentStoreCode]);

  // Store Management Actions
  const createStore = useCallback(async (storeData: Partial<StoreItem>, copyMenuFrom?: string) => {
    try {
      const cleanCode = (storeData.storeCode || "").toUpperCase().trim().replace(/[^A-Z0-9_]/g, "");
      if (!cleanCode) return { success: false, error: "Mã chi nhánh không được để trống và chỉ gồm chữ cái, số." };

      const existingRef = ref(db, `stores/${cleanCode}/storeInfo`);
      const existingSnap = await get(existingRef);
      if (existingSnap.exists()) {
        return { success: false, error: `Mã chi nhánh "${cleanCode}" đã tồn tại trên hệ thống!` };
      }

      const newStoreInfo: StoreItem = {
        id: cleanCode,
        storeCode: cleanCode,
        storeName: storeData.storeName || `POS Trạm - ${cleanCode}`,
        address: storeData.address || "Chi nhánh mới",
        phone: storeData.phone || "",
        wifiName: storeData.wifiName || "Tram_FnB_Free",
        bankId: storeData.bankId || "MB",
        bankAccount: storeData.bankAccount || "",
        accountName: storeData.accountName || "CHU CUA HANG",
        defaultVatRate: storeData.defaultVatRate ?? 8,
        allowStackPromotions: storeData.allowStackPromotions ?? true,
        active: true,
        createdAt: Date.now(),
      };

      await set(ref(db, `stores/${cleanCode}/storeInfo`), newStoreInfo);

      // Default zones and tables for the new store
      const defaultZones = {
        "Tầng 1": { name: "Tầng 1" },
        "Tầng 2": { name: "Tầng 2" },
        "Sân Vườn": { name: "Sân Vườn" },
      };
      const defaultTablesMap = {
        "Tầng 1_Bàn 01": { name: "Bàn 01", zone: "Tầng 1", inUse: false },
        "Tầng 1_Bàn 02": { name: "Bàn 02", zone: "Tầng 1", inUse: false },
        "Tầng 1_Bàn 03": { name: "Bàn 03", zone: "Tầng 1", inUse: false },
        "Tầng 2_Bàn 04": { name: "Bàn 04", zone: "Tầng 2", inUse: false },
        "Tầng 2_Bàn 05": { name: "Bàn 05", zone: "Tầng 2", inUse: false },
        "Sân Vườn_Bàn SV1": { name: "Bàn SV1", zone: "Sân Vườn", inUse: false },
      };

      await set(ref(db, `stores/${cleanCode}/zones`), defaultZones);
      await set(ref(db, `stores/${cleanCode}/tables`), defaultTablesMap);

      // Copy menu and categories if requested
      if (copyMenuFrom) {
        const sourceCatRef = ref(db, `stores/${copyMenuFrom}/categories`);
        const sourceProdRef = ref(db, `stores/${copyMenuFrom}/products`);
        const [catSnap, prodSnap] = await Promise.all([get(sourceCatRef), get(sourceProdRef)]);

        if (catSnap.exists()) {
          await set(ref(db, `stores/${cleanCode}/categories`), catSnap.val());
        }

        if (prodSnap.exists()) {
          await set(ref(db, `stores/${cleanCode}/products`), prodSnap.val());
        }
      }

      // Log action
      const logEntry = {
        action: "CREATE_STORE",
        targetType: "STORE",
        targetId: cleanCode,
        details: `Thêm chi nhánh mới thành công: ${newStoreInfo.storeName} (${cleanCode})`,
        timestamp: Date.now(),
        userRole: "MANAGER",
        username: "admin",
      };
      await set(ref(db, `stores/${cleanCode}/audit_logs/LOG_${Date.now()}`), logEntry);

      return { success: true };
    } catch (e: any) {
      return { success: false, error: e.message || "Lỗi khi tạo chi nhánh mới." };
    }
  }, []);

  const updateStore = useCallback(async (storeCode: string, data: Partial<StoreItem>) => {
    try {
      const storeRefNode = ref(db, `stores/${storeCode}/storeInfo`);
      await update(storeRefNode, data);

      const logEntry = {
        action: "UPDATE_STORE",
        targetType: "STORE",
        targetId: storeCode,
        details: `Cập nhật thông tin chi nhánh: ${data.storeName || storeCode}`,
        timestamp: Date.now(),
        userRole: "MANAGER",
        username: "admin",
      };
      await set(ref(db, `stores/${storeCode}/audit_logs/LOG_${Date.now()}`), logEntry);

      return { success: true };
    } catch (e: any) {
      return { success: false, error: e.message || "Lỗi khi cập nhật chi nhánh." };
    }
  }, []);

  const deleteStore = useCallback(async (storeCode: string) => {
    try {
      // Soft disable store
      const storeRefNode = ref(db, `stores/${storeCode}/storeInfo`);
      await update(storeRefNode, { active: false });

      const logEntry = {
        action: "DEACTIVATE_STORE",
        targetType: "STORE",
        targetId: storeCode,
        details: `Tạm dừng hoạt động chi nhánh: ${storeCode}`,
        timestamp: Date.now(),
        userRole: "MANAGER",
        username: "admin",
      };
      await set(ref(db, `stores/${storeCode}/audit_logs/LOG_${Date.now()}`), logEntry);

      return { success: true };
    } catch (e: any) {
      return { success: false, error: e.message || "Lỗi khi xóa chi nhánh." };
    }
  }, []);

  const updateStoreShiftDifferenceSetting = useCallback(
    async (storeCode: string, allow: boolean) => {
      try {
        const targetCode = storeCode === "ALL" ? (stores[0]?.storeCode || "TRAM01") : storeCode;
        const storeRefNode = ref(db, `stores/${targetCode}/storeInfo`);
        await update(storeRefNode, { allowStaffViewShiftDifference: allow });

        const logEntry = {
          action: "UPDATE_STORE_SETTING",
          targetType: "STORE",
          targetId: targetCode,
          details: `Cập nhật cấu hình xem chênh lệch két tiền nhân viên: ${allow ? "BẬT" : "TẮT"}`,
          timestamp: Date.now(),
          userRole: "MANAGER",
          username: "admin",
        };
        await set(ref(db, `stores/${targetCode}/audit_logs/LOG_${Date.now()}`), logEntry);
        return { success: true };
      } catch (e: any) {
        return { success: false, error: e.message || "Lỗi khi cập nhật cấu hình két tiền." };
      }
    },
    [stores]
  );

  // Table operations (multi-store aware with dual-write to root)
  const checkoutAndFreeTable = useCallback(
    async (
      table: TableItem,
      options?: {
        paymentMethod?: "CASH" | "TRANSFER";
        staffName?: string;
        discountAmount?: number;
      }
    ) => {
      try {
        const targetStoreCode = table.storeCode || (currentStoreCode !== "ALL" ? currentStoreCode : "TRAM01");
        const targetStore = stores.find((s) => s.storeCode === targetStoreCode) || currentStore;
        const storeName =
          targetStore?.storeName ||
          (targetStoreCode === "TRAM01" ? "POS Trạm - Trụ sở 01 (Đà Lạt)" : `POS Trạm - Chi nhánh ${targetStoreCode}`);

        let items: any[] = [];
        try {
          if (table.currentOrderJson) {
            const parsed = JSON.parse(table.currentOrderJson);
            if (Array.isArray(parsed)) items = parsed;
          }
        } catch {}

        const subTotal = items.reduce((sum, it) => {
          const qty = it.quantity || it.count || 1;
          let toppingSum = 0;
          if (Array.isArray(it.selectedToppings)) {
            toppingSum = it.selectedToppings.reduce((ts: number, tp: any) => ts + (tp.price || 0), 0);
          }
          return sum + (Number(it.price || 0) + toppingSum) * qty;
        }, 0);

        const discountAmount = options?.discountAmount || 0;
        const finalAmount = Math.max(0, subTotal - discountAmount);
        const paymentMethod = options?.paymentMethod || "CASH";
        const cashierName = options?.staffName || "Quản trị viên Web";
        const now = Date.now();
        const dateStr = new Date().toISOString().slice(0, 10).replace(/-/g, "");
        const randomSuffix = Math.floor(1000 + Math.random() * 9000);
        const billCode = table.currentBillId || `HD-${dateStr}-${randomSuffix}`;
        const billId = `bill_${now}_${Math.floor(Math.random() * 1000)}`;

        let actionLogs: any[] = [];
        if (table.actionLogsJson) {
          try {
            const p = JSON.parse(table.actionLogsJson);
            if (Array.isArray(p)) actionLogs = p;
          } catch {}
        } else if (Array.isArray(table.actionLogs)) {
          actionLogs = [...table.actionLogs];
        }

        actionLogs.push({
          timestamp: now,
          staffUsername: "admin_web",
          staffFullName: cashierName,
          action: "PAY_BILL",
          details: `Thanh toán hóa đơn ${billCode} bàn ${table.name}: ${new Intl.NumberFormat("vi-VN").format(finalAmount)}đ (${paymentMethod === "CASH" ? "Tiền mặt" : "Chuyển khoản VietQR"}) qua Web Admin`,
        });

        const orderCode = table.currentOrderCode || billCode;

        const historyBill: HistoryOrder = {
          id: billId,
          storeCode: targetStoreCode,
          storeName: storeName,
          billCode: billCode,
          orderCode: orderCode,
          tableName: table.name,
          zone: table.zone || "Khu A",
          guestCount: table.guestCount || 1,
          totalAmount: finalAmount,
          finalAmount: finalAmount,
          subTotal: subTotal,
          discountAmount: discountAmount,
          totalDiscount: discountAmount,
          paymentMethod: paymentMethod,
          status: "PAID",
          timestamp: now,
          createdAt: table.openedAt ? new Date(table.openedAt).getTime() : now,
          closedAt: now,
          cashierName: cashierName,
          staffUsername: "admin_web",
          staffFullName: cashierName,
          orderStaff: table.orderStaff || "POS Staff",
          items: items,
          actionLogs: actionLogs,
        };

        const clearPayload = {
          inUse: false,
          currentOrderJson: "",
          guestCount: 0,
          openedAt: null,
          currentBillId: null,
          currentOrderCode: null,
          mergedIntoTable: null,
          actionLogsJson: null,
        };

        // 1. Write history and bills to store
        const rawHistoryMap = {
          ...historyBill,
          itemsJson: JSON.stringify(items),
          actionLogsJson: JSON.stringify(actionLogs),
        };
        await set(ref(db, `stores/${targetStoreCode}/history/${billId}`), rawHistoryMap);
        await set(ref(db, `stores/${targetStoreCode}/bills/${billId}`), rawHistoryMap).catch(() => {});

        // 2. Clear table in scoped store
        const stdKey = `${table.zone}_${table.name}`;
        await update(ref(db, `stores/${targetStoreCode}/tables/${table.id}`), clearPayload);
        if (stdKey !== table.id) {
          await update(ref(db, `stores/${targetStoreCode}/tables/${stdKey}`), clearPayload).catch(() => {});
        }

        // 3. Write Audit Log
        const logId = `log_${now}_${Math.floor(Math.random() * 1000)}`;
        const auditPayload = {
          timestamp: now,
          username: "admin_web",
          userFullName: cashierName,
          userRole: "ADMIN",
          action: "PAY_BILL",
          targetType: "BILL",
          targetId: billCode,
          storeCode: targetStoreCode,
          details: `Thanh toán & trả bàn ${table.name} (${table.zone}) - Số tiền: ${new Intl.NumberFormat("vi-VN").format(finalAmount)}đ (${paymentMethod === "CASH" ? "Tiền mặt" : "Chuyển khoản VietQR"}) qua Web Admin`,
          afterState: {
            orderCode: billCode,
            tableName: table.name,
            totalAmount: finalAmount,
            itemsCount: items.length,
            paymentMethod: paymentMethod,
          },
        };
        await set(ref(db, `stores/${targetStoreCode}/audit_logs/${logId}`), auditPayload);

        // 4. Optimistic UI update
        setRawTables((prev) => {
          const next = { ...prev };
          const updateList = (list: TableItem[]) =>
            list.map((t) => (t.id === table.id || t.name === table.name ? { ...t, ...clearPayload } : t));
          if (next[targetStoreCode]) next[targetStoreCode] = updateList(next[targetStoreCode]);
          if (next["TRAM01_ROOT"]) next["TRAM01_ROOT"] = updateList(next["TRAM01_ROOT"]);
          return next;
        });

        setAllHistory((prev) => [sanitizeHistoryOrder(historyBill, billId), ...prev]);

        return { success: true, billId };
      } catch (e: any) {
        console.error("checkoutAndFreeTable error:", e);
        return { success: false, error: e.message || "Lỗi khi thanh toán trả bàn" };
      }
    },
    [currentStoreCode, stores, currentStore]
  );

  const cancelActiveTable = useCallback(
    async (
      table: TableItem,
      reason: string,
      staffName?: string
    ): Promise<{ success: boolean; billId?: string; error?: string }> => {
      try {
        const targetStoreCode =
          table.storeCode || (currentStoreCode !== "ALL" ? currentStoreCode : "TRAM01");
        const storeObj = stores.find((s) => s.storeCode === targetStoreCode) || currentStore;
        const storeName = storeObj ? storeObj.storeName : "POS Trạm - Chi nhánh " + targetStoreCode;

        let items: any[] = [];
        try {
          if (table.currentOrderJson) {
            const parsed = JSON.parse(table.currentOrderJson);
            if (Array.isArray(parsed)) items = parsed;
          }
        } catch {}

        const totalAmount = items.reduce((sum, it) => {
          const qty = it.quantity || it.count || 1;
          let toppingSum = 0;
          if (Array.isArray(it.selectedToppings)) {
            toppingSum = it.selectedToppings.reduce((ts: number, tp: any) => ts + (tp.price || 0), 0);
          }
          return sum + (Number(it.price || 0) + toppingSum) * qty;
        }, 0);

        const cancellerName = staffName || "Quản trị viên Web";
        const now = Date.now();
        const dateStr = new Date().toISOString().slice(0, 10).replace(/-/g, "");
        const randomSuffix = Math.floor(1000 + Math.random() * 9000);
        const billCode =
          table.currentBillId && table.currentBillId.startsWith("HD-")
            ? table.currentBillId
            : `HD-${dateStr}-${randomSuffix}`;
        const orderCode = table.currentOrderCode || `OD-${dateStr}-${randomSuffix}`;
        const cancelBillId = `BILL_CANCELLED_${now}`;

        let actionLogs: any[] = [];
        if (table.actionLogsJson) {
          try {
            const p = JSON.parse(table.actionLogsJson);
            if (Array.isArray(p)) actionLogs = p;
          } catch {}
        } else if (Array.isArray(table.actionLogs)) {
          actionLogs = [...table.actionLogs];
        }

        actionLogs.push({
          timestamp: now,
          staffUsername: "admin_web",
          staffFullName: cancellerName,
          action: "CANCEL_BILL",
          details: `${cancellerName} hủy đơn bàn ${table.name}. Lý do: ${reason}`,
        });

        const cancelRecord: HistoryOrder = {
          id: cancelBillId,
          storeCode: targetStoreCode,
          storeName: storeName,
          billCode: billCode,
          orderCode: orderCode,
          tableName: table.name,
          zone: table.zone || "Khu A",
          guestCount: table.guestCount || 1,
          totalAmount: totalAmount,
          finalAmount: 0,
          subTotal: totalAmount,
          discountAmount: 0,
          totalDiscount: 0,
          status: "CANCELLED",
          cancelReason: reason,
          cancellationReason: reason,
          cancelledAt: now,
          cancelledBy: cancellerName,
          timestamp: now,
          createdAt: table.openedAt ? new Date(table.openedAt).getTime() : now,
          closedAt: now,
          cashierName: cancellerName,
          staffUsername: "admin_web",
          staffFullName: cancellerName,
          orderStaff: table.orderStaff || "POS Staff",
          items: items,
          actionLogs: actionLogs,
        };

        const clearPayload = {
          inUse: false,
          currentOrderJson: "",
          guestCount: 0,
          openedAt: null,
          currentBillId: null,
          currentOrderCode: null,
          mergedIntoTable: null,
          actionLogsJson: null,
        };

        const rawCancelMap = {
          ...cancelRecord,
          itemsJson: JSON.stringify(items),
          actionLogsJson: JSON.stringify(actionLogs),
        };

        // Write to history and bills in store
        await set(ref(db, `stores/${targetStoreCode}/history/${cancelBillId}`), rawCancelMap);
        await set(ref(db, `stores/${targetStoreCode}/bills/${cancelBillId}`), rawCancelMap).catch(() => {});

        // Clear table in scoped store
        const stdKey = `${table.zone}_${table.name}`;
        await update(ref(db, `stores/${targetStoreCode}/tables/${table.id}`), clearPayload);
        if (stdKey !== table.id) {
          await update(ref(db, `stores/${targetStoreCode}/tables/${stdKey}`), clearPayload).catch(() => {});
        }

        // Write Audit Log
        const logId = `log_${now}_${Math.floor(Math.random() * 1000)}`;
        const auditPayload = {
          timestamp: now,
          username: "admin_web",
          userFullName: cancellerName,
          userRole: "ADMIN",
          action: "CANCEL_BILL",
          targetType: "BILL",
          targetId: billCode,
          storeCode: targetStoreCode,
          details: `Hủy đơn & trả bàn ${table.name} (${table.zone}) - Số tiền: ${new Intl.NumberFormat("vi-VN").format(totalAmount)}đ. Lý do: ${reason}`,
          afterState: {
            orderCode: billCode,
            tableName: table.name,
            totalAmount: totalAmount,
            itemsCount: items.length,
            status: "CANCELLED",
            reason: reason,
          },
        };
        await set(ref(db, `stores/${targetStoreCode}/audit_logs/${logId}`), auditPayload);

        // Optimistic UI update
        setRawTables((prev) => {
          const next = { ...prev };
          const updateList = (list: TableItem[]) =>
            list.map((t) => (t.id === table.id || t.name === table.name ? { ...t, ...clearPayload } : t));
          if (next[targetStoreCode]) next[targetStoreCode] = updateList(next[targetStoreCode]);
          if (next["TRAM01_ROOT"]) next["TRAM01_ROOT"] = updateList(next["TRAM01_ROOT"]);
          return next;
        });

        setAllHistory((prev) => [sanitizeHistoryOrder(cancelRecord, cancelBillId), ...prev]);

        return { success: true, billId: cancelBillId };
      } catch (e: any) {
        console.error("cancelActiveTable error:", e);
        return { success: false, error: e.message || "Lỗi khi hủy đơn bàn" };
      }
    },
    [currentStoreCode, stores, currentStore]
  );

  const saveTable = useCallback(
    async (
      tableData: { id?: string; name: string; zone: string; inUse?: boolean },
      storeCode?: string
    ) => {
      try {
        const targetCode = storeCode || (currentStoreCode !== "ALL" ? currentStoreCode : "TRAM01");
        const key = tableData.id || `${tableData.zone}_${tableData.name}`;
        const payload = {
          name: tableData.name,
          zone: tableData.zone,
          inUse: tableData.inUse ?? false,
          currentOrderJson: "",
        };
        await set(ref(db, `stores/${targetCode}/tables/${key}`), payload);
        return { success: true };
      } catch (e: any) {
        return { success: false, error: e.message || "Lỗi lưu bàn" };
      }
    },
    [currentStoreCode]
  );

  const deleteTable = useCallback(
    async (tableId: string, storeCode?: string) => {
      try {
        const targetCode = storeCode || (currentStoreCode !== "ALL" ? currentStoreCode : "TRAM01");
        await remove(ref(db, `stores/${targetCode}/tables/${tableId}`));
        return { success: true };
      } catch (e: any) {
        return { success: false, error: e.message || "Lỗi xóa bàn" };
      }
    },
    [currentStoreCode]
  );

  const saveProduct = useCallback(
    async (
      productData: { id?: string; name: string; code?: string; price: number; costPrice?: number; unit?: string; category?: string; imageBase64?: string; isTopping?: boolean },
      storeCode?: string
    ) => {
      try {
        const targetCode = storeCode || (currentStoreCode !== "ALL" ? currentStoreCode : "TRAM01");
        const payload: any = {
          name: productData.name.trim(),
          code: (productData.code || "").trim(),
          price: Number(productData.price),
          costPrice: productData.costPrice != null ? Number(productData.costPrice) : 0,
          unit: (productData.unit || "").trim(),
          category: (productData.category || "").trim(),
          isTopping: Boolean(productData.isTopping),
        };
        if (productData.imageBase64 !== undefined) {
          payload.imageBase64 = productData.imageBase64;
        }

        if (productData.id) {
          await update(ref(db, `stores/${targetCode}/products/${productData.id}`), payload);
        } else {
          await push(ref(db, `stores/${targetCode}/products`), payload);
        }

        // Also ensure category exists under the store if category is specified
        if (payload.category) {
          await update(ref(db, `stores/${targetCode}/categories/${payload.category}`), {
            name: payload.category,
          }).catch(() => {});
        }

        return { success: true };
      } catch (e: any) {
        return { success: false, error: e.message || "Lỗi lưu sản phẩm" };
      }
    },
    [currentStoreCode]
  );

  const deleteProduct = useCallback(
    async (productId: string, storeCode?: string) => {
      try {
        const targetCode = storeCode || (currentStoreCode !== "ALL" ? currentStoreCode : "TRAM01");
        await remove(ref(db, `stores/${targetCode}/products/${productId}`));
        return { success: true };
      } catch (e: any) {
        return { success: false, error: e.message || "Lỗi xóa sản phẩm" };
      }
    },
    [currentStoreCode]
  );

  const saveCategory = useCallback(
    async (categoryName: string, storeCode?: string, oldCategoryName?: string, allowedToppingIds?: string[]) => {
      try {
        const cleanName = categoryName.trim();
        if (!cleanName) return { success: false, error: "Tên danh mục không được để trống" };

        const targetStores = (!storeCode || storeCode === "ALL")
          ? (stores.length > 0 ? stores.map((s) => s.storeCode) : ["TRAM01"])
          : [storeCode];

        for (const code of targetStores) {
          // If renaming: remove old key, update products
          if (oldCategoryName && oldCategoryName !== cleanName) {
            await remove(ref(db, `stores/${code}/categories/${oldCategoryName}`)).catch(() => {});

            // Update any products under this store using the old category name
            const storeProds = allProducts.filter((p) => p.storeCode === code && p.category === oldCategoryName);
            for (const p of storeProds) {
              await update(ref(db, `stores/${code}/products/${p.id}`), { category: cleanName }).catch(() => {});
            }
          }

          // Save new category with allowedToppingIds if provided
          const catPayload: any = { name: cleanName };
          if (allowedToppingIds !== undefined) {
            catPayload.allowedToppingIds = allowedToppingIds;
          }
          await update(ref(db, `stores/${code}/categories/${cleanName}`), catPayload);
        }

        return { success: true };
      } catch (e: any) {
        return { success: false, error: e.message || "Lỗi lưu danh mục" };
      }
    },
    [stores, allProducts]
  );

  const deleteCategory = useCallback(
    async (categoryName: string, storeCode?: string) => {
      try {
        const cleanName = categoryName.trim();
        const targetStores = (!storeCode || storeCode === "ALL")
          ? (stores.length > 0 ? stores.map((s) => s.storeCode) : ["TRAM01"])
          : [storeCode];

        for (const code of targetStores) {
          await remove(ref(db, `stores/${code}/categories/${cleanName}`)).catch(() => {});
        }

        return { success: true };
      } catch (e: any) {
        return { success: false, error: e.message || "Lỗi xóa danh mục" };
      }
    },
    [stores]
  );

  const saveUser = useCallback(
    async (
      userData: {
        username: string;
        fullName: string;
        password?: string;
        role: string;
        phone?: string;
        isActive?: boolean;
        storeCode?: string;
      },
      targetStoreCode?: string
    ) => {
      try {
        const cleanUsername = userData.username.trim().toLowerCase();
        if (!cleanUsername) return { success: false, error: "Tên đăng nhập không được để trống" };
        if (!userData.fullName?.trim()) return { success: false, error: "Họ tên không được để trống" };

        const finalStoreCode = targetStoreCode || userData.storeCode || (currentStoreCode !== "ALL" ? currentStoreCode : "TRAM01");
        const role = userData.role || "ROLE_WAITER";
        const isRootOwner = role === "ROLE_OWNER" || role === "OWNER";
        const now = Date.now();

        const payload: any = {
          username: cleanUsername,
          fullName: userData.fullName.trim(),
          roleId: role,
          role: role,
          phone: userData.phone?.trim() || "",
          isActive: userData.isActive !== false,
          isRootOwner: isRootOwner,
          storeCode: finalStoreCode,
        };

        // Do NOT store raw passwords in Realtime Database. Passwords belong to Firebase Auth.

        // 1. Write to store-scoped path: stores/{storeCode}/users/{username}
        await set(ref(db, `stores/${finalStoreCode}/users/${cleanUsername}`), payload);

        // 2. Write Audit Log
        const logId = `log_${now}_${Math.floor(Math.random() * 1000)}`;
        const auditPayload = {
          timestamp: now,
          username: "admin_web",
          userFullName: "Quản trị viên Web",
          userRole: "ADMIN",
          action: "SAVE_USER",
          targetType: "USER",
          targetId: cleanUsername,
          storeCode: finalStoreCode,
          details: `Lưu thông tin nhân viên: ${userData.fullName.trim()} (@${cleanUsername}) - Vai trò: ${role} - Chi nhánh: ${finalStoreCode}`,
        };
        await set(ref(db, `stores/${finalStoreCode}/audit_logs/${logId}`), auditPayload).catch(() => {});

        // 3. Optimistic state updates
        setRawUsersMap((prev) => {
          const storeUsers = prev[finalStoreCode] ? [...prev[finalStoreCode]] : [];
          const idx = storeUsers.findIndex((u) => u.username.toLowerCase() === cleanUsername);
          const updatedUser: UserItem = {
            id: cleanUsername,
            ...payload,
            storeCode: finalStoreCode,
            storeName: stores.find((s) => s.storeCode === finalStoreCode)?.storeName || finalStoreCode,
          };
          if (idx >= 0) {
            storeUsers[idx] = { ...storeUsers[idx], ...updatedUser };
          } else {
            storeUsers.push(updatedUser);
          }
          return { ...prev, [finalStoreCode]: storeUsers };
        });

        return { success: true };
      } catch (e: any) {
        return { success: false, error: e.message || "Lỗi lưu thông tin nhân viên" };
      }
    },
    [currentStoreCode, stores]
  );

  const deleteUser = useCallback(
    async (username: string, storeCode?: string) => {
      try {
        const cleanUsername = username.trim().toLowerCase();
        if (!cleanUsername) return { success: false, error: "Tên đăng nhập không hợp lệ" };

        const targetStores = (!storeCode || storeCode === "ALL")
          ? (stores.length > 0 ? stores.map((s) => s.storeCode) : ["TRAM01"])
          : [storeCode];

        const now = Date.now();

        for (const code of targetStores) {
          await remove(ref(db, `stores/${code}/users/${cleanUsername}`)).catch(() => {});
        }

        // Audit log
        const logId = `log_${now}_${Math.floor(Math.random() * 1000)}`;
        const auditPayload = {
          timestamp: now,
          username: "admin_web",
          userFullName: "Quản trị viên Web",
          userRole: "ADMIN",
          action: "DELETE_USER",
          targetType: "USER",
          targetId: cleanUsername,
          storeCode: targetStores[0] || "TRAM01",
          details: `Xóa nhân viên @${cleanUsername} khỏi hệ thống`,
        };
        await set(ref(db, `stores/${targetStores[0] || "TRAM01"}/audit_logs/${logId}`), auditPayload).catch(() => {});

        // Optimistic state updates
        setRawUsersMap((prev) => {
          const next = { ...prev };
          for (const code of targetStores) {
            if (next[code]) {
              next[code] = next[code].filter((u) => u.username.toLowerCase() !== cleanUsername);
            }
          }
          return next;
        });

        return { success: true };
      } catch (e: any) {
        return { success: false, error: e.message || "Lỗi xóa nhân viên" };
      }
    },
    [stores]
  );

  const cancelOrder = useCallback(
    async (
      orderId: string,
      reason: string,
      storeCode?: string
    ): Promise<{ success: boolean; error?: string }> => {
      try {
        const order = allHistory.find((h) => h.id === orderId);
        if (!order) return { success: false, error: "Không tìm thấy hóa đơn" };

        const targetStoreCode = storeCode || order.storeCode || (currentStoreCode !== "ALL" ? currentStoreCode : "TRAM01");
        const now = Date.now();

        const cancelLog = {
          timestamp: now,
          staffFullName: "Quản trị viên Web",
          action: "CANCEL_BILL",
          details: `Quản trị viên Web hủy hóa đơn ${order.billCode || order.orderCode || orderId}. Lý do: ${reason}`,
        };

        const updatedLogs = [...(order.actionLogs || []), cancelLog];

        const patch = {
          status: "CANCELLED",
          cancelReason: reason,
          cancelledAt: now,
          cancelledBy: "Quản trị viên Web",
          actionLogs: updatedLogs,
          actionLogsJson: JSON.stringify(updatedLogs),
        };

        // Update in stores/{targetStoreCode}/history/{orderId} and bills
        await update(ref(db, `stores/${targetStoreCode}/history/${orderId}`), patch);
        await update(ref(db, `stores/${targetStoreCode}/bills/${orderId}`), patch).catch(() => {});

        // Audit log
        const logId = `log_${now}_${Math.floor(Math.random() * 1000)}`;
        const auditPayload = {
          timestamp: now,
          username: "admin_web",
          userFullName: "Quản trị viên Web",
          userRole: "ADMIN",
          action: "CANCEL_BILL",
          targetType: "BILL",
          targetId: order.billCode || order.orderCode || orderId,
          storeCode: targetStoreCode,
          details: `Hủy hóa đơn ${order.billCode || order.orderCode || orderId} bàn ${order.tableName} (${new Intl.NumberFormat("vi-VN").format(order.totalAmount || 0)}đ). Lý do: ${reason}`,
        };
        await set(ref(db, `stores/${targetStoreCode}/audit_logs/${logId}`), auditPayload);

        // Optimistic update
        setAllHistory((prev) =>
          prev.map((h) => (h.id === orderId ? { ...h, ...patch } : h))
        );

        return { success: true };
      } catch (e: any) {
        return { success: false, error: e.message || "Lỗi khi hủy hóa đơn" };
      }
    },
    [allHistory, currentStoreCode]
  );

  const deleteOrder = useCallback(
    async (
      orderId: string,
      storeCode?: string
    ): Promise<{ success: boolean; error?: string }> => {
      try {
        const order = allHistory.find((h) => h.id === orderId);
        const targetStoreCode = storeCode || order?.storeCode || (currentStoreCode !== "ALL" ? currentStoreCode : "TRAM01");
        const now = Date.now();

        // Remove from history and bills
        await remove(ref(db, `stores/${targetStoreCode}/history/${orderId}`));
        await remove(ref(db, `stores/${targetStoreCode}/bills/${orderId}`)).catch(() => {});

        // Audit log
        const logId = `log_${now}_${Math.floor(Math.random() * 1000)}`;
        const auditPayload = {
          timestamp: now,
          username: "admin_web",
          userFullName: "Quản trị viên Web",
          userRole: "ADMIN",
          action: "DELETE_BILL",
          targetType: "BILL",
          targetId: order?.billCode || order?.orderCode || orderId,
          storeCode: targetStoreCode,
          details: `Xóa vĩnh viễn hóa đơn ${order?.billCode || order?.orderCode || orderId} khỏi hệ thống`,
        };
        await set(ref(db, `stores/${targetStoreCode}/audit_logs/${logId}`), auditPayload);

        // Optimistic update
        setAllHistory((prev) => prev.filter((h) => h.id !== orderId));

        return { success: true };
      } catch (e: any) {
        return { success: false, error: e.message || "Lỗi khi xóa hóa đơn" };
      }
    },
    [allHistory, currentStoreCode]
  );

  const refreshAll = useCallback(() => {
    setLoading(true);
    setTimeout(() => setLoading(false), 400);
  }, []);

  const value = useMemo(
    () => ({
      stores: enrichedStores,
      currentStoreCode,
      currentStore,
      setCurrentStoreCode,
      createStore,
      updateStore,
      deleteStore,
      updateStoreShiftDifferenceSetting,

      checkoutAndFreeTable,
      cancelActiveTable,
      saveTable,
      deleteTable,
      saveProduct,
      deleteProduct,
      saveCategory,
      deleteCategory,
      saveUser,
      deleteUser,
      cancelOrder,
      deleteOrder,

      tables: scopedTables,
      allTables,
      historyData: scopedHistory,
      products: scopedProducts,
      allProducts,
      categories: scopedCategories,
      allCategories,
      usersList: scopedUsers,
      allUsers,
      auditLogs: scopedAuditLogs,
      onlineOrders,
      cashShifts: scopedCashShifts,
      loading,
      historyLoaded,
      refreshAll,
    }),
    [
      enrichedStores,
      currentStoreCode,
      currentStore,
      setCurrentStoreCode,
      createStore,
      updateStore,
      deleteStore,
      updateStoreShiftDifferenceSetting,
      checkoutAndFreeTable,
      cancelActiveTable,
      saveTable,
      deleteTable,
      saveProduct,
      deleteProduct,
      saveCategory,
      deleteCategory,
      saveUser,
      deleteUser,
      cancelOrder,
      deleteOrder,
      scopedTables,
      allTables,
      scopedHistory,
      scopedProducts,
      allProducts,
      scopedCategories,
      allCategories,
      scopedUsers,
      allUsers,
      scopedAuditLogs,
      onlineOrders,
      scopedCashShifts,
      loading,
      historyLoaded,
      refreshAll,
    ]
  );

  return <DashboardContext.Provider value={value}>{children}</DashboardContext.Provider>;
}

export function useDashboardData() {
  return useContext(DashboardContext);
}
