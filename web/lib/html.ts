/**
 * Escape a value for safe interpolation into HTML text or a quoted attribute.
 * Use for EVERY value interpolated into HTML strings (print windows, document.write, ...),
 * since names/notes come from Firebase and can be written by staff.
 */
export function escapeHtml(value: unknown): string {
  if (value === null || value === undefined) return "";
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}
