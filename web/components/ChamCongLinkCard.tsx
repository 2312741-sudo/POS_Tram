"use client";
import { useCallback, useEffect, useState } from "react";
import { httpsCallable } from "firebase/functions";
import { CheckCircle2, Clock, Link2, Link2Off, RefreshCw, Users } from "lucide-react";
import { functions } from "@/lib/firebase";
import {
  mapChamCongError,
  parseChamCongLinkStatus,
  parseLinkChamCongResponse,
  type ChamCongLinkStatus,
  type ChamCongMethod,
} from "@/lib/chamcong";
import {
  authenticateChamCong,
  getCurrentChamCongIdToken,
  isChamCongConfigured,
  signOutChamCong,
} from "@/lib/chamcong-firebase";
import ChamCongSignInDialog, { type ChamCongStepResult } from "./ChamCongSignInDialog";

interface Props {
  /** Mã chi nhánh POS cụ thể (không phải "ALL"). */
  storeCode: string;
  storeName?: string;
}

const host = () => (typeof window !== "undefined" ? window.location.host : undefined);

/**
 * Thẻ "Liên kết Chấm Công Trạm" (chỉ Chủ quán): xem trạng thái, liên kết / hủy liên kết
 * một cửa hàng bên ứng dụng Chấm Công với chi nhánh POS đang chọn.
 */
