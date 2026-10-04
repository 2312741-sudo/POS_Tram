import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/models/inventory_models.dart';

class ParsedInventoryItem {
  final int index;
  final String managementGroup;
  final String category;
  final String sku;
  final String name;
  final int costPrice;
  final int onHandQty;
  final int minStock;
  final int maxStock;
  final String baseUnitId;
  final String unitCode;
  final int conversionRate;
  final String attributes;
  final String relatedSku;
  final String imageUrl;
  final int weight;
  final String weightUnit;
  final String status; // 'ACTIVE' or 'DISCONTINUED'
  final bool trackStock;
  final String description;
  final String location;
  final String brand;
  final String kind; // 'RAW_MATERIAL' or 'TOOL'
  final bool isValid;
  final String statusMessage;
  final bool isDuplicateSkuDifferentName;

  ParsedInventoryItem({
    required this.index,
    required this.managementGroup,
    required this.category,
    required this.sku,
    required this.name,
    required this.costPrice,
    required this.onHandQty,
    required this.minStock,
    required this.maxStock,
    required this.baseUnitId,
    required this.unitCode,
    required this.conversionRate,
    required this.attributes,
    required this.relatedSku,
    required this.imageUrl,
    required this.weight,
    required this.weightUnit,
    required this.status,
    required this.trackStock,
    required this.description,
    required this.location,
    required this.brand,
    required this.kind,
    required this.isValid,
    required this.statusMessage,
    this.isDuplicateSkuDifferentName = false,
  });
}

class InventoryExcelService {
  static const List<String> excelHeaders = [
    'Nhóm quản lý',
    'Nhóm hàng (3 Cấp)',
    'Mã hàng',
    'Tên hàng',
    'Giá vốn',
    'Tồn kho hiện tại',
    'Định mức tồn nhỏ nhất',
    'Định mức tồn lớn nhất',
    'ĐVT',
    'Mã ĐVT Cơ bản',
    'Quy đổi',
    'Thuộc tính',
    'Mã hàng liên quan',
    'Hình ảnh (url1,url2...)',
    'Trọng lượng',
    'ĐVT trọng lượng',
    'Đang sử dụng',
    'Quản lý tồn kho',
    'Mô tả',
    'Vị trí',
    'Thương hiệu',
  ];

