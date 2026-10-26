"use client";

import React, { useState, useEffect, useMemo, Suspense } from "react";
import { useSearchParams } from "next/navigation";
import { db } from "@/lib/firebase";
import { ref, onValue, push, set } from "firebase/database";
import {
  UtensilsCrossed,
  Bell,
  Search,
  Plus,
  Minus,
  ShoppingBag,
  CheckCircle2,
  Clock,
  X,
  Coffee,
  ChevronRight,
  RefreshCw,
  ChefHat,
  Receipt,
} from "lucide-react";

interface ProductSize {
  [sizeName: string]: number;
}

interface ProductItem {
  id?: number | string;
  name: string;
  code?: string;
  price: number;
  unit?: string;
  category: string;
  imageBase64?: string;
  imageResourceName?: string;
  isAvailable?: boolean;
  sizes?: ProductSize;
  allowedToppings?: string[];
  hasIceSugarOptions?: boolean;
}

interface CartItem {
  id: string;
  productId: number | string;
  name: string;
  basePrice: number;
  unitPrice: number;
  quantity: number;
  selectedSize: string;
  sizeExtraPrice: number;
  selectedSugar: string;
  selectedIce: string;
  selectedToppings: string[];
  toppingPrice: number;
  note: string;
}

const DEFAULT_TOPPING_PRICES: Record<string, number> = {
  "Trân châu đen": 10000,
  "Trân châu trắng": 10000,
  "Thạch phô mai": 12000,
  "Kem Cheese": 15000,
  "Đào miếng": 10000,
  "Sương sáo": 8000,
};

const DEFAULT_PRODUCTS: ProductItem[] = [
  {
    id: "sample_1",
    name: "Cà Phê Sữa Đá Trạm",
    price: 32000,
    category: "Cà Phê",
    isAvailable: true,
    sizes: { S: -4000, M: 0, L: 6000 },
    hasIceSugarOptions: true,
  },
  {
    id: "sample_2",
    name: "Cà Phê Muối Trạm",
    price: 35000,
    category: "Cà Phê",
    isAvailable: true,
    sizes: { M: 0, L: 6000 },
    hasIceSugarOptions: true,
  },
  {
    id: "sample_3",
    name: "Bạc Xỉu Kem Béo",
    price: 35000,
    category: "Cà Phê",
    isAvailable: true,
    sizes: { S: -4000, M: 0, L: 6000 },
    hasIceSugarOptions: true,
  },
  {
    id: "sample_4",
    name: "Trà Đào Cam Sả",
    price: 39000,
    category: "Trà Trái Cây",
    isAvailable: true,
    sizes: { M: 0, L: 8000 },
    allowedToppings: ["Đào miếng", "Trân châu trắng"],
    hasIceSugarOptions: true,
  },
  {
    id: "sample_5",
    name: "Trà Xoài Macchiato",
    price: 42000,
    category: "Trà Trái Cây",
    isAvailable: true,
    sizes: { M: 0, L: 8000 },
    allowedToppings: ["Kem Cheese", "Trân châu trắng"],
    hasIceSugarOptions: true,
  },
  {
    id: "sample_6",
    name: "Trà Sữa Ô Long Nướng",
    price: 38000,
    category: "Trà Sữa",
    isAvailable: true,
    sizes: { M: 0, L: 8000 },
    allowedToppings: ["Trân châu đen", "Trân châu trắng", "Thạch phô mai", "Kem Cheese"],
    hasIceSugarOptions: true,
  },
  {
    id: "sample_7",
    name: "Matcha Latte Nhật Bản",
    price: 45000,
    category: "Đặc Biệt",
    isAvailable: true,
    sizes: { M: 0, L: 8000 },
    hasIceSugarOptions: true,
  },
  {
    id: "sample_8",
    name: "Bánh Croissant Bơ Tỏi",
    price: 35000,
    category: "Bánh Ngọt",
    isAvailable: true,
  },
];

function formatVND(amount: number): string {
  return amount.toLocaleString("vi-VN") + "đ";
}

export default function OrderPage() {
  return (
    <Suspense
      fallback={
        <div style={{ background: "#F8F4EE", minHeight: "100vh", display: "flex", alignItems: "center", justifyContent: "center" }}>
          <div className="flex flex-col items-center gap-3">
            <div className="w-10 h-10 border-4 border-[#7E2930] border-t-transparent rounded-full animate-spin" />
            <p className="text-sm font-semibold text-[#7E2930]">Đang mở thực đơn Trạm F&amp;B...</p>
          </div>
        </div>
      }
    >
      <OrderContent />
    </Suspense>
  );
}

