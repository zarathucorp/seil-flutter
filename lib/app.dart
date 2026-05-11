import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'core/localization/seil_localizations.dart';
import 'core/settings/app_settings_repository.dart';
import 'core/storage/local_database.dart';
import 'core/storage/secure_vault.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_repository.dart';
import 'features/auth/login_screen.dart';
import 'features/connections/connection_repository.dart';
import 'features/connections/connection_list_screen.dart';
import 'features/connections/host_key_repository.dart';
import 'features/sessions/ssh_session_service.dart';
import 'features/sessions/workspace_screen.dart';
import 'shared/app_state.dart';

class SeilMobileApp extends StatefulWidget {
  const SeilMobileApp({super.key});

  @override
  State<SeilMobileApp> createState() => _SeilMobileAppState();
}

class _SeilMobileAppState extends State<SeilMobileApp>
    with WidgetsBindingObserver {
  late final SecureVault vault;
  late final LocalDatabase database;
  late final AuthRepository authRepository;
  late final ConnectionRepository connectionRepository;
  late final HostKeyRepository hostKeyRepository;
  late final AppSettingsRepository settingsRepository;
  late final SshSessionService sshSessionService;
  late final AppState state;
  bool ready = false;
  Object? initError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      vault = const SecureVault();
      database = LocalDatabase(vault);
      await database.open();
      authRepository = AuthRepository(database);
      connectionRepository = ConnectionRepository(database, vault);
      hostKeyRepository = HostKeyRepository(database);
      settingsRepository = AppSettingsRepository(database);
      sshSessionService = DartSshSessionService();
      state = AppState(
        authRepository: authRepository,
        connectionRepository: connectionRepository,
        hostKeyRepository: hostKeyRepository,
        settingsRepository: settingsRepository,
        sshSessionService: sshSessionService,
      );
      await state.initialize();
      setState(() => ready = true);
    } catch (error) {
      setState(() => initError = error);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (ready) {
      database.close();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (!ready) {
      return;
    }
    if (lifecycleState == AppLifecycleState.resumed) {
      unawaited(state.pingLiveSessions());
      unawaited(state.reconnectClosedSessions());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ShadApp.custom(
      theme: buildSeilShadTheme(),
      appBuilder: (context) {
        Widget buildMaterialApp() {
          return MaterialApp(
            title: 'Seil',
            debugShowCheckedModeBanner: false,
            theme: buildSeilTheme(),
            locale:
                ready ? _localeForLanguageCode(state.appLanguageCode) : null,
            supportedLocales: _supportedLocales,
            localizationsDelegates: const [
              SeilLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalShadLocalizations.delegate,
            ],
            home: _buildHome(),
            builder: (context, child) => ShadAppBuilder(
              child: ready
                  ? _AppErrorNotifier(state: state, child: child!)
                  : child!,
            ),
          );
        }

        if (!ready) {
          return buildMaterialApp();
        }
        return AnimatedBuilder(
          animation: state,
          builder: (context, _) => buildMaterialApp(),
        );
      },
    );
  }

  Widget _buildHome() {
    if (initError != null) {
      return InitErrorScreen(error: initError!);
    }

    if (!ready) {
      return const PopScope(
        canPop: false,
        child: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        if (state.currentUser == null) {
          return LoginScreen(state: state);
        }

        if (state.activeSession != null) {
          return WorkspaceScreen(state: state);
        }

        return ConnectionListScreen(state: state);
      },
    );
  }
}

const _supportedLocales = [
  Locale('en'),
  Locale('ko'),
  Locale('ja'),
  Locale('zh'),
];

Locale? _localeForLanguageCode(String languageCode) {
  if (languageCode == AppSettingsRepository.systemLanguageCode) {
    return null;
  }
  return Locale(languageCode);
}

class _AppErrorNotifier extends StatefulWidget {
  const _AppErrorNotifier({required this.state, required this.child});

  final AppState state;
  final Widget child;

  @override
  State<_AppErrorNotifier> createState() => _AppErrorNotifierState();
}

class _AppErrorNotifierState extends State<_AppErrorNotifier> {
  int lastErrorSerial = 0;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_showErrorIfNeeded);
  }

  @override
  void didUpdateWidget(covariant _AppErrorNotifier oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(_showErrorIfNeeded);
      widget.state.addListener(_showErrorIfNeeded);
      lastErrorSerial = 0;
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_showErrorIfNeeded);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  void _showErrorIfNeeded() {
    final message = widget.state.errorMessage;
    if (!mounted ||
        message == null ||
        !widget.state.errorShowsPopup ||
        widget.state.errorSerial == lastErrorSerial) {
      lastErrorSerial = widget.state.errorSerial;
      if (mounted && message != null && !widget.state.errorShowsPopup) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
      return;
    }
    lastErrorSerial = widget.state.errorSerial;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      final media = MediaQuery.of(context);
      final topOffset = media.padding.top + kToolbarHeight + 64;
      final bottomMargin =
          (media.size.height - topOffset).clamp(12.0, media.size.height);
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(
            12,
            0,
            12,
            bottomMargin,
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    });
  }
}

class InitErrorScreen extends StatelessWidget {
  const InitErrorScreen({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.initializingFailed,
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 12),
                Text(error.toString()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
