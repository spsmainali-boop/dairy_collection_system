import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/local_db.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../farmers/add_edit_farmer_screen.dart';
import '../farmers/farmer_list_screen.dart';
import '../rates/rate_chart_screen.dart';

/// Primary post-login screen for a collection center.
///
/// Every registered farmer at this center appears as its own fixed row,
/// listed by Roll ID — the operator doesn't type Roll IDs at all, just fills
/// in FAT% and Qty (liters) for whichever farmers delivered milk this shift,
/// and leaves the rest blank. One shift/date applies to the whole batch.
/// Each filled row is priced from the active rate chart and saved as its
/// own offline-queued milk collection entry — a mistake in one row doesn't
/// block the rest of the batch from saving.
class BulkCollectionScreen extends StatefulWidget {
  const BulkCollectionScreen({
    super.key,
    required this.centerId,
    required this.enteredByUserId,
  });
  final String centerId;
  final String enteredByUserId;

  @override
  State<BulkCollectionScreen> createState() => _BulkCollectionScreenState();
}

class _BulkCollectionScreenState extends State<BulkCollectionScreen> {
  CollectionShift _shift = CollectionShift.morning;
  final DateTime _date = DateTime.now(); // today; back-dating not supported yet

  List<Farmer> _farmers = [];
  final Map<String, TextEditingController> _fatCtrls = {};
  final Map<String, TextEditingController> _qtyCtrls = {};
  final Map<String, String?> _errors = {};

  bool _loading = true;
  bool _saving = false;
  String? _summary;

  @override
  void initState() {
    super.initState();
    _loadFarmers();
  }

  @override
  void dispose() {
    for (final c in _fatCtrls.values) c.dispose();
    for (final c in _qtyCtrls.values) c.dispose();
    super.dispose();
  }

  Future<void> _loadFarmers() async {
    setState(() => _loading = true);
    final db = await LocalDb.instance.db;
    final rows = await db.query(
      'farmers',
      where: 'center_id = ?',
      whereArgs: [widget.centerId],
      orderBy: 'farmer_code ASC',
    );
    final farmers = rows.map((r) => Farmer.fromLocalMap(r)).toList();

    // Keep existing typed values for farmers still present; add controllers
    // for any newly-loaded farmer (e.g. just registered).
    for (final f in farmers) {
      _fatCtrls.putIfAbsent(f.id, () => TextEditingController());
      _qtyCtrls.putIfAbsent(f.id, () => TextEditingController());
    }

    setState(() {
      _farmers = farmers;
      _loading = false;
    });
  }

