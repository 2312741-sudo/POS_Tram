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
  ShoppingCart,
  CheckCircle2,
  Clock,
  Sparkles,
  X,
  Coffee,
  ChevronRight,
  RefreshCw,
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
  id: string; // unique cart line id
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

function formatVND(amount: number): string {
  return amount.toLocaleString("vi-VN") + "đ";
}

function OrderContent() {
  const searchParams = useSearchParams();
  const rawTable = searchParams.get("table") || "Bàn 01";
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
      setProducts(list);
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

  // Open customization modal
  const openCustomization = (product: ProductItem) => {
    setSelectedProduct(product);
    setSelectedSize(product.sizes && Object.keys(product.sizes).length > 0 ? Object.keys(product.sizes)[0] : "M");
    setSelectedToppings([]);
    setSelectedSugar("100% đường");
    setSelectedIce("100% đá");
    setItemNote("");
    setItemQty(1);
  };

  // Calculate unit price for modal item
  const currentModalUnitPrice = useMemo(() => {
    if (!selectedProduct) return 0;
    let base = selectedProduct.price;
    if (selectedProduct.sizes && selectedProduct.sizes[selectedSize]) {
      base += selectedProduct.sizes[selectedSize];
    }
    selectedToppings.forEach((top) => {
      base += DEFAULT_TOPPING_PRICES[top] || 10000;
    });
    return base;
  }, [selectedProduct, selectedSize, selectedToppings]);

  // Add customized item to cart
  const addToCart = () => {
    if (!selectedProduct) return;
    const sizeExtra = selectedProduct.sizes?.[selectedSize] || 0;
    const toppingTotal = selectedToppings.reduce(
      (sum, t) => sum + (DEFAULT_TOPPING_PRICES[t] || 10000),
      0
    );
    const unitPrice = selectedProduct.price + sizeExtra + toppingTotal;

    const cartLineId = `${selectedProduct.id}_${selectedSize}_${selectedSugar}_${selectedIce}_${selectedToppings.sort().join(",")}_${itemNote.trim()}`;

    setCart((prev) => {
      const existingIdx = prev.findIndex((item) => item.id === cartLineId);
      if (existingIdx >= 0) {
        const updated = [...prev];
        updated[existingIdx] = {
          ...updated[existingIdx],
          quantity: updated[existingIdx].quantity + itemQty,
        };
        return updated;
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

      // Push to stores/{storeCode}/online_orders
      const onlineOrdersRef = ref(db, `stores/${storeCode}/online_orders`);
      const newOrderRef = push(onlineOrdersRef);
      await set(newOrderRef, payload);

      // Dual-sync to root /online_orders if branch is TRAM01
      if (storeCode === "TRAM01") {
        const rootOnlineRef = ref(db, `online_orders/${newOrderRef.key}`);
        set(rootOnlineRef, payload).catch(() => {});
      }

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
    if (!confirm(`Bạn muốn gọi nhân viên phục vụ đến bàn ${tableName}?`)) return;
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
      setCallWaiterStatus("Đã báo nhân viên! Phục vụ sẽ đến bàn ngay.");
      setTimeout(() => setCallWaiterStatus(null), 5000);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "Không xác định";
      alert("Lỗi gọi phục vụ: " + msg);
    }
  };

  return (
    <div className="min-h-screen bg-stone-50 text-stone-900 pb-28 font-sans antialiased">
      {/* 1. Header */}
      <header className="sticky top-0 z-30 bg-gradient-to-r from-amber-600 to-orange-600 text-white shadow-md">
        <div className="max-w-md mx-auto px-4 py-3.5 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-full bg-white/20 backdrop-blur-sm flex items-center justify-center font-black text-lg border border-white/30">
              ☕
            </div>
            <div>
              <h1 className="font-bold text-base leading-tight tracking-wide">{storeName}</h1>
              <div className="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full bg-black/20 text-xs font-semibold text-amber-100 mt-0.5">
                <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse"></span>
                Bàn {tableName} • {tableZone}
              </div>
            </div>
          </div>
          <button
            onClick={handleCallWaiter}
            className="flex flex-col items-center justify-center w-11 h-11 rounded-full bg-white text-orange-600 shadow-md active:scale-95 transition-transform"
            title="Gọi nhân viên"
          >
            <Bell className="w-5 h-5 fill-current" />
            <span className="text-[9px] font-bold mt-0.5 leading-none">Gọi NV</span>
          </button>
        </div>

        {/* Call Waiter Notification Banner */}
        {callWaiterStatus && (
          <div className="bg-emerald-600 text-white text-xs font-medium px-4 py-2 text-center animate-fadeIn flex items-center justify-center gap-1.5 shadow-inner">
            <CheckCircle2 className="w-4 h-4" />
            {callWaiterStatus}
          </div>
        )}
      </header>

      {/* 2. Active Order Live Tracking Banner (If order placed) */}
      {activeOrderId && (
        <div className="max-w-md mx-auto px-4 mt-3">
          <div className="bg-white rounded-2xl p-4 shadow-sm border border-amber-200">
            <div className="flex items-center justify-between mb-2">
              <span className="text-xs font-bold text-stone-500 uppercase tracking-wider">
                Mã đơn: #{activeOrderId.slice(-6).toUpperCase()}
              </span>
              <span
                className={`text-xs font-bold px-2.5 py-1 rounded-full flex items-center gap-1 ${
                  activeOrderStatus === "CONFIRMED"
                    ? "bg-emerald-100 text-emerald-700"
                    : activeOrderStatus === "COMPLETED"
                    ? "bg-blue-100 text-blue-700"
                    : "bg-amber-100 text-amber-800"
                }`}
              >
                {activeOrderStatus === "CONFIRMED" ? (
                  <>
                    <Sparkles className="w-3.5 h-3.5" />
                    Quán đã nhận đơn
                  </>
                ) : activeOrderStatus === "COMPLETED" ? (
                  <>
                    <CheckCircle2 className="w-3.5 h-3.5" />
                    Đã hoàn tất
                  </>
                ) : (
                  <>
                    <Clock className="w-3.5 h-3.5 animate-spin" />
                    Chờ nhân viên duyệt...
                  </>
                )}
              </span>
            </div>
            <p className="text-xs text-stone-600 leading-relaxed">
              {activeOrderStatus === "CONFIRMED"
                ? "🎉 Quán đã nhận đơn và đang chuẩn bị món cho bạn! Món sẽ được mang ra bàn sớm."
                : activeOrderStatus === "COMPLETED"
                ? "✅ Món ăn đã phục vụ xong. Chúc bạn có trải nghiệm thật ngon miệng!"
                : "⏳ Đơn của bạn đã được gửi tới quầy thu ngân. Vui lòng chờ vài giây để quán xác nhận..."}
            </p>
          </div>
        </div>
      )}

      {/* 3. Search Bar */}
      <div className="max-w-md mx-auto px-4 mt-3">
        <div className="relative">
          <Search className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-stone-400" />
          <input
            type="text"
            placeholder="Tìm trà sữa, cafe, bánh nướng..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full pl-10 pr-4 py-2.5 bg-white border border-stone-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-amber-500 shadow-sm"
          />
        </div>
      </div>

      {/* 4. Category Tabs (Sticky) */}
      <div className="sticky top-[68px] z-20 bg-stone-50/95 backdrop-blur-md border-b border-stone-200/80 py-2.5 mt-2">
        <div className="max-w-md mx-auto px-4 flex gap-2 overflow-x-auto no-scrollbar">
          {allCategories.map((cat) => (
            <button
              key={cat}
              onClick={() => setSelectedCategory(cat)}
              className={`whitespace-nowrap px-4 py-1.5 rounded-full text-xs font-semibold transition-all ${
                selectedCategory === cat
                  ? "bg-amber-600 text-white shadow-sm"
                  : "bg-white text-stone-600 border border-stone-200 hover:bg-stone-100"
              }`}
            >
              {cat}
            </button>
          ))}
        </div>
      </div>

      {/* 5. Product Grid */}
      <main className="max-w-md mx-auto px-4 mt-4">
        {loading ? (
          <div className="flex flex-col items-center justify-center py-20 text-stone-400">
            <RefreshCw className="w-8 h-8 animate-spin text-amber-600 mb-3" />
            <p className="text-sm font-medium">Đang tải thực đơn...</p>
          </div>
        ) : filteredProducts.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-center text-stone-400">
            <UtensilsCrossed className="w-12 h-12 stroke-[1.5] mb-2" />
            <p className="font-semibold text-stone-600 text-sm">Không tìm thấy món phù hợp</p>
            <p className="text-xs text-stone-400 mt-1">Hãy thử tìm với từ khóa khác</p>
          </div>
        ) : (
          <div className="grid grid-cols-2 gap-3">
            {filteredProducts.map((p) => (
              <div
                key={p.id || p.name}
                onClick={() => openCustomization(p)}
                className="bg-white rounded-2xl p-3 shadow-sm border border-stone-200/80 flex flex-col justify-between cursor-pointer active:scale-[0.98] transition-transform"
              >
                <div>
                  <div className="w-full aspect-square rounded-xl bg-amber-50 overflow-hidden mb-2.5 relative flex items-center justify-center">
                    {p.imageBase64 ? (
                      <img
                        src={p.imageBase64}
                        alt={p.name}
                        className="w-full h-full object-cover"
                        loading="lazy"
                      />
                    ) : (
                      <Coffee className="w-10 h-10 text-amber-300 stroke-[1.5]" />
                    )}
                    <span className="absolute bottom-1.5 right-1.5 w-7 h-7 rounded-full bg-amber-600 text-white flex items-center justify-center shadow-md">
                      <Plus className="w-4 h-4 stroke-[2.5]" />
                    </span>
                  </div>
                  <h3 className="font-bold text-xs leading-snug line-clamp-2 text-stone-800">
                    {p.name}
                  </h3>
                  <p className="text-[11px] text-stone-400 mt-0.5">{p.category}</p>
                </div>
                <div className="mt-2 pt-2 border-t border-stone-100 flex items-center justify-between">
                  <span className="font-extrabold text-sm text-amber-600">
                    {formatVND(p.price)}
                  </span>
                  {p.sizes && Object.keys(p.sizes).length > 0 && (
                    <span className="text-[10px] text-stone-400 bg-stone-100 px-1.5 py-0.5 rounded">
                      Chọn size
                    </span>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}
      </main>

      {/* 6. Sticky Bottom Cart Bar */}
      {cart.length > 0 && (
        <div className="fixed bottom-0 left-0 right-0 z-40 bg-white/95 backdrop-blur-md border-t border-stone-200 p-3 shadow-xl">
          <div className="max-w-md mx-auto flex items-center justify-between gap-3">
            <div
              onClick={() => setShowCartModal(true)}
              className="flex items-center gap-3 cursor-pointer"
            >
              <div className="relative">
                <div className="w-12 h-12 rounded-2xl bg-amber-600 text-white flex items-center justify-center shadow-md shadow-amber-600/30">
                  <ShoppingCart className="w-6 h-6" />
                </div>
                <span className="absolute -top-1.5 -right-1.5 w-5 h-5 rounded-full bg-rose-600 text-white text-[11px] font-bold flex items-center justify-center border-2 border-white">
                  {totalCartQty}
                </span>
              </div>
              <div>
                <p className="text-xs text-stone-400 font-medium">Tổng tiền</p>
                <p className="text-base font-extrabold text-amber-600 leading-tight">
                  {formatVND(totalCartAmount)}
                </p>
              </div>
            </div>

            <button
              onClick={() => setShowCartModal(true)}
              className="flex-1 max-w-[200px] py-3 px-5 rounded-xl bg-gradient-to-r from-amber-600 to-orange-600 text-white font-bold text-sm shadow-md shadow-orange-600/30 flex items-center justify-center gap-1.5 active:scale-95 transition-transform"
            >
              <span>Xem giỏ hàng</span>
              <ChevronRight className="w-4 h-4" />
            </button>
          </div>
        </div>
      )}

      {/* 7. Product Customization Modal */}
      {selectedProduct && (
        <div className="fixed inset-0 z-50 bg-black/60 backdrop-blur-xs flex items-end sm:items-center justify-center p-0 sm:p-4 animate-fadeIn">
          <div className="bg-white w-full max-w-md rounded-t-3xl sm:rounded-3xl max-h-[90vh] flex flex-col overflow-hidden shadow-2xl animate-slideUp">
            {/* Modal Header */}
            <div className="p-4 border-b border-stone-100 flex items-center justify-between sticky top-0 bg-white z-10">
              <div className="flex items-center gap-3">
                <div className="w-12 h-12 rounded-xl bg-amber-50 overflow-hidden shrink-0 flex items-center justify-center">
                  {selectedProduct.imageBase64 ? (
                    <img src={selectedProduct.imageBase64} alt="" className="w-full h-full object-cover" />
                  ) : (
                    <Coffee className="w-6 h-6 text-amber-500" />
                  )}
                </div>
                <div>
                  <h3 className="font-bold text-sm text-stone-900 leading-snug">{selectedProduct.name}</h3>
                  <p className="text-xs font-extrabold text-amber-600 mt-0.5">
                    {formatVND(currentModalUnitPrice)}
                  </p>
                </div>
              </div>
              <button
                onClick={() => setSelectedProduct(null)}
                className="w-8 h-8 rounded-full bg-stone-100 flex items-center justify-center text-stone-400 hover:text-stone-700"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            {/* Modal Body */}
            <div className="p-4 overflow-y-auto space-y-4">
              {/* Size Selection */}
              {selectedProduct.sizes && Object.keys(selectedProduct.sizes).length > 0 && (
                <div>
                  <h4 className="text-xs font-bold text-stone-700 uppercase tracking-wider mb-2">
                    Chọn kích thước (Size)
                  </h4>
                  <div className="grid grid-cols-3 gap-2">
                    {Object.entries(selectedProduct.sizes).map(([sz, extra]) => (
                      <button
                        key={sz}
                        onClick={() => setSelectedSize(sz)}
                        className={`p-2.5 rounded-xl border text-center transition-all ${
                          selectedSize === sz
                            ? "border-amber-600 bg-amber-50/80 text-amber-800 font-bold"
                            : "border-stone-200 text-stone-600 hover:border-stone-300"
                        }`}
                      >
                        <div className="text-xs font-bold">Size {sz}</div>
                        <div className="text-[10px] text-stone-400 mt-0.5">
                          {extra > 0 ? `+${formatVND(extra)}` : "Chuẩn"}
                        </div>
                      </button>
                    ))}
                  </div>
                </div>
              )}

              {/* Topping Selection */}
              {selectedProduct.allowedToppings && selectedProduct.allowedToppings.length > 0 && (
                <div>
                  <h4 className="text-xs font-bold text-stone-700 uppercase tracking-wider mb-2">
                    Thêm Topping
                  </h4>
                  <div className="space-y-1.5">
                    {selectedProduct.allowedToppings.map((top) => {
                      const isSelected = selectedToppings.includes(top);
                      const topPrice = DEFAULT_TOPPING_PRICES[top] || 10000;
                      return (
                        <div
                          key={top}
                          onClick={() => {
                            setSelectedToppings((prev) =>
                              isSelected ? prev.filter((t) => t !== top) : [...prev, top]
                            );
                          }}
                          className={`p-2.5 rounded-xl border flex items-center justify-between cursor-pointer transition-all ${
                            isSelected
                              ? "border-amber-500 bg-amber-50/60 text-amber-900"
                              : "border-stone-200 text-stone-700 hover:border-stone-300"
                          }`}
                        >
                          <span className="text-xs font-medium">{top}</span>
                          <span className="text-xs font-bold text-amber-700">+{formatVND(topPrice)}</span>
                        </div>
                      );
                    })}
                  </div>
                </div>
              )}

              {/* Ice & Sugar options */}
              {selectedProduct.hasIceSugarOptions && (
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <h4 className="text-xs font-bold text-stone-700 uppercase tracking-wider mb-2">
                      Mức đường
                    </h4>
                    <select
                      value={selectedSugar}
                      onChange={(e) => setSelectedSugar(e.target.value)}
                      className="w-full text-xs font-medium p-2.5 bg-stone-50 border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-amber-500"
                    >
                      <option value="100% đường">100% đường (chuẩn)</option>
                      <option value="70% đường">70% đường (ít ngọt)</option>
                      <option value="50% đường">50% đường</option>
                      <option value="30% đường">30% đường</option>
                      <option value="0% đường">Không đường</option>
                    </select>
                  </div>
                  <div>
                    <h4 className="text-xs font-bold text-stone-700 uppercase tracking-wider mb-2">
                      Mức đá
                    </h4>
                    <select
                      value={selectedIce}
                      onChange={(e) => setSelectedIce(e.target.value)}
                      className="w-full text-xs font-medium p-2.5 bg-stone-50 border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-amber-500"
                    >
                      <option value="100% đá">100% đá (chuẩn)</option>
                      <option value="50% đá">50% đá (ít đá)</option>
                      <option value="30% đá">30% đá</option>
                      <option value="0% đá">Không đá</option>
                    </select>
                  </div>
                </div>
              )}

              {/* Note input */}
              <div>
                <h4 className="text-xs font-bold text-stone-700 uppercase tracking-wider mb-2">
                  Ghi chú cho món
                </h4>
                <input
                  type="text"
                  placeholder="Ví dụ: Để riêng đá, đậm trà..."
                  value={itemNote}
                  onChange={(e) => setItemNote(e.target.value)}
                  className="w-full text-xs p-2.5 bg-stone-50 border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-amber-500"
                />
              </div>

              {/* Quantity Selector */}
              <div className="flex items-center justify-between pt-2">
                <span className="text-xs font-bold text-stone-700 uppercase tracking-wider">Số lượng</span>
                <div className="flex items-center gap-3">
                  <button
                    onClick={() => setItemQty((q) => Math.max(1, q - 1))}
                    className="w-8 h-8 rounded-full border border-stone-300 flex items-center justify-center font-bold text-stone-600 active:bg-stone-100"
                  >
                    <Minus className="w-3.5 h-3.5" />
                  </button>
                  <span className="font-extrabold text-base w-6 text-center">{itemQty}</span>
                  <button
                    onClick={() => setItemQty((q) => q + 1)}
                    className="w-8 h-8 rounded-full bg-amber-600 text-white flex items-center justify-center font-bold active:bg-amber-700 shadow-sm"
                  >
                    <Plus className="w-3.5 h-3.5" />
                  </button>
                </div>
              </div>
            </div>

            {/* Modal Footer */}
            <div className="p-4 border-t border-stone-100 bg-stone-50">
              <button
                onClick={addToCart}
                className="w-full py-3.5 rounded-2xl bg-gradient-to-r from-amber-600 to-orange-600 text-white font-bold text-sm shadow-md shadow-orange-600/30 active:scale-95 transition-transform"
              >
                Thêm vào giỏ • {formatVND(currentModalUnitPrice * itemQty)}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* 8. Cart Review & Submit Modal */}
      {showCartModal && (
        <div className="fixed inset-0 z-50 bg-black/60 backdrop-blur-xs flex items-end sm:items-center justify-center p-0 sm:p-4 animate-fadeIn">
          <div className="bg-white w-full max-w-md rounded-t-3xl sm:rounded-3xl max-h-[90vh] flex flex-col overflow-hidden shadow-2xl animate-slideUp">
            {/* Header */}
            <div className="p-4 border-b border-stone-100 flex items-center justify-between">
              <div>
                <h3 className="font-bold text-base text-stone-900">Giỏ hàng của bạn</h3>
                <p className="text-xs text-stone-500">
                  Bàn {tableName} • {tableZone}
                </p>
              </div>
              <button
                onClick={() => setShowCartModal(false)}
                className="w-8 h-8 rounded-full bg-stone-100 flex items-center justify-center text-stone-400 hover:text-stone-700"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            {/* Item List */}
            <div className="p-4 overflow-y-auto space-y-3 flex-1">
              {cart.map((item, idx) => (
                <div key={item.id} className="p-3 bg-stone-50 rounded-2xl border border-stone-200/70">
                  <div className="flex items-start justify-between">
                    <div>
                      <h4 className="font-bold text-xs text-stone-900">{item.name}</h4>
                      <p className="text-[11px] text-stone-500 mt-0.5">
                        {item.selectedSize && `Size ${item.selectedSize}`}
                        {item.selectedToppings.length > 0 && ` + ${item.selectedToppings.join(", ")}`}
                      </p>
                      {(item.selectedSugar || item.selectedIce) && (
                        <p className="text-[10px] text-stone-400">
                          {item.selectedSugar} • {item.selectedIce}
                        </p>
                      )}
                      {item.note && (
                        <p className="text-[11px] text-amber-700 italic mt-0.5">
                          &quot;{item.note}&quot;
                        </p>
                      )}
                    </div>
                    <span className="font-bold text-xs text-amber-600">
                      {formatVND(item.unitPrice * item.quantity)}
                    </span>
                  </div>

                  <div className="flex items-center justify-between mt-2.5 pt-2 border-t border-stone-200/50">
                    <button
                      onClick={() => setCart((prev) => prev.filter((_, i) => i !== idx))}
                      className="text-[11px] text-rose-500 hover:text-rose-700 font-medium"
                    >
                      Xóa
                    </button>
                    <div className="flex items-center gap-2">
                      <button
                        onClick={() => {
                          if (item.quantity <= 1) {
                            setCart((prev) => prev.filter((_, i) => i !== idx));
                          } else {
                            setCart((prev) => {
                              const cp = [...prev];
                              cp[idx].quantity -= 1;
                              return cp;
                            });
                          }
                        }}
                        className="w-6 h-6 rounded-full bg-white border border-stone-200 flex items-center justify-center text-xs font-bold"
                      >
                        -
                      </button>
                      <span className="font-bold text-xs w-4 text-center">{item.quantity}</span>
                      <button
                        onClick={() => {
                          setCart((prev) => {
                            const cp = [...prev];
                            cp[idx].quantity += 1;
                            return cp;
                          });
                        }}
                        className="w-6 h-6 rounded-full bg-amber-600 text-white flex items-center justify-center text-xs font-bold"
                      >
                        +
                      </button>
                    </div>
                  </div>
                </div>
              ))}

              {/* Order global note */}
              <div className="mt-4">
                <label className="text-xs font-bold text-stone-700 uppercase tracking-wider mb-1 block">
                  Ghi chú cho cả đơn (tùy chọn)
                </label>
                <textarea
                  rows={2}
                  placeholder="Lời nhắn cho quán (ví dụ: làm nhanh giúp em nhé...)"
                  value={orderNote}
                  onChange={(e) => setOrderNote(e.target.value)}
                  className="w-full text-xs p-3 bg-stone-50 border border-stone-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-amber-500"
                />
              </div>
            </div>

            {/* Footer Summary & Submit */}
            <div className="p-4 border-t border-stone-100 bg-white">
              <div className="flex items-center justify-between mb-3">
                <span className="text-xs text-stone-500 font-medium">Tổng tiền thanh toán</span>
                <span className="text-lg font-extrabold text-amber-600">
                  {formatVND(totalCartAmount)}
                </span>
              </div>
              <button
                disabled={submitting}
                onClick={handleSubmitOrder}
                className="w-full py-3.5 rounded-2xl bg-gradient-to-r from-amber-600 to-orange-600 text-white font-bold text-sm shadow-md shadow-orange-600/30 flex items-center justify-center gap-2 active:scale-95 transition-transform disabled:opacity-50"
              >
                {submitting ? (
                  <>
                    <RefreshCw className="w-4 h-4 animate-spin" />
                    <span>Đang gửi đơn...</span>
                  </>
                ) : (
                  <span>Gửi Order Đến Quán</span>
                )}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export default function OrderPage() {
  return (
    <Suspense
      fallback={
        <div className="min-h-screen bg-stone-50 flex items-center justify-center text-stone-400">
          <RefreshCw className="w-8 h-8 animate-spin text-amber-600" />
        </div>
      }
    >
      <OrderContent />
    </Suspense>
  );
}
