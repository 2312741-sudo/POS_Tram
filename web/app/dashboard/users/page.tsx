"use client";
import React, { useState, useEffect, useMemo, useCallback } from "react";
import { useRouter } from "next/navigation";
import {
  Search,
  Download,
  Plus,
  Edit2,
  Trash2,
  X,
  Check,
  Users,
  ShieldCheck,
  Store,
  Phone,
  Eye,
  EyeOff,
  CheckCircle2,
  XCircle,
  UserCheck,
  UserX,
  Clock,
  ShieldAlert,
  KeyRound,
} from "lucide-react";
import { exportUsers } from "@/lib/export";
import { useAuth, hasPermission, validateUsername, normalizeUsername } from "@/lib/auth";
import { useDashboardData } from "@/lib/data-context";
import { db, functions } from "@/lib/firebase";
import { ref, set, update, remove } from "firebase/database";
import { httpsCallable } from "firebase/functions";

function formatDateTime(timestamp?: number | null) {
  if (!timestamp) return "Chưa đăng nhập";
  const d = new Date(timestamp);
  const pad = (n: number) => n.toString().padStart(2, "0");
  const time = `${pad(d.getHours())}:${pad(d.getMinutes())}`;
  const date = `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()}`;
  return `${time} ${date}`;
}

const UNIFIED_ROLES = [
  {
    id: "ROLE_OWNER",
    name: "Chủ Quán (Toàn quyền)",
    icon: "👑",
    desc: "Toàn quyền quản trị tất cả chi nhánh và phân quyền",
  },
  {
    id: "ROLE_MANAGER_1",
    name: "Quản Lý 1 (Điều hành & Báo cáo)",
    icon: "⭐",
    desc: "Điều hành bán hàng, kho, doanh thu, ca két, chiết khấu",
  },
  {
    id: "ROLE_MANAGER_2",
    name: "Quản Lý 2 (Giám sát ca)",
    icon: "📋",
    desc: "Giám sát ca trực, điều phối bàn, in bill, xem báo cáo ca",
  },
  {
    id: "ROLE_CASHIER",
    name: "Thu Ngân",
    icon: "💰",
    desc: "Mở bàn, tính tiền, in hóa đơn, áp dụng khuyến mãi",
  },
  {
    id: "ROLE_WAITER",
    name: "Nhân Viên Phục Vụ",
    icon: "🍽️",
    desc: "Xem menu, mở bàn, gọi món gửi bếp KDS",
  },
  {
    id: "ROLE_KITCHEN",
    name: "Bếp / Pha Chế",
    icon: "🍳",
    desc: "Xem màn hình bếp KDS, cập nhật trạng thái chế biến",
  },
];

const AVAILABLE_CUSTOM_PERMISSIONS = [
  { id: "INVENTORY_STOCK_IN", label: "Nhập kho (Stock In)", desc: "Tạo và hoàn thành phiếu nhập hàng, tăng tồn kho" },
  { id: "INVENTORY_STOCK_OUT", label: "Xuất kho (Stock Out)", desc: "Tạo và hoàn thành phiếu xuất kho nội bộ, pha chế" },
  { id: "INVENTORY_WASTE", label: "Huỷ kho (Stock Waste)", desc: "Tạo và hoàn thành phiếu xuất hủy hàng hỏng, hết hạn" },
  { id: "DISCOUNT_ITEM", label: "Giảm giá món", desc: "Giảm giá trực tiếp từng món ăn trên đơn" },
  { id: "MENU_MANAGEMENT", label: "Quản lý thực đơn & Topping", desc: "Quản lý toàn diện món, mã SKU, nhóm món và topping" },
  { id: "MANUAL_DISCOUNT", label: "Chiết khấu thủ công", desc: "Giảm giá trực tiếp trên đơn" },
  { id: "CANCEL_BILL", label: "Hủy hóa đơn", desc: "Hủy đơn hàng sau khi tạo" },
  { id: "REPRINT_BILL", label: "In lại hóa đơn", desc: "In lại hóa đơn đã thanh toán" },
  { id: "CANCEL_KITCHEN_ITEM", label: "Hủy món gửi bếp", desc: "Hủy món đã chuyển sang KDS" },
  { id: "VIEW_AUDIT_LOGS", label: "Xem nhật ký kiểm soát", desc: "Truy cập nhật ký thao tác nhạy cảm" },
  { id: "VIEW_COST_PRICE", label: "Xem giá vốn NVL", desc: "Xem chi phí nguyên vật liệu" },
  { id: "APPROVE_STOCKTAKE", label: "Duyệt kiểm kê kho", desc: "Xác nhận chênh lệch kiểm kê" },
  { id: "ADJUST_CASH_SHIFT", label: "Điều chỉnh két ca", desc: "Sửa đổi số dư ca làm việc" },
  { id: "MANAGE_PROMOTIONS", label: "Quản lý khuyến mãi", desc: "Tạo và sửa chương trình khuyến mãi" },
];

export interface DashboardUser {
  id: string;
  uid?: string;
  username: string;
  fullName: string;
  roleId: string;
  role: string;
  isRootOwner?: boolean;
  customPermissions?: string[];
  isActive?: boolean;
  phone?: string;
  storeCode?: string;
  storeName?: string;
  createdAt?: number;
  lastLoginAt?: number | null;
  mustChangePassword?: boolean;
  totalSales?: number;
  totalOrders?: number;
}

interface UserForm {
  fullName: string;
  username: string;
  password: string;
  role: string;
  phone: string;
  storeCode: string;
  isActive: boolean;
  customPermissions: string[];
}

const emptyForm: UserForm = {
  fullName: "",
  username: "",
  password: "",
  role: "ROLE_WAITER",
  phone: "",
  storeCode: "",
  isActive: true,
  customPermissions: [],
};

