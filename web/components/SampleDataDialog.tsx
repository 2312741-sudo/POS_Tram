"use client";
import { useState } from "react";
import { FlaskConical } from "lucide-react";
import { get, ref, update } from "firebase/database";
import { db } from "@/lib/firebase";
import ModalShell, { btnGhost, btnPrimary, errorBox } from "./ModalShell";
import { errorMessage } from "@/lib/errors";
import { SAMPLE_BILL_LABELS, buildSampleDataUpdates, buildSampleRemovalUpdates, sampleCampaignForms } from "@/lib/sample-data";

interface Props {
  storeCode: string;
  storeName: string;
  actor: { username: string; fullName?: string };
  onClose: () => void;
}

/** Tạo / xóa bộ đơn mẫu + khuyến mãi mẫu (mỗi loại hình) cho một chi nhánh — Chủ quán / Quản lý */
export default function SampleDataDialog({ storeCode, storeName, actor, onClose }: Props) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [done, setDone] = useState("");

  const create = async () => {
    setBusy(true);
    setError("");
    setDone("");
    try {
      await update(ref(db), buildSampleDataUpdates({ storeCode, storeName, actor, now: Date.now() }));
      setDone(`Đã tạo ${sampleCampaignForms().length} chương trình KM và ${SAMPLE_BILL_LABELS.length} hóa đơn mẫu.`);
    } catch (e) {
      setError(errorMessage(e, "Không tạo được dữ liệu mẫu"));
    } finally {
      setBusy(false);
    }
  };

  const remove = async () => {
    if (!confirm("Xóa toàn bộ hóa đơn và chương trình KM mẫu của chi nhánh này?")) return;
    setBusy(true);
    setError("");
    setDone("");
    try {
      const [bills, history, campaigns] = await Promise.all(
        ["bills", "history", "campaigns"].map((n) => get(ref(db, `stores/${storeCode}/${n}`)).then((s) => s.val()))
      );
      const updates = buildSampleRemovalUpdates(storeCode, { bills, history, campaigns });
      const n = Object.keys(updates).length;
      if (n > 0) await update(ref(db), updates);
      setDone(n > 0 ? `Đã xóa ${n} bản ghi mẫu.` : "Không có dữ liệu mẫu để xóa.");
    } catch (e) {
      setError(errorMessage(e, "Không xóa được dữ liệu mẫu"));
    } finally {
      setBusy(false);
    }
  };

  return (
    <ModalShell
      title="Dữ liệu mẫu"
      subtitle={`Chi nhánh ${storeCode} — dùng để kiểm thử / đào tạo`}
      icon={<FlaskConical size={18} color="var(--primary)" />}
      maxWidth={520}
      onClose={onClose}
      footer={<button type="button" style={btnGhost} onClick={onClose}>Đóng</button>}
    >
      {error && <div style={errorBox}>{error}</div>}
      {done && <div style={{ ...errorBox, background: "var(--success-bg)", color: "#137333" }}>{done}</div>}
      <div style={{ fontSize: 13, color: "var(--text)", marginBottom: 8, fontWeight: 700 }}>Các dạng đơn sẽ được tạo:</div>
      <ul style={{ margin: "0 0 12px", paddingLeft: 18, fontSize: 13, color: "var(--subtext)" }}>
        {SAMPLE_BILL_LABELS.map((b) => (
          <li key={b.key}>{b.label}</li>
        ))}
      </ul>
      <div style={{ fontSize: 13, color: "var(--text)", marginBottom: 6, fontWeight: 700 }}>Chương trình khuyến mãi mẫu:</div>
      <ul style={{ margin: "0 0 12px", paddingLeft: 18, fontSize: 13, color: "var(--subtext)" }}>
        {sampleCampaignForms().map((c) => (
          <li key={c.id}>{c.form.name}</li>
        ))}
      </ul>
      <p style={{ fontSize: 12, color: "#8A5B00", background: "#FEF7E0", borderRadius: 8, padding: "8px 10px" }}>
        Lưu ý: hóa đơn mẫu là hóa đơn đã thanh toán thật (mã MAU-xxxx) nên <strong>có tính vào báo cáo doanh thu</strong> cho tới khi bạn bấm &quot;Xóa dữ liệu mẫu&quot;.
      </p>
      <div style={{ display: "flex", gap: 10, marginTop: 12 }}>
        <button type="button" style={{ ...btnPrimary, opacity: busy ? 0.6 : 1 }} disabled={busy} onClick={create}>
          {busy ? "Đang xử lý..." : "Tạo dữ liệu mẫu"}
        </button>
        <button type="button" style={{ ...btnGhost, color: "var(--danger, #B3261E)" }} disabled={busy} onClick={remove}>
          Xóa dữ liệu mẫu
        </button>
      </div>
    </ModalShell>
  );
}
