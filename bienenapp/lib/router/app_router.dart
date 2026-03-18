import 'package:go_router/go_router.dart';
import '../screens/home_screen.dart';
import '../screens/login_screen.dart';
import '../screens/hive_screen.dart';
import '../screens/volk_screen.dart';

// GoRouter configuration
final appRouter = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(
      path: '/home',
      builder: (context, state) =>
          const HomeScreen(title: 'Your Hive Overview'),
    ),
    GoRoute(
      path: '/Hive',
      builder: (context, state) {
        final hiveId = state.uri.queryParameters['id'] ?? 'Unknown';
        return HiveScreen(id: hiveId);
      },
    ),
    GoRoute(
      path: '/volk',
      builder: (context, state) {
        final volkId = state.uri.queryParameters['volk_id'] ?? 'Unknown';
        final hiveId = state.uri.queryParameters['hive_id'] ?? 'Unknown';
        return VolkScreen(hiveId: hiveId, volkId: volkId);
      },
    ),
  ],
);
