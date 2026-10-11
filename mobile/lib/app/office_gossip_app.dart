import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/auth/presentation/bloc/auth_bloc.dart';
import '../core/di/injection_container.dart';
import 'router/app_router.dart';

class OfficeGossipApp extends StatefulWidget {
  const OfficeGossipApp({super.key});

  @override
  State<OfficeGossipApp> createState() => _OfficeGossipAppState();
}

class _OfficeGossipAppState extends State<OfficeGossipApp>
    with WidgetsBindingObserver {
  static const _pendingPollInterval = Duration(seconds: 30);

  final AuthBloc _authBloc = sl<AuthBloc>()..add(const AuthStarted());
  late final AppRouter _appRouter = AppRouter(authBloc: _authBloc);
  Timer? _pendingPoll;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Admin approval happens elsewhere, so a pending member polls until it lands.
    _pendingPoll = Timer.periodic(_pendingPollInterval, (_) {
      final user = _authBloc.state.session?.user;
      if (_foreground && user != null && user.companyRequestPending) {
        _authBloc.add(const AuthUserRefreshRequested());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _authBloc.add(const AuthUserRefreshRequested());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pendingPoll?.cancel();
    _appRouter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider.value(
        value: _authBloc,
        child: BlocListener<AuthBloc, AuthState>(
          listenWhen: (previous, current) =>
              previous.session != null && current.session == null,
          listener: (_, __) => appMessengerKey.currentState?.clearSnackBars(),
          child: MaterialApp.router(
            scaffoldMessengerKey: appMessengerKey,
            title: 'Office Gossip',
            debugShowCheckedModeBanner: false,
            themeMode: ThemeMode.light,
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: const ColorScheme.light(
                primary: Color(0xFF7357E8),
                onPrimary: Colors.white,
                secondary: Color(0xFF7357E8),
                surface: Colors.white,
                onSurface: Color(0xFF111111),
              ),
              scaffoldBackgroundColor: Colors.white,
              appBarTheme: const AppBarTheme(
                backgroundColor: Colors.white,
                foregroundColor: Color(0xFF111111),
                surfaceTintColor: Colors.transparent,
              ),
              cardTheme: const CardThemeData(color: Colors.white),
            ),
            routerConfig: _appRouter.router,
          ),
        ),
      );
}
