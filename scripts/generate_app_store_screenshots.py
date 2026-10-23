#!/usr/bin/env python3
"""
TRAM ECOSYSTEM - APP STORE SCREENSHOT GENERATOR
Tạo bộ ảnh giới thiệu chuẩn kích thước App Store Connect cho iPhone:
- 6.7" Display: 1290 x 2796 px (iPhone 16 Plus / 15 Pro Max / 14 Pro Max)
- 6.5" Display: 1242 x 2688 px (iPhone 11 Pro Max / XS Max)
- 5.5" Display: 1242 x 2208 px (iPhone 8 Plus / 7 Plus / 6s Plus)

Bao gồm:
1. Showcase Dark Burgundy (Thương hiệu Trạm đỏ mận sang trọng)
2. Showcase Light Cream (Kem ấm tối giản thanh lịch)
3. Direct Fullscreen (Ảnh giao diện trực tiếp không mockup, chuẩn 9:41)
"""

import os
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
RAW_DIR = os.path.join(PROJECT_ROOT, "app_store_screenshots", "raw_source")
OUT_BASE = os.path.join(PROJECT_ROOT, "app_store_screenshots")
FONTS_DIR = os.path.join(SCRIPT_DIR, "assets", "fonts")

FONT_BOLD = os.path.join(FONTS_DIR, "BeVietnamPro-Bold.ttf")
FONT_SEMIBOLD = os.path.join(FONTS_DIR, "BeVietnamPro-SemiBold.ttf")
FONT_MEDIUM = os.path.join(FONTS_DIR, "BeVietnamPro-Medium.ttf")
FONT_REGULAR = os.path.join(FONTS_DIR, "BeVietnamPro-Regular.ttf")

SCREENS = [
    {
        "id": "01_so_do_ban",
        "file": "01_so_do_ban.png",
        "tag": "QUẢN LÝ PHÒNG BÀN",
        "title": "Sơ Đồ Bàn Trực Quan",
        "subtitle": "Theo dõi bàn trống & có khách theo khu vực thời gian thực",
        "status_fg": (255, 255, 255, 255),
    },
    {
        "id": "02_goi_mon",
        "file": "02_goi_mon.png",
        "tag": "ORDER & THANH TOÁN",
        "title": "Gọi Món & Bán Hàng Tức Thì",
        "subtitle": "Thao tác mượt mà, gửi bếp trực tiếp & tích điểm thành viên",
        "status_fg": (255, 255, 255, 255),
    },
    {
        "id": "03_lich_su_hoa_don",
        "file": "03_lich_su_hoa_don.png",
        "tag": "LỊCH SỬ & DOANH THU",
        "title": "Tra Cứu Hóa Đơn Minh Bạch",
        "subtitle": "Thống kê doanh số, theo dõi trạng thái đơn bán & hủy",
        "status_fg": (255, 255, 255, 255),
    },
    {
        "id": "04_quan_ly_ca_bep",
        "file": "04_quan_ly_ca_bep.png",
        "tag": "VẬN HÀNH TOÀN DIỆN",
        "title": "Quản Lý Ca & Màn Hình Bếp",
        "subtitle": "Màn hình Bếp KDS, bàn giao két tiền & kết nối máy in",
        "status_fg": (255, 255, 255, 255),
    },
    {
        "id": "05_dang_nhap_he_thong",
        "file": "05_dang_nhap_he_thong.png",
        "tag": "HỆ SINH THÁI TRẠM",
        "title": "Hệ Thống Bán Hàng POS Trạm",
        "subtitle": "Đăng nhập nhanh theo chi nhánh, bảo mật & đồng bộ đám mây",
        "status_fg": (35, 25, 26, 255),
    },
]

