import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/presentation/bloc/auth_bloc.dart';
import '../../core/presentation/widgets/initials_avatar.dart';
import '../../core/presentation/widgets/office_gossip_mark.dart';
import '../../features/sign_in/presentation/pages/sign_in_page.dart';
import '../../features/sign_up/presentation/pages/sign_up_page.dart';
import '../../features/forgot_password/presentation/pages/forgot_password_page.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';
import '../../features/people/presentation/bloc/people_bloc.dart';
import '../../features/people/presentation/pages/people_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/splash/presentation/pages/splash_page.dart';
import '../../features/webpage/domain/webpage_type.dart';
import '../../features/webpage/presentation/pages/webpage_page.dart';
import '../../core/constants/app_links.dart';
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
              '/forgot-password',
            }.contains(state.matchedLocation);
            // Help/privacy/terms open for everyone and never redirect.
            if (state.matchedLocation.startsWith('${WebpagePage.basePath}/')) {
              return null;
            }
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
            GoRoute(
              path: WebpagePage.routePath,
              redirect: (context, state) =>
                  WebpageType.fromPath(state.pathParameters['page']) == null
                      ? '/dashboard'
                      : null,
              builder: (context, state) => WebpagePage(
                type: WebpageType.fromPath(state.pathParameters['page'])!,
                domain:
                    state.uri.queryParameters['domain'] ?? AppLinks.webDomain,
                title: state.uri.queryParameters['title'],
              ),
            ),
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
        appBar: _MemberAppBar(
          tabLabel: _destinations[navigationShell.currentIndex].label,
          onProfile: () => navigationShell.goBranch(3),
        ),
        body: navigationShell,
        bottomNavigationBar: _MemberNavBar(
          destinations: _destinations,
          currentIndex: navigationShell.currentIndex,
          onSelected: (index) => navigationShell.goBranch(index,
              initialLocation: index == navigationShell.currentIndex),
        ),
      );
}

class _MemberAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _MemberAppBar({required this.tabLabel, required this.onProfile});
  final String tabLabel;
  final VoidCallback onProfile;

  static const _ink = Color(0xFF1F1D2B);
  static const _accent = Color(0xFF7357E8);
  static const _muted = Color(0xFF8D8A9B);
  static const _border = Color(0xFFECEAF2);

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final user = context.select((AuthBloc bloc) => bloc.state.session?.user);
    final community = user?.company?.name ?? 'Community';
    final name = user == null || user.name.isEmpty ? '?' : user.name;

    return Material(
      color: const Color(0xFFF8F7FC),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: preferredSize.height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              const OfficeGossipMark(size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text.rich(
                      TextSpan(children: [
                        TextSpan(text: 'office'),
                        TextSpan(
                            text: 'gossip', style: TextStyle(color: _accent)),
                      ]),
                      style: TextStyle(
                        fontSize: 19,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.8,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text('$community · $tabLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _muted)),
                  ],
                ),
              ),
              _CircleAction(
                tooltip: 'Notifications',
                onTap: () => ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                      const SnackBar(content: Text('You’re all caught up.'))),
                child: Stack(clipBehavior: Clip.none, children: [
                  const Icon(Icons.notifications_none_rounded,
                      size: 22, color: _ink),
                  Positioned(
                    right: 1,
                    top: 1,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5484D),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Profile',
                child: GestureDetector(
                  onTap: onProfile,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _accent.withValues(alpha: .35)),
                    ),
                    child: InitialsAvatar(name: name, size: 36),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.tooltip,
    required this.onTap,
    required this.child,
  });
  final String tooltip;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.white,
          shape: const CircleBorder(
              side: BorderSide(color: _MemberAppBar._border)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(dimension: 42, child: Center(child: child)),
          ),
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
