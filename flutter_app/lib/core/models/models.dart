/// Core domain models. Each carries a [clientUuid] generated on-device so the
/// sync engine can push it to Supabase idempotently, plus [syncStatus] used
/// purely on the local SQLite side (never sent to the server).
library models;

enum SyncStatus { synced, pending, conflict }

enum CenterLevel { l2, l1, l0 }

enum UserRole { superAdmin, l2Admin, l1Operator, l0Operator, farmer }

enum CollectionShift { morning, evening }

class Center {
  final String id;
  final String clientUuid;
  final String name;
  final CenterLevel level;
  final String? parentCenterId;
  final String? district;
  final double? gpsLat;
  final double? gpsLng;
  final String settlementCycle; // '15day' | 'monthly'
  final SyncStatus syncStatus;

  Center({
    required this.id,
    required this.clientUuid,
    required this.name,
    required this.level,
    this.parentCenterId,
    this.district,
    this.gpsLat,
    this.gpsLng,
    this.settlementCycle = '15day',
    this.syncStatus = SyncStatus.pending,
  });

  Map<String, Object?> toLocalMap() => {
        'id': id,
        'client_uuid': clientUuid,
        'name': name,
        'level': level.name,
        'parent_center_id': parentCenterId,
        'district': district,
        'gps_lat': gpsLat,
        'gps_lng': gpsLng,
        'settlement_cycle': settlementCycle,
        'sync_status': syncStatus.name,
      };

  factory Center.fromLocalMap(Map<String, Object?> m) => Center(
        id: m['id'] as String,
        clientUuid: m['client_uuid'] as String,
        name: m['name'] as String,
        level: CenterLevel.values.firstWhere((e) => e.name == m['level']),
        parentCenterId: m['parent_center_id'] as String?,
        district: m['district'] as String?,
        gpsLat: m['gps_lat'] as double?,
        gpsLng: m['gps_lng'] as double?,
        settlementCycle: m['settlement_cycle'] as String? ?? '15day',
        syncStatus:
            SyncStatus.values.firstWhere((e) => e.name == m['sync_status']),
      );
}

class Farmer {
  final String id;
  final String clientUuid;
  final String farmerCode;
  final String name;
  final String? mobile;
  final String centerId;
  final SyncStatus syncStatus;

  Farmer({
    required this.id,
    required this.clientUuid,
    required this.farmerCode,
    required this.name,
    this.mobile,
    required this.centerId,
    this.syncStatus = SyncStatus.pending,
  });

  Map<String, Object?> toLocalMap() => {
        'id': id,
        'client_uuid': clientUuid,
        'farmer_code': farmerCode,
        'name': name,
        'mobile': mobile,
        'center_id': centerId,
        'sync_status': syncStatus.name,
      };

  factory Farmer.fromLocalMap(Map<String, Object?> m) => Farmer(
        id: m['id'] as String,
        clientUuid: m['client_uuid'] as String,
        farmerCode: m['farmer_code'] as String,
        name: m['name'] as String,
        mobile: m['mobile'] as String?,
        centerId: m['center_id'] as String,
        syncStatus:
            SyncStatus.values.firstWhere((e) => e.name == m['sync_status']),
      );
}

class MilkCollectionEntry {
  final String id;
  final String clientUuid;
  final String farmerId;
  final String centerId;
  final DateTime collectionDate;
  final CollectionShift shift;
  final double fat;
  final double? snf;
  final double quantityLiters;
  final double rateApplied;
  final double amount;
  final String enteredBy;
  final SyncStatus syncStatus;

  MilkCollectionEntry({
    required this.id,
    required this.clientUuid,
    required this.farmerId,
    required this.centerId,
    required this.collectionDate,
    required this.shift,
    required this.fat,
    this.snf,
    required this.quantityLiters,
    required this.rateApplied,
    required this.amount,
    required this.enteredBy,
    this.syncStatus = SyncStatus.pending,
  });

  Map<String, Object?> toLocalMap() => {
        'id': id,
        'client_uuid': clientUuid,
        'farmer_id': farmerId,
        'center_id': centerId,
        'collection_date': collectionDate.toIso8601String(),
        'shift': shift.name,
        'fat': fat,
        'snf': snf,
        'quantity_liters': quantityLiters,
        'rate_applied': rateApplied,
        'amount': amount,
        'entered_by': enteredBy,
        'sync_status': syncStatus.name,
      };

  factory MilkCollectionEntry.fromLocalMap(Map<String, Object?> m) =>
      MilkCollectionEntry(
        id: m['id'] as String,
        clientUuid: m['client_uuid'] as String,
        farmerId: m['farmer_id'] as String,
        centerId: m['center_id'] as String,
        collectionDate: DateTime.parse(m['collection_date'] as String),
        shift: CollectionShift.values.firstWhere((e) => e.name == m['shift']),
        fat: (m['fat'] as num).toDouble(),
        snf: (m['snf'] as num?)?.toDouble(),
        quantityLiters: (m['quantity_liters'] as num).toDouble(),
        rateApplied: (m['rate_applied'] as num).toDouble(),
        amount: (m['amount'] as num).toDouble(),
        enteredBy: m['entered_by'] as String,
        syncStatus:
            SyncStatus.values.firstWhere((e) => e.name == m['sync_status']),
      );

  /// Auto-calculation used everywhere (entry screen, edits, imports).
  static double calculateAmount(
      {required double quantityLiters, required double ratePerLiter}) {
    return double.parse((quantityLiters * ratePerLiter).toStringAsFixed(2));
  }
}
