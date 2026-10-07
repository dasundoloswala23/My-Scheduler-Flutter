import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'auth_service.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _auth = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _signUp = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _submitEmail() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _run(() async {
      if (_signUp) {
        await _auth.signUpWithEmail(
          name: _name.text,
          email: _email.text,
          password: _password.text,
        );
      } else {
        await _auth.signInWithEmail(email: _email.text, password: _password.text);
      }
    });
  }

  Future<void> _resetPassword() async {
    if (_email.text.trim().isEmpty) {
      setState(() => _error = 'Enter your email first, then tap reset.');
      return;
    }
    await _run(() => _auth.sendPasswordReset(_email.text));
    if (mounted && _error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset email sent.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.bar_chart_rounded, color: Colors.white, size: 32),
                  ),
                  const SizedBox(height: 20),
                  Text('MY SCHEDULER', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.4, color: context.palette.textSecondary)),
                  const SizedBox(height: 4),
                  Text(_signUp ? 'Create account' : 'Welcome back', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 28),
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFFDECEC), borderRadius: BorderRadius.circular(12)),
                      child: Text(_error!, style: TextStyle(color: context.palette.danger)),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        if (_signUp) ...[
                          TextFormField(
                            controller: _name,
                            decoration: const InputDecoration(hintText: 'Full name'),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(hintText: 'Email'),
                          validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          obscureText: true,
                          autofillHints: const [AutofillHints.password],
                          decoration: const InputDecoration(hintText: 'Password'),
                          validator: (v) => (v == null || v.length < 6) ? 'At least 6 characters' : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _submitEmail,
                    child: _busy
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_signUp ? 'Create account' : 'Sign in'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _signUp = !_signUp),
                    child: Text(_signUp ? 'Already have an account? Sign in' : 'New here? Create an account'),
                  ),
                  if (!_signUp)
                    TextButton(onPressed: _busy ? null : _resetPassword, child: const Text('Forgot password?')),
                  const SizedBox(height: 20),
                  Row(children: [
                    const Expanded(child: Divider()),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: TextStyle(color: context.palette.textSecondary))),
                    const Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _run(_auth.signInWithGoogle),
                    icon: const Icon(Icons.g_mobiledata, size: 28),
                    label: const Text('Continue with Google'),
                  ),
                  if (_auth.supportsAppleSignIn) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _run(_auth.signInWithApple),
                      icon: const Icon(Icons.apple, size: 22),
                      label: const Text('Continue with Apple'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
