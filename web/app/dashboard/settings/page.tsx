"use client";
import { useMemo, useState } from "react";
import { CheckCircle2, Clock, Settings, Store } from "lucide-react";
import { nowMs } from "@/lib/kitchen";
import { useDashboardData, type StoreItem } from "@/lib/data-context";
import { useAuth, canAccessRoute } from "@/lib/auth";
import { businessDateOf, formatMinutesAsTime, normalizeBusinessDayStart, parseTimeToMinutes } from "@/lib/business-day";

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

const label = { display: "block", fontSize: "12px", fontWeight: 700, marginBottom: "4px" } as const;

/** Cài đặt cửa hàng: thông tin, thanh toán QR, tùy chọn bán hàng và NGÀY KINH DOANH (giờ chia doanh thu qua 0h) */
export default function StoreSettingsPage() {
  const { stores, currentStoreCode, setCurrentStoreCode } = useDashboardData();
  const { user } = useAuth();
  const store = useMemo(() => stores.find((s) => s.storeCode === currentStoreCode), [stores, currentStoreCode]);

  if (!canAccessRoute(user, "/dashboard/settings")) {
    return <div className="card" style={{ padding: 24 }}>Bạn không có quyền cài đặt cửa hàng.</div>;
  }
  if (!store) {
    return (
      <div className="card" style={{ padding: 24, display: "flex", flexDirection: "column", gap: 12 }}>
        <div style={{ fontWeight: 700 }}>Chọn một cửa hàng để cài đặt</div>
        <select className="input-field" value="" onChange={(e) => e.target.value && setCurrentStoreCode(e.target.value)}>
          <option value="">-- Chọn cửa hàng --</option>
          {stores.map((s) => (
            <option key={s.storeCode} value={s.storeCode}>{s.storeCode} - {s.storeName}</option>
          ))}
        </select>
      </div>
    );
  }
  // key: nạp lại form khi đổi cửa hàng hoặc dữ liệu cửa hàng thay đổi từ nơi khác
  return <SettingsForm key={`${store.storeCode}:${store.businessDayStartMinute ?? 0}:${store.storeName}`} store={store} />;
}

