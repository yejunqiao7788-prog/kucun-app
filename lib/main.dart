import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/env.dart';
import 'core/l10n.dart';
import 'design/tokens.dart';
import 'design/theme.dart';
import 'screens/auth/login_screen.dart';
import 'shell/root_shell.dart';
import 'state/app_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final AppState state = await AppState.bootstrap();
  runApp(TorgseekApp(state: state));
}

class TorgseekApp extends StatelessWidget {
  const TorgseekApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>.value(
      value: state,
      child: Consumer<AppState>(
        builder: (BuildContext context, AppState app, Widget? _) {
          return MaterialApp(
            title: Env.appName,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: switch (app.themeChoice) {
              ThemeChoice.system => ThemeMode.system,
              ThemeChoice.light => ThemeMode.light,
              ThemeChoice.dark => ThemeMode.dark,
            },
            // null = 跟随系统；用户显式选过语言后才固定。
            locale: app.localeOverride,
            supportedLocales: L10n.supportedLocales,
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const AuthGate(),
          );
        },
      ),
    );
  }
}

/// 三态入口：启动占位 → 未登录进登录页 → 已登录进外壳。
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    if (app.booting) return const _Splash();
    if (!app.signedIn) return const LoginScreen();
    return const RootShell();
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[AppInk.dashboard, AppInk.ai],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(Icons.inventory_2_rounded,
                    color: Colors.white, size: 38),
              ),
              const SizedBox(height: 18),
              const Text(
                Env.appName,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: AppType.title,
                  fontWeight: AppType.heavy,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
