import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

/// Vị trí neo cho hộp thoại chia sẻ. iOS (đặc biệt iPad và bản mới) yêu cầu một hình chữ nhật
/// hợp lệ trong màn hình, nếu thiếu thì share_plus ném lỗi và nút chia sẻ "không phản hồi".
/// Có [context] thì neo vào chính widget đó, không thì neo giữa màn hình.
Rect shareOrigin([BuildContext? context]) {
  try {
    final box = context?.findRenderObject();
    if (box is RenderBox && box.hasSize && box.attached) {
      final r = box.localToGlobal(Offset.zero) & box.size;
      if (r.width > 0 && r.height > 0) return r;
    }
  } catch (_) {}
  final views = ui.PlatformDispatcher.instance.views;
  if (views.isNotEmpty) {
    final v = views.first;
    final size = v.physicalSize / v.devicePixelRatio;
    return Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: 1, height: 1);
  }
  return const Rect.fromLTWH(100, 100, 1, 1);
}

/// Chia sẻ văn bản (luôn kèm vị trí neo hợp lệ). Ném lỗi lên để nơi gọi báo cho người dùng.
Future<void> shareTextSafe(String text, {String? subject, BuildContext? context}) {
  return Share.share(text, subject: subject, sharePositionOrigin: shareOrigin(context));
}

/// Chia sẻ tệp (luôn kèm vị trí neo hợp lệ).
Future<void> shareFilesSafe(List<XFile> files, {String? text, String? subject, BuildContext? context}) {
  return Share.shareXFiles(files, text: text, subject: subject, sharePositionOrigin: shareOrigin(context));
}