function SettingsForm({ store }: { store: StoreItem }) {
  const { updateStore } = useDashboardData();
  const [storeName, setStoreName] = useState(store.storeName || "");
  const [address, setAddress] = useState(store.address || "");
  const [phone, setPhone] = useState(store.phone || "");
  const [wifiName, setWifiName] = useState(store.wifiName || "");
  const [bankId, setBankId] = useState(store.bankId || "MB");
  const [bankAccount, setBankAccount] = useState(store.bankAccount || "");
  const [accountName, setAccountName] = useState(store.accountName || "");
  const [vat, setVat] = useState(String(store.defaultVatRate ?? 0));
  const [allowStack, setAllowStack] = useState(store.allowStackPromotions !== false);
  const [allowViewDiff, setAllowViewDiff] = useState(store.allowStaffViewShiftDifference !== false);
  const [dayStart, setDayStart] = useState(formatMinutesAsTime(normalizeBusinessDayStart(store.businessDayStartMinute)));
  const [saving, setSaving] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);

  const startMin = parseTimeToMinutes(dayStart);
  const example = useMemo(() => {
    if (startMin == null || startMin === 0) return null;
    // Ví dụ minh họa: 01:30 sáng thuộc ngày nào
    const nowVn = new Date(nowMs() + 7 * 3600_000);
    const y = nowVn.getUTCFullYear(), m = nowVn.getUTCMonth(), d = nowVn.getUTCDate();
    const ts = Date.UTC(y, m, d, 1, 30) - 7 * 3600_000;
    const fmt = (ymd: string) => ymd.split("-").reverse().join("/");
    const today = `${String(d).padStart(2, "0")}/${String(m + 1).padStart(2, "0")}`;
    return `Hóa đơn lúc 01:30 sáng ${today} sẽ tính vào doanh thu ngày ${fmt(businessDateOf(ts, startMin))}.`;
  }, [startMin]);

  const save = async (e: React.FormEvent) => {
    e.preventDefault();
    setMsg(null);
    if (!storeName.trim()) return setMsg({ ok: false, text: "Vui lòng nhập tên cửa hàng." });
    if (startMin == null) return setMsg({ ok: false, text: "Giờ bắt đầu ngày kinh doanh không hợp lệ (định dạng HH:mm, từ 00:00 đến 12:00)." });
    if (startMin > 12 * 60) return setMsg({ ok: false, text: "Giờ bắt đầu ngày kinh doanh tối đa 12:00 trưa." });
    const vatNum = parseFloat(vat);
    setSaving(true);
    const res = await updateStore(store.storeCode, {
      storeName: storeName.trim(),
      address: address.trim(),
      phone: phone.trim(),
      wifiName: wifiName.trim(),
      bankId,
      bankAccount: bankAccount.trim(),
      accountName: accountName.trim(),
      defaultVatRate: Number.isFinite(vatNum) ? vatNum : 0,
      allowStackPromotions: allowStack,
      allowStaffViewShiftDifference: allowViewDiff,
      businessDayStartMinute: startMin,
    });
    setSaving(false);
    if (res.success) {
      const changedDay = startMin !== normalizeBusinessDayStart(store.businessDayStartMinute);
      setMsg({ ok: true, text: changedDay ? "Đã lưu. Tải lại các trang báo cáo đang mở để áp dụng giờ chia ngày mới." : "Đã lưu cài đặt cửa hàng." });
    } else {
      setMsg({ ok: false, text: res.error || "Không lưu được cài đặt." });
    }
  };

  const section = (title: string, icon: React.ReactNode, children: React.ReactNode) => (
    <div className="card" style={{ padding: "18px 20px", display: "flex", flexDirection: "column", gap: 14 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 8, fontWeight: 800, fontSize: 15 }}>{icon}{title}</div>
      {children}
    </div>
  );

  return (
    <form onSubmit={save} style={{ display: "flex", flexDirection: "column", gap: 18, maxWidth: 760 }}>
      <div>
        <h1 className="section-title" style={{ display: "flex", alignItems: "center", gap: 10 }}>
          <Settings size={22} /> Cài đặt cửa hàng
        </h1>
        <p className="section-subtitle">{store.storeCode} — chỉnh thông tin, thanh toán QR, tùy chọn bán hàng và ngày kinh doanh của cửa hàng đang chọn.</p>
      </div>

      {msg && (
        <div style={{ background: msg.ok ? "var(--success-bg)" : "var(--danger-bg, #fee2e2)", color: msg.ok ? "var(--success)" : "var(--danger)", borderRadius: 10, padding: "12px 16px", fontWeight: 600, fontSize: 14, display: "flex", gap: 8, alignItems: "center" }}>
          {msg.ok && <CheckCircle2 size={18} />}{msg.text}
        </div>
      )}

      {section("Ngày kinh doanh & chia doanh thu", <Clock size={18} />, (
        <>
          <div>
            <label style={label}>Giờ bắt đầu ngày kinh doanh</label>
            <input className="input-field" type="time" value={dayStart} onChange={(e) => setDayStart(e.target.value)} style={{ maxWidth: 160 }} />
            <p style={{ fontSize: 12, color: "var(--subtext)", margin: "6px 0 0", lineHeight: 1.5 }}>
              Cửa hàng hoạt động qua 0h: hóa đơn trước giờ này được tính vào doanh thu của ngày hôm trước. Để 00:00 nếu chốt doanh thu đúng nửa đêm (mặc định).
              Áp dụng cho báo cáo doanh thu, cuối ngày, hàng hóa, khuyến mãi, phân tích và danh sách đơn theo ngày. Biểu đồ theo khung giờ vẫn dùng giờ thực.
            </p>
            {example && <p style={{ fontSize: 13, fontWeight: 700, color: "var(--primary)", margin: "6px 0 0" }}>{example}</p>}
          </div>
        </>
      ))}

      {section("Thông tin cửa hàng", <Store size={18} />, (
        <>
          <div><label style={label}>Tên cửa hàng *</label><input className="input-field" value={storeName} onChange={(e) => setStoreName(e.target.value)} required /></div>
          <div><label style={label}>Địa chỉ</label><input className="input-field" value={address} onChange={(e) => setAddress(e.target.value)} /></div>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(200px, 1fr))", gap: 12 }}>
            <div><label style={label}>Số điện thoại</label><input className="input-field" value={phone} onChange={(e) => setPhone(e.target.value)} /></div>
            <div><label style={label}>Tên WiFi (in trên hóa đơn)</label><input className="input-field" value={wifiName} onChange={(e) => setWifiName(e.target.value)} /></div>
          </div>
        </>
      ))}

      {section("Thanh toán chuyển khoản (VietQR)", <span>💳</span>, (
        <>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(200px, 1fr))", gap: 12 }}>
            <div>
              <label style={label}>Ngân hàng</label>
              <select className="input-field" value={bankId} onChange={(e) => setBankId(e.target.value)}>
                {BANK_OPTIONS.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
              </select>
            </div>
            <div><label style={label}>Số tài khoản</label><input className="input-field" value={bankAccount} onChange={(e) => setBankAccount(e.target.value)} /></div>
          </div>
          <div><label style={label}>Tên chủ tài khoản</label><input className="input-field" value={accountName} onChange={(e) => setAccountName(e.target.value.toUpperCase())} /></div>
        </>
      ))}

      {section("Tùy chọn bán hàng", <span>🧾</span>, (
        <>
          <div style={{ maxWidth: 200 }}>
            <label style={label}>VAT mặc định (%)</label>
            <input className="input-field" type="number" min={0} max={100} step="0.5" value={vat} onChange={(e) => setVat(e.target.value)} />
          </div>
          <label style={{ display: "flex", gap: 10, alignItems: "flex-start", cursor: "pointer" }}>
            <input type="checkbox" checked={allowStack} onChange={(e) => setAllowStack(e.target.checked)} style={{ marginTop: 3, width: 16, height: 16 }} />
            <span><b>Cho phép cộng dồn khuyến mãi</b><br /><span style={{ fontSize: 12, color: "var(--subtext)" }}>Một đơn dùng được nhiều chương trình cùng lúc.</span></span>
          </label>
          <label style={{ display: "flex", gap: 10, alignItems: "flex-start", cursor: "pointer" }}>
            <input type="checkbox" checked={allowViewDiff} onChange={(e) => setAllowViewDiff(e.target.checked)} style={{ marginTop: 3, width: 16, height: 16 }} />
            <span><b>Cho nhân viên xem chênh lệch két khi kết ca</b></span>
          </label>
        </>
      ))}

      <div>
        <button className="btn-primary" type="submit" disabled={saving}>{saving ? "Đang lưu..." : "Lưu cài đặt"}</button>
      </div>
    </form>
  );
}
