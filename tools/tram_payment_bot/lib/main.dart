import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TramPaymentBotApp());
}

class TramPaymentBotApp extends StatelessWidget {
  const TramPaymentBotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trạm Payment Bot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7E2930),
          primary: const Color(0xFF7E2930),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8F4EE),
      ),
      home: const PaymentBotHomeScreen(),
    );
  }
}

class PaymentBotHomeScreen extends StatefulWidget {
  const PaymentBotHomeScreen({super.key});

  @override
  State<PaymentBotHomeScreen> createState() => _PaymentBotHomeScreenState();
}

class _PaymentBotHomeScreenState extends State<PaymentBotHomeScreen> with WidgetsBindingObserver {
  static const _methodChannel = MethodChannel('vn.tram.fnb.tram_payment_bot/methods');
  static const _eventChannel = EventChannel('vn.tram.fnb.tram_payment_bot/events');

  bool _isPermissionGranted = false;
  String _selectedStoreCode = 'TRAM01';
  bool _autoDetectStore = true;
  final List<Map<String, dynamic>> _recentPayments = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
    _loadConfig();
    _listenToPayments();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermission();
    }
  }

  Future<void> _checkPermission() async {
    try {
      final bool granted = await _methodChannel.invokeMethod('isNotificationPermissionGranted');
      if (mounted) {
        setState(() => _isPermissionGranted = granted);
      }
    } catch (_) {}
  }

  Future<void> _loadConfig() async {
    try {
      final String code = await _methodChannel.invokeMethod('getDefaultStoreCode');
      if (mounted) {
        setState(() => _selectedStoreCode = code);
      }
    } catch (_) {}
  }

  Future<void> _setStoreCode(String code) async {
    setState(() => _selectedStoreCode = code);
    try {
      await _methodChannel.invokeMethod('setDefaultStoreCode', {'storeCode': code});
    } catch (_) {}
  }

  void _listenToPayments() {
    _eventChannel.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        final payment = Map<String, dynamic>.from(event);
        if (mounted) {
          setState(() {
            _recentPayments.insert(0, payment);
            if (_recentPayments.length > 50) {
              _recentPayments.removeLast();
            }
          });
        }
      }
    }, onError: (_) {});
  }

  Future<void> _openSettings() async {
    try {
      await _methodChannel.invokeMethod('openNotificationSettings');
    } catch (_) {}
  }

  Future<void> _sendTestPayment({int amount = 15000, String? content}) async {
    final finalContent = content ?? 'tram01a1';
    try {
      await _methodChannel.invokeMethod('sendTestPayment', {
        'storeCode': _selectedStoreCode,
        'amount': amount,
        'content': finalContent,
        'bankName': 'MB Bank (Test)',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Đã bắn thử giao dịch ${_formatVND(amount)} (ND: $finalContent) cho $_selectedStoreCode!'),
            backgroundColor: const Color(0xFF137333),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _formatVND(dynamic amount) {
    final num val = amount is num ? amount : (num.tryParse(amount.toString()) ?? 0);
    return '${val.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} đ';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.hub_outlined, color: Colors.white, size: 24),
            SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trạm Payment Bot',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Lắng nghe chuyển khoản VietQR tự động',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        backgroundColor: const Color(0xFF7E2930),
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Làm mới trạng thái',
            onPressed: _checkPermission,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Trạng thái cấp quyền
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isPermissionGranted ? const Color(0xFF137333) : const Color(0xFFD93025),
                          boxShadow: [
                            BoxShadow(
                              color: (_isPermissionGranted ? const Color(0xFF137333) : const Color(0xFFD93025)).withOpacity(0.4),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _isPermissionGranted ? 'ĐANG LẮNG NGHE THÔNG BÁO' : 'CHƯA CẤP QUYỀN ĐỌC THÔNG BÁO',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: _isPermissionGranted ? const Color(0xFF137333) : const Color(0xFFD93025),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _isPermissionGranted
                        ? 'App đang chạy ngầm an toàn để đọc thông báo tiền vào từ các ngân hàng (MB, VCB, Techcombank, ACB, VPBank...) và đẩy lên máy POS.'
                        : 'Để app tự động nhận diện tiền về, bạn cần cấp quyền "Truy cập thông báo" cho ứng dụng trong Cài đặt hệ thống Android.',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF5D5B63), height: 1.4),
                  ),
                  if (!_isPermissionGranted) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.settings, size: 18),
                        label: const Text('Cấp quyền đọc thông báo ngay', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7E2930),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _openSettings,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 2. Cấu hình Chi nhánh
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.storefront_outlined, color: Color(0xFF7E2930), size: 20),
                      SizedBox(width: 8),
                      Text('Cấu hình Chi nhánh áp dụng', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tự động theo cú pháp mã đơn', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Tự chia tiền cho Quán 1/2/3 khi khách chuyển TRAM01, TRAM02...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    value: _autoDetectStore,
                    activeColor: const Color(0xFF7E2930),
                    onChanged: (val) => setState(() => _autoDetectStore = val),
                  ),
                  const Divider(height: 16),
                  const Text('Chi nhánh mặc định khi không tìm thấy mã:', style: TextStyle(fontSize: 13, color: Color(0xFF5D5B63))),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: ['TRAM01', 'TRAM02', 'TRAM03'].map((code) {
                      final isSelected = _selectedStoreCode == code;
                      return ChoiceChip(
                        label: Text(code == 'TRAM01' ? 'Quán 1 ($code)' : code == 'TRAM02' ? 'Quán 2 ($code)' : 'Quán 3 ($code)'),
                        selected: isSelected,
                        selectedColor: const Color(0xFF7E2930).withOpacity(0.15),
                        labelStyle: TextStyle(
                          color: isSelected ? const Color(0xFF7E2930) : Colors.black87,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        onSelected: (selected) {
                          if (selected) _setStoreCode(code);
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 3. Nút Test giao dịch
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.science_outlined, color: Color(0xFFD97706), size: 20),
                      SizedBox(width: 8),
                      Text('Kiểm tra & Bắn giao dịch Test', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Bấm nút bên dưới để giả lập một giao dịch chuyển khoản 35.000đ tới POS mà không cần chuyển tiền thật.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF5D5B63)),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.bolt, size: 18),
                        label: const Text('Test Bàn A1 (15.000đ - tram01a1)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF137333),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => _sendTestPayment(amount: 15000, content: 'tram01a1'),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.send_rounded, size: 18),
                        label: Text('Test Bàn D5 (35.000đ - ${_selectedStoreCode}_BAN_D5)'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF7E2930),
                          side: const BorderSide(color: Color(0xFF7E2930)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => _sendTestPayment(amount: 35000, content: '${_selectedStoreCode}_BAN_D5'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // 4. Danh sách giao dịch nhận gần đây
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Lịch sử nhận tiền (${_recentPayments.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1C1A2D)),
              ),
              if (_recentPayments.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _recentPayments.clear()),
                  child: const Text('Xóa lịch sử', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
            ],
          ),
          const SizedBox(height: 8),

          if (_recentPayments.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 10),
                  Text(
                    'Chưa có giao dịch chuyển khoản nào',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Khi app ngân hàng có thông báo nhận tiền, giao dịch sẽ hiện tại đây',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                  ),
                ],
              ),
            )
          else
            ..._recentPayments.map((p) {
              return Card(
                elevation: 1,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                color: Colors.white,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF137333).withOpacity(0.12),
                    child: const Icon(Icons.arrow_downward, color: Color(0xFF137333), size: 20),
                  ),
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatVND(p['amount']),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF137333)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7E2930).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          p['storeCode'] ?? 'TRAM01',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF7E2930)),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        'Nội dung nhận diện: ${p['content'] ?? ""}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF137333)),
                      ),
                      if ((p['rawText']?.toString() ?? '').isNotEmpty && p['rawText'] != p['content']) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Tin gốc: ${p['rawText']}',
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            p['bankName'] ?? 'Ngân hàng',
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                          Text(
                            p['timeStr'] ?? '',
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
