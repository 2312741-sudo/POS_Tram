"use client";
import { useMemo, useState } from "react";
import { Search, KeyRound, ListChecks, Download } from "lucide-react";
import { ACTION_CATALOG, PERMISSION_CATALOG } from "@/lib/permission-catalog";
import { ROLE_PERMISSIONS, hasPermission, useAuth } from "@/lib/auth";
import { ROLE_COLUMNS, roleGrants, filterActions, filterPermissions, exportActionCodesExcel } from "@/lib/action-codes-export";

const th = { padding: "10px 12px", textAlign: "left", fontSize: "12px", color: "var(--subtext)" } as const;
const td = { padding: "9px 12px", fontSize: "13px", borderTop: "1px solid var(--border)" } as const;

export default function ActionCodesPage() {
  const [tab, setTab] = useState<"PERMISSION" | "ACTION">("PERMISSION");
  const [q, setQ] = useState("");
  const needle = q.trim().toLowerCase();

  const { user, storeCode } = useAuth();
  const canExport = hasPermission(user, "EXPORT_REPORTS");
  const permissions = useMemo(() => filterPermissions(PERMISSION_CATALOG, q), [q]);
  const actions = useMemo(() => filterActions(ACTION_CATALOG, q), [q]);
  const handleExport = () =>
    exportActionCodesExcel({
      actions,
      permissions,
      allPermissions: PERMISSION_CATALOG,
      presets: ROLE_PERMISSIONS,
      filterText: needle,
      storeName: user?.storeName || storeCode,
      userName: user?.fullName || user?.username,
    });

  const tabBtn = (id: "PERMISSION" | "ACTION", label: string, icon: React.ReactNode) => (
    <button
      onClick={() => setTab(id)}
      style={{
        display: "flex", alignItems: "center", gap: 6, padding: "8px 14px", borderRadius: 8, fontSize: 13, fontWeight: 600,
        cursor: "pointer", border: "1px solid var(--border)",
        background: tab === id ? "var(--primary)" : "var(--surface)", color: tab === id ? "#fff" : "var(--text)",
      }}
    >
      {icon} {label}
    </button>
  );

  return (
    <div style={{ padding: "24px 28px", maxWidth: 1280, margin: "0 auto" }}>
      <h1 style={{ fontSize: 22, fontWeight: 800, margin: 0 }}>Bộ mã hành động & quyền</h1>
      <p style={{ fontSize: 13, color: "var(--subtext)", margin: "4px 0 16px" }}>
        Tra cứu mã quyền (gán trong &quot;Nhân viên và phân quyền&quot;) và mã hành động ghi trong Nhật ký kiểm soát.
      </p>

      <div style={{ display: "flex", gap: 10, flexWrap: "wrap", marginBottom: 14, alignItems: "center" }}>
        {tabBtn("PERMISSION", `Mã quyền (${PERMISSION_CATALOG.length})`, <KeyRound size={15} />)}
        {tabBtn("ACTION", `Mã hành động (${ACTION_CATALOG.length})`, <ListChecks size={15} />)}
        <div style={{ display: "flex", alignItems: "center", gap: 8, background: "var(--bg)", padding: "8px 14px", borderRadius: 8, border: "1px solid var(--border)", flex: 1, minWidth: 220, maxWidth: 360 }}>
          <Search size={15} />
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Tìm mã, tên, nhóm..."
            style={{ border: "none", background: "transparent", outline: "none", fontSize: 13, width: "100%" }}
          />
        </div>
        {canExport && (
          <button
            onClick={handleExport}
            style={{ display: "flex", alignItems: "center", gap: 6, padding: "8px 14px", borderRadius: 8, fontSize: 13, fontWeight: 600, cursor: "pointer", border: "1px solid var(--border)", background: "var(--surface)", color: "var(--text)" }}
          >
            <Download size={15} /> Xuất Excel
          </button>
        )}
      </div>

      <div style={{ background: "var(--surface)", border: "1px solid var(--border)", borderRadius: 14, overflowX: "auto" }}>
        {tab === "PERMISSION" ? (
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <thead>
              <tr style={{ background: "var(--bg)" }}>
                <th style={th}>Mã quyền</th>
                <th style={th}>Tên</th>
                <th style={th}>Nhóm</th>
                {ROLE_COLUMNS.map((r) => (
                  <th key={r.label} style={{ ...th, textAlign: "center" }}>{r.label}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {permissions.map((p) => (
                <tr key={p.key}>
                  <td style={{ ...td, fontFamily: "monospace", fontWeight: 700 }}>{p.key}</td>
                  <td style={td}>
                    {p.label}
                    <div style={{ fontSize: 11, color: "var(--subtext)" }}>{p.description}</div>
                  </td>
                  <td style={{ ...td, color: "var(--subtext)" }}>{p.category}</td>
                  {ROLE_COLUMNS.map((r) => (
                    <td key={r.label} style={{ ...td, textAlign: "center" }}>
                      {roleGrants(ROLE_PERMISSIONS, r.ids, p.key) ? "✓" : ""}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        ) : (
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <thead>
              <tr style={{ background: "var(--bg)" }}>
                <th style={th}>Mã hành động</th>
                <th style={th}>Ý nghĩa</th>
                <th style={th}>Nhóm</th>
                <th style={th}>Quyền cần có</th>
                <th style={th}>Nhạy cảm</th>
              </tr>
            </thead>
            <tbody>
              {actions.map((a) => (
                <tr key={a.code}>
                  <td style={{ ...td, fontFamily: "monospace", fontWeight: 700 }}>{a.code}</td>
                  <td style={td}>{a.label}</td>
                  <td style={{ ...td, color: "var(--subtext)" }}>{a.group}</td>
                  <td style={{ ...td, fontFamily: "monospace" }}>{a.permission || "—"}</td>
                  <td style={{ ...td, color: "#B3261E", fontWeight: 700 }}>{a.sensitive ? "Có" : ""}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
