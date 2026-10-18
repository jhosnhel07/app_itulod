import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants/app_strings.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';

/// Lets code deep in the navigation stack (e.g. the booking receipt screen,
/// right after it pops back to the dashboard) show a SnackBar without
/// needing a still-mounted local BuildContext.
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class ITulodApp extends ConsumerStatefulWidget {
  const ITulodApp({super.key});

  @override
  ConsumerState<ITulodApp> createState() => _ITulodAppState();
}

class _ITulodAppState extends ConsumerState<ITulodApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The phone switched light/dark — matters while no choice is saved.
  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final choice = ref.watch(themeChoiceProvider);
    final platform = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    if (applyPalette(resolveDark(choice, platform))) {
      // Widgets that read AppColors directly don't depend on Theme, so
      // rebuild everything once this frame is done.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) rebuildAllElements(context);
      });
    }

    return MaterialApp.router(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      themeAnimationDuration: Duration.zero,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      routerConfig: router,
    );
  }
}
