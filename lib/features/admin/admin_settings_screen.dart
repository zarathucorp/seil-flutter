import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/localization/seil_localizations.dart';
import '../../core/settings/app_settings_repository.dart';
import '../../shared/app_state.dart';
import '../../shared/models.dart';

class AdminSettingsScreen extends StatelessWidget {
  const AdminSettingsScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final isAdmin = state.currentUser?.role == UserRole.admin;
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(l10n.account, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.person),
                title: Text(state.currentUser?.name ?? '-'),
                subtitle: Text(state.currentUser?.username ?? '-'),
                trailing: IconButton(
                  onPressed: () => _showChangePassword(context),
                  icon: const Icon(Icons.password),
                  tooltip: l10n.changePassword,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                    child: Text(l10n.userManagement,
                        style: Theme.of(context).textTheme.titleLarge)),
                if (isAdmin)
                  IconButton(
                    onPressed: () => _showCreateUser(context),
                    icon: const Icon(Icons.person_add),
                    tooltip: l10n.addUser,
                  ),
              ],
            ),
            if (!isAdmin)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(l10n.adminOnlyUserManagement),
              )
            else
              for (final user in state.users)
                Card(
                  child: ListTile(
                    leading: Icon(user.role == UserRole.admin
                        ? Icons.admin_panel_settings
                        : Icons.person),
                    title: Text(user.name),
                    subtitle: Text('${user.username} · ${user.role.name}'),
                    trailing: user.protectedAccount
                        ? const Icon(Icons.lock)
                        : IconButton(
                            onPressed: () => state.deleteUser(user),
                            icon: const Icon(Icons.delete),
                            tooltip: l10n.delete,
                          ),
                  ),
                ),
            const SizedBox(height: 20),
            Text(l10n.security, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.key),
                title: Text(l10n.keysAndPasswords),
                subtitle: Text(l10n.secretsStorageDescription),
              ),
            ),
            Card(
              child: SwitchListTile(
                secondary: const Icon(Icons.password),
                title: Text(l10n.appLoginPassword),
                subtitle: Text(l10n.appLoginPasswordDescription),
                value: state.loginPasswordEnabled,
                onChanged: isAdmin && !state.busy
                    ? (value) {
                        if (value) {
                          _showEnableLoginPassword(context);
                        } else {
                          state.setLoginPasswordEnabled(false);
                        }
                      }
                    : null,
              ),
            ),
            Card(
              child: SwitchListTile(
                secondary: const Icon(Icons.speed),
                title: Text(l10n.lowEndMode),
                subtitle: Text(l10n.lowEndModeDescription),
                value: state.lowEndModeEnabled,
                onChanged: state.setLowEndModeEnabled,
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.language),
                title: Text(l10n.language),
                subtitle: Text(l10n.languageLabel(state.appLanguageCode)),
                trailing: PopupMenuButton<String>(
                  tooltip: l10n.chooseLanguage,
                  initialValue: state.appLanguageCode,
                  onSelected: state.setAppLanguageCode,
                  itemBuilder: (context) => [
                    for (final code
                        in AppSettingsRepository.supportedLanguageCodes)
                      PopupMenuItem(
                        value: code,
                        child: Text(l10n.languageLabel(code)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(l10n.info, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/app-logo.png',
                    width: 32,
                    height: 32,
                    cacheWidth: 96,
                    fit: BoxFit.contain,
                  ),
                ),
                title: Text(l10n.aboutSeil),
                subtitle: Text(l10n.developedByZarathu),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showAboutSeil(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateUser(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => _CreateUserDialog(state: state),
    );
  }

  Future<void> _showChangePassword(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => _ChangePasswordDialog(state: state),
    );
  }

  Future<void> _showEnableLoginPassword(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => _EnableLoginPasswordDialog(state: state),
    );
  }

  Future<void> _showAboutSeil(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => const _AboutSeilDialog(),
    );
  }
}

class _AboutSeilDialog extends StatelessWidget {
  const _AboutSeilDialog();

  static const companyUrl = 'https://www.zarathu.com/';
  static const repositoryUrl = 'https://github.com/zarathucorp/seil-flutter';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.aboutSeil),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Image.asset(
                'assets/app-logo.png',
                width: 84,
                height: 84,
                cacheWidth: 192,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Seil',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(l10n.aboutDescription),
            const SizedBox(height: 16),
            _AboutInfoRow(
              label: l10n.developer,
              value: 'Zarathu',
            ),
            _AboutLinkRow(
              label: l10n.company,
              value: companyUrl,
            ),
            _AboutLinkRow(
              label: l10n.openSource,
              value: repositoryUrl,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'Seil',
            applicationIcon: Padding(
              padding: const EdgeInsets.all(8),
              child: Image.asset(
                'assets/app-logo.png',
                width: 48,
                height: 48,
                cacheWidth: 96,
              ),
            ),
          ),
          child: Text(l10n.license),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.ok),
        ),
      ],
    );
  }
}

