import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../legal/legal_pages.dart';
import 'auth_service.dart';
import 'auth_widgets.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key, this.auth});

  /// For tests; the app uses the real [AuthService].
  final AuthService? auth;

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  late final AuthService _auth = widget.auth ?? AuthService();
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _signUp = false;
  bool _busy = false;
  bool _obscure = true;
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
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _run(() async {
      if (_signUp) {
        await _auth.signUpWithEmail(name: _name.text, email: _email.text, password: _password.text);
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Password reset email sent.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Align(alignment: Alignment.centerLeft, child: BrandLogo(size: 60)),
        const SizedBox(height: 22),
        Text(
          'MY SCHEDULER',
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 1.6,
            fontWeight: FontWeight.w700,
            color: palette.accent,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _signUp ? 'Create your account' : 'Welcome back',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _signUp
              ? 'Start planning your days in a few seconds.'
              : 'Sign in to continue planning your day.',
          style: TextStyle(fontSize: 14.5, color: palette.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 24),
        if (_error != null) ...[AuthErrorBanner(message: _error!), const SizedBox(height: 16)],
        Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              children: [
                if (_signUp) ...[
                  AuthTextField(
                    controller: _name,
                    label: 'Full name',
                    icon: Icons.person_outline_rounded,
                    enabled: !_busy,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.name],
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
                  ),
                  const SizedBox(height: 14),
                ],
                AuthTextField(
                  controller: _email,
                  label: 'Email',
                  icon: Icons.mail_outline_rounded,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)
                        ? null
                        : 'Enter a valid email';
                  },
                ),
                const SizedBox(height: 14),
                AuthTextField(
                  controller: _password,
                  label: 'Password',
                  icon: Icons.lock_outline_rounded,
                  enabled: !_busy,
                  obscureText: _obscure,
                  keyboardType: TextInputType.visiblePassword,
                  textInputAction: TextInputAction.done,
                  autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
                  onSubmitted: (_) => _submitEmail(),
                  validator: (v) => (v == null || v.length < 6) ? 'At least 6 characters' : null,
                  suffix: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    icon: Icon(
                      _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      size: 20,
                      color: palette.textSecondary,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!_signUp)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _busy ? null : _resetPassword,
              style: TextButton.styleFrom(foregroundColor: palette.accent),
              child: const Text('Forgot password?'),
            ),
          )
        else
          const SizedBox(height: 16),
        const SizedBox(height: 4),
        AuthPrimaryButton(
          label: _signUp ? 'Create account' : 'Sign in',
          busy: _busy,
          onPressed: _submitEmail,
        ),
        // The "or" rule only earns its place when a provider follows it.
        if (_auth.supportsGoogleSignIn || _auth.supportsAppleSignIn) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: Divider(color: palette.divider)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('or', style: TextStyle(color: palette.textSecondary, fontSize: 13)),
              ),
              Expanded(child: Divider(color: palette.divider)),
            ],
          ),
          const SizedBox(height: 20),
        ],
        if (_auth.supportsGoogleSignIn)
          ProviderButton(
            icon: const Icon(Icons.g_mobiledata, size: 28),
            label: 'Continue with Google',
            onPressed: _busy ? null : () => _run(_auth.signInWithGoogle),
          ),
        if (_auth.supportsAppleSignIn) ...[
          if (_auth.supportsGoogleSignIn) const SizedBox(height: 12),
          ProviderButton(
            icon: const Icon(Icons.apple, size: 22),
            label: 'Continue with Apple',
            onPressed: _busy ? null : () => _run(_auth.signInWithApple),
          ),
        ],
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                _signUp ? 'Already have an account?' : 'New here?',
                style: TextStyle(color: palette.textSecondary, fontSize: 14),
              ),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _signUp = !_signUp;
                      _error = null;
                    }),
              style: TextButton.styleFrom(foregroundColor: palette.accent),
              child: Text(_signUp ? 'Sign in' : 'Create an account'),
            ),
          ],
        ),
        const LegalLinks(),
      ],
    );

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: wide ? 40 : 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - (wide ? 80 : 48)),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: wide
                        ? Container(
                            padding: const EdgeInsets.fromLTRB(36, 36, 36, 20),
                            decoration: BoxDecoration(
                              color: palette.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: palette.border),
                            ),
                            child: form,
                          )
                        : form,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
