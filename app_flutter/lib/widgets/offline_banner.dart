// lib/widgets/offline_banner.dart
//
// Thanh báo MẤT MẠNG dùng chung cho toàn app (gắn trong MaterialApp.builder).
// Khi mất kết nối, đơn vẫn lưu trên máy và tự đồng bộ khi có mạng lại, nhưng KHÔNG gộp được thay đổi của
// máy khác → 2 máy cùng sửa một bàn lúc này có thể mất món. Thanh đỏ nhắc nhân viên điều đó.
//  - Chỉ hiện khi mất mạng quá [offlineDelay] (tránh nháy lúc mở app / chập chờn ngắn).
//  - Có mạng lại: báo xanh "Đã kết nối lại" trong [reconnectedFor] rồi ẩn.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../data/services/firebase_service.dart';

class OfflineBanner extends StatefulWidget {
  final Widget child;

  /// Nguồn trạng thái kết nối (test truyền vào); mặc định theo dõi Firebase
  final Stream<bool>? connection;
  final Duration offlineDelay;
  final Duration reconnectedFor;

  const OfflineBanner({
    super.key,
    required this.child,
    this.connection,
    this.offlineDelay = const Duration(seconds: 3),
    this.reconnectedFor = const Duration(seconds: 3),
  });

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

enum _BannerState { hidden, offline, reconnected }

class _OfflineBannerState extends State<OfflineBanner> {
  StreamSubscription<bool>? _sub;
  Timer? _timer;
  _BannerState _state = _BannerState.hidden;
  bool _connected = true;

  @override
  void initState() {
    super.initState();
    final stream = widget.connection ?? FirebaseService().connectionStream();
    _sub = stream.listen(_onConnection, onError: (_) {});
  }

  void _onConnection(bool connected) {
    if (connected == _connected) return;
    _connected = connected;
    _timer?.cancel();
    _timer = null;
    if (!connected) {
      // Chờ một chút: lúc mở app / mạng chập chờn Firebase báo mất kết nối rất ngắn
      _timer = Timer(widget.offlineDelay, () {
        _timer = null;
        if (mounted && !_connected) setState(() => _state = _BannerState.offline);
      });
    } else if (_state == _BannerState.offline) {
      setState(() => _state = _BannerState.reconnected);
      _timer = Timer(widget.reconnectedFor, () {
        _timer = null;
        if (mounted && _connected) setState(() => _state = _BannerState.hidden);
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final show = _state != _BannerState.hidden;
    final offline = _state == _BannerState.offline;
    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: !show
              ? const SizedBox(width: double.infinity)
              : Material(
                  color: offline ? const Color(0xFFB3261E) : const Color(0xFF1E8E3E),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Row(
                        children: [
                          Icon(offline ? LucideIcons.wifiOff : LucideIcons.wifi, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              offline
                                  ? 'Mất kết nối mạng — món vẫn lưu trên máy và tự đồng bộ khi có mạng. '
                                      'Không để 2 máy cùng sửa một bàn lúc này.'
                                  : 'Đã kết nối lại — dữ liệu đang được đồng bộ.',
                              style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
        Expanded(
          // Thanh đã chiếm phần tai thỏ / thanh trạng thái → màn bên dưới không cần chừa lại
          child: MediaQuery.removePadding(context: context, removeTop: show, child: widget.child),
        ),
      ],
    );
  }
}
