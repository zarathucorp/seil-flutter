import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/localization/seil_error_codes.dart';
import '../../core/localization/seil_localizations.dart';
import '../../core/platform/external_file_opener.dart';
import '../../shared/app_state.dart';
import '../../shared/models.dart';
import 'ssh_session_service.dart';

const _border = Color(0xFFE4E4E7);
const _mutedForeground = Color(0xFF71717A);
const _success = Color(0xFF16A34A);
const _warning = Color(0xFFF59E0B);
const _terminalBackground = Color(0xFF1F2430);
const _warpInk = Color(0xFF0F172A);
const _glassFill = Color(0xE8F8FAFC);
const _glassStroke = Color(0xB8FFFFFF);
const _sheetFill = Color(0xF4F8FAFC);
const _terminalSelection = Color(0x666BA6FF);
const _terminalSelectionHandle = Color(0xFF73D0FF);
const _terminalFontFamily = 'FiraCodeNerdFontMono';
const _terminalFontSize = 6.0;
const _terminalMinFontSize = 4.0;
const _terminalMaxFontSize = 14.0;
const _terminalForeground = Color(0xFFE5E7EB);
const _terminalMutedForeground = Color(0xFFA1A1AA);
const _terminalBottomPaddingLines = '\n\n\n\n';
const _terminalAutoScrollBottomTolerance = 24.0;

class _WorkspacePerformance extends InheritedWidget {
  const _WorkspacePerformance({
    required this.lowEndMode,
    required super.child,
  });

  final bool lowEndMode;

  static bool lowEndModeOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_WorkspacePerformance>()
            ?.lowEndMode ??
        false;
  }

  @override
  bool updateShouldNotify(_WorkspacePerformance oldWidget) {
    return lowEndMode != oldWidget.lowEndMode;
  }
}

class WorkspaceScreen extends StatelessWidget {
  const WorkspaceScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final session = state.activeSession;

