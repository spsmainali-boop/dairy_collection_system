import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/local_db.dart';
import '../../core/theme/app_theme.dart';

/// Lets a center set/edit this month's FAT-slab rate chart — e.g.
/// FAT 3.0–3.5 → Rs 62/L, FAT 3.5–4.0 → Rs 66/L. This is what the bulk
/// entry screen looks up when computing each farmer's amount.
class RateChartScreen extends StatefulWidget {
  const RateChartScreen({super.key, required this.centerId});
  final String centerId;

  @override
  State<RateChartScreen> createState() => _RateChartScreenState();
}

class _RateChartScreenState extends State<RateChartScreen> {
  List<Map<String, Object?>> _slabs = [];
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
      orderBy: 'fat_min ASC',
    );
    setState(() {
      _slabs = rows;
      _loading = false;
    });
  }

  Future<void> _addOrEditSlab({Map<String, Object?>? existing}) async {
    final fatMinCtrl = TextEditingController(text: existing != null ? existing['fat_min'].toString() : '');
    final fatMaxCtrl = TextEditingController(text: existing != null ? existing['fat_max'].toString() : '');
    final rateCtrl = TextEditingController(text: existing != null ? existing['rate_per_liter'].toString() : '');
    String? error;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        return AlertDialog(
          title: Text(existing != null ? 'दर सम्पादन गर्नुहोस्' : 'नयाँ दर थप्नुहोस्'), // Edit rate / Add new rate
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: fatMinCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'फ्याट देखि (जस्तै: 3.0)'), // FAT from
              ),
              TextField(
                controller: fatMaxCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'फ्याट सम्म (जस्तै: 3.5)'), // FAT to
              ),
              TextField(
                controller: rateCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'दर प्रति लिटर (रु.)'), // Rate per liter
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
                final fatMin = double.tryParse(fatMinCtrl.text.trim());
                final fatMax = double.tryParse(fatMaxCtrl.text.trim());
                final rate = double.tryParse(rateCtrl.text.trim());
                if (fatMin == null || fatMax == null || rate == null || fatMax <= fatMin) {
                  setDialogState(() => error = 'सही मान भर्नुहोस् (सम्म > देखि)'); // enter valid values
                  return;
                }
                final id = existing?['id'] as String? ?? const Uuid().v4();
                final clientUuid = existing?['client_uuid'] as String? ?? id;
                await LocalDb.instance.upsertAndQueue(
                  table: 'rate_charts',
                  row: {
                    'id': id,
                    'client_uuid': clientUuid,
                    'center_id': widget.centerId,
                    'month': _monthKey,
                    'fat_min': fatMin,
                    'fat_max': fatMax,
                    'rate_per_liter': rate,
                    'sync_status': 'pending',
                  },
                  clientUuid: clientUuid,
                  operation: existing != null ? 'update' : 'insert',
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
          : _slabs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('यो महिनाको लागि दर तोकिएको छैन', style: TextStyle(fontSize: 18)),
                      // "No rate set for this month"
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => _addOrEditSlab(),
                        icon: const Icon(Icons.add),
                        label: const Text('नयाँ दर थप्नुहोस्'), // Add new rate
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _slabs.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, i) {
                    final s = _slabs[i];
                    final fatMin = (s['fat_min'] as num).toDouble();
                    final fatMax = (s['fat_max'] as num).toDouble();
                    final rate = (s['rate_per_liter'] as num).toDouble();
                    return ListTile(
                      title: Text('फ्याट $fatMin – $fatMax', style: const TextStyle(fontSize: 18)),
                      subtitle: Text(
                        'रु. ${rate.toStringAsFixed(2)} / लिटर',
                        style: const TextStyle(fontSize: 16, color: AppTheme.primaryGreen, fontWeight: FontWeight.w600),
                      ),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => _addOrEditSlab(existing: s),
                    );
                  },
                ),
      floatingActionButton: _slabs.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _addOrEditSlab(),
              icon: const Icon(Icons.add),
              label: const Text('नयाँ दर'), // New rate
            ),
    );
  }
}
