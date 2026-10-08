// lib/widgets/keyboard_dismiss_wrapper.dart
import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// Wrapper toàn cục tự động ẩn bàn phím khi:
/// 1. Chạm vào bất kỳ vùng trống nào trên màn hình (tap outside)
/// 2. Cuộn/kéo bất kỳ danh sách hoặc màn hình nào (drag to dismiss)
/// 3. Bấm vào nút nổi "Ẩn bàn phím" xuất hiện ngay phía trên bàn phím ảo
class KeyboardDismissWrapper extends StatelessWidget {
  final Widget child;

  const KeyboardDismissWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardOpen = bottomInset > 80;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification && notification.dragDetails != null) {
          FocusManager.instance.primaryFocus?.unfocus();
        }
        return false;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          FocusManager.instance.primaryFocus?.unfocus();
        },
        child: Stack(
          children: [
            child,
            if (isKeyboardOpen)
              Positioned(
                right: 16,
                bottom: bottomInset + 8,
                child: SafeArea(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primaryDark.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.keyboard_hide_rounded, color: Colors.white, size: 16),
                            SizedBox(width: 5),
                            Text(
                              'Ẩn bàn phím',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