  Future<double?> _rateForFat(double fat) async {
    final db = await LocalDb.instance.db;
    final monthStart =
        DateTime(_date.year, _date.month, 1).toIso8601String().substring(0, 10);
    final rows = await db.query(
      'rate_charts',
      where: 'center_id = ? AND month = ? AND fat_min <= ? AND fat_max > ?',
      whereArgs: [widget.centerId, monthStart, fat, fat],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (rows.first['rate_per_liter'] as num).toDouble();
  }

  Future<void> _submitAll() async {
    setState(() {
      _saving = true;
      _summary = null;
      _errors.clear();
    });

    int savedCount = 0;
    int errorCount = 0;

    for (final farmer in _farmers) {
      final fatText = _fatCtrls[farmer.id]!.text.trim();
      final qtyText = _qtyCtrls[farmer.id]!.text.trim();
      if (fatText.isEmpty && qtyText.isEmpty) continue; // no delivery this shift — skip

      final fat = double.tryParse(fatText);
      final qty = double.tryParse(qtyText);
      if (fat == null || qty == null) {
        _errors[farmer.id] = 'फ्याट र क्वान्टिटी दुवै आवश्यक छ'; // both FAT and Qty required
        errorCount++;
        continue;
      }

      final rate = await _rateForFat(fat);
      if (rate == null) {
        _errors[farmer.id] = 'यो फ्याटको लागि दर तोकिएको छैन'; // no rate set for this FAT
        errorCount++;
        continue;
      }

      final id = const Uuid().v4();
      final entry = MilkCollectionEntry(
        id: id,
        clientUuid: id,
        farmerId: farmer.id,
        centerId: widget.centerId,
        collectionDate: _date,
        shift: _shift,
        fat: fat,
        quantityLiters: qty,
        rateApplied: rate,
        amount: MilkCollectionEntry.calculateAmount(
            fat: fat, quantityLiters: qty, ratePerLiterPerFatPoint: rate),
        enteredBy: widget.enteredByUserId,
      );
      await LocalDb.instance.upsertAndQueue(
        table: 'milk_collections',
        row: entry.toLocalMap(),
        clientUuid: entry.clientUuid,
        operation: 'insert',
      );
      savedCount++;
    }

    setState(() {
      _saving = false;
      _summary = errorCount == 0
          ? '$savedCount किसानको विवरण सुरक्षित भयो ✓' // "N farmers' entries saved"
          : '$savedCount सुरक्षित भयो, $errorCount त्रुटि — तल हेर्नुहोस्'; // "N saved, N errors — see below"
      if (errorCount == 0) {
        for (final c in _fatCtrls.values) c.clear();
        for (final c in _qtyCtrls.values) c.clear();
      }
    });
  }

  Future<void> _goToAddFarmer() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AddEditFarmerScreen(centerId: widget.centerId),
    ));
    _loadFarmers(); // pick up the newly added farmer as a new row
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('yyyy-MM-dd').format(_date);

    return Scaffold(
      appBar: AppBar(
        title: const Text('थोक सङ्कलन'), // Bulk Collection
        actions: [
          IconButton(
            icon: const Icon(Icons.currency_rupee),
            tooltip: 'दूध दर', // Milk Rate
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => RateChartScreen(centerId: widget.centerId),
              ));
            },
          ),
          IconButton(
            icon: const Icon(Icons.person_add_alt_1),
            tooltip: 'किसान थप्नुहोस्', // Add Farmer
            onPressed: _goToAddFarmer,
          ),
          IconButton(
            icon: const Icon(Icons.people_alt_outlined),
            tooltip: 'किसान सूची', // Farmer List
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => FarmerListScreen(centerId: widget.centerId),
              ));
              _loadFarmers();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text(Strings.morning, style: TextStyle(fontSize: 18)),
                          selected: _shift == CollectionShift.morning,
                          onSelected: (_) => setState(() => _shift = CollectionShift.morning),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text(Strings.evening, style: TextStyle(fontSize: 18)),
                          selected: _shift == CollectionShift.evening,
                          onSelected: (_) => setState(() => _shift = CollectionShift.evening),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('मिति: $dateLabel', style: const TextStyle(fontSize: 14, color: Colors.black54)),
                    ],
                  ),
                ),
                if (_farmers.isEmpty)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('कुनै किसान दर्ता गरिएको छैन', style: TextStyle(fontSize: 18)),
                          // "No farmers registered yet"
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _goToAddFarmer,
                            icon: const Icon(Icons.person_add_alt_1),
                            label: const Text('किसान थप्नुहोस्'),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(flex: 3, child: Text('Roll ID', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                        SizedBox(width: 8),
                        Expanded(flex: 2, child: Text('फ्याट%', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                        SizedBox(width: 8),
                        Expanded(flex: 2, child: Text('क्वान्टिटी', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _farmers.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final farmer = _farmers[i];
                        final error = _errors[farmer.id];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(farmer.farmerCode,
                                            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
                                        if (farmer.name != null)
                                          Text(farmer.name!, style: const TextStyle(fontSize: 13, color: Colors.black54)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 2,
                                    child: TextField(
                                      controller: _fatCtrls[farmer.id],
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      style: const TextStyle(fontSize: 18),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 2,
                                    child: TextField(
                                      controller: _qtyCtrls[farmer.id],
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      style: const TextStyle(fontSize: 18),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (error != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(error, style: const TextStyle(color: AppTheme.errorRed, fontSize: 13)),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Column(
                        children: [
                          if (_summary != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(_summary!, style: const TextStyle(fontSize: 16), textAlign: TextAlign.center),
                            ),
                          ElevatedButton(
                            onPressed: _saving ? null : _submitAll,
                            child: _saving
                                ? const SizedBox(
                                    height: 24, width: 24,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                                : const Text('बल्क पेश गर्नुहोस्'), // Bulk Submit
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