    return _WorkspacePerformance(
      lowEndMode: state.lowEndModeEnabled,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) {
            return;
          }
          if (state.activePaneIndex == 1 && state.canGoBackDirectory) {
            unawaited(state.goBackDirectory());
            return;
          }
          if (state.activePaneIndex != 0) {
            state.selectActivePane(0);
            return;
          }
          unawaited(state.detachActiveSession());
        },
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          body: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF8FAFC),
                  Color(0xFFEFF6FF),
                  Color(0xFFF7F2FF),
                ],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _WorkspaceCommandBar(state: state),
                  Expanded(
                    child: session != null &&
                            session.tmuxAvailable &&
                            !session.tmuxSelectionReady
                        ? _TmuxSessionChooser(state: state)
                        : IndexedStack(
                            index: state.activePaneIndex,
                            children: [
                              TerminalPane(
                                state: state,
                                active: state.activePaneIndex == 0,
                              ),
                              FileExplorerPane(state: state),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceCommandBar extends StatelessWidget {
  const _WorkspaceCommandBar({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final active = state.activeSession;
    if (active == null) {
      return const SizedBox.shrink();
    }

    final tmuxLabel = active.tmuxAvailable
        ? _compactPathDisplay(active.currentPath)
        : _compactPathDisplay(active.currentPath);
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
          decoration: const BoxDecoration(
            color: _glassFill,
            border: Border(bottom: BorderSide(color: _glassStroke)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  SizedBox(
                    width:
                        math.min(108, MediaQuery.sizeOf(context).width * .26),
                    child: _HeaderSelectButton(
                      icon: LucideIcons.server,
                      title: active.displayName,
                      statusColor: active.tmuxAvailable ? _success : _warning,
                      onPressed: () => _showServerSheet(context),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _HeaderSelectButton(
                      icon: LucideIcons.squareTerminal,
                      title: tmuxLabel,
                      statusColor: active.tmuxAvailable ? _success : _warning,
                      onPressed: active.tmuxAvailable
                          ? () => _showTmuxSheet(context)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 4),
                  _ToolbarButton(
                    icon: LucideIcons.refreshCw,
                    tooltip: context.l10n.refreshSession,
                    onPressed:
                        state.busy ? null : () => _refreshActiveWorkspace(),
                  ),
                  _ToolbarButton(
                    icon: LucideIcons.x,
                    tooltip: context.l10n.disconnectCurrentConnection,
                    onPressed: state.disconnect,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: _PaneSwitch(state: state)),
                ],
              ),
              const SizedBox(height: 6),
              _SessionNumberBar(state: state),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refreshActiveWorkspace() async {
    await state.pingLiveSessions();
    await state.reconnectClosedSessions(force: true);
    final directory = state.activeDirectory;
    final futures = <Future<void>>[];
    if (directory != null) {
      futures.add(state.loadDirectory(directory.currentPath, force: true));
    }
    futures.add(state.refreshActiveTmuxSessions());
    await Future.wait(futures);
  }

  Future<void> _showServerSheet(BuildContext context) {
    final rootContext = context;
    String? connectingConnectionId;
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: _sheetFill,
      barrierColor: const Color(0x660F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                shrinkWrap: true,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.l10n.serverSessionSelection,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      _ToolbarButton(
                        icon: LucideIcons.plus,
                        tooltip: context.l10n.addSessionFromSavedServer,
                        onPressed: state.busy || connectingConnectionId != null
                            ? null
                            : () {
                                Navigator.pop(context);
                                _showConnectionTemplateSheet(rootContext);
                              },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.connectedServers,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  for (final session in _uniqueLiveServerSessions(
                    state.liveSessions,
                    state.activeSession,
                  ))
                    ListTile(
                      leading: _StatusLamp(
                        color: session.tmuxAvailable ? _success : _warning,
                      ),
                      title: Text(
                        session.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${session.username}@${session.hostName}:${session.connection.port} · ${context.l10n.workspaceCount(_workspaceCountForClient(state.liveSessions, session))}',
                      ),
                      trailing: state.activeSession?.client == session.client
                          ? const Icon(LucideIcons.check, size: 16)
                          : const Icon(LucideIcons.chevronRight, size: 16),
                      onTap: () {
                        Navigator.pop(context);
                        _showServerWorkspaceSheet(rootContext, session);
                      },
                    ),
                  if (state.liveSessions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(context.l10n.noConnectedServers),
                    ),
                  const Divider(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.l10n.savedServers,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      if (connectingConnectionId != null)
                        Text(
                          context.l10n.connecting,
                          style: const TextStyle(
                            color: _mutedForeground,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  for (final connection in state.connections)
                    ListTile(
                      enabled: connectingConnectionId == null,
                      leading: const Icon(LucideIcons.server, size: 18),
                      title: Text(connection.displayName),
                      subtitle: Text(
                        '${connection.username}@${connection.host}:${connection.port}',
                      ),
                      trailing: connectingConnectionId == connection.id
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : _liveSessionsForConnection(
                              state.liveSessions,
                              connection,
                            ).isNotEmpty
                              ? const Icon(LucideIcons.list, size: 16)
                              : const Icon(LucideIcons.plus, size: 16),
                      onTap: connectingConnectionId != null
                          ? null
                          : () async {
                              setSheetState(() {
                                connectingConnectionId = connection.id;
                              });
                              await _showConnectingFrame();
                              if (!context.mounted || !rootContext.mounted) {
                                return;
                              }
                              final existingSessions =
                                  _liveSessionsForConnection(
                                state.liveSessions,
                                connection,
                              );
                              if (existingSessions.isNotEmpty) {
                                Navigator.pop(context);
                                await _showServerWorkspaceSheet(
                                  rootContext,
                                  existingSessions.first,
                                );
                                return;
                              }
                              final session = await _prepareConnectionTemplate(
                                context,
                                connection,
                              );
                              if (!context.mounted || !rootContext.mounted) {
                                return;
                              }
                              if (session != null) {
                                Navigator.pop(context);
                              } else {
                                setSheetState(() {
                                  connectingConnectionId = null;
                                });
                              }
                            },
                    ),
                  if (state.connections.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(context.l10n.noSavedServers),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showServerWorkspaceSheet(
    BuildContext context,
    LiveSshSession serverSession,
  ) {
    final rootContext = context;
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: _sheetFill,
      barrierColor: const Color(0x660F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (context) {
        return AnimatedBuilder(
          animation: state,
          builder: (context, _) {
            final sessions = _liveSessionsForClient(
              state.liveSessions,
              serverSession,
            );
            final source = sessions.isEmpty ? null : sessions.first;
            return SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                shrinkWrap: true,
                children: [
                  Text(
                    serverSession.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${serverSession.username}@${serverSession.hostName}:${serverSession.connection.port}',
                    style: const TextStyle(
                      color: _mutedForeground,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.l10n.openSessions,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  for (final session in sessions)
                    ListTile(
                      leading: _StatusLamp(
                        color: session.tmuxAvailable ? _success : _warning,
                      ),
                      title: Text(
                        _workspaceSessionTitle(state, session),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        _workspaceSessionSubtitle(
                          context.l10n,
                          state,
                          session,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: state.activeSession?.id == session.id
                          ? const Icon(LucideIcons.check, size: 16)
                          : const Icon(LucideIcons.chevronRight, size: 16),
                      onTap: () {
                        state.selectSession(session);
                        Navigator.pop(context);
                      },
                    ),
                  if (sessions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(context.l10n.noOpenSessions),
                    ),
                  const Divider(height: 20),
                  ListTile(
                    enabled: !state.busy && source != null,
                    leading: const Icon(LucideIcons.plus, size: 18),
                    title: Text(context.l10n.addNewTmuxSession),
                    subtitle: Text(context.l10n.addNewTmuxSessionDescription),
                    onTap: source == null
                        ? null
                        : () async {
                            final selectedSource = source;
                            state.selectSession(selectedSource);
                            Navigator.pop(context);
                            await state.createTerminalSessionFromActive(
                              initialPaneIndex: 0,
                              selectNewTmux: true,
                            );
                          },
                  ),
                  ListTile(
                    enabled: source?.tmuxAvailable == true,
                    leading: const Icon(LucideIcons.squareTerminal, size: 18),
                    title: Text(context.l10n.chooseTmuxSession),
                    subtitle: Text(context.l10n.chooseTmuxSessionDescription),
                    onTap: source?.tmuxAvailable != true
                        ? null
                        : () async {
                            final selectedSource = source;
                            if (selectedSource == null) {
                              return;
                            }
                            state.selectSession(selectedSource);
                            Navigator.pop(context);
                            await _showConnectingFrame();
                            if (rootContext.mounted) {
                              await _showTmuxSheet(rootContext);
                            }
                          },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showTmuxSheet(BuildContext context) {
    final session = state.activeSession;
    if (session == null || !session.tmuxAvailable) {
      return Future.value();
    }
    unawaited(state.refreshActiveTmuxSessions());

    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: _sheetFill,
      barrierColor: const Color(0x660F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (context) {
        return AnimatedBuilder(
          animation: state,
          builder: (context, _) {
            final activeSession = state.activeSession ?? session;
            return SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                shrinkWrap: true,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.l10n.tmuxSessions,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      _ToolbarButton(
                        icon: LucideIcons.refreshCw,
                        tooltip: context.l10n.refresh,
                        onPressed: state.busy
                            ? null
                            : () async {
                                await state.refreshActiveTmuxSessions();
                              },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (activeSession.tmuxSessions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        context.l10n.noTmuxSessionsOrLoading,
                        style: const TextStyle(
                          color: _mutedForeground,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  for (final tmuxSession in activeSession.tmuxSessions)
                    ListTile(
                      leading: const _StatusLamp(color: _success),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _compactPathDisplay(
                                tmuxSession.currentPath ??
                                    activeSession.currentPath,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          _TmuxTagBadge(
                            tag: state.tmuxSessionTag(
                              activeSession,
                              tmuxSession.name,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        _formatTmuxActivity(tmuxSession),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _mutedForeground,
                          fontSize: 11,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: context.l10n.tagSettings,
                            icon: const Icon(LucideIcons.hash, size: 15),
                            onPressed: () => _showTmuxTagDialog(
                              context,
                              state,
                              activeSession,
                              tmuxSession.name,
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: context.l10n.endSession,
                            icon: const Icon(LucideIcons.trash2, size: 15),
                            style: IconButton.styleFrom(
                              minimumSize: const Size(44, 36),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: state.busy
                                ? null
                                : () => unawaited(
                                      state.deleteTmuxSession(
                                        activeSession,
                                        tmuxSession.name,
                                      ),
                                    ),
                          ),
                        ],
                      ),
                      onTap: () {
                        state.selectTmuxSession(tmuxSession);
                        Navigator.pop(context);
                      },
                    ),
                  ListTile(
                    enabled: !state.busy,
                    leading: const Icon(LucideIcons.plus, size: 18),
                    title: Text(context.l10n.startTmuxDefaultPath),
                    onTap: state.busy
                        ? null
                        : () async {
                            await state.selectNewTmuxSession();
                            if (!context.mounted) {
                              return;
                            }
                            Navigator.pop(context);
                          },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showConnectionTemplateSheet(BuildContext context) {
    final rootContext = context;
    String? connectingConnectionId;
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: _sheetFill,
      barrierColor: const Color(0x660F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                shrinkWrap: true,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.l10n.connectionTemplates,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (connectingConnectionId != null)
                        Text(
                          context.l10n.connecting,
                          style: const TextStyle(
                            color: _mutedForeground,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final connection in state.connections)
                    ListTile(
                      enabled: connectingConnectionId == null,
                      leading: const Icon(LucideIcons.server, size: 18),
                      title: Text(connection.displayName),
                      subtitle: Text(
                        '${connection.username}@${connection.host}:${connection.port}',
                      ),
                      trailing: connectingConnectionId == connection.id
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(LucideIcons.chevronRight, size: 16),
                      onTap: connectingConnectionId != null
                          ? null
                          : () async {
                              setSheetState(() {
                                connectingConnectionId = connection.id;
                              });
                              await _showConnectingFrame();
                              if (!context.mounted || !rootContext.mounted) {
                                return;
                              }
                              final existingSessions =
                                  _liveSessionsForConnection(
                                state.liveSessions,
                                connection,
                              );
                              if (existingSessions.isNotEmpty) {
                                state.selectSession(existingSessions.first);
                                await state.createTerminalSessionFromActive(
                                  initialPaneIndex: 0,
                                  selectNewTmux: true,
                                );
                                if (!context.mounted || !rootContext.mounted) {
                                  return;
                                }
                                Navigator.pop(context);
                                return;
                              }
                              final session = await _prepareConnectionTemplate(
                                rootContext,
                                connection,
                              );
                              if (!context.mounted || !rootContext.mounted) {
                                return;
                              }
                              if (session != null) {
                                Navigator.pop(context);
                              } else {
                                setSheetState(() {
                                  connectingConnectionId = null;
                                });
                              }
                            },
                    ),
                  if (state.connections.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(context.l10n.noSavedConnections),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showConnectingFrame() {
    return Future<void>.delayed(const Duration(milliseconds: 80));
  }

  Future<LiveSshSession?> _prepareConnectionTemplate(
    BuildContext context,
    SavedConnection connection,
  ) async {
    String? secret;
    if (!connection.hasStoredSecret) {
      secret = await _askSecret(context, connection.authMode);
      if (secret == null || secret.isEmpty) {
        return null;
      }
    }
    await state.connectSaved(
      connection,
      transientSecret: secret,
      reuseExisting: true,
    );
    if (state.errorMessage != null || state.activeSession == null) {
      return null;
    }
    return state.activeSession;
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
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(context.l10n.connect),
          ),
        ],
      ),
    );
  }
}

class _HeaderSelectButton extends StatefulWidget {
  const _HeaderSelectButton({
    required this.icon,
    required this.title,
    required this.statusColor,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final Color statusColor;
  final VoidCallback? onPressed;

  @override
  State<_HeaderSelectButton> createState() => _HeaderSelectButtonState();
}

class _HeaderSelectButtonState extends State<_HeaderSelectButton> {
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null;
    final activePress = pressed && !disabled;
    final contentColor = disabled ? _mutedForeground : _warpInk;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: disabled ? null : widget.onPressed,
      onTapDown: disabled ? null : (_) => _setPressed(true),
      onTapUp: disabled ? null : (_) => _setPressed(false),
      onTapCancel: disabled ? null : () => _setPressed(false),
      child: AnimatedScale(
        scale: activePress ? 0.975 : 1,
        duration: const Duration(milliseconds: 70),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 70),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, activePress ? 1 : 0, 0),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: disabled ? const Color(0x66FFFFFF) : const Color(0xBFFFFFFF),
            border: Border.all(
              color: activePress
                  ? const Color(0xFFFFFFFF)
                  : const Color(0xE5FFFFFF),
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: activePress
                    ? const Color(0x080F172A)
                    : const Color(0x140F172A),
                blurRadius: activePress ? 4 : 14,
                offset: Offset(0, activePress ? 1 : 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(widget.icon, size: 18, color: contentColor),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: _StatusLamp(color: widget.statusColor, size: 8),
                  ),
                ],
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: contentColor,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(LucideIcons.chevronDown, size: 14, color: contentColor),
            ],
          ),
        ),
      ),
    );
  }

  void _setPressed(bool value) {
    if (pressed == value || !mounted) {
      return;
    }
    setState(() => pressed = value);
  }
}

class _SessionNumberBar extends StatefulWidget {
  const _SessionNumberBar({required this.state});

  final AppState state;

  @override
  State<_SessionNumberBar> createState() => _SessionNumberBarState();
}

class _SessionNumberBarState extends State<_SessionNumberBar> {
  String? activeServerKey;
  Timer? refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshTmuxList());
    refreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refreshTmuxList(),
    );
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _SessionNumberBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextKey = _serverKey(widget.state.activeSession);
    if (nextKey != activeServerKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshTmuxList());
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.state.activeSession;
    if (active == null || !active.tmuxAvailable) {
      return const SizedBox.shrink();
    }
    activeServerKey = _serverKey(active);
    final sessions = _visibleTmuxSessions(active);
    if (sessions.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: sessions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 5),
        itemBuilder: (context, index) {
          final session = sessions[index];
          return _SessionNumberButton(
            label: '${index + 1}',
            selected: session.name == active.selectedTmuxSessionName,
            attentionState: session.attentionState,
            onPressed: () async {
              widget.state.acknowledgeCompletedTmuxSession(session);
              await widget.state.selectTmuxSession(session);
            },
          );
        },
      ),
    );
  }

  void _refreshTmuxList() {
    if (!mounted) {
      return;
    }
    final active = widget.state.activeSession;
    activeServerKey = _serverKey(active);
    if (active?.tmuxAvailable == true) {
      unawaited(widget.state.refreshActiveTmuxSessions(silent: true));
    }
  }

  String? _serverKey(LiveSshSession? session) {
    if (session == null) {
      return null;
    }
    return session.connection.fingerprint;
  }

  List<RemoteTmuxSession> _visibleTmuxSessions(LiveSshSession active) {
    final sessions = List<RemoteTmuxSession>.from(active.tmuxSessions);
    final selectedName = active.selectedTmuxSessionName?.trim();
    if (selectedName != null &&
        selectedName.isNotEmpty &&
        !sessions.any((session) => session.name == selectedName)) {
      sessions.add(
        RemoteTmuxSession(
          name: selectedName,
          windows: 1,
          attachedClients: 0,
          createdAt: null,
          lastActivityAt: null,
          currentPath: active.currentPath,
          attentionState: TerminalAttentionState.none,
        ),
      );
    }
    return sessions;
  }
}

class _SessionNumberButton extends StatefulWidget {
  const _SessionNumberButton({
    required this.label,
    required this.selected,
    required this.attentionState,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final TerminalAttentionState attentionState;
  final VoidCallback onPressed;

  @override
  State<_SessionNumberButton> createState() => _SessionNumberButtonState();
}

class _SessionNumberButtonState extends State<_SessionNumberButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController attentionController;
  bool pressed = false;

  @override
  void initState() {
    super.initState();
    attentionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _syncAttentionAnimation();
  }

  @override
  void didUpdateWidget(covariant _SessionNumberButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attentionState != widget.attentionState) {
      _syncAttentionAnimation();
    }
  }

  @override
  void dispose() {
    attentionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activePress = pressed && !widget.selected;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onPressed,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: activePress ? 0.96 : 1,
        duration: const Duration(milliseconds: 70),
        curve: Curves.easeOut,
        child: AnimatedBuilder(
          animation: attentionController,
          builder: (context, child) {
            final style = _attentionStyle();
            return AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              width: 32,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: style.fill,
                border: Border.all(color: style.border),
                borderRadius: BorderRadius.circular(7),
                boxShadow: style.shadow == null
                    ? null
                    : [
                        BoxShadow(
                          color: style.shadow!,
                          blurRadius: 8,
                          spreadRadius: 0.5,
                        ),
                      ],
              ),
              child: Text(
                widget.label,
                maxLines: 1,
                style: TextStyle(
                  color: style.foreground,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  _SessionNumberAttentionStyle _attentionStyle() {
    if (widget.attentionState == TerminalAttentionState.completed) {
      return const _SessionNumberAttentionStyle(
        fill: Color(0xFF2563EB),
        border: Color(0xFF1D4ED8),
        foreground: Colors.white,
        shadow: Color(0x552563EB),
      );
    }

    if (widget.attentionState == TerminalAttentionState.actionRequired) {
      return const _SessionNumberAttentionStyle(
        fill: Color(0xFFF59E0B),
        border: Color(0xFFD97706),
        foreground: _warpInk,
        shadow: Color(0x44F59E0B),
      );
    }

    if (widget.attentionState == TerminalAttentionState.running) {
      final pulse = 0.38 + attentionController.value * 0.46;
      final fill = Color.lerp(
            const Color(0xBFFFFFFF),
            const Color(0xFFF59E0B),
            pulse,
          ) ??
          const Color(0xFFF59E0B);
      return _SessionNumberAttentionStyle(
        fill: fill,
        border: const Color(0xFFD97706),
        foreground: _warpInk,
        shadow: Color.lerp(
          const Color(0x00F59E0B),
          const Color(0x66F59E0B),
          pulse,
        ),
      );
    }

    return _SessionNumberAttentionStyle(
      fill: widget.selected ? _warpInk : const Color(0xBFFFFFFF),
      border: widget.selected ? const Color(0x330F172A) : _glassStroke,
      foreground: widget.selected ? Colors.white : _warpInk,
    );
  }

  void _syncAttentionAnimation() {
    if (widget.attentionState == TerminalAttentionState.running) {
      attentionController.repeat(reverse: true);
    } else {
      attentionController
        ..stop()
        ..value = 0;
    }
  }

  void _setPressed(bool value) {
    if (pressed == value || !mounted) {
      return;
    }
    setState(() => pressed = value);
  }
}

class _SessionNumberAttentionStyle {
  const _SessionNumberAttentionStyle({
    required this.fill,
    required this.border,
    required this.foreground,
    this.shadow,
  });

  final Color fill;
  final Color border;
  final Color foreground;
  final Color? shadow;
}

class _PaneSwitch extends StatelessWidget {
  const _PaneSwitch({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final selected = state.activePaneIndex;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        height: 30,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: const Color(0x99FFFFFF),
          border: Border.all(color: const Color(0xCCFFFFFF)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SwitchItem(
              icon: LucideIcons.terminal,
              label: context.l10n.terminal,
              selected: selected == 0,
              onPressed: () => state.selectActivePane(0),
            ),
            _SwitchItem(
              icon: LucideIcons.folder,
              label: context.l10n.explorer,
              selected: selected == 1,
              onPressed: () => state.selectActivePane(1),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchItem extends StatefulWidget {
  const _SwitchItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_SwitchItem> createState() => _SwitchItemState();
}

class _SwitchItemState extends State<_SwitchItem> {
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    final activePress = pressed && !widget.selected;
    final selected = widget.selected;
    final foreground = selected ? Colors.white : _warpInk;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onPressed,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: activePress ? 0.97 : 1,
        duration: const Duration(milliseconds: 70),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 70),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, activePress ? 1 : 0, 0),
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected
                ? _warpInk
                : activePress
                    ? const Color(0xE6FFFFFF)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: selected || activePress
                ? [
                    BoxShadow(
                      color: activePress
                          ? const Color(0x100F172A)
                          : const Color(0x220F172A),
                      blurRadius: activePress ? 4 : 10,
                      offset: Offset(0, activePress ? 1 : 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 13, color: foreground),
              const SizedBox(width: 5),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setPressed(bool value) {
    if (pressed == value || !mounted) {
      return;
    }
    setState(() => pressed = value);
  }
}

class _TmuxSessionChooser extends StatefulWidget {
  const _TmuxSessionChooser({required this.state});

  final AppState state;

  @override
  State<_TmuxSessionChooser> createState() => _TmuxSessionChooserState();
}

class _TmuxSessionChooserState extends State<_TmuxSessionChooser> {
  Timer? refreshTimer;
  bool refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _refreshSilently(visible: true));
    refreshTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _refreshSilently(),
    );
  }

  @override
  void didUpdateWidget(covariant _TmuxSessionChooser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _refreshSilently();
    }
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    super.dispose();
  }

  void _refreshSilently({bool visible = false}) {
    if (!mounted || refreshing) {
      return;
    }
    if (visible) {
      setState(() => refreshing = true);
    } else {
      refreshing = true;
    }
    unawaited(
      widget.state.refreshActiveTmuxSessions(silent: true).whenComplete(() {
        if (!mounted) {
          refreshing = false;
          return;
        }
        if (visible) {
          setState(() => refreshing = false);
        } else {
          refreshing = false;
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final session = state.activeSession;
    final tmuxSessions = session?.tmuxSessions ?? const <RemoteTmuxSession>[];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ShadCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.list, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tmuxSessions.isEmpty
                          ? context.l10n.noExistingSessions
                          : context.l10n.existingTmuxSessions,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  ShadButton.ghost(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: refreshing
                        ? const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(LucideIcons.refreshCw, size: 14),
                    onPressed: state.busy || refreshing
                        ? null
                        : () => _refreshSilently(visible: true),
                    child: Text(refreshing
                        ? context.l10n.loading
                        : context.l10n.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (tmuxSessions.isEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    border: Border.all(color: _border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      if (refreshing)
                        const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        const Icon(
                          LucideIcons.circleDashed,
                          size: 16,
                          color: _mutedForeground,
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          refreshing
                              ? context.l10n.queryingTmuxSessions
                              : context.l10n.noExistingTmuxSessions,
                          style: const TextStyle(
                            color: _mutedForeground,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              for (final tmuxSession in tmuxSessions)
                _TmuxSessionTile(
                  session: tmuxSession,
                  tag: session == null
                      ? null
                      : state.tmuxSessionTag(session, tmuxSession.name),
                  path: tmuxSession.currentPath ?? session?.currentPath,
                  onPressed: () => state.selectTmuxSession(tmuxSession),
                  onTagPressed: session == null
                      ? null
                      : () => _showTmuxTagDialog(
                            context,
                            state,
                            session,
                            tmuxSession.name,
                          ),
                  onEndPressed: session == null || state.busy
                      ? null
                      : () => unawaited(
                            state.deleteTmuxSession(session, tmuxSession.name),
                          ),
                ),
              const SizedBox(height: 8),
              ShadButton(
                leading: const Icon(LucideIcons.plus, size: 16),
                onPressed:
                    state.busy ? null : () => state.selectNewTmuxSession(),
                child: _FittingLabel(context.l10n.startTmuxDefaultPath),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TmuxSessionTile extends StatelessWidget {
  const _TmuxSessionTile({
    required this.session,
    required this.tag,
    required this.path,
    required this.onPressed,
    required this.onTagPressed,
    required this.onEndPressed,
  });

  final RemoteTmuxSession session;
  final SessionTag? tag;
  final String? path;
  final VoidCallback onPressed;
  final VoidCallback? onTagPressed;
  final VoidCallback? onEndPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: _border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.squareTerminal, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _compactPathDisplay(path ?? session.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatTmuxActivity(session),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _mutedForeground,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _TmuxTagBadge(tag: tag),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: context.l10n.tagSettings,
                icon: const Icon(LucideIcons.hash, size: 15),
                onPressed: onTagPressed,
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: context.l10n.endSession,
                icon: const Icon(LucideIcons.trash2, size: 15),
                style: IconButton.styleFrom(
                  minimumSize: const Size(44, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onEndPressed,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TmuxTagBadge extends StatelessWidget {
  const _TmuxTagBadge({required this.tag});

  final SessionTag? tag;

  @override
  Widget build(BuildContext context) {
    if (tag == null) {
      return const SizedBox.shrink();
    }
    final color = Color(tag!.colorValue);
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.36)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '#${tag!.label}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

const _tmuxTagColors = [
  Color(0xFF2563EB),
  Color(0xFF16A34A),
  Color(0xFFDB2777),
  Color(0xFF7C3AED),
  Color(0xFFEA580C),
  Color(0xFF0891B2),
];

Future<void> _showTmuxTagDialog(
  BuildContext context,
  AppState state,
  LiveSshSession session,
  String tmuxName,
) {
  final currentTag = state.tmuxSessionTag(session, tmuxName);
  final controller = TextEditingController(text: currentTag?.label ?? '');
  var selectedColor =
      Color(currentTag?.colorValue ?? _tmuxTagColors.first.toARGB32());
  return showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(context.l10n.tmuxTagTitle(tmuxName)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(LucideIcons.hash),
                    labelText: context.l10n.tagName,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final color in _tmuxTagColors)
                      InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => setDialogState(() {
                          selectedColor = color;
                        }),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selectedColor == color
                                  ? _warpInk
                                  : Colors.white,
                              width: selectedColor == color ? 3 : 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  state.setTmuxSessionTag(
                    session,
                    tmuxName,
                    label: '',
                    colorValue: selectedColor.toARGB32(),
                  );
                  Navigator.pop(context);
                },
                child: Text(context.l10n.remove),
              ),
              FilledButton(
                onPressed: () {
                  state.setTmuxSessionTag(
                    session,
                    tmuxName,
                    label: controller.text,
                    colorValue: selectedColor.toARGB32(),
                  );
                  Navigator.pop(context);
                },
                child: Text(context.l10n.save),
              ),
            ],
          );
        },
      );
    },
  );
}

class _StatusLamp extends StatelessWidget {
  const _StatusLamp({required this.color, this.size = 10});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
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

const _emptyTerminalFrame = TmuxCaptureFrame(
  content: '',
  paneId: null,
  cursorX: 0,
  cursorY: 0,
  paneWidth: 80,
  paneHeight: 24,
  paneMode: '',
  currentPath: null,
  historySize: null,
);

class _TerminalViewData {
  const _TerminalViewData({
    required this.frame,
    required this.error,
  });

  final TmuxCaptureFrame frame;
  final String? error;
}

class _TerminalDiff {
  String? _previousContent;
  List<int> _previousHashes = const [];
  int _previousLineCount = 0;
  int _unchangedFrames = 0;

  _TerminalDiffResult calculate(String content) {
    if (content == _previousContent) {
      _unchangedFrames += 1;
      return _TerminalDiffResult(
        hasChanges: false,
        changedLineCount: 0,
        totalLineCount: math.max(1, _previousLineCount),
        unchangedFrames: _unchangedFrames,
      );
    }
    _previousContent = content;
    final lines = content.split('\n');
    final hashes = lines.map((line) => line.hashCode).toList(growable: false);
    if (_previousLineCount == 0 ||
        (lines.length - _previousLineCount).abs() > 10) {
      _previousLineCount = lines.length;
      _previousHashes = hashes;
      _unchangedFrames = 0;
      return const _TerminalDiffResult(
        hasChanges: true,
        changedLineCount: 1,
        totalLineCount: 1,
        unchangedFrames: 0,
      );
    }

    var changedLineCount = 0;
    final maxLength = math.max(lines.length, _previousLineCount);
    for (var index = 0; index < maxLength; index += 1) {
      if (index >= hashes.length || index >= _previousHashes.length) {
        changedLineCount += 1;
      } else if (hashes[index] != _previousHashes[index]) {
        changedLineCount += 1;
      }
    }

    if (changedLineCount == 0) {
      _unchangedFrames += 1;
    } else {
      _unchangedFrames = 0;
    }
    _previousLineCount = lines.length;
    _previousHashes = hashes;
    return _TerminalDiffResult(
      hasChanges: changedLineCount > 0,
      changedLineCount: changedLineCount,
      totalLineCount: math.max(1, maxLength),
      unchangedFrames: _unchangedFrames,
    );
  }

  void reset() {
    _previousContent = null;
    _previousHashes = const [];
    _previousLineCount = 0;
    _unchangedFrames = 0;
  }
}

class _TerminalDiffResult {
  const _TerminalDiffResult({
    required this.hasChanges,
    required this.changedLineCount,
    required this.totalLineCount,
    required this.unchangedFrames,
  });

  final bool hasChanges;
  final int changedLineCount;
  final int totalLineCount;
  final int unchangedFrames;

  double get changeRatio => changedLineCount / totalLineCount;
}

class TerminalPane extends StatefulWidget {
  const TerminalPane({
    super.key,
    required this.state,
    required this.active,
  });

  final AppState state;
  final bool active;

  @override
  State<TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends State<TerminalPane> {
  final scrollController = ScrollController();
  final horizontalScrollController = ScrollController();
  final _terminalDiff = _TerminalDiff();
  final viewNotifier = ValueNotifier<_TerminalViewData>(
    const _TerminalViewData(frame: _emptyTerminalFrame, error: null),
  );
  final StringBuffer queuedLiteralInput = StringBuffer();
  Timer? pollTimer;
  Timer? literalInputTimer;
  Timer? reconnectNoticeTimer;
  TmuxCaptureFrame frame = _emptyTerminalFrame;
  bool polling = false;
  bool pollingStopped = false;
  int pollIntervalMs = 120;
  int extraScrollbackLines = 0;
  bool jumpToTopAfterNextPoll = false;
  bool jumpToBottomAfterNextPoll = false;
  bool historyExhausted = false;
  int? pendingHistoryExpansionLines;
  int? pendingHistoryExpansionPreviousLineCount;
  String? localError;
  String? activeFrameKey;

  int get _minPollIntervalMs => widget.state.lowEndModeEnabled ? 120 : 50;

  int get _maxPollIntervalMs => widget.state.lowEndModeEnabled ? 3000 : 2000;

  int get _baseScrollbackLines => widget.state.lowEndModeEnabled ? 400 : 1000;

  int get _historyLineLimit {
    final session = widget.state.activeSession;
    return math.max(
      1,
      session?.connection.tmuxHistoryLimit ?? _baseScrollbackLines,
    );
  }

  int get _currentScrollbackLines {
    return math.min(
      _historyLineLimit,
      _baseScrollbackLines + extraScrollbackLines,
    );
  }

  int get _availableHistoryLines {
    final remoteHistorySize = frame.historySize;
    if (remoteHistorySize == null) {
      return _historyLineLimit;
    }
    return math.min(_historyLineLimit, math.max(0, remoteHistorySize));
  }

  bool get _hasMoreHistory =>
      !historyExhausted && _currentScrollbackLines < _availableHistoryLines;

  @override
  void initState() {
    super.initState();
    _restoreCachedFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active) {
        _startPolling();
      }
    });
  }

  @override
  void dispose() {
    literalInputTimer?.cancel();
    pollTimer?.cancel();
    reconnectNoticeTimer?.cancel();
    viewNotifier.dispose();
    scrollController.dispose();
    horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TerminalPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextKey = _currentFrameKey();
    if (nextKey != activeFrameKey) {
      _restoreCachedFrame();
      if (widget.active) {
        _startPolling();
      }
      return;
    }
    if (widget.active != oldWidget.active) {
      if (widget.active) {
        _startPolling();
      } else {
        _stopPollingUntilActive();
      }
    }
  }

  String? _currentFrameKey() {
    final session = widget.state.activeSession;
    return session == null ? null : widget.state.terminalFrameKey(session);
  }

  void _restoreCachedFrame() {
    reconnectNoticeTimer?.cancel();
    final session = widget.state.activeSession;
    activeFrameKey =
        session == null ? null : widget.state.terminalFrameKey(session);
    final cached = widget.state.cachedTerminalFrame(session);
    frame = cached ?? _emptyTerminalFrame;
    localError = null;
    extraScrollbackLines = 0;
    historyExhausted = false;
    pollIntervalMs = _minPollIntervalMs;
    jumpToBottomAfterNextPoll = true;
    _terminalDiff.reset();
    viewNotifier.value = _TerminalViewData(frame: frame, error: localError);
    _scrollToBottomSoon();
  }

  void _startPolling() {
    reconnectNoticeTimer?.cancel();
    pollTimer?.cancel();
    pollingStopped = false;
    _pollOnce();
  }

  void _stopPollingUntilActive() {
    pollTimer?.cancel();
    pollingStopped = true;
  }

  void _scheduleNextPoll() {
    if (!mounted || pollingStopped || !widget.active) {
      return;
    }
    pollTimer?.cancel();
    pollTimer = Timer(Duration(milliseconds: pollIntervalMs), _pollOnce);
  }

  Future<void> _pollOnce() async {
    if (polling || !mounted || pollingStopped || !widget.active) {
      return;
    }
    polling = true;
    LiveSshSession? polledSession;
    final startedAt = DateTime.now();
    try {
      final live = widget.state.activeSession;
      polledSession = live;
      if (live == null) {
        return;
      }
      final liveFrameKey = widget.state.terminalFrameKey(live);
      final requestedScrollbackLines = _currentScrollbackLines;
      final next = await live.captureActiveTmuxPane(
        scrollbackLines: requestedScrollbackLines,
      );
      final latency = DateTime.now().difference(startedAt).inMilliseconds;
      if (!mounted || _currentFrameKey() != liveFrameKey) {
        return;
      }
      _updateHistoryExhaustion(
        nextContent: next.content,
        requestedScrollbackLines: requestedScrollbackLines,
        expansionRequestLines: pendingHistoryExpansionLines,
        expansionPreviousLineCount: pendingHistoryExpansionPreviousLineCount,
      );
      pendingHistoryExpansionLines = null;
      pendingHistoryExpansionPreviousLineCount = null;
      widget.state.cacheTerminalFrame(live, next);
      widget.state.updateSessionCurrentPath(live, next.currentPath);
      final diff = _terminalDiff.calculate(next.content);
      final metadataChanged = next.cursorX != frame.cursorX ||
          next.cursorY != frame.cursorY ||
          next.paneWidth != frame.paneWidth ||
          next.paneHeight != frame.paneHeight ||
          next.paneMode != frame.paneMode ||
          next.currentPath != frame.currentPath;
      final changed = diff.hasChanges || metadataChanged;
      final shouldFollowOutput = _isScrolledNearBottom();
      frame = next.copyWith(latencyMs: latency);
      localError = null;
      if (changed || viewNotifier.value.error != null) {
        viewNotifier.value = _TerminalViewData(frame: frame, error: null);
      }
      pollIntervalMs = _nextPollInterval(diff, metadataChanged);
      if (jumpToTopAfterNextPoll) {
        jumpToTopAfterNextPoll = false;
        jumpToBottomAfterNextPoll = false;
        if (changed) {
          _scrollToTopSoon();
        }
      } else if (jumpToBottomAfterNextPoll) {
        jumpToBottomAfterNextPoll = false;
        _scrollToBottomSoon();
      } else if (changed) {
        if (shouldFollowOutput) {
          _scrollToBottomSoon();
        }
      }
    } catch (error) {
      final closed =
          polledSession?.isClosed == true || _isClosedSshError(error);
      if (mounted) {
        localError = closed && widget.state.shouldDeferReconnectNotice
            ? null
            : closed
                ? context.l10n.reconnecting
                : _localizedTerminalError(context, error);
        viewNotifier.value = _TerminalViewData(
          frame: frame,
          error: localError,
        );
      }
      if (closed) {
        _handleClosedSession();
      } else {
        pollIntervalMs = math.min(_maxPollIntervalMs, pollIntervalMs + 250);
      }
    } finally {
      polling = false;
      if (!pollingStopped) {
        _scheduleNextPoll();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _KeyboardInsetPadding(
      onKeyboardShown: _scrollToBottomSoon,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: ValueListenableBuilder<_TerminalViewData>(
                      valueListenable: viewNotifier,
                      builder: (context, view, _) {
                        return _CaptureTerminalView(
                          frame: view.frame,
                          error: view.error,
                          hasMoreHistory: _hasMoreHistory,
                          verticalScrollController: scrollController,
                          horizontalScrollController:
                              horizontalScrollController,
                          onLiteralInput: _sendLiteral,
                          onSpecialInput: _sendSpecial,
                          onLoadMoreHistory: _loadMoreHistory,
                        );
                      },
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 10,
                  child: _TerminalSessionEndButton(
                    onPressed: _deleteCurrentTmuxSession,
                  ),
                ),
              ],
            ),
          ),
          RepaintBoundary(
            child: _KeyBar(
              state: widget.state,
              onLiteral: _sendLiteral,
              onSpecial: _sendSpecial,
              onFullText: _openFullText,
              onPasteText: _pasteClipboardText,
              onAttachImage: _attachImage,
            ),
          ),
        ],
      ),
    );
  }

  int _nextPollInterval(_TerminalDiffResult diff, bool metadataChanged) {
    if (metadataChanged || diff.unchangedFrames <= 3 || diff.changeRatio > .3) {
      return _minPollIntervalMs;
    }
    if (diff.unchangedFrames >= 15) {
      return _maxPollIntervalMs;
    }
    final ratio = (diff.unchangedFrames - 3) / (15 - 3);
    return (_minPollIntervalMs +
            (_maxPollIntervalMs - _minPollIntervalMs) * ratio)
        .round();
  }

  Future<void> _sendLiteral(String value) async {
    if (_shouldCoalesceLiteral(value)) {
      queuedLiteralInput.write(value);
      literalInputTimer ??= Timer(
        Duration(milliseconds: widget.state.lowEndModeEnabled ? 48 : 24),
        () => unawaited(_flushQueuedLiteralInput()),
      );
      return;
    }
    await _flushQueuedLiteralInput(pollAfter: false);
    await _sendLiteralNow(value);
  }

  bool _shouldCoalesceLiteral(String value) {
    return value.length == 1 && !value.contains('\n') && !value.contains('\r');
  }

  Future<void> _flushQueuedLiteralInput({bool pollAfter = true}) async {
    literalInputTimer?.cancel();
    literalInputTimer = null;
    if (queuedLiteralInput.isEmpty) {
      return;
    }
    final value = queuedLiteralInput.toString();
    queuedLiteralInput.clear();
    await _sendLiteralNow(value, pollAfter: pollAfter);
  }

  Future<void> _sendLiteralNow(
    String value, {
    bool pollAfter = true,
  }) async {
    final live = widget.state.activeSession;
    if (live == null || value.isEmpty) {
      return;
    }
    if (live.isClosed) {
      _handleClosedSession();
      return;
    }
    await live.sendTmuxLiteral(value);
    if (pollAfter) {
      await _pollOnce();
    }
  }

  Future<void> _sendSpecial(String key) async {
    await _flushQueuedLiteralInput(pollAfter: false);
    final live = widget.state.activeSession;
    if (live == null || key.isEmpty) {
      return;
    }
    if (live.isClosed) {
      _handleClosedSession();
      return;
    }
    await live.sendTmuxKey(key);
    await _pollOnce();
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollController.hasClients) {
        return;
      }
      final position = scrollController.position;
      scrollController.jumpTo(position.maxScrollExtent);
    });
  }

  bool _isScrolledNearBottom() {
    if (!scrollController.hasClients) {
      return true;
    }
    final position = scrollController.position;
    final distanceFromBottom = position.maxScrollExtent - position.pixels;
    return distanceFromBottom <= _terminalAutoScrollBottomTolerance;
  }

  void _scrollToTopSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollController.hasClients) {
        return;
      }
      scrollController.jumpTo(scrollController.position.minScrollExtent);
    });
  }

  void _loadMoreHistory() {
    final maxLines = _historyLineLimit;
    final currentLines = _currentScrollbackLines;
    if (currentLines >= maxLines) {
      return;
    }
    pendingHistoryExpansionPreviousLineCount =
        _terminalContentLineCount(frame.content);
    setState(() {
      extraScrollbackLines = math.min(
        maxLines - _baseScrollbackLines,
        extraScrollbackLines + _baseScrollbackLines,
      );
    });
    pendingHistoryExpansionLines = _currentScrollbackLines;
    jumpToTopAfterNextPoll = true;
    jumpToBottomAfterNextPoll = false;
    unawaited(_pollOnce());
  }

  void _updateHistoryExhaustion({
    required String nextContent,
    required int requestedScrollbackLines,
    required int? expansionRequestLines,
    required int? expansionPreviousLineCount,
  }) {
    final lineIncrease = expansionPreviousLineCount == null
        ? null
        : _terminalContentLineCount(nextContent) - expansionPreviousLineCount;
    final reachedHistoryStart = requestedScrollbackLines >= _historyLineLimit ||
        requestedScrollbackLines >= _availableHistoryLines ||
        expansionRequestLines == requestedScrollbackLines &&
            requestedScrollbackLines > _baseScrollbackLines &&
            lineIncrease != null &&
            lineIncrease < 3;
    if (historyExhausted == reachedHistoryStart) {
      return;
    }
    setState(() => historyExhausted = reachedHistoryStart);
  }

  void _handleClosedSession() {
    final deferNotice = widget.state.shouldDeferReconnectNotice;
    _stopPollingWithClosedMessage(showMessage: !deferNotice);
    if (deferNotice) {
      _scheduleReconnectNotice(widget.state.reconnectNoticeDelay);
    }
  }

  void _stopPollingWithClosedMessage({bool showMessage = true}) {
    pollingStopped = true;
    pollTimer?.cancel();
    if (mounted && showMessage) {
      localError = context.l10n.reconnecting;
      viewNotifier.value = _TerminalViewData(frame: frame, error: localError);
    }
    unawaited(widget.state.reconnectClosedSessions());
  }

  void _scheduleReconnectNotice(Duration delay) {
    reconnectNoticeTimer?.cancel();
    final frameKey = _currentFrameKey();
    reconnectNoticeTimer = Timer(delay, () {
      if (!mounted || !pollingStopped || _currentFrameKey() != frameKey) {
        return;
      }
      localError = context.l10n.reconnecting;
      viewNotifier.value = _TerminalViewData(frame: frame, error: localError);
    });
  }

  Future<void> _openFullText() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FullTextScreen(text: _stripAnsi(frame.content)),
      ),
    );
  }

  Future<void> _pasteClipboardText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      return;
    }
    await _sendLiteral(text);
  }

  Future<void> _attachImage() async {
    final live = widget.state.activeSession;
    if (live == null) {
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.image,
      withData: false,
      withReadStream: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    final file = result.files.first;
    final stream = file.readStream;
    if (stream == null) {
      return;
    }
    final directoryPath =
        widget.state.activeDirectory?.currentPath ?? live.currentPath;
    final uploadName = _temporaryUploadName(file.name);
    await widget.state.uploadFileStream(
      directoryPath: directoryPath,
      name: uploadName,
      stream: stream,
      temporary: true,
    );
    await _sendLiteral(_quoteForTerminal(_joinRemotePath(
      directoryPath,
      uploadName,
    )));
  }

  Future<void> _deleteCurrentTmuxSession() async {
    final session = widget.state.activeSession;
    final tmuxName = session?.selectedTmuxSessionName?.trim();
    if (session == null ||
        !session.tmuxAvailable ||
        tmuxName == null ||
        tmuxName.isEmpty) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.deleteTmuxSession),
        content: Text(context.l10n.deleteTmuxSessionMessage(tmuxName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.state.deleteActiveTmuxSession();
    }
  }
}

class _KeyboardInsetPadding extends StatefulWidget {
  const _KeyboardInsetPadding({
    required this.child,
    required this.onKeyboardShown,
  });

  final Widget child;
  final VoidCallback onKeyboardShown;

  @override
  State<_KeyboardInsetPadding> createState() => _KeyboardInsetPaddingState();
}

class _KeyboardInsetPaddingState extends State<_KeyboardInsetPadding> {
  double previousInset = 0;
  double targetInset = 0;
  double appliedInset = 0;
  Timer? insetTimer;

  @override
  void dispose() {
    insetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lowEndMode = _WorkspacePerformance.lowEndModeOf(context);
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    if (inset > 0 && inset > previousInset) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onKeyboardShown();
        }
      });
    }
    previousInset = inset;
    final effectiveInset = lowEndMode ? _debouncedInset(inset) : inset;
    return Padding(
      padding: EdgeInsets.only(bottom: effectiveInset),
      child: widget.child,
    );
  }

  double _debouncedInset(double inset) {
    if (inset == appliedInset) {
      targetInset = inset;
      return appliedInset;
    }
    if (inset == 0) {
      insetTimer?.cancel();
      targetInset = 0;
      appliedInset = 0;
      return appliedInset;
    }
    if (targetInset != inset) {
      targetInset = inset;
      insetTimer?.cancel();
      insetTimer = Timer(const Duration(milliseconds: 64), () {
        if (!mounted || appliedInset == targetInset) {
          return;
        }
        setState(() => appliedInset = targetInset);
      });
    }
    return appliedInset;
  }
}

class _CaptureTerminalView extends StatefulWidget {
  const _CaptureTerminalView({
    required this.frame,
    required this.error,
    required this.hasMoreHistory,
    required this.verticalScrollController,
    required this.horizontalScrollController,
    required this.onLiteralInput,
    required this.onSpecialInput,
    required this.onLoadMoreHistory,
  });

  final TmuxCaptureFrame frame;
  final String? error;
  final bool hasMoreHistory;
  final ScrollController verticalScrollController;
  final ScrollController horizontalScrollController;
  final Future<void> Function(String) onLiteralInput;
  final Future<void> Function(String) onSpecialInput;
  final VoidCallback onLoadMoreHistory;

  @override
  State<_CaptureTerminalView> createState() => _CaptureTerminalViewState();
}

class _CaptureTerminalViewState extends State<_CaptureTerminalView> {
  final focusNode = FocusNode();
  double fontSize = _terminalFontSize;

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lowEndMode = _WorkspacePerformance.lowEndModeOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final content =
            _terminalDisplayText(widget.frame.content, context.l10n);
        final textSpan = TextSpan(
          style: TextStyle(
            color: _terminalForeground,
            fontFamily: _terminalFontFamily,
            fontFamilyFallback: const [
              'FiraCodeNerdFontMono',
              'monospace',
            ],
            fontSize: fontSize,
            height: 1.1,
          ),
          children: _ansiTextSpans(
            content,
            fontSize,
          ),
        );
        final minWidth = math.max(
          constraints.maxWidth,
          widget.frame.paneWidth * _terminalCharacterWidth(fontSize) + 10,
        );
        return DecoratedBox(
          decoration: const BoxDecoration(color: _terminalBackground),
          child: KeyboardListener(
            focusNode: focusNode,
            autofocus: true,
            onKeyEvent: _handleKey,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => focusNode.requestFocus(),
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.error != null)
                        _TerminalErrorStrip(error: widget.error!),
                      Expanded(
                        child: Scrollbar(
                          controller: widget.horizontalScrollController,
                          thumbVisibility: true,
                          notificationPredicate: (notification) =>
                              notification.metrics.axis == Axis.horizontal,
                          child: SingleChildScrollView(
                            controller: widget.horizontalScrollController,
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: minWidth,
                              child: Scrollbar(
                                controller: widget.verticalScrollController,
                                thumbVisibility: true,
                                child: SingleChildScrollView(
                                  controller: widget.verticalScrollController,
                                  padding: const EdgeInsets.all(4),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (widget.hasMoreHistory)
                                        _TerminalHistoryMoreButton(
                                          onPressed: widget.onLoadMoreHistory,
                                        ),
                                      TextSelectionTheme(
                                        data: const TextSelectionThemeData(
                                          selectionColor: _terminalSelection,
                                          selectionHandleColor:
                                              _terminalSelectionHandle,
                                        ),
                                        child: lowEndMode
                                            ? Text.rich(
                                                textSpan,
                                                textScaler:
                                                    TextScaler.noScaling,
                                              )
                                            : SelectableText.rich(
                                                textSpan,
                                                textScaler:
                                                    TextScaler.noScaling,
                                              ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: _TerminalZoomControls(
                      canZoomIn: fontSize < _terminalMaxFontSize,
                      canZoomOut: fontSize > _terminalMinFontSize,
                      onZoomIn: () => _adjustFontSize(1),
                      onZoomOut: () => _adjustFontSize(-1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _adjustFontSize(double delta) {
    final nextFontSize =
        (fontSize + delta).clamp(_terminalMinFontSize, _terminalMaxFontSize);
    if (nextFontSize == fontSize) {
      return;
    }
    setState(() => fontSize = nextFontSize);
    focusNode.requestFocus();
    _scrollToBottomSoon();
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.verticalScrollController.hasClients) {
        return;
      }
      final position = widget.verticalScrollController.position;
      widget.verticalScrollController.jumpTo(position.maxScrollExtent);
    });
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return;
    }
    final logical = event.logicalKey;
    if (logical == LogicalKeyboardKey.enter) {
      unawaited(widget.onSpecialInput('Enter'));
      return;
    }
    if (logical == LogicalKeyboardKey.backspace) {
      unawaited(widget.onSpecialInput('BSpace'));
      return;
    }
    if (logical == LogicalKeyboardKey.tab) {
      unawaited(widget.onSpecialInput('Tab'));
      return;
    }
    if (logical == LogicalKeyboardKey.escape) {
      unawaited(widget.onSpecialInput('Escape'));
      return;
    }
    if (logical == LogicalKeyboardKey.arrowLeft) {
      unawaited(widget.onSpecialInput('Left'));
      return;
    }
    if (logical == LogicalKeyboardKey.arrowRight) {
      unawaited(widget.onSpecialInput('Right'));
      return;
    }
    if (logical == LogicalKeyboardKey.arrowUp) {
      unawaited(widget.onSpecialInput('Up'));
      return;
    }
    if (logical == LogicalKeyboardKey.arrowDown) {
      unawaited(widget.onSpecialInput('Down'));
      return;
    }
    if (HardwareKeyboard.instance.isControlPressed &&
        event.character != null &&
        event.character!.isNotEmpty) {
      unawaited(widget.onSpecialInput('C-${event.character!.toLowerCase()}'));
      return;
    }
    final character = event.character;
    if (character != null && character.isNotEmpty) {
      unawaited(widget.onLiteralInput(character));
    }
  }
}

class _TerminalHistoryMoreButton extends StatelessWidget {
  const _TerminalHistoryMoreButton({
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Center(
        child: TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: _terminalForeground,
            backgroundColor: const Color(0xFF2B3240),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            visualDensity: VisualDensity.compact,
            textStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          onPressed: onPressed,
          icon: const Icon(LucideIcons.chevronUp, size: 14),
          label: _FittingLabel(context.l10n.loadMoreHistory),
        ),
      ),
    );
  }
}

class _TerminalZoomControls extends StatelessWidget {
  const _TerminalZoomControls({
    required this.canZoomIn,
    required this.canZoomOut,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final bool canZoomIn;
  final bool canZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: context.l10n.zoomOutTerminal,
          child: _CompactGlassButton(
            height: 26,
            padding: EdgeInsets.zero,
            icon: LucideIcons.minus,
            onPressed: canZoomOut ? onZoomOut : null,
          ),
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: context.l10n.zoomInTerminal,
          child: _CompactGlassButton(
            height: 26,
            padding: EdgeInsets.zero,
            icon: LucideIcons.plus,
            onPressed: canZoomIn ? onZoomIn : null,
          ),
        ),
      ],
    );
  }
}

class _TerminalErrorStrip extends StatelessWidget {
  const _TerminalErrorStrip({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF111827),
        border: Border(bottom: BorderSide(color: Color(0xFF1F2937))),
      ),
      child: Row(
        children: [
          const _StatusLamp(color: _warning, size: 8),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFFBBF24),
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TerminalSessionEndButton extends StatelessWidget {
  const _TerminalSessionEndButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.l10n.deleteCurrentTmuxSession,
      child: _CompactGlassButton(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        icon: LucideIcons.logOut,
        label: context.l10n.endSession,
        onPressed: onPressed,
      ),
    );
  }
}

class _KeyBar extends StatefulWidget {
  const _KeyBar({
    required this.state,
    required this.onLiteral,
    required this.onSpecial,
    required this.onFullText,
    required this.onPasteText,
    required this.onAttachImage,
  });

  final AppState state;
  final Future<void> Function(String) onLiteral;
  final Future<void> Function(String) onSpecial;
  final VoidCallback onFullText;
  final Future<void> Function() onPasteText;
  final Future<void> Function() onAttachImage;

  @override
  State<_KeyBar> createState() => _KeyBarState();
}

class _KeyBarState extends State<_KeyBar> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MacroKeyRow(
              state: widget.state,
              onLiteral: widget.onLiteral,
              onSpecial: widget.onSpecial,
            ),
            const SizedBox(height: 5),
            SizedBox(
              height: 32,
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 1,
                textInputAction: TextInputAction.send,
                style: const TextStyle(fontSize: 12, color: _warpInk),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                  filled: true,
                  fillColor: const Color(0xEFFFFFFF),
                  prefixIcon: const Icon(LucideIcons.keyboard, size: 15),
                  suffixIcon: IconButton(
                    icon: const Icon(LucideIcons.send, size: 15),
                    onPressed: () => unawaited(_submitText()),
                    tooltip: context.l10n.sendInput,
                  ),
                ),
                onSubmitted: (_) => unawaited(_submitText()),
              ),
            ),
            const SizedBox(height: 5),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _KeyButton(
                      label: 'Ctrl+C', value: 'C-c', onSend: widget.onSpecial),
                  _KeyButton(
                      label: 'Enter', value: 'Enter', onSend: widget.onSpecial),
                  _KeyButton(
                      label: 'Back', value: 'BSpace', onSend: widget.onSpecial),
                  _KeyButton(
                      label: 'Up', value: 'Up', onSend: widget.onSpecial),
                  _KeyButton(
                      label: 'Down', value: 'Down', onSend: widget.onSpecial),
                  _KeyButton(
                    label: 'Tab',
                    value: 'Tab',
                    onSend: (_) => _submitTabCompletion(),
                  ),
                  _KeyButton(
                      label: 'Ctrl+D', value: 'C-d', onSend: widget.onSpecial),
                ],
              ),
            ),
            const SizedBox(height: 5),
            SizedBox(
              height: 32,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    SizedBox(
                      width: 36,
                      child: _CompactGlassButton(
                        height: 30,
                        padding: EdgeInsets.zero,
                        label: '1',
                        repeatOnLongPress: true,
                        onPressed: () => unawaited(widget.onLiteral('1')),
                      ),
                    ),
                    const SizedBox(width: 5),
                    SizedBox(
                      width: 36,
                      child: _CompactGlassButton(
                        height: 30,
                        padding: EdgeInsets.zero,
                        label: '2',
                        repeatOnLongPress: true,
                        onPressed: () => unawaited(widget.onLiteral('2')),
                      ),
                    ),
                    const SizedBox(width: 5),
                    SizedBox(
                      width: 50,
                      child: _CompactGlassButton(
                        height: 30,
                        padding: EdgeInsets.zero,
                        label: 'Esc',
                        repeatOnLongPress: true,
                        onPressed: () => unawaited(widget.onSpecial('Escape')),
                      ),
                    ),
                    const SizedBox(width: 5),
                    SizedBox(
                      width: 92,
                      child: _CompactGlassButton(
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        icon: LucideIcons.scrollText,
                        label: 'Full Text',
                        onPressed: widget.onFullText,
                      ),
                    ),
                    const SizedBox(width: 5),
                    SizedBox(
                      width: 78,
                      child: _CompactGlassButton(
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        icon: LucideIcons.clipboardPaste,
                        label: 'Paste',
                        onPressed: () => unawaited(widget.onPasteText()),
                      ),
                    ),
                    const SizedBox(width: 5),
                    SizedBox(
                      width: 78,
                      child: _CompactGlassButton(
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        icon: LucideIcons.imagePlus,
                        label: 'Image',
                        onPressed: () => unawaited(widget.onAttachImage()),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitText() async {
    final text = controller.text;
    if (text.isEmpty) {
      await widget.onSpecial('Enter');
      return;
    }
    await widget.onLiteral(text);
    await widget.onSpecial('Enter');
    controller.clear();
  }

  Future<void> _submitTabCompletion() async {
    final text = controller.text;
    if (text.isNotEmpty) {
      await widget.onLiteral(text);
    }
    await widget.onSpecial('Tab');
    if (text.isNotEmpty) {
      controller.clear();
    }
  }
}

class _MacroKeyRow extends StatelessWidget {
  const _MacroKeyRow({
    required this.state,
    required this.onLiteral,
    required this.onSpecial,
  });

  final AppState state;
  final Future<void> Function(String) onLiteral;
  final Future<void> Function(String) onSpecial;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var index = 0; index < 9; index += 1) ...[
              SizedBox(
                width: 42,
                child: _CompactGlassButton(
                  height: 30,
                  padding: EdgeInsets.zero,
                  label: 'F${index + 1}',
                  repeatOnLongPress: true,
                  inactive: state.keyboardMacro(index).trim().isEmpty,
                  onPressed: () => unawaited(_sendMacro(index)),
                ),
              ),
              const SizedBox(width: 5),
            ],
            SizedBox(
              width: 38,
              child: Tooltip(
                message: context.l10n.keyboardMacroSettings,
                child: _CompactGlassButton(
                  height: 30,
                  padding: EdgeInsets.zero,
                  icon: LucideIcons.settings,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => KeyboardMacroSettingsScreen(state: state),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendMacro(int index) async {
    final macro = state.keyboardMacro(index);
    if (macro.trim().isEmpty) {
      await onSpecial('F${index + 1}');
      return;
    }
    final specialKey = _macroSpecialKey(macro);
    if (specialKey != null) {
      await onSpecial(specialKey);
      return;
    }
    await onLiteral(macro);
  }
}

String? _macroSpecialKey(String macro) {
  final normalized = macro.trim().toUpperCase();
  final functionKey = RegExp(r'^F([1-9]|1[0-2])$').firstMatch(normalized);
  if (functionKey != null) {
    return normalized;
  }
  return null;
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({
    required this.label,
    required this.value,
    required this.onSend,
  });

  final String label;
  final String value;
  final Future<void> Function(String) onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: _CompactGlassButton(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        label: label,
        repeatOnLongPress: true,
        onPressed: () => unawaited(onSend(value)),
      ),
    );
  }
}

class _FittingLabel extends StatelessWidget {
  const _FittingLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.visible,
      ),
    );
  }
}

class KeyboardMacroSettingsScreen extends StatefulWidget {
  const KeyboardMacroSettingsScreen({super.key, required this.state});

  final AppState state;

  @override
  State<KeyboardMacroSettingsScreen> createState() =>
      _KeyboardMacroSettingsScreenState();
}

class _KeyboardMacroSettingsScreenState
    extends State<KeyboardMacroSettingsScreen> {
  late final List<TextEditingController> controllers;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    controllers = List<TextEditingController>.generate(
      9,
      (index) => TextEditingController(text: widget.state.keyboardMacro(index)),
    );
  }

  @override
  void dispose() {
    for (final controller in controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.keyboardMacros),
        actions: [
          _ToolbarButton(
            icon: LucideIcons.save,
            tooltip: context.l10n.save,
            onPressed: saving ? null : () => unawaited(_save()),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: controllers.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            return TextField(
              controller: controllers[index],
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                labelText: 'F${index + 1}',
                hintText: context.l10n.keyboardMacroHint,
                prefixIcon: const Icon(LucideIcons.keyboard),
                suffixIcon: IconButton(
                  tooltip: context.l10n.clear,
                  icon: const Icon(LucideIcons.x, size: 16),
                  onPressed: () => controllers[index].clear(),
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            icon: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.save, size: 16),
            onPressed: saving ? null : () => unawaited(_save()),
            label: Text(context.l10n.save),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (saving) {
      return;
    }
    setState(() => saving = true);
    await widget.state.saveKeyboardMacros(
      controllers.map((controller) => controller.text).toList(),
    );
    if (!mounted) {
      return;
    }
    setState(() => saving = false);
    Navigator.pop(context);
  }
}

class _CompactGlassButton extends StatefulWidget {
  const _CompactGlassButton({
    required this.height,
    required this.padding,
    required this.onPressed,
    this.icon,
    this.label,
    this.selected = false,
    this.inactive = false,
    this.busy = false,
    this.repeatOnLongPress = false,
  });

  final double height;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onPressed;
  final IconData? icon;
  final String? label;
  final bool selected;
  final bool inactive;
  final bool busy;
  final bool repeatOnLongPress;

  @override
  State<_CompactGlassButton> createState() => _CompactGlassButtonState();
}

class _CompactGlassButtonState extends State<_CompactGlassButton> {
  Timer? repeatDelayTimer;
  Timer? repeatTimer;
  bool pointerIsDown = false;
  bool repeatedDuringPress = false;
  bool pressedFeedback = false;

  @override
  void dispose() {
    _cancelRepeat();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _CompactGlassButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onPressed == null || !widget.repeatOnLongPress) {
      _cancelRepeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lowEndMode = _WorkspacePerformance.lowEndModeOf(context);
    final disabled = widget.onPressed == null;
    final pressed = pressedFeedback && !disabled;
    final inactive = widget.inactive && !widget.selected;
    final backgroundColor = widget.selected
        ? _warpInk
        : disabled
            ? const Color(0x66FFFFFF)
            : pressed
                ? inactive
                    ? const Color(0xFFD4D4D8)
                    : const Color(0xFFFFFFFF)
                : inactive
                    ? const Color(0xFFE4E4E7)
                    : const Color(0xE6FFFFFF);
    final borderColor = widget.selected
        ? const Color(0x330F172A)
        : pressed
            ? inactive
                ? const Color(0xFFD4D4D8)
                : const Color(0xFFFFFFFF)
            : inactive
                ? const Color(0xFFD4D4D8)
                : const Color(0xCCFFFFFF);
    final contentColor = widget.selected
        ? Colors.white
        : disabled || widget.inactive
            ? const Color(0xFF71717A)
            : _warpInk;
    final animationDuration =
        lowEndMode ? Duration.zero : const Duration(milliseconds: 70);
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: inactive || lowEndMode ? 0 : 12,
          sigmaY: inactive || lowEndMode ? 0 : 12,
        ),
        child: InkWell(
          onTap: disabled ? null : _handleTap,
          onTapDown: disabled ? null : _handleTapDown,
          onTapUp: disabled ? null : (_) => _releasePress(),
          onTapCancel: disabled ? null : _cancelRepeat,
          child: AnimatedScale(
            scale: pressed && !lowEndMode ? 0.96 : 1,
            duration: animationDuration,
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: animationDuration,
              curve: Curves.easeOut,
              transform: Matrix4.translationValues(
                0,
                pressed && !lowEndMode ? 1 : 0,
                0,
              ),
              height: widget.height,
              constraints: BoxConstraints(minWidth: widget.height),
              padding: widget.padding,
              decoration: BoxDecoration(
                color: backgroundColor,
                border: Border.all(color: borderColor),
                borderRadius: BorderRadius.circular(7),
                boxShadow: inactive || lowEndMode
                    ? const []
                    : [
                        BoxShadow(
                          color: pressed
                              ? const Color(0x080F172A)
                              : const Color(0x120F172A),
                          blurRadius: pressed ? 3 : 10,
                          offset: Offset(0, pressed ? 1 : 4),
                        ),
                        if (pressed)
                          const BoxShadow(
                            color: Color(0x1AFFFFFF),
                            blurRadius: 0,
                            spreadRadius: 1,
                          ),
                      ],
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final bounded = constraints.hasBoundedWidth;
                  final label = widget.label == null
                      ? null
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            widget.label!,
                            maxLines: 1,
                            overflow: TextOverflow.visible,
                            style: TextStyle(
                              color: contentColor,
                              fontSize: 11,
                              fontWeight:
                                  inactive ? FontWeight.w600 : FontWeight.w700,
                            ),
                          ),
                        );
                  return Row(
                    mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.busy)
                        SizedBox(
                          width: math.max(12, widget.height * .42),
                          height: math.max(12, widget.height * .42),
                          child:
                              const CircularProgressIndicator(strokeWidth: 2),
                        ),
                      if (widget.icon != null)
                        Icon(
                          widget.icon,
                          size: 13,
                          color: contentColor,
                        ),
                      if (widget.icon != null && widget.label != null)
                        const SizedBox(width: 5),
                      if (label != null)
                        bounded ? Flexible(child: label) : label,
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleTap() {
    if (repeatedDuringPress) {
      repeatedDuringPress = false;
      return;
    }
    widget.onPressed?.call();
  }

  void _handleTapDown(TapDownDetails _) {
    _setPressedFeedback(true);
    if (!widget.repeatOnLongPress || widget.onPressed == null) {
      return;
    }
    _cancelRepeat(keepPressedFeedback: true);
    pointerIsDown = true;
    repeatedDuringPress = false;
    repeatDelayTimer = Timer(const Duration(milliseconds: 420), () {
      if (!pointerIsDown || widget.onPressed == null) {
        return;
      }
      repeatedDuringPress = true;
      widget.onPressed?.call();
      repeatTimer = Timer.periodic(const Duration(milliseconds: 90), (_) {
        if (!pointerIsDown || widget.onPressed == null) {
          _cancelRepeat();
          return;
        }
        widget.onPressed?.call();
      });
    });
  }

  void _releasePress() {
    _cancelRepeat();
  }

  void _cancelRepeat({bool keepPressedFeedback = false}) {
    pointerIsDown = false;
    repeatDelayTimer?.cancel();
    repeatDelayTimer = null;
    repeatTimer?.cancel();
    repeatTimer = null;
    if (!keepPressedFeedback) {
      _setPressedFeedback(false);
    }
  }

  void _setPressedFeedback(bool value) {
    if (pressedFeedback == value || !mounted) {
      return;
    }
    setState(() => pressedFeedback = value);
  }
}

const _ansiSpanCacheLimit = 24;
const _ansiSpanCacheMaxChars = 260000;
final LinkedHashMap<String, List<TextSpan>> _ansiSpanCache = LinkedHashMap();
final Map<double, double> _terminalCharacterWidthCache = {};

double _terminalCharacterWidth(double fontSize) {
  final cached = _terminalCharacterWidthCache[fontSize];
  if (cached != null) {
    return cached;
  }
  final painter = TextPainter(
    text: TextSpan(
      text: 'M',
      style: TextStyle(
        fontFamily: _terminalFontFamily,
        fontFamilyFallback: const [
          'FiraCodeNerdFontMono',
          'monospace',
        ],
        fontSize: fontSize,
        height: 1.1,
      ),
    ),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
  )..layout();
  final width = math.max(1.0, painter.width);
  _terminalCharacterWidthCache[fontSize] = width;
  return width;
}

String _terminalDisplayText(String rawText, SeilLocalizations l10n) {
  return rawText.isEmpty
      ? '${l10n.terminalPreparingTmuxSession}$_terminalBottomPaddingLines'
      : '$rawText$_terminalBottomPaddingLines';
}

int _terminalContentLineCount(String text) {
  if (text.isEmpty) {
    return 0;
  }
  return '\n'.allMatches(text).length + 1;
}

List<TextSpan> _ansiTextSpans(String text, double fontSize) {
  final cacheKey = '$fontSize\x00$text';
  if (text.length <= _ansiSpanCacheMaxChars) {
    final cached = _ansiSpanCache.remove(cacheKey);
    if (cached != null) {
      _ansiSpanCache[cacheKey] = cached;
      return cached;
    }
  }

  final spans = <TextSpan>[];
  var currentStyle = _TerminalTextStyleState.base();
  var index = 0;
  final ansi = RegExp(r'\x1B\[([0-9;:?]*)[ -/]*[@-~]');
  for (final match in ansi.allMatches(text)) {
    if (match.start > index) {
      spans.add(TextSpan(
        text: text.substring(index, match.start),
        style: currentStyle.toTextStyle(fontSize: fontSize),
      ));
    }
    final sequence = match.group(0) ?? '';
    if (sequence.endsWith('m')) {
      currentStyle = _applySgr(currentStyle, match.group(1) ?? '');
    }
    index = match.end;
  }
  if (index < text.length) {
    spans.add(TextSpan(
      text: text.substring(index),
      style: currentStyle.toTextStyle(fontSize: fontSize),
    ));
  }

  if (text.length <= _ansiSpanCacheMaxChars) {
    _ansiSpanCache[cacheKey] = spans;
    while (_ansiSpanCache.length > _ansiSpanCacheLimit) {
      _ansiSpanCache.remove(_ansiSpanCache.keys.first);
    }
  }
  return spans;
}

_TerminalTextStyleState _applySgr(
  _TerminalTextStyleState current,
  String rawCodes,
) {
  final codes = rawCodes.isEmpty
      ? const [0]
      : rawCodes
          .replaceAll(':', ';')
          .split(';')
          .where((code) => code.isNotEmpty)
          .map((code) => int.tryParse(code) ?? 0)
          .toList();
  var style = current;
  for (var i = 0; i < codes.length; i += 1) {
    final code = codes[i];
    if (code == 0) {
      style = _TerminalTextStyleState.base();
    } else if (code == 1) {
      style = style.copyWith(fontWeight: FontWeight.w500);
    } else if (code == 2) {
      style = style.copyWith(
        foreground: _dimmedTerminalColor(style.foreground),
      );
    } else if (code == 3) {
      style = style.copyWith(fontStyle: FontStyle.italic);
    } else if (code == 4) {
      style = style.copyWith(decoration: TextDecoration.underline);
    } else if (code == 7) {
      style = style.copyWith(inverse: true);
    } else if (code == 22) {
      style = style.copyWith(fontWeight: FontWeight.w400);
    } else if (code == 23) {
      style = style.copyWith(fontStyle: FontStyle.normal);
    } else if (code == 24) {
      style = style.copyWith(decoration: TextDecoration.none);
    } else if (code == 27) {
      style = style.copyWith(inverse: false);
    } else if (code == 39) {
      style = style.copyWith(foreground: _terminalForeground);
    } else if (code == 49) {
      style = style.copyWith(background: Colors.transparent);
    } else if (code >= 30 && code <= 37) {
      style = style.copyWith(
        foreground: _ansiColor(code - 30, bright: false),
      );
    } else if (code >= 40 && code <= 47) {
      style = style.copyWith(
        background: _ansiColor(code - 40, bright: false),
      );
    } else if (code == 38 || code == 48) {
      final parsed = _parseExtendedAnsiColor(codes, i + 1);
      if (parsed != null) {
        style = code == 38
            ? style.copyWith(foreground: parsed.color)
            : style.copyWith(background: parsed.color);
        i = parsed.nextIndex - 1;
      }
    } else if (code >= 90 && code <= 97) {
      style = style.copyWith(
        foreground: _ansiColor(code - 90, bright: true),
      );
    } else if (code >= 100 && code <= 107) {
      style = style.copyWith(
        background: _ansiColor(code - 100, bright: true),
      );
    }
  }
  return style;
}

class _TerminalTextStyleState {
  const _TerminalTextStyleState({
    required this.foreground,
    required this.background,
    required this.fontWeight,
    required this.fontStyle,
    required this.decoration,
    required this.inverse,
  });

  factory _TerminalTextStyleState.base() {
    return const _TerminalTextStyleState(
      foreground: _terminalForeground,
      background: Colors.transparent,
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      decoration: TextDecoration.none,
      inverse: false,
    );
  }

  final Color foreground;
  final Color background;
  final FontWeight fontWeight;
  final FontStyle fontStyle;
  final TextDecoration decoration;
  final bool inverse;

  _TerminalTextStyleState copyWith({
    Color? foreground,
    Color? background,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    TextDecoration? decoration,
    bool? inverse,
  }) {
    return _TerminalTextStyleState(
      foreground: foreground ?? this.foreground,
      background: background ?? this.background,
      fontWeight: fontWeight ?? this.fontWeight,
      fontStyle: fontStyle ?? this.fontStyle,
      decoration: decoration ?? this.decoration,
      inverse: inverse ?? this.inverse,
    );
  }

  TextStyle toTextStyle({double? fontSize}) {
    final foreground = _readableTerminalForeground(
      effectiveForeground,
      effectiveBackground,
    );
    return TextStyle(
      color: foreground,
      backgroundColor: effectiveBackground,
      fontFamily: _terminalFontFamily,
      fontFamilyFallback: const [
        'FiraCodeNerdFontMono',
        'monospace',
      ],
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      decoration: decoration,
      decorationColor: foreground,
      fontSize: fontSize,
      height: 1.1,
    );
  }

  Color get effectiveForeground {
    if (!inverse) {
      return foreground;
    }
    return background == Colors.transparent ? _terminalBackground : background;
  }

  Color get effectiveBackground {
    if (!inverse) {
      return background;
    }
    return foreground;
  }
}

Color _dimmedTerminalColor(Color color) {
  return Color.lerp(color, _terminalMutedForeground, 0.45) ?? color;
}

Color _readableTerminalForeground(Color foreground, Color background) {
  final effectiveBackground =
      background == Colors.transparent ? _terminalBackground : background;
  if (_contrastRatio(foreground, effectiveBackground) >= 3.2) {
    return foreground;
  }

  final backgroundIsDark = _relativeLuminance(effectiveBackground) < 0.5;
  final hsl = HSLColor.fromColor(foreground);
  for (var step = 1; step <= 12; step += 1) {
    final amount = step / 12;
    final lightness = backgroundIsDark
        ? hsl.lightness + (1 - hsl.lightness) * amount
        : hsl.lightness * (1 - amount);
    final candidate = hsl.withLightness(lightness.clamp(0.0, 1.0)).toColor();
    if (_contrastRatio(candidate, effectiveBackground) >= 3.2) {
      return candidate;
    }
  }

  return backgroundIsDark ? Colors.white : Colors.black;
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = _relativeLuminance(first);
  final secondLuminance = _relativeLuminance(second);
  final lighter = math.max(firstLuminance, secondLuminance);
  final darker = math.min(firstLuminance, secondLuminance);
  return (lighter + 0.05) / (darker + 0.05);
}

double _relativeLuminance(Color color) {
  double linearize(int channel) {
    final value = channel / 255.0;
    return value <= 0.03928
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  final argb = color.toARGB32();
  return 0.2126 * linearize((argb >> 16) & 0xff) +
      0.7152 * linearize((argb >> 8) & 0xff) +
      0.0722 * linearize(argb & 0xff);
}

({Color color, int nextIndex})? _parseExtendedAnsiColor(
  List<int> codes,
  int startIndex,
) {
  if (startIndex >= codes.length) {
    return null;
  }

  final mode = codes[startIndex];
  if (mode == 5 && startIndex + 1 < codes.length) {
    return (
      color: _ansi256Color(codes[startIndex + 1]),
      nextIndex: startIndex + 2,
    );
  }

  if (mode == 2 && startIndex + 3 < codes.length) {
    return (
      color: Color.fromARGB(
        255,
        codes[startIndex + 1].clamp(0, 255),
        codes[startIndex + 2].clamp(0, 255),
        codes[startIndex + 3].clamp(0, 255),
      ),
      nextIndex: startIndex + 4,
    );
  }

  return null;
}

Color _ansiColor(int index, {required bool bright}) {
  const normal = [
    Color(0xFF5C6773),
    Color(0xFFF28779),
    Color(0xFFBAE67E),
    Color(0xFFFFD580),
    Color(0xFF73D0FF),
    Color(0xFFD4BFFF),
    Color(0xFF95E6CB),
    Color(0xFFCBCCC6),
  ];
  const brightColors = [
    Color(0xFF707A8C),
    Color(0xFFFFAD99),
    Color(0xFFD5FF80),
    Color(0xFFFFE6B3),
    Color(0xFFA6E1FF),
    Color(0xFFE6D6FF),
    Color(0xFFC2FFF0),
    Color(0xFFFFFFFF),
  ];
  return bright ? brightColors[index] : normal[index];
}

Color _ansi256Color(int value) {
  final code = value.clamp(0, 255);
  if (code < 16) {
    return _ansiColor(code % 8, bright: code >= 8);
  }
  if (code >= 232) {
    final channel = 8 + (code - 232) * 10;
    return Color.fromARGB(255, channel, channel, channel);
  }

  final cube = code - 16;
  final r = cube ~/ 36;
  final g = (cube % 36) ~/ 6;
  final b = cube % 6;
  int channel(int component) => component == 0 ? 0 : 55 + component * 40;
  return Color.fromARGB(255, channel(r), channel(g), channel(b));
}

String _stripAnsi(String text) {
  return text.replaceAll(RegExp(r'\x1B\[[0-9;:?]*[ -/]*[@-~]'), '');
}

String _quoteForTerminal(String value) {
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

String _joinRemotePath(String directoryPath, String name) {
  final base = directoryPath.trim().isEmpty ? '/' : directoryPath.trim();
  return base == '/' ? '/$name' : '$base/$name';
}

String _temporaryUploadName(String originalName) {
  final sanitized = originalName
      .trim()
      .replaceAll(RegExp(r'[/\\]+'), '-')
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-');
  final suffix = sanitized.isEmpty ? 'image' : sanitized;
  return '.seil-${DateTime.now().millisecondsSinceEpoch}-$suffix';
}

String _temporaryExternalOpenName(String originalName) {
  final sanitized = originalName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final safeName = sanitized.trim().isEmpty ? 'seil-file' : sanitized.trim();
  return '${DateTime.now().microsecondsSinceEpoch}-$safeName';
}

Future<void> _openRemoteFileExternally({
  required LiveSshSession session,
  required RemoteFileEntry entry,
}) async {
  final bytes = await session.downloadBytes(entry.path);
  final directory = await getTemporaryDirectory();
  final localPath = p.join(
    directory.path,
    _temporaryExternalOpenName(entry.name),
  );
  final file = File(localPath);
  await file.writeAsBytes(bytes, flush: true);
  await const ExternalFileOpener().open(file.path);
}

bool _isClosedSshError(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains(SeilErrorCodes.reconnecting.toLowerCase()) ||
      message.contains('transport is closed') ||
      message.contains('connection closed while waiting for channel open') ||
      message.contains('sshstateerror(connection closed');
}

String _localizedTerminalError(BuildContext context, Object error) {
  if (_isClosedSshError(error)) {
    return context.l10n.reconnecting;
  }
  return seilLocalizedErrorMessage(
    Localizations.localeOf(context).languageCode,
    error,
  );
}

class FileExplorerPane extends StatefulWidget {
  const FileExplorerPane({super.key, required this.state});

  final AppState state;

  @override
  State<FileExplorerPane> createState() => _FileExplorerPaneState();
}

class _FileExplorerPaneState extends State<FileExplorerPane> {
  String filter = '';
  bool showHidden = false;
  String sortMode = 'name';
  bool uploading = false;
  bool deleteMode = false;
  bool deleting = false;
  final selectedDeletePaths = <String>{};
  Timer? filterDebounce;

  @override
  void dispose() {
    filterDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final directory = widget.state.activeDirectory;
    if (directory == null) {
      return Center(child: Text(context.l10n.fileInfoUnavailable));
    }

    final entries = _filteredEntries(directory.entries);
    final dirCount = entries.where((entry) => entry.isDirectory).length;
    final fileCount = entries.length - dirCount;
    final selectedDeleteEntries = [
      for (final entry in entries)
        if (!entry.isDirectory && selectedDeletePaths.contains(entry.path))
          entry,
    ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (deleteMode) ...[
                    _ExplorerIconButton(
                      icon: LucideIcons.x,
                      tooltip: context.l10n.cancel,
                      onPressed: deleting ? null : _exitDeleteMode,
                    ),
                    _ExplorerIconButton(
                      icon: LucideIcons.trash2,
                      tooltip: context.l10n.delete,
                      busy: deleting,
                      selected: selectedDeleteEntries.isNotEmpty,
                      onPressed: deleting || selectedDeleteEntries.isEmpty
                          ? null
                          : () => _confirmDelete(selectedDeleteEntries),
                    ),
                  ] else ...[
                    _ExplorerIconButton(
                      icon: LucideIcons.chevronLeft,
                      tooltip: context.l10n.previousFolder,
                      onPressed: widget.state.canGoBackDirectory
                          ? widget.state.goBackDirectory
                          : null,
                    ),
                    _ExplorerIconButton(
                      icon: LucideIcons.chevronUp,
                      tooltip: context.l10n.parentFolder,
                      onPressed: directory.parentPath == null
                          ? null
                          : () => widget.state.loadDirectory(
                                directory.parentPath!,
                              ),
                    ),
                    _ExplorerIconButton(
                      icon: LucideIcons.squareTerminal,
                      tooltip: context.l10n.startTerminalHere,
                      onPressed: widget.state.busy
                          ? null
                          : () => widget.state.createTerminalSessionFromActive(
                                path: directory.currentPath,
                                initialPaneIndex: 0,
                                selectNewTmux: true,
                              ),
                    ),
                    _ExplorerIconButton(
                      icon: LucideIcons.upload,
                      tooltip: context.l10n.upload,
                      busy: uploading,
                      onPressed: uploading ? null : () => _uploadFiles(context),
                    ),
                    _ExplorerIconButton(
                      icon: LucideIcons.folderPlus,
                      tooltip: context.l10n.newFolder,
                      onPressed: () => _newFolder(context),
                    ),
                    _ExplorerIconButton(
                      icon: LucideIcons.trash2,
                      tooltip: context.l10n.delete,
                      onPressed: fileCount == 0
                          ? null
                          : () => setState(() => deleteMode = true),
                    ),
                    _ExplorerIconButton(
                      icon: LucideIcons.refreshCw,
                      tooltip: context.l10n.refresh,
                      onPressed: widget.state.refreshActiveDirectory,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              _ExplorerPathBanner(directory.currentPath),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 28,
                      child: TextField(
                        style: const TextStyle(
                          color: _warpInk,
                          fontSize: 12,
                          height: 1.1,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xEFFFFFFF),
                          prefixIcon: const Icon(LucideIcons.search, size: 14),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          hintText: context.l10n.search,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(7),
                            borderSide: const BorderSide(color: _glassStroke),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(7),
                            borderSide: const BorderSide(color: _glassStroke),
                          ),
                        ),
                        onChanged: _setFilterDebounced,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _SortMenu(
                    value: sortMode,
                    onChanged: (value) => setState(() => sortMode = value),
                  ),
                  _ExplorerIconButton(
                    icon: showHidden ? LucideIcons.eye : LucideIcons.eyeOff,
                    tooltip: context.l10n.showHiddenFiles,
                    selected: showHidden,
                    onPressed: () => setState(() => showHidden = !showHidden),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _ExplorerPill(label: context.l10n.dirsCount(dirCount)),
                  const SizedBox(width: 5),
                  _ExplorerPill(label: context.l10n.filesCount(fileCount)),
                  if (deleteMode) ...[
                    const SizedBox(width: 5),
                    _ExplorerPill(
                      label: selectedDeleteEntries.isEmpty
                          ? context.l10n.selectFilesToDelete
                          : context.l10n.selectedFiles(
                              selectedDeleteEntries.length,
                            ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    _sortModeLabel(context, sortMode),
                    style: const TextStyle(
                      color: _mutedForeground,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    filter.trim().isEmpty
                        ? context.l10n.emptyDirectory
                        : context.l10n.noSearchResults,
                    style: const TextStyle(
                      color: _mutedForeground,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    8,
                    0,
                    8,
                    84 + MediaQuery.viewPaddingOf(context).bottom,
                  ),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final selected = selectedDeletePaths.contains(entry.path);
                    return _ExplorerEntryTile(
                      entry: entry,
                      selected: selected,
                      selectionMode: deleteMode,
                      selectable: !entry.isDirectory,
                      onTap: deleteMode
                          ? () => _toggleDeleteSelection(entry)
                          : () => entry.isDirectory
                              ? widget.state.loadDirectory(entry.path)
                              : _openFile(context, entry),
                      onRename:
                          deleteMode ? null : () => _rename(context, entry),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _uploadFiles(BuildContext context) async {
    final directory = widget.state.activeDirectory;
    if (directory == null || uploading) {
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
      withReadStream: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }

    setState(() => uploading = true);
    var uploaded = 0;
    var skipped = 0;
    try {
      for (final file in result.files) {
        final stream = file.readStream;
        if (stream == null) {
          skipped += 1;
          continue;
        }
        await widget.state.uploadFileStream(
          directoryPath: directory.currentPath,
          name: file.name,
          stream: stream,
        );
        uploaded += 1;
      }
    } finally {
      if (mounted) {
        setState(() => uploading = false);
      }
    }

    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          skipped == 0
              ? context.l10n.uploadedFiles(uploaded)
              : context.l10n.uploadedAndSkippedFiles(uploaded, skipped),
        ),
      ),
    );
  }

  List<RemoteFileEntry> _filteredEntries(List<RemoteFileEntry> entries) {
    final needle = filter.trim().toLowerCase();
    final filtered = entries.where((entry) {
      if (!showHidden && entry.name.startsWith('.')) {
        return false;
      }
      return needle.isEmpty || entry.name.toLowerCase().contains(needle);
    }).toList();

    filtered.sort((left, right) {
      if (left.isDirectory != right.isDirectory) {
        return left.isDirectory ? -1 : 1;
      }
      return switch (sortMode) {
        'type' => left.typeLabel.compareTo(right.typeLabel),
        'modified' =>
          (right.modifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(
                  left.modifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
        'created' => (right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(
                left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
        _ => left.name.toLowerCase().compareTo(right.name.toLowerCase()),
      };
    });
    return filtered;
  }

  void _setFilterDebounced(String value) {
    filterDebounce?.cancel();
    filterDebounce = Timer(const Duration(milliseconds: 120), () {
      if (mounted) {
        setState(() => filter = value);
      }
    });
  }

  void _exitDeleteMode() {
    setState(() {
      deleteMode = false;
      selectedDeletePaths.clear();
    });
  }

  void _toggleDeleteSelection(RemoteFileEntry entry) {
    if (entry.isDirectory || deleting) {
      return;
    }
    setState(() {
      if (!selectedDeletePaths.add(entry.path)) {
        selectedDeletePaths.remove(entry.path);
      }
    });
  }

  Future<void> _confirmDelete(
    List<RemoteFileEntry> entries,
  ) async {
    if (entries.isEmpty || deleting) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.delete),
        content: Text(context.l10n.deleteFilesMessage(entries.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => deleting = true);
    try {
      await widget.state.deleteFileEntries(entries);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.deletedFiles(entries.length))),
      );
      _exitDeleteMode();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.deleteFailed(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => deleting = false);
      }
    }
  }

  Future<void> _newFolder(BuildContext context) async {
    final name = await _askText(
      context,
      title: context.l10n.newFolder,
      label: context.l10n.folderName,
    );
    if (name != null && name.trim().isNotEmpty) {
      await widget.state.createFolder(name);
    }
  }

  Future<void> _rename(BuildContext context, RemoteFileEntry entry) async {
    final name = await _askText(
      context,
      title: context.l10n.rename,
      label: context.l10n.newName,
      initialValue: entry.name,
    );
    if (name != null && name.trim().isNotEmpty) {
      await widget.state.renameEntry(entry, name);
    }
  }

  Future<void> _openFile(BuildContext context, RemoteFileEntry entry) async {
    final session = widget.state.activeSession;
    if (session == null) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FilePreviewScreen(
          session: session,
          entry: entry,
          onSaved: widget.state.refreshActiveDirectory,
        ),
      ),
    );
  }

  Future<String?> _askText(
    BuildContext context, {
    required String title,
    required String label,
    String initialValue = '',
  }) {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: label),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(context.l10n.ok),
          ),
        ],
      ),
    );
  }
}

class _ExplorerPathBanner extends StatelessWidget {
  const _ExplorerPathBanner(this.path);

  final String path;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: path,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: () => _showFullPath(context, path),
        child: Container(
          height: 30,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: const Color(0xEFFFFFFF),
            border: Border.all(color: _glassStroke),
            borderRadius: BorderRadius.circular(7),
          ),
          child: _FittingExplorerPathText(path),
        ),
      ),
    );
  }
}

class _FittingExplorerPathText extends StatelessWidget {
  const _FittingExplorerPathText(this.path);

  static const _style = TextStyle(
    color: _mutedForeground,
    fontSize: 11,
    fontWeight: FontWeight.w700,
  );

  final String path;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final display = _pathDisplayForWidth(
          path,
          constraints.maxWidth,
          _style,
          Directionality.of(context),
        );
        return Text(
          display,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _style,
        );
      },
    );
  }
}

Future<void> _showFullPath(BuildContext context, String path) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.currentPath),
      content: SelectableText(path),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: path));
            Navigator.pop(context);
          },
          child: Text(context.l10n.copy),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.ok),
        ),
      ],
    ),
  );
}

String _pathDisplayForWidth(
  String path,
  double maxWidth,
  TextStyle style,
  TextDirection textDirection,
) {
  final normalized = _normalizeDisplayPath(path);
  if (_textFits(normalized, maxWidth, style, textDirection)) {
    return normalized;
  }
  final candidates = _parentCompactedPathCandidates(normalized);
  for (final candidate in candidates) {
    if (_textFits(candidate, maxWidth, style, textDirection)) {
      return candidate;
    }
  }
  return candidates.isEmpty ? normalized : candidates.last;
}

List<String> _parentCompactedPathCandidates(String path) {
  if (path == '/') {
    return const ['/'];
  }
  final absolute = path.startsWith('/');
  final prefix = absolute ? '/...' : '...';
  final parts = path.split('/').where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) {
    return const ['/'];
  }

  final candidates = <String>[];
  for (var start = 1; start < parts.length; start += 1) {
    candidates.add('$prefix/${parts.sublist(start).join('/')}');
  }
  candidates.add(parts.last);
  return candidates;
}

bool _textFits(
  String text,
  double maxWidth,
  TextStyle style,
  TextDirection textDirection,
) {
  if (!maxWidth.isFinite || maxWidth <= 0) {
    return true;
  }
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: textDirection,
  )..layout(maxWidth: maxWidth);
  return !painter.didExceedMaxLines && painter.size.width <= maxWidth;
}

String _compactPathDisplay(String path) {
  final normalized = _normalizeDisplayPath(path);
  if (normalized == '/') {
    return '/';
  }
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) {
    return '/';
  }
  final leaf = parts.last;
  if (parts.length == 1) {
    return '/$leaf';
  }
  return '../$leaf';
}

String _normalizeDisplayPath(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) {
    return '/';
  }
  final collapsed = trimmed.replaceAll(RegExp(r'/+'), '/');
  if (collapsed == '/') {
    return '/';
  }
  return collapsed.endsWith('/')
      ? collapsed.substring(0, collapsed.length - 1)
      : collapsed;
}

class _ExplorerIconButton extends StatelessWidget {
  const _ExplorerIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.busy = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: SizedBox(
          width: 30,
          child: _CompactGlassButton(
            height: 30,
            padding: EdgeInsets.zero,
            icon: busy ? null : icon,
            label: null,
            selected: selected,
            busy: busy,
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }
}

class _ExplorerPill extends StatelessWidget {
  const _ExplorerPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xBFFFFFFF),
        border: Border.all(color: _glassStroke),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: _mutedForeground,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ExplorerEntryTile extends StatelessWidget {
  const _ExplorerEntryTile({
    required this.entry,
    required this.onTap,
    required this.onRename,
    this.selectionMode = false,
    this.selectable = true,
    this.selected = false,
  });

  final RemoteFileEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onRename;
  final bool selectionMode;
  final bool selectable;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFE0F2FE) : const Color(0xBFFFFFFF),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: selectionMode && !selectable ? null : onTap,
        onLongPress: onRename,
        child: Container(
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(
              color:
                  selected ? const Color(0xFF38BDF8) : const Color(0xCFFFFFFF),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              if (selectionMode) ...[
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: selected,
                    onChanged: selectable ? (_) => onTap() : null,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              _FileEntryIcon(entry: entry),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _warpInk,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatEntryDate(entry.modifiedAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _mutedForeground,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      entry.isDirectory
                          ? context.l10n.folder
                          : '${entry.typeLabel} · ${_formatBytes(entry.size)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _mutedForeground,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (!selectionMode)
                Icon(
                  entry.isDirectory
                      ? LucideIcons.chevronRight
                      : LucideIcons.eye,
                  size: 14,
                  color: _mutedForeground,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileEntryIcon extends StatelessWidget {
  const _FileEntryIcon({required this.entry});

  final RemoteFileEntry entry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: SvgPicture.asset(
        'assets/vscode-icons/icons/${entry.iconName}',
        width: 24,
        height: 24,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Icon(
          entry.isDirectory ? LucideIcons.folder : LucideIcons.file,
          size: 20,
          color: _mutedForeground,
        ),
      ),
    );
  }
}

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: context.l10n.sort,
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (context) => [
        PopupMenuItem(value: 'name', child: Text(context.l10n.sortByName)),
        PopupMenuItem(value: 'type', child: Text(context.l10n.sortByType)),
        PopupMenuItem(
            value: 'modified', child: Text(context.l10n.sortByModified)),
        PopupMenuItem(
            value: 'created', child: Text(context.l10n.sortByCreated)),
      ],
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0xE6FFFFFF),
          border: Border.all(color: const Color(0xCCFFFFFF)),
          borderRadius: BorderRadius.circular(7),
        ),
        child: const Icon(LucideIcons.arrowUpDown, size: 14),
      ),
    );
  }
}

