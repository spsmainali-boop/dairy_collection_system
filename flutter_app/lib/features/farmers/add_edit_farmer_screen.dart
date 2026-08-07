import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/local_db.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';

/// Register a new farmer, or edit an existing one ("farmer profile").
///
/// Only the Roll ID (the serial number this center assigns) is required —
/// mobile and name are optional and can be filled in or changed anytime.
/// Roll ID itself can also be changed later by the center (e.g. correcting
/// a typo, or re-numbering), unlike the earlier version of this screen.
///
/// Setting/changing the mobile number automatically provisions (or updates)
/// the farmer's own login once this record syncs to Supabase — a database
/// trigger there creates a login with PIN = the last 4 digits of that
/// mobile. The "temporary PIN" shown here is a live preview of that PIN so
/// the center can tell the farmer their login on the spot.
///
/// On an existing farmer's profile, the center can also reassign which
/// collection center the farmer belongs to.
class AddEditFarmerScreen extends StatefulWidget {
  const AddEditFarmerScreen({super.key, required this.centerId, this.farmer});
  final String centerId;
  final Farmer? farmer; // null = adding a new farmer

  @override
  State<AddEditFarmerScreen> createState() => _AddEditFarmerScreenState();
}

class _AddEditFarmerScreenState extends State<AddEditFarmerScreen> {
  late final TextEditingController _mobileCtrl;
  late final TextEditingController _idCtrl;
  late final TextEditingController _nameCtrl;
  bool _saving = false;
  String? _error;

  List<Center> _centers = [];
  late String _selectedCenterId;

  bool get _isEditing => widget.farmer != null;

  @override
  void initState() {
    super.initState();
    _mobileCtrl = TextEditingController(text: widget.farmer?.mobile ?? '');
    _idCtrl = TextEditingController(text: widget.farmer?.farmerCode ?? '');
    _nameCtrl = TextEditingController(text: widget.farmer?.name ?? '');
    _selectedCenterId = widget.farmer?.centerId ?? widget.centerId;
    _mobileCtrl.addListener(() => setState(() {})); // live-update temp PIN preview
    _loadCenters();
  }

  Future<void> _loadCenters() async {
    final db = await LocalDb.instance.db;
    final rows = await db.query('centers', orderBy: 'name ASC');
    setState(() => _centers = rows.map((r) => Center.fromLocalMap(r)).toList());
  }

  String get _tempPinPreview {
    final digits = _mobileCtrl.text.trim();
    if (digits.length < 4) return '----';
    return digits.substring(digits.length - 4);
  }

  Future<void> _save() async {
    final id = _idCtrl.text.trim();
    if (id.isEmpty) {
      setState(() => _error = 'Roll ID आवश्यक छ'); // Roll ID is required
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final name = _nameCtrl.text.trim();
    final mobile = _mobileCtrl.text.trim();
    final recordId = widget.farmer?.id ?? const Uuid().v4();
    final clientUuid = widget.farmer?.clientUuid ?? recordId;

    final farmer = Farmer(
      id: recordId,
      clientUuid: clientUuid,
      farmerCode: id,
      name: name.isEmpty ? null : name,
      mobile: mobile.isEmpty ? null : mobile,
      centerId: _selectedCenterId,
    );

    try {
      await LocalDb.instance.upsertAndQueue(
        table: 'farmers',
        row: farmer.toLocalMap(),
        clientUuid: farmer.clientUuid,
        operation: _isEditing ? 'update' : 'insert',
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = 'सुरक्षित गर्न सकिएन: $e'); // Could not save
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showTempPin = _mobileCtrl.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'किसान प्रोफाइल' : 'किसान थप्नुहोस्')), // Farmer Profile / Add Farmer
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _mobileCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(fontSize: 22),
              decoration: const InputDecoration(
                labelText: 'मोबाइल नम्बर (वैकल्पिक)', // Mobile number (optional)
                prefixIcon: Icon(Icons.phone_android),
              ),
            ),
            if (showTempPin)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 4),
                child: Text(
                  'अस्थायी पिन: $_tempPinPreview', // Temporary PIN: ____
                  style: const TextStyle(fontSize: 15, color: AppTheme.primaryGreen, fontWeight: FontWeight.w600),
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _idCtrl,
              style: const TextStyle(fontSize: 22),
              decoration: const InputDecoration(
                labelText: 'Roll ID *', // compulsory, always editable — center can renumber
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(fontSize: 22),
              decoration: const InputDecoration(
                labelText: 'नाम (वैकल्पिक)', // Name (optional)
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            if (_isEditing) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _centers.any((c) => c.id == _selectedCenterId) ? _selectedCenterId : null,
                decoration: const InputDecoration(
                  labelText: 'सङ्कलन केन्द्र', // Collection Center
                  prefixIcon: Icon(Icons.store_outlined),
                ),
                items: _centers
                    .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name, style: const TextStyle(fontSize: 18))))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedCenterId = v);
                },
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_error!, style: const TextStyle(color: AppTheme.errorRed, fontSize: 16)),
              ),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 24, width: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                  : const Text('सुरक्षित गर्नुहोस्'), // Save
            ),
          ],
        ),
      ),
    );
  }
}
