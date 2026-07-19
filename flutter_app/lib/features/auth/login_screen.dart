import 'package:flutter/material.dart';
import '../../core/auth/auth_service.dart';
import '../../core/theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.authService, required this.onLoggedIn});
  final AuthService authService;
  final VoidCallback onLoggedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _mobileCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final mustChangePin = await widget.authService.login(
        mobile: _mobileCtrl.text.trim(),
        pin: _pinCtrl.text.trim(),
      );
      if (!mounted) return;
      if (mustChangePin) {
        await _showChangePinDialog(_mobileCtrl.text.trim());
      }
      widget.onLoggedIn();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showChangePinDialog(String mobile) async {
    final newPinCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? dialogError;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        return AlertDialog(
          title: const Text(Strings.changePinTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: newPinCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                decoration: const InputDecoration(hintText: Strings.newPin),
              ),
              TextField(
                controller: confirmCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                decoration: const InputDecoration(hintText: Strings.confirmPin),
              ),
              if (dialogError != null)
                Text(dialogError!, style: const TextStyle(color: AppTheme.errorRed)),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                if (newPinCtrl.text.length < 4) {
                  setDialogState(() => dialogError = 'कम्तिमा ४ अंकको पिन राख्नुहोस्');
                  return;
                }
                if (newPinCtrl.text != confirmCtrl.text) {
                  setDialogState(() => dialogError = 'पिन मिलेन');
                  return;
                }
                await widget.authService.changePin(mobile: mobile, newPin: newPinCtrl.text);
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: const Text(Strings.save),
            ),
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.local_drink_rounded, size: 72, color: AppTheme.primaryGreen),
                const SizedBox(height: 12),
                Text(Strings.appName, style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center),
                const SizedBox(height: 32),
                TextField(
                  controller: _mobileCtrl,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(fontSize: 22),
                  decoration: const InputDecoration(
                    hintText: Strings.mobileNumber,
                    prefixIcon: Icon(Icons.phone_android),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _pinCtrl,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 6,
                  style: const TextStyle(fontSize: 22),
                  decoration: const InputDecoration(
                    hintText: Strings.pin,
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!,
                        style: const TextStyle(color: AppTheme.errorRed, fontSize: 16),
                        textAlign: TextAlign.center),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            height: 24, width: 24,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                        : const Text(Strings.login),
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