String _sortModeLabel(BuildContext context, String sortMode) {
  return switch (sortMode) {
    'type' => context.l10n.sortByType,
    'modified' => context.l10n.sortByModified,
    'created' => context.l10n.sortByCreated,
    _ => context.l10n.sortByName,
  };
}

String _formatBytes(int? value) {
  if (value == null) {
    return '-';
  }
  if (value < 1024) {
    return '$value B';
  }
  final kb = value / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  }
  final mb = kb / 1024;
  if (mb < 1024) {
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  }
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(gb < 10 ? 1 : 0)} GB';
}

String _formatEntryDate(DateTime? value) {
  if (value == null) {
    return '-';
  }
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}.${two(local.month)}.${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

String _formatTmuxActivity(RemoteTmuxSession session) {
  final windows = '${session.windows} window${session.windows == 1 ? '' : 's'}';
  if (session.attachedClients > 0) {
    return '$windows · attached ${session.attachedClients}';
  }
  final activity = _formatEntryDate(session.lastActivityAt);
  return activity == '-' ? windows : '$windows · $activity';
}

List<LiveSshSession> _uniqueLiveServerSessions(
  List<LiveSshSession> sessions,
  LiveSshSession? activeSession,
) {
  final unique = <Object, LiveSshSession>{};
  for (final session in sessions) {
    final current = unique[session.client];
    if (current == null || session.id == activeSession?.id) {
      unique[session.client] = session;
    }
  }
  return unique.values.toList();
}

List<LiveSshSession> _liveSessionsForClient(
  List<LiveSshSession> sessions,
  LiveSshSession serverSession,
) {
  return sessions
      .where((session) => session.client == serverSession.client)
      .toList();
}

List<LiveSshSession> _liveSessionsForConnection(
  List<LiveSshSession> sessions,
  SavedConnection connection,
) {
  return sessions
      .where(
        (session) =>
            !session.isClosed &&
            session.connection.fingerprint == connection.fingerprint,
      )
      .toList();
}

int _workspaceCountForClient(
  List<LiveSshSession> sessions,
  LiveSshSession serverSession,
) {
  return sessions
      .where((session) => session.client == serverSession.client)
      .length;
}

String _workspaceSessionTitle(AppState state, LiveSshSession session) {
  final customName = state.sessionCustomName(session);
  if (customName != null) {
    return customName;
  }
  final tmuxName = session.selectedTmuxSessionName;
  final tag = tmuxName == null ? null : state.tmuxSessionTag(session, tmuxName);
  if (tag != null) {
    return '#${tag.label}';
  }
  return _compactPathDisplay(session.currentPath);
}

String _workspaceSessionSubtitle(
  SeilLocalizations l10n,
  AppState state,
  LiveSshSession session,
) {
  final tmuxName = session.selectedTmuxSessionName;
  final tmuxPart = tmuxName == null || tmuxName.isEmpty
      ? l10n.tmuxSelectionPending
      : l10n.tmuxSessionLabel;
  return '$tmuxPart · ${_compactPathDisplay(state.sessionLabel(session))}';
}

class FilePreviewScreen extends StatefulWidget {
  const FilePreviewScreen({
    super.key,
    required this.session,
    required this.entry,
    required this.onSaved,
  });

  final LiveSshSession session;
  final RemoteFileEntry entry;
  final Future<void> Function() onSaved;

  @override
  State<FilePreviewScreen> createState() => _FilePreviewScreenState();
}

class _FilePreviewScreenState extends State<FilePreviewScreen> {
  late final Future<_LoadedPreview> previewFuture;
  final editor = TextEditingController();
  bool editing = false;
  bool saving = false;
  bool openingExternal = false;
  bool downloading = false;
  RemoteTextFile? textFile;

  @override
  void initState() {
    super.initState();
    previewFuture = _loadPreview().then((preview) {
      if (mounted) {
        setState(() {});
      }
      return preview;
    });
  }

  @override
  void dispose() {
    editor.dispose();
    super.dispose();
  }

  Future<_LoadedPreview> _loadPreview() async {
    if (widget.entry.previewKind == FilePreviewKind.image) {
      final bytes = await widget.session.downloadBytes(widget.entry.path);
      return _LoadedPreview(imageBytes: bytes);
    }
    if (widget.entry.previewKind == FilePreviewKind.download) {
      return const _LoadedPreview(
        unsupportedPreview: true,
      );
    }
    final file = await widget.session.readTextFile(widget.entry.path);
    textFile = file;
    editor.text = file.content;
    return _LoadedPreview(textFile: file);
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = widget.entry.previewKind == FilePreviewKind.code ||
        widget.entry.previewKind == FilePreviewKind.markdown;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Expanded(
              child: Text(
                widget.entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (canEdit) ...[
              const SizedBox(width: 8),
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed:
                    saving ? null : () => setState(() => editing = !editing),
                icon: Icon(
                  editing ? LucideIcons.eye : LucideIcons.pencil,
                  size: 15,
                ),
                label: Text(editing ? context.l10n.preview : context.l10n.edit),
              ),
            ],
          ],
        ),
        actions: [
          if (editing)
            _ToolbarButton(
              icon: LucideIcons.save,
              tooltip: context.l10n.save,
              onPressed: saving ? null : () => unawaited(_save()),
            ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<_LoadedPreview>(
          future: previewFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _UnavailableFilePreview(
                message: snapshot.error.toString(),
                opening: openingExternal,
                downloading: downloading,
                onOpen: _openExternally,
                onDownload: _download,
              );
            }
            final preview = snapshot.data!;
            if (preview.imageBytes != null) {
              return InteractiveViewer(
                minScale: 0.5,
                maxScale: 5,
                child: Center(
                  child: Image.memory(
                    preview.imageBytes!,
                    fit: BoxFit.contain,
                  ),
                ),
              );
            }
            if (preview.unsupportedPreview) {
              return _UnavailableFilePreview(
                message: context.l10n.filePreviewUnsupported,
                opening: openingExternal,
                downloading: downloading,
                onOpen: _openExternally,
                onDownload: _download,
              );
            }
            final file = textFile ?? preview.textFile!;
            if (editing) {
              return _CodeEditor(
                controller: editor,
                language: file.language,
              );
            }
            if (file.previewKind == FilePreviewKind.markdown) {
              return Markdown(data: file.content);
            }
            return _HighlightedCodeView(file: file);
          },
        ),
      ),
    );
  }

  Future<void> _openExternally() async {
    if (openingExternal) {
      return;
    }
    setState(() => openingExternal = true);
    try {
      await _openRemoteFileExternally(
        session: widget.session,
        entry: widget.entry,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.openFileFailed(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => openingExternal = false);
      }
    }
  }

  Future<void> _download() async {
    if (downloading) {
      return;
    }
    setState(() => downloading = true);
    final downloadTitle = context.l10n.download;
    final downloadedMessage = context.l10n.fileDownloaded;
    try {
      final bytes = await widget.session.downloadBytes(widget.entry.path);
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: downloadTitle,
        fileName: widget.entry.name,
        bytes: bytes,
      );
      if (savedPath != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(downloadedMessage)),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.downloadFailed(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => downloading = false);
      }
    }
  }

  Future<void> _save() async {
    if (saving) {
      return;
    }
    setState(() => saving = true);
    try {
      await widget.session.writeTextFile(widget.entry.path, editor.text);
      await widget.onSaved();
      textFile = RemoteTextFile(
        path: textFile?.path ?? widget.entry.path,
        name: textFile?.name ?? widget.entry.name,
        content: editor.text,
        truncated: false,
        size: editor.text.length,
        modifiedAt: DateTime.now().toUtc(),
        createdAt: textFile?.createdAt,
        previewKind: textFile?.previewKind ?? widget.entry.previewKind,
        typeLabel: textFile?.typeLabel ?? widget.entry.typeLabel,
        language: textFile?.language ?? widget.entry.language,
      );
      if (mounted) {
        setState(() {
          editing = false;
          saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.fileSaved)),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.saveFailed(error))),
        );
      }
    }
  }
}

