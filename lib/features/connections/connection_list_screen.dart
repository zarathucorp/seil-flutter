import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/localization/seil_localizations.dart';
import '../admin/admin_settings_screen.dart';
import '../sessions/ssh_session_service.dart';
import '../../shared/app_state.dart';
import '../../shared/models.dart';

const _foreground = Color(0xFF09090B);
const _mutedForeground = Color(0xFF71717A);
const _success = Color(0xFF16A34A);
const _warning = Color(0xFFF59E0B);

class ConnectionListScreen extends StatelessWidget {
  const ConnectionListScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        if (state.liveSessions.isEmpty) {
          return;
        }
        state.selectSession(state.liveSessions.last);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.servers),
          actions: [
            IconButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => AdminSettingsScreen(state: state)),
              ),
              icon: const Icon(LucideIcons.settings),
              tooltip: l10n.settings,
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(l10n.workspace,
                        style: Theme.of(context).textTheme.headlineSmall),
                  ),
                  ShadButton(
                    onPressed:
                        state.busy ? null : () => _showConnectionSheet(context),
                    leading: const Icon(LucideIcons.plus, size: 16),
                    child: Text(l10n.newConnection),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (state.liveSessions.isNotEmpty) ...[
                _SectionHeader(
                  title: l10n.activeSessions,
                  badge: l10n.activeBadge(state.liveSessions.length),
                ),
                const SizedBox(height: 8),
                for (final session in state.liveSessions)
                  _LiveSessionCard(
                    session: session,
                    number: state.sessionNumber(session),
                    onPressed: () => state.selectSession(session),
                  ),
                const SizedBox(height: 16),
              ],
              _SectionHeader(
                title: l10n.savedServers,
                badge: l10n.savedBadge(state.connections.length),
              ),
              const SizedBox(height: 8),
              for (final connection in state.connections)
                _ServerCard(
                  connection: connection,
                  connecting: state.connectingConnectionId == connection.id,
                  onConnect: state.busy
                      ? null
                      : () => _connectSaved(context, connection),
                  onAction: (action) =>
                      _handleConnectionAction(context, connection, action),
                ),
              if (state.connections.isEmpty)
                ShadCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      l10n.noSavedConnections,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleConnectionAction(
    BuildContext context,
    SavedConnection connection,
    _ConnectionAction action,
  ) async {
    if (action == _ConnectionAction.connect) {
      await _connectSaved(context, connection);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.deleteTemplate),
        content:
            Text(context.l10n.deleteTemplateMessage(connection.displayName)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.delete)),
        ],
      ),
    );
    if (confirmed == true) {
      await state.deleteConnection(connection);
    }
  }

  Future<void> _connectSaved(
      BuildContext context, SavedConnection connection) async {
    String? secret;
    if (!connection.hasStoredSecret) {
      secret = await _askSecret(context, connection.authMode);
      if (secret == null || secret.isEmpty) {
        return;
      }
    }
    await state.connectSaved(connection, transientSecret: secret);
  }

  Future<String?> _askSecret(BuildContext context, AuthMode authMode) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(authMode == AuthMode.password
            ? context.l10n.sshPassword
            : 'Private Key'),
        content: TextField(
          controller: controller,
          minLines: authMode == AuthMode.privateKey ? 6 : 1,
          maxLines: authMode == AuthMode.privateKey ? 10 : 1,
          obscureText: authMode == AuthMode.password,
          decoration: InputDecoration(labelText: context.l10n.secret),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: Text(context.l10n.connect)),
        ],
      ),
    );
  }

  Future<void> _showConnectionSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF8FAFC),
      barrierColor: const Color(0x660F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (context) => _ConnectionForm(state: state),
    );
  }
}

enum _ConnectionAction { connect, delete }

class _LiveSessionCard extends StatelessWidget {
  const _LiveSessionCard({
    required this.session,
    required this.number,
    required this.onPressed,
  });

