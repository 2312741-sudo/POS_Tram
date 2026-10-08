"use client";
import { useState, useMemo, useEffect, useRef } from "react";
import {
  Search,
  Plus,
  Package,
  Truck,
  ClipboardList,
  Filter,
  ArrowUpDown,
  AlertTriangle,
  ChevronRight,
  Warehouse,
  Upload,
  Download,
  FileSpreadsheet,
  CheckCircle2,
  AlertCircle,
  X,
  ArrowLeft,
} from "lucide-react";
import { ref, onValue, set, push, remove, update, get } from "firebase/database";
import { db } from "@/lib/firebase";
import { useDashboardData } from "@/lib/data-context";
import { useAuth, hasPermission } from "@/lib/auth";
import * as XLSX from "xlsx";
import { errorMessage } from "@/lib/errors";

function formatVND(amount: number) {
  return new Intl.NumberFormat("vi-VN", { style: "currency", currency: "VND" }).format(amount);
}

function formatDate(ts: number) {
  if (!ts) return "—";
  const d = new Date(ts);
  return d.toLocaleDateString("vi-VN", { day: "2-digit", month: "2-digit", year: "numeric" });
}

// ==================== TYPES ====================
interface CatalogItem {
  itemId: string;
  sku: string;
  name: string;
  kind: string;
  managementGroup: string;
  groupIds: string[];
  baseUnitId: string;
  trackStock: boolean;
  costPrice: number;
  minStock: number;
  maxStock: number;
  status: string;
  description: string;
  imageUrl?: string;
  weight?: number;
  weightUnit?: string;
  conversionRate?: number;
  location?: string;
  brand?: string;
  createdAt: number;
  updatedAt: number;
}

interface SupplierItem {
  supplierId: string;
  supplierCode: string;
  name: string;
  phone: string;
  email: string;
  taxId: string;
  address: string;
  groupId: string;
  note: string;
  status: string;
  createdAt: number;
}

interface StockBalanceItem {
  balanceId: string;
  branchId: string;
  itemId: string;
  onHandQty: number;
  reservedQty: number;
  inventoryValue: number;
  averageCostScaled: number;
  updatedAt: number;
}

interface InventoryDocLine {
  lineId?: string;
  itemId: string;
  itemSku?: string;
  itemName: string;
  unitName?: string;
  quantity: number;
  unitPrice: number;
  lineNetMoney: number;
}

interface InventoryDocItem {
  documentId: string;
  documentCode: string;
  docType: string;
  status: string;
  branchId: string;
  supplierId?: string;
  supplierName?: string;
  totalQuantity: number;
  totalMoney: number;
  totalNetMoney: number;
  note: string;
  reason?: string;
  lines?: InventoryDocLine[];
  createdBy: string;
  createdByName: string;
  createdAt: number;
  completedAt?: number;
  completedBy?: string;
  completedByName?: string;
  committedEventIds?: string[];
  cancelReason?: string;
}

interface ParsedItemRow {
  index: number;
  managementGroup: string; // Nhóm quản lý ("Nguyên vật liệu" | "Công cụ dụng cụ")
  category: string; // Nhóm hàng
  sku: string; // Mã hàng
  name: string; // Tên hàng
  costPrice: number; // Giá vốn
  onHandQty: number; // Tồn kho hiện tại
  minStock: number; // Định mức tồn nhỏ nhất
  maxStock: number; // Định mức tồn lớn nhất
  unit: string; // ĐVT
  unitCode: string; // Mã ĐVT Cơ bản
  conversionRate: number; // Quy đổi
  attributes: string; // Thuộc tính
  relatedSku: string; // Mã hàng liên quan
  imageUrl: string; // Hình ảnh (url1,url2...)
  weight: number; // Trọng lượng
  weightUnit: string; // ĐVT trọng lượng
  status: "ACTIVE" | "DISCONTINUED"; // Đang sử dụng
  trackStock: boolean; // Quản lý tồn kho
  description: string; // Mô tả
  location: string; // Vị trí
  brand: string; // Thương hiệu
  kind: "RAW_MATERIAL" | "TOOL";
  isValid: boolean;
  statusMessage: string;
  isDuplicateSkuDifferentName?: boolean;
}

const kindLabels: Record<string, string> = {
  RAW_MATERIAL: "Nguyên vật liệu",
  TOOL: "Công cụ dụng cụ",
  DIRECT_SALE: "Hàng bán trực tiếp",
  MADE_TO_ORDER: "Hàng chế biến",
  MANUFACTURED: "Hàng sản xuất",
  TOPPING: "Topping",
  SERVICE: "Dịch vụ",
};

const docTypeLabels: Record<string, string> = {
  PURCHASE_RECEIPT: "Nhập hàng",
  PURCHASE_RETURN: "Trả hàng NCC",
  STOCKTAKE: "Kiểm kho",
  TRANSFER: "Chuyển hàng",
  WASTE: "Xuất hủy",
  INTERNAL_USE: "Dùng nội bộ",
  PRODUCTION: "Sản xuất",
  ADJUSTMENT: "Điều chỉnh",
  OPENING: "Tồn đầu",
};

const statusLabels: Record<string, string> = {
  DRAFT: "Phiếu tạm",
  COMPLETED: "Hoàn thành",
  CANCELLED: "Đã hủy",
  ACTIVE: "Hoạt động",
  DISCONTINUED: "Ngừng sử dụng",
  INACTIVE: "Ngưng hoạt động",
};

const statusColors: Record<string, string> = {
  DRAFT: "#f59e0b",
  COMPLETED: "#10b981",
  CANCELLED: "#ef4444",
  ACTIVE: "#10b981",
  DISCONTINUED: "#9ca3af",
  INACTIVE: "#9ca3af",
};