class _LoadedPreview {
  const _LoadedPreview({
    this.textFile,
    this.imageBytes,
    this.unsupportedPreview = false,
  });

  final RemoteTextFile? textFile;
  final Uint8List? imageBytes;
  final bool unsupportedPreview;
}

class _UnavailableFilePreview extends StatelessWidget {
  const _UnavailableFilePreview({
    required this.message,
    required this.opening,
    required this.downloading,
    required this.onOpen,
    required this.onDownload,
  });

  final String message;
  final bool opening;
  final bool downloading;
  final VoidCallback onOpen;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                LucideIcons.fileQuestionMark,
                size: 28,
                color: _mutedForeground,
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _mutedForeground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: opening || downloading ? null : onOpen,
                    icon: opening
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(LucideIcons.externalLink, size: 16),
                    label: Text(context.l10n.openNow),
                  ),
                  OutlinedButton.icon(
                    onPressed: opening || downloading ? null : onDownload,
                    icon: downloading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(LucideIcons.download, size: 16),
                    label: Text(context.l10n.download),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CodeEditor extends StatelessWidget {
  const _CodeEditor({required this.controller, required this.language});

  final TextEditingController controller;
  final String? language;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      expands: true,
      maxLines: null,
      minLines: null,
      keyboardType: TextInputType.multiline,
      style: const TextStyle(
        fontFamily: _terminalFontFamily,
        fontFamilyFallback: ['FiraCodeNerdFontMono', 'monospace'],
        fontSize: 12,
        height: 1.35,
      ),
      decoration: InputDecoration(
        border: InputBorder.none,
        contentPadding: const EdgeInsets.all(12),
        hintText: language == null
            ? context.l10n.enterContent
            : context.l10n.editLanguage(language!),
      ),
    );
  }
}