export default function ChamCongLinkCard({ storeCode, storeName }: Props) {
  const configured = isChamCongConfigured();
  const [status, setStatus] = useState<ChamCongLinkStatus | null>(null);
  const [loading, setLoading] = useState(configured);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [showLink, setShowLink] = useState(false);
  const [confirmUnlink, setConfirmUnlink] = useState(false);
  const [unlinking, setUnlinking] = useState(false);

  const fetchStatus = useCallback(async (): Promise<{ status: ChamCongLinkStatus | null; error: string }> => {
    try {
      const call = httpsCallable<{ storeCode: string }, unknown>(functions, "getChamCongLinkStatus");
      const res = await call({ storeCode });
      return { status: parseChamCongLinkStatus(res.data), error: "" };
    } catch (e) {
      return { status: null, error: mapChamCongError(e, host()) };
    }
  }, [storeCode]);

  const loadStatus = useCallback(async () => {
    setLoading(true);
    setError("");
    const r = await fetchStatus();
    setStatus(r.status);
    setError(r.error);
    setLoading(false);
  }, [fetchStatus]);

  // Thẻ được gắn key theo storeCode nên đổi chi nhánh sẽ tạo lại state.
  useEffect(() => {
    if (!configured) return;
    let cancelled = false;
    void fetchStatus().then((r) => {
      if (cancelled) return;
      setStatus(r.status);
      setError(r.error);
      setLoading(false);
    });
    return () => {
      cancelled = true;
    };
  }, [configured, fetchStatus]);

  const callLink = async (idToken: string, chamCongStoreId?: string): Promise<ChamCongStepResult> => {
    const call = httpsCallable<{ storeCode: string; idToken: string; chamCongStoreId?: string }, unknown>(
      functions,
      "linkChamCongStore"
    );
    const res = await call(chamCongStoreId ? { storeCode, idToken, chamCongStoreId } : { storeCode, idToken });
    const parsed = parseLinkChamCongResponse(res.data);
    if (!parsed) {
      await signOutChamCong();
      return { error: "Máy chủ trả về phản hồi không hợp lệ. Vui lòng thử lại." };
    }
    if (parsed.status === "CHOOSE_CHAMCONG_STORE") {
      return {
        options: parsed.stores.map((s) => ({
          id: s.chamCongStoreId,
          label: s.name,
          sublabel: s.code ? `Mã cửa hàng: ${s.code}` : undefined,
        })),
      };
    }
    await signOutChamCong();
    setShowLink(false);
    setNotice(`Đã liên kết với cửa hàng chấm công "${parsed.chamCongStoreName}".`);
    void loadStatus();
  };

  const handleMethod = async (method: ChamCongMethod): Promise<ChamCongStepResult> => {
    try {
      const idToken = await authenticateChamCong(method);
      return await callLink(idToken);
    } catch (e) {
      await signOutChamCong();
      return { error: mapChamCongError(e, host()) };
    }
  };

  const handlePick = async (chamCongStoreId: string): Promise<ChamCongStepResult> => {
    try {
      const idToken = await getCurrentChamCongIdToken();
      if (!idToken) return { error: "Phiên Chấm Công đã hết hạn. Vui lòng quay lại và đăng nhập lại." };
      return await callLink(idToken, chamCongStoreId);
    } catch (e) {
      return { error: mapChamCongError(e, host()) };
    }
  };

  const closeLink = () => {
    setShowLink(false);
    void signOutChamCong();
  };

  const handleUnlink = async () => {
    setUnlinking(true);
    setError("");
    try {
      const call = httpsCallable<{ storeCode: string }, unknown>(functions, "unlinkChamCongStore");
      await call({ storeCode });
      setConfirmUnlink(false);
      setNotice("Đã hủy liên kết Chấm Công Trạm.");
      await loadStatus();
    } catch (e) {
      setError(mapChamCongError(e, host()));
      setConfirmUnlink(false);
    } finally {
      setUnlinking(false);
    }
  };

  const linkedAtText =
    status?.linkedAt !== undefined ? new Date(status.linkedAt).toLocaleString("vi-VN") : undefined;

  return (
    <section className="card" aria-labelledby="chamcong-link-title" style={{ padding: "18px 20px" }}>
      <div style={{ display: "flex", alignItems: "flex-start", justifyContent: "space-between", gap: "12px", flexWrap: "wrap" }}>
        <div style={{ minWidth: 0, flex: "1 1 280px" }}>
          <h2 id="chamcong-link-title" style={{ fontSize: "16px", fontWeight: 800, color: "var(--text)", display: "flex", alignItems: "center", gap: "8px" }}>
            <Clock size={18} style={{ color: "var(--primary)" }} aria-hidden="true" />
            Liên kết Chấm Công Trạm
          </h2>
          <p style={{ fontSize: "13px", color: "var(--subtext)", marginTop: "4px", lineHeight: 1.5 }}>
            Cho phép nhân viên của cửa hàng chấm công đăng nhập POS chi nhánh{" "}
            <strong style={{ color: "var(--text)" }}>{storeName || storeCode}</strong> chỉ với một chạm.
          </p>
        </div>

        {configured && !loading && status && (
          <div style={{ display: "flex", gap: "8px", flexWrap: "wrap" }}>
            {status.linked ? (
              <button type="button" className="btn-danger btn-sm" onClick={() => setConfirmUnlink(true)}>
                <Link2Off size={15} aria-hidden="true" /> Hủy liên kết
              </button>
            ) : (
              <button type="button" className="btn-primary btn-sm" onClick={() => { setNotice(""); setShowLink(true); }} aria-haspopup="dialog">
                <Link2 size={15} aria-hidden="true" /> Liên kết ngay
              </button>
            )}
          </div>
        )}
      </div>

      <div style={{ marginTop: "14px", display: "flex", flexDirection: "column", gap: "10px" }} aria-live="polite">
        {!configured ? (
          <div style={{ fontSize: "13px", color: "var(--warning)", background: "var(--warning-bg)", borderRadius: "10px", padding: "10px 12px" }}>
            Web chưa được cấu hình kết nối Chấm Công Trạm. Thêm các biến NEXT_PUBLIC_CHAMCONG_* (xem web/.env.example) rồi build lại.
          </div>
        ) : loading ? (
          <div style={{ display: "flex", alignItems: "center", gap: "8px", fontSize: "13px", color: "var(--subtext)" }}>
            <span className="spinner" aria-hidden="true" style={{ width: "14px", height: "14px", borderWidth: "2px" }} />
            Đang kiểm tra trạng thái liên kết...
          </div>
        ) : status ? (
          status.linked ? (
            <div style={{ display: "flex", flexWrap: "wrap", gap: "8px 18px", fontSize: "13px", color: "var(--text)" }}>
              <span className="badge badge-success" style={{ display: "inline-flex", alignItems: "center", gap: "4px" }}>
                <CheckCircle2 size={13} aria-hidden="true" /> Đã liên kết
              </span>
              <span>
                Cửa hàng chấm công: <strong>{status.chamCongStoreName || status.chamCongStoreId}</strong>
              </span>
              <span style={{ display: "inline-flex", alignItems: "center", gap: "4px" }}>
                <Users size={14} aria-hidden="true" style={{ color: "var(--subtext)" }} />
                {status.provisionedCount} tài khoản đã tạo
              </span>
              {linkedAtText && <span style={{ color: "var(--subtext)" }}>Liên kết lúc {linkedAtText}</span>}
            </div>
          ) : (
            <div style={{ fontSize: "13px", color: "var(--subtext)" }}>
              Chưa liên kết. Bấm &quot;Liên kết ngay&quot; và đăng nhập bằng tài khoản <strong>chủ cửa hàng</strong> trên Chấm Công Trạm.
            </div>
          )
        ) : null}

        {error && (
          <div role="alert" style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: "8px", flexWrap: "wrap", fontSize: "13px", color: "var(--danger)", background: "var(--danger-bg)", borderRadius: "10px", padding: "10px 12px" }}>
            <span>{error}</span>
            <button type="button" className="btn-secondary btn-sm" onClick={() => void loadStatus()}>
              <RefreshCw size={14} aria-hidden="true" /> Thử lại
            </button>
          </div>
        )}
        {notice && !error && (
          <div style={{ fontSize: "13px", color: "var(--success)", background: "var(--success-bg)", borderRadius: "10px", padding: "10px 12px", fontWeight: 600 }}>
            {notice}
          </div>
        )}

        {configured && (
          <p style={{ fontSize: "12px", color: "var(--muted)", lineHeight: 1.5, margin: 0 }}>
            Nhân viên đăng nhập lần đầu sẽ tự xuất hiện với vai trò <strong>Phục vụ</strong>. Bạn có thể nâng quyền
            (Thu ngân, Quản lý...) trong mục <strong>Nhân viên</strong>.
          </p>
        )}
      </div>

      {showLink && (
        <ChamCongSignInDialog
          title="Liên kết Chấm Công Trạm"
          description={`Đăng nhập bằng tài khoản chủ cửa hàng trên Chấm Công Trạm để liên kết với chi nhánh ${storeCode}.`}
          pickTitle="Chọn cửa hàng chấm công cần liên kết"
          onMethod={handleMethod}
          onPick={handlePick}
          onClose={closeLink}
          footer="Phiên Chấm Công chỉ dùng để xác minh quyền chủ cửa hàng và không được lưu lại."
        />
      )}

      {confirmUnlink && (
        <div className="modal-overlay" style={{ zIndex: 1200 }} onClick={unlinking ? undefined : () => setConfirmUnlink(false)}>
          <div
            className="modal-content"
            role="alertdialog"
            aria-modal="true"
            aria-labelledby="chamcong-unlink-title"
            aria-describedby="chamcong-unlink-desc"
            style={{ maxWidth: "400px", padding: "22px 24px" }}
            onClick={(e) => e.stopPropagation()}
          >
            <h2 id="chamcong-unlink-title" style={{ fontSize: "17px", fontWeight: 800, color: "var(--text)" }}>
              Hủy liên kết Chấm Công Trạm?
            </h2>
            <p id="chamcong-unlink-desc" style={{ fontSize: "13px", color: "var(--subtext)", marginTop: "8px", lineHeight: 1.5 }}>
              Nhân viên sẽ không thể đăng nhập chi nhánh {storeCode} bằng Chấm Công Trạm nữa. Các tài khoản POS đã tạo
              vẫn được giữ nguyên.
            </p>
            <div style={{ display: "flex", gap: "10px", marginTop: "18px" }}>
              <button type="button" className="btn-secondary" autoFocus disabled={unlinking} onClick={() => setConfirmUnlink(false)} style={{ flex: 1, justifyContent: "center" }}>
                Giữ liên kết
              </button>
              <button type="button" className="btn-danger" disabled={unlinking} onClick={() => void handleUnlink()} style={{ flex: 1, justifyContent: "center" }}>
                {unlinking ? "Đang hủy..." : "Hủy liên kết"}
              </button>
            </div>
          </div>
        </div>
      )}
    </section>
  );
}
