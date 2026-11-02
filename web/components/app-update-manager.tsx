"use client";
import { useEffect, useState } from "react";
import { get, ref, update } from "firebase/database";
import { db } from "@/lib/firebase";
import { Download, ExternalLink, RefreshCw, Smartphone } from "lucide-react";
import { errorMessage } from "@/lib/errors";

interface AppUpdateConfig {
  versionCode: number;
  versionName: string;
  minVersionCode: number;
  apkUrl: string;
  releaseNotes: string;
  apkSize?: string;
  isForce?: boolean;
  publishedAt?: number;
}

export function AppUpdateManager({ isOwner }: { isOwner: boolean }) {
  const [config, setConfig] = useState<AppUpdateConfig>({
    versionCode: 8,
    versionName: "1.0.7",
    minVersionCode: 7,
    apkUrl: "",
    releaseNotes: "- Cập nhật tính năng mới\n- Sửa lỗi và cải thiện hiệu năng",
    apkSize: "45 MB",
    isForce: false,
  });
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);

  useEffect(() => {
    const loadConfig = async () => {
      try {
        const snap = await get(ref(db, "system_config/app_update/android"));
        if (snap.exists() && snap.val()) {
          const val = snap.val();
          setConfig({
            versionCode: Number(val.versionCode) || 1,
            versionName: String(val.versionName || "1.0.0"),
            minVersionCode: Number(val.minVersionCode) || 0,
            apkUrl: String(val.apkUrl || ""),
            releaseNotes: String(val.releaseNotes || ""),
            apkSize: val.apkSize ? String(val.apkSize) : "45 MB",
            isForce: val.isForce === true,
            publishedAt: val.publishedAt ? Number(val.publishedAt) : undefined,
          });
        }
      } catch (err) {
        console.error("Lỗi đọc cấu hình cập nhật APK:", err);
      } finally {
        setLoading(false);
      }
    };
    loadConfig();
  }, []);

  const handlePublish = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!isOwner) {
      setMsg({ ok: false, text: "Chỉ Chủ quán mới có quyền phát hành bản cập nhật APK." });
      return;
    }
    if (!config.apkUrl.trim()) {
      setMsg({ ok: false, text: "Vui lòng nhập đường link tải file APK." });
      return;
    }
    if (!config.versionName.trim() || config.versionCode <= 0) {
      setMsg({ ok: false, text: "Vui lòng nhập phiên bản và mã build hợp lệ." });
      return;
    }

    setSaving(true);
    setMsg(null);
    try {
      const now = Date.now();
      const payload = {
        versionCode: Number(config.versionCode),
        versionName: config.versionName.trim(),
        minVersionCode: Number(config.minVersionCode) || 0,
        apkUrl: config.apkUrl.trim(),
        releaseNotes: config.releaseNotes.trim(),
        apkSize: (config.apkSize || "").trim(),
        isForce: config.isForce === true,
        publishedAt: now,
      };

      await update(ref(db, "system_config/app_update/android"), payload);
      setConfig((prev) => ({ ...prev, publishedAt: now }));
      setMsg({
        ok: true,
        text: `Đã phát hành bản cập nhật v${payload.versionName} (Build ${payload.versionCode}) thành công! Tất cả máy POS Android sẽ nhận được thông báo tự động.`,
      });
    } catch (err) {
      setMsg({ ok: false, text: `Lỗi lưu cấu hình: ${errorMessage(err)}` });
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return (
      <div className="card" style={{ padding: 20, textAlign: "center", color: "var(--muted)" }}>
        Đang tải thông tin bản cập nhật APK...
      </div>
    );
  }

  const labelStyle = { display: "block", fontSize: "12px", fontWeight: 700, marginBottom: "4px" } as const;

  return (
    <div className="card" style={{ padding: "18px 20px", display: "flex", flexDirection: "column", gap: 14 }}>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: 8 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8, fontWeight: 800, fontSize: 15 }}>
          <Smartphone size={18} style={{ color: "var(--primary)" }} />
          Tự động cập nhật ứng dụng Android POS (In-App APK Update)
        </div>
        {config.publishedAt && (
          <span style={{ fontSize: "12px", color: "var(--muted)" }}>
            Phát hành lần cuối: {new Date(config.publishedAt).toLocaleString("vi-VN")}
          </span>
        )}
      </div>

      <div style={{ fontSize: "13px", color: "var(--subtext)", lineHeight: 1.5 }}>
        Hệ thống tự động phát hiện phiên bản mới trên máy POS cầm tay / tablet Android. Khi có bản mới, app POS sẽ hiện thông báo, tải file APK theo % tiến trình và kích hoạt cài đặt đè mà không làm mất dữ liệu.
      </div>

      {msg && (
        <div style={{
          padding: "10px 14px",
          borderRadius: 8,
          fontSize: 13,
          fontWeight: 600,
          background: msg.ok ? "var(--success-bg)" : "var(--danger-bg)",
          color: msg.ok ? "#166534" : "var(--danger)",
          border: `1px solid ${msg.ok ? "#bbf7d0" : "#fecaca"}`,
        }}>
          {msg.text}
        </div>
      )}

      <form onSubmit={handlePublish} style={{ display: "flex", flexDirection: "column", gap: 12 }}>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))", gap: 12 }}>
          <div>
            <label style={labelStyle}>Tên phiên bản mới (versionName) *</label>
            <input
              className="input-field"
              value={config.versionName}
              onChange={(e) => setConfig({ ...config, versionName: e.target.value })}
              placeholder="VD: 1.0.7"
              required
              disabled={!isOwner}
            />
          </div>
          <div>
            <label style={labelStyle}>Mã bản dựng (versionCode) *</label>
            <input
              className="input-field"
              type="number"
              min="1"
              value={config.versionCode}
              onChange={(e) => setConfig({ ...config, versionCode: Number(e.target.value) || 0 })}
              placeholder="VD: 8"
              required
              disabled={!isOwner}
            />
          </div>
          <div>
            <label style={labelStyle}>Bản dựng tối thiểu (minVersionCode)</label>
            <input
              className="input-field"
              type="number"
              min="0"
              value={config.minVersionCode}
              onChange={(e) => setConfig({ ...config, minVersionCode: Number(e.target.value) || 0 })}
              placeholder="Dưới số này bắt buộc update"
              disabled={!isOwner}
            />
          </div>
          <div>
            <label style={labelStyle}>Dung lượng hiển thị (apkSize)</label>
            <input
              className="input-field"
              value={config.apkSize || ""}
              onChange={(e) => setConfig({ ...config, apkSize: e.target.value })}
              placeholder="VD: 45 MB"
              disabled={!isOwner}
            />
          </div>
        </div>

        <div>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <label style={labelStyle}>Đường link tải file APK (URL) *</label>
            {config.apkUrl && (
              <a
                href={config.apkUrl}
                target="_blank"
                rel="noreferrer"
                style={{ fontSize: "11px", color: "var(--primary)", display: "inline-flex", alignItems: "center", gap: 4, textDecoration: "none" }}
              >
                <ExternalLink size={12} /> Kiểm tra link tải
              </a>
            )}
          </div>
          <input
            className="input-field"
            value={config.apkUrl}
            onChange={(e) => setConfig({ ...config, apkUrl: e.target.value })}
            placeholder="https://storage.googleapis.com/.../app-release.apk hoặc link trực tiếp"
            required
            disabled={!isOwner}
          />
        </div>

        <div>
          <label style={labelStyle}>Nội dung cập nhật (Release Notes / Changelog)</label>
          <textarea
            className="input-field"
            rows={3}
            value={config.releaseNotes}
            onChange={(e) => setConfig({ ...config, releaseNotes: e.target.value })}
            placeholder="• Tính năng mới 1&#10;• Sửa lỗi 2..."
            disabled={!isOwner}
          />
        </div>

        <label style={{ display: "flex", gap: 10, alignItems: "center", cursor: isOwner ? "pointer" : "default" }}>
          <input
            type="checkbox"
            checked={config.isForce === true}
            onChange={(e) => setConfig({ ...config, isForce: e.target.checked })}
            style={{ width: 16, height: 16 }}
            disabled={!isOwner}
          />
          <span>
            <b>Bắt buộc cập nhật ngay (Force Update)</b>
            <span style={{ fontSize: 12, color: "var(--subtext)", marginLeft: 6 }}>
              (Không cho phép nhân viên bấm &quot;Để sau&quot;, phải cập nhật mới được vào app)
            </span>
          </span>
        </label>

        {isOwner && (
          <div style={{ marginTop: 6 }}>
            <button
              className="btn-primary"
              type="submit"
              disabled={saving}
              style={{ display: "inline-flex", alignItems: "center", gap: 6 }}
            >
              {saving ? <RefreshCw size={15} className="animate-spin" /> : <Download size={15} />}
              {saving ? "Đang phát hành..." : "Phát hành bản cập nhật APK"}
            </button>
          </div>
        )}
      </form>
    </div>
  );
}
