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

class _OfficeGossipAppState extends State<OfficeGossipApp> {
  final AuthBloc _authBloc = sl<AuthBloc>()..add(const AuthStarted());
  late final AppRouter _appRouter = AppRouter(authBloc: _authBloc);

  @override
  void dispose() {
    _appRouter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider.value(
        value: _authBloc,
        child: MaterialApp.router(
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
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF9A84FF),
                brightness: Brightness.dark),
          ),
          routerConfig: _appRouter.router,
        ),
      );
}
