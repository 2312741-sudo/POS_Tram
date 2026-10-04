"use client";
import { useState, useMemo } from "react";
import {
  Search,
  Download,
  Plus,
  Edit2,
  Trash2,
  Filter,
  X,
  Check,
  Store,
  FolderPlus,
  Folder,
  Layers,
  Eye,
  Tag,
  AlertCircle,
  UtensilsCrossed,
} from "lucide-react";
import { exportProducts } from "@/lib/export";
import { useDashboardData, ProductItem, CategoryItem } from "@/lib/data-context";

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

const emptyProductForm: ProductFormData = {
  name: "",
  price: "",
  unit: "",
  category: "",
  imageBase64: "",
  storeCode: "TRAM01",
};

interface CategoryFormData {
  name: string;
  storeCode: string;
}

const emptyCategoryForm: CategoryFormData = {
  name: "",
  storeCode: "TRAM01",
};

export default function ProductsPage() {
  const {
    products,
    allProducts,
    categories,
    allCategories,
    stores,
    currentStoreCode,
    setCurrentStoreCode,
    saveProduct,
    deleteProduct,
    saveCategory,
    deleteCategory,
    loading: ctxLoading,
  } = useDashboardData();

  const loading = ctxLoading && products.length === 0;

  // Active top-level subtab: "products" or "categories"
  const [activeTab, setActiveTab] = useState<"products" | "categories">("products");

  // Product tab state
  const [search, setSearch] = useState("");
  const [filterCategory, setFilterCategory] = useState("");
  const [showProductModal, setShowProductModal] = useState(false);
  const [editProductId, setEditProductId] = useState<string | null>(null);
  const [productForm, setProductForm] = useState<ProductFormData>(emptyProductForm);
  const [productSaving, setProductSaving] = useState(false);
  const [deleteProductTarget, setDeleteProductTarget] = useState<ProductItem | null>(null);
  const [productError, setProductError] = useState("");

  // Category tab & modal state
  const [categorySearch, setCategorySearch] = useState("");
  const [showCategoryModal, setShowCategoryModal] = useState(false);
  const [editCategoryOriginalName, setEditCategoryOriginalName] = useState<string | null>(null);
  const [categoryForm, setCategoryForm] = useState<CategoryFormData>(emptyCategoryForm);
  const [categorySaving, setCategorySaving] = useState(false);
  const [categoryError, setCategoryError] = useState("");
  const [deleteCategoryTarget, setDeleteCategoryTarget] = useState<CategoryItem | null>(null);

  // Quick inline add category while inside product modal
  const [quickAddCatOpen, setQuickAddCatOpen] = useState(false);
  const [quickCatName, setQuickCatName] = useState("");

  // Compute category statistics (number of products per category, sample items)
  const categoryStats = useMemo(() => {
    const counts: Record<string, number> = {};
    const sampleItems: Record<string, ProductItem[]> = {};

    products.forEach((p) => {
      const catKey = p.category ? p.category.trim() : "Chưa phân loại";
      counts[catKey] = (counts[catKey] || 0) + 1;
      if (!sampleItems[catKey]) {
        sampleItems[catKey] = [];
      }
      if (sampleItems[catKey].length < 3) {
        sampleItems[catKey].push(p);
      }
    });

    return { counts, sampleItems };
  }, [products]);

  // Filtered categories for Tab 2
  const filteredCategories = useMemo(() => {
    return categories.filter((c) => {
      const matchSearch =
        !categorySearch || c.name.toLowerCase().includes(categorySearch.toLowerCase());
      return matchSearch;
    });
  }, [categories, categorySearch]);

  // Uncategorized products count
  const uncategorizedCount = useMemo(() => {
    return products.filter((p) => !p.category || !p.category.trim()).length;
  }, [products]);

  // Filtered products for Tab 1
  const filteredProducts = useMemo(() => {
    return products.filter((p) => {
      const matchSearch = !search || p.name.toLowerCase().includes(search.toLowerCase());
      const matchCat = !filterCategory || p.category === filterCategory;
      return matchSearch && matchCat;
    });
  }, [products, search, filterCategory]);

  // Open Product Modal
  const openAddProduct = () => {
    setEditProductId(null);
    setProductForm({
      ...emptyProductForm,
      storeCode: currentStoreCode !== "ALL" ? currentStoreCode : stores[0]?.storeCode || "TRAM01",
      category: filterCategory || (categories[0]?.name ?? ""),
    });
    setProductError("");
    setQuickAddCatOpen(false);
    setShowProductModal(true);
  };

  const openEditProduct = (p: ProductItem) => {
    setEditProductId(p.id);
    setProductForm({
      name: p.name,
      price: String(p.price),
      unit: p.unit || "",
      category: p.category || "",
      imageBase64: p.imageBase64 || "",
      storeCode: p.storeCode || (currentStoreCode !== "ALL" ? currentStoreCode : "TRAM01"),
    });
    setProductError("");
    setQuickAddCatOpen(false);
    setShowProductModal(true);
  };

  const handleImageChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      if (file.size > 2 * 1024 * 1024) {
        setProductError("Kích thước ảnh quá lớn, vui lòng chọn ảnh < 2MB");
        return;
      }
      const reader = new FileReader();
      reader.onloadend = () => {
        setProductForm((f) => ({ ...f, imageBase64: reader.result as string }));
      };
      reader.readAsDataURL(file);
    }
  };

  const closeProductModal = () => {
    setShowProductModal(false);
    setEditProductId(null);
    setProductForm(emptyProductForm);
    setProductError("");
    setQuickAddCatOpen(false);
  };

  const handleSaveProduct = async () => {
    if (!productForm.name.trim()) {
      setProductError("Vui lòng nhập tên sản phẩm");
      return;
    }
    if (!productForm.price || isNaN(Number(productForm.price)) || Number(productForm.price) < 0) {
      setProductError("Giá không hợp lệ");
      return;
    }
    setProductSaving(true);
    setProductError("");
    try {
      const targetStore =
        productForm.storeCode || (currentStoreCode !== "ALL" ? currentStoreCode : "TRAM01");
      const res = await saveProduct(
        {
          id: editProductId || undefined,
          name: productForm.name.trim(),
          price: Number(productForm.price),
          unit: productForm.unit.trim(),
          category: productForm.category.trim(),
          imageBase64: productForm.imageBase64,
        },
        targetStore
      );
      if (!res.success) {
        setProductError(res.error || "Lỗi lưu dữ liệu");
        setProductSaving(false);
        return;
      }
      closeProductModal();
    } catch (e: any) {
      setProductError(e.message || "Lỗi lưu dữ liệu");
    }
    setProductSaving(false);
  };

  const handleDeleteProduct = async () => {
    if (!deleteProductTarget) return;
    try {
      await deleteProduct(deleteProductTarget.id, deleteProductTarget.storeCode);
      setDeleteProductTarget(null);
    } catch {}
  };

  // Open Category Modal
  const openAddCategory = () => {
    setEditCategoryOriginalName(null);
    setCategoryForm({
      name: "",
      storeCode: currentStoreCode !== "ALL" ? currentStoreCode : "ALL",
    });
    setCategoryError("");
    setShowCategoryModal(true);
  };

  const openEditCategory = (c: CategoryItem) => {
    setEditCategoryOriginalName(c.name);
    setCategoryForm({
      name: c.name,
      storeCode: c.storeCode || (currentStoreCode !== "ALL" ? currentStoreCode : "ALL"),
    });
    setCategoryError("");
    setShowCategoryModal(true);
  };

  const closeCategoryModal = () => {
    setShowCategoryModal(false);
    setEditCategoryOriginalName(null);
    setCategoryForm(emptyCategoryForm);
    setCategoryError("");
  };

  const handleSaveCategory = async () => {
    const cleanName = categoryForm.name.trim();
    if (!cleanName) {
      setCategoryError("Vui lòng nhập tên danh mục");
      return;
    }
    setCategorySaving(true);
    setCategoryError("");
    try {
      const res = await saveCategory(
        cleanName,
        categoryForm.storeCode,
        editCategoryOriginalName || undefined
      );
      if (!res.success) {
        setCategoryError(res.error || "Lỗi lưu danh mục");
        setCategorySaving(false);
        return;
      }
      closeCategoryModal();
    } catch (e: any) {
      setCategoryError(e.message || "Lỗi lưu danh mục");
    }
    setCategorySaving(false);
  };

  const handleDeleteCategory = async () => {
    if (!deleteCategoryTarget) return;
    try {
      await deleteCategory(deleteCategoryTarget.name, deleteCategoryTarget.storeCode);
      setDeleteCategoryTarget(null);
    } catch {}
  };

  const handleQuickAddCategory = async () => {
    const clean = quickCatName.trim();
    if (!clean) return;
    try {
      const targetStore =
        productForm.storeCode || (currentStoreCode !== "ALL" ? currentStoreCode : "TRAM01");
      await saveCategory(clean, targetStore);
      setProductForm((f) => ({ ...f, category: clean }));
      setQuickCatName("");
      setQuickAddCatOpen(false);
    } catch {}
  };

  const handleExport = () => {
    exportProducts(filteredProducts);
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
      {/* Page Header */}
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: "16px" }}>
        <div>
          <h1 className="section-title">Thực đơn & Sản phẩm 🍜</h1>
          <p className="section-subtitle">
            {currentStoreCode === "ALL"
              ? `Toàn hệ thống: ${products.length} món • ${categories.length} danh mục (${stores.length} chi nhánh)`
              : `Chi nhánh ${currentStoreCode}: ${products.length} món • ${categories.length} danh mục`}
          </p>
        </div>
        <div style={{ display: "flex", gap: "10px", flexWrap: "wrap" }}>
          {activeTab === "products" ? (
            <>
              <button className="btn-secondary" onClick={handleExport}>
                <Download size={16} />
                Xuất Excel
              </button>
              <button className="btn-primary" onClick={openAddProduct}>
                <Plus size={16} />
                Thêm sản phẩm
              </button>
            </>
          ) : (
            <button className="btn-primary" onClick={openAddCategory}>
              <FolderPlus size={16} />
              Thêm danh mục mới
            </button>
          )}
        </div>
      </div>

      {/* Main Tabs Switcher: Products vs Categories */}
      <div
        style={{
          display: "flex",
          borderBottom: "1px solid #E6DEC8",
          gap: "8px",
          alignItems: "center",
          backgroundColor: "#FFFFFF",
          padding: "6px 12px 0",
          borderRadius: "14px 14px 0 0",
        }}
      >
        <button
          onClick={() => setActiveTab("products")}
          style={{
            display: "flex",
            alignItems: "center",
            gap: "8px",
            padding: "12px 20px",
            fontSize: "14px",
            fontWeight: "700",
            cursor: "pointer",
            background: "none",
            border: "none",
            borderBottom: activeTab === "products" ? "3px solid #7E2930" : "3px solid transparent",
            color: activeTab === "products" ? "#7E2930" : "#5D5B63",
            transition: "all 0.15s ease",
          }}
        >
          <UtensilsCrossed size={18} />
          Món ăn & Hàng hóa
          <span
            style={{
              padding: "2px 8px",
              borderRadius: "12px",
              fontSize: "12px",
              background: activeTab === "products" ? "rgba(126,41,48,0.12)" : "#F4EFE6",
              color: activeTab === "products" ? "#7E2930" : "#8B8FA8",
              fontWeight: "700",
            }}
          >
            {products.length}
          </span>
        </button>

        <button
          onClick={() => setActiveTab("categories")}
          style={{
            display: "flex",
            alignItems: "center",
            gap: "8px",
            padding: "12px 20px",
            fontSize: "14px",
            fontWeight: "700",
            cursor: "pointer",
            background: "none",
            border: "none",
            borderBottom: activeTab === "categories" ? "3px solid #7E2930" : "3px solid transparent",
            color: activeTab === "categories" ? "#7E2930" : "#5D5B63",
            transition: "all 0.15s ease",
          }}
        >
          <Layers size={18} />
          Danh mục sản phẩm
          <span
            style={{
              padding: "2px 8px",
              borderRadius: "12px",
              fontSize: "12px",
              background: activeTab === "categories" ? "rgba(126,41,48,0.12)" : "#F4EFE6",
              color: activeTab === "categories" ? "#7E2930" : "#8B8FA8",
              fontWeight: "700",
            }}
          >
            {categories.length}
          </span>
        </button>
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
            🌐 Tất cả chi nhánh ({allProducts.length} món)
          </button>
          {stores.map((s) => {
            const isSelected = currentStoreCode === s.storeCode;
            const count = allProducts.filter((p) => p.storeCode === s.storeCode).length;
            const catCount = allCategories.filter((c) => c.storeCode === s.storeCode).length;
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
                🏪 {s.storeName} ({count} món • {catCount} nhóm)
              </button>
            );
          })}
        </div>
      )}

      {/* ==================== TAB 1: PRODUCTS TABLE ==================== */}
      {activeTab === "products" && (
        <div style={{ display: "flex", flexDirection: "column", gap: "16px" }}>
          {/* Category Filter Pills */}
          {categories.length > 0 && (
            <div
              style={{
                display: "flex",
                gap: "8px",
                overflowX: "auto",
                paddingBottom: "4px",
                alignItems: "center",
              }}
            >
              <span style={{ fontSize: "12px", fontWeight: "700", color: "#8B8FA8", whiteSpace: "nowrap" }}>
                Nhóm món:
              </span>
              <button
                onClick={() => setFilterCategory("")}
                style={{
                  padding: "5px 12px",
                  borderRadius: "20px",
                  fontSize: "12px",
                  fontWeight: "600",
                  cursor: "pointer",
                  border: "1px solid",
                  borderColor: filterCategory === "" ? "#7E2930" : "#E6DEC8",
                  background: filterCategory === "" ? "rgba(126,41,48,0.1)" : "#FFFFFF",
                  color: filterCategory === "" ? "#7E2930" : "#5D5B63",
                  whiteSpace: "nowrap",
                }}
              >
                Tất cả ({products.length})
              </button>
              {categories.map((c, idx) => {
                const isSelected = filterCategory === c.name;
                const count = categoryStats.counts[c.name] || 0;
                return (
                  <button
                    key={`cat_pill_${c.storeCode || ""}_${c.id || c.name}_${idx}`}
                    onClick={() => setFilterCategory(isSelected ? "" : c.name)}
                    style={{
                      padding: "5px 12px",
                      borderRadius: "20px",
                      fontSize: "12px",
                      fontWeight: "600",
                      cursor: "pointer",
                      border: "1px solid",
                      borderColor: isSelected ? "#7E2930" : "#E6DEC8",
                      background: isSelected ? "rgba(126,41,48,0.1)" : "#FFFFFF",
                      color: isSelected ? "#7E2930" : "#5D5B63",
                      whiteSpace: "nowrap",
                    }}
                  >
                    📂 {c.name} ({count})
                  </button>
                );
              })}
              {uncategorizedCount > 0 && (
                <button
                  onClick={() => setFilterCategory("Chưa phân loại")}
                  style={{
                    padding: "5px 12px",
                    borderRadius: "20px",
                    fontSize: "12px",
                    fontWeight: "600",
                    cursor: "pointer",
                    border: "1px solid",
                    borderColor: filterCategory === "Chưa phân loại" ? "#DC2626" : "#FCA5A5",
                    background: filterCategory === "Chưa phân loại" ? "rgba(220,38,38,0.1)" : "#FEF2F2",
                    color: "#DC2626",
                    whiteSpace: "nowrap",
                  }}
                >
                  ⚠️ Chưa phân loại ({uncategorizedCount})
                </button>
              )}
            </div>
          )}

          {/* Search and Secondary Filter */}
          <div className="card" style={{ padding: "16px 20px" }}>
            <div style={{ display: "flex", gap: "12px", flexWrap: "wrap", alignItems: "center" }}>
              <div style={{ position: "relative", flex: "1", minWidth: "220px" }}>
                <Search
                  size={16}
                  style={{
                    position: "absolute",
                    left: "12px",
                    top: "50%",
                    transform: "translateY(-50%)",
                    color: "#8B8FA8",
                  }}
                />
                <input
                  className="input-field"
                  placeholder="Tìm tên sản phẩm hoặc mã..."
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  style={{ paddingLeft: "38px" }}
                />
              </div>

              <select
                className="input-field"
                value={filterCategory}
                onChange={(e) => setFilterCategory(e.target.value)}
                style={{ width: "auto", minWidth: "220px" }}
              >
                <option value="">📂 Tất cả danh mục ({categories.length})</option>
                {categories.map((c, i) => (
                  <option key={`filter_cat_opt_${c.storeCode || ""}_${c.id || c.name}_${i}`} value={c.name}>
                    📂 {c.name} ({categoryStats.counts[c.name] || 0} món)
                  </option>
                ))}
                {uncategorizedCount > 0 && (
                  <option value="Chưa phân loại">⚠️ Chưa phân loại ({uncategorizedCount} món)</option>
                )}
              </select>

              {filterCategory && (
                <button
                  onClick={() => setFilterCategory("")}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: "4px",
                    padding: "8px 12px",
                    borderRadius: "8px",
                    background: "#F3F4F6",
                    border: "none",
                    fontSize: "12px",
                    color: "#5D5B63",
                    cursor: "pointer",
                  }}
                >
                  <X size={14} /> Xóa bộ lọc nhóm
                </button>
              )}
            </div>
          </div>

          {/* Products Table */}
          <div className="table-wrapper">
            <table>
              <thead>
                <tr>
                  <th>#</th>
                  <th>Tên sản phẩm</th>
                  {currentStoreCode === "ALL" && <th>Chi nhánh</th>}
                  <th>Danh mục</th>
                  <th>Giá bán</th>
                  <th>Đơn vị</th>
                  <th>Thao tác</th>
                </tr>
              </thead>
              <tbody>
                {filteredProducts.length === 0 ? (
                  <tr>
                    <td
                      colSpan={currentStoreCode === "ALL" ? 7 : 6}
                      style={{ textAlign: "center", padding: "48px", color: "#8B8FA8" }}
                    >
                      <div style={{ fontSize: "36px", marginBottom: "8px" }}>🍽️</div>
                      Không có sản phẩm nào phù hợp
                    </td>
                  </tr>
                ) : (
                  filteredProducts.map((p, i) => (
                    <tr key={`prod_row_${p.storeCode || "TRAM01"}_${p.id || p.name}_${i}`}>
                      <td style={{ color: "#8B8FA8" }}>{i + 1}</td>
                      <td>
                        <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
                          {p.imageBase64 ? (
                            <img
                              src={p.imageBase64}
                              alt={p.name}
                              style={{ width: "38px", height: "38px", borderRadius: "8px", objectFit: "cover" }}
                            />
                          ) : (
                            <div
                              style={{
                                width: "38px",
                                height: "38px",
                                borderRadius: "8px",
                                background: "#FAF7F2",
                                display: "flex",
                                alignItems: "center",
                                justifyContent: "center",
                                fontSize: "18px",
                              }}
                            >
                              🍽️
                            </div>
                          )}
                          <div>
                            <div style={{ fontWeight: "700", color: "#1C1A2D" }}>{p.name}</div>
                            {p.id && (
                              <div style={{ fontSize: "11px", color: "#8B8FA8" }}>Mã: {p.id.slice(0, 10)}</div>
                            )}
                          </div>
                        </div>
                      </td>
                      {currentStoreCode === "ALL" && (
                        <td>
                          <span
                            style={{
                              padding: "3px 8px",
                              borderRadius: "6px",
                              background: "#FAF7F2",
                              border: "1px solid #E6DEC8",
                              fontSize: "12px",
                              fontWeight: "600",
                              color: "#7E2930",
                            }}
                          >
                            🏪 {p.storeCode || "TRAM01"}
                          </span>
                        </td>
                      )}
                      <td>
                        {p.category ? (
                          <span
                            style={{
                              padding: "4px 10px",
                              borderRadius: "8px",
                              background: "rgba(126,41,48,0.08)",
                              color: "#7E2930",
                              fontSize: "12px",
                              fontWeight: "600",
                              display: "inline-flex",
                              alignItems: "center",
                              gap: "4px",
                            }}
                          >
                            <Tag size={12} />
                            {p.category}
                          </span>
                        ) : (
                          <span
                            style={{
                              padding: "4px 10px",
                              borderRadius: "8px",
                              background: "#FEE2E2",
                              color: "#DC2626",
                              fontSize: "11px",
                              fontWeight: "600",
                            }}
                          >
                            Chưa phân loại
                          </span>
                        )}
                      </td>
                      <td style={{ fontWeight: "700", color: "#1C1A2D" }}>{formatVND(p.price)}</td>
                      <td style={{ color: "#5D5B63" }}>{p.unit || "Phần"}</td>
                      <td>
                        <div style={{ display: "flex", gap: "6px" }}>
                          <button
                            onClick={() => openEditProduct(p)}
                            title="Sửa sản phẩm"
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
                            onClick={() => setDeleteProductTarget(p)}
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
        </div>
      )}

      {/* ==================== TAB 2: CATEGORIES MANAGEMENT ==================== */}
      {activeTab === "categories" && (
        <div style={{ display: "flex", flexDirection: "column", gap: "20px" }}>
          {/* KPI Summary Cards */}
          <div
            style={{
              display: "grid",
              gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))",
              gap: "16px",
            }}
          >
            <div className="card" style={{ padding: "18px 20px" }}>
              <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: "8px" }}>
                <span style={{ fontSize: "13px", color: "#8B8FA8", fontWeight: "600" }}>Tổng danh mục</span>
                <span style={{ padding: "6px", borderRadius: "8px", background: "rgba(126,41,48,0.1)", color: "#7E2930" }}>
                  <Layers size={18} />
                </span>
              </div>
              <div style={{ fontSize: "26px", fontWeight: "800", color: "#1C1A2D" }}>
                {categories.length} <span style={{ fontSize: "14px", fontWeight: "500", color: "#8B8FA8" }}>nhóm</span>
              </div>
            </div>

            <div className="card" style={{ padding: "18px 20px" }}>
              <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: "8px" }}>
                <span style={{ fontSize: "13px", color: "#8B8FA8", fontWeight: "600" }}>Món đã phân nhóm</span>
                <span style={{ padding: "6px", borderRadius: "8px", background: "rgba(16,185,129,0.1)", color: "#10B981" }}>
                  <Check size={18} />
                </span>
              </div>
              <div style={{ fontSize: "26px", fontWeight: "800", color: "#10B981" }}>
                {products.length - uncategorizedCount}{" "}
                <span style={{ fontSize: "14px", fontWeight: "500", color: "#8B8FA8" }}>/ {products.length} món</span>
              </div>
            </div>

            <div className="card" style={{ padding: "18px 20px" }}>
              <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: "8px" }}>
                <span style={{ fontSize: "13px", color: "#8B8FA8", fontWeight: "600" }}>Món chưa có danh mục</span>
                <span style={{ padding: "6px", borderRadius: "8px", background: "rgba(239,68,68,0.1)", color: "#EF4444" }}>
                  <AlertCircle size={18} />
                </span>
              </div>
              <div style={{ fontSize: "26px", fontWeight: "800", color: uncategorizedCount > 0 ? "#EF4444" : "#1C1A2D" }}>
                {uncategorizedCount} <span style={{ fontSize: "14px", fontWeight: "500", color: "#8B8FA8" }}>món</span>
              </div>
            </div>
          </div>

          {/* Search bar and Add button */}
          <div className="card" style={{ padding: "16px 20px" }}>
            <div style={{ display: "flex", gap: "12px", justifyContent: "space-between", flexWrap: "wrap", alignItems: "center" }}>
              <div style={{ position: "relative", flex: "1", minWidth: "240px" }}>
                <Search
                  size={16}
                  style={{
                    position: "absolute",
                    left: "12px",
                    top: "50%",
                    transform: "translateY(-50%)",
                    color: "#8B8FA8",
                  }}
                />
                <input
                  className="input-field"
                  placeholder="Tìm kiếm danh mục món ăn..."
                  value={categorySearch}
                  onChange={(e) => setCategorySearch(e.target.value)}
                  style={{ paddingLeft: "38px" }}
                />
              </div>

              <button className="btn-primary" onClick={openAddCategory}>
                <FolderPlus size={16} />
                Thêm danh mục mới
              </button>
            </div>
          </div>

          {/* Categories Table */}
          <div className="table-wrapper">
            <table>
              <thead>
                <tr>
                  <th>#</th>
                  <th>Tên danh mục</th>
                  {currentStoreCode === "ALL" && <th>Chi nhánh</th>}
                  <th>Số lượng món</th>
                  <th>Món tiêu biểu</th>
                  <th>Thao tác</th>
                </tr>
              </thead>
              <tbody>
                {filteredCategories.length === 0 ? (
                  <tr>
                    <td
                      colSpan={currentStoreCode === "ALL" ? 6 : 5}
                      style={{ textAlign: "center", padding: "48px", color: "#8B8FA8" }}
                    >
                      <div style={{ fontSize: "36px", marginBottom: "8px" }}>📂</div>
                      {categorySearch ? "Không tìm thấy danh mục phù hợp" : "Chưa có danh mục nào được tạo"}
                      <div style={{ marginTop: "12px" }}>
                        <button className="btn-primary" onClick={openAddCategory} style={{ margin: "0 auto" }}>
                          <Plus size={16} /> Tạo danh mục đầu tiên
                        </button>
                      </div>
                    </td>
                  </tr>
                ) : (
                  filteredCategories.map((c, i) => {
                    const count = categoryStats.counts[c.name] || 0;
                    const samples = categoryStats.sampleItems[c.name] || [];
                    return (
                      <tr key={`${c.storeCode || "TRAM01"}_${c.id || c.name}_${i}`}>
                        <td style={{ color: "#8B8FA8" }}>{i + 1}</td>
                        <td>
                          <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
                            <div
                              style={{
                                width: "36px",
                                height: "36px",
                                borderRadius: "10px",
                                background: "rgba(126,41,48,0.08)",
                                display: "flex",
                                alignItems: "center",
                                justifyContent: "center",
                                color: "#7E2930",
                              }}
                            >
                              <Folder size={18} />
                            </div>
                            <span style={{ fontWeight: "700", color: "#1C1A2D", fontSize: "14px" }}>
                              {c.name}
                            </span>
                          </div>
                        </td>
                        {currentStoreCode === "ALL" && (
                          <td>
                            <span
                              style={{
                                padding: "3px 8px",
                                borderRadius: "6px",
                                background: "#FAF7F2",
                                border: "1px solid #E6DEC8",
                                fontSize: "12px",
                                fontWeight: "600",
                                color: "#7E2930",
                              }}
                            >
                              🏪 {c.storeCode || "Tất cả"}
                            </span>
                          </td>
                        )}
                        <td>
                          <span
                            style={{
                              padding: "4px 10px",
                              borderRadius: "12px",
                              background: count > 0 ? "rgba(16,185,129,0.1)" : "#F3F4F6",
                              color: count > 0 ? "#059669" : "#8B8FA8",
                              fontWeight: "700",
                              fontSize: "13px",
                            }}
                          >
                            {count} món
                          </span>
                        </td>
                        <td>
                          {samples.length > 0 ? (
                            <div style={{ display: "flex", gap: "6px", flexWrap: "wrap" }}>
                              {samples.map((item, itemIdx) => (
                                <span
                                  key={`sample_${c.name}_${item.storeCode || ""}_${item.id || item.name}_${itemIdx}`}
                                  style={{
                                    fontSize: "11px",
                                    padding: "2px 8px",
                                    background: "#F9FAFB",
                                    border: "1px solid #E5E7EB",
                                    borderRadius: "6px",
                                    color: "#4B5563",
                                  }}
                                >
                                  {item.name}
                                </span>
                              ))}
                              {count > 3 && (
                                <span style={{ fontSize: "11px", color: "#8B8FA8", alignSelf: "center" }}>
                                  +{count - 3} món khác
                                </span>
                              )}
                            </div>
                          ) : (
                            <span style={{ fontSize: "12px", color: "#9CA3AF", fontStyle: "italic" }}>
                              Chưa có món
                            </span>
                          )}
                        </td>
                        <td>
                          <div style={{ display: "flex", gap: "6px" }}>
                            <button
                              onClick={() => {
                                setFilterCategory(c.name);
                                setActiveTab("products");
                              }}
                              title="Xem danh sách món thuộc nhóm này"
                              style={{
                                display: "flex",
                                alignItems: "center",
                                gap: "4px",
                                padding: "6px 10px",
                                borderRadius: "8px",
                                background: "rgba(126,41,48,0.08)",
                                border: "1px solid rgba(126,41,48,0.2)",
                                color: "#7E2930",
                                fontSize: "12px",
                                fontWeight: "600",
                                cursor: "pointer",
                              }}
                            >
                              <Eye size={14} />
                              Xem món ({count})
                            </button>
                            <button
                              onClick={() => openEditCategory(c)}
                              title="Sửa tên danh mục"
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
                              onClick={() => setDeleteCategoryTarget(c)}
                              title="Xóa danh mục"
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
                    );
                  })
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* ==================== MODAL: ADD/EDIT PRODUCT ==================== */}
      {showProductModal && (
        <div className="modal-overlay" onClick={closeProductModal}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()}>
            <div style={{ padding: "24px 24px 0", display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: "20px" }}>
              <h2 style={{ fontSize: "18px", fontWeight: "700", color: "#1C1A2D" }}>
                {editProductId ? "Chỉnh sửa sản phẩm" : "Thêm sản phẩm mới"}
              </h2>
              <button onClick={closeProductModal} style={{ background: "none", border: "none", color: "#5D5B63", cursor: "pointer" }}>
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
                    value={productForm.storeCode}
                    disabled={Boolean(editProductId)}
                    onChange={(e) => setProductForm((f) => ({ ...f, storeCode: e.target.value }))}
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
                  {productForm.imageBase64 ? (
                    <img src={productForm.imageBase64} alt="Preview" style={{ width: "100%", height: "100%", objectFit: "cover" }} />
                  ) : (
                    <div style={{ fontSize: "32px" }}>🍽️</div>
                  )}
                  {productForm.imageBase64 && (
                    <button
                      type="button"
                      onClick={() => setProductForm((f) => ({ ...f, imageBase64: "" }))}
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
                { label: "Tên sản phẩm *", key: "name" as const, placeholder: "Ví dụ: Cà phê sữa đá, Bạc xỉu..." },
                { label: "Giá bán (VNĐ) *", key: "price" as const, placeholder: "Ví dụ: 35000", type: "number" },
                { label: "Đơn vị tính", key: "unit" as const, placeholder: "Ví dụ: Ly, Cốc, Phần, Đĩa..." },
              ].map((field) => (
                <div key={field.key}>
                  <label style={{ display: "block", fontSize: "13px", fontWeight: "600", color: "#8B8FA8", marginBottom: "6px" }}>
                    {field.label}
                  </label>
                  <input
                    type={field.type || "text"}
                    className="input-field"
                    placeholder={field.placeholder}
                    value={productForm[field.key]}
                    onChange={(e) => setProductForm((f) => ({ ...f, [field.key]: e.target.value }))}
                  />
                </div>
              ))}

              {/* Category Dropdown + Quick Add */}
              <div>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "6px" }}>
                  <label style={{ fontSize: "13px", fontWeight: "600", color: "#8B8FA8" }}>
                    Danh mục sản phẩm
                  </label>
                  <button
                    type="button"
                    onClick={() => setQuickAddCatOpen(!quickAddCatOpen)}
                    style={{
                      background: "none",
                      border: "none",
                      color: "#7E2930",
                      fontSize: "12px",
                      fontWeight: "700",
                      cursor: "pointer",
                      display: "flex",
                      alignItems: "center",
                      gap: "4px",
                    }}
                  >
                    <Plus size={12} /> {quickAddCatOpen ? "Đóng" : "Tạo nhóm mới"}
                  </button>
                </div>

                {quickAddCatOpen ? (
                  <div style={{ display: "flex", gap: "8px", marginBottom: "8px" }}>
                    <input
                      className="input-field"
                      placeholder="Tên danh mục mới (vd: Trà sữa, Ăn vặt...)"
                      value={quickCatName}
                      onChange={(e) => setQuickCatName(e.target.value)}
                    />
                    <button
                      type="button"
                      className="btn-primary"
                      onClick={handleQuickAddCategory}
                      style={{ whiteSpace: "nowrap", padding: "8px 14px" }}
                    >
                      Thêm
                    </button>
                  </div>
                ) : null}

                <div style={{ display: "flex", gap: "8px" }}>
                  <select
                    className="input-field"
                    value={productForm.category}
                    onChange={(e) => setProductForm((f) => ({ ...f, category: e.target.value }))}
                    style={{ flex: 1 }}
                  >
                    <option value="">-- Chọn danh mục --</option>
                    {categories.map((c, i) => (
                      <option key={`modal_cat_opt_${c.storeCode || ""}_${c.id || c.name}_${i}`} value={c.name}>
                        📂 {c.name}
                      </option>
                    ))}
                  </select>
                </div>
              </div>

              {productError && (
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
                  {productError}
                </div>
              )}

              <div style={{ display: "flex", gap: "10px", marginTop: "8px" }}>
                <button className="btn-secondary" onClick={closeProductModal} style={{ flex: 1, justifyContent: "center" }}>
                  Hủy
                </button>
                <button
                  className="btn-primary"
                  onClick={handleSaveProduct}
                  disabled={productSaving}
                  style={{ flex: 1, justifyContent: "center", opacity: productSaving ? 0.7 : 1 }}
                >
                  {productSaving ? (
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
                  {editProductId ? "Cập nhật" : "Thêm mới"}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ==================== MODAL: ADD/EDIT CATEGORY ==================== */}
      {showCategoryModal && (
        <div className="modal-overlay" onClick={closeCategoryModal}>
          <div className="modal-content" style={{ maxWidth: "460px" }} onClick={(e) => e.stopPropagation()}>
            <div style={{ padding: "24px 24px 0", display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: "16px" }}>
              <h2 style={{ fontSize: "18px", fontWeight: "700", color: "#1C1A2D" }}>
                {editCategoryOriginalName ? "Chỉnh sửa danh mục" : "Thêm danh mục mới"}
              </h2>
              <button onClick={closeCategoryModal} style={{ background: "none", border: "none", color: "#5D5B63", cursor: "pointer" }}>
                <X size={20} />
              </button>
            </div>

            <div style={{ padding: "0 24px 24px", display: "flex", flexDirection: "column", gap: "14px" }}>
              <div>
                <label style={{ display: "block", fontSize: "13px", fontWeight: "600", color: "#8B8FA8", marginBottom: "6px" }}>
                  Tên danh mục *
                </label>
                <input
                  className="input-field"
                  placeholder="Ví dụ: Cà phê, Trà hoa quả, Bánh ngọt, Topping..."
                  value={categoryForm.name}
                  onChange={(e) => setCategoryForm((f) => ({ ...f, name: e.target.value }))}
                  autoFocus
                />
              </div>

              <div>
                <label style={{ display: "block", fontSize: "13px", fontWeight: "600", color: "#8B8FA8", marginBottom: "6px" }}>
                  Chi nhánh áp dụng
                </label>
                <select
                  className="input-field"
                  value={categoryForm.storeCode}
                  onChange={(e) => setCategoryForm((f) => ({ ...f, storeCode: e.target.value }))}
                >
                  <option value="ALL">🌐 Tất cả chi nhánh</option>
                  {stores.map((s) => (
                    <option key={s.storeCode} value={s.storeCode}>
                      🏪 {s.storeCode} - {s.storeName}
                    </option>
                  ))}
                </select>
              </div>

              {editCategoryOriginalName && (
                <div
                  style={{
                    background: "rgba(59,130,246,0.08)",
                    border: "1px solid rgba(59,130,246,0.2)",
                    borderRadius: "8px",
                    padding: "10px 14px",
                    color: "#1E40AF",
                    fontSize: "12px",
                  }}
                >
                  ℹ️ Lưu ý: Khi đổi tên danh mục, tất cả các sản phẩm thuộc danh mục cũ sẽ tự động được cập nhật sang tên mới.
                </div>
              )}

              {categoryError && (
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
                  {categoryError}
                </div>
              )}

              <div style={{ display: "flex", gap: "10px", marginTop: "8px" }}>
                <button className="btn-secondary" onClick={closeCategoryModal} style={{ flex: 1, justifyContent: "center" }}>
                  Hủy
                </button>
                <button
                  className="btn-primary"
                  onClick={handleSaveCategory}
                  disabled={categorySaving}
                  style={{ flex: 1, justifyContent: "center", opacity: categorySaving ? 0.7 : 1 }}
                >
                  {categorySaving ? (
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
                  {editCategoryOriginalName ? "Cập nhật" : "Tạo danh mục"}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ==================== MODAL: DELETE PRODUCT CONFIRM ==================== */}
      {deleteProductTarget && (
        <div className="modal-overlay" onClick={() => setDeleteProductTarget(null)}>
          <div className="modal-content" style={{ maxWidth: "420px" }} onClick={(e) => e.stopPropagation()}>
            <div style={{ padding: "28px", textAlign: "center" }}>
              <div style={{ fontSize: "48px", marginBottom: "16px" }}>🗑️</div>
              <h2 style={{ fontSize: "18px", fontWeight: "700", color: "#1C1A2D", marginBottom: "8px" }}>
                Xác nhận xóa món
              </h2>
              <p style={{ color: "#8B8FA8", fontSize: "14px", marginBottom: "24px" }}>
                Bạn có chắc muốn xóa món <strong>"{deleteProductTarget.name}"</strong>
                {deleteProductTarget.storeCode ? ` thuộc chi nhánh ${deleteProductTarget.storeCode}` : ""}? Hành động này không thể hoàn tác.
              </p>
              <div style={{ display: "flex", gap: "10px" }}>
                <button className="btn-secondary" onClick={() => setDeleteProductTarget(null)} style={{ flex: 1, justifyContent: "center" }}>
                  Hủy
                </button>
                <button className="btn-danger" onClick={handleDeleteProduct} style={{ flex: 1, justifyContent: "center" }}>
                  <Trash2 size={16} />
                  Xóa
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ==================== MODAL: DELETE CATEGORY CONFIRM ==================== */}
      {deleteCategoryTarget && (
        <div className="modal-overlay" onClick={() => setDeleteCategoryTarget(null)}>
          <div className="modal-content" style={{ maxWidth: "440px" }} onClick={(e) => e.stopPropagation()}>
            <div style={{ padding: "28px", textAlign: "center" }}>
              <div style={{ fontSize: "48px", marginBottom: "16px" }}>📁</div>
              <h2 style={{ fontSize: "18px", fontWeight: "700", color: "#1C1A2D", marginBottom: "8px" }}>
                Xác nhận xóa danh mục
              </h2>
              <p style={{ color: "#8B8FA8", fontSize: "14px", marginBottom: "14px" }}>
                Bạn có chắc muốn xóa danh mục <strong>"{deleteCategoryTarget.name}"</strong>
                {deleteCategoryTarget.storeCode ? ` khỏi chi nhánh ${deleteCategoryTarget.storeCode}` : ""}?
              </p>
              {(categoryStats.counts[deleteCategoryTarget.name] || 0) > 0 && (
                <div
                  style={{
                    background: "rgba(239,68,68,0.1)",
                    border: "1px solid rgba(239,68,68,0.3)",
                    borderRadius: "8px",
                    padding: "10px 14px",
                    color: "#EF4444",
                    fontSize: "13px",
                    marginBottom: "20px",
                    textAlign: "left",
                  }}
                >
                  ⚠️ Đang có{" "}
                  <strong>{categoryStats.counts[deleteCategoryTarget.name]} sản phẩm</strong> thuộc danh mục này. Khi xóa, các sản phẩm sẽ chuyển về trạng thái Chưa phân loại.
                </div>
              )}
              <div style={{ display: "flex", gap: "10px" }}>
                <button className="btn-secondary" onClick={() => setDeleteCategoryTarget(null)} style={{ flex: 1, justifyContent: "center" }}>
                  Hủy
                </button>
                <button className="btn-danger" onClick={handleDeleteCategory} style={{ flex: 1, justifyContent: "center" }}>
                  <Trash2 size={16} />
                  Xóa danh mục
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