function OrderContent() {
  const searchParams = useSearchParams();
  const rawTable = searchParams.get("table") || "01";
  const rawZone = searchParams.get("zone") || "Khu A";
  const rawStore = searchParams.get("store") || "TRAM01";

  const [tableName] = useState(rawTable);
  const [tableZone] = useState(rawZone);
  const [storeCode] = useState(rawStore.toUpperCase().trim());

  // Store & Menu state
  const [storeName, setStoreName] = useState("Trạm F&B");
  const [products, setProducts] = useState<ProductItem[]>([]);
  const [categories, setCategories] = useState<string[]>([]);
  const [selectedCategory, setSelectedCategory] = useState("Tất cả");
  const [searchQuery, setSearchQuery] = useState("");
  const [loading, setLoading] = useState(true);

  // Cart & Customization Modal state
  const [cart, setCart] = useState<CartItem[]>([]);
  const [showCartModal, setShowCartModal] = useState(false);
  const [selectedProduct, setSelectedProduct] = useState<ProductItem | null>(null);

  // Customization Form
  const [selectedSize, setSelectedSize] = useState("M");
  const [selectedToppings, setSelectedToppings] = useState<string[]>([]);
  const [selectedSugar, setSelectedSugar] = useState("100% đường");
  const [selectedIce, setSelectedIce] = useState("100% đá");
  const [itemNote, setItemNote] = useState("");
  const [itemQty, setItemQty] = useState(1);
  const [orderNote, setOrderNote] = useState("");

  // Order submission & live tracking state
  const [submitting, setSubmitting] = useState(false);
  const [activeOrderId, setActiveOrderId] = useState<string | null>(null);
  const [activeOrderStatus, setActiveOrderStatus] = useState<string>("PENDING");
  const [callWaiterStatus, setCallWaiterStatus] = useState<string | null>(null);
  const [callingWaiter, setCallingWaiter] = useState(false);

  // 1. Listen to Store Info, Products & Categories
  useEffect(() => {
    // Listen to store info
    const storeInfoRef = ref(db, `stores/${storeCode}/storeInfo`);
    const unsubStore = onValue(storeInfoRef, (snap) => {
      if (snap.exists()) {
        const val = snap.val();
        setStoreName(val.storeName || "Trạm F&B");
      }
    });

    // Listen to products
    const productsRef = ref(db, `stores/${storeCode}/products`);
    const unsubProducts = onValue(productsRef, (snap) => {
      const list: ProductItem[] = [];
      if (snap.exists()) {
        const val = snap.val();
        if (typeof val === "object" && val !== null) {
          Object.entries(val).forEach(([key, raw]: [string, unknown]) => {
            const p = raw as Record<string, unknown> | null;
            if (p && p.isAvailable !== false) {
              list.push({
                ...p,
                id: (p.id as string | number) || key,
                name: (p.name as string) || key,
                price: Number(p.price || 0),
                category: (p.category as string) || "Khác",
              } as ProductItem);
            }
          });
        }
      }
      setProducts(list.length > 0 ? list : DEFAULT_PRODUCTS);
      setLoading(false);
    });

    // Listen to categories
    const categoriesRef = ref(db, `stores/${storeCode}/categories`);
    const unsubCategories = onValue(categoriesRef, (snap) => {
      const cats: string[] = [];
      if (snap.exists()) {
        const val = snap.val();
        if (typeof val === "object" && val !== null) {
          Object.values(val).forEach((c: unknown) => {
            const cat = c as { name?: string } | null;
            if (cat && cat.name) cats.push(cat.name);
          });
        }
      }
      setCategories(cats);
    });

    return () => {
      unsubStore();
      unsubProducts();
      unsubCategories();
    };
  }, [storeCode]);

  // 2. Listen to Active Order Status (Live Tracking)
  useEffect(() => {
    if (!activeOrderId) return;
    const orderRef = ref(db, `stores/${storeCode}/online_orders/${activeOrderId}`);
    const unsub = onValue(orderRef, (snap) => {
      if (snap.exists()) {
        const val = snap.val();
        setActiveOrderStatus(val.status || "PENDING");
      }
    });
    return () => unsub();
  }, [activeOrderId, storeCode]);

  // Available categories list
  const allCategories = useMemo(() => {
    const set = new Set<string>(["Tất cả"]);
    categories.forEach((c) => set.add(c));
    products.forEach((p) => {
      if (p.category) set.add(p.category);
    });
    return Array.from(set);
  }, [categories, products]);

  // Filtered products
  const filteredProducts = useMemo(() => {
    return products.filter((p) => {
      const matchCat = selectedCategory === "Tất cả" || p.category === selectedCategory;
      const matchQuery =
        !searchQuery.trim() ||
        p.name.toLowerCase().includes(searchQuery.toLowerCase().trim()) ||
        p.category.toLowerCase().includes(searchQuery.toLowerCase().trim());
      return matchCat && matchQuery;
    });
  }, [products, selectedCategory, searchQuery]);

  // Open Customization Modal
  const openCustomization = (p: ProductItem) => {
    setSelectedProduct(p);
    setSelectedSize("M");
    setSelectedToppings([]);
    setSelectedSugar("100% đường");
    setSelectedIce("100% đá");
    setItemNote("");
    setItemQty(1);
  };

  // Calculate Single Item Unit Price with Size & Toppings
  const currentModalUnitPrice = useMemo(() => {
    if (!selectedProduct) return 0;
    let base = selectedProduct.price;
    if (selectedProduct.sizes && selectedProduct.sizes[selectedSize] !== undefined) {
      base += selectedProduct.sizes[selectedSize];
    }
    const toppingTotal = selectedToppings.reduce(
      (sum, t) => sum + (DEFAULT_TOPPING_PRICES[t] || 10000),
      0
    );
    return Math.max(0, base + toppingTotal);
  }, [selectedProduct, selectedSize, selectedToppings]);

  // Add Item to Cart
  const handleAddToCart = () => {
    if (!selectedProduct) return;

    let sizeExtra = 0;
    if (selectedProduct.sizes && selectedProduct.sizes[selectedSize] !== undefined) {
      sizeExtra = selectedProduct.sizes[selectedSize];
    }

    const toppingTotal = selectedToppings.reduce(
      (sum, t) => sum + (DEFAULT_TOPPING_PRICES[t] || 10000),
      0
    );

    const unitPrice = Math.max(0, selectedProduct.price + sizeExtra + toppingTotal);
    const cartLineId = `${selectedProduct.id}_${selectedSize}_${selectedSugar}_${selectedIce}_${selectedToppings.sort().join(",")}_${itemNote.trim()}`;

    setCart((prev) => {
      const existingIdx = prev.findIndex((item) => item.id === cartLineId);
      if (existingIdx >= 0) {
        const next = [...prev];
        next[existingIdx] = {
          ...next[existingIdx],
          quantity: next[existingIdx].quantity + itemQty,
        };
        return next;
      }
      return [
        ...prev,
        {
          id: cartLineId,
          productId: selectedProduct.id || 0,
          name: selectedProduct.name,
          basePrice: selectedProduct.price,
          unitPrice,
          quantity: itemQty,
          selectedSize,
          sizeExtraPrice: sizeExtra,
          selectedSugar,
          selectedIce,
          selectedToppings: [...selectedToppings],
          toppingPrice: toppingTotal,
          note: itemNote.trim(),
        },
      ];
    });

    setSelectedProduct(null);
  };

  // Cart total calculations
  const totalCartQty = useMemo(() => cart.reduce((sum, item) => sum + item.quantity, 0), [cart]);
  const totalCartAmount = useMemo(() => cart.reduce((sum, item) => sum + item.unitPrice * item.quantity, 0), [cart]);

  // Submit Order to Firebase
  const handleSubmitOrder = async () => {
    if (cart.length === 0) return;
    setSubmitting(true);

    try {
      const orderItems = cart.map((c) => ({
        productId: c.productId,
        name: c.name,
        price: c.basePrice,
        quantity: c.quantity,
        selectedSize: c.selectedSize,
        sizeExtraPrice: c.sizeExtraPrice,
        selectedSugar: c.selectedSugar,
        selectedIce: c.selectedIce,
        selectedToppings: c.selectedToppings,
        toppingPrice: c.toppingPrice,
        itemTotal: c.unitPrice * c.quantity,
        note: c.note,
      }));

      const payload = {
        tableName,
        tableZone,
        storeCode,
        itemsJson: JSON.stringify(orderItems),
        status: "PENDING",
        type: "ORDER",
        platform: "WEB_QR",
        timestamp: Date.now(),
        notes: orderNote.trim(),
      };

      const onlineOrdersRef = ref(db, `stores/${storeCode}/online_orders`);
      const newOrderRef = push(onlineOrdersRef);
      await set(newOrderRef, payload);

      setActiveOrderId(newOrderRef.key);
      setActiveOrderStatus("PENDING");
      setCart([]);
      setOrderNote("");
      setShowCartModal(false);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "Vui lòng thử lại";
      alert("Không thể gửi đơn: " + msg);
    } finally {
      setSubmitting(false);
    }
  };

  // Call Waiter function
  const handleCallWaiter = async () => {
    if (callingWaiter) return;
    if (!confirm(`Bạn muốn gọi nhân viên phục vụ đến bàn ${tableName}?`)) return;
    setCallingWaiter(true);
    try {
      const payload = {
        tableName,
        tableZone,
        storeCode,
        type: "CALL_WAITER",
        status: "PENDING",
        platform: "WEB_QR",
        timestamp: Date.now(),
      };
      const onlineOrdersRef = ref(db, `stores/${storeCode}/online_orders`);
      const newRef = push(onlineOrdersRef);
      await set(newRef, payload);
      setCallWaiterStatus(`Đã gọi nhân viên! Phục vụ sẽ đến Bàn ${tableName} ngay.`);
      setTimeout(() => setCallWaiterStatus(null), 5000);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "Không xác định";
      alert("Lỗi gọi phục vụ: " + msg);
    } finally {
      setCallingWaiter(false);
    }
  };

  return (
    <div
      style={{
        backgroundColor: "#F8F4EE",
        color: "#1C1A2D",
        minHeight: "100vh",
        paddingBottom: "110px",
        fontFamily: "'Be Vietnam Pro', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif",
      }}
    >
      {/* 1. Header Nhận Diện Trạm F&B */}
      <header
        style={{
          position: "sticky",
          top: 0,
          zIndex: 30,
          background: "linear-gradient(135deg, #7E2930 0%, #5C1F24 100%)",
          color: "#FFFFFF",
          boxShadow: "0 4px 20px rgba(92, 31, 36, 0.25)",
          borderBottom: "1px solid rgba(255, 255, 255, 0.12)",
        }}
      >
        <div style={{ maxWidth: "480px", margin: "0 auto", padding: "12px 16px", display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          <div style={{ display: "flex", alignItems: "center", gap: "12px" }}>
            <div
              style={{
                width: "42px",
                height: "42px",
                borderRadius: "14px",
                background: "rgba(255, 255, 255, 0.15)",
                backdropFilter: "blur(8px)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                border: "1.5px solid rgba(255, 255, 255, 0.3)",
                boxShadow: "0 2px 8px rgba(0,0,0,0.15)",
                fontSize: "20px",
              }}
            >
              ☕
            </div>
            <div>
              <div style={{ display: "flex", alignItems: "center", gap: "6px" }}>
                <h1 style={{ fontWeight: 800, fontSize: "16px", letterSpacing: "0.5px", margin: 0 }}>
                  {storeName}
                </h1>
                <span
                  style={{
                    fontSize: "10px",
                    fontWeight: 700,
                    padding: "2px 6px",
                    borderRadius: "6px",
                    background: "#D97706",
                    color: "#FFFFFF",
                  }}
                >
                  {storeCode}
                </span>
              </div>
              <div
                style={{
                  display: "inline-flex",
                  alignItems: "center",
                  gap: "6px",
                  padding: "2px 8px",
                  borderRadius: "20px",
                  background: "rgba(0, 0, 0, 0.22)",
                  fontSize: "12px",
                  fontWeight: 600,
                  color: "#F6EFDF",
                  marginTop: "4px",
                }}
              >
                <span
                  style={{
                    width: "7px",
                    height: "7px",
                    borderRadius: "50%",
                    background: "#146A65",
                    boxShadow: "0 0 6px #4FB8AE",
                  }}
                />
                <span>Bàn {tableName} • {tableZone}</span>
              </div>
            </div>
          </div>

          {/* Quick Call Waiter Button */}
          <button
            onClick={handleCallWaiter}
            disabled={callingWaiter}
            style={{
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              justifyContent: "center",
              width: "46px",
              height: "46px",
              borderRadius: "14px",
              background: "#FFFFFF",
              color: "#7E2930",
              border: "1.5px solid #F6EFDF",
              boxShadow: "0 4px 12px rgba(0, 0, 0, 0.15)",
              cursor: "pointer",
              transition: "transform 0.15s",
            }}
            title="Gọi nhân viên phục vụ"
          >
            <Bell size={18} fill="#7E2930" />
            <span style={{ fontSize: "9px", fontWeight: 800, marginTop: "2px" }}>Gọi NV</span>
          </button>
        </div>

        {/* Notification Banner when calling waiter */}
        {callWaiterStatus && (
          <div
            style={{
              background: "#146A65",
              color: "#FFFFFF",
              fontSize: "12px",
              fontWeight: 600,
              padding: "8px 16px",
              textAlign: "center",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              gap: "6px",
              boxShadow: "inset 0 1px 3px rgba(0,0,0,0.2)",
            }}
          >
            <CheckCircle2 size={16} />
            <span>{callWaiterStatus}</span>
          </div>
        )}
      </header>

      {/* 2. Order Live Status Tracker (Tiến độ gọi món thời gian thực) */}
      {activeOrderId && (
        <div style={{ maxWidth: "480px", margin: "12px auto 0", padding: "0 16px" }}>
          <div
            style={{
              background: "#FFFFFF",
              borderRadius: "18px",
              padding: "16px",
              border: "1.5px solid #E6DEC8",
              boxShadow: "0 4px 14px rgba(126, 41, 48, 0.06)",
            }}
          >
            <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: "12px" }}>
              <div>
                <span style={{ fontSize: "11px", fontWeight: 700, color: "#8E8C94", textTransform: "uppercase", letterSpacing: "0.5px" }}>
                  Mã đơn hàng: #{activeOrderId.slice(-6).toUpperCase()}
                </span>
                <div style={{ fontSize: "14px", fontWeight: 800, color: "#7E2930", marginTop: "2px" }}>
                  Bàn {tableName} • {tableZone}
                </div>
              </div>

              <span
                style={{
                  fontSize: "12px",
                  fontWeight: 700,
                  padding: "4px 10px",
                  borderRadius: "20px",
                  display: "flex",
                  alignItems: "center",
                  gap: "5px",
                  background:
                    activeOrderStatus === "CONFIRMED"
                      ? "#E6F4F2"
                      : activeOrderStatus === "COMPLETED"
                      ? "#E3EFF7"
                      : "#FBEFD4",
                  color:
                    activeOrderStatus === "CONFIRMED"
                      ? "#146A65"
                      : activeOrderStatus === "COMPLETED"
                      ? "#1C4E6B"
                      : "#B45309",
                  border: `1px solid ${
                    activeOrderStatus === "CONFIRMED"
                      ? "#146A65"
                      : activeOrderStatus === "COMPLETED"
                      ? "#1C4E6B"
                      : "#D97706"
                  }`,
                }}
              >
                {activeOrderStatus === "CONFIRMED" ? (
                  <>
                    <ChefHat size={14} />
                    Đã duyệt • Đang làm
                  </>
                ) : activeOrderStatus === "COMPLETED" ? (
                  <>
                    <CheckCircle2 size={14} />
                    Đã phục vụ
                  </>
                ) : (
                  <>
                    <Clock size={14} className="animate-spin" />
                    Chờ thu ngân duyệt...
                  </>
                )}
              </span>
            </div>

            {/* Stepper Progress Indicator */}
            <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: "8px", marginTop: "8px" }}>
              <div
                style={{
                  padding: "8px",
                  borderRadius: "10px",
                  background: "#F6EFDF",
                  textAlign: "center",
                  border: "1px solid #E6DEC8",
                }}
              >
                <div style={{ fontSize: "11px", fontWeight: 700, color: "#7E2930" }}>1. Đã gửi đơn</div>
                <div style={{ fontSize: "10px", color: "#146A65", fontWeight: 600 }}>✓ Hoàn tất</div>
              </div>

              <div
                style={{
                  padding: "8px",
                  borderRadius: "10px",
                  background: activeOrderStatus === "CONFIRMED" || activeOrderStatus === "COMPLETED" ? "#E6F4F2" : "#FFFFFF",
                  textAlign: "center",
                  border: `1px solid ${activeOrderStatus === "CONFIRMED" || activeOrderStatus === "COMPLETED" ? "#146A65" : "#E6DEC8"}`,
                }}
              >
                <div style={{ fontSize: "11px", fontWeight: 700, color: activeOrderStatus === "CONFIRMED" || activeOrderStatus === "COMPLETED" ? "#146A65" : "#8E8C94" }}>
                  2. Pha chế
                </div>
                <div style={{ fontSize: "10px", color: "#8E8C94" }}>
                  {activeOrderStatus === "CONFIRMED" || activeOrderStatus === "COMPLETED" ? "Đang chuẩn bị" : "Chờ quầy"}
                </div>
              </div>

              <div
                style={{
                  padding: "8px",
                  borderRadius: "10px",
                  background: activeOrderStatus === "COMPLETED" ? "#E3EFF7" : "#FFFFFF",
                  textAlign: "center",
                  border: `1px solid ${activeOrderStatus === "COMPLETED" ? "#1C4E6B" : "#E6DEC8"}`,
                }}
              >
                <div style={{ fontSize: "11px", fontWeight: 700, color: activeOrderStatus === "COMPLETED" ? "#1C4E6B" : "#8E8C94" }}>
                  3. Lên món
                </div>
                <div style={{ fontSize: "10px", color: "#8E8C94" }}>
                  {activeOrderStatus === "COMPLETED" ? "Đã ra bàn" : "Chờ phục vụ"}
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* 3. Search Bar */}
      <div style={{ maxWidth: "480px", margin: "14px auto 0", padding: "0 16px" }}>
        <div style={{ position: "relative" }}>
          <Search
            size={18}
            style={{ position: "absolute", left: "14px", top: "50%", transform: "translateY(-50%)", color: "#8E8C94" }}
          />
          <input
            type="text"
            placeholder="Tìm cà phê, trà trái cây, topping..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            style={{
              width: "100%",
              padding: "11px 16px 11px 40px",
              background: "#FFFFFF",
              border: "1.5px solid #E6DEC8",
              borderRadius: "14px",
              fontSize: "14px",
              color: "#1C1A2D",
              boxShadow: "0 2px 6px rgba(28, 26, 45, 0.03)",
              outline: "none",
            }}
          />
          {searchQuery && (
            <button
              onClick={() => setSearchQuery("")}
              style={{ position: "absolute", right: "12px", top: "50%", transform: "translateY(-50%)", background: "none", border: "none", color: "#8E8C94", cursor: "pointer" }}
            >
              <X size={16} />
            </button>
          )}
        </div>
      </div>

      {/* 4. Category Tabs (Sticky Bar) */}
      <div
        style={{
          position: "sticky",
          top: "66px",
          zIndex: 20,
          background: "rgba(248, 244, 238, 0.96)",
          backdropFilter: "blur(10px)",
          borderBottom: "1px solid #E6DEC8",
          padding: "10px 0",
          marginTop: "10px",
        }}
      >
        <div
          style={{
            maxWidth: "480px",
            margin: "0 auto",
            padding: "0 16px",
            display: "flex",
            gap: "8px",
            overflowX: "auto",
            scrollbarWidth: "none",
          }}
        >
          {allCategories.map((cat) => {
            const isSelected = selectedCategory === cat;
            return (
              <button
                key={cat}
                onClick={() => setSelectedCategory(cat)}
                style={{
                  whiteSpace: "nowrap",
                  padding: "7px 15px",
                  borderRadius: "20px",
                  fontSize: "13px",
                  fontWeight: isSelected ? 700 : 600,
                  transition: "all 0.15s",
                  border: isSelected ? "1.5px solid #7E2930" : "1.5px solid #E6DEC8",
                  background: isSelected ? "#7E2930" : "#FFFFFF",
                  color: isSelected ? "#FFFFFF" : "#5D5B63",
                  boxShadow: isSelected ? "0 3px 10px rgba(126, 41, 48, 0.25)" : "none",
                  cursor: "pointer",
                }}
              >
                {cat}
              </button>
            );
          })}
        </div>
      </div>

      {/* 5. Product Grid Menu */}
      <main style={{ maxWidth: "480px", margin: "14px auto 0", padding: "0 16px" }}>
        {loading ? (
          <div style={{ display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", padding: "60px 0", color: "#8E8C94" }}>
            <RefreshCw size={32} className="animate-spin" style={{ color: "#7E2930", marginBottom: "12px" }} />
            <p style={{ fontSize: "14px", fontWeight: 600, color: "#7E2930" }}>Đang tải thực đơn Trạm...</p>
          </div>
        ) : filteredProducts.length === 0 ? (
          <div style={{ textAlign: "center", padding: "50px 20px", color: "#8E8C94" }}>
            <UtensilsCrossed size={44} style={{ margin: "0 auto 10px", opacity: 0.6 }} />
            <p style={{ fontSize: "15px", fontWeight: 700, color: "#1C1A2D" }}>Không tìm thấy món phù hợp</p>
            <p style={{ fontSize: "12px", color: "#8E8C94", marginTop: "4px" }}>Vui lòng thử tìm kiếm với tên món khác</p>
          </div>
        ) : (
          <div style={{ display: "grid", gridTemplateColumns: "repeat(2, 1fr)", gap: "12px" }}>
            {filteredProducts.map((p) => {
              const hasSizes = p.sizes && Object.keys(p.sizes).length > 0;
              return (
                <div
                  key={p.id || p.name}
                  onClick={() => openCustomization(p)}
                  style={{
                    background: "#FFFFFF",
                    borderRadius: "18px",
                    padding: "12px",
                    border: "1.5px solid #E6DEC8",
                    boxShadow: "0 4px 12px rgba(28, 26, 45, 0.04)",
                    display: "flex",
                    flexDirection: "column",
                    justifyContent: "space-between",
                    cursor: "pointer",
                    transition: "transform 0.15s, box-shadow 0.15s",
                  }}
                >
                  <div>
                    {/* Product Image / Icon placeholder */}
                    <div
                      style={{
                        width: "100%",
                        aspectRatio: "1/1",
                        borderRadius: "14px",
                        background: "#F6EFDF",
                        overflow: "hidden",
                        marginBottom: "10px",
                        position: "relative",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        border: "1px solid #ECE5D8",
                      }}
                    >
                      {p.imageBase64 ? (
                        /* eslint-disable-next-line @next/next/no-img-element */
                        <img
                          src={p.imageBase64}
                          alt={p.name}
                          style={{ width: "100%", height: "100%", objectFit: "cover" }}
                          loading="lazy"
                        />
                      ) : (
                        <div style={{ textAlign: "center", color: "#7E2930" }}>
                          <Coffee size={36} strokeWidth={1.5} />
                          <div style={{ fontSize: "10px", fontWeight: 700, marginTop: "2px", opacity: 0.8 }}>TRẠM</div>
                        </div>
                      )}

                      {/* Add button pill */}
                      <button
                        style={{
                          position: "absolute",
                          bottom: "8px",
                          right: "8px",
                          width: "32px",
                          height: "32px",
                          borderRadius: "50%",
                          background: "#7E2930",
                          color: "#FFFFFF",
                          border: "none",
                          display: "flex",
                          alignItems: "center",
                          justifyContent: "center",
                          boxShadow: "0 3px 8px rgba(126, 41, 48, 0.35)",
                          cursor: "pointer",
                        }}
                        title="Chọn món"
                      >
                        <Plus size={18} strokeWidth={2.5} />
                      </button>
                    </div>

                    <h3
                      style={{
                        fontWeight: 700,
                        fontSize: "13px",
                        lineHeight: 1.35,
                        color: "#1C1A2D",
                        margin: 0,
                        display: "-webkit-box",
                        WebkitLineClamp: 2,
                        WebkitBoxOrient: "vertical",
                        overflow: "hidden",
                      }}
                    >
                      {p.name}
                    </h3>
                    <div style={{ fontSize: "11px", color: "#8E8C94", marginTop: "3px" }}>{p.category}</div>
                  </div>

                  <div
                    style={{
                      marginTop: "10px",
                      paddingTop: "8px",
                      borderTop: "1px solid #F6EFDF",
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "space-between",
                    }}
                  >
                    <span style={{ fontWeight: 800, fontSize: "14px", color: "#7E2930" }}>
                      {formatVND(p.price)}
                    </span>
                    {hasSizes && (
                      <span
                        style={{
                          fontSize: "10px",
                          fontWeight: 700,
                          color: "#7E2930",
                          background: "#FBECEE",
                          padding: "2px 6px",
                          borderRadius: "6px",
                        }}
                      >
                        Chọn size
                      </span>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </main>

      {/* 6. Sticky Floating Cart Bar (Đỏ mận Trạm) */}
      {cart.length > 0 && (
        <div
          style={{
            position: "fixed",
            bottom: "16px",
            left: 0,
            right: 0,
            zIndex: 40,
            padding: "0 16px",
          }}
        >
          <div
            style={{
              maxWidth: "480px",
              margin: "0 auto",
              background: "linear-gradient(135deg, #7E2930 0%, #5C1F24 100%)",
              color: "#FFFFFF",
              borderRadius: "20px",
              padding: "12px 18px",
              boxShadow: "0 8px 25px rgba(92, 31, 36, 0.4)",
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
              border: "1.5px solid rgba(255, 255, 255, 0.2)",
            }}
          >
            <div
              onClick={() => setShowCartModal(true)}
              style={{ display: "flex", alignItems: "center", gap: "12px", cursor: "pointer" }}
            >
              <div style={{ position: "relative" }}>
                <div
                  style={{
                    width: "44px",
                    height: "44px",
                    borderRadius: "14px",
                    background: "rgba(255, 255, 255, 0.18)",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    border: "1px solid rgba(255, 255, 255, 0.3)",
                  }}
                >
                  <ShoppingBag size={22} color="#FFFFFF" />
                </div>
                <span
                  style={{
                    position: "absolute",
                    top: "-6px",
                    right: "-6px",
                    minWidth: "20px",
                    height: "20px",
                    padding: "0 4px",
                    borderRadius: "10px",
                    background: "#D97706",
                    color: "#FFFFFF",
                    fontSize: "11px",
                    fontWeight: 800,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    border: "2px solid #7E2930",
                  }}
                >
                  {totalCartQty}
                </span>
              </div>

              <div>
                <div style={{ fontSize: "11px", color: "#F6EFDF", fontWeight: 600 }}>Giỏ hàng bàn {tableName}</div>
                <div style={{ fontSize: "17px", fontWeight: 900, color: "#FFFFFF", letterSpacing: "0.2px" }}>
                  {formatVND(totalCartAmount)}
                </div>
              </div>
            </div>

            <button
              onClick={() => setShowCartModal(true)}
              style={{
                background: "#FFFFFF",
                color: "#7E2930",
                border: "none",
                borderRadius: "12px",
                padding: "10px 16px",
                fontWeight: 800,
                fontSize: "13px",
                display: "flex",
                alignItems: "center",
                gap: "6px",
                cursor: "pointer",
                boxShadow: "0 3px 10px rgba(0, 0, 0, 0.15)",
              }}
            >
              <span>Xem giỏ</span>
              <ChevronRight size={16} strokeWidth={2.5} />
            </button>
          </div>
        </div>
      )}

      {/* 7. Product Customization Modal (Drawer Tùy Chỉnh Món) */}
      {selectedProduct && (
        <div
          style={{
            position: "fixed",
            inset: 0,
            zIndex: 50,
            background: "rgba(28, 26, 45, 0.65)",
            backdropFilter: "blur(4px)",
            display: "flex",
            alignItems: "flex-end",
            justifyContent: "center",
          }}
          onClick={() => setSelectedProduct(null)}
        >
          <div
            style={{
              width: "100%",
              maxWidth: "480px",
              background: "#FFFFFF",
              borderTopLeftRadius: "24px",
              borderTopRightRadius: "24px",
              maxHeight: "88vh",
              display: "flex",
              flexDirection: "column",
              overflow: "hidden",
              boxShadow: "0 -10px 40px rgba(0, 0, 0, 0.2)",
            }}
            onClick={(e) => e.stopPropagation()}
          >
            {/* Modal Header */}
            <div
              style={{
                padding: "16px 20px",
                borderBottom: "1px solid #E6DEC8",
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
                background: "#FAF7F2",
              }}
            >
              <div style={{ display: "flex", alignItems: "center", gap: "12px" }}>
                <div
                  style={{
                    width: "48px",
                    height: "48px",
                    borderRadius: "12px",
                    background: "#F6EFDF",
                    overflow: "hidden",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    border: "1px solid #ECE5D8",
                  }}
                >
                  {selectedProduct.imageBase64 ? (
                    /* eslint-disable-next-line @next/next/no-img-element */
                    <img src={selectedProduct.imageBase64} alt="" style={{ width: "100%", height: "100%", objectFit: "cover" }} />
                  ) : (
                    <Coffee size={24} color="#7E2930" />
                  )}
                </div>
                <div>
                  <h3 style={{ fontSize: "15px", fontWeight: 800, color: "#1C1A2D", margin: 0 }}>
                    {selectedProduct.name}
                  </h3>
                  <div style={{ fontSize: "15px", fontWeight: 900, color: "#7E2930", marginTop: "2px" }}>
                    {formatVND(currentModalUnitPrice)}
                  </div>
                </div>
              </div>

              <button
                onClick={() => setSelectedProduct(null)}
                style={{
                  width: "32px",
                  height: "32px",
                  borderRadius: "50%",
                  background: "#E6DEC8",
                  color: "#1C1A2D",
                  border: "none",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  cursor: "pointer",
                }}
              >
                <X size={18} />
              </button>
            </div>

            {/* Modal Body */}
            <div style={{ padding: "18px 20px", overflowY: "auto", display: "flex", flexDirection: "column", gap: "18px" }}>
              {/* Size Selection */}
              {selectedProduct.sizes && Object.keys(selectedProduct.sizes).length > 0 && (
                <div>
                  <label style={{ fontSize: "12px", fontWeight: 800, color: "#7E2930", textTransform: "uppercase", letterSpacing: "0.5px", display: "block", marginBottom: "8px" }}>
                    1. Kích thước (Size)
                  </label>
                  <div style={{ display: "grid", gridTemplateColumns: `repeat(${Object.keys(selectedProduct.sizes).length}, 1fr)`, gap: "8px" }}>
                    {Object.entries(selectedProduct.sizes).map(([sName, sExtra]) => {
                      const isSel = selectedSize === sName;
                      return (
                        <button
                          key={sName}
                          onClick={() => setSelectedSize(sName)}
                          style={{
                            padding: "10px 8px",
                            borderRadius: "12px",
                            border: isSel ? "2px solid #7E2930" : "1.5px solid #E6DEC8",
                            background: isSel ? "#FBECEE" : "#FFFFFF",
                            color: isSel ? "#7E2930" : "#1C1A2D",
                            textAlign: "center",
                            cursor: "pointer",
                          }}
                        >
                          <div style={{ fontWeight: 800, fontSize: "14px" }}>Size {sName}</div>
                          <div style={{ fontSize: "11px", fontWeight: 600, color: isSel ? "#7E2930" : "#8E8C94", marginTop: "2px" }}>
                            {sExtra > 0 ? `+${formatVND(sExtra)}` : sExtra < 0 ? formatVND(sExtra) : "Chuẩn"}
                          </div>
                        </button>
                      );
                    })}
                  </div>
                </div>
              )}

              {/* Sugar & Ice options */}
              {selectedProduct.hasIceSugarOptions !== false && (
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "12px" }}>
                  <div>
                    <label style={{ fontSize: "12px", fontWeight: 800, color: "#7E2930", textTransform: "uppercase", display: "block", marginBottom: "6px" }}>
                      Mức Đường
                    </label>
                    <select
                      value={selectedSugar}
                      onChange={(e) => setSelectedSugar(e.target.value)}
                      style={{
                        width: "100%",
                        padding: "9px 12px",
                        borderRadius: "10px",
                        border: "1.5px solid #E6DEC8",
                        background: "#FFFFFF",
                        fontSize: "13px",
                        fontWeight: 600,
                        color: "#1C1A2D",
                      }}
                    >
                      <option value="100% đường">100% đường (chuẩn)</option>
                      <option value="70% đường">70% đường (ít ngọt)</option>
                      <option value="50% đường">50% đường</option>
                      <option value="30% đường">30% đường</option>
                      <option value="0% đường">Không đường</option>
                    </select>
                  </div>

                  <div>
                    <label style={{ fontSize: "12px", fontWeight: 800, color: "#7E2930", textTransform: "uppercase", display: "block", marginBottom: "6px" }}>
                      Mức Đá
                    </label>
                    <select
                      value={selectedIce}
                      onChange={(e) => setSelectedIce(e.target.value)}
                      style={{
                        width: "100%",
                        padding: "9px 12px",
                        borderRadius: "10px",
                        border: "1.5px solid #E6DEC8",
                        background: "#FFFFFF",
                        fontSize: "13px",
                        fontWeight: 600,
                        color: "#1C1A2D",
                      }}
                    >
                      <option value="100% đá">100% đá (chuẩn)</option>
                      <option value="70% đá">70% đá (ít đá)</option>
                      <option value="50% đá">50% đá</option>
                      <option value="Không đá">Không đá</option>
                      <option value="Nóng">Uống Nóng ♨</option>
                    </select>
                  </div>
                </div>
              )}

              {/* Toppings Checklist */}
              {selectedProduct.allowedToppings && selectedProduct.allowedToppings.length > 0 && (
                <div>
                  <label style={{ fontSize: "12px", fontWeight: 800, color: "#7E2930", textTransform: "uppercase", letterSpacing: "0.5px", display: "block", marginBottom: "8px" }}>
                    2. Thêm Topping
                  </label>
                  <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "8px" }}>
                    {selectedProduct.allowedToppings.map((top) => {
                      const isSel = selectedToppings.includes(top);
                      const price = DEFAULT_TOPPING_PRICES[top] || 10000;
                      return (
                        <div
                          key={top}
                          onClick={() => {
                            setSelectedToppings((prev) =>
                              isSel ? prev.filter((t) => t !== top) : [...prev, top]
                            );
                          }}
                          style={{
                            padding: "8px 10px",
                            borderRadius: "10px",
                            border: isSel ? "2px solid #7E2930" : "1.5px solid #E6DEC8",
                            background: isSel ? "#FBECEE" : "#FFFFFF",
                            display: "flex",
                            alignItems: "center",
                            justifyContent: "space-between",
                            cursor: "pointer",
                          }}
                        >
                          <div>
                            <div style={{ fontSize: "12px", fontWeight: 700, color: isSel ? "#7E2930" : "#1C1A2D" }}>{top}</div>
                            <div style={{ fontSize: "11px", color: isSel ? "#7E2930" : "#8E8C94", fontWeight: 600 }}>+{formatVND(price)}</div>
                          </div>
                          <div
                            style={{
                              width: "18px",
                              height: "18px",
                              borderRadius: "6px",
                              border: isSel ? "2px solid #7E2930" : "2px solid #D8CFBD",
                              background: isSel ? "#7E2930" : "#FFFFFF",
                              display: "flex",
                              alignItems: "center",
                              justifyContent: "center",
                              color: "#FFFFFF",
                              fontSize: "11px",
                              fontWeight: 900,
                            }}
                          >
                            {isSel ? "✓" : ""}
                          </div>
                        </div>
                      );
                    })}
                  </div>
                </div>
              )}

              {/* Item Note */}
              <div>
                <label style={{ fontSize: "12px", fontWeight: 800, color: "#7E2930", textTransform: "uppercase", display: "block", marginBottom: "6px" }}>
                  Ghi chú cho món này
                </label>
                <input
                  type="text"
                  placeholder="Ví dụ: ít đá, để đá riêng..."
                  value={itemNote}
                  onChange={(e) => setItemNote(e.target.value)}
                  style={{
                    width: "100%",
                    padding: "9px 12px",
                    borderRadius: "10px",
                    border: "1.5px solid #E6DEC8",
                    fontSize: "13px",
                    color: "#1C1A2D",
                    outline: "none",
                  }}
                />
              </div>

              {/* Quantity Counter */}
              <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", paddingTop: "8px", borderTop: "1px solid #F6EFDF" }}>
                <span style={{ fontSize: "13px", fontWeight: 700, color: "#1C1A2D" }}>Số lượng:</span>
                <div style={{ display: "flex", alignItems: "center", gap: "10px", background: "#FAF7F2", padding: "4px 8px", borderRadius: "12px", border: "1px solid #E6DEC8" }}>
                  <button
                    onClick={() => setItemQty(Math.max(1, itemQty - 1))}
                    style={{
                      width: "30px",
                      height: "30px",
                      borderRadius: "8px",
                      background: "#FFFFFF",
                      border: "1px solid #E6DEC8",
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "center",
                      color: "#7E2930",
                      cursor: "pointer",
                    }}
                  >
                    <Minus size={14} />
                  </button>
                  <span style={{ fontWeight: 800, fontSize: "15px", minWidth: "24px", textAlign: "center" }}>{itemQty}</span>
                  <button
                    onClick={() => setItemQty(itemQty + 1)}
                    style={{
                      width: "30px",
                      height: "30px",
                      borderRadius: "8px",
                      background: "#7E2930",
                      border: "none",
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "center",
                      color: "#FFFFFF",
                      cursor: "pointer",
                    }}
                  >
                    <Plus size={14} />
                  </button>
                </div>
              </div>
            </div>

            {/* Modal Footer Submit */}
            <div style={{ padding: "14px 20px", borderTop: "1px solid #E6DEC8", background: "#FAF7F2" }}>
              <button
                onClick={handleAddToCart}
                style={{
                  width: "100%",
                  padding: "13px",
                  borderRadius: "14px",
                  background: "linear-gradient(135deg, #7E2930 0%, #5C1F24 100%)",
                  color: "#FFFFFF",
                  border: "none",
                  fontWeight: 800,
                  fontSize: "15px",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  gap: "8px",
                  boxShadow: "0 4px 14px rgba(126, 41, 48, 0.35)",
                  cursor: "pointer",
                }}
              >
                <span>Thêm vào giỏ</span>
                <span>•</span>
                <span>{formatVND(currentModalUnitPrice * itemQty)}</span>
              </button>
            </div>
          </div>
        </div>
      )}

      {/* 8. Cart Review & Checkout Modal */}
      {showCartModal && (
        <div
          style={{
            position: "fixed",
            inset: 0,
            zIndex: 50,
            background: "rgba(28, 26, 45, 0.65)",
            backdropFilter: "blur(4px)",
            display: "flex",
            alignItems: "flex-end",
            justifyContent: "center",
          }}
          onClick={() => setShowCartModal(false)}
        >
          <div
            style={{
              width: "100%",
              maxWidth: "480px",
              background: "#FFFFFF",
              borderTopLeftRadius: "24px",
              borderTopRightRadius: "24px",
              maxHeight: "88vh",
              display: "flex",
              flexDirection: "column",
              overflow: "hidden",
              boxShadow: "0 -10px 40px rgba(0, 0, 0, 0.2)",
            }}
            onClick={(e) => e.stopPropagation()}
          >
            {/* Header */}
            <div
              style={{
                padding: "16px 20px",
                borderBottom: "1px solid #E6DEC8",
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
                background: "linear-gradient(135deg, #7E2930 0%, #5C1F24 100%)",
                color: "#FFFFFF",
              }}
            >
              <div style={{ display: "flex", alignItems: "center", gap: "8px", fontWeight: 800, fontSize: "16px" }}>
                <ShoppingBag size={20} />
                <span>Giỏ Hàng Bàn {tableName}</span>
              </div>
              <button
                onClick={() => setShowCartModal(false)}
                style={{ background: "none", border: "none", color: "#FFFFFF", cursor: "pointer" }}
              >
                <X size={20} />
              </button>
            </div>

            {/* Cart Items List */}
            <div style={{ padding: "16px 20px", overflowY: "auto", display: "flex", flexDirection: "column", gap: "12px" }}>
              {cart.map((item, idx) => (
                <div
                  key={item.id + idx}
                  style={{
                    background: "#FAF7F2",
                    borderRadius: "14px",
                    padding: "12px",
                    border: "1.5px solid #E6DEC8",
                    display: "flex",
                    alignItems: "flex-start",
                    justifyContent: "space-between",
                    gap: "10px",
                  }}
                >
                  <div style={{ flex: 1 }}>
                    <div style={{ fontWeight: 800, fontSize: "14px", color: "#1C1A2D" }}>{item.name}</div>
                    <div style={{ fontSize: "12px", color: "#7E2930", fontWeight: 700, marginTop: "2px" }}>
                      {formatVND(item.unitPrice)} x {item.quantity} = {formatVND(item.unitPrice * item.quantity)}
                    </div>

                    {/* Options list */}
                    <div style={{ display: "flex", flexWrap: "wrap", gap: "4px", marginTop: "6px" }}>
                      <span style={{ fontSize: "10px", fontWeight: 700, padding: "2px 6px", borderRadius: "4px", background: "#FBECEE", color: "#7E2930" }}>
                        Size {item.selectedSize}
                      </span>
                      <span style={{ fontSize: "10px", padding: "2px 6px", borderRadius: "4px", background: "#FFFFFF", border: "1px solid #E6DEC8", color: "#5D5B63" }}>
                        {item.selectedSugar}
                      </span>
                      <span style={{ fontSize: "10px", padding: "2px 6px", borderRadius: "4px", background: "#FFFFFF", border: "1px solid #E6DEC8", color: "#5D5B63" }}>
                        {item.selectedIce}
                      </span>
                      {item.selectedToppings.map((top) => (
                        <span key={top} style={{ fontSize: "10px", padding: "2px 6px", borderRadius: "4px", background: "#E6F4F2", color: "#146A65", fontWeight: 600 }}>
                          +{top}
                        </span>
                      ))}
                    </div>

                    {item.note && (
                      <div style={{ fontSize: "11px", color: "#B45309", fontStyle: "italic", marginTop: "4px" }}>
                        Ghi chú: {item.note}
                      </div>
                    )}
                  </div>

                  {/* Quantity adjustment / remove */}
                  <div style={{ display: "flex", alignItems: "center", gap: "6px" }}>
                    <button
                      onClick={() => {
                        if (item.quantity === 1) {
                          setCart((prev) => prev.filter((_, i) => i !== idx));
                        } else {
                          setCart((prev) => {
                            const next = [...prev];
                            next[idx] = { ...next[idx], quantity: next[idx].quantity - 1 };
                            return next;
                          });
                        }
                      }}
                      style={{
                        width: "28px",
                        height: "28px",
                        borderRadius: "8px",
                        background: "#FFFFFF",
                        border: "1px solid #E6DEC8",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        color: "#7E2930",
                        cursor: "pointer",
                      }}
                    >
                      <Minus size={13} />
                    </button>
                    <span style={{ fontWeight: 800, fontSize: "13px", minWidth: "18px", textAlign: "center" }}>
                      {item.quantity}
                    </span>
                    <button
                      onClick={() => {
                        setCart((prev) => {
                          const next = [...prev];
                          next[idx] = { ...next[idx], quantity: next[idx].quantity + 1 };
                          return next;
                        });
                      }}
                      style={{
                        width: "28px",
                        height: "28px",
                        borderRadius: "8px",
                        background: "#7E2930",
                        border: "none",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        color: "#FFFFFF",
                        cursor: "pointer",
                      }}
                    >
                      <Plus size={13} />
                    </button>
                  </div>
                </div>
              ))}

              {/* Order Note Field */}
              <div style={{ marginTop: "6px" }}>
                <label style={{ fontSize: "12px", fontWeight: 800, color: "#7E2930", display: "block", marginBottom: "6px" }}>
                  Ghi chú chung cho đơn hàng (Bàn {tableName}):
                </label>
                <textarea
                  placeholder="Ví dụ: Giao cùng lúc, mang thêm ly nước đá..."
                  value={orderNote}
                  onChange={(e) => setOrderNote(e.target.value)}
                  rows={2}
                  style={{
                    width: "100%",
                    padding: "10px 12px",
                    borderRadius: "12px",
                    border: "1.5px solid #E6DEC8",
                    fontSize: "13px",
                    color: "#1C1A2D",
                    outline: "none",
                    resize: "none",
                  }}
                />
              </div>

              {/* Order Summary */}
              <div
                style={{
                  background: "#F6EFDF",
                  borderRadius: "14px",
                  padding: "12px 14px",
                  border: "1px solid #E6DEC8",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "space-between",
                }}
              >
                <span style={{ fontSize: "13px", fontWeight: 700, color: "#1C1A2D" }}>
                  Tổng cộng ({totalCartQty} món):
                </span>
                <span style={{ fontSize: "18px", fontWeight: 900, color: "#7E2930" }}>
                  {formatVND(totalCartAmount)}
                </span>
              </div>
            </div>

            {/* Footer Submit Button */}
            <div style={{ padding: "14px 20px", borderTop: "1px solid #E6DEC8", background: "#FAF7F2" }}>
              <button
                onClick={handleSubmitOrder}
                disabled={submitting || cart.length === 0}
                style={{
                  width: "100%",
                  padding: "14px",
                  borderRadius: "14px",
                  background: "linear-gradient(135deg, #7E2930 0%, #5C1F24 100%)",
                  color: "#FFFFFF",
                  border: "none",
                  fontWeight: 900,
                  fontSize: "16px",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  gap: "8px",
                  boxShadow: "0 4px 16px rgba(126, 41, 48, 0.4)",
                  cursor: submitting ? "not-allowed" : "pointer",
                  opacity: submitting ? 0.7 : 1,
                }}
              >
                {submitting ? (
                  <>
                    <RefreshCw size={18} className="animate-spin" />
                    <span>Đang gửi đơn xuống quán...</span>
                  </>
                ) : (
                  <>
                    <Receipt size={18} />
                    <span>Xác Nhận Gọi Món ({formatVND(totalCartAmount)})</span>
                  </>
                )}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
