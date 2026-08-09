import 'package:flutter/material.dart';
import '../../core/auth/auth_service.dart';
import '../../core/database/local_db.dart';
import '../../core/theme/app_theme.dart';

/// A farmer's own view once their connection is 'active': total liters
/// delivered, total earned, total paid, current balance, and a list of
/// recent collection entries. Includes the ability to disconnect from the
/// center — only allowed once their balance is fully cleared.
class FarmerDashboardScreen extends StatefulWidget {
  const FarmerDashboardScreen({
    super.key,
    required this.authService,
    required this.mobile,
    required this.pin,
    required this.farmerId,
    required this.centerName,
    required this.onDisconnected,
    required this.onLogout,
  });
  final AuthService authService;
  final String mobile;
  final String pin;
  final String farmerId;
  final String centerName;
  final VoidCallback onDisconnected;
  final VoidCallback onLogout;

  @override
  State<FarmerDashboardScreen> createState() => _FarmerDashboardScreenState();
}

class _FarmerDashboardScreenState extends State<FarmerDashboardScreen> {
  bool _loading = true;
  double _totalLiters = 0;
  double _totalEarned = 0;
  double _totalPaid = 0;
  List<Map<String, Object?>> _recentEntries = [];
  bool _disconnecting = false;
  String? _disconnectMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = await LocalDb.instance.db;

    final collectionRows = await db.query(
      'milk_collections',
      where: 'farmer_id = ? AND is_deleted = 0',
      whereArgs: [widget.farmerId],
      orderBy: 'collection_date DESC',
    );
    final paymentRows = await db.query(
      'payments',
      where: 'farmer_id = ?',
      whereArgs: [widget.farmerId],
    );

    double liters = 0, earned = 0, paid = 0;
    for (final r in collectionRows) {
      liters += (r['quantity_liters'] as num).toDouble();
      earned += (r['amount'] as num).toDouble();
    }
    for (final r in paymentRows) {
      paid += (r['amount_paid'] as num).toDouble();
    }

    setState(() {
      _totalLiters = liters;
      _totalEarned = earned;
      _totalPaid = paid;
      _recentEntries = collectionRows.take(10).toList();
      _loading = false;
    });
  }

  double get _balance => _totalEarned - _totalPaid;

  Future<void> _confirmDisconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('विच्छेद गर्नुहोस्?'), // Disconnect?
        content: Text(_balance == 0
            ? '${widget.centerName} बाट विच्छेद हुन निश्चित हुनुहुन्छ?' // "Sure you want to disconnect from <center>?"
            : 'बाँकी रु. ${_balance.toStringAsFixed(2)} — विच्छेद गर्न पहिले भुक्तानी बुझ्नुपर्छ।'),
            // "Outstanding Rs X — you must be paid first before disconnecting."
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('रद्द गर्नुहोस्')), // Cancel
          if (_balance == 0)
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
              child: const Text('विच्छेद गर्नुहोस्'), // Disconnect
            ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _disconnecting = true);
    final message = await widget.authService.disconnectFarmer(mobile: widget.mobile, pin: widget.pin);
    setState(() {
      _disconnecting = false;
      _disconnectMessage = message;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
    if (message.contains('सफलतापूर्वक')) {
      // "successfully" — matches the RPC's success message
      widget.onDisconnected();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.centerName),
        actions: [
          IconButton(icon: const Icon(Icons.logout), tooltip: 'लगआउट', onPressed: widget.onLogout),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(label: 'जम्मा लिटर', value: _totalLiters.toStringAsFixed(1)), // Total Liters
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(label: 'कमाएको', value: 'रु. ${_totalEarned.toStringAsFixed(0)}'), // Earned
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(label: 'भुक्तानी भएको', value: 'रु. ${_totalPaid.toStringAsFixed(0)}'), // Paid
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          label: 'बाँकी', // Balance
                          value: 'रु. ${_balance.toStringAsFixed(0)}',
                          highlight: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text('हालैका विवरणहरू', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), // Recent entries
                  const SizedBox(height: 8),
                  if (_recentEntries.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text('कुनै विवरण छैन', style: TextStyle(fontSize: 16, color: Colors.black54)), // No entries yet
                    )
                  else
                    ..._recentEntries.map((e) {
                      final date = (e['collection_date'] as String).substring(0, 10);
                      final shift = e['shift'] == 'morning' ? 'बिहान' : 'साँझ';
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('$date · $shift'),
                        subtitle: Text('फ्याट ${e['fat']} · ${e['quantity_liters']} लि.'),
                        trailing: Text('रु. ${(e['amount'] as num).toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryGreen)),
                      );
                    }),
                  const SizedBox(height: 32),
                  OutlinedButton(
                    onPressed: _disconnecting ? null : _confirmDisconnect,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      foregroundColor: AppTheme.errorRed,
                      side: const BorderSide(color: AppTheme.errorRed),
                    ),
                    child: _disconnecting
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('केन्द्रबाट विच्छेद हुनुहोस्'), // Disconnect from center
                  ),
                ],
              ),
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, this.highlight = false});
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlight ? AppTheme.primaryGreen.withOpacity(0.1) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.black54)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
