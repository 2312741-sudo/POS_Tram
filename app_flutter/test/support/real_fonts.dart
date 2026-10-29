import 'dart:io';
import 'package:flutter/services.dart';

/// Nạp font thật (Be Vietnam Pro SemiBold) cho test bố cục.
/// Font mặc định của flutter_test vẽ mỗi ký tự thành ô vuông nên đo chữ rộng hơn thực tế;
/// dùng font thật (đậm vừa, hơi rộng hơn bản Regular) để kiểm tra tràn chữ sát với điện thoại.
Future<void> loadRealFonts() async {
  final bytes = File('test/fonts/BeVietnamPro-SemiBold.ttf').readAsBytesSync();
  final data = ByteData.view(bytes.buffer);
  final families = <String>[
    'Roboto', 'BeVietnamPro', 'Be Vietnam Pro', 'Merriweather',
    for (final w in ['regular', '100', '200', '300', '500', '600', '700', '800', '900']) ...[
      'BeVietnamPro_$w', 'Merriweather_$w',
    ],
  ];
  for (final f in families) {
    final loader = FontLoader(f)..addFont(Future.value(data));
    await loader.load();
  }
}
