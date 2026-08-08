import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/local_db.dart';
import '../../core/theme/app_theme.dart';

/// Lets a center set this month's milk rate — a single flat value, not a
/// FAT-range slab table. Pricing formula used throughout the app:
///
///   Amount = FAT% x Quantity (liters) x this rate
///
/// e.g. FAT 5.5, 5.5 L, rate Rs 15 -> 5.5 x 5.5 x 15 = Rs 453.75
///
/// Internally this still uses the `rate_charts` table (fat_min=0,
/// fat_max=100 — a single row covering every possible FAT% — so the same
/// lookup query in the bulk entry screen keeps working unchanged); it just
/// isn't exposed to the user as ranges anymore.
class RateChartScreen extends StatefulWidget {
  const RateChartScreen({super.key, required this.centerId});
  final String centerId;

  @override
  State<RateChartScreen> createState() => _RateChartScreenState();
}

class _RateChartScreenState extends State<RateChartScreen> {
  Map<String, Object?>? _currentRate;
  bool _loading = true;

  String get _monthKey =>
      DateTime(DateTime.now().year, DateTime.now().month, 1).toIso8601String().substring(0, 10);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = await LocalDb.instance.db;
    final rows = await db.query(
      'rate_charts',
      where: 'center_id = ? AND month = ?',
      whereArgs: [widget.centerId, _monthKey],
      limit: 1,
    );
    setState(() {
      _currentRate = rows.isNotEmpty ? rows.first : null;
      _loading = false;
    });
  }

  Future<void> _editRate() async {
    final rateCtrl = TextEditingController(
        text: _currentRate != null ? _currentRate!['rate_per_liter'].toString() : '');
    String? error;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        return AlertDialog(
          title: Text(_currentRate != null ? 'दर परिवर्तन गर्नुहोस्' : 'यो महिनाको दर सेट गर्नुहोस्'),
          // "Change rate" / "Set this month's rate"
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('रकम = फ्याट% × क्वान्टिटी (लिटर) × दर', style: TextStyle(fontSize: 13, color: Colors.black54)),
              // "Amount = FAT% x Quantity (liters) x Rate"
              const SizedBox(height: 12),
              TextField(
                controller: rateCtrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 22),
                decoration: const InputDecoration(labelText: 'दर (रु. प्रति फ्याट% प्रति लिटर)'),
                // "Rate (Rs. per FAT% per liter)"
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!, style: const TextStyle(color: AppTheme.errorRed)),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('रद्द गर्नुहोस्')), // Cancel
            ElevatedButton(
              onPressed: () async {
                final rate = double.tryParse(rateCtrl.text.trim());
                if (rate == null || rate <= 0) {
                  setDialogState(() => error = 'सही दर भर्नुहोस्'); // enter a valid rate
                  return;
                }
                final id = _currentRate?['id'] as String? ?? const Uuid().v4();
                final clientUuid = _currentRate?['client_uuid'] as String? ?? id;
                await LocalDb.instance.upsertAndQueue(
                  table: 'rate_charts',
                  row: {
                    'id': id,
                    'client_uuid': clientUuid,
                    'center_id': widget.centerId,
                    'month': _monthKey,
                    'fat_min': 0,
                    'fat_max': 100, // covers every FAT% — flat per-point rate, not slabs
                    'rate_per_liter': rate,
                    'sync_status': 'pending',
                  },
                  clientUuid: clientUuid,
                  operation: _currentRate != null ? 'update' : 'insert',
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('सुरक्षित गर्नुहोस्'), // Save
            ),
          ],
        );
      }),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('दूध दर')), // Milk Rate
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'रकम = फ्याट% × क्वान्टिटी (लिटर) × दर',
                    style: TextStyle(fontSize: 15, color: Colors.black54),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _currentRate != null
                              ? 'रु. ${(_currentRate!['rate_per_liter'] as num).toStringAsFixed(2)}'
                              : 'तोकिएको छैन', // Not set
                          style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                        ),
                        const SizedBox(height: 4),
                        const Text('प्रति फ्याट% प्रति लिटर', style: TextStyle(fontSize: 15)), // per FAT% per liter
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  ElevatedButton.icon(
                    onPressed: _editRate,
                    icon: Icon(_currentRate != null ? Icons.edit : Icons.add),
                    label: Text(_currentRate != null ? 'दर परिवर्तन गर्नुहोस्' : 'दर सेट गर्नुहोस्'),
                    // "Change rate" / "Set rate"
                  ),
                ],
              ),
            ),
    );
  }
}
