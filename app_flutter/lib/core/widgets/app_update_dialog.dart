import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:open_filex/open_filex.dart';
import '../models/app_update_info.dart';
import '../services/app_update_service.dart';

/// Hộp thoại thông báo và tải bản cập nhật APK trực tiếp trên máy
class AppUpdateDialog extends StatefulWidget {
  final AppUpdateInfo info;
  final bool isMandatory;
  final String currentVersion;
  final int currentBuild;

  const AppUpdateDialog({
    super.key,
    required this.info,
    this.isMandatory = false,
    required this.currentVersion,
    required this.currentBuild,
  });

  /// Hàm tiện ích hiển thị Dialog cập nhật
  static Future<void> show(
    BuildContext context, {
    required AppUpdateInfo info,
    bool isMandatory = false,
    required String currentVersion,
    required int currentBuild,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: !isMandatory,
      builder: (ctx) => PopScope(
        canPop: !isMandatory,
        child: AppUpdateDialog(
          info: info,
          isMandatory: isMandatory,
          currentVersion: currentVersion,
          currentBuild: currentBuild,
        ),
      ),
    );
  }

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  String _status = '';
  String? _errorMessage;
  File? _downloadedFile;

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _progress = 0.0;
      _status = 'Đang kết nối máy chủ...';
    });

    try {
      final file = await AppUpdateService().downloadApkFile(
        widget.info.apkUrl,
        onProgress: (p, received, total) {
          if (mounted) {
            setState(() {
              _progress = p;
              _receivedBytes = received;
              _totalBytes = total;
            });
          }
        },
        onStatusChange: (status) {
          if (mounted) {
            setState(() {
              _status = status;
            });
          }
        },
      );

      _downloadedFile = file;

      if (mounted) {
        setState(() {
          _status = 'Đã tải xong, đang mở trình cài đặt...';
        });
      }

      // Kích hoạt PackageInstaller của Android
      final openRes = await AppUpdateService().installApk(file.path);
      if (openRes.type != ResultType.done && mounted) {
        setState(() {
          _status = 'Vui lòng nhấn nút "Cài đặt" bên dưới nếu chưa thấy màn hình cập nhật';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Lỗi tải cập nhật: $e';
          _isDownloading = false;
        });
      }
    }
  }

  Future<void> _reInstall() async {
    if (_downloadedFile == null) return;
    try {
      await AppUpdateService().installApk(_downloadedFile!.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi mở trình cài đặt: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      child: Container(
        width: 440,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header icon & Tiêu đề
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    LucideIcons.sparkles,
                    color: primaryColor,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Đã có phiên bản mới!',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Phiên bản ${widget.info.versionName} (Build ${widget.info.versionCode})',
                        style: TextStyle(
                          fontSize: 13,
                          color: primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Thông tin chi tiết
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Phiên bản hiện tại:', style: TextStyle(fontSize: 13, color: Colors.black54)),
                      Text('${widget.currentVersion} (${widget.currentBuild})',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Dung lượng tải:', style: TextStyle(fontSize: 13, color: Colors.black54)),
                      Text(widget.info.apkSize ?? 'Khoảng 40–50 MB',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  if (widget.isMandatory) ...[
                    const SizedBox(height: 6),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Yêu cầu:', style: TextStyle(fontSize: 13, color: Colors.black54)),
                        Text('Bắt buộc cập nhật',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Nội dung thay đổi (Changelog)
            if (widget.info.releaseNotes.trim().isNotEmpty) ...[
              const Text(
                'Nội dung cập nhật:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 120),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    widget.info.releaseNotes,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Tiến trình tải xuống nếu đang tải
            if (_isDownloading) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _status.isNotEmpty ? _status : 'Đang tải bản cập nhật...',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.black87),
                      ),
                      Text(
                        '${(_progress * 100).toInt()}%',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primaryColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: _progress > 0 ? _progress : null,
                      minHeight: 10,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                    ),
                  ),
                  if (_totalBytes > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${_formatBytes(_receivedBytes)} / ${_formatBytes(_totalBytes)}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Hiển thị lỗi nếu có
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.alertCircle, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Các nút thao tác
            if (!_isDownloading && _downloadedFile == null) ...[
              Row(
                children: [
                  if (!widget.isMandatory) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Để sau', style: TextStyle(color: Colors.black54)),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _startDownload,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.download, size: 16),
                          SizedBox(width: 6),
                          Text('Cập nhật ngay', style: TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ] else if (_downloadedFile != null) ...[
              ElevatedButton.icon(
                onPressed: _reInstall,
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                label: const Text('Cài đặt bản cập nhật', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
