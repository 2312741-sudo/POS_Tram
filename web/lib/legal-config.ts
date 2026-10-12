/**
 * Thông tin dùng chung cho các trang pháp lý công khai (/privacy, /privacy-choices).
 * Email liên hệ đặt qua biến môi trường NEXT_PUBLIC_PRIVACY_EMAIL (Vercel → Environment Variables);
 * để trống thì trang hướng dẫn người dùng liên hệ chủ cửa hàng nơi họ sử dụng dịch vụ.
 */
export const LEGAL = {
  appName: "POS Trạm",
  effectiveDate: "12/10/2026",
  host: "pos-tram.vercel.app",
  hotline: "0865.062.205",
  hotlineTel: "tel:0865062205",
  contactEmail: (process.env.NEXT_PUBLIC_PRIVACY_EMAIL || "").trim(),
} as const;

/** Liên kết mailto có sẵn tiêu đề; chuỗi rỗng khi chưa cấu hình email */
export function privacyMailto(subject: string): string {
  return LEGAL.contactEmail ? `mailto:${LEGAL.contactEmail}?subject=${encodeURIComponent(subject)}` : "";
}
