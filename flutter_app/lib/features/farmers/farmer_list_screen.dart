import 'package:flutter/material.dart';
import '../../core/database/local_db.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import 'add_edit_farmer_screen.dart';

/// Lists farmers registered at this center. Tap a row to edit (fill in or
/// change name/mobile); tap the + button to register a new farmer.
class FarmerListScreen extends StatefulWidget {
  const FarmerListScreen({super.key, required this.centerId});
  final String centerId;

  @override
  State<FarmerListScreen> createState() => _FarmerListScreenState();
}

class _FarmerListScreenState extends State<FarmerListScreen> {
  List<Farmer> _farmers = [];
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({String query = ''}) async {
    final db = await LocalDb.instance.db;
    final rows = await db.query(
      'farmers',
      where: query.isEmpty
          ? 'center_id = ?'
          : 'center_id = ? AND (name LIKE ? OR farmer_code LIKE ? OR mobile LIKE ?)',
      whereArgs: query.isEmpty
          ? [widget.centerId]
          : [widget.centerId, '%$query%', '%$query%', '%$query%'],
      orderBy: 'farmer_code ASC',
    );
    setState(() => _farmers = rows.map((r) => Farmer.fromLocalMap(r)).toList());
  }

  Future<void> _openAddEdit({Farmer? farmer}) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AddEditFarmerScreen(centerId: widget.centerId, farmer: farmer),
    ));
    _load(query: _searchCtrl.text); // refresh after returning
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('किसान सूची')), // Farmer List
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'खोज्नुहोस् (नाम, ID, मोबाइल)', // Search (name, ID, mobile)
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (q) => _load(query: q),
            ),
          ),
          Expanded(
            child: _farmers.isEmpty
                ? const Center(child: Text('कुनै किसान फेला परेन', style: TextStyle(fontSize: 18)))
                : ListView.separated(
                    itemCount: _farmers.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final f = _farmers[i];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.primaryGreen.withOpacity(0.15),
                          child: Text(f.farmerCode.isNotEmpty ? f.farmerCode[0] : '?',
                              style: const TextStyle(color: AppTheme.primaryGreen, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(f.displayName, style: const TextStyle(fontSize: 19)),
                        subtitle: Text(
                          'ID: ${f.farmerCode}${f.mobile != null ? ' • ${f.mobile}' : ''}',
                          style: const TextStyle(fontSize: 15),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openAddEdit(farmer: f),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddEdit(),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('नयाँ किसान'), // New Farmer
      ),
    );
  }
}
