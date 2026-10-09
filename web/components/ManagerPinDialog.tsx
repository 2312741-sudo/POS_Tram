"use client";
import { useState } from "react";
import { KeyRound, ShieldCheck, X } from "lucide-react";
import { httpsCallable } from "firebase/functions";
import { functions } from "@/lib/firebase";
import {
  APPROVAL_ACTION_LABELS,
  mapApprovalError,
  parseApproval,
  type ApprovalAction,
  type ApproverOption,
  type ManagerApproval,
} from "@/lib/manager-approval";

interface Props {
  storeCode: string;
  action: ApprovalAction;
  /** Mô tả ngắn thao tác (ghi vào audit log phía máy chủ), VD: `Giảm giá "Bạc xỉu" bàn A1` */
  context: string;
  approvers: ApproverOption[];
  onApproved: (approval: ManagerApproval) => void;
  onCancel: () => void;
}

/**
 * Hộp thoại "Quản lý duyệt bằng PIN" (port luồng Flutter _requestManagerDiscountApproval).
 * PIN được xác minh phía máy chủ qua callable verifyManagerPin — client không bao giờ đọc PIN.
 */
export default function ManagerPinDialog({ storeCode, action, context, approvers, onApproved, onCancel }: Props) {
  const [approverUid, setApproverUid] = useState<string>("");
  const [pin, setPin] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  const submit = async () => {
    if (!/^\d{4,8}$/.test(pin)) {
      setError("PIN phải gồm 4–8 chữ số.");
      return;
    }
    setBusy(true);
    setError("");
    try {
      const call = httpsCallable(functions, "verifyManagerPin");
      const res = await call({ storeCode, pin, action, approverUid: approverUid || undefined, context });
      const approval = parseApproval(res.data);
      if (!approval) throw new Error("Phản hồi duyệt không hợp lệ.");
      setPin("");
      onApproved(approval);
    } catch (e) {
      setPin("");
      setError(mapApprovalError(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="modal-overlay" style={{ zIndex: 1200 }} onClick={busy ? undefined : onCancel}>
      <div
        className="modal-content"
        role="dialog"
        aria-modal="true"
        aria-labelledby="manager-pin-title"
        style={{ maxWidth: "380px" }}
        onClick={(e) => e.stopPropagation()}
      >
        <div style={{ padding: "20px 24px 0", display: "flex", alignItems: "center", justifyContent: "space-between", gap: "12px" }}>
          <div>
            <h2 id="manager-pin-title" style={{ fontSize: "17px", fontWeight: 800, color: "var(--text)", display: "flex", alignItems: "center", gap: "8px" }}>
              <ShieldCheck size={18} color="var(--warning)" /> Quản lý duyệt bằng PIN
            </h2>
            <div style={{ fontSize: "12px", color: "var(--subtext)", marginTop: "2px" }}>{APPROVAL_ACTION_LABELS[action]}</div>
          </div>
          <button type="button" aria-label="Đóng" disabled={busy} onClick={onCancel} style={{ background: "none", border: "none", color: "var(--subtext)", cursor: "pointer" }}>
            <X size={20} />
          </button>
        </div>
        <form
          style={{ padding: "16px 24px 24px", display: "flex", flexDirection: "column", gap: "14px" }}
          onSubmit={(e) => {
            e.preventDefault();
            void submit();
          }}
        >
          <p style={{ fontSize: "13px", color: "var(--text)", margin: 0 }}>
            Bạn không có quyền thực hiện thao tác này. Vui lòng nhờ Quản lý nhập mã PIN duyệt.
          </p>
          {context && <div style={{ fontSize: "12px", color: "var(--subtext)" }}>{context}</div>}

          <div>
            <label htmlFor="manager-pin-approver" style={{ display: "block", fontSize: "13px", fontWeight: 700, color: "var(--text)", marginBottom: "6px" }}>
              Người duyệt
            </label>
            <select
              id="manager-pin-approver"
              className="input-field"
              value={approverUid}
              onChange={(e) => setApproverUid(e.target.value)}
              disabled={busy}
            >
              <option value="">Tự nhận diện theo PIN</option>
              {approvers.map((a) => (
                <option key={a.uid} value={a.uid}>
                  {a.name}
                  {a.hasPin ? "" : " (chưa đặt PIN)"}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label htmlFor="manager-pin-input" style={{ display: "block", fontSize: "13px", fontWeight: 700, color: "var(--text)", marginBottom: "6px" }}>
              Mã PIN Quản lý
            </label>
            <input
              id="manager-pin-input"
              className="input-field"
              type="password"
              inputMode="numeric"
              autoComplete="off"
              autoFocus
              maxLength={8}
              placeholder="••••"
              value={pin}
              disabled={busy}
              onChange={(e) => setPin(e.target.value.replace(/\D/g, ""))}
              style={{ letterSpacing: "6px", fontSize: "18px", textAlign: "center" }}
            />
          </div>

          {error && (
            <div role="alert" style={{ background: "var(--danger-bg)", color: "var(--danger)", borderRadius: "8px", padding: "10px 12px", fontSize: "13px" }}>
              {error}
            </div>
          )}

          <div style={{ display: "flex", gap: "10px" }}>
            <button type="button" className="btn-secondary" disabled={busy} onClick={onCancel} style={{ flex: 1, justifyContent: "center" }}>
              Hủy
            </button>
            <button type="submit" className="btn-primary" disabled={busy || pin.length < 4} style={{ flex: 1.4, justifyContent: "center", opacity: busy ? 0.7 : 1 }}>
              {busy ? "Đang xác minh..." : "Xác nhận duyệt"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

/**
 * Hộp thoại để Quản lý / Chủ quán đặt hoặc đổi PIN duyệt của CHÍNH MÌNH (callable setManagerPin).
 */
export function SetApprovalPinDialog({ storeCode, hasPin, onClose }: { storeCode: string; hasPin: boolean; onClose: (changed: boolean) => void }) {
  const [pin, setPin] = useState("");
  const [confirmPin, setConfirmPin] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [done, setDone] = useState("");

  const call = async (value: string | null) => {
    setBusy(true);
    setError("");
    try {
      await httpsCallable(functions, "setManagerPin")({ storeCode, pin: value });
      setDone(value === null ? "Đã xóa PIN duyệt." : "Đã lưu PIN duyệt.");
      setPin("");
      setConfirmPin("");
    } catch (e) {
      setError(mapApprovalError(e));
    } finally {
      setBusy(false);
    }
  };

  const save = () => {
    if (!/^\d{4,8}$/.test(pin)) return setError("PIN phải gồm 4–8 chữ số.");
    if (pin !== confirmPin) return setError("Hai lần nhập PIN không khớp.");
    void call(pin);
  };

  return (
    <div className="modal-overlay" style={{ zIndex: 1200 }} onClick={busy ? undefined : () => onClose(!!done)}>
      <div
        className="modal-content"
        role="dialog"
        aria-modal="true"
        aria-labelledby="set-pin-title"
        style={{ maxWidth: "380px" }}
        onClick={(e) => e.stopPropagation()}
      >
        <div style={{ padding: "20px 24px 0", display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          <h2 id="set-pin-title" style={{ fontSize: "17px", fontWeight: 800, color: "var(--text)", display: "flex", alignItems: "center", gap: "8px" }}>
            <KeyRound size={18} color="var(--primary)" /> PIN duyệt của tôi
          </h2>
          <button type="button" aria-label="Đóng" disabled={busy} onClick={() => onClose(!!done)} style={{ background: "none", border: "none", color: "var(--subtext)", cursor: "pointer" }}>
            <X size={20} />
          </button>
        </div>
        <form
          style={{ padding: "16px 24px 24px", display: "flex", flexDirection: "column", gap: "12px" }}
          onSubmit={(e) => {
            e.preventDefault();
            save();
          }}
        >
          <p style={{ fontSize: "12px", color: "var(--subtext)", margin: 0 }}>
            Dùng để duyệt giảm giá món / hủy món đã gửi bếp cho nhân viên trên Web. PIN được băm và lưu phía máy chủ,
            không ai đọc được (kể cả Chủ quán). {hasPin ? "Bạn đã có PIN — nhập PIN mới để đổi." : "Bạn chưa đặt PIN."}
          </p>
          <input
            className="input-field"
            type="password"
            inputMode="numeric"
            autoComplete="new-password"
            aria-label="PIN mới"
            placeholder="PIN mới (4–8 số)"
            maxLength={8}
            value={pin}
            disabled={busy}
            onChange={(e) => setPin(e.target.value.replace(/\D/g, ""))}
          />
          <input
            className="input-field"
            type="password"
            inputMode="numeric"
            autoComplete="new-password"
            aria-label="Nhập lại PIN"
            placeholder="Nhập lại PIN"
            maxLength={8}
            value={confirmPin}
            disabled={busy}
            onChange={(e) => setConfirmPin(e.target.value.replace(/\D/g, ""))}
          />
          {error && (
            <div role="alert" style={{ background: "var(--danger-bg)", color: "var(--danger)", borderRadius: "8px", padding: "10px 12px", fontSize: "13px" }}>
              {error}
            </div>
          )}
          {done && (
            <div role="status" style={{ background: "var(--success-bg)", color: "var(--success)", borderRadius: "8px", padding: "10px 12px", fontSize: "13px" }}>
              {done}
            </div>
          )}
          <div style={{ display: "flex", gap: "10px", flexWrap: "wrap" }}>
            {hasPin && (
              <button type="button" className="btn-secondary" disabled={busy} onClick={() => void call(null)} style={{ flex: 1, justifyContent: "center", color: "var(--danger)" }}>
                Xóa PIN
              </button>
            )}
            <button type="submit" className="btn-primary" disabled={busy} style={{ flex: 1.4, justifyContent: "center", opacity: busy ? 0.7 : 1 }}>
              {busy ? "Đang lưu..." : "Lưu PIN"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
