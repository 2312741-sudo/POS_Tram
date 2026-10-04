"use client";
import { useState, useMemo } from "react";
import { 
  Search, Download, Plus, Edit2, Trash2, X, Check, Users, ShieldCheck, 
  Store, Phone, Lock, Eye, EyeOff, CheckCircle2, XCircle, UserCheck, UserX
} from "lucide-react";
import { exportUsers } from "@/lib/export";
import { useDashboardData, UserItem } from "@/lib/data-context";

function formatVND(amount: number) {
  return new Intl.NumberFormat("vi-VN", { style: "currency", currency: "VND" }).format(amount);
}

export const UNIFIED_ROLES = [
  { id: "ROLE_OWNER", name: "Chủ Quán (Toàn quyền)", icon: "👑", desc: "Toàn quyền quản trị tất cả chi nhánh và phân quyền" },
  { id: "ROLE_MANAGER", name: "Quản Lý Ca / Chi Nhánh", icon: "⭐", desc: "Quản lý phòng bàn, thực đơn, két tiền ca, báo cáo" },
  { id: "ROLE_CASHIER", name: "Thu Ngân", icon: "💰", desc: "Mở bàn, tính tiền, in hóa đơn, áp dụng khuyến mãi" },
  { id: "ROLE_WAITER", name: "Nhân Viên Phục Vụ", icon: "🍽️", desc: "Xem menu, mở bàn, gọi món gửi bếp KDS" },
  { id: "ROLE_KITCHEN", name: "Bếp / Pha Chế", icon: "🍳", desc: "Xem màn hình bếp KDS, cập nhật trạng thái chế biến" },
];

interface UserForm {
  fullName: string;
  username: string;
  password: string;
  role: string;
  phone: string;
  storeCode: string;
  isActive: boolean;
}

const emptyForm: UserForm = {
  fullName: "",
  username: "",
  password: "",
  role: "ROLE_WAITER",
  phone: "",
  storeCode: "TRAM01",
  isActive: true,
};

