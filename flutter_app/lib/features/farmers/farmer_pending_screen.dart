import 'package:flutter/material.dart';
import '../../core/auth/auth_service.dart';
import '../../core/theme/app_theme.dart';

/// Shown to a farmer whose connection to a center is still 'pending' —
/// completely blocks everything else in the app until they respond. This is
/// the only thing a newly-added (not-yet-accepted) farmer can see.
class FarmerPendingScreen extends StatefulWidget {
  const FarmerPendingScreen({
    super.key,
    required this.authService,
    required this.mobile,
    required this.pin,
    required this.centerName,
    required this.onAccepted,
    required this.onRejected,
  });
  final AuthService authService;
  final String mobile;
  final String pin;
  final String centerName;
  final VoidCallback onAccepted;
  final VoidCallback onRejected;

  @override
  State<FarmerPendingScreen> createState() => _FarmerPendingScreenState();
}

class _FarmerPendingScreenState extends State<FarmerPendingScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _respond(bool accept) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ok = await widget.authService.respondToConnection(
        mobile: widget.mobile,
        pin: widget.pin,
        accept: accept,
      );
      if (!ok) {
        setState(() => _error = 'केही समस्या भयो, फेरि प्रयास गर्नुहोस्'); // something went wrong, try again
        return;
      }
      if (accept) {
        widget.onAccepted();
      } else {
        widget.onRejected();
      }
    } catch (e) {
      setState(() => _error = 'इन्टरनेट जडान जाँच गर्नुहोस्'); // check your internet connection
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.person_add_alt_1, size: 64, color: AppTheme.primaryGreen),
                const SizedBox(height: 20),
                Text(
                  '${widget.centerName} ले तपाईंलाई किसानको रूपमा थपेको छ',
                  // "<Center> has added you as a farmer"
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'स्वीकार गर्नुभयो भने यो केन्द्रमा तपाईंको दूध विवरण र भुक्तानी हेर्न सक्नुहुन्छ।',
                  // "If you accept, you'll be able to see your milk records and payments at this center."
                  style: TextStyle(fontSize: 16, color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(_error!, style: const TextStyle(color: AppTheme.errorRed, fontSize: 15)),
                  ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : () => _respond(true),
                    child: _loading
                        ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white))
                        : const Text('स्वीकार गर्नुहोस्'), // Accept
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _loading ? null : () => _respond(false),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(64)),
                    child: const Text('अस्वीकार गर्नुहोस्', style: TextStyle(fontSize: 20, color: AppTheme.errorRed)),
                    // Reject
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
