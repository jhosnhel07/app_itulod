import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants/app_strings.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

/// Lets code deep in the navigation stack (e.g. the booking receipt screen,
/// right after it pops back to the dashboard) show a SnackBar without
/// needing a still-mounted local BuildContext.
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class ITulodApp extends ConsumerWidget {
  const ITulodApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      routerConfig: router,
    );
  }
}