def make_background(w, h, theme="burgundy"):
    y_vals = np.linspace(0, 1, h)
    x_vals = np.linspace(0, 1, w)
    xx, yy = np.meshgrid(x_vals, y_vals)

    dist = np.sqrt((xx - 0.5)**2 + (yy - 0.22)**2)

    if theme == "burgundy":
        glow = np.clip(1.0 - dist * 1.45, 0, 1)
        top = np.array([130, 42, 50])       # Brand wine red
        bot = np.array([32, 9, 13])         # Deep night burgundy
        glow_col = np.array([182, 52, 63])  # Warm crimson highlight
        grad = top * (1 - yy[:, :, None]) + bot * yy[:, :, None]
        final = grad * (1 - glow[:, :, None] * 0.32) + glow_col * (glow[:, :, None] * 0.32)
        ring_color = (255, 220, 200, 14)
    else:  # cream
        glow = np.clip(1.0 - dist * 1.4, 0, 1)
        top = np.array([250, 246, 240])     # Warm cream
        bot = np.array([234, 224, 212])     # Soft ivory
        glow_col = np.array([255, 255, 255])
        grad = top * (1 - yy[:, :, None]) + bot * yy[:, :, None]
        final = grad * (1 - glow[:, :, None] * 0.4) + glow_col * (glow[:, :, None] * 0.4)
        ring_color = (126, 41, 48, 12)

    final = np.clip(final, 0, 255).astype(np.uint8)
    bg_img = Image.fromarray(final).convert("RGBA")

    # Concentric rings
    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    ring_center = (w // 2, 480)
    for r in [450, 700, 950]:
        d.ellipse(
            [ring_center[0] - r, ring_center[1] - r, ring_center[0] + r, ring_center[1] + r],
            outline=ring_color,
            width=2,
        )

    bg_img.alpha_composite(overlay)
    return bg_img

def clean_raw_screenshot(raw_im):
    """
    Seamlessly cleans personal status bar artifacts (heart emojis, 57% battery)
    by cloning adjacent gradient slices, preserving 100% of underlying UI shapes.
    """
    im = raw_im.copy()
    w, h = im.size

    # Left slice: clone column from x=150, y=0..60 across x=15..135
    left_slice = im.crop((150, 0, 151, 60))
    for x in range(15, 138):
        im.paste(left_slice, (x, 0))

    # Right slice: clone column from x=465, y=0..60 across x=330..465
    right_slice = im.crop((465, 0, 466, 60))
    for x in range(330, 465):
        im.paste(right_slice, (x, 0))

    return im

def draw_apple_status_bar(img, fg_color, w, h=130):
    """Draws Apple's signature 9:41 AM status bar + cellular, wifi, and battery icons."""
    d = ImageDraw.Draw(img)
    font_time = ImageFont.truetype(FONT_BOLD, 38)

    # 9:41 on left
    d.text((58, 44), "9:41", fill=fg_color, font=font_time)

    # Cell signal (4 vertical bars)
    cx = w - 215
    cy = 50
    bar_w = 6
    bar_gap = 4
    heights = [10, 16, 22, 28]
    for i, bh in enumerate(heights):
        bx = cx + i * (bar_w + bar_gap)
        by = cy + (28 - bh)
        d.rounded_rectangle([bx, by, bx + bar_w, cy + 28], radius=2, fill=fg_color)

    # Wi-Fi arcs
    wx = w - 160
    wy = cy + 2
    d.ellipse([wx + 13, wy + 21, wx + 19, wy + 27], fill=fg_color)
    d.arc([wx + 7, wy + 13, wx + 25, wy + 31], start=210, end=330, fill=fg_color, width=3)
    d.arc([wx, wy + 4, wx + 32, wy + 36], start=210, end=330, fill=fg_color, width=3)

    # Battery icon (100%)
    bx = w - 105
    by = cy + 4
    bw = 50
    bh = 24
    d.rounded_rectangle([bx, by, bx + bw, by + bh], radius=7, outline=fg_color, width=3)
    d.rounded_rectangle([bx + 4, by + 4, bx + bw - 4, by + bh - 4], radius=4, fill=fg_color)
    d.rounded_rectangle([bx + bw + 2, by + 7, bx + bw + 5, by + bh - 7], radius=2, fill=fg_color)

def build_showcase_screenshot(config, theme="burgundy", W=1290, H=2796):
    canvas = make_background(W, H, theme=theme)
    draw = ImageDraw.Draw(canvas)

    font_title = ImageFont.truetype(FONT_BOLD, 78)
    font_subtitle = ImageFont.truetype(FONT_MEDIUM, 38)
    font_tag = ImageFont.truetype(FONT_SEMIBOLD, 28)

    # 1. TAG PILL
    tag_text = config["tag"]
    t_box = draw.textbbox((0, 0), tag_text, font=font_tag)
    tw = t_box[2] - t_box[0]
    th = t_box[3] - t_box[1]
    pw = tw + 52
    ph = th + 26
    px = (W - pw) // 2
    py = 145

    pill_img = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
    pill_draw = ImageDraw.Draw(pill_img)

    if theme == "burgundy":
        pill_draw.rounded_rectangle(
            [0, 0, pw - 1, ph - 1],
            radius=ph // 2,
            fill=(255, 255, 255, 24),
            outline=(255, 230, 180, 130),
            width=2,
        )
        pill_text_color = (255, 236, 205, 255)
        title_color = (255, 255, 255, 255)
        sub_color = (245, 220, 215, 235)
    else:  # cream
        pill_draw.rounded_rectangle(
            [0, 0, pw - 1, ph - 1],
            radius=ph // 2,
            fill=(126, 41, 48, 18),
            outline=(126, 41, 48, 70),
            width=2,
        )
        pill_text_color = (126, 41, 48, 255)
        title_color = (70, 20, 25, 255)
        sub_color = (100, 75, 75, 230)

    canvas.alpha_composite(pill_img, (px, py))
    draw.text((px + 26, py + 12), tag_text, font=font_tag, fill=pill_text_color)

    # 2. MAIN TITLE
    title_text = config["title"]
    title_box = draw.textbbox((0, 0), title_text, font=font_title)
    title_w = title_box[2] - title_box[0]
    title_y = py + ph + 34
    draw.text(((W - title_w) // 2, title_y), title_text, font=font_title, fill=title_color)

    # 3. SUBTITLE
    sub_text = config["subtitle"]
    sub_box = draw.textbbox((0, 0), sub_text, font=font_subtitle)
    sub_w = sub_box[2] - sub_box[0]
    sub_y = title_y + 105
    draw.text(((W - sub_w) // 2, sub_y), sub_text, font=font_subtitle, fill=sub_color)

    # 4. PHONE MOCKUP
    phone_w = 1044
    phone_h = 2260
    phone_x = (W - phone_w) // 2
    phone_y = 530
    corner_r = 92
    bezel = 18

    # Soft drop shadow
    shadow_img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(shadow_img)
    shadow_opacity = 180 if theme == "burgundy" else 120
    s_draw.rounded_rectangle(
        [phone_x - 10, phone_y + 25, phone_x + phone_w + 10, phone_y + phone_h + 35],
        radius=corner_r + 6,
        fill=(0, 0, 0, shadow_opacity),
    )
    shadow_blurred = shadow_img.filter(ImageFilter.GaussianBlur(45))
    canvas.alpha_composite(shadow_blurred)

    # Phone chassis
    phone_img = Image.new("RGBA", (phone_w, phone_h), (0, 0, 0, 0))
    p_draw = ImageDraw.Draw(phone_img)

    # Outer metallic titanium body
    p_draw.rounded_rectangle(
        [0, 0, phone_w - 1, phone_h - 1],
        radius=corner_r,
        fill=(24, 24, 27, 255),
        outline=(78, 78, 84, 255),
        width=3,
    )
    p_draw.rounded_rectangle(
        [bezel, bezel, phone_w - bezel - 1, phone_h - bezel - 1],
        radius=corner_r - bezel,
        fill=(0, 0, 0, 255),
    )

    # Screen dimensions
    screen_w = phone_w - bezel * 2
    screen_h = phone_h - bezel * 2
    screen_r = corner_r - bezel

    # Load & clean screenshot
    raw_path = os.path.join(RAW_DIR, config["file"])
    raw_screen = Image.open(raw_path).convert("RGBA")
    cleaned_screen = clean_raw_screenshot(raw_screen)

    # Scale to screen size
    scaled_screen = cleaned_screen.resize((screen_w, screen_h), Image.Resampling.LANCZOS)

    # Draw Apple status bar
    draw_apple_status_bar(scaled_screen, config["status_fg"], screen_w, h=128)

    # Rounded screen mask
    mask = Image.new("L", (screen_w, screen_h), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle([0, 0, screen_w, screen_h], radius=screen_r, fill=255)

    phone_img.paste(scaled_screen, (bezel, bezel), mask)

    # Dynamic Island
    di_w = 286
    di_h = 76
    di_x = (phone_w - di_w) // 2
    di_y = bezel + 22
    p_draw.rounded_rectangle(
        [di_x, di_y, di_x + di_w, di_y + di_h],
        radius=di_h // 2,
        fill=(0, 0, 0, 255),
        outline=(28, 28, 28, 255),
        width=1,
    )
    # Camera lens reflection inside Dynamic Island
    p_draw.ellipse(
        [di_x + di_w - 46, di_y + (di_h - 24) // 2, di_x + di_w - 22, di_y + (di_h + 24) // 2],
        fill=(15, 20, 35, 255),
    )

    # Screen inner border accent
    p_draw.rounded_rectangle(
        [bezel, bezel, phone_w - bezel - 1, phone_h - bezel - 1],
        radius=screen_r,
        outline=(255, 255, 255, 20),
        width=1,
    )

    # Composite phone onto canvas
    canvas.alpha_composite(phone_img, (phone_x, phone_y))

    # Return pure 24-bit RGB (App Store standard: no alpha channel)
    return canvas.convert("RGB")

def build_direct_screenshot(config, W=1290, H=2796):
    raw_path = os.path.join(RAW_DIR, config["file"])
    raw_screen = Image.open(raw_path).convert("RGBA")
    cleaned_screen = clean_raw_screenshot(raw_screen)
    scaled = cleaned_screen.resize((W, H), Image.Resampling.LANCZOS)
    draw_apple_status_bar(scaled, config["status_fg"], W, h=155)
    return scaled.convert("RGB")

def main():
    dirs = {
        "6.7_burgundy": os.path.join(OUT_BASE, "iphone_6_7_showcase"),
        "6.7_light": os.path.join(OUT_BASE, "iphone_6_7_showcase_light"),
        "6.5_showcase": os.path.join(OUT_BASE, "iphone_6_5_showcase"),
        "5.5_showcase": os.path.join(OUT_BASE, "iphone_5_5_showcase"),
        "6.7_direct": os.path.join(OUT_BASE, "iphone_6_7_direct"),
    }

    for path in dirs.values():
        os.makedirs(path, exist_ok=True)

    print("🚀 Đang khởi tạo bộ ảnh App Store tiêu chuẩn...")

    for idx, screen in enumerate(SCREENS):
        sid = screen["id"]
        print(f"[{idx+1}/{len(SCREENS)}] Tạo ảnh cho {sid}: {screen['title']}...")

        # 1. 6.7" Showcase Burgundy (1290 x 2796)
        img_burgundy_67 = build_showcase_screenshot(screen, theme="burgundy", W=1290, H=2796)
        img_burgundy_67.save(os.path.join(dirs["6.7_burgundy"], f"{sid}.png"), quality=98)

        # 2. 6.7" Showcase Light (1290 x 2796)
        img_light_67 = build_showcase_screenshot(screen, theme="cream", W=1290, H=2796)
        img_light_67.save(os.path.join(dirs["6.7_light"], f"{sid}.png"), quality=98)

        # 3. 6.5" Showcase (1242 x 2688)
        img_65 = img_burgundy_67.resize((1242, 2688), Image.Resampling.LANCZOS)
        img_65.save(os.path.join(dirs["6.5_showcase"], f"{sid}.png"), quality=98)

        # 4. 5.5" Showcase (1242 x 2208)
        img_55 = img_burgundy_67.resize((1242, 2208), Image.Resampling.LANCZOS)
        img_55.save(os.path.join(dirs["5.5_showcase"], f"{sid}.png"), quality=98)

        # 5. 6.7" Direct Screen (1290 x 2796)
        img_direct = build_direct_screenshot(screen, W=1290, H=2796)
        img_direct.save(os.path.join(dirs["6.7_direct"], f"{sid}.png"), quality=98)

    print("\n✅ Hoàn tất toàn bộ bộ ảnh giới thiệu App Store!")
    print(f"- iPhone 6.7\" Showcase (Đỏ mận):  {dirs['6.7_burgundy']}")
    print(f"- iPhone 6.7\" Showcase (Kem sáng): {dirs['6.7_light']}")
    print(f"- iPhone 6.5\" Showcase (1242x2688): {dirs['6.5_showcase']}")
    print(f"- iPhone 5.5\" Showcase (1242x2208): {dirs['5.5_showcase']}")
    print(f"- iPhone 6.7\" Direct (Trực tiếp):  {dirs['6.7_direct']}")

if __name__ == "__main__":
    main()
