import 'package:flutter/material.dart';

import '../../core/localization/seil_localizations.dart';
import '../../shared/app_state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.state});

  final AppState state;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final password = TextEditingController();

  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isBootstrap = widget.state.needsBootstrap;
    final passwordEnabled = widget.state.loginPasswordEnabled;
    final l10n = context.l10n;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 20),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE4E4E7)),
                        color: const Color(0xFFFFFFFF),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Seil',
                                style:
                                    Theme.of(context).textTheme.displaySmall),
                            const SizedBox(height: 8),
                            Text(
                              isBootstrap
                                  ? (passwordEnabled
                                      ? l10n.bootstrapWithPasswordDescription
                                      : l10n
                                          .bootstrapWithoutPasswordDescription)
                                  : (passwordEnabled
                                      ? l10n.loginWithPasswordDescription
                                      : l10n.loginWithoutPasswordDescription),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: const Color(0xFF71717A)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    isBootstrap
                                        ? l10n.createAdmin
                                        : l10n.userLogin,
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                  ),
                                ),
                                const _StatusPill(label: 'Secure'),
                              ],
                            ),
                            const SizedBox(height: 14),
                            if (passwordEnabled) ...[
                              TextField(
                                controller: password,
                                decoration: InputDecoration(
                                    prefixIcon: const Icon(Icons.lock),
                                    labelText: l10n.password),
                                obscureText: true,
                                onSubmitted: (_) => _submit(),
                              ),
                            ] else
                              Text(
                                l10n.loginPasswordCanBeEnabled,
                                style:
                                    const TextStyle(color: Color(0xFF71717A)),
                              ),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              onPressed: widget.state.busy ? null : _submit,
                              icon: widget.state.busy
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.login),
                              label: Text(isBootstrap
                                  ? (passwordEnabled
                                      ? l10n.createAdmin
                                      : l10n.start)
                                  : (passwordEnabled ? l10n.login : l10n.open)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!widget.state.loginPasswordEnabled) {
      await widget.state.loginWithoutPassword();
    } else if (widget.state.needsBootstrap) {
      await widget.state.bootstrapAndLogin(
        username: 'admin',
        name: 'Seil Admin',
        password: password.text,
      );
    } else {
      await widget.state.loginWithPassword(password.text);
    }
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F4F5),
        border: Border.all(color: const Color(0xFFE4E4E7)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFF18181B),
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