  /// Tải và chia sẻ file Excel mẫu cho người dùng
  static Future<String?> downloadSampleTemplate() async {
    try {
      final excel = Excel.createExcel();
      const sheetName = 'HangHoa';
      final sheet = excel[sheetName];
      excel.setDefaultSheet(sheetName);

      // Thêm Header
      sheet.appendRow(excelHeaders.map((h) => TextCellValue(h)).toList());

      // 4 Dòng dữ liệu mẫu chuẩn theo mẫu người dùng
      final sampleRows = [
        [
          TextCellValue('Nguyên vật liệu'),
          TextCellValue('Mứt'),
          TextCellValue('SP000001'),
          TextCellValue('Mứt Sinh Tố Ổi Xanh'),
          IntCellValue(140000),
          IntCellValue(20),
          IntCellValue(0),
          IntCellValue(999999999),
          TextCellValue('lít'),
          TextCellValue(''),
          IntCellValue(1),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          IntCellValue(1),
          TextCellValue('kg'),
          IntCellValue(1),
          IntCellValue(1),
          TextCellValue(''),
          TextCellValue('Kho chính|Kho phụ|Kho tạm'),
          TextCellValue('GreenFarm'),
        ],
        [
          TextCellValue('Công cụ dụng cụ'),
          TextCellValue('Nắp cốc'),
          TextCellValue('SP000002'),
          TextCellValue('Nắp dẹt'),
          IntCellValue(3000),
          IntCellValue(10),
          IntCellValue(0),
          IntCellValue(999999999),
          TextCellValue('cái'),
          TextCellValue(''),
          IntCellValue(1),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          IntCellValue(10),
          TextCellValue('g'),
          IntCellValue(1),
          IntCellValue(1),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue('Bao bì Gia Thành'),
        ],
        [
          TextCellValue('Công cụ dụng cụ'),
          TextCellValue('Nắp cốc'),
          TextCellValue('SP000003'),
          TextCellValue('Nắp tròn'),
          IntCellValue(3000),
          IntCellValue(10),
          IntCellValue(0),
          IntCellValue(999999999),
          TextCellValue('cái'),
          TextCellValue(''),
          IntCellValue(1),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          IntCellValue(10),
          TextCellValue('g'),
          IntCellValue(0),
          IntCellValue(1),
          TextCellValue(''),
          TextCellValue('Kho chính'),
          TextCellValue('Bao bì Gia Thành'),
        ],
        [
          TextCellValue('Công cụ dụng cụ'),
          TextCellValue('Cốc'),
          TextCellValue('SP000004'),
          TextCellValue('Cốc giấy 12oz'),
          IntCellValue(3000),
          IntCellValue(1000),
          IntCellValue(0),
          IntCellValue(999999999),
          TextCellValue('cái'),
          TextCellValue(''),
          IntCellValue(1),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          IntCellValue(20),
          TextCellValue('g'),
          IntCellValue(1),
          IntCellValue(1),
          TextCellValue(''),
          TextCellValue('Kho phụ'),
          TextCellValue('Bao bì Gia Thành'),
        ],
      ];

      for (final r in sampleRows) {
        sheet.appendRow(r);
      }

      final fileBytes = excel.save();
      if (fileBytes == null) return null;

      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/Mau_Nhap_Hang_Hoa_Kho.xlsx';
      final file = File(filePath);
      await file.writeAsBytes(fileBytes);

      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'File mẫu nhập hàng hóa kho (Excel)',
      );

      return filePath;
    } catch (e) {
      debugPrint('Error generating sample Excel: $e');
      rethrow;
    }
  }

  /// Xuất toàn bộ danh sách hàng hóa và số dư tồn kho ra file Excel 21 cột
  static Future<String?> exportInventoryExcel({
    required List<CatalogItemModel> items,
    required List<StockBalanceModel> balances,
    required String storeCode,
    required String storeName,
  }) async {
    try {
      final excel = Excel.createExcel();
      const sheetName = 'HangHoa';
      final sheet = excel[sheetName];
      excel.setDefaultSheet(sheetName);

      // Map stock balances theo itemId
      final Map<String, StockBalanceModel> balanceMap = {
        for (final b in balances) b.itemId: b,
      };

      // Header row
      sheet.appendRow(excelHeaders.map((h) => TextCellValue(h)).toList());

      // Dữ liệu hàng
      for (final item in items) {
        final bal = balanceMap[item.itemId];
        final onHand = bal?.onHandQty ?? 0;
        final kindLabel = (item.kind == 'TOOL' || (item.managementGroup?.contains('Công cụ') ?? false))
            ? 'Công cụ dụng cụ'
            : 'Nguyên vật liệu';
        final inUse = item.status == 'DISCONTINUED' ? 0 : 1;
        final track = item.trackStock ? 1 : 0;

        sheet.appendRow([
          TextCellValue(item.managementGroup ?? kindLabel),
          TextCellValue(item.managementGroup ?? (item.groupIds.isNotEmpty ? item.groupIds.first : kindLabel)),
          TextCellValue(item.sku ?? ''),
          TextCellValue(item.name),
          IntCellValue(item.costPrice),
          IntCellValue(onHand),
          IntCellValue(item.minStock),
          IntCellValue(item.maxStock > 0 ? item.maxStock : 999999999),
          TextCellValue(item.baseUnitId.isNotEmpty ? item.baseUnitId : 'cái'),
          TextCellValue(''),
          IntCellValue(item.conversionRate > 0 ? item.conversionRate : 1),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(item.imageUrl ?? ''),
          IntCellValue(item.weight),
          TextCellValue(item.weightUnit ?? ''),
          IntCellValue(inUse),
          IntCellValue(track),
          TextCellValue(item.description),
          TextCellValue(item.location ?? ''),
          TextCellValue(item.brand ?? ''),
        ]);
      }

      final fileBytes = excel.save();
      if (fileBytes == null) return null;

      final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/Danh_Sach_Hang_Hoa_Kho_${storeCode}_$dateStr.xlsx';
      final file = File(filePath);
      await file.writeAsBytes(fileBytes);

      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'Danh sách hàng hóa kho - $storeName ($storeCode)',
      );

      return filePath;
    } catch (e) {
      debugPrint('Error exporting inventory Excel: $e');
      rethrow;
    }
  }

  /// Phân tích nội dung file Excel đã chọn và kiểm tra tính hợp lệ
  static List<ParsedInventoryItem> parseExcelBytes({
    required Uint8List bytes,
    required List<CatalogItemModel> existingItems,
    required String duplicateSkuOption, // 'error' or 'replace'
  }) {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      throw Exception('File Excel không có dữ liệu bảng tính');
    }

    final String sheetName = excel.tables.containsKey('HangHoa')
        ? 'HangHoa'
        : excel.tables.keys.first;

    final sheet = excel.tables[sheetName];
    if (sheet == null || sheet.rows.isEmpty) {
      throw Exception('Không có dữ liệu trong sheet: $sheetName');
    }

    final rows = sheet.rows;
    if (rows.length < 2) {
      throw Exception('File Excel không có dòng dữ liệu hàng hóa!');
    }

    // Đọc hàng header
    final headerRow = rows[0].map((cell) => _getCellValue(cell).toLowerCase().trim()).toList();

    int getColIdx(List<String> aliases) {
      return headerRow.indexWhere((col) => aliases.any((a) => col.contains(a)));
    }

    final idxGroup = getColIdx(['nhóm quản lý', 'loại hàng']);
    final idxCategory = getColIdx(['nhóm hàng', 'danh mục']);
    final idxSku = getColIdx(['mã hàng', 'mã', 'sku']);
    final idxName = getColIdx(['tên hàng', 'tên']);
    final idxCost = getColIdx(['giá vốn', 'giá nhập']);
    final idxOnHand = getColIdx(['tồn kho hiện tại', 'tồn kho', 'tồn']);
    final idxMin = getColIdx(['định mức tồn nhỏ nhất', 'tồn nhỏ nhất', 'tồn tối thiểu']);
    final idxMax = getColIdx(['định mức tồn lớn nhất', 'tồn lớn nhất', 'tồn tối đa']);
    final idxUnit = getColIdx(['đvt', 'đơn vị']);
    final idxUnitCode = getColIdx(['mã đvt cơ bản']);
    final idxConversion = getColIdx(['quy đổi']);
    final idxAttr = getColIdx(['thuộc tính']);
    final idxRelSku = getColIdx(['mã hàng liên quan']);
    final idxImg = getColIdx(['hình ảnh', 'ảnh']);
    final idxWeight = getColIdx(['trọng lượng']);
    final idxWeightUnit = getColIdx(['đvt trọng lượng']);
    final idxInUse = getColIdx(['đang sử dụng', 'sử dụng']);
    final idxTrack = getColIdx(['quản lý tồn kho']);
    final idxDesc = getColIdx(['mô tả']);
    final idxLocation = getColIdx(['vị trí']);
    final idxBrand = getColIdx(['thương hiệu']);

    final List<ParsedInventoryItem> parsedList = [];
    final Set<String> seenSkusInFile = {};

    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty || row.every((c) => c == null || _getCellValue(c).trim().isEmpty)) {
        continue;
      }

      String getColVal(int idx, int defaultIdx) {
        final col = idx >= 0 ? idx : defaultIdx;
        if (col < row.length && row[col] != null) {
          return _getCellValue(row[col]).trim();
        }
        return '';
      }

      int getColInt(int idx, int defaultIdx, int fallback) {
        final str = getColVal(idx, defaultIdx);
        if (str.isEmpty) return fallback;
        final clean = str.replaceAll(RegExp(r'[^0-9\-]'), '');
        return int.tryParse(clean) ?? fallback;
      }

      final rawName = getColVal(idxName, 3);
      if (rawName.isEmpty || rawName.toLowerCase() == 'total' || rawName.toLowerCase() == 'tổng cộng') {
        continue;
      }

      final rawGroup = getColVal(idxGroup, 0);
      final rawCat = getColVal(idxCategory, 1);
      var rawSku = getColVal(idxSku, 2);
      if (rawSku.isEmpty) {
        rawSku = 'SP${i.toString().padLeft(6, '0')}';
      }

      final rawCost = getColInt(idxCost, 4, 0);
      final rawOnHand = getColInt(idxOnHand, 5, 0);
      final rawMin = getColInt(idxMin, 6, 0);
      final rawMax = getColInt(idxMax, 7, 999999999);
      final rawUnit = getColVal(idxUnit, 8).isNotEmpty ? getColVal(idxUnit, 8) : 'cái';
      final rawUnitCode = getColVal(idxUnitCode, 9);
      final rawConversion = getColInt(idxConversion, 10, 1);
      final rawAttr = getColVal(idxAttr, 11);
      final rawRelSku = getColVal(idxRelSku, 12);
      final rawImg = getColVal(idxImg, 13);
      final rawWeight = getColInt(idxWeight, 14, 0);
      final rawWeightUnit = getColVal(idxWeightUnit, 15);

      final inUseVal = getColVal(idxInUse, 16).toLowerCase();
      final status = (inUseVal == '0' || inUseVal == 'false' || inUseVal == 'ngưng')
          ? 'DISCONTINUED'
          : 'ACTIVE';

      final trackVal = getColVal(idxTrack, 17).toLowerCase();
      final trackStock = !(trackVal == '0' || trackVal == 'false' || trackVal == 'không');

      final rawDesc = getColVal(idxDesc, 18);
      final rawLoc = getColVal(idxLocation, 19);
      final rawBrand = getColVal(idxBrand, 20);

      final kind = (rawGroup.toLowerCase().contains('công cụ') || rawGroup.toLowerCase().contains('tool'))
          ? 'TOOL'
          : 'RAW_MATERIAL';

      // Kiểm tra tính hợp lệ & trùng mã SKU
      bool isValid = true;
      String statusMessage = 'Hợp lệ (Thêm mới)';
      bool isDuplicateSkuDifferentName = false;

      final existingItem = existingItems.cast<CatalogItemModel?>().firstWhere(
        (ci) => ci?.sku?.toLowerCase() == rawSku.toLowerCase(),
        orElse: () => null,
      );

      if (existingItem != null) {
        if (existingItem.name.trim().toLowerCase() != rawName.toLowerCase()) {
          isDuplicateSkuDifferentName = true;
          if (duplicateSkuOption == 'error') {
            isValid = false;
            statusMessage = 'Lỗi: Trùng mã hàng với [${existingItem.name}] (chọn "Thay thế tên hàng" để cập nhật)';
          } else {
            isValid = true;
            statusMessage = 'Cập nhật tên mới cho món [${existingItem.name}]';
          }
        } else {
          statusMessage = 'Cập nhật mặt hàng hiện có';
        }
      }

      if (seenSkusInFile.contains(rawSku.toLowerCase())) {
        isValid = false;
        statusMessage = 'Lỗi: Mã hàng $rawSku bị lặp lại nhiều lần trong file';
      }
      seenSkusInFile.add(rawSku.toLowerCase());

      parsedList.add(ParsedInventoryItem(
        index: i,
        managementGroup: rawGroup.isNotEmpty ? rawGroup : (kind == 'TOOL' ? 'Công cụ dụng cụ' : 'Nguyên vật liệu'),
        category: rawCat,
        sku: rawSku,
        name: rawName,
        costPrice: rawCost,
        onHandQty: rawOnHand,
        minStock: rawMin,
        maxStock: rawMax,
        baseUnitId: rawUnit,
        unitCode: rawUnitCode,
        conversionRate: rawConversion,
        attributes: rawAttr,
        relatedSku: rawRelSku,
        imageUrl: rawImg,
        weight: rawWeight,
        weightUnit: rawWeightUnit,
        status: status,
        trackStock: trackStock,
        description: rawDesc,
        location: rawLoc,
        brand: rawBrand,
        kind: kind,
        isValid: isValid,
        statusMessage: statusMessage,
        isDuplicateSkuDifferentName: isDuplicateSkuDifferentName,
      ));
    }

    return parsedList;
  }

  static String _getCellValue(Data? cell) {
    if (cell == null || cell.value == null) return '';
    return cell.value.toString().trim();
  }
}