class _AboutInfoRow extends StatelessWidget {
  const _AboutInfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 2),
          SelectableText(value),
        ],
      ),
    );
  }
}

class _AboutLinkRow extends StatelessWidget {
  const _AboutLinkRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _AboutInfoRow(label: label, value: value),
          ),
          IconButton(
            tooltip: context.l10n.copyLink,
            visualDensity: VisualDensity.compact,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.l10n.copiedLink)),
              );
            },
            icon: const Icon(Icons.copy, size: 18),
          ),
        ],
      ),
    );
  }
}

class _EnableLoginPasswordDialog extends StatefulWidget {
  const _EnableLoginPasswordDialog({required this.state});

  final AppState state;

  @override
  State<_EnableLoginPasswordDialog> createState() =>
      _EnableLoginPasswordDialogState();
}

class _EnableLoginPasswordDialogState
    extends State<_EnableLoginPasswordDialog> {
  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  String? localError;

  @override
  void dispose() {
    password.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.appLoginPassword),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: password,
              decoration: InputDecoration(labelText: l10n.newPassword),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmPassword,
              decoration: InputDecoration(labelText: l10n.confirmNewPassword),
              obscureText: true,
            ),
            if (localError != null) ...[
              const SizedBox(height: 12),
              Text(localError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(
          onPressed: widget.state.busy ? null : _submit,
          child: Text(l10n.enable),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (password.text != confirmPassword.text) {
      setState(() => localError = context.l10n.passwordsDoNotMatch);
      return;
    }
    setState(() => localError = null);
    await widget.state.setLoginPasswordEnabled(
      true,
      newPassword: password.text,
    );
    if (mounted && widget.state.errorMessage == null) {
      Navigator.pop(context);
    }
  }
}

class _CreateUserDialog extends StatefulWidget {
  const _CreateUserDialog({required this.state});

  final AppState state;

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.state});

  final AppState state;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final currentPassword = TextEditingController();
  final nextPassword = TextEditingController();
  final confirmPassword = TextEditingController();
  String? localError;

  @override
  void dispose() {
    currentPassword.dispose();
    nextPassword.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.changePassword),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentPassword,
              decoration: InputDecoration(labelText: l10n.currentPassword),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nextPassword,
              decoration: InputDecoration(labelText: l10n.newPassword),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmPassword,
              decoration: InputDecoration(labelText: l10n.confirmNewPassword),
              obscureText: true,
            ),
            if (localError != null) ...[
              const SizedBox(height: 12),
              Text(localError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(
          onPressed: widget.state.busy ? null : _submit,
          child: Text(l10n.change),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (nextPassword.text != confirmPassword.text) {
      setState(() => localError = context.l10n.passwordsDoNotMatch);
      return;
    }
    setState(() => localError = null);
    await widget.state.changePassword(
      currentPassword: currentPassword.text,
      newPassword: nextPassword.text,
    );
    if (mounted && widget.state.errorMessage == null) {
      Navigator.pop(context);
    }
  }
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final username = TextEditingController();
  final name = TextEditingController();
  final password = TextEditingController();
  UserRole role = UserRole.user;

  @override
  void dispose() {
    username.dispose();
    name.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.addUser),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: username,
                decoration: InputDecoration(labelText: l10n.userId)),
            const SizedBox(height: 12),
            TextField(
                controller: name,
                decoration: InputDecoration(labelText: l10n.name)),
            const SizedBox(height: 12),
            TextField(
                controller: password,
                decoration: InputDecoration(labelText: l10n.password),
                obscureText: true),
            const SizedBox(height: 12),
            SegmentedButton<UserRole>(
              segments: const [
                ButtonSegment(value: UserRole.user, label: Text('User')),
                ButtonSegment(value: UserRole.admin, label: Text('Admin')),
              ],
              selected: {role},
              onSelectionChanged: (value) => setState(() => role = value.first),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(
          onPressed: () async {
            await widget.state.createUser(
              username: username.text,
              name: name.text,
              password: password.text,
              role: role,
            );
            if (context.mounted) {
              Navigator.pop(context);
            }
          },
          child: Text(l10n.add),
        ),
      ],
    );
  }
}
