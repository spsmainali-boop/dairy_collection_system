import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/local_db.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';

/// Register a new farmer, or edit an existing one. Only the ID number
/// (the serial number this center assigns) is required — name and mobile
/// are optional and can be filled in or changed anytime later.
///
/// Updating a farmer's mobile number automatically provisions (or updates)
/// their own login once this record syncs to Supabase — a database trigger
/// there creates a login with PIN = the last 4 digits of that mobile,
/// exactly like every other account in this system. No extra step needed
/// here; saving the farmer record is enough.
class AddEditFarmerScreen extends StatefulWidget {
  const AddEditFarmerScreen({super.key, required this.centerId, this.farmer});
  final String centerId;
  final Farmer? farmer; // null = adding a new farmer

  @override
  State<AddEditFarmerScreen> createState() => _AddEditFarmerScreenState();
}

class _AddEditFarmerScreenState extends State<AddEditFarmerScreen> {
  late final TextEditingController _idCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _mobileCtrl;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.farmer != null;

  @override
  void initState() {
    super.initState();
    _idCtrl = TextEditingController(text: widget.farmer?.farmerCode ?? '');
    _nameCtrl = TextEditingController(text: widget.farmer?.name ?? '');
    _mobileCtrl = TextEditingController(text: widget.farmer?.mobile ?? '');
  }

  Future<void> _save() async {
    final id = _idCtrl.text.trim();
    if (id.isEmpty) {
      setState(() => _error = 'ID नम्बर आवश्यक छ'); // ID number is required
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
      centerId: widget.centerId,
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
    final mobileChanged = _isEditing && _mobileCtrl.text.trim() != (widget.farmer?.mobile ?? '');

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'किसान सम्पादन' : 'नयाँ किसान')), // Edit Farmer / New Farmer
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _idCtrl,
              enabled: !_isEditing, // ID number shouldn't change once assigned
              style: const TextStyle(fontSize: 22),
              decoration: const InputDecoration(
                labelText: 'ID नम्बर *', // ID Number (required)
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
            const SizedBox(height: 16),
            TextField(
              controller: _mobileCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(fontSize: 22),
              decoration: const InputDecoration(
                labelText: 'मोबाइल नम्बर (वैकल्पिक)', // Mobile number (optional)
                prefixIcon: Icon(Icons.phone_android),
              ),
              onChanged: (_) => setState(() {}), // refresh the mobile-changed hint below
            ),
            if (mobileChanged || (!_isEditing && _mobileCtrl.text.trim().isNotEmpty))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'नयाँ मोबाइल नम्बरको अन्तिम ४ अंक किसानको लगइन पिन हुनेछ।',
                  // "The last 4 digits of the new mobile number will be the farmer's login PIN."
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                ),
              ),
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
