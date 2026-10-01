import 'dart:async';
import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../features/auth/presentation/providers/auth_provider.dart';
import '../features/splash/splash_view.dart';
import 'supabase/supabase_client.dart';
import 'utils/app_log.dart';

/// Root of the widget tree. Shows the animated [SplashView] while the app
/// boots (env, Supabase, first auth resolution), surfaces a Retry state if
/// that fails, then fades into [ITulodApp] once everything is ready.
class AppRoot extends ConsumerStatefulWidget {
  const AppRoot({super.key});

  @override
  ConsumerState<AppRoot> createState() => _AppRootState();
}

enum _Phase { loading, error, ready }

class _AppRootState extends ConsumerState<AppRoot> {
  /// How long the animated splash stays on screen once it is *actually
  /// painted* — in debug builds the engine's first frame can lag the widget
  /// build by a second or more, so we measure from the real first frame.
  static const _minVisible = Duration(milliseconds: 1900);

  /// Hard ceiling on any single boot step, so we can't hang forever.
  static const _stepTimeout = Duration(seconds: 12);

  _Phase _phase = _Phase.loading;
  bool _finishing = false;
  String _errorMessage = '';

  bool _bootDone = false;
  bool _minVisiblePassed = false;
  bool _firstFrameSeen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addTimingsCallback(_onFrameTimings);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeTimingsCallback(_onFrameTimings);
    super.dispose();
  }

  /// Fires after every rendered frame. The first call means the splash is
  /// genuinely on screen — start the minimum-visible clock from here.
  void _onFrameTimings(List<FrameTiming> timings) {
    if (_firstFrameSeen) return;
    _firstFrameSeen = true;
    WidgetsBinding.instance.removeTimingsCallback(_onFrameTimings);
    Future<void>.delayed(_minVisible, () {
      _minVisiblePassed = true;
      _maybeFinish();
    });
  }

  Future<void> _bootstrap() async {
    if (_phase != _Phase.loading || _finishing) {
      setState(() {
        _phase = _Phase.loading;
        _finishing = false;
        _bootDone = false;
      });
    }

    try {
      // 1. Environment — non-fatal, there are compiled-in fallbacks.
      try {
        await dotenv.load(fileName: '.env');
      } catch (e, s) {
        AppLog.warn('AppRoot: .env not loaded, using defaults', e, s);
      }

      // 2. Supabase client (safe to re-run on retry).
      await SupabaseConfig.initialize().timeout(_stepTimeout);

      // 3. First auth resolution — wait for a definite answer.
      final auth = ref.read(authNotifierProvider.notifier);
      await auth.bootstrapped.timeout(_stepTimeout);

      // A signed-in user whose profile could not be loaded (offline) is a
      // real failure the user can retry — as opposed to simply being logged
      // out, which just routes to the login screen.
      final state = ref.read(authNotifierProvider);
      if (state.status == AuthStatus.unauthenticated &&
          state.errorMessage != null &&
          SupabaseConfig.hasSession) {
        throw Exception(state.errorMessage);
      }

      _bootDone = true;
      _maybeFinish();
    } catch (e, s) {
      AppLog.warn('AppRoot: startup failed', e, s);
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _errorMessage =
              "We couldn't connect. Check your internet connection and try again.";
        });
      }
    }
  }

  /// Hand off only once the boot has finished *and* the splash has been on
  /// screen long enough to be seen.
  void _maybeFinish() {
    if (!mounted || _finishing) return;
    if (_bootDone && _minVisiblePassed && _phase == _Phase.loading) {
      setState(() => _finishing = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == _Phase.ready) return const ITulodApp();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // Pin light so the splash looks the same regardless of system dark mode.
      theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
      home: SplashView(
        error: _phase == _Phase.error ? _errorMessage : null,
        onRetry: _bootstrap,
        finishing: _finishing,
        onFinished: () {
          if (mounted) setState(() => _phase = _Phase.ready);
        },
      ),
    );
  }
}
