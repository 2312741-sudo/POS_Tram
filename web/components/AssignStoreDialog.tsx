"use client";
import { useState } from "react";
import { Store } from "lucide-react";
import { httpsCallable } from "firebase/functions";
import { functions } from "@/lib/firebase";
import ModalShell, { btnGhost, btnPrimary, errorBox, fieldInput, fieldLabel } from "./ModalShell";

const ROLE_CHOICES = [
  { id: "ROLE_STAFF", label: "Nhân viên (Thu ngân / Phục vụ)" },
  { id: "ROLE_MANAGER", label: "Quản lý" },
  { id: "ROLE_KITCHEN", label: "Bếp / Bar" },
] as const;

interface Props {
  staff: { uid: string; fullName: string; username: string };
  sourceStoreCode: string;
  stores: { storeCode: string; storeName: string }[];
  onClose: () => void;
  onDone: (msg: string) => void;
}

/** Chủ quán / Admin gán nhân viên có sẵn sang cửa hàng khác với vai trò riêng của cửa hàng đó (cùng một tài khoản & mật khẩu) */
export default function AssignStoreDialog({ staff, sourceStoreCode, stores, onClose, onDone }: Props) {
  const targets = stores.filter((s) => s.storeCode !== sourceStoreCode);
  const [target, setTarget] = useState(targets[0]?.storeCode ?? "");
  const [role, setRole] = useState<(typeof ROLE_CHOICES)[number]["id"]>("ROLE_STAFF");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  const submit = async () => {
    if (!target) return setError("Chọn cửa hàng đích");
    setBusy(true);
    setError("");
    try {
      const fn = httpsCallable<{ sourceStoreCode: string; targetStoreCode: string; targetUid: string; roleId: string }, { success: boolean }>(functions, "assignStaffToStore");
      await fn({ sourceStoreCode, targetStoreCode: target, targetUid: staff.uid, roleId: role });
      const roleLabel = ROLE_CHOICES.find((r) => r.id === role)?.label ?? role;
      onDone(`Đã thêm @${staff.username} vào cửa hàng ${target} với vai trò ${roleLabel}. Đăng nhập bằng cùng mật khẩu, chọn mã cửa hàng ${target}.`);
    } catch (e) {
      const m = (e as { message?: string })?.message;
      setError(m && /[^\x00-\x7F]/.test(m) ? m : "Không thêm được nhân viên vào cửa hàng khác. Vui lòng thử lại.");
    } finally {
      setBusy(false);
    }
  };

  return (
    <ModalShell
      title="Thêm vào cửa hàng khác"
      subtitle={`${staff.fullName} (@${staff.username}) • đang ở ${sourceStoreCode}`}
      icon={<Store size={18} color="var(--primary)" />}
      onClose={onClose}
      footer={
        <>
          <button type="button" style={btnGhost} onClick={onClose}>Hủy</button>
          <button type="button" style={{ ...btnPrimary, opacity: busy || !target ? 0.6 : 1 }} disabled={busy || !target} onClick={submit}>
            {busy ? "Đang thêm..." : "Thêm vào cửa hàng"}
          </button>
        </>
      }
    >
      {error && <div style={errorBox}>{error}</div>}
      {targets.length === 0 ? (
        <p style={{ fontSize: 13 }}>Hệ thống chỉ có một cửa hàng.</p>
      ) : (
        <div style={{ display: "grid", gap: 12 }}>
          <div>
            <label style={fieldLabel}>Cửa hàng đích</label>
            <select style={fieldInput} value={target} onChange={(e) => setTarget(e.target.value)}>
              {targets.map((s) => (
                <option key={s.storeCode} value={s.storeCode}>{s.storeCode} — {s.storeName}</option>
              ))}
            </select>
          </div>
          <div>
            <label style={fieldLabel}>Vai trò tại cửa hàng đó</label>
            <select style={fieldInput} value={role} onChange={(e) => setRole(e.target.value as typeof role)}>
              {ROLE_CHOICES.map((r) => (
                <option key={r.id} value={r.id}>{r.label}</option>
              ))}
            </select>
          </div>
          <p style={{ fontSize: 12, color: "var(--subtext)", margin: 0 }}>
            Cùng một tài khoản và mật khẩu; mỗi cửa hàng có vai trò, ca/két và nhật ký riêng. Quyền riêng không sao chép sang cửa hàng mới.
            Một người không mở được ca ở hai cửa hàng cùng lúc — phải chốt ca trước.
          </p>
        </div>
      )}
    </ModalShell>
  );
}
