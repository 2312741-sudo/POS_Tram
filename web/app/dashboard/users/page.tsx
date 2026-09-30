"use client";
import { useEffect, useState, useMemo } from "react";
import { db } from "@/lib/firebase";
import { ref, onValue, push, update, remove } from "firebase/database";
import { Search, Download, Plus, Edit2, Trash2, X, Check, Trophy, Users, TrendingUp } from "lucide-react";
import { exportUsers } from "@/lib/export";

function formatVND(amount: number) {
  return new Intl.NumberFormat("vi-VN", { style: "currency", currency: "VND" }).format(amount);
}

interface User {
  id: string;
  fullName: string;
  username: string;
  password?: string;
  role: string;
  totalSales?: number;
  totalOrders?: number;
}

interface UserForm {
  fullName: string;
  username: string;
  password: string;
  role: string;
}

const emptyForm: UserForm = { fullName: "", username: "", password: "", role: "STAFF" };
const ROLES = ["MANAGER", "STAFF", "KITCHEN"];

import { useDashboardData } from "@/lib/data-context";

export default function UsersPage() {
  const { usersList: users, historyData, loading: ctxLoading } = useDashboardData();
  const loading = ctxLoading && users.length === 0;
  const [search, setSearch] = useState("");
  const [showModal, setShowModal] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [form, setForm] = useState<UserForm>(emptyForm);
  const [saving, setSaving] = useState(false);
  const [deleteId, setDeleteId] = useState<string | null>(null);
  const [error, setError] = useState("");

  const usersWithStats = useMemo(() => {
    return users.map((u) => {
      const userOrders = historyData.filter((h) => h.username === u.username || h.createdBy === u.username);
      const totalSales = userOrders.reduce((s, h) => s + (Number(h.totalAmount) || 0), 0);
      return { ...u, totalSales, totalOrders: userOrders.length };
    }).sort((a, b) => (b.totalSales || 0) - (a.totalSales || 0));
  }, [users, historyData]);

  const filtered = useMemo(() => {
    return usersWithStats.filter((u) =>
      !search ||
      u.fullName.toLowerCase().includes(search.toLowerCase()) ||
      u.username.toLowerCase().includes(search.toLowerCase())
    );
  }, [usersWithStats, search]);

  const openAdd = () => {
    setEditId(null);
    setForm(emptyForm);
    setError("");
    setShowModal(true);
  };

  const openEdit = (u: User) => {
    setEditId(u.id);
    setForm({ fullName: u.fullName, username: u.username, password: u.password || "", role: u.role });
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
    if (!form.fullName.trim()) { setError("Vui lòng nhập họ tên"); return; }
    if (!form.username.trim()) { setError("Vui lòng nhập tài khoản"); return; }
    if (!editId && !form.password.trim()) { setError("Vui lòng nhập mật khẩu"); return; }
    setSaving(true);
    setError("");
    try {
      const data: any = { fullName: form.fullName.trim(), username: form.username.trim(), role: form.role };
      if (form.password.trim()) data.password = form.password.trim();
      if (editId) {
        await update(ref(db, `users/${editId}`), data);
      } else {
        await push(ref(db, "users"), data);
      }
      closeModal();
    } catch (e: any) {
      setError(e.message || "Lỗi lưu dữ liệu");
    }
    setSaving(false);
  };

  const handleDelete = async (id: string) => {
    try {
      await remove(ref(db, `users/${id}`));
      setDeleteId(null);
    } catch {}
  };

  const handleExport = () => {
    exportUsers(filtered);
  };

  const getRoleBadge = (role: string) => {
    switch (role) {
      case "MANAGER": return <span className="badge badge-danger">👑 {role}</span>;
      case "KITCHEN": return <span className="badge badge-warning">🍳 {role}</span>;
      default: return <span className="badge badge-info">👤 {role}</span>;
    }
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
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <div>
          <h1 className="section-title">Quản lý Nhân viên 👥</h1>
          <p className="section-subtitle">{users.length} nhân viên</p>
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

      {/* Top 3 */}
      {usersWithStats.slice(0, 3).some(u => u.totalSales > 0) && (
        <div style={{ display: "grid", gridTemplateColumns: "repeat(3,1fr)", gap: "16px" }}>
          {usersWithStats.slice(0, 3).map((u, i) => (
            <div key={u.id} className="stat-card" style={{ borderColor: i === 0 ? "rgba(255,182,39,0.4)" : "rgba(45,49,71,1)" }}>
              <div style={{ display: "flex", alignItems: "center", gap: "12px", marginBottom: "12px" }}>
                <span style={{ fontSize: "24px" }}>{getRankIcon(i)}</span>
                <div>
                  <div style={{ fontWeight: "700", color: "#1C1A2D" }}>{u.fullName}</div>
                  <div>{getRoleBadge(u.role)}</div>
                </div>
              </div>
              <div style={{ fontSize: "18px", fontWeight: "800", color: "#7E2930" }}>{formatVND(u.totalSales || 0)}</div>
              <div style={{ fontSize: "12px", color: "#8B8FA8", marginTop: "2px" }}>{u.totalOrders || 0} đơn hàng</div>
            </div>
          ))}
        </div>
      )}

      {/* Search */}
      <div className="card" style={{ padding: "16px 20px" }}>
        <div style={{ position: "relative", maxWidth: "400px" }}>
          <Search size={16} style={{ position: "absolute", left: "12px", top: "50%", transform: "translateY(-50%)", color: "#8B8FA8" }} />
          <input
            className="input-field"
            placeholder="Tìm tên, tài khoản..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            style={{ paddingLeft: "38px" }}
          />
        </div>
      </div>

      {/* Table */}
      <div className="table-wrapper">
        <table>
          <thead>
            <tr>
              <th>Hạng</th>
              <th>Họ tên</th>
              <th>Tài khoản</th>
              <th>Vai trò</th>
              <th>Doanh số</th>
              <th>Số đơn</th>
              <th>Thao tác</th>
            </tr>
          </thead>
          <tbody>
            {filtered.length === 0 ? (
              <tr>
                <td colSpan={7} style={{ textAlign: "center", padding: "48px", color: "#8B8FA8" }}>
                  Không có nhân viên
                </td>
              </tr>
            ) : (
              filtered.map((u, i) => (
                <tr key={u.id + '-' + i}>
                  <td style={{ textAlign: "center", fontSize: "20px" }}>{getRankIcon(i)}</td>
                  <td style={{ fontWeight: "600" }}>{u.fullName}</td>
                  <td>
                    <span style={{ fontFamily: "monospace", color: "#8B8FA8", fontSize: "13px" }}>{u.username}</span>
                  </td>
                  <td>{getRoleBadge(u.role)}</td>
                  <td style={{ fontWeight: "700", color: "#7E2930" }}>{formatVND(u.totalSales || 0)}</td>
                  <td style={{ color: "#5D5B63" }}>{u.totalOrders || 0}</td>
                  <td>
                    <div style={{ display: "flex", gap: "8px" }}>
                      <button
                        onClick={() => openEdit(u)}
                        style={{ padding: "6px", borderRadius: "8px", background: "rgba(59,130,246,0.1)", border: "1px solid rgba(59,130,246,0.3)", color: "#3B82F6", cursor: "pointer" }}
                      >
                        <Edit2 size={15} />
                      </button>
                      <button
                        onClick={() => setDeleteId(u.id)}
                        style={{ padding: "6px", borderRadius: "8px", background: "rgba(239,68,68,0.1)", border: "1px solid rgba(239,68,68,0.3)", color: "#EF4444", cursor: "pointer" }}
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

      {/* Add/Edit Modal */}
      {showModal && (
        <div className="modal-overlay" onClick={closeModal}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()}>
            <div style={{ padding: "24px 24px 0", display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: "20px" }}>
              <h2 style={{ fontSize: "18px", fontWeight: "700", color: "#1C1A2D" }}>
                {editId ? "Chỉnh sửa nhân viên" : "Thêm nhân viên"}
              </h2>
              <button onClick={closeModal} style={{ background: "none", border: "none", color: "#8B8FA8", cursor: "pointer" }}>
                <X size={20} />
              </button>
            </div>
            <div style={{ padding: "0 24px 24px", display: "flex", flexDirection: "column", gap: "14px" }}>
              {[
                { label: "Họ tên *", key: "fullName" as const, placeholder: "Nhập họ và tên" },
                { label: "Tài khoản *", key: "username" as const, placeholder: "Nhập username" },
                { label: editId ? "Mật khẩu mới (để trống nếu không đổi)" : "Mật khẩu *", key: "password" as const, placeholder: "Nhập mật khẩu", type: "password" },
              ].map((field) => (
                <div key={field.key}>
                  <label style={{ display: "block", fontSize: "13px", fontWeight: "600", color: "#8B8FA8", marginBottom: "6px" }}>{field.label}</label>
                  <input
                    type={field.type || "text"}
                    className="input-field"
                    placeholder={field.placeholder}
                    value={form[field.key]}
                    onChange={(e) => setForm((f) => ({ ...f, [field.key]: e.target.value }))}
                  />
                </div>
              ))}
              <div>
                <label style={{ display: "block", fontSize: "13px", fontWeight: "600", color: "#8B8FA8", marginBottom: "6px" }}>Vai trò</label>
                <select className="input-field" value={form.role} onChange={(e) => setForm((f) => ({ ...f, role: e.target.value }))}>
                  {ROLES.map((r) => <option key={r} value={r}>{r}</option>)}
                </select>
              </div>
              {error && (
                <div style={{ background: "rgba(239,68,68,0.1)", border: "1px solid rgba(239,68,68,0.3)", borderRadius: "8px", padding: "10px 14px", color: "#EF4444", fontSize: "13px" }}>
                  {error}
                </div>
              )}
              <div style={{ display: "flex", gap: "10px", marginTop: "8px" }}>
                <button className="btn-secondary" onClick={closeModal} style={{ flex: 1, justifyContent: "center" }}>Hủy</button>
                <button className="btn-primary" onClick={handleSave} disabled={saving} style={{ flex: 1, justifyContent: "center", opacity: saving ? 0.7 : 1 }}>
                  {saving ? <div style={{ width: "16px", height: "16px", border: "2px solid rgba(255,255,255,0.3)", borderTopColor: "white", borderRadius: "50%", animation: "spin 0.7s linear infinite" }} /> : <Check size={16} />}
                  {editId ? "Cập nhật" : "Thêm mới"}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Delete Confirm */}
      {deleteId && (
        <div className="modal-overlay" onClick={() => setDeleteId(null)}>
          <div className="modal-content" style={{ maxWidth: "380px" }} onClick={(e) => e.stopPropagation()}>
            <div style={{ padding: "28px", textAlign: "center" }}>
              <div style={{ fontSize: "48px", marginBottom: "16px" }}>⚠️</div>
              <h2 style={{ fontSize: "18px", fontWeight: "700", color: "#1C1A2D", marginBottom: "8px" }}>Xác nhận xóa</h2>
              <p style={{ color: "#8B8FA8", fontSize: "14px", marginBottom: "24px" }}>Bạn có chắc muốn xóa nhân viên này?</p>
              <div style={{ display: "flex", gap: "10px" }}>
                <button className="btn-secondary" onClick={() => setDeleteId(null)} style={{ flex: 1, justifyContent: "center" }}>Hủy</button>
                <button className="btn-danger" onClick={() => handleDelete(deleteId)} style={{ flex: 1, justifyContent: "center" }}>
                  <Trash2 size={16} />
                  Xóa
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
