import 'package:firebase_database/firebase_database.dart';
import '../../data/models/app_models.dart';
import '../../core/domain/promotion_migration.dart';

class MigrationService {
  static final MigrationService _instance = MigrationService._internal();
  factory MigrationService() => _instance;
  MigrationService._internal();

  final _db = FirebaseDatabase.instance;
  String _currentStoreCode = 'TRAM01';
  DatabaseReference get _storeRef => _db.ref('stores/$_currentStoreCode');
  
  void switchStore(String storeCode) { _currentStoreCode = storeCode; }

  /// Lấy danh sách legacy promotions chưa được migrate
  Future<List<PromotionModel>> getLegacyPromotions() async {
    List<PromotionModel> promotions = [];
    final snapshot = await _storeRef.child('promotions').get();
    
    if (snapshot.value != null) {
      final map = snapshot.value as Map<dynamic, dynamic>;
      map.forEach((key, value) {
        promotions.add(PromotionModel.fromMap(value, key.toString()));
      });
    }
    return promotions;
  }

  /// Kiểm tra xem migration đã chạy chưa
  Future<MigrationStatus> getMigrationStatus() async {
    final snapshot = await _storeRef.child('migration_log/promotions').get();
    if (snapshot.value == null) {
      return MigrationStatus(migrated: false);
    }
    
    final data = snapshot.value as Map<dynamic, dynamic>;
    return MigrationStatus(
      migrated: data['migrated'] ?? false,
      migratedAt: data['migratedAt'],
      count: data['count'] ?? 0,
      warnings: List<String>.from(data['warnings'] ?? []),
    );
  }

  /// Chạy migration: đọc legacy → convert → ghi campaign mới
  Future<MigrationResult> migratePromotions({bool dryRun = false}) async {
    final status = await getMigrationStatus();
    if (status.migrated) {
      return MigrationResult(skipped: status.count, warnings: ['Already migrated']);
    }

    final legacies = await getLegacyPromotions();
    int success = 0;
    int skipped = 0;
    List<String> allWarnings = [];
    List<String> allErrors = [];

    for (var old in legacies) {
      try {
        final campaign = PromotionMigration.fromLegacy(old);
        final warnings = PromotionMigration.validateMigration(old, campaign);
        
        allWarnings.addAll(warnings.map((w) => '${old.id}: $w'));

        if (!dryRun) {
          await _storeRef.child('campaigns/${campaign.campaignId}').set(campaign.toMap());
          success++;
        } else {
          success++;
        }
      } catch (e) {
        allErrors.add('Error migrating ${old.id}: $e');
        skipped++;
      }
    }

    if (!dryRun && success > 0) {
      await _storeRef.child('migration_log/promotions').set({
        'migrated': true,
        'migratedAt': DateTime.now().millisecondsSinceEpoch,
        'count': success,
        'warnings': allWarnings,
      });
    }

    return MigrationResult(
      success: success,
      skipped: skipped,
      warnings: allWarnings,
      errors: allErrors,
    );
  }

  /// Rollback: xóa campaigns đã migrate (giữ legacy)
  Future<void> rollbackMigration() async {
    final status = await getMigrationStatus();
    if (!status.migrated) return;

    final snapshot = await _storeRef.child('campaigns').get();
    if (snapshot.value != null) {
      final map = snapshot.value as Map<dynamic, dynamic>;
      final updates = <String, dynamic>{};
      
      map.forEach((key, value) {
        final data = Map<String, dynamic>.from(value);
        if (data['legacyPromotionId'] != null) {
          updates[key.toString()] = null;
        }
      });

      if (updates.isNotEmpty) {
        await _storeRef.child('campaigns').update(updates);
      }
    }

    await _storeRef.child('migration_log/promotions').remove();
  }
}

class MigrationStatus {
  final bool migrated;
  final int? migratedAt;
  final int count;
  final List<String> warnings;
  
  MigrationStatus({
    required this.migrated, 
    this.migratedAt, 
    this.count = 0, 
    this.warnings = const []
  });
}

class MigrationResult {
  final int success;
  final int skipped;
  final List<String> warnings;
  final List<String> errors;
  
  MigrationResult({
    this.success = 0, 
    this.skipped = 0, 
    this.warnings = const [], 
    this.errors = const []
  });
}
