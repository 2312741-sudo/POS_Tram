"use client";
import { useEffect, useState, useMemo } from "react";
import { db } from "@/lib/firebase";
import { ref, onValue, update, remove, set } from "firebase/database";
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
  AlertTriangle,
  CreditCard,
  Banknote,
  QrCode,
  Bookmark,
  Calendar,
  Phone,
  DollarSign,
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
  selectedToppings?: any[];
  note?: string;
  imageBase64?: string;
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
  actionLogsJson?: string | null;
  isReserved?: boolean;
  reservationCustomer?: string;
  reservationPhone?: string;
  reservationTime?: string;
  reservationDeposit?: number;
  [key: string]: any;
}

interface TableFormData {
  name: string;
  zone: string;
}

const emptyForm: TableFormData = {
  name: "",
  zone: "",
};

import { useDashboardData } from "@/lib/data-context";

export default function TablesPage() {
  const {
    tables,
    loading: ctxLoading,
    currentStoreCode,
    currentStore,
    stores,
    checkoutAndFreeTable,
    saveTable,
    deleteTable,
  } = useDashboardData();
  const loading = ctxLoading && tables.length === 0;
  const [selectedZone, setSelectedZone] = useState<string>("ALL");
  const [statusFilter, setStatusFilter] = useState<"ALL" | "IN_USE" | "EMPTY" | "RESERVED">("ALL");
  const [viewMode, setViewMode] = useState<"grid" | "list">("grid");
  const [search, setSearch] = useState("");
  
  const zones = useMemo(() => {
    const unique = Array.from(new Set(tables.map((t) => t.zone).filter(Boolean))) as string[];
    unique.sort();
    return unique;
  }, [tables]);
  
  // Modals
  const [showModal, setShowModal] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [form, setForm] = useState<TableFormData>(emptyForm);
  const [saving, setSaving] = useState(false);
  const [deleteId, setDeleteId] = useState<string | null>(null);
  const [error, setError] = useState("");

  // Order Details Modal & Payment
  const [selectedTableForOrder, setSelectedTableForOrder] = useState<Table | null>(null);
  const [completingPayment, setCompletingPayment] = useState(false);
  const [paymentMethod, setPaymentMethod] = useState<"CASH" | "TRANSFER">("CASH");
  const [checkoutToast, setCheckoutToast] = useState<string | null>(null);

  // Update selectedTableForOrder if tables change
  useEffect(() => {
    if (selectedTableForOrder) {
      const updated = tables.find((t) => t.id === selectedTableForOrder.id || t.name === selectedTableForOrder.name);
      if (updated && updated.inUse) {
        setSelectedTableForOrder(updated);
      } else if (updated && !updated.inUse) {
        setSelectedTableForOrder(null);
      }
    }
  }, [tables]);

  const filtered = useMemo(() => {
    return tables.filter((t) => {
      const matchZone = selectedZone === "ALL" || t.zone === selectedZone;
      const matchSearch =
        !search ||
        t.name.toLowerCase().includes(search.toLowerCase()) ||
        (t.zone && t.zone.toLowerCase().includes(search.toLowerCase()));
      let matchStatus = true;
      if (statusFilter === "IN_USE") matchStatus = t.inUse;
      else if (statusFilter === "EMPTY") matchStatus = !t.inUse && !t.isReserved;
      else if (statusFilter === "RESERVED") matchStatus = !!t.isReserved;
      return matchZone && matchSearch && matchStatus;
    });
  }, [tables, selectedZone, search, statusFilter]);

  // Statistics
  const inUseCount = useMemo(() => tables.filter((t) => t.inUse).length, [tables]);
  const reservedCount = useMemo(() => tables.filter((t) => t.isReserved).length, [tables]);
  const emptyCount = useMemo(() => tables.filter((t) => !t.inUse && !t.isReserved).length, [tables]);
  const totalGuests = useMemo(
    () =>
      tables
        .filter((t) => t.inUse)
        .reduce((sum, t) => sum + (t.guestCount && t.guestCount > 0 ? t.guestCount : 1), 0),
    [tables]
  );

  const parseOrderItems = (json?: string): OrderItem[] => {
    if (!json || json.trim() === "" || json === "[]") return [];
    try {
      const parsed = JSON.parse(json);
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  };

  const calculateTableTotal = (items: OrderItem[]): number => {
    return items.reduce((sum, it) => {
      const qty = it.quantity || it.count || 1;
      let toppingSum = 0;
      if (Array.isArray(it.selectedToppings)) {
        toppingSum = it.selectedToppings.reduce((ts, tp) => ts + (tp.price || 0), 0);
      }
      return sum + (it.price + toppingSum) * qty;
    }, 0);
  };

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
    } catch (e: any) {
      setError(e.message || "Lỗi lưu dữ liệu");
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
    } catch (e: any) {
      alert("Lỗi xóa bàn: " + e.message);
    }
  };

  const handleCheckoutAndFreeTable = async (t: Table) => {
    const items = parseOrderItems(t.currentOrderJson);
    const total = calculateTableTotal(items);
    const methodText = paymentMethod === "CASH" ? "Tiền mặt" : "Chuyển khoản VietQR";

    if (!confirm(`Xác nhận hoàn tất thanh toán (${methodText}) và trả ${t.name} (Tổng tiền: ${formatVND(total)} VNĐ)?`)) return;

    setCompletingPayment(true);
    try {
      const res = await checkoutAndFreeTable(t, { paymentMethod });
      if (res.success) {
        setCheckoutToast(`✅ Đã thanh toán hóa đơn ${res.billId} và trả bàn ${t.name} thành công!`);
        setTimeout(() => setCheckoutToast(null), 5000);
        setSelectedTableForOrder(null);
      } else {
        alert("Lỗi khi trả bàn: " + (res.error || "Không xác định"));
      }
    } catch (e: any) {
      alert("Lỗi khi trả bàn: " + e.message);
    }
    setCompletingPayment(false);
  };

  const handleUpdateGuestCount = async (table: Table, count: number) => {
    try {
      const targetStoreCode = table.storeCode || (currentStoreCode !== "ALL" ? currentStoreCode : "TRAM01");
      const key = table.id;
      const stdKey = `${table.zone}_${table.name}`;
      await update(ref(db, `stores/${targetStoreCode}/tables/${key}`), { guestCount: count });
      if (stdKey !== key) {
        await update(ref(db, `stores/${targetStoreCode}/tables/${stdKey}`), { guestCount: count }).catch(() => {});
      }
      if (targetStoreCode === "TRAM01") {
        await update(ref(db, `tables/${key}`), { guestCount: count }).catch(() => {});
        if (stdKey !== key) {
          await update(ref(db, `tables/${stdKey}`), { guestCount: count }).catch(() => {});
        }
      }
      setSelectedTableForOrder((prev) => (prev ? { ...prev, guestCount: count } : null));
    } catch (e: any) {
      console.error("Lỗi cập nhật số khách:", e);
    }
  };

  const handleCheckInReservation = async (table: Table) => {
    if (!confirm(`Xác nhận nhận khách vào ${table.name}?`)) return;
    try {
      const targetStoreCode = table.storeCode || (currentStoreCode !== "ALL" ? currentStoreCode : "TRAM01");
      const key = table.id;
      const stdKey = `${table.zone}_${table.name}`;
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
      await update(ref(db, `stores/${targetStoreCode}/tables/${key}`), payload);
      if (stdKey !== key) {
        await update(ref(db, `stores/${targetStoreCode}/tables/${stdKey}`), payload).catch(() => {});
      }
      if (targetStoreCode === "TRAM01") {
        await update(ref(db, `tables/${key}`), payload).catch(() => {});
        if (stdKey !== key) {
          await update(ref(db, `tables/${stdKey}`), payload).catch(() => {});
        }
      }
      setCheckoutToast(`✅ Đã nhận khách vào ${table.name}!`);
      setTimeout(() => setCheckoutToast(null), 4000);
    } catch (e: any) {
      alert("Lỗi nhận bàn: " + e.message);
    }
  };

  const handleCancelReservation = async (table: Table) => {
    if (!confirm(`Xác nhận hủy đặt trước cho bàn ${table.name}?`)) return;
    try {
      const targetStoreCode = table.storeCode || (currentStoreCode !== "ALL" ? currentStoreCode : "TRAM01");
      const key = table.id;
      const stdKey = `${table.zone}_${table.name}`;
      const payload = {
        isReserved: false,
        reservationCustomer: null,
        reservationPhone: null,
        reservationTime: null,
        reservationDeposit: 0,
      };
      await update(ref(db, `stores/${targetStoreCode}/tables/${key}`), payload);
      if (stdKey !== key) {
        await update(ref(db, `stores/${targetStoreCode}/tables/${stdKey}`), payload).catch(() => {});
      }
      if (targetStoreCode === "TRAM01") {
        await update(ref(db, `tables/${key}`), payload).catch(() => {});
        if (stdKey !== key) {
          await update(ref(db, `tables/${stdKey}`), payload).catch(() => {});
        }
      }
      setCheckoutToast(`Đã hủy đặt trước bàn ${table.name}!`);
      setTimeout(() => setCheckoutToast(null), 4000);
    } catch (e: any) {
      alert("Lỗi hủy đặt bàn: " + e.message);
    }
  };

  const printBill = (table: Table) => {
    const items = parseOrderItems(table.currentOrderJson);
    const total = calculateTableTotal(items);
    const printWindow = window.open("", "_blank");
    if (!printWindow) {
      alert("Vui lòng cho phép mở cửa sổ popup để in hóa đơn");
      return;
    }

    const itemsHtml = items
      .map(
        (it) => `
      <tr>
        <td style="padding: 4px 0; text-align: left;">
          <strong>${it.name}</strong>
          ${it.selectedSize ? `<br/><small>Size: ${it.selectedSize}</small>` : ""}
          ${
            it.selectedToppings && it.selectedToppings.length > 0
              ? `<br/><small>+ ${it.selectedToppings.map((tp) => tp.name).join(", ")}</small>`
              : ""
          }
        </td>
        <td style="padding: 4px 0; text-align: center;">${it.quantity || it.count || 1}</td>
        <td style="padding: 4px 0; text-align: right;">${formatVND(it.price)}đ</td>
        <td style="padding: 4px 0; text-align: right; font-weight: bold;">
          ${formatVND(it.price * (it.quantity || it.count || 1))}đ
        </td>
      </tr>
    `
      )
      .join("");

    printWindow.document.write(`
      <!DOCTYPE html>
      <html>
      <head>
        <title>Hóa đơn tạm tính - ${table.name}</title>
        <style>
          body { font-family: monospace, sans-serif; width: 300px; margin: 0 auto; padding: 10px; color: #000; }
          .header { text-align: center; border-bottom: 1px dashed #000; padding-bottom: 8px; margin-bottom: 8px; }
          .title { font-size: 18px; font-weight: bold; }
          table { width: 100%; border-collapse: collapse; font-size: 13px; }
          th { border-bottom: 1px solid #000; padding: 4px 0; }
          .total { border-top: 1px dashed #000; margin-top: 10px; padding-top: 8px; }
          .total-row { display: flex; justify-content: space-between; font-size: 15px; font-weight: bold; }
          .footer { text-align: center; margin-top: 15px; font-size: 12px; border-top: 1px dashed #000; padding-top: 8px; }
        </style>
      </head>
      <body>
        <div class="header">
          <div class="title">TRẠM FnB SYSTEM</div>
          <div>PHIẾU TẠM TÍNH BÀN</div>
          <div style="margin-top: 4px;"><strong>${table.zone} - ${table.name}</strong></div>
          <div style="font-size: 11px;">Thời gian: ${new Date().toLocaleString("vi-VN")}</div>
        </div>
        <table>
          <thead>
            <tr>
              <th style="text-align: left;">Món</th>
              <th style="text-align: center;">SL</th>
              <th style="text-align: right;">Đơn giá</th>
              <th style="text-align: right;">T.Tiền</th>
            </tr>
          </thead>
          <tbody>
            ${itemsHtml}
          </tbody>
        </table>
        <div class="total">
          <div class="total-row">
            <span>TỔNG CỘNG:</span>
            <span>${formatVND(total)} VNĐ</span>
          </div>
        </div>
        <div class="footer">
          <div>Cảm ơn Quý khách! Hẹn gặp lại.</div>
          <div style="font-size: 10px; margin-top: 4px;">Hệ thống Quản lý Vận hành POS Trạm</div>
        </div>
        <script>
          window.onload = function() { window.print(); }
        </script>
      </body>
      </html>
    `);
    printWindow.document.close();
  };

  if (loading) {
    return (
      <div style={{ display: "flex", alignItems: "center", justifyContent: "center", height: "60vh" }}>
        <div className="spinner" />
      </div>
    );
  }

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "24px" }}>
      {/* Toast feedback */}
      {checkoutToast && (
        <div
          style={{
            background: "#ECFDF5",
            border: "1.5px solid #10B981",
            borderRadius: "12px",
            padding: "14px 18px",
            color: "#065F46",
            fontWeight: "600",
            display: "flex",
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
              background: "#FFFFFF",
              border: "1px solid #E6DEC8",
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
                background: viewMode === "grid" ? "#7E2930" : "transparent",
                color: viewMode === "grid" ? "#FFFFFF" : "#5D5B63",
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
                background: viewMode === "list" ? "#7E2930" : "transparent",
                color: viewMode === "list" ? "#FFFFFF" : "#5D5B63",
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

          <button className="btn-primary" onClick={openAdd}>
            <Plus size={16} />
            Thêm bàn mới
          </button>
        </div>
      </div>

      {/* Statistics Cards */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(210px, 1fr))", gap: "16px" }}>
        <div className="stat-card">
          <div style={{ fontSize: "13px", fontWeight: "600", color: "#5D5B63", marginBottom: "8px" }}>
            TỔNG SỐ BÀN
          </div>
          <div style={{ fontSize: "28px", fontWeight: "800", color: "#1C1A2D" }}>
            {tables.length} <span style={{ fontSize: "14px", fontWeight: "500", color: "#5D5B63" }}>bàn</span>
          </div>
          <div style={{ fontSize: "12px", color: "#5D5B63", marginTop: "4px" }}>
            Toàn bộ các khu vực
          </div>
        </div>

        <div
          className="stat-card"
          style={{
            borderLeft: "4px solid #7E2930",
            background: inUseCount > 0 ? "linear-gradient(135deg, #FFFFFF 0%, #FFF0F2 100%)" : "#FFFFFF",
          }}
        >
          <div style={{ fontSize: "13px", fontWeight: "700", color: "#7E2930", marginBottom: "8px" }}>
            ĐANG CÓ KHÁCH (IN USE)
          </div>
          <div style={{ fontSize: "28px", fontWeight: "800", color: "#7E2930" }}>
            {inUseCount} <span style={{ fontSize: "14px", fontWeight: "600", color: "#7E2930" }}>bàn</span>
          </div>
          <div style={{ fontSize: "12px", color: "#7E2930", marginTop: "4px", fontWeight: "600" }}>
            🔴 Đã gửi bếp & đang phục vụ
          </div>
        </div>

        <div
          className="stat-card"
          style={{
            borderLeft: "4px solid #146A65",
            background: "linear-gradient(135deg, #FFFFFF 0%, #E6F4F2 100%)",
          }}
        >
          <div style={{ fontSize: "13px", fontWeight: "700", color: "#146A65", marginBottom: "8px" }}>
            BÀN TRỐNG (AVAILABLE)
          </div>
          <div style={{ fontSize: "28px", fontWeight: "800", color: "#146A65" }}>
            {emptyCount} <span style={{ fontSize: "14px", fontWeight: "600", color: "#146A65" }}>bàn</span>
          </div>
          <div style={{ fontSize: "12px", color: "#146A65", marginTop: "4px", fontWeight: "600" }}>
            🟢 Sẵn sàng nhận khách mới
          </div>
        </div>

        <div className="stat-card" style={{ borderLeft: "4px solid #D97706" }}>
          <div style={{ fontSize: "13px", fontWeight: "700", color: "#D97706", marginBottom: "8px" }}>
            TỔNG SỐ KHÁCH HIỆN TẠI
          </div>
          <div style={{ fontSize: "28px", fontWeight: "800", color: "#D97706" }}>
            {totalGuests} <span style={{ fontSize: "14px", fontWeight: "600", color: "#D97706" }}>khách</span>
          </div>
          <div style={{ fontSize: "12px", color: "#805214", marginTop: "4px" }}>
            Đang ngồi tại {inUseCount} bàn
          </div>
        </div>

        <div
          className="stat-card"
          style={{
            borderLeft: "4px solid #B45309",
            background: reservedCount > 0 ? "linear-gradient(135deg, #FFFFFF 0%, #FEF3C7 100%)" : "#FFFFFF",
          }}
        >
          <div style={{ fontSize: "13px", fontWeight: "700", color: "#B45309", marginBottom: "8px" }}>
            ĐẶT TRƯỚC (RESERVED)
          </div>
          <div style={{ fontSize: "28px", fontWeight: "800", color: "#B45309" }}>
            {reservedCount} <span style={{ fontSize: "14px", fontWeight: "600", color: "#B45309" }}>bàn</span>
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
                color: "#8B8FA8",
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
        <div style={{ display: "flex", alignItems: "center", gap: "8px", flexWrap: "wrap", borderTop: "1px dashed #ECE5D8", paddingTop: "12px" }}>
          <span style={{ fontSize: "12px", fontWeight: "700", color: "#5D5B63", marginRight: "4px" }}>
            Trạng thái bàn:
          </span>
          <button
            onClick={() => setStatusFilter("ALL")}
            style={{
              padding: "4px 10px",
              borderRadius: "14px",
              fontSize: "12px",
              fontWeight: statusFilter === "ALL" ? "700" : "500",
              background: statusFilter === "ALL" ? "#1C1A2D" : "#F3F0EB",
              color: statusFilter === "ALL" ? "#FFFFFF" : "#5D5B63",
              border: "none",
              cursor: "pointer",
            }}
          >
            Tất cả ({tables.length})
          </button>
          <button
            onClick={() => setStatusFilter("IN_USE")}
            style={{
              padding: "4px 10px",
              borderRadius: "14px",
              fontSize: "12px",
              fontWeight: statusFilter === "IN_USE" ? "700" : "500",
              background: statusFilter === "IN_USE" ? "#7E2930" : "#FFF0F2",
              color: statusFilter === "IN_USE" ? "#FFFFFF" : "#7E2930",
              border: "1px solid rgba(126, 41, 48, 0.2)",
              cursor: "pointer",
            }}
          >
            🔴 Đang có khách ({inUseCount})
          </button>
          <button
            onClick={() => setStatusFilter("EMPTY")}
            style={{
              padding: "4px 10px",
              borderRadius: "14px",
              fontSize: "12px",
              fontWeight: statusFilter === "EMPTY" ? "700" : "500",
              background: statusFilter === "EMPTY" ? "#146A65" : "#E6F4F2",
              color: statusFilter === "EMPTY" ? "#FFFFFF" : "#146A65",
              border: "1px solid rgba(20, 106, 101, 0.2)",
              cursor: "pointer",
            }}
          >
            🟢 Bàn trống ({emptyCount})
          </button>
          <button
            onClick={() => setStatusFilter("RESERVED")}
            style={{
              padding: "4px 10px",
              borderRadius: "14px",
              fontSize: "12px",
              fontWeight: statusFilter === "RESERVED" ? "700" : "500",
              background: statusFilter === "RESERVED" ? "#B45309" : "#FEF3C7",
              color: statusFilter === "RESERVED" ? "#FFFFFF" : "#B45309",
              border: "1px solid rgba(180, 83, 9, 0.2)",
              cursor: "pointer",
            }}
          >
            🟡 Đặt trước ({reservedCount})
          </button>
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
              color: "#5D5B63",
            }}
          >
            <div style={{ fontSize: "48px", marginBottom: "12px" }}>🪑</div>
            <div style={{ fontSize: "16px", fontWeight: "700", color: "#1C1A2D", marginBottom: "6px" }}>
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
              gridTemplateColumns: "repeat(auto-fill, minmax(280px, 1fr))",
              gap: "20px",
            }}
          >
            {filtered.map((t) => {
              const orderItems = parseOrderItems(t.currentOrderJson);
              const orderTotal = calculateTableTotal(orderItems);
              const elapsedMinutes = getElapsedMinutes(t.openedAt);

              if (t.inUse) {
                // Thẻ bàn ĐANG CÓ KHÁCH (Màu đỏ mận Trạm)
                return (
                  <div
                    key={t.id}
                    onClick={() => setSelectedTableForOrder(t)}
                    style={{
                      background: "#FFFFFF",
                      borderRadius: "16px",
                      border: "2px solid #7E2930",
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
                        background: "linear-gradient(135deg, #7E2930 0%, #5C1F24 100%)",
                        padding: "14px 16px",
                        display: "flex",
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
                        <span style={{ fontSize: "18px", fontWeight: "800", letterSpacing: "0.02em" }}>
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
                      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
                        <span className="badge badge-danger">
                          <CheckCircle2 size={13} />
                          Đang có khách
                        </span>
                        <div style={{ display: "flex", alignItems: "center", gap: "10px", fontSize: "12px", color: "#5D5B63" }}>
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

                      {/* Danh sách món tóm tắt */}
                      <div
                        style={{
                          background: "#FFF0F2",
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
                            <div style={{ fontSize: "12px", fontWeight: "700", color: "#7E2930", marginBottom: "4px" }}>
                              {orderItems.length} món đã gửi bếp:
                            </div>
                            <div style={{ fontSize: "13px", color: "#1C1A2D", lineHeight: 1.4 }}>
                              {orderItems.slice(0, 2).map((item, idx) => (
                                <div key={idx} style={{ display: "flex", justifyContent: "space-between" }}>
                                  <span style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", maxWidth: "160px" }}>
                                    • {item.name}
                                  </span>
                                  <span style={{ fontWeight: "600", color: "#7E2930" }}>
                                    x{item.quantity || item.count || 1}
                                  </span>
                                </div>
                              ))}
                              {orderItems.length > 2 && (
                                <span style={{ fontSize: "11px", color: "#7E2930", fontWeight: "600" }}>
                                  + {orderItems.length - 2} món khác...
                                </span>
                              )}
                            </div>
                          </>
                        ) : (
                          <div style={{ textAlign: "center", fontSize: "12px", color: "#7E2930", fontStyle: "italic" }}>
                            Bàn đang mở • Chưa có món
                          </div>
                        )}
                      </div>

                      {/* Tổng tiền & Nút xem */}
                      <div
                        style={{
                          marginTop: "auto",
                          paddingTop: "10px",
                          borderTop: "1px solid #ECE5D8",
                          display: "flex",
                          alignItems: "center",
                          justifyContent: "space-between",
                        }}
                      >
                        <div>
                          <div style={{ fontSize: "11px", color: "#5D5B63", textTransform: "uppercase" }}>
                            Tạm tính
                          </div>
                          <div style={{ fontSize: "17px", fontWeight: "800", color: "#7E2930" }}>
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
                      background: "#FFFFFF",
                      borderRadius: "16px",
                      border: "2px solid #D97706",
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
                        background: "linear-gradient(135deg, #D97706 0%, #B45309 100%)",
                        padding: "14px 16px",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "space-between",
                        color: "#FFFFFF",
                      }}
                    >
                      <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
                        <Bookmark size={18} color="#FFFFFF" />
                        <span style={{ fontSize: "18px", fontWeight: "800", letterSpacing: "0.02em" }}>
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
                      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
                        <span className="badge badge-warning" style={{ background: "#FEF3C7", color: "#B45309", border: "1px solid #FDE68A" }}>
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
                          background: "#FFFBEB",
                          borderRadius: "10px",
                          padding: "12px",
                          border: "1px dashed rgba(217, 119, 6, 0.35)",
                          display: "flex",
                          flexDirection: "column",
                          gap: "6px",
                          fontSize: "13px",
                        }}
                      >
                        <div style={{ display: "flex", alignItems: "center", gap: "6px", color: "#1C1A2D" }}>
                          <Users size={14} color="#D97706" />
                          <span>Khách: <strong>{t.reservationCustomer || "Khách hẹn"}</strong></span>
                        </div>
                        {t.reservationPhone && (
                          <div style={{ display: "flex", alignItems: "center", gap: "6px", color: "#5D5B63", fontSize: "12px" }}>
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
                          borderTop: "1px solid #ECE5D8",
                          display: "flex",
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
                            color: "#B4232C",
                            fontSize: "12px",
                            fontWeight: "600",
                            cursor: "pointer",
                          }}
                        >
                          Hủy đặt
                        </button>
                        <button
                          className="btn-primary"
                          style={{ padding: "6px 14px", fontSize: "12px", background: "#D97706", borderColor: "#B45309" }}
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
                      background: "#FFFFFF",
                      borderRadius: "16px",
                      border: "1.5px solid #E6DEC8",
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
                        background: "#F6EFDF",
                        padding: "14px 16px",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "space-between",
                        borderBottom: "1px solid #E6DEC8",
                      }}
                    >
                      <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
                        <div
                          style={{
                            width: "9px",
                            height: "9px",
                            borderRadius: "50%",
                            background: "#146A65",
                          }}
                        />
                        <span style={{ fontSize: "18px", fontWeight: "800", color: "#1C1A2D" }}>
                          {t.name}
                        </span>
                      </div>
                      <span
                        style={{
                          fontSize: "11px",
                          fontWeight: "600",
                          padding: "3px 8px",
                          borderRadius: "6px",
                          background: "#FFFFFF",
                          border: "1px solid #D8CFBD",
                          color: "#5D5B63",
                        }}
                      >
                        {t.zone}
                      </span>
                    </div>

                    {/* Thân bàn trống */}
                    <div style={{ padding: "16px", flex: 1, display: "flex", flexDirection: "column", gap: "14px" }}>
                      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
                        <span className="badge badge-success">
                          <CheckCircle2 size={13} />
                          Bàn trống
                        </span>
                        <span style={{ fontSize: "12px", color: "#146A65", fontWeight: "600" }}>
                          Sẵn sàng
                        </span>
                      </div>

                      <div
                        style={{
                          background: "#E6F4F2",
                          borderRadius: "10px",
                          padding: "12px",
                          display: "flex",
                          alignItems: "center",
                          justifyContent: "center",
                          gap: "8px",
                          color: "#146A65",
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
                          borderTop: "1px solid #ECE5D8",
                          display: "flex",
                          alignItems: "center",
                          justifyContent: "flex-end",
                          gap: "8px",
                        }}
                      >
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
                            color: "#B4232C",
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
                  <td colSpan={8} style={{ textAlign: "center", padding: "48px", color: "#5D5B63" }}>
                    Không có dữ liệu bàn
                  </td>
                </tr>
              ) : (
                filtered.map((t, i) => {
                  const orderItems = parseOrderItems(t.currentOrderJson);
                  const orderTotal = calculateTableTotal(orderItems);
                  return (
                    <tr key={t.id}>
                      <td style={{ color: "#5D5B63" }}>{i + 1}</td>
                      <td style={{ fontWeight: "700", color: "#1C1A2D", fontSize: "15px" }}>{t.name}</td>
                      <td>
                        <span
                          className="badge"
                          style={{
                            background: "#F6EFDF",
                            color: "#1C1A2D",
                            border: "1px solid #D8CFBD",
                          }}
                        >
                          {t.zone}
                        </span>
                      </td>
                      <td>
                        <span className={t.inUse ? "badge badge-danger" : (t.isReserved ? "badge badge-warning" : "badge badge-success")}>
                          {t.inUse ? "🔴 Đang có khách" : (t.isReserved ? "🟡 Đặt trước" : "🟢 Trống")}
                        </span>
                      </td>
                      <td>
                        {t.inUse ? (
                          <div style={{ fontSize: "13px" }}>
                            <div>👥 {t.guestCount || 1} khách</div>
                            <div style={{ fontSize: "11px", color: "#5D5B63" }}>
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
                          <span style={{ color: "#8B8FA8" }}>—</span>
                        )}
                      </td>
                      <td>
                        {t.inUse && orderItems.length > 0 ? (
                          <span style={{ fontWeight: "600", color: "#7E2930" }}>
                            {orderItems.length} món
                          </span>
                        ) : (
                          <span style={{ color: "#8B8FA8" }}>—</span>
                        )}
                      </td>
                      <td>
                        {t.inUse ? (
                          <span style={{ fontWeight: "700", color: "#7E2930" }}>
                            {formatVND(orderTotal)} đ
                          </span>
                        ) : (
                          <span style={{ color: "#8B8FA8" }}>—</span>
                        )}
                      </td>
                      <td>
                        <div style={{ display: "flex", gap: "8px" }}>
                          {t.inUse && (
                            <button
                              onClick={() => setSelectedTableForOrder(t)}
                              style={{
                                padding: "6px 10px",
                                borderRadius: "8px",
                                background: "#FFF0F2",
                                border: "1px solid rgba(126, 41, 48, 0.3)",
                                color: "#7E2930",
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
                                background: "#FEF3C7",
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
                              color: t.inUse ? "#9E9CA3" : "#B4232C",
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
                background: "linear-gradient(135deg, #7E2930 0%, #5C1F24 100%)",
                color: "#FFFFFF",
                display: "flex",
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
                  <span
                    style={{
                      fontSize: "12px",
                      padding: "2px 8px",
                      borderRadius: "6px",
                      background: "#146A65",
                    }}
                  >
                    Đang phục vụ
                  </span>
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
              <div style={{ fontSize: "14px", fontWeight: "700", color: "#1C1A2D", marginBottom: "12px" }}>
                Danh sách món đã gửi bếp từ POS:
              </div>

              {parseOrderItems(selectedTableForOrder.currentOrderJson).length === 0 ? (
                <div
                  style={{
                    padding: "36px",
                    textAlign: "center",
                    color: "#5D5B63",
                    background: "#F8F4EE",
                    borderRadius: "12px",
                  }}
                >
                  <UtensilsCrossed size={32} style={{ margin: "0 auto 8px", color: "#7E2930" }} />
                  <div>Chưa có dữ liệu món ăn được gửi bếp.</div>
                </div>
              ) : (
                <div
                  style={{
                    border: "1px solid #E6DEC8",
                    borderRadius: "12px",
                    overflow: "hidden",
                    marginBottom: "18px",
                  }}
                >
                  <table style={{ width: "100%", fontSize: "13px" }}>
                    <thead>
                      <tr style={{ background: "#F6EFDF" }}>
                        <th style={{ padding: "10px 14px" }}>Món ăn / Đồ uống</th>
                        <th style={{ padding: "10px 14px", textAlign: "center" }}>SL</th>
                        <th style={{ padding: "10px 14px", textAlign: "right" }}>Đơn giá</th>
                        <th style={{ padding: "10px 14px", textAlign: "right" }}>Thành tiền</th>
                      </tr>
                    </thead>
                    <tbody>
                      {parseOrderItems(selectedTableForOrder.currentOrderJson).map((item, idx) => {
                        const qty = item.quantity || item.count || 1;
                        let toppingTotal = 0;
                        if (Array.isArray(item.selectedToppings)) {
                          toppingTotal = item.selectedToppings.reduce(
                            (s, tp) => s + (tp.price || 0),
                            0
                          );
                        }
                        const itemPriceWithTopping = item.price + toppingTotal;
                        const lineTotal = itemPriceWithTopping * qty;

                        return (
                          <tr key={idx} style={{ borderBottom: "1px solid #ECE5D8" }}>
                            <td style={{ padding: "12px 14px" }}>
                              <div style={{ fontWeight: "700", color: "#1C1A2D" }}>{item.name}</div>
                              {item.selectedSize && (
                                <div style={{ fontSize: "11px", color: "#5D5B63" }}>
                                  Size: <span style={{ fontWeight: "600" }}>{item.selectedSize}</span>
                                </div>
                              )}
                              {Array.isArray(item.selectedToppings) &&
                                item.selectedToppings.length > 0 && (
                                  <div style={{ fontSize: "11px", color: "#146A65" }}>
                                    + {item.selectedToppings.map((tp) => tp.name).join(", ")}
                                  </div>
                                )}
                              {item.note && (
                                <div style={{ fontSize: "11px", color: "#D97706", fontStyle: "italic" }}>
                                  Ghi chú: {item.note}
                                </div>
                              )}
                            </td>
                            <td style={{ padding: "12px 14px", textAlign: "center", fontWeight: "700" }}>
                              {qty}
                            </td>
                            <td style={{ padding: "12px 14px", textAlign: "right", color: "#5D5B63" }}>
                              {formatVND(itemPriceWithTopping)}đ
                            </td>
                            <td style={{ padding: "12px 14px", textAlign: "right", fontWeight: "800", color: "#7E2930" }}>
                              {formatVND(lineTotal)}đ
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              )}

              {/* Total Calculation */}
              <div
                style={{
                  background: "#FFF0F2",
                  borderRadius: "12px",
                  padding: "16px 20px",
                  border: "1.5px solid rgba(126, 41, 48, 0.2)",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "space-between",
                  marginBottom: "16px",
                }}
              >
                <div>
                  <div style={{ fontSize: "12px", color: "#5D5B63", textTransform: "uppercase", fontWeight: "600" }}>
                    Tổng tiền tạm tính của bàn
                  </div>
                  <div style={{ fontSize: "11px", color: "#7E2930", marginTop: "2px" }}>
                    Chưa bao gồm khuyến mãi / VAT (nếu có khi thanh toán)
                  </div>
                </div>
                <div style={{ fontSize: "24px", fontWeight: "800", color: "#7E2930" }}>
                  {formatVND(
                    calculateTableTotal(parseOrderItems(selectedTableForOrder.currentOrderJson))
                  )}{" "}
                  <span style={{ fontSize: "15px" }}>VNĐ</span>
                </div>
              </div>

              {/* Phương thức thanh toán */}
              <div style={{ marginBottom: "18px" }}>
                <div style={{ fontSize: "12px", fontWeight: "700", color: "#1C1A2D", marginBottom: "8px" }}>
                  Phương thức thanh toán:
                </div>
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "10px" }}>
                  <button
                    type="button"
                    onClick={() => setPaymentMethod("CASH")}
                    style={{
                      padding: "10px 14px",
                      borderRadius: "10px",
                      border: paymentMethod === "CASH" ? "2px solid #7E2930" : "1px solid #E6DEC8",
                      background: paymentMethod === "CASH" ? "#FFF0F2" : "#FFFFFF",
                      color: paymentMethod === "CASH" ? "#7E2930" : "#5D5B63",
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
                      border: paymentMethod === "TRANSFER" ? "2px solid #146A65" : "1px solid #E6DEC8",
                      background: paymentMethod === "TRANSFER" ? "#F0FDF4" : "#FFFFFF",
                      color: paymentMethod === "TRANSFER" ? "#146A65" : "#5D5B63",
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
                  const orderTotal = calculateTableTotal(
                    parseOrderItems(selectedTableForOrder.currentOrderJson)
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
                        background: "#F8FAF8",
                        border: "1.5px dashed #146A65",
                        display: "flex",
                        alignItems: "center",
                        gap: "14px",
                      }}
                    >
                      <img
                        src={qrUrl}
                        alt="VietQR Payment"
                        style={{
                          width: "90px",
                          height: "90px",
                          borderRadius: "8px",
                          border: "1px solid #E2E8F0",
                          objectFit: "contain",
                          background: "#FFFFFF",
                        }}
                      />
                      <div style={{ fontSize: "12px", lineHeight: "1.6", color: "#1C1A2D", flex: 1 }}>
                        <div style={{ fontWeight: "700", color: "#146A65", marginBottom: "2px" }}>
                          Quét mã VietQR để thanh toán:
                        </div>
                        <div>
                          Ngân hàng: <strong>{bankId}</strong> • STK: <strong>{bankAccount}</strong>
                        </div>
                        <div>
                          Chủ TK: <strong>{accountName}</strong>
                        </div>
                        <div style={{ color: "#7E2930", fontWeight: "700", marginTop: "2px" }}>
                          Số tiền: {formatVND(orderTotal)} VNĐ
                        </div>
                      </div>
                    </div>
                  );
                })()}
              </div>

              {/* Actions */}
              <div style={{ display: "flex", gap: "12px", flexWrap: "wrap" }}>
                <button
                  className="btn-secondary"
                  onClick={() => printBill(selectedTableForOrder)}
                  style={{ flex: 1, justifyContent: "center" }}
                >
                  <Printer size={16} />
                  In tạm tính
                </button>
                <button
                  className="btn-primary"
                  onClick={() => handleCheckoutAndFreeTable(selectedTableForOrder)}
                  disabled={completingPayment}
                  style={{ flex: 1, justifyContent: "center", opacity: completingPayment ? 0.7 : 1 }}
                >
                  <CheckCircle2 size={16} />
                  {completingPayment ? "Đang xử lý..." : "Thanh toán & Trả bàn"}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Modal: Thêm / Sửa bàn */}
      {showModal && (
        <div className="modal-overlay" onClick={closeModal}>
          <div className="modal-content" style={{ maxWidth: "420px" }} onClick={(e) => e.stopPropagation()}>
            <div
              style={{
                padding: "20px 24px 0",
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
                marginBottom: "20px",
              }}
            >
              <h2 style={{ fontSize: "18px", fontWeight: "800", color: "#1C1A2D" }}>
                {editId ? "Chỉnh sửa bàn" : "Thêm bàn mới"}
              </h2>
              <button
                onClick={closeModal}
                style={{ background: "none", border: "none", color: "#5D5B63", cursor: "pointer" }}
              >
                <X size={20} />
              </button>
            </div>
            <div style={{ padding: "0 24px 24px", display: "flex", flexDirection: "column", gap: "16px" }}>
              <div>
                <label style={{ display: "block", fontSize: "13px", fontWeight: "700", color: "#1C1A2D", marginBottom: "6px" }}>
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
                <label style={{ display: "block", fontSize: "13px", fontWeight: "700", color: "#1C1A2D", marginBottom: "6px" }}>
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
                <p style={{ fontSize: "11px", color: "#5D5B63", marginTop: "4px" }}>
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
                    color: "#B4232C",
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
              <h2 style={{ fontSize: "18px", fontWeight: "800", color: "#1C1A2D", marginBottom: "8px" }}>
                Xác nhận xóa bàn
              </h2>
              <p style={{ color: "#5D5B63", fontSize: "14px", marginBottom: "24px" }}>
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