class _HighlightedCodeView extends StatelessWidget {
  const _HighlightedCodeView({required this.file});

  final RemoteTextFile file;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: TextSelectionTheme(
        data: const TextSelectionThemeData(
          selectionColor: _terminalSelection,
          selectionHandleColor: _terminalSelectionHandle,
        ),
        child: SelectableText.rich(
          TextSpan(
            style: const TextStyle(
              color: _warpInk,
              fontFamily: _terminalFontFamily,
              fontFamilyFallback: ['FiraCodeNerdFontMono', 'monospace'],
              fontSize: 12,
              height: 1.35,
            ),
            children: _codeHighlightSpans(file.content, file.language),
          ),
        ),
      ),
    );
  }
}

List<TextSpan> _codeHighlightSpans(String source, String? language) {
  final keywords = _keywordsForLanguage(language);
  if (source.isEmpty || keywords.isEmpty && language != 'markdown') {
    return [TextSpan(text: source)];
  }

  final spans = <TextSpan>[];
  final pattern = language == 'markdown'
      ? RegExp(r'(^#{1,6}\s.*$|`[^`]*`|\*\*[^*]+\*\*)', multiLine: true)
      : RegExp(
          r'''(#.*$|//.*$|".*?"|'.*?'|\b[A-Za-z_][A-Za-z0-9_.]*\b)''',
          multiLine: true,
        );
  var index = 0;
  for (final match in pattern.allMatches(source)) {
    if (match.start > index) {
      spans.add(TextSpan(text: source.substring(index, match.start)));
    }
    final token = match.group(0) ?? '';
    spans.add(TextSpan(text: token, style: _styleForToken(token, keywords)));
    index = match.end;
  }
  if (index < source.length) {
    spans.add(TextSpan(text: source.substring(index)));
  }
  return spans;
}