export default function UsersPage() {
  const router = useRouter();
  const { user: currentUser, loading: authLoading, storeCode: activeStoreCode } = useAuth();

  const {
    stores,
    allUsers,
    loading: dataLoading,
    currentStoreCode,
    setCurrentStoreCode,
  } = useDashboardData();

  const loadingUsers = dataLoading;

  const storesList = useMemo(() => {
    return stores.map((s) => ({ storeCode: s.storeCode, storeName: s.storeName }));
  }, [stores]);

  const usersMap = useMemo(() => {
    const map: Record<string, DashboardUser[]> = {};
    stores.forEach((s) => {
      map[s.storeCode] = [];
    });
    allUsers.forEach((u) => {
      const sCode = u.storeCode || "TRAM01";
      if (!map[sCode]) map[sCode] = [];
      map[sCode].push({
        id: u.id || u.username || "",
        uid: u.id || u.username || "",
        username: u.username || "",
        fullName: u.fullName || u.username || "",
        roleId: u.roleId || u.role || "ROLE_WAITER",
        role: u.roleId || u.role || "ROLE_WAITER",
        isRootOwner: u.isRootOwner,
        customPermissions: u.customPermissions || [],
        isActive: u.isActive !== false,
        phone: u.phone || "",
        storeCode: sCode,
        storeName: u.storeName,
        createdAt: u.createdAt,
        lastLoginAt: u.lastLoginAt,
        mustChangePassword: u.mustChangePassword,
      });
    });
    return map;
  }, [stores, allUsers]);

  const [search, setSearch] = useState("");
  const [filterRole, setFilterRole] = useState("ALL");
  const [showModal, setShowModal] = useState(false);
  const [editUser, setEditUser] = useState<DashboardUser | null>(null);
  const [form, setForm] = useState<UserForm>(emptyForm);
  const [showPassword, setShowPassword] = useState(false);
  const [saving, setSaving] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<DashboardUser | null>(null);
  const [error, setError] = useState("");

  // Quản lý Đặt lại mật khẩu qua Cloud Function
  const [resetPasswordTarget, setResetPasswordTarget] = useState<DashboardUser | null>(null);
  const [newPasswordInput, setNewPasswordInput] = useState("");
  const [showNewPassword, setShowNewPassword] = useState(false);
  const [resettingPassword, setResettingPassword] = useState(false);
  const [resetPasswordError, setResetPasswordError] = useState("");

  // 1. Phân quyền truy cập trang (Chỉ Chủ quán hoặc người có MANAGE_USERS)
  const canManageUsers = useMemo(() => {
    return hasPermission(currentUser, "MANAGE_USERS");
  }, [currentUser]);

  useEffect(() => {
    if (!authLoading && currentUser && !canManageUsers) {
      router.replace("/dashboard");
    }
  }, [authLoading, currentUser, canManageUsers, router]);

  // Danh sách người dùng theo chi nhánh được chọn
  const currentUsers = useMemo(() => {
    if (currentStoreCode === "ALL") {
      const all: DashboardUser[] = [];
      Object.values(usersMap).forEach((list) => all.push(...list));
      return all;
    }
    return usersMap[currentStoreCode] || [];
  }, [usersMap, currentStoreCode]);

  // Bộ lọc tìm kiếm & vai trò
  const filteredUsers = useMemo(() => {
    return currentUsers.filter((u) => {
      const q = search.trim().toLowerCase();
      const matchSearch =
        !q ||
        u.fullName.toLowerCase().includes(q) ||
        u.username.toLowerCase().includes(q) ||
        (u.phone && u.phone.includes(q));

      const roleIdUpper = (u.roleId || u.role || "").toUpperCase();
      const matchRole =
        filterRole === "ALL" ||
        roleIdUpper === filterRole ||
        (filterRole === "ROLE_MANAGER_1" && roleIdUpper.includes("MANAGER_1")) ||
        (filterRole === "ROLE_MANAGER_2" && (roleIdUpper.includes("MANAGER_2") || roleIdUpper === "ROLE_MANAGER"));

      return matchSearch && matchRole;
    });
  }, [currentUsers, search, filterRole]);

  // Thống kê nhanh
  const stats = useMemo(() => {
    const totalStaff = currentUsers.length;
    const activeStaff = currentUsers.filter((u) => u.isActive !== false).length;
    const managers = currentUsers.filter((u) => {
      const r = (u.roleId || u.role || "").toUpperCase();
      return r.includes("OWNER") || r.includes("MANAGER");
    }).length;
    return { totalStaff, activeStaff, managers };
  }, [currentUsers]);

  const openAdd = () => {
    setEditUser(null);
    setForm({
      ...emptyForm,
      storeCode:
        currentStoreCode !== "ALL"
          ? currentStoreCode
          : storesList[0]?.storeCode || activeStoreCode || "",
    });
    setError("");
    setShowPassword(false);
    setShowModal(true);
  };

  const openEdit = (u: DashboardUser) => {
    setEditUser(u);
    setForm({
      fullName: u.fullName,
      username: u.username,
      password: "",
      role: u.roleId || u.role || "ROLE_WAITER",
      phone: u.phone || "",
      storeCode: u.storeCode || storesList[0]?.storeCode || activeStoreCode || "",
      isActive: u.isActive !== false,
      customPermissions: u.customPermissions || [],
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

  const toggleCustomPermission = (permId: string) => {
    setForm((f) => {
      const exists = f.customPermissions.includes(permId);
      return {
        ...f,
        customPermissions: exists
          ? f.customPermissions.filter((p) => p !== permId)
          : [...f.customPermissions, permId],
      };
    });
  };

  // Lưu người dùng (Tạo mới qua Secondary App hoặc Cập nhật)
  const handleSave = async () => {
    setError("");

    if (!form.fullName.trim()) {
      setError("Vui lòng nhập họ và tên nhân viên");
      return;
    }

    if (!editUser) {
      // Xác thực tên đăng nhập mới
      const userCheck = validateUsername(form.username);
      if (!userCheck.valid) {
        setError(userCheck.error || "Tên đăng nhập không hợp lệ");
        return;
      }

      if (!form.password.trim()) {
        setError("Vui lòng nhập mật khẩu khởi tạo cho nhân viên");
        return;
      }
      if (form.password.trim().length < 6) {
        setError("Mật khẩu khởi tạo phải có tối thiểu 6 ký tự");
        return;
      }
    }

    setSaving(true);
    const cleanStore = form.storeCode.trim().toUpperCase();
    const cleanUser = normalizeUsername(form.username);

    try {
      if (editUser) {
        // CẬP NHẬT NHÂN VIÊN
        const targetUid = editUser.uid || editUser.id;
        const isRoot = editUser.isRootOwner === true;

        const updateData: Record<string, unknown> = {
          fullName: form.fullName.trim(),
          phone: form.phone.trim(),
          roleId: isRoot ? editUser.roleId : form.role,
          role: isRoot ? editUser.role : form.role,
          customPermissions: form.customPermissions,
          isActive: isRoot ? true : form.isActive,
        };

        // Ghi vào stores/{storeCode}/users/{uid}
        await update(ref(db, `stores/${cleanStore}/users/${targetUid}`), updateData);
        // Đồng bộ bản ghi username nếu có
        await update(ref(db, `stores/${cleanStore}/users/${cleanUser}`), updateData).catch(() => {});

        // Ghi Audit log
        const logId = `LOG_${Date.now()}_${Math.floor(Math.random() * 1000)}`;
        await set(ref(db, `stores/${cleanStore}/audit_logs/${logId}`), {
          action: "UPDATE_USER",
          targetType: "USER",
          targetId: targetUid,
          username: currentUser?.username || "admin",
          userFullName: currentUser?.fullName || "Quản trị viên",
          userRole: currentUser?.roleId || "ROLE_OWNER",
          details: `Cập nhật thông tin nhân viên: ${form.fullName.trim()} (@${cleanUser})`,
          timestamp: Date.now(),
        }).catch(() => {});

        closeModal();
      } else {
        // TẠO NHÂN VIÊN MỚI QUA CLOUD FUNCTIONS (An toàn tuyệt đối)
        const createStaffFn = httpsCallable<
          {
            storeCode: string;
            username: string;
            fullName: string;
            roleId: string;
            tempPassword: string;
            phone?: string;
            customPermissions?: string[];
          },
          { success: boolean; uid: string; message: string }
        >(functions, "createStaffAccount");

        await createStaffFn({
          storeCode: cleanStore,
          username: cleanUser,
          fullName: form.fullName.trim(),
          roleId: form.role,
          tempPassword: form.password.trim(),
          phone: form.phone.trim(),
          customPermissions: form.customPermissions,
        });

        closeModal();
      }
    } catch (e: unknown) {
      const err = e as { code?: string; message?: string };
      if (err.code === "already-exists" || err.message?.includes("đã tồn tại")) {
        setError(`Tên tài khoản @${cleanUser} đã tồn tại trong chi nhánh này`);
      } else {
        setError(err.message || "Lỗi khi lưu thông tin nhân viên");
      }
    } finally {
      setSaving(false);
    }
  };

  // Khóa / Mở tài khoản qua Cloud Functions (Đồng bộ Auth + RTDB)
  const handleToggleActive = useCallback(
    async (u: DashboardUser) => {
      // Sovereign Owner Rule: Không cho phép khóa tài khoản Chủ quán
      if (u.isRootOwner) {
        alert("Không thể khóa tài khoản Chủ quán tối cao.");
        return;
      }

      const newActive = !u.isActive;
      const targetStore = u.storeCode || activeStoreCode || "";
      if (!targetStore) {
        alert("Không xác định được chi nhánh của nhân viên.");
        return;
      }
      const targetUid = u.uid || u.id;

      try {
        const setStaffDisabledFn = httpsCallable<
          { storeCode: string; targetUid: string; disabled: boolean },
          { success: boolean; message: string }
        >(functions, "setStaffDisabled");

        await setStaffDisabledFn({
          storeCode: targetStore,
          targetUid: targetUid,
          disabled: !newActive,
        });
      } catch (err: unknown) {
        alert((err as Error)?.message || "Lỗi cập nhật trạng thái tài khoản");
      }
    },
    [activeStoreCode]
  );

  // Đặt lại mật khẩu nhân viên qua Cloud Functions
  const openResetPassword = (u: DashboardUser) => {
    setResetPasswordTarget(u);
    setNewPasswordInput("");
    setShowNewPassword(false);
    setResetPasswordError("");
  };

  const closeResetPassword = () => {
    setResetPasswordTarget(null);
    setNewPasswordInput("");
    setResetPasswordError("");
  };

  const handleConfirmResetPassword = async () => {
    if (!resetPasswordTarget) return;
    if (!newPasswordInput || newPasswordInput.length < 6) {
      setResetPasswordError("Mật khẩu mới phải có tối thiểu 6 ký tự.");
      return;
    }

    setResettingPassword(true);
    setResetPasswordError("");

    try {
      const targetStore = resetPasswordTarget.storeCode || activeStoreCode || "";
      if (!targetStore) throw new Error("Không xác định được chi nhánh của nhân viên.");
      const targetUid = resetPasswordTarget.uid || resetPasswordTarget.id;

      const resetFn = httpsCallable<
        { storeCode: string; targetUid: string; newPassword: string },
        { success: boolean; message: string }
      >(functions, "resetStaffPassword");

      await resetFn({
        storeCode: targetStore,
        targetUid: targetUid,
        newPassword: newPasswordInput,
      });

      alert(`Đã đặt lại mật khẩu cho tài khoản @${resetPasswordTarget.username}. Nhân viên sẽ bắt buộc đổi mật khẩu khi đăng nhập.`);
      closeResetPassword();
    } catch (err: unknown) {
      setResetPasswordError((err as Error)?.message || "Lỗi khi đặt lại mật khẩu nhân viên.");
    } finally {
      setResettingPassword(false);
    }
  };

  // Xóa tài khoản nhân viên
  const handleDelete = useCallback(async () => {
    if (!deleteTarget) return;

    if (deleteTarget.isRootOwner) {
      alert("Không thể xóa tài khoản Chủ quán tối cao.");
      setDeleteTarget(null);
      return;
    }

    const targetStore = deleteTarget.storeCode || activeStoreCode || "";
    if (!targetStore) {
      alert("Không xác định được chi nhánh của nhân viên.");
      return;
    }
    const targetUid = deleteTarget.uid || deleteTarget.id;

    try {
      await remove(ref(db, `stores/${targetStore}/users/${targetUid}`));
      await remove(ref(db, `stores/${targetStore}/users/${deleteTarget.username}`)).catch(() => {});

      const logId = `LOG_${Date.now()}_${Math.floor(Math.random() * 1000)}`;
      await set(ref(db, `stores/${targetStore}/audit_logs/${logId}`), {
        action: "DELETE_USER",
        targetType: "USER",
        targetId: targetUid,
        username: currentUser?.username || "admin",
        userFullName: currentUser?.fullName || "Quản trị viên",
        userRole: currentUser?.roleId || "ROLE_OWNER",
        details: `Xóa tài khoản nhân viên: ${deleteTarget.fullName} (@${deleteTarget.username})`,
        timestamp: Date.now(),
      }).catch(() => {});

      setDeleteTarget(null);
    } catch (err: unknown) {
      alert((err as Error)?.message || "Lỗi xóa tài khoản");
    }
  }, [deleteTarget, currentUser, activeStoreCode]);

  const handleExport = () => {
    // Chuyển format phù hợp cho exportUsers
    const listForExport = filteredUsers.map((u) => ({
      id: u.id,
      fullName: u.fullName,
      username: u.username,
      role: u.roleId || u.role,
      roleId: u.roleId,
      phone: u.phone,
      storeCode: u.storeCode,
      isActive: u.isActive,
    }));
    exportUsers(listForExport);
  };

  const getRoleBadge = (roleStr: string) => {
    const r = (roleStr || "").toUpperCase();
    if (r.includes("OWNER")) {
      return (
        <span className="badge badge-danger" style={{ display: "inline-flex", alignItems: "center", gap: "4px" }}>
          👑 Chủ Quán
        </span>
      );
    }
    if (r.includes("MANAGER_1")) {
      return (
        <span
          className="badge"
          style={{
            background: "rgba(245,158,11,0.15)",
            color: "var(--warning)",
            borderColor: "rgba(245,158,11,0.3)",
            display: "inline-flex",
            alignItems: "center",
            gap: "4px",
          }}
        >
          ⭐ Quản Lý 1
        </span>
      );
    }
    if (r.includes("MANAGER_2") || r === "ROLE_MANAGER") {
      return (
        <span
          className="badge"
          style={{
            background: "rgba(59,130,246,0.15)",
            color: "#2563EB",
            borderColor: "rgba(59,130,246,0.3)",
            display: "inline-flex",
            alignItems: "center",
            gap: "4px",
          }}
        >
          📋 Quản Lý 2
        </span>
      );
    }
    if (r.includes("CASHIER") || r.includes("THUNGAN")) {
      return (
        <span
          className="badge"
          style={{
            background: "rgba(16,185,129,0.15)",
            color: "#059669",
            borderColor: "rgba(16,185,129,0.3)",
            display: "inline-flex",
            alignItems: "center",
            gap: "4px",
          }}
        >
          💰 Thu Ngân
        </span>
      );
    }
    if (r.includes("KITCHEN") || r.includes("BEP")) {
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

  if (authLoading || (!canManageUsers && currentUser)) {
    return (
      <div style={{ display: "flex", alignItems: "center", justifyContent: "center", height: "60vh" }}>
        <div className="spinner" />
      </div>
    );
  }

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "24px" }}>
      {/* Header */}
      <div
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          flexWrap: "wrap",
          gap: "16px",
        }}
      >
        <div>
          <h1 className="section-title">Quản lý Tài khoản & Phân quyền 👥</h1>
          <p className="section-subtitle">
            Hệ thống xác thực Firebase Authentication &amp; Phân quyền đa chi nhánh ({currentUsers.length} tài khoản)
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

      {/* Store Filter Switcher */}
      {storesList.length > 0 && (
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
              borderColor: currentStoreCode === "ALL" ? "var(--primary)" : "var(--border)",
              background: currentStoreCode === "ALL" ? "var(--primary)" : "var(--surface)",
              color: currentStoreCode === "ALL" ? "#FFFFFF" : "var(--subtext)",
            }}
          >
            🌐 Tất cả chi nhánh ({Object.values(usersMap).reduce((acc, l) => acc + l.length, 0)} NV)
          </button>
          {storesList.map((s) => {
            const isSelected = currentStoreCode === s.storeCode;
            const count = (usersMap[s.storeCode] || []).length;
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
                  borderColor: isSelected ? "var(--primary)" : "var(--border)",
                  background: isSelected ? "var(--primary)" : "var(--surface)",
                  color: isSelected ? "#FFFFFF" : "var(--subtext)",
                }}
              >
                🏪 {s.storeName} ({count} NV)
              </button>
            );
          })}
        </div>
      )}

      {/* Stat Cards */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(min(200px, 100%), 1fr))", gap: "16px" }}>
        <div className="stat-card">
          <div
            style={{
              fontSize: "13px",
              color: "var(--muted)",
              fontWeight: "600",
              display: "flex",
              alignItems: "center",
              gap: "6px",
            }}
          >
            <Users size={16} color="#7E2930" /> Tổng nhân viên
          </div>
          <div style={{ fontSize: "24px", fontWeight: "800", color: "var(--text)", marginTop: "8px" }}>
            {stats.totalStaff}
          </div>
          <div style={{ fontSize: "12px", color: "#10B981", marginTop: "4px", fontWeight: "600" }}>
            ● {stats.activeStaff} đang hoạt động
          </div>
        </div>

        <div className="stat-card">
          <div
            style={{
              fontSize: "13px",
              color: "var(--muted)",
              fontWeight: "600",
              display: "flex",
              alignItems: "center",
              gap: "6px",
            }}
          >
            <ShieldCheck size={16} color="#F59E0B" /> Quản lý &amp; Chủ quán
          </div>
          <div style={{ fontSize: "24px", fontWeight: "800", color: "var(--warning)", marginTop: "8px" }}>
            {stats.managers}
          </div>
          <div style={{ fontSize: "12px", color: "var(--muted)", marginTop: "4px" }}>
            Quyền điều hành &amp; kiểm soát
          </div>
        </div>

        <div className="stat-card">
          <div
            style={{
              fontSize: "13px",
              color: "var(--muted)",
              fontWeight: "600",
              display: "flex",
              alignItems: "center",
              gap: "6px",
            }}
          >
            <Store size={16} color="#3B82F6" /> Nhân viên vận hành
          </div>
          <div style={{ fontSize: "24px", fontWeight: "800", color: "#3B82F6", marginTop: "8px" }}>
            {stats.totalStaff - stats.managers}
          </div>
          <div style={{ fontSize: "12px", color: "var(--muted)", marginTop: "4px" }}>
            Thu ngân, phục vụ, bếp/bar
          </div>
        </div>
      </div>

      {/* Search & Filter */}
      <div className="card" style={{ padding: "16px 20px" }}>
        <div
          style={{
            display: "flex",
            gap: "12px",
            flexWrap: "wrap",
            alignItems: "center",
            justifyContent: "space-between",
          }}
        >
          <div style={{ position: "relative", minWidth: "280px", flex: 1 }}>
            <Search
              size={16}
              style={{
                position: "absolute",
                left: "12px",
                top: "50%",
                transform: "translateY(-50%)",
                color: "var(--muted)",
              }}
            />
            <input
              className="input-field"
              placeholder="Tìm theo tên, tài khoản, SĐT..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              style={{ paddingLeft: "38px" }}
            />
          </div>

          <div style={{ display: "flex", gap: "8px", alignItems: "center" }}>
            <span style={{ fontSize: "13px", fontWeight: "600", color: "var(--muted)" }}>Vai trò:</span>
            <select
              className="input-field"
              style={{ width: "auto", minWidth: "180px" }}
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
              <th>Họ &amp; Tên</th>
              <th>Tài khoản (@username)</th>
              <th>Chi nhánh</th>
              <th>Vai trò</th>
              <th>Quyền riêng</th>
              <th>Trạng thái</th>
              <th>Lần đăng nhập cuối</th>
              <th style={{ textAlign: "right" }}>Thao tác</th>
            </tr>
          </thead>
          <tbody>
            {loadingUsers ? (
              <tr>
                <td colSpan={8} style={{ textAlign: "center", padding: "48px" }}>
                  <div className="spinner" style={{ margin: "0 auto" }} />
                </td>
              </tr>
            ) : filteredUsers.length === 0 ? (
              <tr>
                <td colSpan={8} style={{ textAlign: "center", padding: "48px", color: "var(--muted)" }}>
                  Không tìm thấy nhân viên nào phù hợp
                </td>
              </tr>
            ) : (
              filteredUsers.map((u) => (
                <tr key={`${u.storeCode}_${u.username}_${u.id}`}>
                  <td>
                    <div style={{ fontWeight: "700", color: "var(--text)" }}>{u.fullName}</div>
                    {u.phone && (
                      <div
                        style={{
                          fontSize: "12px",
                          color: "var(--muted)",
                          display: "flex",
                          alignItems: "center",
                          gap: "4px",
                          marginTop: "2px",
                        }}
                      >
                        <Phone size={11} /> {u.phone}
                      </div>
                    )}
                  </td>
                  <td>
                    <span
                      style={{
                        fontFamily: "monospace",
                        color: "var(--primary)",
                        fontWeight: "700",
                        fontSize: "13px",
                        background: "rgba(126,41,48,0.06)",
                        padding: "2px 8px",
                        borderRadius: "6px",
                      }}
                    >
                      @{u.username}
                    </span>
                    {u.mustChangePassword && (
                      <div style={{ fontSize: "10px", color: "var(--warning)", fontWeight: "600", marginTop: "2px" }}>
                        ⚡ Cần đổi MK lần đầu
                      </div>
                    )}
                  </td>
                  <td>
                    <span
                      className="badge"
                      style={{
                        fontSize: "12px",
                        background: "var(--surface-muted)",
                        color: "var(--subtext)",
                        borderColor: "var(--border)",
                      }}
                    >
                      🏪 {u.storeName || u.storeCode}
                    </span>
                  </td>
                  <td>{getRoleBadge(u.roleId || u.role)}</td>
                  <td>
                    {u.customPermissions && u.customPermissions.length > 0 ? (
                      <div style={{ display: "flex", gap: "4px", flexWrap: "wrap", maxWidth: "200px" }}>
                        {u.customPermissions.map((cp) => (
                          <span
                            key={cp}
                            style={{
                              fontSize: "10px",
                              padding: "2px 6px",
                              borderRadius: "4px",
                              background: "rgba(126,41,48,0.08)",
                              color: "var(--primary)",
                              fontWeight: "600",
                            }}
                          >
                            {cp}
                          </span>
                        ))}
                      </div>
                    ) : (
                      <span style={{ fontSize: "12px", color: "var(--muted)" }}>Mặc định vai trò</span>
                    )}
                  </td>
                  <td>
                    {u.isActive !== false ? (
                      <span
                        style={{
                          display: "inline-flex",
                          alignItems: "center",
                          gap: "6px",
                          fontSize: "12px",
                          color: "#10B981",
                          fontWeight: "600",
                        }}
                      >
                        <CheckCircle2 size={14} /> Hoạt động
                      </span>
                    ) : (
                      <span
                        style={{
                          display: "inline-flex",
                          alignItems: "center",
                          gap: "6px",
                          fontSize: "12px",
                          color: "#EF4444",
                          fontWeight: "600",
                        }}
                      >
                        <XCircle size={14} /> Đã khóa
                      </span>
                    )}
                  </td>
                  <td>
                    <div style={{ fontSize: "12px", color: "var(--subtext)", display: "flex", alignItems: "center", gap: "4px" }}>
                      <Clock size={12} color="#8B8FA8" />
                      {formatDateTime(u.lastLoginAt)}
                    </div>
                  </td>
                  <td style={{ textAlign: "right" }}>
                    <div style={{ display: "inline-flex", gap: "6px" }}>
                      {/* Nút Khóa / Mở */}
                      {!u.isRootOwner && (
                        <button
                          title={u.isActive !== false ? "Khóa tài khoản" : "Kích hoạt lại tài khoản"}
                          onClick={() => handleToggleActive(u)}
                          style={{
                            padding: "6px 8px",
                            borderRadius: "8px",
                            background: u.isActive !== false ? "rgba(245,158,11,0.1)" : "rgba(16,185,129,0.1)",
                            border: `1px solid ${
                              u.isActive !== false ? "rgba(245,158,11,0.3)" : "rgba(16,185,129,0.3)"
                            }`,
                            color: u.isActive !== false ? "var(--warning)" : "#10B981",
                            cursor: "pointer",
                          }}
                        >
                          {u.isActive !== false ? <UserX size={15} /> : <UserCheck size={15} />}
                        </button>
                      )}

                      {/* Nút Sửa */}
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

                      {/* Nút Đặt lại mật khẩu */}
                      {(!u.isRootOwner || currentUser?.isRootOwner) && (
                        <button
                          title="Đặt lại mật khẩu nhân viên"
                          onClick={() => openResetPassword(u)}
                          style={{
                            padding: "6px 8px",
                            borderRadius: "8px",
                            background: "rgba(139, 92, 246, 0.1)",
                            border: "1px solid rgba(139, 92, 246, 0.3)",
                            color: "#8B5CF6",
                            cursor: "pointer",
                          }}
                        >
                          <KeyRound size={15} />
                        </button>
                      )}

                      {/* Nút Xóa (Bảo vệ Chủ quán tối cao) */}
                      {!u.isRootOwner && (
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
                      )}
                    </div>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {/* Modal Thêm / Sửa nhân viên */}
      {showModal && (
        <div className="modal-overlay" onClick={closeModal}>
          <div
            className="modal-content"
            style={{ maxWidth: "560px", maxHeight: "90vh", overflowY: "auto" }}
            onClick={(e) => e.stopPropagation()}
          >
            <div
              style={{
                padding: "20px 24px 0",
                display: "flex", flexWrap: "wrap", rowGap: "8px",
                alignItems: "center",
                justifyContent: "space-between",
                marginBottom: "16px",
              }}
            >
              <div>
                <h2 style={{ fontSize: "18px", fontWeight: "700", color: "var(--text)" }}>
                  {editUser ? "Chỉnh sửa thông tin nhân viên" : "Thêm nhân viên mới"}
                </h2>
                <p style={{ fontSize: "12px", color: "var(--muted)", marginTop: "2px" }}>
                  Xác thực danh tính an toàn qua Firebase Auth &bull; Không lưu mật khẩu thô
                </p>
              </div>
              <button
                onClick={closeModal}
                style={{ background: "none", border: "none", color: "var(--muted)", cursor: "pointer" }}
              >
                <X size={20} />
              </button>
            </div>

            <div style={{ padding: "0 24px 24px", display: "flex", flexDirection: "column", gap: "14px" }}>
              {/* Họ & Tên */}
              <div>
                <label
                  style={{ display: "block", fontSize: "13px", fontWeight: "600", color: "var(--text)", marginBottom: "6px" }}
                >
                  Họ và tên nhân viên *
                </label>
                <input
                  className="input-field"
                  placeholder="Ví dụ: Nguyễn Thu Ngân"
                  value={form.fullName}
                  onChange={(e) => setForm((f) => ({ ...f, fullName: e.target.value }))}
                />
              </div>

              {/* Username & Phone */}
              <div className="grid-stack-sm" style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "12px" }}>
                <div>
                  <label
                    style={{
                      display: "block",
                      fontSize: "13px",
                      fontWeight: "600",
                      color: "var(--text)",
                      marginBottom: "6px",
                    }}
                  >
                    Tên đăng nhập *
                  </label>
                  <input
                    className="input-field"
                    placeholder="ví dụ: thungan1"
                    value={form.username}
                    disabled={!!editUser}
                    onChange={(e) =>
                      setForm((f) => ({
                        ...f,
                        username: e.target.value.toLowerCase().trim(),
                      }))
                    }
                    style={{ background: editUser ? "var(--surface-muted)" : undefined, cursor: editUser ? "not-allowed" : undefined }}
                  />
                  {editUser ? (
                    <span style={{ fontSize: "11px", color: "var(--muted)" }}>Không thể đổi tên đăng nhập</span>
                  ) : (
                    <span style={{ fontSize: "11px", color: "var(--muted)" }}>3-30 ký tự (a-z, 0-9, _, -)</span>
                  )}
                </div>

                <div>
                  <label
                    style={{
                      display: "block",
                      fontSize: "13px",
                      fontWeight: "600",
                      color: "var(--text)",
                      marginBottom: "6px",
                    }}
                  >
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

              {/* Password khi tạo mới */}
              {!editUser && (
                <div>
                  <label
                    style={{
                      display: "block",
                      fontSize: "13px",
                      fontWeight: "600",
                      color: "var(--text)",
                      marginBottom: "6px",
                    }}
                  >
                    Mật khẩu khởi tạo * (Nhân viên phải đổi ở lần đăng nhập đầu)
                  </label>
                  <div style={{ position: "relative" }}>
                    <input
                      type={showPassword ? "text" : "password"}
                      className="input-field"
                      placeholder="Tối thiểu 6 ký tự"
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
                        color: "var(--muted)",
                        cursor: "pointer",
                      }}
                    >
                      {showPassword ? <EyeOff size={16} /> : <Eye size={16} />}
                    </button>
                  </div>
                </div>
              )}

              {/* Chi nhánh */}
              <div>
                <label
                  style={{ display: "block", fontSize: "13px", fontWeight: "600", color: "var(--text)", marginBottom: "6px" }}
                >
                  Chi nhánh làm việc *
                </label>
                <select
                  className="input-field"
                  value={form.storeCode}
                  disabled={!!editUser}
                  onChange={(e) => setForm((f) => ({ ...f, storeCode: e.target.value }))}
                  style={{ background: editUser ? "var(--surface-muted)" : undefined }}
                >
                  {storesList.map((s) => (
                    <option key={s.storeCode} value={s.storeCode}>
                      🏪 {s.storeName} ({s.storeCode})
                    </option>
                  ))}
                </select>
              </div>

              {/* Vai trò chuẩn */}
              <div>
                <label
                  style={{ display: "block", fontSize: "13px", fontWeight: "600", color: "var(--text)", marginBottom: "6px" }}
                >
                  Vai trò &amp; Phân quyền chuẩn *
                </label>
                <div style={{ display: "flex", flexDirection: "column", gap: "8px" }}>
                  {UNIFIED_ROLES.map((r) => {
                    const isSelected = form.role === r.id;
                    const isRoot = editUser?.isRootOwner === true;
                    return (
                      <div
                        key={r.id}
                        onClick={() => {
                          if (!isRoot) setForm((f) => ({ ...f, role: r.id }));
                        }}
                        style={{
                          padding: "10px 14px",
                          borderRadius: "10px",
                          border: `1.5px solid ${isSelected ? "#7E2930" : "#E6DEC8"}`,
                          background: isSelected ? "rgba(126,41,48,0.04)" : "var(--surface)",
                          cursor: isRoot ? "not-allowed" : "pointer",
                          display: "flex", flexWrap: "wrap", rowGap: "8px",
                          alignItems: "center",
                          justifyContent: "space-between",
                          transition: "all 0.15s ease",
                          opacity: isRoot && !isSelected ? 0.5 : 1,
                        }}
                      >
                        <div>
                          <div
                            style={{
                              fontWeight: "700",
                              color: isSelected ? "var(--primary)" : "var(--text)",
                              fontSize: "13px",
                              display: "flex",
                              alignItems: "center",
                              gap: "6px",
                            }}
                          >
                            <span>{r.icon}</span> {r.name}
                          </div>
                          <div style={{ fontSize: "11px", color: "var(--muted)", marginTop: "2px" }}>{r.desc}</div>
                        </div>
                        <input
                          type="radio"
                          name="user_role"
                          checked={isSelected}
                          disabled={isRoot}
                          onChange={() => {
                            if (!isRoot) setForm((f) => ({ ...f, role: r.id }));
                          }}
                          style={{ accentColor: "#7E2930", cursor: "pointer" }}
                        />
                      </div>
                    );
                  })}
                </div>
              </div>

              {/* Quyền riêng biệt bổ sung (customPermissions) */}
              <div>
                <label
                  style={{ display: "block", fontSize: "13px", fontWeight: "600", color: "var(--text)", marginBottom: "6px" }}
                >
                  Quyền bổ sung riêng lẻ (Custom Permissions)
                </label>
                <div
                  style={{
                    display: "grid",
                    gridTemplateColumns: "1fr 1fr",
                    gap: "8px",
                    background: "var(--surface-muted)",
                    padding: "12px",
                    borderRadius: "10px",
                    border: "1px solid var(--border)",
                  }}
                >
                  {AVAILABLE_CUSTOM_PERMISSIONS.map((perm) => {
                    const checked = form.customPermissions.includes(perm.id);
                    return (
                      <label
                        key={perm.id}
                        style={{
                          display: "flex",
                          alignItems: "flex-start",
                          gap: "8px",
                          fontSize: "12px",
                          cursor: "pointer",
                        }}
                      >
                        <input
                          type="checkbox"
                          checked={checked}
                          onChange={() => toggleCustomPermission(perm.id)}
                          style={{ marginTop: "2px", accentColor: "#7E2930" }}
                        />
                        <div>
                          <div style={{ fontWeight: "600", color: "var(--text)" }}>{perm.label}</div>
                          <div style={{ fontSize: "10px", color: "var(--muted)" }}>{perm.desc}</div>
                        </div>
                      </label>
                    );
                  })}
                </div>
              </div>

              {/* Active Toggle */}
              <div style={{ display: "flex", alignItems: "center", gap: "10px", padding: "4px 0" }}>
                <input
                  type="checkbox"
                  id="user_is_active_form"
                  checked={form.isActive}
                  disabled={editUser?.isRootOwner === true}
                  onChange={(e) => setForm((f) => ({ ...f, isActive: e.target.checked }))}
                  style={{ width: "18px", height: "18px", accentColor: "#7E2930", cursor: "pointer" }}
                />
                <label
                  htmlFor="user_is_active_form"
                  style={{ fontSize: "13px", fontWeight: "600", color: "var(--text)", cursor: "pointer" }}
                >
                  Kích hoạt tài khoản (cho phép đăng nhập hệ thống)
                </label>
              </div>

              {/* Error */}
              {error && (
                <div
                  style={{
                    background: "rgba(239,68,68,0.1)",
                    border: "1px solid rgba(239,68,68,0.3)",
                    borderRadius: "8px",
                    padding: "10px 14px",
                    color: "#EF4444",
                    fontSize: "13px",
                  }}
                >
                  {error}
                </div>
              )}

              {/* Actions */}
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
                    <div
                      style={{
                        width: "16px",
                        height: "16px",
                        border: "2px solid rgba(255,255,255,0.3)",
                        borderTopColor: "white",
                        borderRadius: "50%",
                        animation: "spin 0.7s linear infinite",
                      }}
                    />
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

      {/* Modal Xóa Nhân viên */}
      {deleteTarget && (
        <div className="modal-overlay" onClick={() => setDeleteTarget(null)}>
          <div className="modal-content" style={{ maxWidth: "420px" }} onClick={(e) => e.stopPropagation()}>
            <div style={{ padding: "28px", textAlign: "center" }}>
              <div style={{ display: "flex", justifyContent: "center", marginBottom: "16px" }}>
                <ShieldAlert size={48} color="#EF4444" />
              </div>
              <h2 style={{ fontSize: "18px", fontWeight: "700", color: "var(--text)", marginBottom: "8px" }}>
                Xác nhận xóa nhân viên
              </h2>
              <p style={{ color: "var(--muted)", fontSize: "14px", lineHeight: "1.5", marginBottom: "20px" }}>
                Bạn có chắc chắn muốn xóa nhân viên{" "}
                <strong style={{ color: "var(--text)" }}>{deleteTarget.fullName}</strong> (@{deleteTarget.username}) thuộc
                chi nhánh <strong style={{ color: "var(--text)" }}>{deleteTarget.storeCode}</strong> khỏi hệ thống?
              </p>
              <div style={{ display: "flex", gap: "10px" }}>
                <button
                  className="btn-secondary"
                  onClick={() => setDeleteTarget(null)}
                  style={{ flex: 1, justifyContent: "center" }}
                >
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

      {/* Modal Đặt lại Mật khẩu Nhân viên */}
      {resetPasswordTarget && (
        <div className="modal-overlay" onClick={closeResetPassword}>
          <div className="modal-content" style={{ maxWidth: "440px" }} onClick={(e) => e.stopPropagation()}>
            <div style={{ padding: "24px" }}>
              <div style={{ display: "flex", flexWrap: "wrap", rowGap: "8px", justifyContent: "space-between", alignItems: "center", marginBottom: "16px" }}>
                <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
                  <div style={{ width: "36px", height: "36px", borderRadius: "8px", background: "rgba(139, 92, 246, 0.1)", display: "flex", alignItems: "center", justifyContent: "center" }}>
                    <KeyRound size={20} color="#8B5CF6" />
                  </div>
                  <h2 style={{ fontSize: "17px", fontWeight: "700", color: "var(--text)" }}>
                    Đặt lại mật khẩu
                  </h2>
                </div>
                <button
                  onClick={closeResetPassword}
                  style={{ background: "none", border: "none", cursor: "pointer", color: "var(--muted)" }}
                >
                  <X size={20} />
                </button>
              </div>

              <div style={{ background: "var(--surface-muted)", padding: "12px 14px", borderRadius: "8px", marginBottom: "16px", border: "1px solid var(--border)" }}>
                <div style={{ fontSize: "13px", color: "var(--muted)" }}>Tài khoản nhân viên:</div>
                <div style={{ fontSize: "14px", fontWeight: "700", color: "var(--text)", marginTop: "2px" }}>
                  {resetPasswordTarget.fullName} <span style={{ color: "var(--muted)", fontWeight: "500" }}>@{resetPasswordTarget.username}</span>
                </div>
                <div style={{ fontSize: "12px", color: "var(--muted)", marginTop: "2px" }}>
                  Chi nhánh: <strong style={{ color: "#0F172A" }}>{resetPasswordTarget.storeCode || activeStoreCode}</strong>
                </div>
              </div>

              <div style={{ marginBottom: "16px" }}>
                <label style={{ display: "block", fontSize: "13px", fontWeight: "600", color: "#334155", marginBottom: "6px" }}>
                  Mật khẩu mới <span style={{ color: "#EF4444" }}>*</span>
                </label>
                <div style={{ position: "relative" }}>
                  <input
                    type={showNewPassword ? "text" : "password"}
                    value={newPasswordInput}
                    onChange={(e) => setNewPasswordInput(e.target.value)}
                    placeholder="Nhập mật khẩu mới (tối thiểu 6 ký tự)"
                    style={{
                      width: "100%",
                      padding: "10px 40px 10px 12px",
                      borderRadius: "8px",
                      border: "1px solid var(--border)",
                      fontSize: "14px",
                      outline: "none",
                    }}
                  />
                  <button
                    type="button"
                    onClick={() => setShowNewPassword(!showNewPassword)}
                    style={{
                      position: "absolute",
                      right: "10px",
                      top: "50%",
                      transform: "translateY(-50%)",
                      background: "none",
                      border: "none",
                      cursor: "pointer",
                      color: "var(--muted)",
                    }}
                  >
                    {showNewPassword ? <EyeOff size={18} /> : <Eye size={18} />}
                  </button>
                </div>
                <p style={{ fontSize: "12px", color: "var(--muted)", marginTop: "6px" }}>
                  * Nhân viên sẽ bắt buộc phải đổi mật khẩu ở lần đăng nhập tiếp theo.
                </p>
              </div>

              {resetPasswordError && (
                <div style={{ background: "var(--danger-bg)", border: "1px solid #FCA5A5", borderRadius: "8px", padding: "10px 12px", color: "var(--danger)", fontSize: "13px", marginBottom: "16px" }}>
                  {resetPasswordError}
                </div>
              )}

              <div style={{ display: "flex", gap: "10px" }}>
                <button
                  className="btn-secondary"
                  onClick={closeResetPassword}
                  style={{ flex: 1, justifyContent: "center" }}
                >
                  Hủy bỏ
                </button>
                <button
                  className="btn-primary"
                  onClick={handleConfirmResetPassword}
                  disabled={resettingPassword}
                  style={{ flex: 1, justifyContent: "center", background: "#8B5CF6", borderColor: "#8B5CF6" }}
                >
                  {resettingPassword ? "Đang xử lý..." : "Xác nhận đặt lại"}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
