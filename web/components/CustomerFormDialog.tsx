"use client";
import { useState } from "react";
import { UserPlus } from "lucide-react";
import ModalShell, { btnGhost, btnPrimary, errorBox, fieldInput, fieldLabel } from "./ModalShell";
import { validateNewCustomer } from "@/lib/loyalty";
import type { StoreCustomer } from "@/lib/customers";

interface Props {
  storeCode: string;
  existing: StoreCustomer[];
  initial?: StoreCustomer | null;
  saving?: boolean;
  error?: string;
  onCancel: () => void;
  onSave: (v: { name: string; phone: string; gender: string; birthday: string }) => void;
}

/** Tạo hoặc sửa thông tin khách hàng cho một chi nhánh */
export default function CustomerFormDialog({ storeCode, existing, initial, saving, error, onCancel, onSave }: Props) {
  const [name, setName] = useState(initial?.hoTen || "");
  const [phone, setPhone] = useState(initial?.soDienThoai || "");
  const [gender, setGender] = useState(initial?.gioiTinh || "Khác");
  const [birthday, setBirthday] = useState(initial?.ngaySinh || "");
  const [localError, setLocalError] = useState("");

  const isEditing = Boolean(initial);

  const submit = () => {
    const listToCheck = isEditing ? existing.filter((c) => c.id !== initial?.id) : existing;
    const r = validateNewCustomer({ name, phone }, listToCheck);
    if ("error" in r) {
      setLocalError(r.error);
      return;
    }
    setLocalError("");
    onSave({ name: r.name.toUpperCase(), phone: r.phone, gender, birthday });
  };
  const shown = localError || error;

  return (
    <ModalShell
      title={isEditing ? "Chỉnh sửa thông tin khách hàng" : "Thêm khách hàng mới"}
      subtitle={isEditing ? `Mã: ${initial?.maKhachHang || initial?.id} • ${initial?.diemHienTai || 0} điểm` : `Chi nhánh ${storeCode} • điểm khởi tạo 0`}
      icon={<UserPlus size={18} color="var(--primary)" />}
      onClose={onCancel}
      footer={
        <>
          <button type="button" style={btnGhost} onClick={onCancel}>Hủy</button>
          <button type="button" style={{ ...btnPrimary, opacity: saving ? 0.6 : 1 }} disabled={saving} onClick={submit}>
            {saving ? "Đang lưu..." : (isEditing ? "Lưu thay đổi" : "Lưu khách hàng")}
          </button>
        </>
      }
    >
      {shown && <div style={errorBox}>{shown}</div>}
      <div style={{ display: "grid", gap: 12 }}>
        <div>
          <label style={fieldLabel}>Họ và tên *</label>
          <input
            style={{ ...fieldInput, textTransform: "uppercase" }}
            value={name}
            onChange={(e) => setName(e.target.value.toUpperCase())}
            autoFocus
          />
        </div>
        <div>
          <label style={fieldLabel}>Số điện thoại *</label>
          <input style={fieldInput} value={phone} inputMode="tel" onChange={(e) => setPhone(e.target.value)} />
        </div>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
          <div>
            <label style={fieldLabel}>Giới tính</label>
            <select style={fieldInput} value={gender} onChange={(e) => setGender(e.target.value)}>
              <option>Khác</option>
              <option>Nam</option>
              <option>Nữ</option>
            </select>
          </div>
          <div>
            <label style={fieldLabel}>Ngày sinh</label>
            <input style={fieldInput} type="date" value={birthday} onChange={(e) => setBirthday(e.target.value)} />
          </div>
        </div>
      </div>
    </ModalShell>
  );
}