export default function UsersPage() {
  const {
    usersList: users,
    allUsers,
    stores,
    currentStoreCode,
    setCurrentStoreCode,
    saveUser,
    deleteUser,
    historyData,
    loading: ctxLoading,
  } = useDashboardData();

  const loading = ctxLoading && users.length === 0;
  const [search, setSearch] = useState("");
  const [filterRole, setFilterRole] = useState("ALL");
  const [showModal, setShowModal] = useState(false);
  const [editUser, setEditUser] = useState<UserItem | null>(null);
  const [form, setForm] = useState<UserForm>(emptyForm);
  const [showPassword, setShowPassword] = useState(false);
  const [saving, setSaving] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<UserItem | null>(null);
  const [error, setError] = useState("");

  const usersWithStats = useMemo(() => {
    return users.map((u) => {
      const uName = (u.username || u.id || "").toLowerCase();
      const userOrders = historyData.filter(
        (h) =>
          (h.username && h.username.toLowerCase() === uName) ||
          (h.createdBy && h.createdBy.toLowerCase() === uName) ||
          (h.orderStaff && h.orderStaff.toLowerCase() === (u.fullName || "").toLowerCase()) ||
          (h.cashierName && h.cashierName.toLowerCase() === (u.fullName || "").toLowerCase())
      );
      const totalSales = userOrders.reduce((s, h) => s + (Number(h.totalAmount) || 0), 0);
      return { ...u, totalSales, totalOrders: userOrders.length };
    }).sort((a, b) => (b.totalSales || 0) - (a.totalSales || 0));
  }, [users, historyData]);

  const filtered = useMemo(() => {
    return usersWithStats.filter((u) => {
      const q = search.trim().toLowerCase();
      const matchSearch =
        !q ||
        (u.fullName && u.fullName.toLowerCase().includes(q)) ||
        (u.username && u.username.toLowerCase().includes(q)) ||
        (u.phone && u.phone.includes(q));

      const roleId = (u.roleId || u.role || "").toUpperCase();
      const matchRole = filterRole === "ALL" || roleId === filterRole;

      return matchSearch && matchRole;
    });
  }, [usersWithStats, search, filterRole]);

  // Overall stats
  const stats = useMemo(() => {
    const totalStaff = users.length;
    const activeStaff = users.filter((u) => u.isActive !== false).length;
    const managers = users.filter((u) => {
      const r = (u.roleId || u.role || "").toUpperCase();
      return r.includes("OWNER") || r.includes("MANAGER");
    }).length;
    const cashiers = users.filter((u) => {
      const r = (u.roleId || u.role || "").toUpperCase();
      return r.includes("CASHIER") || r.includes("THUNGAN");
    }).length;
    return { totalStaff, activeStaff, managers, cashiers };
  }, [users]);

  const openAdd = () => {
    setEditUser(null);
    setForm({
      ...emptyForm,
      storeCode: currentStoreCode !== "ALL" ? currentStoreCode : (stores[0]?.storeCode || "TRAM01"),
    });
    setError("");
    setShowPassword(false);
    setShowModal(true);
  };

  const openEdit = (u: UserItem) => {
    setEditUser(u);
    setForm({
      fullName: u.fullName || "",
      username: u.username || u.id || "",
      password: u.password || "",
      role: u.roleId || u.role || "ROLE_WAITER",
      phone: u.phone || "",
      storeCode: u.storeCode || (currentStoreCode !== "ALL" ? currentStoreCode : stores[0]?.storeCode || "TRAM01"),
      isActive: u.isActive !== false,
    });
    setError("");
    setShowPassword(false);
    setShowModal(true);
  };

  const closeModal = () => {
    setShowModal(false);
    setEditUser(null);
    setForm(emptyForm);
    setError("");
  };

  const handleSave = async () => {
    if (!form.fullName.trim()) { setError("Vui lòng nhập họ và tên nhân viên"); return; }
    if (!form.username.trim()) { setError("Vui lòng nhập tên đăng nhập"); return; }
    if (!editUser && !form.password.trim()) { setError("Vui lòng nhập mật khẩu đăng nhập"); return; }
    
    setSaving(true);
    setError("");

    try {
      const res = await saveUser({
        username: form.username.trim().toLowerCase(),
        fullName: form.fullName.trim(),
        password: form.password ? form.password.trim() : undefined,
        role: form.role,
        phone: form.phone.trim(),
        isActive: form.isActive,
        storeCode: form.storeCode,
      }, form.storeCode);

      if (!res.success) {
        setError(res.error || "Lỗi lưu thông tin nhân viên");
        setSaving(false);
        return;
      }

      closeModal();
    } catch (e: any) {
      setError(e.message || "Lỗi kết nối");
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async () => {
    if (!deleteTarget) return;
    try {
      await deleteUser(deleteTarget.username || deleteTarget.id, deleteTarget.storeCode);
      setDeleteTarget(null);
    } catch (e: any) {
      alert(e.message || "Lỗi khi xóa nhân viên");
    }
  };

  const handleToggleActive = async (u: UserItem) => {
    try {
      await saveUser({
        username: u.username || u.id,
        fullName: u.fullName,
        password: u.password,
        role: u.roleId || u.role,
        phone: u.phone,
        storeCode: u.storeCode,
        isActive: u.isActive === false ? true : false,
      }, u.storeCode);
    } catch (e: any) {
      alert(e.message || "Lỗi cập nhật trạng thái");
    }
  };

  const handleExport = () => {
    exportUsers(filtered);
  };

  const getRoleBadge = (roleStr: string) => {
    const r = (roleStr || "").toUpperCase();
    if (r.includes("OWNER") || r.includes("ADMIN")) {
      return (
        <span className="badge badge-danger" style={{ display: "inline-flex", alignItems: "center", gap: "4px" }}>
          👑 Chủ Quán
        </span>
      );
    }
    if (r.includes("MANAGER")) {
      return (
        <span className="badge" style={{ background: "rgba(245,158,11,0.15)", color: "#D97706", borderColor: "rgba(245,158,11,0.3)", display: "inline-flex", alignItems: "center", gap: "4px" }}>
          ⭐ Quản Lý
        </span>
      );
    }
    if (r.includes("CASHIER") || r.includes("THUNGAN")) {
      return (
        <span className="badge" style={{ background: "rgba(16,185,129,0.15)", color: "#059669", borderColor: "rgba(16,185,129,0.3)", display: "inline-flex", alignItems: "center", gap: "4px" }}>
          💰 Thu Ngân
        </span>
      );
    }
    if (r.includes("KITCHEN") || r.includes("BEP") || r.includes("DAUBEP")) {
      return (
        <span className="badge badge-warning" style={{ display: "inline-flex", alignItems: "center", gap: "4px" }}>
          🍳 Bếp / Bar
        </span>
      );
    }
    return (
      <span className="badge badge-info" style={{ display: "inline-flex", alignItems: "center", gap: "4px" }}>
        🍽️ Phục Vụ
      </span>
    );
  };

  const getRankIcon = (i: number) => {
    if (i === 0) return "🥇";
    if (i === 1) return "🥈";
    if (i === 2) return "🥉";
    return `#${i + 1}`;
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
      {/* Header */}
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: "16px" }}>
        <div>
          <h1 className="section-title">Quản lý Nhân viên & Vai trò 👥</h1>
          <p className="section-subtitle">
            Đồng bộ phân quyền thời gian thực giữa Web Quản trị và Mobile POS ({users.length} tài khoản)
          </p>
        </div>
        <div style={{ display: "flex", gap: "10px" }}>
          <button className="btn-secondary" onClick={handleExport}>
            <Download size={16} />
            Xuất Excel
          </button>
          <button className="btn-primary" onClick={openAdd}>
            <Plus size={16} />
            Thêm nhân viên
          </button>
        </div>
      </div>

      {/* Store Quick Switcher Bar */}
      {stores.length > 0 && (
        <div style={{ display: "flex", gap: "8px", flexWrap: "wrap", alignItems: "center" }}>
          <button
            onClick={() => setCurrentStoreCode("ALL")}
            style={{
              padding: "7px 16px",
              borderRadius: "10px",
              fontSize: "13px",
              fontWeight: "700",
              cursor: "pointer",
              transition: "all 0.15s ease",
              border: "1px solid",
              borderColor: currentStoreCode === "ALL" ? "#7E2930" : "#E6DEC8",
              background: currentStoreCode === "ALL" ? "#7E2930" : "#FFFFFF",
              color: currentStoreCode === "ALL" ? "#FFFFFF" : "#5D5B63",
            }}
          >
            🌐 Tất cả chi nhánh ({allUsers.length} NV)
          </button>
          {stores.map((s) => {
            const isSelected = currentStoreCode === s.storeCode;
            const count = allUsers.filter((u) => u.storeCode === s.storeCode || u.isRootOwner).length;
            return (
              <button
                key={s.storeCode}
                onClick={() => setCurrentStoreCode(s.storeCode)}
                style={{
                  padding: "7px 16px",
                  borderRadius: "10px",
                  fontSize: "13px",
                  fontWeight: "700",
                  cursor: "pointer",
                  transition: "all 0.15s ease",
                  border: "1px solid",
                  borderColor: isSelected ? "#7E2930" : "#E6DEC8",
                  background: isSelected ? "#7E2930" : "#FFFFFF",
                  color: isSelected ? "#FFFFFF" : "#5D5B63",
                }}
              >
                🏪 {s.storeName} ({count} NV)
              </button>
            );
          })}
        </div>
      )}

      {/* Overview Stat Cards */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(200px, 1fr))", gap: "16px" }}>
        <div className="stat-card">
          <div style={{ fontSize: "13px", color: "#8B8FA8", fontWeight: "600", display: "flex", alignItems: "center", gap: "6px" }}>
            <Users size={16} color="#7E2930" /> Tổng nhân viên
          </div>
          <div style={{ fontSize: "24px", fontWeight: "800", color: "#1C1A2D", marginTop: "8px" }}>
            {stats.totalStaff}
          </div>
          <div style={{ fontSize: "12px", color: "#10B981", marginTop: "4px", fontWeight: "600" }}>
            ● {stats.activeStaff} đang hoạt động
          </div>
        </div>

        <div className="stat-card">
          <div style={{ fontSize: "13px", color: "#8B8FA8", fontWeight: "600", display: "flex", alignItems: "center", gap: "6px" }}>
            <ShieldCheck size={16} color="#F59E0B" /> Quản lý & Chủ quán
          </div>
          <div style={{ fontSize: "24px", fontWeight: "800", color: "#D97706", marginTop: "8px" }}>
            {stats.managers}
          </div>
          <div style={{ fontSize: "12px", color: "#8B8FA8", marginTop: "4px" }}>
            Quyền quản trị & hủy món/bill
          </div>
        </div>

        <div className="stat-card">
          <div style={{ fontSize: "13px", color: "#8B8FA8", fontWeight: "600", display: "flex", alignItems: "center", gap: "6px" }}>
            <Store size={16} color="#3B82F6" /> Thu ngân & Phục vụ
          </div>
          <div style={{ fontSize: "24px", fontWeight: "800", color: "#3B82F6", marginTop: "8px" }}>
            {stats.totalStaff - stats.managers}
          </div>
          <div style={{ fontSize: "12px", color: "#8B8FA8", marginTop: "4px" }}>
            Tác nghiệp bán hàng & order
          </div>
        </div>
      </div>

      {/* Top 3 Staff Performers */}
      {usersWithStats.slice(0, 3).some((u) => u.totalSales > 0) && (
        <div>
          <div style={{ fontSize: "14px", fontWeight: "700", color: "#1C1A2D", marginBottom: "12px" }}>
            🏆 Bảng vinh danh doanh số nhân viên
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(280px, 1fr))", gap: "16px" }}>
            {usersWithStats.slice(0, 3).map((u, i) => (
              <div key={u.id} className="stat-card" style={{ borderColor: i === 0 ? "rgba(255,182,39,0.5)" : "#E6DEC8" }}>
                <div style={{ display: "flex", alignItems: "center", gap: "12px", marginBottom: "12px" }}>
                  <span style={{ fontSize: "28px" }}>{getRankIcon(i)}</span>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontWeight: "700", color: "#1C1A2D", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                      {u.fullName}
                    </div>
                    <div style={{ display: "flex", alignItems: "center", gap: "6px", marginTop: "2px" }}>
                      {getRoleBadge(u.roleId || u.role)}
                      <span style={{ fontSize: "11px", color: "#8B8FA8" }}>@{u.username}</span>
                    </div>
                  </div>
                </div>
                <div style={{ fontSize: "18px", fontWeight: "800", color: "#7E2930" }}>{formatVND(u.totalSales || 0)}</div>
                <div style={{ fontSize: "12px", color: "#8B8FA8", marginTop: "2px" }}>{u.totalOrders || 0} đơn hàng đã hoàn tất</div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Search & Filter Bar */}
      <div className="card" style={{ padding: "16px 20px" }}>
        <div style={{ display: "flex", gap: "12px", flexWrap: "wrap", alignItems: "center", justifyContent: "space-between" }}>
          <div style={{ position: "relative", minWidth: "280px", flex: 1 }}>
            <Search size={16} style={{ position: "absolute", left: "12px", top: "50%", transform: "translateY(-50%)", color: "#8B8FA8" }} />
            <input
              className="input-field"
              placeholder="Tìm theo tên, tài khoản, SĐT..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              style={{ paddingLeft: "38px" }}
            />
          </div>

          <div style={{ display: "flex", gap: "8px", alignItems: "center" }}>
            <span style={{ fontSize: "13px", fontWeight: "600", color: "#8B8FA8" }}>Vai trò:</span>
            <select
              className="input-field"
              style={{ width: "auto", minWidth: "160px" }}
              value={filterRole}
              onChange={(e) => setFilterRole(e.target.value)}
            >
              <option value="ALL">Tất cả vai trò</option>
              {UNIFIED_ROLES.map((r) => (
                <option key={r.id} value={r.id}>
                  {r.icon} {r.name}
                </option>
              ))}
            </select>
          </div>
        </div>
      </div>

      {/* Users Table */}
      <div className="table-wrapper">
        <table>
          <thead>
            <tr>
              <th style={{ width: "60px", textAlign: "center" }}>Hạng</th>
              <th>Họ & Tên</th>
              <th>Tài khoản</th>
              <th>Chi nhánh</th>
              <th>Vai trò</th>
              <th>Trạng thái</th>
              <th>Doanh số</th>
              <th>Số đơn</th>
              <th style={{ textAlign: "right" }}>Thao tác</th>
            </tr>
          </thead>
          <tbody>
            {filtered.length === 0 ? (
              <tr>
                <td colSpan={9} style={{ textAlign: "center", padding: "48px", color: "#8B8FA8" }}>
                  Không tìm thấy nhân viên nào phù hợp
                </td>
              </tr>
            ) : (
              filtered.map((u, i) => (
                <tr key={`${u.storeCode || 'TRAM01'}_${u.username || u.id}`}>
                  <td style={{ textAlign: "center", fontSize: "18px" }}>{getRankIcon(i)}</td>
                  <td>
                    <div style={{ fontWeight: "700", color: "#1C1A2D" }}>{u.fullName}</div>
                    {u.phone && (
                      <div style={{ fontSize: "12px", color: "#8B8FA8", display: "flex", alignItems: "center", gap: "4px", marginTop: "2px" }}>
                        <Phone size={11} /> {u.phone}
                      </div>
                    )}
                  </td>
                  <td>
                    <span style={{ fontFamily: "monospace", color: "#7E2930", fontWeight: "700", fontSize: "13px", background: "rgba(126,41,48,0.06)", padding: "2px 8px", borderRadius: "6px" }}>
                      @{u.username}
                    </span>
                  </td>
                  <td>
                    <span className="badge" style={{ fontSize: "12px", background: "#F4EFE6", color: "#5D5B63", borderColor: "#E6DEC8" }}>
                      🏪 {u.storeName || u.storeCode || "TRAM01"}
                    </span>
                  </td>
                  <td>{getRoleBadge(u.roleId || u.role)}</td>
                  <td>
                    {u.isActive !== false ? (
                      <span style={{ display: "inline-flex", alignItems: "center", gap: "6px", fontSize: "12px", color: "#10B981", fontWeight: "600" }}>
                        <CheckCircle2 size={14} /> Hoạt động
                      </span>
                    ) : (
                      <span style={{ display: "inline-flex", alignItems: "center", gap: "6px", fontSize: "12px", color: "#EF4444", fontWeight: "600" }}>
                        <XCircle size={14} /> Đã khóa
                      </span>
                    )}
                  </td>
                  <td style={{ fontWeight: "700", color: "#7E2930" }}>{formatVND(u.totalSales || 0)}</td>
                  <td style={{ color: "#5D5B63", fontWeight: "600" }}>{u.totalOrders || 0}</td>
                  <td style={{ textAlign: "right" }}>
                    <div style={{ display: "inline-flex", gap: "6px" }}>
                      <button
                        title={u.isActive !== false ? "Khóa tài khoản" : "Kích hoạt lại tài khoản"}
                        onClick={() => handleToggleActive(u)}
                        style={{
                          padding: "6px 8px",
                          borderRadius: "8px",
                          background: u.isActive !== false ? "rgba(245,158,11,0.1)" : "rgba(16,185,129,0.1)",
                          border: `1px solid ${u.isActive !== false ? "rgba(245,158,11,0.3)" : "rgba(16,185,129,0.3)"}`,
                          color: u.isActive !== false ? "#D97706" : "#10B981",
                          cursor: "pointer",
                        }}
                      >
                        {u.isActive !== false ? <UserX size={15} /> : <UserCheck size={15} />}
                      </button>
                      <button
                        title="Chỉnh sửa thông tin"
                        onClick={() => openEdit(u)}
                        style={{
                          padding: "6px 8px",
                          borderRadius: "8px",
                          background: "rgba(59,130,246,0.1)",
                          border: "1px solid rgba(59,130,246,0.3)",
                          color: "#3B82F6",
                          cursor: "pointer",
                        }}
                      >
                        <Edit2 size={15} />
                      </button>
                      <button
                        title="Xóa nhân viên"
                        onClick={() => setDeleteTarget(u)}
                        style={{
                          padding: "6px 8px",
                          borderRadius: "8px",
                          background: "rgba(239,68,68,0.1)",
                          border: "1px solid rgba(239,68,68,0.3)",
                          color: "#EF4444",
                          cursor: "pointer",
                        }}
                      >
                        <Trash2 size={15} />
                      </button>
                    </div>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {/* Add / Edit User Modal */}
      {showModal && (
        <div className="modal-overlay" onClick={closeModal}>
          <div className="modal-content" style={{ maxWidth: "540px" }} onClick={(e) => e.stopPropagation()}>
            <div style={{ padding: "20px 24px 0", display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: "16px" }}>
              <div>
                <h2 style={{ fontSize: "18px", fontWeight: "700", color: "#1C1A2D" }}>
                  {editUser ? "Chỉnh sửa thông tin nhân viên" : "Thêm nhân viên mới"}
                </h2>
                <p style={{ fontSize: "12px", color: "#8B8FA8", marginTop: "2px" }}>
                  Tài khoản có thể đăng nhập trên cả ứng dụng Mobile POS và Web Quản trị
                </p>
              </div>
              <button onClick={closeModal} style={{ background: "none", border: "none", color: "#8B8FA8", cursor: "pointer" }}>
                <X size={20} />
              </button>
            </div>

            <div style={{ padding: "0 24px 24px", display: "flex", flexDirection: "column", gap: "14px" }}>
              {/* Full Name */}
              <div>
                <label style={{ display: "block", fontSize: "13px", fontWeight: "600", color: "#1C1A2D", marginBottom: "6px" }}>
                  Họ và tên nhân viên *
                </label>
                <input
                  className="input-field"
                  placeholder="Ví dụ: Nguyễn Văn A"
                  value={form.fullName}
                  onChange={(e) => setForm((f) => ({ ...f, fullName: e.target.value }))}
                />
              </div>

              {/* Username & Phone */}
              <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "12px" }}>
                <div>
                  <label style={{ display: "block", fontSize: "13px", fontWeight: "600", color: "#1C1A2D", marginBottom: "6px" }}>
                    Tên đăng nhập *
                  </label>
                  <input
                    className="input-field"
                    placeholder="ví dụ: nva"
                    value={form.username}
                    disabled={!!editUser}
                    onChange={(e) => setForm((f) => ({ ...f, username: e.target.value.toLowerCase().replace(/[^a-z0-9_]/g, "") }))}
                    style={{ background: editUser ? "#F4EFE6" : undefined, cursor: editUser ? "not-allowed" : undefined }}
                  />
                  {editUser && <span style={{ fontSize: "11px", color: "#8B8FA8" }}>Không thể đổi tên đăng nhập</span>}
                </div>

                <div>
                  <label style={{ display: "block", fontSize: "13px", fontWeight: "600", color: "#1C1A2D", marginBottom: "6px" }}>
                    Số điện thoại
                  </label>
                  <input
                    className="input-field"
                    placeholder="0987xxxxxx"
                    value={form.phone}
                    onChange={(e) => setForm((f) => ({ ...f, phone: e.target.value }))}
                  />
                </div>
              </div>

              {/* Password */}
              <div>
                <label style={{ display: "block", fontSize: "13px", fontWeight: "600", color: "#1C1A2D", marginBottom: "6px" }}>
                  {editUser ? "Mật khẩu mới (để trống nếu giữ nguyên)" : "Mật khẩu đăng nhập *"}
                </label>
                <div style={{ position: "relative" }}>
                  <input
                    type={showPassword ? "text" : "password"}
                    className="input-field"
                    placeholder={editUser ? "Nhập mật khẩu mới..." : "Nhập mật khẩu (ví dụ: 123456)"}
                    value={form.password}
                    onChange={(e) => setForm((f) => ({ ...f, password: e.target.value }))}
                    style={{ paddingRight: "40px" }}
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    style={{
                      position: "absolute",
                      right: "12px",
                      top: "50%",
                      transform: "translateY(-50%)",
                      background: "none",
                      border: "none",
                      color: "#8B8FA8",
                      cursor: "pointer",
                    }}
                  >
                    {showPassword ? <EyeOff size={16} /> : <Eye size={16} />}
                  </button>
                </div>
              </div>

              {/* Store Code Selection */}
              <div>
                <label style={{ display: "block", fontSize: "13px", fontWeight: "600", color: "#1C1A2D", marginBottom: "6px" }}>
                  Chi nhánh làm việc *
                </label>
                <select
                  className="input-field"
                  value={form.storeCode}
                  onChange={(e) => setForm((f) => ({ ...f, storeCode: e.target.value }))}
                >
                  {stores.map((s) => (
                    <option key={s.storeCode} value={s.storeCode}>
                      🏪 {s.storeName} ({s.storeCode})
                    </option>
                  ))}
                </select>
              </div>

              {/* Unified Role Selection */}
              <div>
                <label style={{ display: "block", fontSize: "13px", fontWeight: "600", color: "#1C1A2D", marginBottom: "6px" }}>
                  Vai trò & Phân quyền chuẩn *
                </label>
                <div style={{ display: "flex", flexDirection: "column", gap: "8px" }}>
                  {UNIFIED_ROLES.map((r) => {
                    const isSelected = form.role === r.id;
                    return (
                      <div
                        key={r.id}
                        onClick={() => setForm((f) => ({ ...f, role: r.id }))}
                        style={{
                          padding: "10px 14px",
                          borderRadius: "10px",
                          border: `1.5px solid ${isSelected ? "#7E2930" : "#E6DEC8"}`,
                          background: isSelected ? "rgba(126,41,48,0.04)" : "#FFFFFF",
                          cursor: "pointer",
                          display: "flex",
                          alignItems: "center",
                          justifyContent: "space-between",
                          transition: "all 0.15s ease",
                        }}
                      >
                        <div>
                          <div style={{ fontWeight: "700", color: isSelected ? "#7E2930" : "#1C1A2D", fontSize: "13px", display: "flex", alignItems: "center", gap: "6px" }}>
                            <span>{r.icon}</span> {r.name}
                          </div>
                          <div style={{ fontSize: "11px", color: "#8B8FA8", marginTop: "2px" }}>{r.desc}</div>
                        </div>
                        <input
                          type="radio"
                          name="user_role"
                          checked={isSelected}
                          onChange={() => setForm((f) => ({ ...f, role: r.id }))}
                          style={{ accentColor: "#7E2930", cursor: "pointer" }}
                        />
                      </div>
                    );
                  })}
                </div>
              </div>

              {/* Active Toggle */}
              <div style={{ display: "flex", alignItems: "center", gap: "10px", padding: "10px 0" }}>
                <input
                  type="checkbox"
                  id="user_is_active"
                  checked={form.isActive}
                  onChange={(e) => setForm((f) => ({ ...f, isActive: e.target.checked }))}
                  style={{ width: "18px", height: "18px", accentColor: "#7E2930", cursor: "pointer" }}
                />
                <label htmlFor="user_is_active" style={{ fontSize: "13px", fontWeight: "600", color: "#1C1A2D", cursor: "pointer" }}>
                  Kích hoạt tài khoản (cho phép đăng nhập hệ thống)
                </label>
              </div>

              {/* Error Message */}
              {error && (
                <div style={{ background: "rgba(239,68,68,0.1)", border: "1px solid rgba(239,68,68,0.3)", borderRadius: "8px", padding: "10px 14px", color: "#EF4444", fontSize: "13px" }}>
                  {error}
                </div>
              )}

              {/* Actions */}
              <div style={{ display: "flex", gap: "10px", marginTop: "8px" }}>
                <button className="btn-secondary" onClick={closeModal} style={{ flex: 1, justifyContent: "center" }}>
                  Hủy
                </button>
                <button className="btn-primary" onClick={handleSave} disabled={saving} style={{ flex: 1, justifyContent: "center", opacity: saving ? 0.7 : 1 }}>
                  {saving ? (
                    <div style={{ width: "16px", height: "16px", border: "2px solid rgba(255,255,255,0.3)", borderTopColor: "white", borderRadius: "50%", animation: "spin 0.7s linear infinite" }} />
                  ) : (
                    <Check size={16} />
                  )}
                  {editUser ? "Lưu thay đổi" : "Tạo nhân viên"}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Delete Confirmation Modal */}
      {deleteTarget && (
        <div className="modal-overlay" onClick={() => setDeleteTarget(null)}>
          <div className="modal-content" style={{ maxWidth: "420px" }} onClick={(e) => e.stopPropagation()}>
            <div style={{ padding: "28px", textAlign: "center" }}>
              <div style={{ fontSize: "48px", marginBottom: "16px" }}>⚠️</div>
              <h2 style={{ fontSize: "18px", fontWeight: "700", color: "#1C1A2D", marginBottom: "8px" }}>Xác nhận xóa nhân viên</h2>
              <p style={{ color: "#8B8FA8", fontSize: "14px", lineHeight: "1.5", marginBottom: "20px" }}>
                Bạn có chắc chắn muốn xóa nhân viên <strong style={{ color: "#1C1A2D" }}>{deleteTarget.fullName}</strong> (@{deleteTarget.username}) thuộc chi nhánh <strong style={{ color: "#1C1A2D" }}>{deleteTarget.storeCode}</strong> khỏi hệ thống?
              </p>
              <div style={{ display: "flex", gap: "10px" }}>
                <button className="btn-secondary" onClick={() => setDeleteTarget(null)} style={{ flex: 1, justifyContent: "center" }}>
                  Hủy bỏ
                </button>
                <button className="btn-danger" onClick={handleDelete} style={{ flex: 1, justifyContent: "center" }}>
                  <Trash2 size={16} />
                  Xóa nhân viên
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