  final LiveSshSession session;
  final int number;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ShadCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: _foreground,
                child: Text(
                  '$number',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Positioned(
                right: -1,
                bottom: -1,
                child: _StatusLamp(
                  color: session.tmuxAvailable ? _success : _warning,
                ),
              ),
            ],
          ),
          title: Text(session.displayName),
          subtitle: Text(
            '${session.username}@${session.hostName} · ${_compactPathName(session.currentPath)}',
          ),
          trailing: const Icon(LucideIcons.chevronRight, size: 16),
          onTap: onPressed,
        ),
      ),
    );
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.connection,
    required this.connecting,
    required this.onConnect,
    required this.onAction,
  });

  final SavedConnection connection;
  final bool connecting;
  final VoidCallback? onConnect;
  final ValueChanged<_ConnectionAction> onAction;

  @override
  Widget build(BuildContext context) {
    final needsSecret = !connection.hasStoredSecret;
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ShadCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                connection.authMode == AuthMode.privateKey
                    ? LucideIcons.keyRound
                    : LucideIcons.lockKeyhole,
              ),
              Positioned(
                right: -3,
                bottom: -2,
                child: _StatusLamp(color: needsSecret ? _warning : _success),
              ),
            ],
          ),
          title: Text(connection.displayName),
          subtitle: Text(
            '${connection.username}@${connection.host}:${connection.port} · history ${connection.tmuxHistoryLimit} · ${l10n.authModeLabel(connection.authMode)} · ${connecting ? l10n.connecting : needsSecret ? l10n.secretRequired : l10n.quickConnect}',
          ),
          trailing: connecting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : PopupMenuButton<_ConnectionAction>(
                  tooltip: l10n.serverActions,
                  onSelected: onAction,
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _ConnectionAction.connect,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(LucideIcons.terminal),
                        title: Text(l10n.connect),
                      ),
                    ),
                    PopupMenuItem(
                      value: _ConnectionAction.delete,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(LucideIcons.trash2),
                        title: Text(l10n.delete),
                      ),
                    ),
                  ],
                ),
          onTap: onConnect,
        ),
      ),
    );
  }
}

class _ConnectionForm extends StatefulWidget {
  const _ConnectionForm({required this.state});

  final AppState state;

  @override
  State<_ConnectionForm> createState() => _ConnectionFormState();
}

class _ConnectionFormState extends State<_ConnectionForm> {
  final label = TextEditingController();
  final host = TextEditingController();
  final port = TextEditingController(text: '22');
  final username = TextEditingController();
  final tmuxHistoryLimit =
      TextEditingController(text: defaultTmuxHistoryLimit.toString());
  final secret = TextEditingController();
  AuthMode authMode = AuthMode.password;
  int initialPaneIndex = 0;
  bool saveSecret = false;
  bool submitting = false;
  String? formError;

