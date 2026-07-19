import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/local_db.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';

/// Core daily-use screen: an operator selects a farmer, shift, FAT, and
/// quantity — the amount is computed live from the active rate chart and
/// shown in large text before saving. Designed for one-handed, fast entry
/// at a busy collection counter.
class MilkCollectionScreen extends StatefulWidget {
  const MilkCollectionScreen({
    super.key,
    required this.centerId,
    required this.enteredByUserId,
    required this.getRateForFat, // injected: looks up rate_charts for current month/center
    required this.searchFarmers,  // injected: local SQLite farmer search/QR lookup
  });

  final String centerId;
  final String enteredByUserId;
  final Future<double?> Function(double fat) getRateForFat;
  final Future<List<Farmer>> Function(String query) searchFarmers;

  @override
  State<MilkCollectionScreen> createState() => _MilkCollectionScreenState();
}

class _MilkCollectionScreenState extends State<MilkCollectionScreen> {
  Farmer? _selectedFarmer;
  CollectionShift _shift = CollectionShift.morning;
  final _fatCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  double? _liveRate;
  double _liveAmount = 0;
  bool _saving = false;

  Future<void> _recalculate() async {
    final fat = double.tryParse(_fatCtrl.text);
    final qty = double.tryParse(_qtyCtrl.text);
    if (fat == null) {
      setState(() {
        _liveRate = null;
        _liveAmount = 0;
      });
      return;
    }
    final rate = await widget.getRateForFat(fat);
    setState(() {
      _liveRate = rate;
      _liveAmount = (rate != null && qty != null)
          ? MilkCollectionEntry.calculateAmount(quantityLiters: qty, ratePerLiter: rate)
          : 0;
    });
  }

  Future<void> _save() async {
    if (_selectedFarmer == null || _liveRate == null) return;
    final fat = double.tryParse(_fatCtrl.text);
    final qty = double.tryParse(_qtyCtrl.text);
    if (fat == null || qty == null) return;

    setState(() => _saving = true);
    final id = const Uuid().v4();
    final entry = MilkCollectionEntry(
      id: id,
      clientUuid: id,
      farmerId: _selectedFarmer!.id,
      centerId: widget.centerId,
      collectionDate: DateTime.now(),
      shift: _shift,
      fat: fat,
      quantityLiters: qty,
      rateApplied: _liveRate!,
      amount: _liveAmount,
      enteredBy: widget.enteredByUserId,
    );

    await LocalDb.instance.upsertAndQueue(
      table: 'milk_collections',
      row: entry.toLocalMap(),
      clientUuid: entry.clientUuid,
      operation: 'insert',
    );

    setState(() {
      _saving = false;
      _selectedFarmer = null;
      _fatCtrl.clear();
      _qtyCtrl.clear();
      _liveRate = null;
      _liveAmount = 0;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('सुरक्षित भयो ✓')), // "Saved"
      );
    }
  }

  Future<void> _pickFarmer() async {
    final controller = TextEditingController();
    List<Farmer> results = [];
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheetState) {
        return Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: Strings.selectFarmer),
                    onChanged: (q) async {
                      final r = await widget.searchFarmers(q);
                      setSheetState(() => results = r);
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.qr_code_scanner, size: 32),
                  tooltip: Strings.scanQr,
                  onPressed: () {
                    // Hook up mobile_scanner here; on scan, call
                    // widget.searchFarmers(scannedCode) and auto-select if match.
                  },
                ),
              ]),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: results.length,
                  itemBuilder: (ctx, i) => ListTile(
                    title: Text(results[i].name, style: const TextStyle(fontSize: 20)),
                    subtitle: Text(results[i].farmerCode),
                    onTap: () {
                      setState(() => _selectedFarmer = results[i]);
                      Navigator.pop(ctx);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('दूध सङ्कलन')), // Milk Collection
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: _pickFarmer,
              icon: const Icon(Icons.person_search, size: 28),
              label: Text(
                _selectedFarmer?.name ?? Strings.selectFarmer,
                style: const TextStyle(fontSize: 20),
              ),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(64)),
            ),
            const SizedBox(height: 16),
            Row(
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
            const SizedBox(height: 16),
            TextField(
              controller: _fatCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 26),
              decoration: const InputDecoration(labelText: Strings.fat),
              onChanged: (_) => _recalculate(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _qtyCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 26),
              decoration: const InputDecoration(labelText: Strings.quantity),
              onChanged: (_) => _recalculate(),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  if (_liveRate != null)
                    Text('${Strings.rate}: रु. ${_liveRate!.toStringAsFixed(2)} / लिटर',
                        style: const TextStyle(fontSize: 18)),
                  const SizedBox(height: 4),
                  Text(
                    'रु. ${_liveAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 40, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen),
                  ),
                  Text(Strings.amount, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: (_selectedFarmer != null && _liveRate != null && !_saving) ? _save : null,
              child: _saving
                  ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white))
                  : const Text(Strings.submit),
            ),
          ],
        ),
      ),
    );
  }
}