Set<String> _keywordsForLanguage(String? language) {
  return switch (language?.toLowerCase()) {
    'py' || 'python' => const {
        'and',
        'as',
        'class',
        'def',
        'elif',
        'else',
        'except',
        'False',
        'for',
        'from',
        'if',
        'import',
        'in',
        'is',
        'None',
        'not',
        'or',
        'return',
        'True',
        'try',
        'while',
        'with',
      },
    'r' => const {
        'function',
        'if',
        'else',
        'for',
        'while',
        'repeat',
        'in',
        'next',
        'break',
        'TRUE',
        'FALSE',
        'NULL',
      },
    'sh' || 'bash' || 'shell' => const {
        'case',
        'do',
        'done',
        'elif',
        'else',
        'esac',
        'fi',
        'for',
        'function',
        'if',
        'in',
        'then',
        'while',
      },
    _ => const <String>{},
  };
}

TextStyle _styleForToken(String token, Set<String> keywords) {
  if (token.startsWith('#') || token.startsWith('//')) {
    return const TextStyle(color: Color(0xFF64748B));
  }
  if (token.startsWith('"') ||
      token.startsWith("'") ||
      token.startsWith('`') ||
      token.startsWith('**')) {
    return const TextStyle(color: Color(0xFF0F766E));
  }
  if (keywords.contains(token)) {
    return const TextStyle(
      color: Color(0xFF2563EB),
      fontWeight: FontWeight.w700,
    );
  }
  return const TextStyle();
}

class FullTextScreen extends StatelessWidget {
  const FullTextScreen({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.fullText),
        actions: [
          _ToolbarButton(
            icon: LucideIcons.copy,
            tooltip: context.l10n.copyAll,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.l10n.copiedAllText)),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: TextSelectionTheme(
            data: const TextSelectionThemeData(
              selectionColor: _terminalSelection,
              selectionHandleColor: _terminalSelectionHandle,
            ),
            child: SelectableText(
              text.isEmpty ? context.l10n.noTerminalText : text,
              style: const TextStyle(
                fontFamily: _terminalFontFamily,
                fontFamilyFallback: [
                  'FiraCodeNerdFontMono',
                  'monospace',
                ],
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: _CompactGlassButton(
          height: 32,
          padding: EdgeInsets.zero,
          icon: icon,
          onPressed: onPressed,
        ),
      ),
    );
  }
}
