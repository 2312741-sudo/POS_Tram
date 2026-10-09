"use client";
import { useState, useMemo } from "react";
import {
  Store,
  Plus,
  MapPin,
  Phone,
  Wifi,
  CreditCard,
  Utensils,
  CheckCircle2,
  Edit2,
  Power,
  Building2,
  Search,
  TrendingUp,
  X,
} from "lucide-react";
import { useDashboardData, StoreItem } from "@/lib/data-context";

const BANK_OPTIONS = [
  { id: "MB", name: "MB Bank (Quân Đội)" },
  { id: "VCB", name: "Vietcombank" },
  { id: "TCB", name: "Techcombank" },
  { id: "ACB", name: "ACB (Á Châu)" },
  { id: "VPB", name: "VPBank" },
  { id: "TPB", name: "TPBank" },
  { id: "BIDV", name: "BIDV" },
  { id: "VIB", name: "VIB" },
  { id: "CTG", name: "VietinBank" },
];

export default function StoresManagementPage() {
  const {
    stores,
    currentStoreCode,
    setCurrentStoreCode,
    createStore,
    updateStore,
  } = useDashboardData();

  const [search, setSearch] = useState("");
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [editingStore, setEditingStore] = useState<StoreItem | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [actionError, setActionError] = useState("");
  const [actionSuccess, setActionSuccess] = useState("");

  // Create form state
  const [newStoreCode, setNewStoreCode] = useState("");
  const [newStoreName, setNewStoreName] = useState("");
  const [newAddress, setNewAddress] = useState("");
  const [newPhone, setNewPhone] = useState("");
  const [newWifi, setNewWifi] = useState("");
  const [newBankId, setNewBankId] = useState("MB");
  const [newBankAccount, setNewBankAccount] = useState("");
  const [newAccountName, setNewAccountName] = useState("");
  const [newVatRate] = useState("0");
  const [copyMenuFrom, setCopyMenuFrom] = useState("TRAM01");

  // Edit form state
  const [editName, setEditName] = useState("");
  const [editAddress, setEditAddress] = useState("");
  const [editPhone, setEditPhone] = useState("");
  const [editWifi, setEditWifi] = useState("");
  const [editBankId, setEditBankId] = useState("MB");
  const [editBankAccount, setEditBankAccount] = useState("");
  const [editAccountName, setEditAccountName] = useState("");
  const [editVatRate, setEditVatRate] = useState("0");
  const [editActive, setEditActive] = useState(true);

  // Filtered stores
  const filteredStores = useMemo(() => {
    return stores.filter((s) => {
      const q = search.toLowerCase();
      return (
        s.storeCode.toLowerCase().includes(q) ||
        s.storeName.toLowerCase().includes(q) ||
        (s.address || "").toLowerCase().includes(q) ||
        (s.phone || "").toLowerCase().includes(q)
      );
    });
  }, [stores, search]);

  // Ecosystem-wide stats
  const ecoStats = useMemo(() => {
    const totalStores = stores.length;
    const activeStores = stores.filter((s) => s.active !== false).length;
    const totalRev = stores.reduce((sum, s) => sum + (s.totalRevenue || 0), 0);
    const totalTables = stores.reduce((sum, s) => sum + (s.totalTables || 0), 0);
    const totalInUse = stores.reduce((sum, s) => sum + (s.inUseTables || 0), 0);
    const totalOrders = stores.reduce((sum, s) => sum + (s.totalOrders || 0), 0);

    return { totalStores, activeStores, totalRev, totalTables, totalInUse, totalOrders };
  }, [stores]);

  const handleOpenEdit = (store: StoreItem) => {
    setEditingStore(store);
    setEditName(store.storeName || "");
    setEditAddress(store.address || "");
    setEditPhone(store.phone || "");
    setEditWifi(store.wifiName || "");
    setEditBankId(store.bankId || "MB");
    setEditBankAccount(store.bankAccount || "");
    setEditAccountName(store.accountName || "");
    setEditVatRate(String(typeof store.defaultVatRate === "number" ? store.defaultVatRate : 0));
    setEditActive(store.active !== false);
    setActionError("");
    setActionSuccess("");
  };

  const handleCreateSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setActionError("");
    if (!newStoreCode.trim() || !newStoreName.trim()) {
      setActionError("Vui lòng nhập Mã chi nhánh và Tên chi nhánh.");
      return;
    }

    setSubmitting(true);
    const parsedNewVat = parseFloat(newVatRate);
    const res = await createStore(
      {
        storeCode: newStoreCode.trim().toUpperCase(),
        storeName: newStoreName.trim(),
        address: newAddress.trim(),
        phone: newPhone.trim(),
        wifiName: newWifi.trim() || "Tram_FnB_WiFi",
        bankId: newBankId,
        bankAccount: newBankAccount.trim(),
        accountName: newAccountName.trim() || "CHU CUA HANG",
        defaultVatRate: isNaN(parsedNewVat) ? 0 : parsedNewVat,
        active: true,
      },
      copyMenuFrom ? copyMenuFrom : undefined
    );

    setSubmitting(false);
    if (res.success) {
      setShowCreateModal(false);
      // Reset form
      setNewStoreCode("");
      setNewStoreName("");
      setNewAddress("");
      setNewPhone("");
      setNewWifi("");
      setNewBankAccount("");
      setNewAccountName("");
      setActionSuccess(`Đã tạo thành công chi nhánh mới: ${newStoreName}!`);
      setTimeout(() => setActionSuccess(""), 4000);
    } else {
      setActionError(res.error || "Không thể tạo chi nhánh mới.");
    }
  };

  const handleEditSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editingStore) return;
    setActionError("");

    setSubmitting(true);
    const parsedEditVat = parseFloat(editVatRate);
    const res = await updateStore(editingStore.storeCode, {
      storeName: editName.trim(),
      address: editAddress.trim(),
      phone: editPhone.trim(),
      wifiName: editWifi.trim(),
      bankId: editBankId,
      bankAccount: editBankAccount.trim(),
      accountName: editAccountName.trim(),
      defaultVatRate: isNaN(parsedEditVat) ? 0 : parsedEditVat,
      active: editActive,
    });
    setSubmitting(false);

    if (res.success) {
      setEditingStore(null);
      setActionSuccess(`Đã cập nhật thông tin chi nhánh ${editingStore.storeCode}!`);
      setTimeout(() => setActionSuccess(""), 4000);
    } else {
      setActionError(res.error || "Không thể cập nhật chi nhánh.");
    }
  };

  const handleToggleActive = async (store: StoreItem) => {
    const newStatus = !(store.active !== false);
    const msg = newStatus
      ? `Kích hoạt lại chi nhánh ${store.storeCode}?`
      : `Tạm dừng hoạt động chi nhánh ${store.storeCode}?`;

    if (confirm(msg)) {
      await updateStore(store.storeCode, { active: newStatus });
    }
  };

  const formatVnd = (num: number) => {
    return new Intl.NumberFormat("vi-VN", { style: "currency", currency: "VND" }).format(num);
  };

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "24px" }}>
      {/* Header */}
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: "16px" }}>
        <div>
          <h1 className="section-title" style={{ display: "flex", alignItems: "center", gap: "10px" }}>
            Hệ thống Multi-Store & Quản lý Chi nhánh 🏪
          </h1>
          <p className="section-subtitle">
            Mở rộng và kiểm soát chuỗi nhiều cửa hàng trên một nền tảng vận hành đồng bộ theo hệ sinh thái POS Trạm.
          </p>
        </div>

        <div style={{ display: "flex", gap: "12px", alignItems: "center" }}>
          <button className="btn-primary" onClick={() => setShowCreateModal(true)}>
            <Plus size={16} />
            Mở chi nhánh mới
          </button>
        </div>
      </div>

      {/* Notifications */}
      {actionSuccess && (
        <div
          style={{
            background: "var(--success-bg)",
            border: "1px solid #A3D9D2",
            color: "var(--success)",
            borderRadius: "10px",
            padding: "12px 16px",
            display: "flex",
            alignItems: "center",
            gap: "8px",
            fontSize: "14px",
            fontWeight: "600",
          }}
        >
          <CheckCircle2 size={18} />
          {actionSuccess}
        </div>
      )}

      {/* KPI Overview Cards */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(min(210px, 100%), 1fr))", gap: "16px" }}>
        <div className="card" style={{ padding: "18px 20px" }}>
          <div style={{ display: "flex", flexWrap: "wrap", rowGap: "8px", justifyContent: "space-between", alignItems: "center" }}>
            <span style={{ fontSize: "13px", fontWeight: "600", color: "var(--subtext)" }}>Tổng số chi nhánh</span>
            <Store size={20} style={{ color: "var(--primary)" }} />
          </div>
          <div style={{ fontSize: "24px", fontWeight: "800", color: "var(--text)", marginTop: "8px" }}>
            {ecoStats.totalStores} <span style={{ fontSize: "14px", fontWeight: "500", color: "var(--subtext)" }}>cửa hàng</span>
          </div>
          <div style={{ fontSize: "12px", color: "var(--success)", marginTop: "4px", fontWeight: "600" }}>
            ● {ecoStats.activeStores} chi nhánh đang hoạt động
          </div>
        </div>

        <div className="card" style={{ padding: "18px 20px" }}>
          <div style={{ display: "flex", flexWrap: "wrap", rowGap: "8px", justifyContent: "space-between", alignItems: "center" }}>
            <span style={{ fontSize: "13px", fontWeight: "600", color: "var(--subtext)" }}>Doanh thu toàn chuỗi</span>
            <TrendingUp size={20} style={{ color: "var(--success)" }} />
          </div>
          <div style={{ fontSize: "24px", fontWeight: "800", color: "var(--success)", marginTop: "8px" }}>
            {formatVnd(ecoStats.totalRev)}
          </div>
          <div style={{ fontSize: "12px", color: "var(--subtext)", marginTop: "4px" }}>
            {ecoStats.totalOrders} hóa đơn đã hoàn tất
          </div>
        </div>

        <div className="card" style={{ padding: "18px 20px" }}>
          <div style={{ display: "flex", flexWrap: "wrap", rowGap: "8px", justifyContent: "space-between", alignItems: "center" }}>
            <span style={{ fontSize: "13px", fontWeight: "600", color: "var(--subtext)" }}>Sơ đồ bàn toàn chuỗi</span>
            <Utensils size={20} style={{ color: "var(--warning)" }} />
          </div>
          <div style={{ fontSize: "24px", fontWeight: "800", color: "var(--text)", marginTop: "8px" }}>
            {ecoStats.totalTables} <span style={{ fontSize: "14px", fontWeight: "500", color: "var(--subtext)" }}>bàn</span>
          </div>
          <div style={{ fontSize: "12px", color: "var(--warning)", marginTop: "4px", fontWeight: "600" }}>
            ⚡ {ecoStats.totalInUse} bàn đang có khách ngồi
          </div>
        </div>

        <div className="card" style={{ padding: "18px 20px" }}>
          <div style={{ display: "flex", flexWrap: "wrap", rowGap: "8px", justifyContent: "space-between", alignItems: "center" }}>
            <span style={{ fontSize: "13px", fontWeight: "600", color: "var(--subtext)" }}>Chi nhánh đang xem</span>
            <Building2 size={20} style={{ color: "var(--primary)" }} />
          </div>
          <div style={{ fontSize: "18px", fontWeight: "800", color: "var(--primary)", marginTop: "8px" }}>
            {currentStoreCode === "ALL" ? "🌐 Toàn hệ thống" : `🏪 ${currentStoreCode}`}
          </div>
          <div style={{ fontSize: "12px", color: "var(--subtext)", marginTop: "4px" }}>
            {currentStoreCode === "ALL" ? "Xem dữ liệu tổng hợp" : (stores.find(s => s.storeCode === currentStoreCode)?.storeName || "Chi nhánh đã chọn")}
          </div>
        </div>
      </div>

      {/* Filter Toolbar */}
      <div className="card" style={{ padding: "16px 20px" }}>
        <div style={{ display: "flex", gap: "12px", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap" }}>
          <div style={{ position: "relative", flex: 1, minWidth: "260px" }}>
            <Search size={16} style={{ position: "absolute", left: "12px", top: "50%", transform: "translateY(-50%)", color: "var(--muted)" }} />
            <input
              className="input-field"
              placeholder="Tìm theo mã chi nhánh, tên cửa hàng, địa chỉ..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              style={{ paddingLeft: "38px", width: "100%" }}
            />
          </div>

          <div style={{ display: "flex", gap: "8px" }}>
            <button
              className="btn-secondary"
              onClick={() => setCurrentStoreCode("ALL")}
              style={{
                fontSize: "13px",
                borderColor: currentStoreCode === "ALL" ? "var(--primary)" : "var(--border)",
                background: currentStoreCode === "ALL" ? "var(--primary-light)" : "var(--surface)",
                fontWeight: currentStoreCode === "ALL" ? "700" : "500",
              }}
            >
              🌐 Xem toàn hệ thống
            </button>
          </div>
        </div>
      </div>

      {/* Stores List Grid */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(min(360px, 100%), 1fr))", gap: "20px" }}>
        {filteredStores.map((store) => {
          const isSelected = currentStoreCode === store.storeCode;
          const isActive = store.active !== false;

          return (
            <div
              key={store.storeCode}
              className="card"
              style={{
                padding: "24px",
                border: isSelected ? "2px solid var(--primary)" : "1px solid var(--border)",
                position: "relative",
                background: isSelected ? "#FFFEFB" : "var(--surface)",
                boxShadow: isSelected ? "0 8px 24px rgba(126, 41, 48, 0.12)" : "0 2px 8px rgba(0, 0, 0, 0.04)",
              }}
            >
              {/* Card Header */}
              <div style={{ display: "flex", flexWrap: "wrap", rowGap: "8px", justifyContent: "space-between", alignItems: "flex-start", marginBottom: "16px" }}>
                <div>
                  <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
                    <span
                      style={{
                        padding: "4px 10px",
                        background: "var(--primary)",
                        color: "#FFFFFF",
                        borderRadius: "8px",
                        fontWeight: "800",
                        fontSize: "13px",
                        letterSpacing: "0.04em",
                      }}
                    >
                      {store.storeCode}
                    </span>
                    <span
                      style={{
                        display: "inline-flex",
                        alignItems: "center",
                        gap: "4px",
                        padding: "3px 8px",
                        borderRadius: "12px",
                        fontSize: "11px",
                        fontWeight: "700",
                        background: isActive ? "var(--success-bg)" : "var(--danger-bg)",
                        color: isActive ? "var(--success)" : "var(--danger)",
                        border: `1px solid ${isActive ? "#A3D9D2" : "#FCA5A5"}`,
                      }}
                    >
                      {isActive ? "🟢 Đang hoạt động" : "⏸️ Tạm dừng"}
                    </span>
                  </div>
                  <h3 style={{ fontSize: "17px", fontWeight: "800", color: "var(--text)", marginTop: "8px", lineHeight: 1.3 }}>
                    {store.storeName}
                  </h3>
                </div>

                <button
                  className="btn-secondary"
                  onClick={() => handleOpenEdit(store)}
                  style={{ padding: "6px 10px", borderRadius: "8px" }}
                  title="Chỉnh sửa chi nhánh"
                >
                  <Edit2 size={14} />
                </button>
              </div>

              {/* Branch Details */}
              <div style={{ display: "flex", flexDirection: "column", gap: "8px", fontSize: "13px", color: "var(--subtext)", marginBottom: "18px" }}>
                <div style={{ display: "flex", alignItems: "flex-start", gap: "8px" }}>
                  <MapPin size={15} style={{ color: "var(--primary)", flexShrink: 0, marginTop: "2px" }} />
                  <span>{store.address || "Chưa cập nhật địa chỉ"}</span>
                </div>
                <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
                  <Phone size={15} style={{ color: "var(--primary)", flexShrink: 0 }} />
                  <span>{store.phone || "Chưa có số điện thoại"}</span>
                </div>
                <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
                  <Wifi size={15} style={{ color: "var(--primary)", flexShrink: 0 }} />
                  <span>WiFi: <strong>{store.wifiName || "Mặc định"}</strong></span>
                </div>
                <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
                  <CreditCard size={15} style={{ color: "var(--primary)", flexShrink: 0 }} />
                  <span>VietQR: <strong>{store.bankId}</strong> - <code>{store.bankAccount || "Chưa thiết lập"}</code> ({store.accountName})</span>
                </div>
              </div>

              {/* Quick Branch Metrics */}
              <div
                style={{
                  display: "grid",
                  gridTemplateColumns: "1fr 1fr 1fr",
                  gap: "10px",
                  padding: "12px",
                  background: "var(--bg)",
                  borderRadius: "10px",
                  marginBottom: "18px",
                  textAlign: "center",
                }}
              >
                <div>
                  <div style={{ fontSize: "11px", color: "var(--subtext)", fontWeight: "600" }}>SỐ BÀN</div>
                  <div style={{ fontSize: "16px", fontWeight: "800", color: "var(--text)", marginTop: "2px" }}>
                    {store.totalTables || 0}
                    {store.inUseTables ? <span style={{ fontSize: "11px", color: "var(--warning)" }}> ({store.inUseTables} bận)</span> : null}
                  </div>
                </div>
                <div>
                  <div style={{ fontSize: "11px", color: "var(--subtext)", fontWeight: "600" }}>HÓA ĐƠN</div>
                  <div style={{ fontSize: "16px", fontWeight: "800", color: "var(--text)", marginTop: "2px" }}>
                    {store.totalOrders || 0}
                  </div>
                </div>
                <div>
                  <div style={{ fontSize: "11px", color: "var(--subtext)", fontWeight: "600" }}>DOANH THU</div>
                  <div style={{ fontSize: "15px", fontWeight: "800", color: "var(--success)", marginTop: "2px" }}>
                    {formatVnd(store.totalRevenue || 0)}
                  </div>
                </div>
              </div>

              {/* Actions Footer */}
              <div style={{ display: "flex", flexWrap: "wrap", gap: "10px", alignItems: "center", justifyContent: "space-between" }}>
                <button
                  className="btn-primary"
                  onClick={() => setCurrentStoreCode(store.storeCode)}
                  style={{
                    flex: 1,
                    justifyContent: "center",
                    padding: "8px 14px",
                    fontSize: "13px",
                    background: isSelected ? "var(--success)" : undefined,
                  }}
                >
                  {isSelected ? "✓ Đang xem chi nhánh này" : "Chuyển sang chi nhánh này"}
                </button>

                <button
                  className="btn-secondary"
                  onClick={() => handleToggleActive(store)}
                  style={{
                    padding: "8px 12px",
                    fontSize: "13px",
                    color: isActive ? "var(--danger)" : "var(--success)",
                  }}
                  title={isActive ? "Tạm dừng hoạt động" : "Kích hoạt lại chi nhánh"}
                >
                  <Power size={14} />
                </button>
              </div>
            </div>
          );
        })}
      </div>

      {/* ==================== CREATE STORE MODAL ==================== */}
      {showCreateModal && (
        <div
          style={{
            position: "fixed",
            inset: 0,
            backgroundColor: "rgba(0, 0, 0, 0.5)",
            backdropFilter: "blur(4px)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            zIndex: 9999,
            padding: "20px",
          }}
          onClick={() => setShowCreateModal(false)}
        >
          <div
            className="card"
            style={{
              width: "100%",
              maxWidth: "580px",
              maxHeight: "90vh",
              overflowY: "auto",
              backgroundColor: "var(--surface)",
              borderRadius: "16px",
              boxShadow: "0 20px 40px rgba(0, 0, 0, 0.2)",
              padding: "26px",
            }}
            onClick={(e) => e.stopPropagation()}
          >
            <div style={{ display: "flex", flexWrap: "wrap", rowGap: "8px", justifyContent: "space-between", alignItems: "center", marginBottom: "20px" }}>
              <h2 style={{ fontSize: "19px", fontWeight: "800", color: "var(--text)", display: "flex", alignItems: "center", gap: "8px", margin: 0 }}>
                <Store size={22} style={{ color: "var(--primary)" }} />
                Mở Chi Nhánh Mới Trong Hệ Sinh Thái
              </h2>
              <button onClick={() => setShowCreateModal(false)} style={{ background: "none", border: "none", cursor: "pointer", color: "var(--muted)" }}>
                <X size={20} />
              </button>
            </div>

            {actionError && (
              <div style={{ background: "var(--danger-bg)", color: "var(--danger)", padding: "10px 14px", borderRadius: "8px", fontSize: "13px", fontWeight: "600", marginBottom: "16px" }}>
                ⚠️ {actionError}
              </div>
            )}

            <form onSubmit={handleCreateSubmit} style={{ display: "flex", flexDirection: "column", gap: "14px" }}>
              <div className="grid-stack-sm" style={{ display: "grid", gridTemplateColumns: "1fr 2fr", gap: "12px" }}>
                <div>
                  <label style={{ display: "block", fontSize: "12px", fontWeight: "700", marginBottom: "4px" }}>
                    Mã chi nhánh *
                  </label>
                  <input
                    className="input-field"
                    placeholder="VD: TRAM03"
                    value={newStoreCode}
                    onChange={(e) => setNewStoreCode(e.target.value.toUpperCase())}
                    style={{ textTransform: "uppercase", fontWeight: "700" }}
                    required
                  />
                </div>
                <div>
                  <label style={{ display: "block", fontSize: "12px", fontWeight: "700", marginBottom: "4px" }}>
                    Tên cửa hàng / chi nhánh *
                  </label>
                  <input
                    className="input-field"
                    placeholder="VD: Trạm F&B - Chi nhánh Cầu Giấy"
                    value={newStoreName}
                    onChange={(e) => setNewStoreName(e.target.value)}
                    required
                  />
                </div>
              </div>

              <div>
                <label style={{ display: "block", fontSize: "12px", fontWeight: "700", marginBottom: "4px" }}>
                  Địa chỉ chi nhánh
                </label>
                <input
                  className="input-field"
                  placeholder="VD: 123 Đường Cầu Giấy, Hà Nội"
                  value={newAddress}
                  onChange={(e) => setNewAddress(e.target.value)}
                />
              </div>

              <div className="grid-stack-sm" style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "12px" }}>
                <div>
                  <label style={{ display: "block", fontSize: "12px", fontWeight: "700", marginBottom: "4px" }}>
                    Số điện thoại
                  </label>
                  <input
                    className="input-field"
                    placeholder="0987xxxxxx"
                    value={newPhone}
                    onChange={(e) => setNewPhone(e.target.value)}
                  />
                </div>
                <div>
                  <label style={{ display: "block", fontSize: "12px", fontWeight: "700", marginBottom: "4px" }}>
                    Tên WiFi cửa hàng
                  </label>
                  <input
                    className="input-field"
                    placeholder="Tram_FnB_Free"
                    value={newWifi}
                    onChange={(e) => setNewWifi(e.target.value)}
                  />
                </div>
              </div>

              {/* VietQR section */}
              <div style={{ background: "var(--bg)", padding: "14px", borderRadius: "10px", border: "1px solid var(--border)" }}>
                <div style={{ fontSize: "12px", fontWeight: "800", color: "var(--primary)", marginBottom: "10px", display: "flex", alignItems: "center", gap: "6px" }}>
                  <CreditCard size={15} /> THÔNG TIN THANH TOÁN VIETQR TẠI QUẦY
                </div>
                <div className="grid-stack-sm" style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "10px", marginBottom: "10px" }}>
                  <div>
                    <label style={{ display: "block", fontSize: "11px", fontWeight: "600", marginBottom: "3px" }}>Ngân hàng</label>
                    <select
                      className="input-field"
                      value={newBankId}
                      onChange={(e) => setNewBankId(e.target.value)}
                      style={{ fontSize: "13px" }}
                    >
                      {BANK_OPTIONS.map((b) => (
                        <option key={b.id} value={b.id}>{b.name}</option>
                      ))}
                    </select>
                  </div>
                  <div>
                    <label style={{ display: "block", fontSize: "11px", fontWeight: "600", marginBottom: "3px" }}>Số tài khoản</label>
                    <input
                      className="input-field"
                      placeholder="0987654321"
                      value={newBankAccount}
                      onChange={(e) => setNewBankAccount(e.target.value)}
                      style={{ fontSize: "13px" }}
                    />
                  </div>
                </div>
                <div>
                  <label style={{ display: "block", fontSize: "11px", fontWeight: "600", marginBottom: "3px" }}>Tên chủ tài khoản (In hoa không dấu)</label>
                  <input
                    className="input-field"
                    placeholder="CHU CUA HANG TRAM FNB"
                    value={newAccountName}
                    onChange={(e) => setNewAccountName(e.target.value.toUpperCase())}
                    style={{ fontSize: "13px", textTransform: "uppercase" }}
                  />
                </div>
              </div>

              {/* Ecosystem Seed Option */}
              <div style={{ background: "var(--success-bg)", padding: "12px 14px", borderRadius: "10px", border: "1px solid #A3D9D2" }}>
                <label style={{ display: "flex", alignItems: "center", gap: "8px", fontSize: "13px", fontWeight: "700", color: "var(--success)", cursor: "pointer" }}>
                  <input
                    type="checkbox"
                    checked={Boolean(copyMenuFrom)}
                    onChange={(e) => setCopyMenuFrom(e.target.checked ? "TRAM01" : "")}
                  />
                  <span>Tự động sao chép toàn bộ thực đơn & danh mục món từ Trụ sở TRAM01</span>
                </label>
                <div style={{ fontSize: "11px", color: "var(--subtext)", marginTop: "4px", marginLeft: "22px" }}>
                  Chi nhánh mới sẽ có sẵn 37 món, 10 danh mục và 6 bàn phân bổ theo Tầng 1, Tầng 2, Sân Vườn.
                </div>
              </div>

              <div style={{ display: "flex", justifyContent: "flex-end", gap: "10px", marginTop: "10px" }}>
                <button
                  type="button"
                  className="btn-secondary"
                  onClick={() => setShowCreateModal(false)}
                  disabled={submitting}
                >
                  Hủy
                </button>
                <button
                  type="submit"
                  className="btn-primary"
                  disabled={submitting}
                >
                  {submitting ? "Đang khởi tạo..." : "Xác nhận tạo chi nhánh"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* ==================== EDIT STORE MODAL ==================== */}
      {editingStore && (
        <div
          style={{
            position: "fixed",
            inset: 0,
            backgroundColor: "rgba(0, 0, 0, 0.5)",
            backdropFilter: "blur(4px)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            zIndex: 9999,
            padding: "20px",
          }}
          onClick={() => setEditingStore(null)}
        >
          <div
            className="card"
            style={{
              width: "100%",
              maxWidth: "580px",
              maxHeight: "90vh",
              overflowY: "auto",
              backgroundColor: "var(--surface)",
              borderRadius: "16px",
              boxShadow: "0 20px 40px rgba(0, 0, 0, 0.2)",
              padding: "26px",
            }}
            onClick={(e) => e.stopPropagation()}
          >
            <div style={{ display: "flex", flexWrap: "wrap", rowGap: "8px", justifyContent: "space-between", alignItems: "center", marginBottom: "20px" }}>
              <h2 style={{ fontSize: "19px", fontWeight: "800", color: "var(--text)", display: "flex", alignItems: "center", gap: "8px", margin: 0 }}>
                <Edit2 size={20} style={{ color: "var(--primary)" }} />
                Chỉnh Sửa Chi Nhánh: {editingStore.storeCode}
              </h2>
              <button onClick={() => setEditingStore(null)} style={{ background: "none", border: "none", cursor: "pointer", color: "var(--muted)" }}>
                <X size={20} />
              </button>
            </div>

            {actionError && (
              <div style={{ background: "var(--danger-bg)", color: "var(--danger)", padding: "10px 14px", borderRadius: "8px", fontSize: "13px", fontWeight: "600", marginBottom: "16px" }}>
                ⚠️ {actionError}
              </div>
            )}

            <form onSubmit={handleEditSubmit} style={{ display: "flex", flexDirection: "column", gap: "14px" }}>
              <div>
                <label style={{ display: "block", fontSize: "12px", fontWeight: "700", marginBottom: "4px" }}>
                  Tên cửa hàng / chi nhánh *
                </label>
                <input
                  className="input-field"
                  value={editName}
                  onChange={(e) => setEditName(e.target.value)}
                  required
                />
              </div>

              <div>
                <label style={{ display: "block", fontSize: "12px", fontWeight: "700", marginBottom: "4px" }}>
                  Địa chỉ chi nhánh
                </label>
                <input
                  className="input-field"
                  value={editAddress}
                  onChange={(e) => setEditAddress(e.target.value)}
                />
              </div>

              <div className="grid-stack-sm" style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "12px" }}>
                <div>
                  <label style={{ display: "block", fontSize: "12px", fontWeight: "700", marginBottom: "4px" }}>
                    Số điện thoại
                  </label>
                  <input
                    className="input-field"
                    value={editPhone}
                    onChange={(e) => setEditPhone(e.target.value)}
                  />
                </div>
                <div>
                  <label style={{ display: "block", fontSize: "12px", fontWeight: "700", marginBottom: "4px" }}>
                    Tên WiFi cửa hàng
                  </label>
                  <input
                    className="input-field"
                    value={editWifi}
                    onChange={(e) => setEditWifi(e.target.value)}
                  />
                </div>
              </div>

              {/* VietQR section */}
              <div style={{ background: "var(--bg)", padding: "14px", borderRadius: "10px", border: "1px solid var(--border)" }}>
                <div style={{ fontSize: "12px", fontWeight: "800", color: "var(--primary)", marginBottom: "10px", display: "flex", alignItems: "center", gap: "6px" }}>
                  <CreditCard size={15} /> THÔNG TIN THANH TOÁN VIETQR
                </div>
                <div className="grid-stack-sm" style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "10px", marginBottom: "10px" }}>
                  <div>
                    <label style={{ display: "block", fontSize: "11px", fontWeight: "600", marginBottom: "3px" }}>Ngân hàng</label>
                    <select
                      className="input-field"
                      value={editBankId}
                      onChange={(e) => setEditBankId(e.target.value)}
                      style={{ fontSize: "13px" }}
                    >
                      {BANK_OPTIONS.map((b) => (
                        <option key={b.id} value={b.id}>{b.name}</option>
                      ))}
                    </select>
                  </div>
                  <div>
                    <label style={{ display: "block", fontSize: "11px", fontWeight: "600", marginBottom: "3px" }}>Số tài khoản</label>
                    <input
                      className="input-field"
                      value={editBankAccount}
                      onChange={(e) => setEditBankAccount(e.target.value)}
                      style={{ fontSize: "13px" }}
                    />
                  </div>
                </div>
                <div>
                  <label style={{ display: "block", fontSize: "11px", fontWeight: "600", marginBottom: "3px" }}>Tên chủ tài khoản</label>
                  <input
                    className="input-field"
                    value={editAccountName}
                    onChange={(e) => setEditAccountName(e.target.value.toUpperCase())}
                    style={{ fontSize: "13px", textTransform: "uppercase" }}
                  />
                </div>
              </div>

              <div style={{ display: "flex", alignItems: "center", gap: "10px", marginTop: "4px" }}>
                <label style={{ display: "flex", alignItems: "center", gap: "8px", fontSize: "13px", fontWeight: "700", cursor: "pointer" }}>
                  <input
                    type="checkbox"
                    checked={editActive}
                    onChange={(e) => setEditActive(e.target.checked)}
                  />
                  <span>Chi nhánh đang mở cửa hoạt động</span>
                </label>
              </div>

              <div style={{ display: "flex", justifyContent: "flex-end", gap: "10px", marginTop: "14px" }}>
                <button
                  type="button"
                  className="btn-secondary"
                  onClick={() => setEditingStore(null)}
                  disabled={submitting}
                >
                  Hủy
                </button>
                <button
                  type="submit"
                  className="btn-primary"
                  disabled={submitting}
                >
                  {submitting ? "Đang lưu..." : "Lưu thay đổi"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
