import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/local_db.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../farmers/add_edit_farmer_screen.dart';
import '../farmers/farmer_list_screen.dart';

class _BulkRow {
  final TextEditingController rollIdCtrl = TextEditingController();
  final TextEditingController fatCtrl = TextEditingController();
  final TextEditingController literCtrl = TextEditingController();
  String? error;
}

/// Primary post-login screen for a collection center. Instead of picking one
/// farmer at a time, the operator enters Roll ID + FAT% + Liter for many
/// farmers in a single sitting — much faster for a busy morning/evening
/// collection window where the operator already knows every farmer's Roll ID
/// by heart. One shift applies to the whole batch. Each row is looked up by
/// Roll ID within this center, priced from the active rate chart, and saved
/// as its own offline-queued milk collection entry — a mistake in one row
/// doesn't block the rest of the batch from saving.
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
  final List<_BulkRow> _rows = [_BulkRow()];
  bool _saving = false;
  String? _summary;

  void _addRow() => setState(() => _rows.add(_BulkRow()));

  void _removeRow(int i) {
    if (_rows.length == 1) return;
    setState(() => _rows.removeAt(i));
  }

  Future<double?> _rateForFat(double fat) async {
    final db = await LocalDb.instance.db;
    final monthStart =
        DateTime(DateTime.now().year, DateTime.now().month, 1).toIso8601String().substring(0, 10);
    final rows = await db.query(
      'rate_charts',
      where: 'center_id = ? AND month = ? AND fat_min <= ? AND fat_max > ?',
      whereArgs: [widget.centerId, monthStart, fat, fat],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (rows.first['rate_per_liter'] as num).toDouble();
  }

  Future<void> _saveAll() async {
    setState(() {
      _saving = true;
      _summary = null;
    });

    final db = await LocalDb.instance.db;
    int savedCount = 0;
    int errorCount = 0;

    for (final row in _rows) {
      row.error = null;
      final rollId = row.rollIdCtrl.text.trim();
      if (rollId.isEmpty && row.fatCtrl.text.trim().isEmpty && row.literCtrl.text.trim().isEmpty) {
        continue; // fully empty row — ignore silently, don't count as an error
      }
      if (rollId.isEmpty) {
        row.error = 'Roll ID आवश्यक छ';
        errorCount++;
        continue;
      }

      final fat = double.tryParse(row.fatCtrl.text.trim());
      final liter = double.tryParse(row.literCtrl.text.trim());
      if (fat == null || liter == null) {
        row.error = 'फ्याट र लिटर दुवै आवश्यक छ';
        errorCount++;
        continue;
      }

      final farmerRows = await db.query(
        'farmers',
        where: 'farmer_code = ? AND center_id = ?',
        whereArgs: [rollId, widget.centerId],
        limit: 1,
      );
      if (farmerRows.isEmpty) {
        row.error = 'यो Roll ID फेला परेन';
        errorCount++;
        continue;
      }

      final rate = await _rateForFat(fat);
      if (rate == null) {
        row.error = 'यो फ्याटको लागि दर तोकिएको छैन';
        errorCount++;
        continue;
      }

      final farmer = Farmer.fromLocalMap(farmerRows.first);
      final id = const Uuid().v4();
      final entry = MilkCollectionEntry(
        id: id,
        clientUuid: id,
        farmerId: farmer.id,
        centerId: widget.centerId,
        collectionDate: DateTime.now(),
        shift: _shift,
        fat: fat,
        quantityLiters: liter,
        rateApplied: rate,
        amount: MilkCollectionEntry.calculateAmount(quantityLiters: liter, ratePerLiter: rate),
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
        _rows
          ..clear()
          ..add(_BulkRow());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('थोक सङ्कलन'), // Bulk Collection
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1),
            tooltip: 'किसान थप्नुहोस्', // Add Farmer
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => AddEditFarmerScreen(centerId: widget.centerId),
              ));
            },
          ),
          IconButton(
            icon: const Icon(Icons.people_alt_outlined),
            tooltip: 'किसान सूची', // Farmer List
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => FarmerListScreen(centerId: widget.centerId),
              ));
            },
          ),
        ],
      ),
      body: Column(
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
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text('Roll ID', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                SizedBox(width: 8),
                Expanded(flex: 2, child: Text('फ्याट%', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                SizedBox(width: 8),
                Expanded(flex: 2, child: Text('लिटर', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                SizedBox(width: 36),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _rows.length,
              itemBuilder: (context, i) {
                final row = _rows[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: row.rollIdCtrl,
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
                              controller: row.fatCtrl,
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
                              controller: row.literCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(fontSize: 18),
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 36,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                              onPressed: () => _removeRow(i),
                            ),
                          ),
                        ],
                      ),
                      if (row.error != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 4, top: 2),
                          child: Text(row.error!, style: const TextStyle(color: AppTheme.errorRed, fontSize: 13)),
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
                  OutlinedButton.icon(
                    onPressed: _addRow,
                    icon: const Icon(Icons.add),
                    label: const Text('थप पङ्क्ति'), // Add row
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  ),
                  const SizedBox(height: 12),
                  if (_summary != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_summary!, style: const TextStyle(fontSize: 16), textAlign: TextAlign.center),
                    ),
                  ElevatedButton(
                    onPressed: _saving ? null : _saveAll,
                    child: _saving
                        ? const SizedBox(
                            height: 24, width: 24,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                        : const Text('सबै सुरक्षित गर्नुहोस्'), // Save all
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
