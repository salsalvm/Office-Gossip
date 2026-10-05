import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/presentation/bloc/auth_bloc.dart';
import '../../core/presentation/widgets/office_gossip_mark.dart';
import '../../features/sign_in/presentation/pages/sign_in_page.dart';
import '../../features/sign_up/presentation/pages/sign_up_page.dart';
import '../../features/forgot_password/presentation/pages/forgot_password_page.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';
import '../../features/people/presentation/bloc/people_bloc.dart';
import '../../features/people/presentation/pages/people_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/splash/presentation/pages/splash_page.dart';
import '../../core/di/injection_container.dart';

class AppRouter {
  AppRouter({required AuthBloc authBloc})
      : this._(authBloc, _AuthRefresh(authBloc), DateTime.now());

  AppRouter._(AuthBloc authBloc, _AuthRefresh refresh, DateTime startedAt)
      : _refresh = refresh,
        router = GoRouter(
          initialLocation: '/splash',
          refreshListenable: refresh,
          redirect: (context, state) async {
            final auth = authBloc.state;
            if (auth.status == AuthStatus.checking) {
              return state.matchedLocation == '/splash' ? null : '/splash';
            }
            if (state.matchedLocation == '/splash') {
              final remaining = const Duration(seconds: 1) -
                  DateTime.now().difference(startedAt);
              if (remaining > Duration.zero) {
                await Future<void>.delayed(remaining);
              }
            }
            final publicRoute = const {
              '/sign-in',
              '/sign-up',
              '/forgot-password'
            }.contains(state.matchedLocation);
            final atSplash = state.matchedLocation == '/splash';
            if (auth.status == AuthStatus.authenticated &&
                (publicRoute || atSplash)) {
              return '/dashboard';
            }
            if (auth.status != AuthStatus.authenticated && atSplash) {
              return '/sign-in';
            }
            if (auth.status != AuthStatus.authenticated && !publicRoute) {
              return '/sign-in';
            }
            return null;
          },
          routes: [
            GoRoute(
                path: '/splash',
                builder: (context, state) => const SplashPage()),
            GoRoute(
                path: '/sign-in',
                builder: (context, state) => const SignInPage()),
            GoRoute(
                path: '/sign-up',
                builder: (context, state) => const SignUpPage()),
            GoRoute(
                path: '/forgot-password',
                builder: (context, state) => ForgotPasswordPage(
                    initialEmail: state.extra as String? ?? '')),
            GoRoute(path: '/home', redirect: (context, state) => '/dashboard'),
            StatefulShellRoute.indexedStack(
              builder: (context, state, navigationShell) =>
                  _MemberShell(navigationShell: navigationShell),
              branches: [
                StatefulShellBranch(routes: [
                  GoRoute(
                      path: '/dashboard',
                      builder: (context, state) => const DashboardPage())
                ]),
                StatefulShellBranch(routes: [
                  GoRoute(
                      path: '/trending',
                      builder: (context, state) =>
                          const DashboardPage(trending: true))
                ]),
                StatefulShellBranch(routes: [
                  GoRoute(
                      path: '/people',
                      builder: (context, state) => BlocProvider(
                          create: (_) =>
                              sl<PeopleBloc>()..add(const PeopleRequested()),
                          child: const PeoplePage()))
                ]),
                StatefulShellBranch(routes: [
                  GoRoute(
                      path: '/profile',
                      builder: (context, state) => const ProfilePage())
                ]),
              ],
            ),
          ],
        );

  final _AuthRefresh _refresh;
  final GoRouter router;
  void dispose() {
    router.dispose();
    _refresh.dispose();
  }
}

class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(AuthBloc bloc) {
    _subscription = bloc.stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription<AuthState> _subscription;
  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

class _MemberShell extends StatelessWidget {
  const _MemberShell({required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  static const _destinations = [
    _NavDestination(Icons.home_outlined, Icons.home_rounded, 'Home'),
    _NavDestination(Icons.local_fire_department_outlined,
        Icons.local_fire_department_rounded, 'Trending'),
    _NavDestination(
        Icons.people_outline_rounded, Icons.people_rounded, 'People'),
    _NavDestination(
        Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF8F7FC),
        appBar: AppBar(
            backgroundColor: const Color(0xFFF8F7FC),
            title: const Row(children: [
              OfficeGossipMark(size: 36),
              SizedBox(width: 10),
              Text('Office Gossip',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ]),
            actions: [
              IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.notifications_outlined),
                  tooltip: 'Notifications')
            ]),
        body: navigationShell,
        bottomNavigationBar: _MemberNavBar(
          destinations: _destinations,
          currentIndex: navigationShell.currentIndex,
          onSelected: (index) => navigationShell.goBranch(index,
              initialLocation: index == navigationShell.currentIndex),
        ),
      );
}

class _NavDestination {
  const _NavDestination(this.icon, this.selectedIcon, this.label);
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class _MemberNavBar extends StatelessWidget {
  const _MemberNavBar({
    required this.destinations,
    required this.currentIndex,
    required this.onSelected,
  });
  final List<_NavDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 10),
        child: Container(
          height: 64,
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFEDEBF4)),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFF5B45C9).withValues(alpha: .10),
                  blurRadius: 24,
                  offset: const Offset(0, 8)),
            ],
          ),
          child: Row(children: [
            for (var i = 0; i < destinations.length; i++)
              Expanded(
                flex: i == currentIndex ? 5 : 3,
                child: _NavItem(
                  destination: destinations[i],
                  selected: i == currentIndex,
                  onTap: () => onSelected(i),
                ),
              ),
          ]),
        ),
      );
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });
  final _NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  static const _accent = Color(0xFF7357E8);

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        button: true,
        label: destination.label,
        child: InkResponse(
          onTap: onTap,
          radius: 36,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.symmetric(
                    horizontal: selected ? 14 : 10, vertical: 9),
                decoration: BoxDecoration(
                  color:
                      selected ? const Color(0xFFEFEBFF) : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(selected ? destination.selectedIcon : destination.icon,
                      size: 22,
                      color: selected ? _accent : const Color(0xFF9A98A6)),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: selected
                        ? Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(destination.label,
                                maxLines: 1,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _accent)),
                          )
                        : const SizedBox.shrink(),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}
