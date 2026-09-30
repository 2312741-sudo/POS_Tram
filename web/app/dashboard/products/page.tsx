"use client";
import { useState, useMemo } from "react";
import { Search, Download, Plus, Edit2, Trash2, Filter, X, Check, Store } from "lucide-react";
import { exportProducts } from "@/lib/export";
import { useDashboardData, ProductItem } from "@/lib/data-context";

function formatVND(amount: number) {
  return new Intl.NumberFormat("vi-VN", { style: "currency", currency: "VND" }).format(amount);
}

interface ProductFormData {
  name: string;
  price: string;
  unit: string;
  category: string;
  imageBase64: string;
  storeCode: string;
}

const emptyForm: ProductFormData = {
  name: "",
  price: "",
  unit: "",
  category: "",
  imageBase64: "",
  storeCode: "TRAM01",
};

export default function ProductsPage() {
  const {
    products,
    allProducts,
    categories,
    stores,
    currentStoreCode,
    setCurrentStoreCode,
    saveProduct,
    deleteProduct,
    loading: ctxLoading,
  } = useDashboardData();

  const loading = ctxLoading && products.length === 0;
  const [search, setSearch] = useState("");
  const [filterCategory, setFilterCategory] = useState("");
  const [showModal, setShowModal] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);
  const [form, setForm] = useState<ProductFormData>(emptyForm);
  const [saving, setSaving] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<ProductItem | null>(null);
  const [error, setError] = useState("");

  const filtered = useMemo(() => {
    return products.filter((p) => {
      const matchSearch = !search || p.name.toLowerCase().includes(search.toLowerCase());
      const matchCat = !filterCategory || p.category === filterCategory;
      return matchSearch && matchCat;
    });
  }, [products, search, filterCategory]);

  const openAdd = () => {
    setEditId(null);
    setForm({
      ...emptyForm,
      storeCode: currentStoreCode !== "ALL" ? currentStoreCode : (stores[0]?.storeCode || "TRAM01"),
    });
    setError("");
    setShowModal(true);
  };

  const openEdit = (p: ProductItem) => {
    setEditId(p.id);
    setForm({
      name: p.name,
      price: String(p.price),
      unit: p.unit || "",
      category: p.category || "",
      imageBase64: p.imageBase64 || "",
      storeCode: p.storeCode || (currentStoreCode !== "ALL" ? currentStoreCode : "TRAM01"),
    });
    setError("");
    setShowModal(true);
  };

  const handleImageChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      if (file.size > 2 * 1024 * 1024) {
        setError("Kích thước ảnh quá lớn, vui lòng chọn ảnh < 2MB");
        return;
      }
      const reader = new FileReader();
      reader.onloadend = () => {
        setForm((f) => ({ ...f, imageBase64: reader.result as string }));
      };
      reader.readAsDataURL(file);
    }
  };

  const closeModal = () => {
    setShowModal(false);
    setEditId(null);
    setForm(emptyForm);
    setError("");
  };

  const handleSave = async () => {
    if (!form.name.trim()) {
      setError("Vui lòng nhập tên sản phẩm");
      return;
    }
    if (!form.price || isNaN(Number(form.price)) || Number(form.price) < 0) {
      setError("Giá không hợp lệ");
      return;
    }
    setSaving(true);
    setError("");
    try {
      const targetStore = form.storeCode || (currentStoreCode !== "ALL" ? currentStoreCode : "TRAM01");
      const res = await saveProduct(
        {
          id: editId || undefined,
          name: form.name.trim(),
          price: Number(form.price),
          unit: form.unit.trim(),
          category: form.category.trim(),
          imageBase64: form.imageBase64,
        },
        targetStore
      );
      if (!res.success) {
        setError(res.error || "Lỗi lưu dữ liệu");
        setSaving(false);
        return;
      }
      closeModal();
    } catch (e: any) {
      setError(e.message || "Lỗi lưu dữ liệu");
    }
    setSaving(false);
  };

  const handleDelete = async () => {
    if (!deleteTarget) return;
    try {
      await deleteProduct(deleteTarget.id, deleteTarget.storeCode);
      setDeleteTarget(null);
    } catch {}
  };

  const handleExport = () => {
    exportProducts(filtered);
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
          <h1 className="section-title">Quản lý Sản phẩm & Thực đơn 🍜</h1>
          <p className="section-subtitle">
            {currentStoreCode === "ALL"
              ? `Toàn hệ thống: ${filtered.length} món (${stores.length} chi nhánh)`
              : `Chi nhánh ${currentStoreCode}: ${filtered.length} món`}
          </p>
        </div>
        <div style={{ display: "flex", gap: "10px" }}>
          <button className="btn-secondary" onClick={handleExport}>
            <Download size={16} />
            Xuất Excel
          </button>
          <button className="btn-primary" onClick={openAdd}>
            <Plus size={16} />
            Thêm sản phẩm
          </button>
        </div>
      </div>

      {/* Store Quick Switcher Tabs */}
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
            🌐 Tất cả chi nhánh ({allProducts.length})
          </button>
          {stores.map((s) => {
            const isSelected = currentStoreCode === s.storeCode;
            const count = allProducts.filter((p) => p.storeCode === s.storeCode).length;
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
                🏪 {s.storeName} ({count})
              </button>
            );
          })}
        </div>
      )}

      {/* Filters */}
      <div className="card" style={{ padding: "16px 20px" }}>
        <div style={{ display: "flex", gap: "12px", flexWrap: "wrap", alignItems: "center" }}>
          <div style={{ position: "relative", flex: "1", minWidth: "220px" }}>
            <Search size={16} style={{ position: "absolute", left: "12px", top: "50%", transform: "translateY(-50%)", color: "#8B8FA8" }} />
            <input
              className="input-field"
              placeholder="Tìm tên sản phẩm..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              style={{ paddingLeft: "38px" }}
            />
          </div>
          <div style={{ position: "relative" }}>
            <Filter size={16} style={{ position: "absolute", left: "12px", top: "50%", transform: "translateY(-50%)", color: "#8B8FA8" }} />
            <select
              className="input-field"
              value={filterCategory}
              onChange={(e) => setFilterCategory(e.target.value)}
              style={{ paddingLeft: "38px", minWidth: "200px" }}
            >
              <option value="">Tất cả danh mục ({categories.length})</option>
              {categories.map((c, i) => (
                <option key={c.id + "-" + i} value={c.name}>
                  {c.name}
                </option>
              ))}
            </select>
          </div>
        </div>
      </div>

      {/* Table */}
      <div className="table-wrapper">
        <table>
          <thead>
            <tr>
              <th>#</th>
              <th>Tên sản phẩm</th>
              {currentStoreCode === "ALL" && <th>Chi nhánh</th>}
              <th>Danh mục</th>
              <th>Giá</th>
              <th>Đơn vị</th>
              <th>Thao tác</th>
            </tr>
          </thead>
          <tbody>
            {filtered.length === 0 ? (
              <tr>
                <td colSpan={currentStoreCode === "ALL" ? 7 : 6} style={{ textAlign: "center", padding: "48px", color: "#8B8FA8" }}>
                  Không có sản phẩm nào
                </td>
              </tr>
            ) : (
              filtered.map((p, i) => (
                <tr key={`${p.storeCode || "TRAM01"}_${p.id}`}>
                  <td style={{ color: "#8B8FA8" }}>{i + 1}</td>
                  <td>
                    <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
                      {p.imageBase64 ? (
                        <img
                          src={p.imageBase64}
                          alt={p.name}
                          style={{ width: "36px", height: "36px", borderRadius: "8px", objectFit: "cover" }}
                        />
                      ) : (
                        <div
                          style={{
                            width: "36px",
                            height: "36px",
                            borderRadius: "8px",
                            background: "#FAF7F2",
                            border: "1px solid #E6DEC8",
                            display: "flex",
                            alignItems: "center",
                            justifyContent: "center",
                            fontSize: "18px",
                          }}
                        >
                          🍽️
                        </div>
                      )}
                      <span style={{ fontWeight: "700", color: "#1C1A2D" }}>{p.name}</span>
                    </div>
                  </td>
                  {currentStoreCode === "ALL" && (
                    <td>
                      <span
                        style={{
                          padding: "4px 8px",
                          borderRadius: "6px",
                          fontSize: "12px",
                          fontWeight: "600",
                          background: p.storeCode === "TRAM02" ? "#EFF6FF" : "#FEF3C7",
                          color: p.storeCode === "TRAM02" ? "#1D4ED8" : "#92400E",
                          border: `1px solid ${p.storeCode === "TRAM02" ? "#BFDBFE" : "#FDE68A"}`,
                          whiteSpace: "nowrap",
                        }}
                      >
                        {p.storeCode === "TRAM02" ? "🏪 Trạm Sữa (TRAM02)" : "🍋 Trạm Chanh (TRAM01)"}
                      </span>
                    </td>
                  )}
                  <td>
                    {p.category ? (
                      <span className="badge badge-primary">{p.category}</span>
                    ) : (
                      <span style={{ color: "#5D5B63" }}>—</span>
                    )}
                  </td>
                  <td style={{ fontWeight: "700", color: "#7E2930" }}>{formatVND(p.price)}</td>
                  <td style={{ color: "#8B8FA8" }}>{p.unit || "—"}</td>
                  <td>
                    <div style={{ display: "flex", gap: "8px" }}>
                      <button
                        onClick={() => openEdit(p)}
                        title="Chỉnh sửa"
                        style={{
                          padding: "6px",
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
                        onClick={() => setDeleteTarget(p)}
                        title="Xóa món"
                        style={{
                          padding: "6px",
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

      {/* Add/Edit Modal */}
      {showModal && (
        <div className="modal-overlay" onClick={closeModal}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()}>
            <div style={{ padding: "24px 24px 0", display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: "20px" }}>
              <h2 style={{ fontSize: "18px", fontWeight: "700", color: "#1C1A2D" }}>
                {editId ? "Chỉnh sửa sản phẩm" : "Thêm sản phẩm mới"}
              </h2>
              <button onClick={closeModal} style={{ background: "none", border: "none", color: "#5D5B63", cursor: "pointer" }}>
                <X size={20} />
              </button>
            </div>
            <div style={{ padding: "0 24px 24px", display: "flex", flexDirection: "column", gap: "14px" }}>
              {/* Store Selection */}
              {stores.length > 0 && (
                <div>
                  <label style={{ display: "block", fontSize: "13px", fontWeight: "600", color: "#8B8FA8", marginBottom: "6px" }}>
                    Chi nhánh áp dụng *
                  </label>
                  <select
                    className="input-field"
                    value={form.storeCode}
                    disabled={Boolean(editId)}
                    onChange={(e) => setForm((f) => ({ ...f, storeCode: e.target.value }))}
                  >
                    {stores.map((s) => (
                      <option key={s.storeCode} value={s.storeCode}>
                        🏪 {s.storeCode} - {s.storeName}
                      </option>
                    ))}
                  </select>
                </div>
              )}

              {/* Image Upload */}
              <div style={{ display: "flex", flexDirection: "column", alignItems: "center", marginBottom: "8px" }}>
                <div
                  style={{
                    width: "100px",
                    height: "100px",
                    borderRadius: "16px",
                    background: "#FAF7F2",
                    border: "1px dashed #D8CFBD",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    overflow: "hidden",
                    marginBottom: "10px",
                    position: "relative",
                  }}
                >
                  {form.imageBase64 ? (
                    <img src={form.imageBase64} alt="Preview" style={{ width: "100%", height: "100%", objectFit: "cover" }} />
                  ) : (
                    <div style={{ fontSize: "32px" }}>🍽️</div>
                  )}
                  {form.imageBase64 && (
                    <button
                      type="button"
                      onClick={() => setForm((f) => ({ ...f, imageBase64: "" }))}
                      style={{
                        position: "absolute",
                        top: "4px",
                        right: "4px",
                        background: "rgba(0,0,0,0.5)",
                        border: "none",
                        borderRadius: "50%",
                        width: "24px",
                        height: "24px",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        color: "white",
                        cursor: "pointer",
                      }}
                    >
                      <X size={14} />
                    </button>
                  )}
                </div>
                <label
                  style={{
                    padding: "8px 16px",
                    background: "rgba(255,107,53,0.1)",
                    color: "#CB2D2E",
                    borderRadius: "8px",
                    fontSize: "13px",
                    fontWeight: "600",
                    cursor: "pointer",
                  }}
                >
                  Chọn ảnh sản phẩm
                  <input type="file" accept="image/*" style={{ display: "none" }} onChange={handleImageChange} />
                </label>
              </div>

              {[
                { label: "Tên sản phẩm *", key: "name" as const, placeholder: "Nhập tên sản phẩm" },
                { label: "Giá (VNĐ) *", key: "price" as const, placeholder: "Ví dụ: 50000", type: "number" },
                { label: "Đơn vị", key: "unit" as const, placeholder: "Ví dụ: Tô, Ly, Phần, Cái" },
              ].map((field) => (
                <div key={field.key}>
                  <label style={{ display: "block", fontSize: "13px", fontWeight: "600", color: "#8B8FA8", marginBottom: "6px" }}>
                    {field.label}
                  </label>
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
                <label style={{ display: "block", fontSize: "13px", fontWeight: "600", color: "#8B8FA8", marginBottom: "6px" }}>
                  Danh mục
                </label>
                <input
                  list="categories-list"
                  className="input-field"
                  placeholder="Chọn hoặc nhập tên danh mục"
                  value={form.category}
                  onChange={(e) => setForm((f) => ({ ...f, category: e.target.value }))}
                />
                <datalist id="categories-list">
                  {categories.map((c, i) => (
                    <option key={c.id + "-" + i} value={c.name} />
                  ))}
                </datalist>
              </div>

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
                  {editId ? "Cập nhật" : "Thêm mới"}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Delete Confirm Modal */}
      {deleteTarget && (
        <div className="modal-overlay" onClick={() => setDeleteTarget(null)}>
          <div className="modal-content" style={{ maxWidth: "420px" }} onClick={(e) => e.stopPropagation()}>
            <div style={{ padding: "28px", textAlign: "center" }}>
              <div style={{ fontSize: "48px", marginBottom: "16px" }}>🗑️</div>
              <h2 style={{ fontSize: "18px", fontWeight: "700", color: "#1C1A2D", marginBottom: "8px" }}>
                Xác nhận xóa
              </h2>
              <p style={{ color: "#8B8FA8", fontSize: "14px", marginBottom: "24px" }}>
                Bạn có chắc muốn xóa món <strong>"{deleteTarget.name}"</strong>
                {deleteTarget.storeCode ? ` thuộc chi nhánh ${deleteTarget.storeCode}` : ""}? Hành động này không thể hoàn tác.
              </p>
              <div style={{ display: "flex", gap: "10px" }}>
                <button className="btn-secondary" onClick={() => setDeleteTarget(null)} style={{ flex: 1, justifyContent: "center" }}>
                  Hủy
                </button>
                <button className="btn-danger" onClick={handleDelete} style={{ flex: 1, justifyContent: "center" }}>
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