  @override
  void dispose() {
    label.dispose();
    host.dispose();
    port.dispose();
    username.dispose();
    tmuxHistoryLimit.dispose();
    secret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final media = MediaQuery.of(context);
    final systemBottom =
        media.viewInsets.bottom == 0 ? media.viewPadding.bottom : 0.0;
    final bottomPadding = 16 + media.viewInsets.bottom + systemBottom;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: bottomPadding,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(l10n.newSshConnection,
                        style: Theme.of(context).textTheme.titleLarge)),
                _StatusPill(label: 'SFTP + Terminal'),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: label,
              enabled: !submitting,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                prefixIcon: const Icon(LucideIcons.tag),
                labelText: l10n.label,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: host,
              enabled: !submitting,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              onChanged: (_) => _clearFormError(),
              decoration: const InputDecoration(
                prefixIcon: Icon(LucideIcons.server),
                labelText: 'Host',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: port,
              enabled: !submitting,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              onChanged: (_) => _clearFormError(),
              decoration: const InputDecoration(
                prefixIcon: Icon(LucideIcons.hash),
                labelText: 'Port',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: username,
              enabled: !submitting,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              onChanged: (_) => _clearFormError(),
              decoration: const InputDecoration(
                prefixIcon: Icon(LucideIcons.user),
                labelText: 'Username',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: tmuxHistoryLimit,
                    enabled: !submitting,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => _clearFormError(),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(LucideIcons.history),
                      labelText: 'tmux history-limit',
                      helperText: l10n.tmuxDefaultHistoryHelper,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: EdgeInsets.only(top: 17),
                  child: Text(
                    l10n.recommendedLines(recommendedTmuxHistoryLimit),
                    style: TextStyle(
                      color: _mutedForeground,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<AuthMode>(
              segments: const [
                ButtonSegment(
                    value: AuthMode.password, label: Text('Password')),
                ButtonSegment(
                    value: AuthMode.privateKey, label: Text('Private Key')),
              ],
              selected: {authMode},
              onSelectionChanged: submitting
                  ? null
                  : (value) => setState(() {
                        authMode = value.first;
                        formError = null;
                      }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: secret,
              enabled: !submitting,
              minLines: authMode == AuthMode.privateKey ? 6 : 1,
              maxLines: authMode == AuthMode.privateKey ? 10 : 1,
              obscureText: authMode == AuthMode.password,
              textInputAction: authMode == AuthMode.password
                  ? TextInputAction.done
                  : TextInputAction.newline,
              decoration: InputDecoration(
                  labelText: authMode == AuthMode.password
                      ? l10n.sshPassword
                      : l10n.privateKeyRaw),
              onSubmitted:
                  authMode == AuthMode.password ? (_) => _submit() : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: saveSecret,
              onChanged: submitting
                  ? null
                  : (value) => setState(() => saveSecret = value),
              title: Text(l10n.saveSecretOnDevice),
            ),
            SegmentedButton<int>(
              segments: [
                ButtonSegment(
                  value: 0,
                  icon: const Icon(LucideIcons.terminal, size: 16),
                  label: Text(l10n.terminal),
                ),
                ButtonSegment(
                  value: 1,
                  icon: const Icon(LucideIcons.folder, size: 16),
                  label: Text(l10n.explorer),
                ),
              ],
              selected: {initialPaneIndex},
              onSelectionChanged: submitting
                  ? null
                  : (value) => setState(() => initialPaneIndex = value.first),
            ),
            if (formError != null) ...[
              const SizedBox(height: 12),
              _InlineFormError(message: formError!),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: submitting || widget.state.busy ? null : _submit,
              icon: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.terminal),
              label: Text(submitting ? l10n.connecting : l10n.saveAndConnect),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (submitting) {
      return;
    }
    final validated = _validateInput();
    if (validated == null) {
      return;
    }
    final previousActiveSessionId = widget.state.activeSession?.id;
    setState(() {
      formError = null;
      submitting = true;
    });
    await widget.state.connectNew(
      SshConnectionInput(
        label: validated.label,
        host: validated.host,
        port: validated.port,
        username: validated.username,
        authMode: authMode,
        tmuxHistoryLimit: validated.tmuxHistoryLimit,
        secret: secret.text,
        saveSecret: saveSecret,
      ),
      initialPaneIndex: initialPaneIndex,
    );
    if (!mounted) {
      return;
    }
    setState(() => submitting = false);
    final nextActiveSession = widget.state.activeSession;
    if (nextActiveSession != null &&
        nextActiveSession.id != previousActiveSessionId) {
      Navigator.pop(context);
    }
  }

  _ValidatedConnectionInput? _validateInput() {
    final trimmedHost = host.text.trim();
    final trimmedUsername = username.text.trim();
    final parsedPort = int.tryParse(port.text.trim());
    final parsedHistoryLimit = int.tryParse(tmuxHistoryLimit.text.trim());
    String? message;
    if (trimmedHost.isEmpty) {
      message = context.l10n.hostRequired;
    } else if (trimmedUsername.isEmpty) {
      message = context.l10n.usernameRequired;
    } else if (parsedPort == null || parsedPort < 1 || parsedPort > 65535) {
      message = context.l10n.portInvalid;
    } else if (parsedHistoryLimit == null || parsedHistoryLimit < 1) {
      message = context.l10n.tmuxHistoryInvalid;
    }
    if (message != null) {
      setState(() => formError = message);
      return null;
    }
    final validPort = parsedPort;
    final validHistoryLimit = parsedHistoryLimit;
    if (validPort == null || validHistoryLimit == null) {
      return null;
    }
    return _ValidatedConnectionInput(
      label: label.text.trim(),
      host: trimmedHost,
      port: validPort,
      username: trimmedUsername,
      tmuxHistoryLimit: validHistoryLimit,
    );
  }

  void _clearFormError() {
    if (formError == null || !mounted) {
      return;
    }
    setState(() => formError = null);
  }
}

class _ValidatedConnectionInput {
  const _ValidatedConnectionInput({
    required this.label,
    required this.host,
    required this.port,
    required this.username,
    required this.tmuxHistoryLimit,
  });

  final String label;
  final String host;
  final int port;
  final String username;
  final int tmuxHistoryLimit;
}

class _InlineFormError extends StatelessWidget {
  const _InlineFormError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: errorColor.withValues(alpha: .08),
        border: Border.all(color: errorColor.withValues(alpha: .35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.circleAlert, size: 16, color: errorColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: errorColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.badge});

  final String title;
  final String badge;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        _StatusPill(label: badge, subtle: true),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, this.subtle = false});

  final String label;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: subtle ? const Color(0xFFF4F4F5) : const Color(0xFF18181B),
        border: Border.all(color: const Color(0xFFE4E4E7)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: subtle ? const Color(0xFF71717A) : const Color(0xFFFAFAFA),
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _StatusLamp extends StatelessWidget {
  const _StatusLamp({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: Colors.white, width: 1.5),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.25),
            blurRadius: 6,
          ),
        ],
      ),
    );
  }
}

String _compactPathName(String path) {
  final normalized = p.posix.normalize(path.trim().isEmpty ? '/' : path.trim());
  if (normalized == '/') {
    return '/';
  }
  final base = p.posix.basename(normalized);
  final parent = p.posix.dirname(normalized);
  return parent == '/' || parent == '.' ? '/$base' : '../$base';
}