export default function InventoryPage() {
  const { stores, currentStoreCode, setCurrentStoreCode } = useDashboardData();
  const { user } = useAuth();

  const canStockIn = user?.isRootOwner || hasPermission(user, "INVENTORY_STOCK_IN") || hasPermission(user, "CREATE_RECEIPT");
  const canStockOut = user?.isRootOwner || hasPermission(user, "INVENTORY_STOCK_OUT") || hasPermission(user, "CREATE_INTERNAL_USE");
  const canWaste = user?.isRootOwner || hasPermission(user, "INVENTORY_WASTE") || hasPermission(user, "CREATE_WASTE");
  const canCompleteDoc = user?.isRootOwner || hasPermission(user, "COMPLETE_RECEIPT") || hasPermission(user, "INVENTORY_STOCK_IN");

  const [activeTab, setActiveTab] = useState<"catalog" | "stock" | "documents" | "suppliers">("catalog");
  const [search, setSearch] = useState("");
  const [filterKind, setFilterKind] = useState("");
  const [filterDocType, setFilterDocType] = useState("");
  const [filterDocStatus, setFilterDocStatus] = useState("");

  // Firebase data state
  const [catalogItems, setCatalogItems] = useState<CatalogItem[]>([]);
  const [suppliers, setSuppliers] = useState<SupplierItem[]>([]);
  const [stockBalances, setStockBalances] = useState<StockBalanceItem[]>([]);
  const [documents, setDocuments] = useState<InventoryDocItem[]>([]);
  // Mã chi nhánh đã nạp xong catalog — loading được suy ra, không setState đồng bộ trong effect
  const [loadedStoreCode, setLoadedStoreCode] = useState<string | null>(null);

  // Modal state for add/edit
  const [showItemModal, setShowItemModal] = useState(false);
  const [showSupplierModal, setShowSupplierModal] = useState(false);
  const [editingItem, setEditingItem] = useState<CatalogItem | null>(null);
  const [editingSupplier, setEditingSupplier] = useState<SupplierItem | null>(null);
  const [saving, setSaving] = useState(false);
  const [formError, setFormError] = useState("");

  // Document creation & view modal states
  const [showDocModal, setShowDocModal] = useState(false);
  const [docModalType, setDocModalType] = useState<"PURCHASE_RECEIPT" | "INTERNAL_USE" | "WASTE">("PURCHASE_RECEIPT");
  const [docSupplierId, setDocSupplierId] = useState("");
  const [docReason, setDocReason] = useState("");
  const [docNote, setDocNote] = useState("");
  const [docLines, setDocLines] = useState<InventoryDocLine[]>([]);
  const [docSaving, setDocSaving] = useState(false);
  const [docError, setDocError] = useState("");

  const [viewingDoc, setViewingDoc] = useState<InventoryDocItem | null>(null);
  const [actionInProgress, setActionInProgress] = useState(false);

  // Item form state
  const [itemForm, setItemForm] = useState({
    name: "",
    sku: "",
    kind: "RAW_MATERIAL",
    managementGroup: "",
    baseUnitId: "g",
    trackStock: true,
    costPrice: "",
    minStock: "",
    maxStock: "",
    description: "",
  });

  // Supplier form state
  const [supplierForm, setSupplierForm] = useState({
    name: "",
    phone: "",
    email: "",
    taxId: "",
    address: "",
    groupId: "",
    note: "",
  });

  // ==================== EXCEL IMPORT STATES ====================
  const [showImportModal, setShowImportModal] = useState(false);
  const [importStep, setImportStep] = useState<1 | 2>(1); // Step 1: Config, Step 2: Upload & Preview

  // Option 1: Cập nhật giá trị tồn kho?
  const [updateStockBalanceOption, setUpdateStockBalanceOption] = useState<"no" | "yes">("no");
  // Option 2: Xử lý trùng mã hàng, khác tên hàng?
  const [duplicateSkuOption, setDuplicateSkuOption] = useState<"error" | "replace">("error");
  // Option 3: Phạm vi áp dụng trạng thái kinh doanh
  const [scopeOption, setScopeOption] = useState<"all" | "branch">("all");

  const [importedFile, setImportedFile] = useState<File | null>(null);
  const [parsedRows, setParsedRows] = useState<ParsedItemRow[]>([]);
  const [isImporting, setIsImporting] = useState(false);
  const [importSuccessMsg, setImportSuccessMsg] = useState("");
  const fileInputRef = useRef<HTMLInputElement>(null);

  // Ở chế độ "ALL" dùng chi nhánh đầu tiên thực tế (không hardcode TRAM01)
  const targetStoreCode = currentStoreCode === "ALL" ? (stores[0]?.storeCode || "") : currentStoreCode;
  const loading = !!targetStoreCode && loadedStoreCode !== targetStoreCode;

  // Load data from Firebase
  useEffect(() => {
    if (!targetStoreCode) return;
    const unsubs: (() => void)[] = [];

    // Catalog Items
    const catRef = ref(db, `stores/${targetStoreCode}/catalog_items`);
    unsubs.push(
      onValue(catRef, (snap) => {
        const items: CatalogItem[] = [];
        snap.forEach((child) => {
          const v = child.val();
          items.push({
            itemId: child.key!,
            sku: v.sku || "",
            name: v.name || "",
            kind: v.kind || "RAW_MATERIAL",
            managementGroup: v.managementGroup || "",
            groupIds: v.groupIds || [],
            baseUnitId: v.baseUnitId || "",
            trackStock: v.trackStock ?? true,
            costPrice: v.costPrice || 0,
            minStock: v.minStock || 0,
            maxStock: v.maxStock || 0,
            status: v.status || "ACTIVE",
            description: v.description || "",
            imageUrl: v.imageUrl || "",
            weight: v.weight || 0,
            weightUnit: v.weightUnit || "",
            conversionRate: v.conversionRate || 1,
            location: v.location || "",
            brand: v.brand || "",
            createdAt: v.createdAt || 0,
            updatedAt: v.updatedAt || 0,
          });
        });
        setCatalogItems(items.sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0)));
        setLoadedStoreCode(targetStoreCode);
      })
    );

    // Suppliers
    const supRef = ref(db, `stores/${targetStoreCode}/suppliers`);
    unsubs.push(
      onValue(supRef, (snap) => {
        const sups: SupplierItem[] = [];
        snap.forEach((child) => {
          const v = child.val();
          sups.push({
            supplierId: child.key!,
            supplierCode: v.supplierCode || "",
            name: v.name || "",
            phone: v.phone || "",
            email: v.email || "",
            taxId: v.taxId || "",
            address: v.address || "",
            groupId: v.groupId || "",
            note: v.note || "",
            status: v.status || "ACTIVE",
            createdAt: v.createdAt || 0,
          });
        });
        setSuppliers(sups.sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0)));
      })
    );

    // Stock Balances
    const balRef = ref(db, `stores/${targetStoreCode}/stock_balances`);
    unsubs.push(
      onValue(balRef, (snap) => {
        const bals: StockBalanceItem[] = [];
        snap.forEach((child) => {
          const v = child.val();
          bals.push({
            balanceId: child.key!,
            branchId: v.branchId || targetStoreCode,
            itemId: v.itemId || "",
            onHandQty: v.onHandQty || 0,
            reservedQty: v.reservedQty || 0,
            inventoryValue: v.inventoryValue || 0,
            averageCostScaled: v.averageCostScaled || 0,
            updatedAt: v.updatedAt || 0,
          });
        });
        setStockBalances(bals);
      })
    );

    // Inventory Documents
    const docRef = ref(db, `stores/${targetStoreCode}/inventory_documents`);
    unsubs.push(
      onValue(docRef, (snap) => {
        const docs: InventoryDocItem[] = [];
        snap.forEach((child) => {
          const v = child.val();
          let parsedLines: InventoryDocLine[] = [];
          if (v.lines) {
            if (Array.isArray(v.lines)) {
              parsedLines = v.lines;
            } else if (typeof v.lines === "object") {
              parsedLines = Object.values(v.lines);
            }
          }
          docs.push({
            documentId: child.key!,
            documentCode: v.documentCode || "",
            docType: v.docType || "",
            status: v.status || "DRAFT",
            branchId: v.branchId || "",
            supplierId: v.supplierId || "",
            supplierName: v.supplierName || "",
            totalQuantity: v.totalQuantity || 0,
            totalMoney: v.totalMoney || 0,
            totalNetMoney: v.totalNetMoney || 0,
            note: v.note || "",
            reason: v.reason || "",
            lines: parsedLines,
            createdBy: v.createdBy || "",
            createdByName: v.createdByName || "",
            createdAt: v.createdAt || 0,
            completedAt: v.completedAt || 0,
            completedBy: v.completedBy || "",
            completedByName: v.completedByName || "",
            committedEventIds: v.committedEventIds || [],
            cancelReason: v.cancelReason || "",
          });
        });
        setDocuments(docs.sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0)));
      })
    );

    return () => unsubs.forEach((u) => u());
  }, [targetStoreCode]);

  // Filtered data
  const filteredCatalog = useMemo(() => {
    return catalogItems.filter((i) => {
      const matchSearch =
        !search ||
        i.name.toLowerCase().includes(search.toLowerCase()) ||
        i.sku.toLowerCase().includes(search.toLowerCase()) ||
        (i.managementGroup && i.managementGroup.toLowerCase().includes(search.toLowerCase()));
      const matchKind = !filterKind || i.kind === filterKind;
      return matchSearch && matchKind;
    });
  }, [catalogItems, search, filterKind]);

  const filteredSuppliers = useMemo(() => {
    return suppliers.filter((s) => {
      return (
        !search ||
        s.name.toLowerCase().includes(search.toLowerCase()) ||
        s.phone.includes(search) ||
        s.supplierCode.toLowerCase().includes(search.toLowerCase())
      );
    });
  }, [suppliers, search]);

  const filteredDocs = useMemo(() => {
    return documents.filter((d) => {
      const matchType = !filterDocType || d.docType === filterDocType;
      const matchStatus = !filterDocStatus || d.status === filterDocStatus;
      return matchType && matchStatus;
    });
  }, [documents, filterDocType, filterDocStatus]);

  // Stock balance lookup by itemId
  const balanceMap = useMemo(() => {
    const m: Record<string, StockBalanceItem> = {};
    stockBalances.forEach((b) => {
      m[b.itemId] = b;
    });
    return m;
  }, [stockBalances]);

  // Save Single Catalog Item
  const handleSaveItem = async () => {
    if (!itemForm.name.trim()) {
      setFormError("Tên hàng là bắt buộc");
      return;
    }
    if (!itemForm.baseUnitId.trim()) {
      setFormError("Đơn vị cơ bản là bắt buộc");
      return;
    }
    setSaving(true);
    setFormError("");
    try {
      const now = Date.now();
      const itemId = editingItem?.itemId || `ITM_${now}_${Math.random().toString(36).slice(2, 6)}`;
      const sku = editingItem?.sku || `NVL${String(catalogItems.length + 1).padStart(4, "0")}`;
      const data = {
        itemId,
        sku,
        name: itemForm.name.trim(),
        kind: itemForm.kind,
        managementGroup: itemForm.managementGroup.trim(),
        baseUnitId: itemForm.baseUnitId.trim(),
        trackStock: itemForm.trackStock,
        costPrice: parseInt(itemForm.costPrice) || 0,
        minStock: parseInt(itemForm.minStock) || 0,
        maxStock: parseInt(itemForm.maxStock) || 0,
        description: itemForm.description.trim(),
        status: "ACTIVE",
        createdAt: editingItem?.createdAt || now,
        updatedAt: now,
        version: 1,
      };
      await set(ref(db, `stores/${targetStoreCode}/catalog_items/${itemId}`), data);
      setShowItemModal(false);
      setEditingItem(null);
    } catch (e) {
      setFormError(errorMessage(e) || "Lỗi lưu hàng");
    }
    setSaving(false);
  };

  // Save Single Supplier
  const handleSaveSupplier = async () => {
    if (!supplierForm.name.trim()) {
      setFormError("Tên NCC là bắt buộc");
      return;
    }
    setSaving(true);
    setFormError("");
    try {
      const now = Date.now();
      const supplierId = editingSupplier?.supplierId || `SUP_${now}_${Math.random().toString(36).slice(2, 6)}`;
      const supplierCode = editingSupplier?.supplierCode || `NCC${String(suppliers.length + 1).padStart(4, "0")}`;
      const data = {
        supplierId,
        supplierCode,
        name: supplierForm.name.trim(),
        phone: supplierForm.phone.trim(),
        email: supplierForm.email.trim(),
        taxId: supplierForm.taxId.trim(),
        address: supplierForm.address.trim(),
        groupId: supplierForm.groupId.trim(),
        note: supplierForm.note.trim(),
        status: "ACTIVE",
        enabledBranches: [targetStoreCode],
        createdAt: editingSupplier?.createdAt || now,
        updatedAt: now,
        version: 1,
      };
      await set(ref(db, `stores/${targetStoreCode}/suppliers/${supplierId}`), data);
      setShowSupplierModal(false);
      setEditingSupplier(null);
    } catch (e) {
      setFormError(errorMessage(e) || "Lỗi lưu NCC");
    }
    setSaving(false);
  };

  const openEditItem = (item: CatalogItem) => {
    setEditingItem(item);
    setItemForm({
      name: item.name,
      sku: item.sku,
      kind: item.kind,
      managementGroup: item.managementGroup,
      baseUnitId: item.baseUnitId,
      trackStock: item.trackStock,
      costPrice: String(item.costPrice || ""),
      minStock: String(item.minStock || ""),
      maxStock: String(item.maxStock || ""),
      description: item.description,
    });
    setFormError("");
    setShowItemModal(true);
  };

  const openAddItem = () => {
    setEditingItem(null);
    setItemForm({
      name: "",
      sku: "",
      kind: "RAW_MATERIAL",
      managementGroup: "",
      baseUnitId: "g",
      trackStock: true,
      costPrice: "",
      minStock: "",
      maxStock: "",
      description: "",
    });
    setFormError("");
    setShowItemModal(true);
  };

  const openEditSupplier = (sup: SupplierItem) => {
    setEditingSupplier(sup);
    setSupplierForm({
      name: sup.name,
      phone: sup.phone,
      email: sup.email,
      taxId: sup.taxId,
      address: sup.address,
      groupId: sup.groupId,
      note: sup.note,
    });
    setFormError("");
    setShowSupplierModal(true);
  };

  const openAddSupplier = () => {
    setEditingSupplier(null);
    setSupplierForm({
      name: "",
      phone: "",
      email: "",
      taxId: "",
      address: "",
      groupId: "",
      note: "",
    });
    setFormError("");
    setShowSupplierModal(true);
  };

  // ==================== PHIẾU KHO ACTIONS ====================
  const openCreateDoc = (type: "PURCHASE_RECEIPT" | "INTERNAL_USE" | "WASTE") => {
    setDocModalType(type);
    setDocSupplierId(suppliers[0]?.supplierId || "");
    setDocReason(type === "INTERNAL_USE" ? "Pha chế quầy bar" : (type === "WASTE" ? "Hết hạn sử dụng" : ""));
    setDocNote("");
    setDocLines([]);
    setDocError("");
    setShowDocModal(true);
  };

  const applyDocCompletion = async (doc: InventoryDocItem) => {
    const now = Date.now();
    const eventIds: string[] = [];

    for (const line of (doc.lines || [])) {
      const balanceKey = `${targetStoreCode}_${line.itemId}`;
      const balSnap = await get(ref(db, `stores/${targetStoreCode}/stock_balances/${balanceKey}`));
      const balVal = balSnap.exists() ? balSnap.val() : null;

      const oldOnHandQty = balVal?.onHandQty || 0;
      const oldAvgCostScaled = balVal?.averageCostScaled || 0;
      const oldInventoryValue = balVal?.inventoryValue || 0;

      let qtyDelta = 0;
      let valueDelta = 0;
      let newOnHandQty = oldOnHandQty;
      let newInventoryValue = oldInventoryValue;
      let newAvgCostScaled = oldAvgCostScaled;

      if (doc.docType === "PURCHASE_RECEIPT" || doc.docType === "PRODUCTION_OUTPUT" || doc.docType === "OPENING" || doc.docType === "TRANSFER_RECEIVE") {
        qtyDelta = line.quantity;
        valueDelta = line.quantity * (line.unitPrice || 0);
        newOnHandQty = oldOnHandQty + qtyDelta;
        newInventoryValue = oldInventoryValue + valueDelta;
        const unitCostScaled = Math.round((line.unitPrice || 0) * 100);
        newAvgCostScaled = (oldOnHandQty + qtyDelta) > 0
          ? Math.round((oldOnHandQty * oldAvgCostScaled + qtyDelta * unitCostScaled) / (oldOnHandQty + qtyDelta))
          : unitCostScaled;
      } else {
        // INTERNAL_USE, WASTE
        qtyDelta = -line.quantity;
        valueDelta = -Math.round((line.quantity * oldAvgCostScaled) / 100);
        newOnHandQty = Math.max(0, oldOnHandQty - line.quantity);
        newInventoryValue = Math.max(0, oldInventoryValue - Math.abs(valueDelta));
        newAvgCostScaled = oldAvgCostScaled;
      }

      await set(ref(db, `stores/${targetStoreCode}/stock_balances/${balanceKey}`), {
        balanceId: balanceKey,
        branchId: targetStoreCode,
        itemId: line.itemId,
        onHandQty: newOnHandQty,
        reservedQty: balVal?.reservedQty || 0,
        inventoryValue: newInventoryValue,
        averageCostScaled: newAvgCostScaled,
        updatedAt: now,
      });

      const eventId = `EVT_${now}_${Math.random().toString(36).slice(2, 6)}`;
      eventIds.push(eventId);
      await set(ref(db, `stores/${targetStoreCode}/stock_events/${eventId}`), {
        eventId,
        commandId: `${doc.documentId}_${now}`,
        documentId: doc.documentId,
        documentType: doc.docType,
        documentLineId: line.lineId || `LINE_${line.itemId}`,
        branchId: targetStoreCode,
        itemId: line.itemId,
        qtyDeltaBase: qtyDelta,
        valueDeltaMoney: valueDelta,
        unitCostSnapshot: oldAvgCostScaled,
        occurredAt: now,
        committedAt: now,
        actorId: user?.username || "admin",
        sequence: now,
      });
    }

    if (doc.docType === "PURCHASE_RECEIPT" && doc.supplierId) {
      const ledgerId = `LED_${now}_${Math.random().toString(36).slice(2, 6)}`;
      await set(ref(db, `stores/${targetStoreCode}/supplier_ledger/${ledgerId}`), {
        entryId: ledgerId,
        supplierId: doc.supplierId,
        branchId: targetStoreCode,
        entryType: "PURCHASE",
        amountMoney: doc.totalNetMoney || doc.totalMoney,
        referenceDocId: doc.documentId,
        referenceDocType: doc.docType,
        occurredAt: now,
        committedAt: now,
        actorId: user?.username || "admin",
      });
    }

    await update(ref(db, `stores/${targetStoreCode}/inventory_documents/${doc.documentId}`), {
      status: "COMPLETED",
      completedAt: now,
      completedBy: user?.username || "admin",
      completedByName: user?.fullName || "Quản trị viên",
      committedEventIds: eventIds,
    });

    const logId = `AUDIT_${now}_${Math.random().toString(36).slice(2, 6)}`;
    await set(ref(db, `stores/${targetStoreCode}/audit_logs/${logId}`), {
      timestamp: now,
      username: user?.username || "admin",
      userFullName: user?.fullName || "Quản trị viên",
      userRole: user?.role || "ADMIN",
      action: `COMPLETE_${doc.docType}`,
      targetType: "INVENTORY_DOCUMENT",
      targetId: doc.documentCode || doc.documentId,
      storeCode: targetStoreCode,
      details: `Hoàn thành phiếu ${docTypeLabels[doc.docType] || doc.docType} ${doc.documentCode} (${doc.totalQuantity} SP, ${formatVND(doc.totalMoney)})`,
    });
  };

  const handleSaveDoc = async (isComplete: boolean) => {
    if (docModalType === "PURCHASE_RECEIPT" && !docSupplierId) {
      setDocError("Vui lòng chọn nhà cung cấp");
      return;
    }
    if (docLines.length === 0) {
      setDocError("Vui lòng thêm ít nhất 1 mặt hàng");
      return;
    }
    for (const l of docLines) {
      if (!l.quantity || l.quantity <= 0) {
        setDocError(`Số lượng mặt hàng "${l.itemName}" phải lớn hơn 0`);
        return;
      }
    }
    if (isComplete && !canCompleteDoc) {
      setDocError("Bạn không có quyền duyệt hoàn thành phiếu");
      return;
    }

    setDocSaving(true);
    setDocError("");
    try {
      const now = Date.now();
      const docId = `DOC_${now}_${Math.random().toString(36).slice(2, 6)}`;
      const prefix = docModalType === "PURCHASE_RECEIPT" ? "PN" : (docModalType === "INTERNAL_USE" ? "PX" : "PH");
      const docCode = `${prefix}-${now.toString().slice(5)}`;
      const totalQty = docLines.reduce((s, l) => s + l.quantity, 0);
      const totalMoney = docLines.reduce((s, l) => s + l.lineNetMoney, 0);
      const selectedSup = suppliers.find((s) => s.supplierId === docSupplierId);

      const docData: InventoryDocItem = {
        documentId: docId,
        documentCode: docCode,
        docType: docModalType,
        status: isComplete ? "COMPLETED" : "DRAFT",
        branchId: targetStoreCode,
        supplierId: docModalType === "PURCHASE_RECEIPT" ? docSupplierId : "",
        supplierName: docModalType === "PURCHASE_RECEIPT" ? (selectedSup?.name || "") : "",
        reason: (docModalType === "INTERNAL_USE" || docModalType === "WASTE") ? docReason : "",
        lines: docLines,
        totalQuantity: totalQty,
        totalMoney: totalMoney,
        totalNetMoney: totalMoney,
        note: docNote.trim(),
        createdBy: user?.username || "admin",
        createdByName: user?.fullName || "Quản trị viên",
        createdAt: now,
      };

      await set(ref(db, `stores/${targetStoreCode}/inventory_documents/${docId}`), docData);

      if (isComplete) {
        await applyDocCompletion(docData);
      }

      setShowDocModal(false);
      setDocLines([]);
    } catch (e) {
      setDocError(errorMessage(e) || "Lỗi lưu phiếu kho");
    } finally {
      setDocSaving(false);
    }
  };

  const handleCompleteDraftDoc = async (doc: InventoryDocItem) => {
    if (!canCompleteDoc) {
      alert("Bạn không có quyền duyệt phiếu");
      return;
    }
    if (!confirm(`Bạn có chắc muốn hoàn thành phiếu ${doc.documentCode}? Số lượng tồn kho sẽ được cập nhật ngay lập tức.`)) {
      return;
    }
    setActionInProgress(true);
    try {
      await applyDocCompletion(doc);
      setViewingDoc(null);
    } catch (e) {
      alert("Lỗi khi duyệt phiếu: " + (errorMessage(e) || String(e)));
    } finally {
      setActionInProgress(false);
    }
  };

  const handleCancelDraftDoc = async (doc: InventoryDocItem) => {
    if (!confirm(`Bạn có chắc muốn huỷ phiếu ${doc.documentCode}?`)) {
      return;
    }
    setActionInProgress(true);
    try {
      await update(ref(db, `stores/${targetStoreCode}/inventory_documents/${doc.documentId}`), {
        status: "CANCELLED",
        cancelReason: "Huỷ bởi người dùng",
      });
      setViewingDoc(null);
    } catch (e) {
      alert("Lỗi khi huỷ phiếu: " + (errorMessage(e) || String(e)));
    } finally {
      setActionInProgress(false);
    }
  };

  // ==================== TẢI FILE MẪU EXCEL ====================
  const downloadSampleTemplate = () => {
    const headers = [
      "Nhóm quản lý",
      "Nhóm hàng (3 Cấp)",
      "Mã hàng",
      "Tên hàng",
      "Giá vốn",
      "Tồn kho hiện tại",
      "Định mức tồn nhỏ nhất",
      "Định mức tồn lớn nhất",
      "ĐVT",
      "Mã ĐVT Cơ bản",
      "Quy đổi",
      "Thuộc tính",
      "Mã hàng liên quan",
      "Hình ảnh (url1,url2...)",
      "Trọng lượng",
      "ĐVT trọng lượng",
      "Đang sử dụng",
      "Quản lý tồn kho",
      "Mô tả",
      "Vị trí",
      "Thương hiệu",
    ];

    const sampleRows = [
      ["Nguyên vật liệu", "Mứt", "SP000001", "Mứt Sinh Tố Ổi Xanh", 140000, 20, 0, 999999999, "lít", "", 1, "", "", "", 1, "kg", 1, 1, "", "Kho chính|Kho phụ|Kho tạm", "GreenFarm"],
      ["Công cụ dụng cụ", "Nắp cốc", "SP000002", "Nắp dẹt", 3000, 10, 0, 999999999, "cái", "", 1, "", "", "", 10, "g", 1, 1, "", "", "Bao bì Gia Thành"],
      ["Công cụ dụng cụ", "Nắp cốc", "SP000003", "Nắp tròn", 3000, 10, 0, 999999999, "cái", "", 1, "", "", "", 10, "g", 0, 1, "", "Kho chính", "Bao bì Gia Thành"],
      ["Công cụ dụng cụ", "Cốc", "SP000004", "Cốc giấy 12oz", 3000, 1000, 0, 999999999, "cái", "", 1, "", "", "", 20, "g", 1, 1, "", "Kho phụ", "Bao bì Gia Thành"],
    ];

    const ws = XLSX.utils.aoa_to_sheet([headers, ...sampleRows]);
    ws["!cols"] = [
      { wch: 18 }, { wch: 16 }, { wch: 12 }, { wch: 25 }, { wch: 12 },
      { wch: 16 }, { wch: 22 }, { wch: 22 }, { wch: 10 }, { wch: 14 },
      { wch: 10 }, { wch: 12 }, { wch: 16 }, { wch: 22 }, { wch: 12 },
      { wch: 16 }, { wch: 14 }, { wch: 16 }, { wch: 20 }, { wch: 25 }, { wch: 18 },
    ];

    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, "HangHoa");
    XLSX.writeFile(wb, "Mau_Nhap_Hang_Hoa_Kho.xlsx");
  };

  // ==================== XUẤT FILE EXCEL HÀNG HÓA KHO ====================
  const exportInventoryExcel = () => {
    const headers = [
      "Nhóm quản lý",
      "Nhóm hàng (3 Cấp)",
      "Mã hàng",
      "Tên hàng",
      "Giá vốn",
      "Tồn kho hiện tại",
      "Định mức tồn nhỏ nhất",
      "Định mức tồn lớn nhất",
      "ĐVT",
      "Mã ĐVT Cơ bản",
      "Quy đổi",
      "Thuộc tính",
      "Mã hàng liên quan",
      "Hình ảnh (url1,url2...)",
      "Trọng lượng",
      "ĐVT trọng lượng",
      "Đang sử dụng",
      "Quản lý tồn kho",
      "Mô tả",
      "Vị trí",
      "Thương hiệu",
    ];

    const rows = catalogItems.map((item) => {
      const bal = balanceMap[item.itemId];
      const onHand = bal?.onHandQty || 0;
      const kindName = item.kind === "TOOL" ? "Công cụ dụng cụ" : "Nguyên vật liệu";
      const inUse = item.status === "DISCONTINUED" ? 0 : 1;
      const track = item.trackStock ? 1 : 0;

      return [
        item.managementGroup || kindName,
        item.managementGroup || (kindLabels[item.kind] || item.kind),
        item.sku,
        item.name,
        item.costPrice || 0,
        onHand,
        item.minStock || 0,
        item.maxStock || 999999999,
        item.baseUnitId || "cái",
        "",
        item.conversionRate || 1,
        "",
        "",
        item.imageUrl || "",
        item.weight || 0,
        item.weightUnit || "",
        inUse,
        track,
        item.description || "",
        item.location || "",
        item.brand || "",
      ];
    });

    const ws = XLSX.utils.aoa_to_sheet([headers, ...rows]);
    ws["!cols"] = [
      { wch: 18 }, { wch: 16 }, { wch: 12 }, { wch: 25 }, { wch: 12 },
      { wch: 16 }, { wch: 22 }, { wch: 22 }, { wch: 10 }, { wch: 14 },
      { wch: 10 }, { wch: 12 }, { wch: 16 }, { wch: 22 }, { wch: 12 },
      { wch: 16 }, { wch: 14 }, { wch: 16 }, { wch: 20 }, { wch: 25 }, { wch: 18 },
    ];

    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, "HangHoa");
    XLSX.writeFile(wb, `Danh_Sach_Hang_Hoa_Kho_${targetStoreCode}_${new Date().toISOString().slice(0, 10)}.xlsx`);
  };

  // ==================== XỬ LÝ ĐỌC VÀ PARSE FILE EXCEL ====================
  const handleFileUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setImportedFile(file);

    const reader = new FileReader();
    reader.onload = (evt) => {
      try {
        const buffer = evt.target?.result as ArrayBuffer;
        const workbook = XLSX.read(new Uint8Array(buffer), { type: "array" });
        const sheetName = workbook.SheetNames[0];
        const worksheet = workbook.Sheets[sheetName];
        const rawJson: unknown[][] = XLSX.utils.sheet_to_json(worksheet, { header: 1 });

        if (!rawJson || rawJson.length < 2) {
          alert("File Excel không có dữ liệu hàng hóa!");
          return;
        }

        // Header mapping
        const headerRow = rawJson[0].map((h) => String(h || "").trim().toLowerCase());
        const getColIdx = (aliases: string[]) => {
          return headerRow.findIndex((col) => aliases.some((a) => col.includes(a)));
        };

        const idxGroup = getColIdx(["nhóm quản lý", "loại hàng"]);
        const idxCategory = getColIdx(["nhóm hàng", "danh mục"]);
        const idxSku = getColIdx(["mã hàng", "mã", "sku"]);
        const idxName = getColIdx(["tên hàng", "tên"]);
        const idxCost = getColIdx(["giá vốn", "giá nhập"]);
        const idxOnHand = getColIdx(["tồn kho hiện tại", "tồn kho", "tồn"]);
        const idxMin = getColIdx(["định mức tồn nhỏ nhất", "tồn nhỏ nhất", "tồn tối thiểu"]);
        const idxMax = getColIdx(["định mức tồn lớn nhất", "tồn lớn nhất", "tồn tối đa"]);
        const idxUnit = getColIdx(["đvt", "đơn vị"]);
        const idxUnitCode = getColIdx(["mã đvt cơ bản"]);
        const idxConversion = getColIdx(["quy đổi"]);
        const idxAttr = getColIdx(["thuộc tính"]);
        const idxRelSku = getColIdx(["mã hàng liên quan"]);
        const idxImg = getColIdx(["hình ảnh", "ảnh"]);
        const idxWeight = getColIdx(["trọng lượng"]);
        const idxWeightUnit = getColIdx(["đvt trọng lượng"]);
        const idxInUse = getColIdx(["đang sử dụng", "sử dụng"]);
        const idxTrack = getColIdx(["quản lý tồn kho"]);
        const idxDesc = getColIdx(["mô tả"]);
        const idxLocation = getColIdx(["vị trí"]);
        const idxBrand = getColIdx(["thương hiệu"]);

        const rows: ParsedItemRow[] = [];
        const seenSkusInFile = new Set<string>();

        for (let i = 1; i < rawJson.length; i++) {
          const row = rawJson[i];
          if (!row || row.length === 0 || row.every((c) => c === undefined || c === null || String(c).trim() === "")) {
            continue;
          }

          const rawName = String(row[idxName >= 0 ? idxName : 3] || "").trim();
          if (!rawName || rawName.toLowerCase() === "total") continue;

          const rawGroup = String(row[idxGroup >= 0 ? idxGroup : 0] || "").trim();
          const rawCat = String(row[idxCategory >= 0 ? idxCategory : 1] || "").trim();
          let rawSku = String(row[idxSku >= 0 ? idxSku : 2] || "").trim();
          if (!rawSku) {
            rawSku = `SP${String(i).padStart(6, "0")}`;
          }

          const cleanNum = (val: unknown, fallback = 0) => {
            if (typeof val === "number") return val;
            if (!val) return fallback;
            const cleaned = String(val).replace(/[^0-9\-]/g, "");
            return parseInt(cleaned) || fallback;
          };

          const rawCost = cleanNum(row[idxCost >= 0 ? idxCost : 4], 0);
          const rawOnHand = cleanNum(row[idxOnHand >= 0 ? idxOnHand : 5], 0);
          const rawMin = cleanNum(row[idxMin >= 0 ? idxMin : 6], 0);
          const rawMax = cleanNum(row[idxMax >= 0 ? idxMax : 7], 999999999);
          const rawUnit = String(row[idxUnit >= 0 ? idxUnit : 8] || "cái").trim();
          const rawUnitCode = String(row[idxUnitCode >= 0 ? idxUnitCode : 9] || "").trim();
          const rawConversion = cleanNum(row[idxConversion >= 0 ? idxConversion : 10], 1);
          const rawAttr = String(row[idxAttr >= 0 ? idxAttr : 11] || "").trim();
          const rawRelSku = String(row[idxRelSku >= 0 ? idxRelSku : 12] || "").trim();
          const rawImg = String(row[idxImg >= 0 ? idxImg : 13] || "").trim();
          const rawWeight = cleanNum(row[idxWeight >= 0 ? idxWeight : 14], 0);
          const rawWeightUnit = String(row[idxWeightUnit >= 0 ? idxWeightUnit : 15] || "").trim();

          const rawInUseVal = String(row[idxInUse >= 0 ? idxInUse : 16] ?? "1").trim().toLowerCase();
          const status = rawInUseVal === "0" || rawInUseVal === "false" || rawInUseVal === "ngưng" ? "DISCONTINUED" : "ACTIVE";

          const rawTrackVal = String(row[idxTrack >= 0 ? idxTrack : 17] ?? "1").trim().toLowerCase();
          const trackStock = !(rawTrackVal === "0" || rawTrackVal === "false" || rawTrackVal === "không");

          const rawDesc = String(row[idxDesc >= 0 ? idxDesc : 18] || "").trim();
          const rawLoc = String(row[idxLocation >= 0 ? idxLocation : 19] || "").trim();
          const rawBrand = String(row[idxBrand >= 0 ? idxBrand : 20] || "").trim();

          const kind = rawGroup.toLowerCase().includes("công cụ") ? "TOOL" : "RAW_MATERIAL";

          // Validation & duplicate checks
          let isValid = true;
          let statusMessage = "Hợp lệ (Thêm mới)";
          let isDuplicateSkuDifferentName = false;

          const existingItem = catalogItems.find((ci) => ci.sku.toLowerCase() === rawSku.toLowerCase());
          if (existingItem) {
            if (existingItem.name.trim().toLowerCase() !== rawName.toLowerCase()) {
              isDuplicateSkuDifferentName = true;
              if (duplicateSkuOption === "error") {
                isValid = false;
                statusMessage = `Lỗi: Trùng mã hàng với [${existingItem.name}] (chọn 'Thay thế tên hàng' để cập nhật)`;
              } else {
                isValid = true;
                statusMessage = `Cập nhật tên mới cho món [${existingItem.name}]`;
              }
            } else {
              statusMessage = "Cập nhật mặt hàng hiện có";
            }
          }

          if (seenSkusInFile.has(rawSku.toLowerCase())) {
            isValid = false;
            statusMessage = `Lỗi: Mã hàng ${rawSku} bị lặp lại nhiều lần trong file`;
          }
          seenSkusInFile.add(rawSku.toLowerCase());

          rows.push({
            index: i,
            managementGroup: rawGroup || (kind === "TOOL" ? "Công cụ dụng cụ" : "Nguyên vật liệu"),
            category: rawCat,
            sku: rawSku,
            name: rawName,
            costPrice: rawCost,
            onHandQty: rawOnHand,
            minStock: rawMin,
            maxStock: rawMax,
            unit: rawUnit,
            unitCode: rawUnitCode,
            conversionRate: rawConversion,
            attributes: rawAttr,
            relatedSku: rawRelSku,
            imageUrl: rawImg,
            weight: rawWeight,
            weightUnit: rawWeightUnit,
            status,
            trackStock,
            description: rawDesc,
            location: rawLoc,
            brand: rawBrand,
            kind,
            isValid,
            statusMessage,
            isDuplicateSkuDifferentName,
          });
        }

        setParsedRows(rows);
      } catch (err) {
        alert("Lỗi khi đọc file Excel: " + (errorMessage(err) || String(err)));
      }
    };
    reader.readAsArrayBuffer(file);
  };

  // ==================== THỰC HIỆN IMPORT VÀO HỆ THỐNG ====================
  const executeImport = async () => {
    const validRows = parsedRows.filter((r) => r.isValid);
    if (validRows.length === 0) {
      alert("Không có dòng nào hợp lệ để nhập vào hệ thống!");
      return;
    }

    setIsImporting(true);
    try {
      const now = Date.now();
      const targetBranches =
        scopeOption === "all"
          ? stores.filter((s) => s.active !== false).map((s) => s.storeCode)
          : [targetStoreCode];

      for (const branch of targetBranches) {
        for (const r of validRows) {
          const existingItem = catalogItems.find((ci) => ci.sku.toLowerCase() === r.sku.toLowerCase());
          const itemId = existingItem?.itemId || `ITM_${now}_${Math.random().toString(36).slice(2, 6)}`;

          const itemData = {
            itemId,
            sku: r.sku,
            name: r.name,
            kind: r.kind,
            managementGroup: r.category || r.managementGroup,
            groupIds: r.category ? [r.category] : [],
            baseUnitId: r.unit || "cái",
            conversionRate: r.conversionRate || 1,
            trackStock: r.trackStock,
            costPrice: r.costPrice || 0,
            minStock: r.minStock || 0,
            maxStock: r.maxStock || 999999999,
            status: r.status,
            description: r.description || "",
            imageUrl: r.imageUrl || "",
            weight: r.weight || 0,
            weightUnit: r.weightUnit || "",
            location: r.location || "",
            brand: r.brand || "",
            createdAt: existingItem?.createdAt || now,
            updatedAt: now,
            version: 1,
          };

          await set(ref(db, `stores/${branch}/catalog_items/${itemId}`), itemData);

          // Cập nhật tồn kho nếu chọn Option "Có"
          if (updateStockBalanceOption === "yes" && r.trackStock) {
            const balanceId = `${branch}_${itemId}`;
            const balData = {
              balanceId,
              branchId: branch,
              itemId: itemId,
              onHandQty: r.onHandQty,
              reservedQty: 0,
              inventoryValue: r.onHandQty * (r.costPrice || 0),
              averageCostScaled: (r.costPrice || 0) * 100,
              updatedAt: now,
            };
            await set(ref(db, `stores/${branch}/stock_balances/${balanceId}`), balData);
          }
        }
      }

      setImportSuccessMsg(`Đã nhập thành công ${validRows.length} mặt hàng vào kho!`);
      setTimeout(() => {
        setImportSuccessMsg("");
        setShowImportModal(false);
        setImportStep(1);
        setImportedFile(null);
        setParsedRows([]);
      }, 2000);
    } catch (e) {
      alert("Lỗi khi nhập dữ liệu: " + (errorMessage(e) || String(e)));
    } finally {
      setIsImporting(false);
    }
  };

  const tabs = [
    { key: "catalog" as const, label: "Danh sách hàng", icon: Package, count: catalogItems.length },
    { key: "stock" as const, label: "Tồn kho", icon: Warehouse, count: stockBalances.length },
    { key: "documents" as const, label: "Phiếu kho", icon: ClipboardList, count: documents.length },
    { key: "suppliers" as const, label: "Nhà cung cấp", icon: Truck, count: suppliers.length },
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
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "24px", flexWrap: "wrap", gap: "12px" }}>
        <div>
          <h1 style={{ fontSize: "24px", fontWeight: "800", color: "#1a1a2e", margin: 0 }}>
            📦 Kho hàng & Nguyên vật liệu
          </h1>
          <p style={{ fontSize: "14px", color: "#666", margin: "4px 0 0" }}>
            Quản lý danh mục hàng hóa, tồn kho, nhập/xuất và nhà cung cấp
          </p>
        </div>
        <div style={{ display: "flex", gap: "8px", flexWrap: "wrap" }}>
          {activeTab === "catalog" && (
            <>
              <button
                onClick={() => {
                  setImportStep(1);
                  setImportedFile(null);
                  setParsedRows([]);
                  setShowImportModal(true);
                }}
                style={btnSecondary}
              >
                <Upload size={16} /> Nhập Excel
              </button>
              <button onClick={exportInventoryExcel} style={btnSecondary}>
                <Download size={16} /> Xuất Excel
              </button>
              <button onClick={openAddItem} style={btnPrimary}>
                <Plus size={16} /> Thêm hàng
              </button>
            </>
          )}
          {activeTab === "stock" && (
            <button onClick={exportInventoryExcel} style={btnSecondary}>
              <Download size={16} /> Xuất Excel tồn kho
            </button>
          )}
          {activeTab === "documents" && (
            <>
              {canStockIn && (
                <button onClick={() => openCreateDoc("PURCHASE_RECEIPT")} style={btnPrimary}>
                  <Plus size={16} /> Nhập kho
                </button>
              )}
              {canStockOut && (
                <button onClick={() => openCreateDoc("INTERNAL_USE")} style={{ ...btnPrimary, background: "#0284c7" }}>
                  <Plus size={16} /> Xuất kho
                </button>
              )}
              {canWaste && (
                <button onClick={() => openCreateDoc("WASTE")} style={{ ...btnPrimary, background: "#dc2626" }}>
                  <Plus size={16} /> Huỷ kho
                </button>
              )}
            </>
          )}
          {activeTab === "suppliers" && (
            <button onClick={openAddSupplier} style={btnPrimary}>
              <Plus size={16} /> Thêm NCC
            </button>
          )}
        </div>
      </div>

      {/* Store Selector */}
      {stores.length > 1 && (
        <div style={{ marginBottom: "16px", display: "flex", gap: "8px", flexWrap: "wrap" }}>
          {stores.filter((s) => s.active !== false).map((s) => (
            <button
              key={s.storeCode}
              onClick={() => setCurrentStoreCode(s.storeCode)}
              style={{
                padding: "6px 14px",
                borderRadius: "8px",
                fontSize: "13px",
                fontWeight: "600",
                cursor: "pointer",
                border: targetStoreCode === s.storeCode ? "2px solid #7E2930" : "1px solid #ddd",
                background: targetStoreCode === s.storeCode ? "#7E2930" : "#fff",
                color: targetStoreCode === s.storeCode ? "#fff" : "#333",
              }}
            >
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
            <button
              key={tab.key}
              onClick={() => {
                setActiveTab(tab.key);
                setSearch("");
              }}
              style={{
                display: "flex",
                alignItems: "center",
                gap: "6px",
                padding: "10px 16px",
                fontSize: "13px",
                fontWeight: isActive ? "700" : "500",
                cursor: "pointer",
                border: "none",
                borderBottom: isActive ? "3px solid #7E2930" : "3px solid transparent",
                background: "transparent",
                color: isActive ? "#7E2930" : "#666",
                marginBottom: "-2px",
              }}
            >
              <Icon size={16} />
              {tab.label}
              <span
                style={{
                  background: isActive ? "#7E2930" : "#e5e7eb",
                  color: isActive ? "#fff" : "#666",
                  fontSize: "11px",
                  fontWeight: "700",
                  padding: "1px 6px",
                  borderRadius: "10px",
                }}
              >
                {tab.count}
              </span>
            </button>
          );
        })}
      </div>

      {/* Search & Filters */}
      <div style={{ display: "flex", gap: "12px", marginBottom: "16px", alignItems: "center", flexWrap: "wrap" }}>
        <div style={{ flex: 1, minWidth: "260px", position: "relative" }}>
          <Search size={16} style={{ position: "absolute", left: "12px", top: "50%", transform: "translateY(-50%)", color: "#999" }} />
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder={
              activeTab === "catalog"
                ? "Tìm theo tên, mã hàng, nhóm hàng..."
                : activeTab === "suppliers"
                ? "Tìm theo tên, SĐT, mã NCC..."
                : "Tìm kiếm..."
            }
            style={{ width: "100%", padding: "10px 12px 10px 36px", borderRadius: "8px", border: "1px solid #ddd", fontSize: "14px" }}
          />
        </div>
        {activeTab === "catalog" && (
          <select
            value={filterKind}
            onChange={(e) => setFilterKind(e.target.value)}
            style={{ padding: "10px 12px", borderRadius: "8px", border: "1px solid #ddd", fontSize: "13px", minWidth: "160px" }}
          >
            <option value="">Tất cả loại</option>
            {Object.entries(kindLabels).map(([k, v]) => (
              <option key={k} value={k}>
                {v}
              </option>
            ))}
          </select>
        )}
        {activeTab === "documents" && (
          <>
            <select
              value={filterDocType}
              onChange={(e) => setFilterDocType(e.target.value)}
              style={{ padding: "10px 12px", borderRadius: "8px", border: "1px solid #ddd", fontSize: "13px", minWidth: "140px" }}
            >
              <option value="">Tất cả loại</option>
              {Object.entries(docTypeLabels).map(([k, v]) => (
                <option key={k} value={k}>
                  {v}
                </option>
              ))}
            </select>
            <select
              value={filterDocStatus}
              onChange={(e) => setFilterDocStatus(e.target.value)}
              style={{ padding: "10px 12px", borderRadius: "8px", border: "1px solid #ddd", fontSize: "13px", minWidth: "120px" }}
            >
              <option value="">Tất cả trạng thái</option>
              <option value="DRAFT">Phiếu tạm</option>
              <option value="COMPLETED">Hoàn thành</option>
              <option value="CANCELLED">Đã hủy</option>
            </select>
          </>
        )}
      </div>

      {/* Content */}
      {loading ? (
        <div style={{ textAlign: "center", padding: "60px", color: "#999" }}>⏳ Đang tải dữ liệu...</div>
      ) : (
        <>
          {activeTab === "catalog" && <CatalogTable items={filteredCatalog} balanceMap={balanceMap} onEdit={openEditItem} />}
          {activeTab === "stock" && <StockTable items={catalogItems.filter((i) => i.trackStock)} balanceMap={balanceMap} />}
          {activeTab === "documents" && <DocumentsTable docs={filteredDocs} onSelectDoc={setViewingDoc} />}
          {activeTab === "suppliers" && <SuppliersTable suppliers={filteredSuppliers} onEdit={openEditSupplier} />}
        </>
      )}

      {/* Add/Edit Item Modal */}
      {showItemModal && (
        <Modal title={editingItem ? "Sửa hàng hóa" : "Thêm hàng hóa"} onClose={() => setShowItemModal(false)}>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "12px" }}>
            <FormField label="Tên hàng *" value={itemForm.name} onChange={(v) => setItemForm({ ...itemForm, name: v })} />
            <FormField label="Mã hàng (tự động)" value={itemForm.sku} onChange={(v) => setItemForm({ ...itemForm, sku: v })} disabled={!!editingItem} />
            <div>
              <label style={labelStyle}>Loại hàng</label>
              <select value={itemForm.kind} onChange={(e) => setItemForm({ ...itemForm, kind: e.target.value })} style={inputStyle}>
                {Object.entries(kindLabels).map(([k, v]) => (
                  <option key={k} value={k}>
                    {v}
                  </option>
                ))}
              </select>
            </div>
            <FormField label="Nhóm quản lý" value={itemForm.managementGroup} onChange={(v) => setItemForm({ ...itemForm, managementGroup: v })} />
            <FormField label="Đơn vị cơ bản *" value={itemForm.baseUnitId} onChange={(v) => setItemForm({ ...itemForm, baseUnitId: v })} placeholder="g, ml, cái, chai..." />
            <FormField label="Giá vốn (VND)" value={itemForm.costPrice} onChange={(v) => setItemForm({ ...itemForm, costPrice: v })} type="number" />
            <FormField label="Tồn tối thiểu" value={itemForm.minStock} onChange={(v) => setItemForm({ ...itemForm, minStock: v })} type="number" />
            <FormField label="Tồn tối đa" value={itemForm.maxStock} onChange={(v) => setItemForm({ ...itemForm, maxStock: v })} type="number" />
            <div style={{ gridColumn: "1 / -1" }}>
              <label style={{ ...labelStyle, display: "flex", alignItems: "center", gap: "8px" }}>
                <input type="checkbox" checked={itemForm.trackStock} onChange={(e) => setItemForm({ ...itemForm, trackStock: e.target.checked })} />
                Quản lý tồn kho
              </label>
            </div>
            <div style={{ gridColumn: "1 / -1" }}>
              <FormField label="Mô tả" value={itemForm.description} onChange={(v) => setItemForm({ ...itemForm, description: v })} />
            </div>
          </div>
          {formError && <div style={{ color: "#ef4444", fontSize: "13px", marginTop: "8px" }}>{formError}</div>}
          <div style={{ display: "flex", justifyContent: "flex-end", gap: "8px", marginTop: "16px" }}>
            <button onClick={() => setShowItemModal(false)} style={btnSecondary}>Hủy</button>
            <button onClick={handleSaveItem} disabled={saving} style={btnPrimary}>
              {saving ? "Đang lưu..." : "Lưu"}
            </button>
          </div>
        </Modal>
      )}

      {/* Add/Edit Supplier Modal */}
      {showSupplierModal && (
        <Modal title={editingSupplier ? "Sửa nhà cung cấp" : "Thêm nhà cung cấp"} onClose={() => setShowSupplierModal(false)}>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "12px" }}>
            <FormField label="Tên NCC *" value={supplierForm.name} onChange={(v) => setSupplierForm({ ...supplierForm, name: v })} />
            <FormField label="Số điện thoại" value={supplierForm.phone} onChange={(v) => setSupplierForm({ ...supplierForm, phone: v })} />
            <FormField label="Email" value={supplierForm.email} onChange={(v) => setSupplierForm({ ...supplierForm, email: v })} />
            <FormField label="Mã số thuế" value={supplierForm.taxId} onChange={(v) => setSupplierForm({ ...supplierForm, taxId: v })} />
            <div style={{ gridColumn: "1 / -1" }}>
              <FormField label="Địa chỉ" value={supplierForm.address} onChange={(v) => setSupplierForm({ ...supplierForm, address: v })} />
            </div>
            <FormField label="Nhóm NCC" value={supplierForm.groupId} onChange={(v) => setSupplierForm({ ...supplierForm, groupId: v })} />
            <FormField label="Ghi chú" value={supplierForm.note} onChange={(v) => setSupplierForm({ ...supplierForm, note: v })} />
          </div>
          {formError && <div style={{ color: "#ef4444", fontSize: "13px", marginTop: "8px" }}>{formError}</div>}
          <div style={{ display: "flex", justifyContent: "flex-end", gap: "8px", marginTop: "16px" }}>
            <button onClick={() => setShowSupplierModal(false)} style={btnSecondary}>Hủy</button>
            <button onClick={handleSaveSupplier} disabled={saving} style={btnPrimary}>
              {saving ? "Đang lưu..." : "Lưu"}
            </button>
          </div>
        </Modal>
      )}

      {/* ==================== MODAL TẠO PHIẾU KHO (NHẬP, XUẤT, HỦY) ==================== */}
      {showDocModal && (
        <Modal
          title={
            docModalType === "PURCHASE_RECEIPT"
              ? "📥 Tạo phiếu nhập kho"
              : docModalType === "INTERNAL_USE"
              ? "📤 Tạo phiếu xuất kho"
              : "🗑️ Tạo phiếu xuất hủy"
          }
          onClose={() => setShowDocModal(false)}
        >
          <div style={{ display: "flex", flexDirection: "column", gap: "14px" }}>
            {docError && (
              <div style={{ padding: "10px 14px", background: "#FEE2E2", color: "#DC2626", borderRadius: "8px", fontSize: "13px" }}>
                ⚠️ {docError}
              </div>
            )}

            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "12px" }}>
              {docModalType === "PURCHASE_RECEIPT" && (
                <div>
                  <label style={labelStyle}>Nhà cung cấp *</label>
                  <select
                    value={docSupplierId}
                    onChange={(e) => setDocSupplierId(e.target.value)}
                    style={inputStyle}
                  >
                    <option value="">-- Chọn nhà cung cấp --</option>
                    {suppliers.map((s) => (
                      <option key={s.supplierId} value={s.supplierId}>
                        {s.name} ({s.supplierCode})
                      </option>
                    ))}
                  </select>
                </div>
              )}

              {(docModalType === "INTERNAL_USE" || docModalType === "WASTE") && (
                <div>
                  <label style={labelStyle}>Lý do {docModalType === "INTERNAL_USE" ? "xuất" : "hủy"} *</label>
                  <input
                    value={docReason}
                    onChange={(e) => setDocReason(e.target.value)}
                    placeholder={
                      docModalType === "INTERNAL_USE"
                        ? "Ví dụ: Pha chế quầy bar, Bếp chế biến..."
                        : "Ví dụ: Hết hạn sử dụng, Hư hỏng, Bể vỡ..."
                    }
                    style={inputStyle}
                  />
                </div>
              )}

              <div>
                <label style={labelStyle}>Ghi chú phiếu</label>
                <input
                  value={docNote}
                  onChange={(e) => setDocNote(e.target.value)}
                  placeholder="Ghi chú nội dung..."
                  style={inputStyle}
                />
              </div>
            </div>

            {/* Bảng danh sách hàng hóa trong phiếu */}
            <div style={{ marginTop: "8px" }}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "8px" }}>
                <span style={{ fontSize: "14px", fontWeight: "700", color: "#1f2937" }}>
                  Danh sách hàng hóa ({docLines.length})
                </span>
                <button
                  type="button"
                  onClick={() => {
                    const availableItems = catalogItems.filter((i) => i.trackStock);
                    if (availableItems.length === 0) {
                      alert("Chưa có mặt hàng nào được quản lý tồn kho.");
                      return;
                    }
                    const itemToAdd = availableItems[0];
                    const unitPrice =
                      docModalType === "PURCHASE_RECEIPT"
                        ? (itemToAdd.costPrice || 0)
                        : (balanceMap[itemToAdd.itemId]?.averageCostScaled ? Math.round(balanceMap[itemToAdd.itemId].averageCostScaled / 100) : itemToAdd.costPrice || 0);

                    setDocLines([
                      ...docLines,
                      {
                        lineId: `line_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`,
                        itemId: itemToAdd.itemId,
                        itemName: itemToAdd.name,
                        itemSku: itemToAdd.sku,
                        unitName: itemToAdd.baseUnitId || "cái",
                        quantity: 1,
                        unitPrice: unitPrice,
                        lineNetMoney: unitPrice * 1,
                      },
                    ]);
                  }}
                  style={{
                    padding: "6px 12px",
                    background: "#0066FF",
                    color: "#fff",
                    border: "none",
                    borderRadius: "6px",
                    fontSize: "12px",
                    fontWeight: "600",
                    cursor: "pointer",
                    display: "flex",
                    alignItems: "center",
                    gap: "4px",
                  }}
                >
                  <Plus size={14} /> Thêm hàng
                </button>
              </div>

              {docLines.length === 0 ? (
                <div style={{ padding: "24px", textAlign: "center", background: "#F9FAFB", borderRadius: "8px", border: "1px dashed #D1D5DB", color: "#6B7280", fontSize: "13px" }}>
                  Chưa có mặt hàng nào. Bấm &quot;Thêm hàng&quot; để chọn hàng hóa cho phiếu.
                </div>
              ) : (
                <div style={{ maxHeight: "240px", overflowY: "auto", border: "1px solid #E5E7EB", borderRadius: "8px" }}>
                  <table style={{ width: "100%", borderCollapse: "collapse", fontSize: "13px" }}>
                    <thead>
                      <tr style={{ background: "#F9FAFB", borderBottom: "1px solid #E5E7EB" }}>
                        <th style={{ ...thStyle, padding: "8px" }}>Mặt hàng</th>
                        <th style={{ ...thStyle, padding: "8px" }}>ĐVT</th>
                        <th style={{ ...thStyle, padding: "8px", width: "90px" }}>Số lượng</th>
                        <th style={{ ...thStyle, padding: "8px", width: "120px" }}>
                          {docModalType === "PURCHASE_RECEIPT" ? "Giá nhập" : "Giá vốn"}
                        </th>
                        <th style={{ ...thStyle, padding: "8px", width: "120px", textAlign: "right" }}>Thành tiền</th>
                        <th style={{ ...thStyle, padding: "8px", width: "40px" }}></th>
                      </tr>
                    </thead>
                    <tbody>
                      {docLines.map((line, idx) => (
                        <tr key={line.lineId || idx} style={{ borderBottom: "1px solid #F3F4F6" }}>
                          <td style={{ padding: "6px 8px" }}>
                            <select
                              value={line.itemId}
                              onChange={(e) => {
                                const sel = catalogItems.find((ci) => ci.itemId === e.target.value);
                                if (!sel) return;
                                const uPrice =
                                  docModalType === "PURCHASE_RECEIPT"
                                    ? (sel.costPrice || 0)
                                    : (balanceMap[sel.itemId]?.averageCostScaled ? Math.round(balanceMap[sel.itemId].averageCostScaled / 100) : sel.costPrice || 0);

                                const next = [...docLines];
                                next[idx] = {
                                  ...line,
                                  itemId: sel.itemId,
                                  itemName: sel.name,
                                  itemSku: sel.sku,
                                  unitName: sel.baseUnitId || "cái",
                                  unitPrice: uPrice,
                                  lineNetMoney: uPrice * line.quantity,
                                };
                                setDocLines(next);
                              }}
                              style={{ width: "100%", padding: "6px 8px", borderRadius: "6px", border: "1px solid #D1D5DB", fontSize: "12px" }}
                            >
                              {catalogItems
                                .filter((ci) => ci.trackStock)
                                .map((ci) => (
                                  <option key={ci.itemId} value={ci.itemId}>
                                    {ci.name} ({ci.sku})
                                  </option>
                                ))}
                            </select>
                          </td>
                          <td style={{ padding: "6px 8px", color: "#6B7280" }}>{line.unitName}</td>
                          <td style={{ padding: "6px 8px" }}>
                            <input
                              type="number"
                              min="1"
                              value={line.quantity}
                              onChange={(e) => {
                                const q = Math.max(1, parseInt(e.target.value) || 1);
                                const next = [...docLines];
                                next[idx] = { ...line, quantity: q, lineNetMoney: q * line.unitPrice };
                                setDocLines(next);
                              }}
                              style={{ width: "100%", padding: "6px 8px", borderRadius: "6px", border: "1px solid #D1D5DB", fontSize: "12px", textAlign: "right" }}
                            />
                          </td>
                          <td style={{ padding: "6px 8px" }}>
                            <input
                              type="number"
                              min="0"
                              disabled={docModalType !== "PURCHASE_RECEIPT"}
                              value={line.unitPrice}
                              onChange={(e) => {
                                const p = Math.max(0, parseInt(e.target.value) || 0);
                                const next = [...docLines];
                                next[idx] = { ...line, unitPrice: p, lineNetMoney: line.quantity * p };
                                setDocLines(next);
                              }}
                              style={{ width: "100%", padding: "6px 8px", borderRadius: "6px", border: "1px solid #D1D5DB", fontSize: "12px", textAlign: "right", opacity: docModalType !== "PURCHASE_RECEIPT" ? 0.7 : 1 }}
                            />
                          </td>
                          <td style={{ padding: "6px 8px", textAlign: "right", fontWeight: "600", color: "#111827" }}>
                            {formatVND(line.lineNetMoney)}
                          </td>
                          <td style={{ padding: "6px 8px", textAlign: "center" }}>
                            <button
                              type="button"
                              onClick={() => setDocLines(docLines.filter((_, i) => i !== idx))}
                              style={{ background: "transparent", border: "none", color: "#EF4444", cursor: "pointer", padding: "2px" }}
                            >
                              <X size={16} />
                            </button>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </div>

            {/* Tổng cộng */}
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: "12px 16px", background: "#F3F4F6", borderRadius: "8px" }}>
              <div style={{ fontSize: "13px", color: "#4B5563" }}>
                Tổng số lượng: <strong style={{ color: "#111827" }}>{docLines.reduce((s, l) => s + l.quantity, 0)}</strong>
              </div>
              <div style={{ fontSize: "15px", fontWeight: "700", color: "#7E2930" }}>
                Tổng giá trị: {formatVND(docLines.reduce((s, l) => s + l.lineNetMoney, 0))}
              </div>
            </div>

            {/* Footer Buttons */}
            <div style={{ display: "flex", justifyContent: "flex-end", gap: "10px", marginTop: "12px" }}>
              <button
                type="button"
                onClick={() => setShowDocModal(false)}
                disabled={docSaving}
                style={btnSecondary}
              >
                Hủy bỏ
              </button>
              <button
                type="button"
                onClick={() => handleSaveDoc(false)}
                disabled={docSaving}
                style={{ ...btnSecondary, background: "#FEF3C7", borderColor: "#F59E0B", color: "#B45309" }}
              >
                {docSaving ? "Đang lưu..." : "Lưu tạm (DRAFT)"}
              </button>
              {canCompleteDoc && (
                <button
                  type="button"
                  onClick={() => handleSaveDoc(true)}
                  disabled={docSaving}
                  style={btnPrimary}
                >
                  {docSaving ? "Đang xử lý..." : "Hoàn thành & Cập nhật kho"}
                </button>
              )}
            </div>
          </div>
        </Modal>
      )}

      {/* ==================== MODAL XEM CHI TIẾT PHIẾU KHO ==================== */}
      {viewingDoc && (
        <Modal
          title={`📄 Chi tiết phiếu: ${viewingDoc.documentCode}`}
          onClose={() => setViewingDoc(null)}
        >
          <div style={{ display: "flex", flexDirection: "column", gap: "16px" }}>
            {/* Header thông tin phiếu */}
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "10px", padding: "14px", background: "#F9FAFB", borderRadius: "10px", fontSize: "13px" }}>
              <div>
                <span style={{ color: "#6B7280" }}>Loại phiếu: </span>
                <span style={badgeStyle("#3B82F6")}>{docTypeLabels[viewingDoc.docType] || viewingDoc.docType}</span>
              </div>
              <div>
                <span style={{ color: "#6B7280" }}>Trạng thái: </span>
                <span style={badgeStyle(statusColors[viewingDoc.status] || "#999")}>
                  {statusLabels[viewingDoc.status] || viewingDoc.status}
                </span>
              </div>
              <div>
                <span style={{ color: "#6B7280" }}>Chi nhánh: </span>
                <strong>{viewingDoc.branchId}</strong>
              </div>
              <div>
                <span style={{ color: "#6B7280" }}>Ngày tạo: </span>
                <strong>{formatDate(viewingDoc.createdAt)}</strong>
              </div>
              <div>
                <span style={{ color: "#6B7280" }}>Người tạo: </span>
                <strong>{viewingDoc.createdByName || viewingDoc.createdBy || "—"}</strong>
              </div>
              {viewingDoc.completedAt && (
                <div>
                  <span style={{ color: "#6B7280" }}>Người duyệt: </span>
                  <strong>{viewingDoc.completedByName || viewingDoc.completedBy || "—"}</strong> ({formatDate(viewingDoc.completedAt)})
                </div>
              )}
              {viewingDoc.supplierName && (
                <div>
                  <span style={{ color: "#6B7280" }}>Nhà cung cấp: </span>
                  <strong>{viewingDoc.supplierName}</strong>
                </div>
              )}
              {viewingDoc.reason && (
                <div>
                  <span style={{ color: "#6B7280" }}>Lý do: </span>
                  <strong>{viewingDoc.reason}</strong>
                </div>
              )}
              {viewingDoc.note && (
                <div style={{ gridColumn: "span 2" }}>
                  <span style={{ color: "#6B7280" }}>Ghi chú: </span>
                  <span>{viewingDoc.note}</span>
                </div>
              )}
            </div>

            {/* Bảng chi tiết mặt hàng */}
            <div>
              <h4 style={{ fontSize: "14px", fontWeight: "700", marginBottom: "8px", color: "#1F2937" }}>
                Danh sách mặt hàng ({viewingDoc.lines?.length || 0})
              </h4>
              <div style={{ border: "1px solid #E5E7EB", borderRadius: "8px", overflow: "hidden" }}>
                <table style={{ width: "100%", borderCollapse: "collapse", fontSize: "13px" }}>
                  <thead>
                    <tr style={{ background: "#F9FAFB" }}>
                      <th style={thStyle}>Mã SKU</th>
                      <th style={thStyle}>Tên hàng hóa</th>
                      <th style={thStyle}>ĐVT</th>
                      <th style={{ ...thStyle, textAlign: "right" }}>Số lượng</th>
                      <th style={{ ...thStyle, textAlign: "right" }}>Đơn giá</th>
                      <th style={{ ...thStyle, textAlign: "right" }}>Thành tiền</th>
                    </tr>
                  </thead>
                  <tbody>
                    {(viewingDoc.lines || []).map((l, i) => (
                      <tr key={l.lineId || i} style={{ borderBottom: "1px solid #F3F4F6" }}>
                        <td style={tdStyle}>{l.itemSku || "—"}</td>
                        <td style={{ ...tdStyle, fontWeight: "600" }}>{l.itemName}</td>
                        <td style={tdStyle}>{l.unitName || "—"}</td>
                        <td style={{ ...tdStyle, textAlign: "right" }}>{l.quantity}</td>
                        <td style={{ ...tdStyle, textAlign: "right" }}>{formatVND(l.unitPrice)}</td>
                        <td style={{ ...tdStyle, textAlign: "right", fontWeight: "600" }}>{formatVND(l.lineNetMoney)}</td>
                      </tr>
                    ))}
                    <tr style={{ background: "#F9FAFB", fontWeight: "700" }}>
                      <td colSpan={3} style={{ ...tdStyle, textAlign: "right" }}>Tổng cộng:</td>
                      <td style={{ ...tdStyle, textAlign: "right", color: "#111827" }}>{viewingDoc.totalQuantity}</td>
                      <td></td>
                      <td style={{ ...tdStyle, textAlign: "right", color: "#7E2930", fontSize: "14px" }}>
                        {formatVND(viewingDoc.totalNetMoney || viewingDoc.totalMoney)}
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>

            {/* Footer Buttons */}
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginTop: "8px" }}>
              <div>
                {viewingDoc.status === "DRAFT" && (
                  <button
                    type="button"
                    onClick={() => handleCancelDraftDoc(viewingDoc)}
                    disabled={actionInProgress}
                    style={{ ...btnSecondary, color: "#EF4444", borderColor: "#FCA5A5" }}
                  >
                    Hủy phiếu
                  </button>
                )}
              </div>
              <div style={{ display: "flex", gap: "8px" }}>
                <button
                  type="button"
                  onClick={() => setViewingDoc(null)}
                  style={btnSecondary}
                >
                  Đóng
                </button>
                {viewingDoc.status === "DRAFT" && canCompleteDoc && (
                  <button
                    type="button"
                    onClick={() => handleCompleteDraftDoc(viewingDoc)}
                    disabled={actionInProgress}
                    style={{ ...btnPrimary, background: "#10B981" }}
                  >
                    {actionInProgress ? "Đang xử lý..." : "Duyệt & Hoàn thành phiếu"}
                  </button>
                )}
              </div>
            </div>
          </div>
        </Modal>
      )}

      {/* ==================== MODAL THÊM HÀNG HÓA TỪ FILE EXCEL (KHỚP 100% ẢNH MẪU) ==================== */}
      {showImportModal && (
        <div
          style={{
            position: "fixed",
            inset: 0,
            background: "rgba(0,0,0,0.5)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            zIndex: 1000,
          }}
          onClick={() => setShowImportModal(false)}
        >
          <div
            style={{
              background: "#FFFFFF",
              borderRadius: "16px",
              padding: "24px 28px",
              width: "580px",
              maxWidth: "95vw",
              maxHeight: "90vh",
              overflow: "auto",
              boxShadow: "0 20px 60px rgba(0,0,0,0.25)",
            }}
            onClick={(e) => e.stopPropagation()}
          >
            {/* Header */}
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "16px" }}>
              <h2 style={{ fontSize: "19px", fontWeight: "700", color: "#111827", margin: 0 }}>
                {importStep === 1 ? "Thêm hàng hóa từ file Excel" : "Tải lên file dữ liệu hàng hóa"}
              </h2>
              <button
                onClick={() => setShowImportModal(false)}
                style={{ background: "transparent", border: "none", cursor: "pointer", color: "#6B7280", padding: "4px" }}
              >
                <X size={20} />
              </button>
            </div>

            {/* STEP 1: CÁCH XỬ LÝ THÔNG TIN (GIAO DIỆN CHÍNH XÁC NHƯ HÌNH) */}
            {importStep === 1 && (
              <div>
                <div style={{ fontSize: "14px", fontWeight: "700", color: "#1F2937", marginBottom: "16px" }}>
                  Cách xử lý thông tin
                </div>

                {/* 1. Cập nhật giá trị tồn kho */}
                <div style={{ marginBottom: "16px" }}>
                  <div style={{ fontSize: "14px", fontWeight: "500", color: "#111827", marginBottom: "8px" }}>
                    Cập nhật giá trị tồn kho?
                  </div>
                  <div style={{ display: "flex", flexDirection: "column", gap: "10px", paddingLeft: "2px" }}>
                    <label style={{ display: "flex", alignItems: "center", gap: "10px", fontSize: "14px", color: "#374151", cursor: "pointer" }}>
                      <input
                        type="radio"
                        name="updateStock"
                        checked={updateStockBalanceOption === "no"}
                        onChange={() => setUpdateStockBalanceOption("no")}
                        style={{ width: "16px", height: "16px", accentColor: "#0066FF", cursor: "pointer" }}
                      />
                      Không
                    </label>
                    <label style={{ display: "flex", alignItems: "center", gap: "10px", fontSize: "14px", color: "#374151", cursor: "pointer" }}>
                      <input
                        type="radio"
                        name="updateStock"
                        checked={updateStockBalanceOption === "yes"}
                        onChange={() => setUpdateStockBalanceOption("yes")}
                        style={{ width: "16px", height: "16px", accentColor: "#0066FF", cursor: "pointer" }}
                      />
                      Có
                    </label>
                  </div>
                </div>

                {/* 2. Xử lý trùng mã hàng, khác tên hàng */}
                <div style={{ marginBottom: "16px" }}>
                  <div style={{ fontSize: "14px", fontWeight: "500", color: "#111827", marginBottom: "8px" }}>
                    Xử lý trùng mã hàng, khác tên hàng?
                  </div>
                  <div style={{ display: "flex", flexDirection: "column", gap: "10px", paddingLeft: "2px" }}>
                    <label style={{ display: "flex", alignItems: "center", gap: "10px", fontSize: "14px", color: "#374151", cursor: "pointer" }}>
                      <input
                        type="radio"
                        name="duplicateSku"
                        checked={duplicateSkuOption === "error"}
                        onChange={() => setDuplicateSkuOption("error")}
                        style={{ width: "16px", height: "16px", accentColor: "#0066FF", cursor: "pointer" }}
                      />
                      Báo lỗi và dừng import
                    </label>
                    <label style={{ display: "flex", alignItems: "center", gap: "10px", fontSize: "14px", color: "#374151", cursor: "pointer" }}>
                      <input
                        type="radio"
                        name="duplicateSku"
                        checked={duplicateSkuOption === "replace"}
                        onChange={() => setDuplicateSkuOption("replace")}
                        style={{ width: "16px", height: "16px", accentColor: "#0066FF", cursor: "pointer" }}
                      />
                      Thay thế tên hàng cũ bằng tên hàng mới
                    </label>
                  </div>
                </div>

                {/* 3. Phạm vi áp dụng trạng thái kinh doanh */}
                <div style={{ marginBottom: "18px" }}>
                  <div style={{ fontSize: "14px", fontWeight: "500", color: "#111827", marginBottom: "8px" }}>
                    Phạm vi áp dụng trạng thái kinh doanh
                  </div>
                  <div style={{ display: "flex", flexDirection: "column", gap: "10px", paddingLeft: "2px" }}>
                    <label style={{ display: "flex", alignItems: "center", gap: "10px", fontSize: "14px", color: "#374151", cursor: "pointer" }}>
                      <input
                        type="radio"
                        name="scope"
                        checked={scopeOption === "all"}
                        onChange={() => setScopeOption("all")}
                        style={{ width: "16px", height: "16px", accentColor: "#0066FF", cursor: "pointer" }}
                      />
                      Toàn hệ thống
                    </label>
                    <label style={{ display: "flex", alignItems: "center", gap: "10px", fontSize: "14px", color: "#374151", cursor: "pointer" }}>
                      <input
                        type="radio"
                        name="scope"
                        checked={scopeOption === "branch"}
                        onChange={() => setScopeOption("branch")}
                        style={{ width: "16px", height: "16px", accentColor: "#0066FF", cursor: "pointer" }}
                      />
                      Theo chi nhánh ({targetStoreCode})
                    </label>
                  </div>
                </div>

                {/* Khung Lưu ý */}
                <div
                  style={{
                    background: "#F8FAFC",
                    border: "1px solid #BFDBFE",
                    borderRadius: "12px",
                    padding: "14px 18px",
                    marginBottom: "24px",
                  }}
                >
                  <div style={{ fontSize: "13px", fontWeight: "700", color: "#1E293B", marginBottom: "8px" }}>
                    Lưu ý
                  </div>
                  <ul style={{ margin: 0, paddingLeft: "18px", fontSize: "13px", color: "#334155", lineHeight: 1.65 }}>
                    <li>Hệ thống cho phép nhập tối đa 5.000 mặt hàng mỗi lần từ file.</li>
                    <li>Mã hàng chứa kí tự đặc biệt (@, #, $, *, /, -, _, ...) và chữ có dấu sẽ gây khó khăn khi in và sử dụng mã vạch.</li>
                    <li>Với hình ảnh hàng hóa, hệ thống sẽ lưu trữ và hiển thị theo link hình ảnh được nhập trên file excel (không lưu trữ ảnh).</li>
                    <li>Hệ thống chỉ hỗ trợ import Nguyên vật liệu và Công cụ dụng cụ.</li>
                  </ul>
                </div>

                {/* Footer Modal Step 1 */}
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", paddingTop: "8px" }}>
                  <div style={{ fontSize: "13px", color: "#4B5563" }}>
                    Chưa có file mẫu?{" "}
                    <button
                      onClick={downloadSampleTemplate}
                      style={{
                        background: "transparent",
                        border: "none",
                        color: "#0066FF",
                        fontWeight: "600",
                        cursor: "pointer",
                        textDecoration: "none",
                        padding: 0,
                      }}
                    >
                      Tải ngay
                    </button>
                  </div>
                  <div style={{ display: "flex", gap: "10px" }}>
                    <button
                      onClick={() => setShowImportModal(false)}
                      style={{
                        padding: "8px 20px",
                        background: "transparent",
                        border: "none",
                        color: "#374151",
                        fontSize: "14px",
                        fontWeight: "600",
                        cursor: "pointer",
                      }}
                    >
                      Bỏ qua
                    </button>
                    <button
                      onClick={() => setImportStep(2)}
                      style={{
                        padding: "9px 24px",
                        background: "#0066FF",
                        border: "none",
                        borderRadius: "24px",
                        color: "#FFFFFF",
                        fontSize: "14px",
                        fontWeight: "600",
                        cursor: "pointer",
                        boxShadow: "0 2px 6px rgba(0, 102, 255, 0.3)",
                      }}
                    >
                      Tiếp tục
                    </button>
                  </div>
                </div>
              </div>
            )}

            {/* STEP 2: TẢI FILE VÀ XEM TRƯỚC HÀNG HÓA */}
            {importStep === 2 && (
              <div>
                <button
                  onClick={() => setImportStep(1)}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: "6px",
                    background: "transparent",
                    border: "none",
                    color: "#0066FF",
                    fontSize: "13px",
                    fontWeight: "600",
                    cursor: "pointer",
                    padding: 0,
                    marginBottom: "14px",
                  }}
                >
                  <ArrowLeft size={16} /> Quay lại thiết lập
                </button>

                {/* Dropzone */}
                <div
                  onClick={() => fileInputRef.current?.click()}
                  style={{
                    border: "2px dashed #93C5FD",
                    background: "#F8FAFC",
                    borderRadius: "12px",
                    padding: "24px",
                    textAlign: "center",
                    cursor: "pointer",
                    marginBottom: "16px",
                  }}
                >
                  <FileSpreadsheet size={40} color="#0066FF" style={{ margin: "0 auto 10px" }} />
                  <div style={{ fontSize: "14px", fontWeight: "600", color: "#1E293B" }}>
                    {importedFile ? importedFile.name : "Kéo thả hoặc bấm để chọn file Excel / CSV"}
                  </div>
                  <div style={{ fontSize: "12px", color: "#64748B", marginTop: "4px" }}>
                    Hỗ trợ định dạng .xlsx, .xls, .csv theo mẫu KiotViet / Trạm
                  </div>
                  <input
                    type="file"
                    ref={fileInputRef}
                    accept=".xlsx,.xls,.csv"
                    style={{ display: "none" }}
                    onChange={handleFileUpload}
                  />
                </div>

                {/* Summary bar if rows parsed */}
                {parsedRows.length > 0 && (
                  <div style={{ marginBottom: "12px" }}>
                    <div style={{ display: "flex", gap: "10px", alignItems: "center", marginBottom: "8px" }}>
                      <span style={{ fontSize: "13px", fontWeight: "600", color: "#333" }}>
                        Tổng số: {parsedRows.length} mặt hàng
                      </span>
                      <span style={{ fontSize: "12px", background: "#DCFCE7", color: "#15803D", padding: "2px 8px", borderRadius: "12px", fontWeight: "600" }}>
                        ✓ {parsedRows.filter((r) => r.isValid).length} hợp lệ
                      </span>
                      {parsedRows.filter((r) => !r.isValid).length > 0 && (
                        <span style={{ fontSize: "12px", background: "#FEE2E2", color: "#B91C1C", padding: "2px 8px", borderRadius: "12px", fontWeight: "600" }}>
                          ⚠ {parsedRows.filter((r) => !r.isValid).length} lỗi
                        </span>
                      )}
                    </div>

                    {/* Preview Table */}
                    <div style={{ border: "1px solid #E5E7EB", borderRadius: "8px", maxHeight: "240px", overflow: "auto" }}>
                      <table style={{ width: "100%", borderCollapse: "collapse", fontSize: "12px" }}>
                        <thead>
                          <tr style={{ background: "#F1F5F9", color: "#475569", borderBottom: "1px solid #CBD5E1" }}>
                            <th style={{ padding: "8px", textAlign: "left" }}>Mã</th>
                            <th style={{ padding: "8px", textAlign: "left" }}>Tên hàng</th>
                            <th style={{ padding: "8px", textAlign: "left" }}>Loại</th>
                            <th style={{ padding: "8px", textAlign: "right" }}>Giá vốn</th>
                            <th style={{ padding: "8px", textAlign: "right" }}>Tồn</th>
                            <th style={{ padding: "8px", textAlign: "left" }}>Trạng thái</th>
                          </tr>
                        </thead>
                        <tbody>
                          {parsedRows.map((r, idx) => (
                            <tr key={idx} style={{ borderBottom: "1px solid #F1F5F9", background: r.isValid ? "#FFF" : "#FFF5F5" }}>
                              <td style={{ padding: "6px 8px", fontFamily: "monospace", fontWeight: "600" }}>{r.sku}</td>
                              <td style={{ padding: "6px 8px", fontWeight: "500" }}>{r.name}</td>
                              <td style={{ padding: "6px 8px" }}>{r.kind === "TOOL" ? "Công cụ" : "NVL"}</td>
                              <td style={{ padding: "6px 8px", textAlign: "right" }}>{formatVND(r.costPrice)}</td>
                              <td style={{ padding: "6px 8px", textAlign: "right" }}>{r.onHandQty} {r.unit}</td>
                              <td style={{ padding: "6px 8px" }}>
                                <span
                                  style={{
                                    fontSize: "11px",
                                    color: r.isValid ? "#15803D" : "#B91C1C",
                                    fontWeight: "600",
                                  }}
                                >
                                  {r.statusMessage}
                                </span>
                              </td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  </div>
                )}

                {importSuccessMsg && (
                  <div style={{ padding: "10px", background: "#DCFCE7", color: "#15803D", borderRadius: "8px", fontSize: "13px", fontWeight: "600", marginBottom: "12px" }}>
                    ✓ {importSuccessMsg}
                  </div>
                )}

                {/* Footer Modal Step 2 */}
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", paddingTop: "12px" }}>
                  <div style={{ fontSize: "13px", color: "#4B5563" }}>
                    Chưa có file mẫu?{" "}
                    <button
                      onClick={downloadSampleTemplate}
                      style={{
                        background: "transparent",
                        border: "none",
                        color: "#0066FF",
                        fontWeight: "600",
                        cursor: "pointer",
                        padding: 0,
                      }}
                    >
                      Tải ngay
                    </button>
                  </div>
                  <div style={{ display: "flex", gap: "10px" }}>
                    <button
                      onClick={() => setShowImportModal(false)}
                      style={{
                        padding: "8px 20px",
                        background: "transparent",
                        border: "none",
                        color: "#374151",
                        fontSize: "14px",
                        fontWeight: "600",
                        cursor: "pointer",
                      }}
                    >
                      Bỏ qua
                    </button>
                    <button
                      onClick={executeImport}
                      disabled={isImporting || parsedRows.filter((r) => r.isValid).length === 0}
                      style={{
                        padding: "9px 24px",
                        background: isImporting || parsedRows.filter((r) => r.isValid).length === 0 ? "#9CA3AF" : "#0066FF",
                        border: "none",
                        borderRadius: "24px",
                        color: "#FFFFFF",
                        fontSize: "14px",
                        fontWeight: "600",
                        cursor: isImporting || parsedRows.filter((r) => r.isValid).length === 0 ? "not-allowed" : "pointer",
                        boxShadow: "0 2px 6px rgba(0, 102, 255, 0.3)",
                      }}
                    >
                      {isImporting
                        ? "Đang nhập..."
                        : `Tiếp tục nhập (${parsedRows.filter((r) => r.isValid).length} món)`}
                    </button>
                  </div>
                </div>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

// ==================== SUB-COMPONENTS ====================

function CatalogTable({
  items,
  balanceMap,
  onEdit,
}: {
  items: CatalogItem[];
  balanceMap: Record<string, StockBalanceItem>;
  onEdit: (i: CatalogItem) => void;
}) {
  if (items.length === 0)
    return (
      <EmptyState
        icon="📦"
        text="Chưa có hàng hóa nào"
        sub="Bấm 'Thêm hàng' hoặc 'Nhập Excel' để tải dữ liệu nguyên vật liệu và công cụ dụng cụ."
      />
    );
  return (
    <div style={{ borderRadius: "12px", border: "1px solid #e5e7eb", overflow: "hidden" }}>
      <table style={{ width: "100%", borderCollapse: "collapse" }}>
        <thead>
          <tr style={{ background: "#f9fafb" }}>
            {["Mã", "Tên hàng", "Nhóm hàng", "Loại", "ĐVT", "Giá vốn", "Tồn kho", "Trạng thái", ""].map((h) => (
              <th key={h} style={thStyle}>
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {items.map((item) => {
            const bal = balanceMap[item.itemId];
            const qty = bal?.onHandQty || 0;
            const belowMin = item.trackStock && item.minStock > 0 && qty < item.minStock;
            return (
              <tr
                key={item.itemId}
                style={{ borderBottom: "1px solid #f0f0f0", cursor: "pointer" }}
                onClick={() => onEdit(item)}
                onMouseEnter={(e) => (e.currentTarget.style.background = "#fafafa")}
                onMouseLeave={(e) => (e.currentTarget.style.background = "transparent")}
              >
                <td style={tdStyle}>
                  <span style={{ fontFamily: "monospace", fontSize: "12px", color: "#7E2930", fontWeight: "600" }}>
                    {item.sku}
                  </span>
                </td>
                <td style={{ ...tdStyle, fontWeight: "600" }}>{item.name}</td>
                <td style={tdStyle}>
                  <span style={{ fontSize: "12px", color: "#666" }}>{item.managementGroup || "—"}</span>
                </td>
                <td style={tdStyle}>
                  <span style={badgeStyle(item.kind === "RAW_MATERIAL" ? "#3b82f6" : "#8b5cf6")}>
                    {kindLabels[item.kind] || item.kind}
                  </span>
                </td>
                <td style={tdStyle}>{item.baseUnitId}</td>
                <td style={{ ...tdStyle, textAlign: "right" }}>
                  {item.costPrice > 0 ? formatVND(item.costPrice) : "—"}
                </td>
                <td style={{ ...tdStyle, textAlign: "right" }}>
                  {item.trackStock ? (
                    <span style={{ color: belowMin ? "#ef4444" : "#111", fontWeight: belowMin ? "700" : "400" }}>
                      {belowMin && <AlertTriangle size={13} style={{ marginRight: "4px", verticalAlign: "middle" }} />}
                      {qty} {item.baseUnitId}
                    </span>
                  ) : (
                    <span style={{ color: "#999" }}>Không theo dõi</span>
                  )}
                </td>
                <td style={tdStyle}>
                  <span style={badgeStyle(statusColors[item.status] || "#999")}>
                    {statusLabels[item.status] || item.status}
                  </span>
                </td>
                <td style={tdStyle}>
                  <ChevronRight size={16} color="#ccc" />
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

function StockTable({ items, balanceMap }: { items: CatalogItem[]; balanceMap: Record<string, StockBalanceItem> }) {
  if (items.length === 0)
    return (
      <EmptyState
        icon="📊"
        text="Chưa có hàng theo dõi tồn kho"
        sub="Tạo hàng hóa và bật 'Quản lý tồn kho' để xem tại đây."
      />
    );
  return (
    <div style={{ borderRadius: "12px", border: "1px solid #e5e7eb", overflow: "hidden" }}>
      <table style={{ width: "100%", borderCollapse: "collapse" }}>
        <thead>
          <tr style={{ background: "#f9fafb" }}>
            {["Mã", "Tên hàng", "ĐVT", "Tồn kho", "Đang giữ", "Có thể bán", "Giá vốn TB", "Giá trị tồn"].map((h) => (
              <th key={h} style={thStyle}>
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {items.map((item) => {
            const bal = balanceMap[item.itemId];
            const onHand = bal?.onHandQty || 0;
            const reserved = bal?.reservedQty || 0;
            const available = onHand - reserved;
            const belowMin = item.minStock > 0 && onHand < item.minStock;
            return (
              <tr key={item.itemId} style={{ borderBottom: "1px solid #f0f0f0" }}>
                <td style={tdStyle}>
                  <span style={{ fontFamily: "monospace", fontSize: "12px", color: "#7E2930" }}>{item.sku}</span>
                </td>
                <td style={{ ...tdStyle, fontWeight: "600" }}>{item.name}</td>
                <td style={tdStyle}>{item.baseUnitId}</td>
                <td
                  style={{
                    ...tdStyle,
                    textAlign: "right",
                    color: belowMin ? "#ef4444" : "#111",
                    fontWeight: belowMin ? "700" : "400",
                  }}
                >
                  {belowMin && "⚠️ "}
                  {onHand}
                </td>
                <td style={{ ...tdStyle, textAlign: "right", color: reserved > 0 ? "#f59e0b" : "#999" }}>{reserved}</td>
                <td style={{ ...tdStyle, textAlign: "right", fontWeight: "600" }}>{available}</td>
                <td style={{ ...tdStyle, textAlign: "right" }}>
                  {bal?.averageCostScaled ? formatVND(bal.averageCostScaled / 100) : "—"}
                </td>
                <td style={{ ...tdStyle, textAlign: "right", fontWeight: "600" }}>
                  {bal?.inventoryValue ? formatVND(bal.inventoryValue) : "—"}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

function DocumentsTable({
  docs,
  onSelectDoc,
}: {
  docs: InventoryDocItem[];
  onSelectDoc?: (doc: InventoryDocItem) => void;
}) {
  if (docs.length === 0)
    return <EmptyState icon="📋" text="Chưa có phiếu kho nào" sub="Bấm nút Nhập kho / Xuất kho / Huỷ kho phía trên để tạo phiếu." />;
  return (
    <div style={{ borderRadius: "12px", border: "1px solid #e5e7eb", overflow: "hidden" }}>
      <table style={{ width: "100%", borderCollapse: "collapse" }}>
        <thead>
          <tr style={{ background: "#f9fafb" }}>
            {["Mã phiếu", "Loại", "NCC / Lý do", "Tổng SL", "Tổng tiền", "Trạng thái", "Người tạo", "Ngày tạo", ""].map((h) => (
              <th key={h} style={thStyle}>
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {docs.map((doc) => (
            <tr
              key={doc.documentId}
              style={{ borderBottom: "1px solid #f0f0f0", cursor: "pointer" }}
              onClick={() => onSelectDoc?.(doc)}
              onMouseEnter={(e) => (e.currentTarget.style.background = "#fafafa")}
              onMouseLeave={(e) => (e.currentTarget.style.background = "transparent")}
            >
              <td style={tdStyle}>
                <span style={{ fontFamily: "monospace", fontSize: "12px", fontWeight: "700", color: "#7E2930" }}>
                  {doc.documentCode || doc.documentId.slice(0, 12)}
                </span>
              </td>
              <td style={tdStyle}>
                <span style={badgeStyle(doc.docType === "PURCHASE_RECEIPT" ? "#3b82f6" : doc.docType === "INTERNAL_USE" ? "#0284c7" : "#ef4444")}>
                  {docTypeLabels[doc.docType] || doc.docType}
                </span>
              </td>
              <td style={tdStyle}>{doc.supplierName || doc.reason || "—"}</td>
              <td style={{ ...tdStyle, textAlign: "right", fontWeight: "600" }}>{doc.totalQuantity}</td>
              <td style={{ ...tdStyle, textAlign: "right", fontWeight: "700" }}>
                {formatVND(doc.totalNetMoney || doc.totalMoney)}
              </td>
              <td style={tdStyle}>
                <span style={badgeStyle(statusColors[doc.status] || "#999")}>
                  {statusLabels[doc.status] || doc.status}
                </span>
              </td>
              <td style={tdStyle}>{doc.createdByName || doc.createdBy || "—"}</td>
              <td style={tdStyle}>{formatDate(doc.createdAt)}</td>
              <td style={tdStyle}>
                <ChevronRight size={16} color="#ccc" />
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function SuppliersTable({
  suppliers,
  onEdit,
}: {
  suppliers: SupplierItem[];
  onEdit: (s: SupplierItem) => void;
}) {
  if (suppliers.length === 0)
    return <EmptyState icon="🏪" text="Chưa có nhà cung cấp" sub="Bấm 'Thêm NCC' để thêm nhà cung cấp đầu tiên." />;
  return (
    <div style={{ borderRadius: "12px", border: "1px solid #e5e7eb", overflow: "hidden" }}>
      <table style={{ width: "100%", borderCollapse: "collapse" }}>
        <thead>
          <tr style={{ background: "#f9fafb" }}>
            {["Mã NCC", "Tên nhà cung cấp", "SĐT", "Email", "MST", "Địa chỉ", "Trạng thái", ""].map((h) => (
              <th key={h} style={thStyle}>
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {suppliers.map((sup) => (
            <tr
              key={sup.supplierId}
              style={{ borderBottom: "1px solid #f0f0f0", cursor: "pointer" }}
              onClick={() => onEdit(sup)}
              onMouseEnter={(e) => (e.currentTarget.style.background = "#fafafa")}
              onMouseLeave={(e) => (e.currentTarget.style.background = "transparent")}
            >
              <td style={tdStyle}>
                <span style={{ fontFamily: "monospace", fontSize: "12px", color: "#7E2930", fontWeight: "600" }}>
                  {sup.supplierCode}
                </span>
              </td>
              <td style={{ ...tdStyle, fontWeight: "600" }}>{sup.name}</td>
              <td style={tdStyle}>{sup.phone || "—"}</td>
              <td style={tdStyle}>{sup.email || "—"}</td>
              <td style={tdStyle}>{sup.taxId || "—"}</td>
              <td style={{ ...tdStyle, maxWidth: "200px", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                {sup.address || "—"}
              </td>
              <td style={tdStyle}>
                <span style={badgeStyle(statusColors[sup.status] || "#10b981")}>
                  {statusLabels[sup.status] || sup.status}
                </span>
              </td>
              <td style={tdStyle}>
                <ChevronRight size={16} color="#ccc" />
              </td>
            </tr>
          ))}
        </tbody>
      </table>
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
    <div
      style={{
        position: "fixed",
        inset: 0,
        background: "rgba(0,0,0,0.5)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        zIndex: 100,
      }}
      onClick={onClose}
    >
      <div
        style={{
          background: "#fff",
          borderRadius: "16px",
          padding: "24px",
          minWidth: "500px",
          maxWidth: "650px",
          maxHeight: "80vh",
          overflow: "auto",
          boxShadow: "0 20px 60px rgba(0,0,0,0.3)",
        }}
        onClick={(e) => e.stopPropagation()}
      >
        <h3 style={{ fontSize: "18px", fontWeight: "700", marginBottom: "16px", color: "#1a1a2e" }}>{title}</h3>
        {children}
      </div>
    </div>
  );
}

function FormField({
  label,
  value,
  onChange,
  type = "text",
  placeholder = "",
  disabled = false,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  type?: string;
  placeholder?: string;
  disabled?: boolean;
}) {
  return (
    <div>
      <label style={labelStyle}>{label}</label>
      <input
        type={type}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        disabled={disabled}
        style={{ ...inputStyle, opacity: disabled ? 0.6 : 1 }}
      />
    </div>
  );
}

// Styles
const btnPrimary: React.CSSProperties = {
  display: "flex",
  alignItems: "center",
  gap: "6px",
  padding: "9px 16px",
  background: "#7E2930",
  color: "#fff",
  border: "none",
  borderRadius: "10px",
  fontSize: "13px",
  fontWeight: "700",
  cursor: "pointer",
};

const btnSecondary: React.CSSProperties = {
  display: "flex",
  alignItems: "center",
  gap: "6px",
  padding: "9px 16px",
  background: "#f5f5f5",
  color: "#333",
  border: "1px solid #ddd",
  borderRadius: "10px",
  fontSize: "13px",
  fontWeight: "600",
  cursor: "pointer",
};

const thStyle: React.CSSProperties = {
  padding: "12px 14px",
  textAlign: "left",
  fontSize: "12px",
  fontWeight: "700",
  color: "#666",
  textTransform: "uppercase",
  letterSpacing: "0.03em",
};

const tdStyle: React.CSSProperties = {
  padding: "12px 14px",
  fontSize: "13px",
  color: "#333",
};

const labelStyle: React.CSSProperties = {
  display: "block",
  fontSize: "12px",
  fontWeight: "600",
  color: "#555",
  marginBottom: "4px",
};

const inputStyle: React.CSSProperties = {
  width: "100%",
  padding: "8px 12px",
  borderRadius: "8px",
  border: "1px solid #ddd",
  fontSize: "14px",
};

const badgeStyle = (color: string): React.CSSProperties => ({
  display: "inline-block",
  padding: "2px 8px",
  borderRadius: "6px",
  fontSize: "11px",
  fontWeight: "700",
  background: `${color}15`,
  color: color,
  whiteSpace: "nowrap",
});
