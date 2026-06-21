import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/strings.dart';
import '../services/api_service.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onLogin;

  const LoginScreen({super.key, required this.onLogin});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _recoveryPhrase = TextEditingController();
  bool _isRegister = false;
  String? _error;
  String? _deviceId;

  @override
  void initState() {
    super.initState();
    _initDeviceId();
  }

  Future<void> _initDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString('device_id');
    if (id == null) {
      id = _generateId();
      await prefs.setString('device_id', id);
    }
    if (mounted) setState(() => _deviceId = id);
  }

  String _generateId() {
    final r = Random();
    return '${DateTime.now().millisecondsSinceEpoch}_${r.nextInt(1000000)}';
  }

  Future<void> _submit() async {
    if (_username.text.isEmpty || _password.text.isEmpty) return;
    setState(() => _error = null);

    try {
      Map<String, dynamic> result;
      if (_isRegister) {
        result = await ApiService.register(_username.text, _password.text,
            deviceId: _deviceId, recoveryPhrase: _recoveryPhrase.text);
      } else {
        result = await ApiService.login(_username.text, _password.text);
      }

      if (result.containsKey('error')) {
        setState(() => _error = result['error']);
      } else {
        widget.onLogin();
      }
    } catch (e) {
      setState(() => _error = Strings.t('auth.connection_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
                child: Icon(Icons.shield_moon, size: 52, color: cs.onPrimaryContainer),
              ),
              const SizedBox(height: 20),
              Text('Barricade', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Свой мессенджер. Без облаков.',
                  style: TextStyle(color: cs.outline, fontSize: 14)),
              const SizedBox(height: 32),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Войти')),
                  ButtonSegment(value: true, label: Text('Регистрация')),
                ],
                selected: {_isRegister},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() {
                  _isRegister = s.first;
                  _error = null;
                }),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _username,
                decoration: InputDecoration(
                  labelText: Strings.t('auth.username'),
                  prefixIcon: const Icon(Icons.alternate_email),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                decoration: InputDecoration(
                  labelText: Strings.t('auth.password'),
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
                obscureText: true,
                onSubmitted: (_) => _submit(),
              ),
              if (_isRegister) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _recoveryPhrase,
                  decoration: InputDecoration(
                    labelText: Strings.t('auth.recovery_phrase'),
                    helperText: Strings.t('auth.recovery_phrase_hint'),
                    prefixIcon: const Icon(Icons.key),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: cs.error)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  child: Text(_isRegister ? Strings.t('auth.register') : Strings.t('auth.login')),
                ),
              ),
              if (!_isRegister) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const _ResetPasswordScreen()),
                  ),
                  child: Text(Strings.t('auth.forgot_password')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _recoveryPhrase.dispose();
    super.dispose();
  }
}

class _ResetPasswordScreen extends StatefulWidget {
  const _ResetPasswordScreen();

  @override
  State<_ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<_ResetPasswordScreen> {
  final _username = TextEditingController();
  final _recoveryPhrase = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  String? _error;
  bool _loading = false;

  Future<void> _submit() async {
    if (_username.text.isEmpty || _recoveryPhrase.text.isEmpty || _newPassword.text.isEmpty) return;
    if (_newPassword.text != _confirmPassword.text) {
      setState(() => _error = 'Пароли не совпадают');
      return;
    }
    if (_newPassword.text.length < 4) {
      setState(() => _error = 'Пароль должен быть минимум 4 символа');
      return;
    }
    setState(() { _error = null; _loading = true; });
    try {
      final result = await ApiService.resetPassword(
        _username.text, _recoveryPhrase.text, _newPassword.text,
      );
      if (result.containsKey('error')) {
        setState(() => _error = result['error']);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(Strings.t('auth.password_reset'))),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      setState(() => _error = Strings.t('auth.connection_failed'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(Strings.t('auth.reset_password'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _username,
              decoration: InputDecoration(
                labelText: Strings.t('auth.username'),
                prefixIcon: const Icon(Icons.alternate_email),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _recoveryPhrase,
              decoration: InputDecoration(
                labelText: Strings.t('auth.recovery_phrase'),
                helperText: Strings.t('auth.recovery_phrase_help'),
                prefixIcon: const Icon(Icons.key),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _newPassword,
              decoration: InputDecoration(
                labelText: Strings.t('auth.new_password'),
                prefixIcon: const Icon(Icons.lock_outline),
              ),
              obscureText: true,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _confirmPassword,
              decoration: InputDecoration(
                labelText: Strings.t('auth.confirm_password'),
                prefixIcon: const Icon(Icons.lock_outline),
              ),
              obscureText: true,
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: cs.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(Strings.t('auth.reset_password')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _username.dispose();
    _recoveryPhrase.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }
}
