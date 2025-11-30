import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/app_env.dart';
import 'config/openai_config.dart';
import 'pages/company_gate.dart';
import 'pages/sign_in_page.dart';
import 'services/connectivity_service.dart';
import 'services/notification_service.dart';
import 'services/offline_actions_service.dart';
import 'services/offline_storage.dart';
import 'services/supabase_service.dart';
import 'theme/app_colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  await initializeDateFormatting('fr_CA');
  Intl.defaultLocale = 'fr_CA';

  AppEnv.assertIsConfigured();
  assert(OpenAIConfig.apiKey.isNotEmpty, 'Manque OPENAI_API_KEY dans .env');

  await Supa.init(
    url: AppEnv.supabaseUrl,
    anonKey: AppEnv.supabaseAnonKey,
  );

  await OfflineStorage.instance.init();
  await ConnectivityService.instance.init();
  await OfflineActionsService.instance.init();

  // Initialiser le service de notifications (Supabase uniquement)
  try {
    await NotificationService.instance.initialize();
  } catch (e) {
    debugPrint('⚠️ Service de notifications non initialisé: $e');
  }

  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    );
    final colorScheme = baseScheme.copyWith(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      surface: AppColors.surface,
      surfaceContainerHighest: AppColors.surfaceAlt,
      onSurface: Colors.black87,
      secondaryContainer: AppColors.tonalBackground,
      onSecondaryContainer: AppColors.tonalForeground,
      outline: AppColors.outline,
      outlineVariant: AppColors.tonalBorder,
      error: AppColors.danger,
      onError: Colors.white,
      errorContainer: AppColors.dangerPressed,
      onErrorContainer: Colors.white,
    );

    return MaterialApp(
      title: 'Logtek G&I',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: AppColors.surface,
        canvasColor: AppColors.surface,
        cardTheme: const CardThemeData(
          color: AppColors.surface,
          surfaceTintColor: AppColors.surface,
          elevation: 2,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.surface,
          foregroundColor: colorScheme.onSurface,
          elevation: 0,
          titleTextStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 20,
            color: Colors.black87,
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          indicatorColor: colorScheme.primary.withValues(alpha: 0.14),
          backgroundColor: AppColors.surface,
          labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: AppColors.surface,
          surfaceTintColor: Colors.transparent,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: ButtonStyle(
            textStyle: const WidgetStatePropertyAll(
              TextStyle(fontWeight: FontWeight.w600),
            ),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return AppColors.disabledBackground;
              }
              return null;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return AppColors.disabledForeground;
              }
              return null;
            }),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: ButtonStyle(
            textStyle: const WidgetStatePropertyAll(
              TextStyle(fontWeight: FontWeight.w600),
            ),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return AppColors.disabledForeground;
              }
              if (states.contains(WidgetState.pressed)) {
                return AppColors.primaryPressed;
              }
              if (states.contains(WidgetState.hovered)) {
                return AppColors.primaryHover;
              }
              return AppColors.primary;
            }),
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return AppColors.primaryPressed.withValues(alpha: 0.12);
              }
              if (states.contains(WidgetState.hovered)) {
                return AppColors.primaryHover.withValues(alpha: 0.08);
              }
              if (states.contains(WidgetState.focused)) {
                return AppColors.primary.withValues(alpha: 0.12);
              }
              return null;
            }),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: ButtonStyle(
            textStyle: const WidgetStatePropertyAll(
              TextStyle(fontWeight: FontWeight.w600),
            ),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return AppColors.disabledForeground;
              }
              if (states.contains(WidgetState.pressed)) {
                return AppColors.primaryPressed;
              }
              if (states.contains(WidgetState.hovered)) {
                return AppColors.primaryHover;
              }
              return AppColors.primary;
            }),
            side: WidgetStateProperty.resolveWith((states) {
              final color = states.contains(WidgetState.disabled)
                  ? AppColors.disabledForeground
                  : AppColors.outline;
              return BorderSide(color: color, width: 1.5);
            }),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return AppColors.disabledBackground;
              }
              return Colors.transparent;
            }),
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return AppColors.primaryPressed.withValues(alpha: 0.12);
              }
              if (states.contains(WidgetState.hovered)) {
                return AppColors.primaryHover.withValues(alpha: 0.06);
              }
              if (states.contains(WidgetState.focused)) {
                return AppColors.primary.withValues(alpha: 0.12);
              }
              return null;
            }),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.primary, width: 2),
          ),
        ),
        chipTheme: ChipThemeData(
          color: const WidgetStatePropertyAll(AppColors.surfaceAlt),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      ),
      home: AuthGate(),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('fr', 'CA'),
      ],
      debugShowCheckedModeBanner: false,
    );
  }
}

class AuthGate extends StatelessWidget {
  AuthGate({super.key});
  final _auth = Supabase.instance.client.auth;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _auth.onAuthStateChange,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final session = _auth.currentSession ?? snap.data?.session;
        if (session != null) {
          return const CompanyGatePage();
        }
        return const SignInPage();
      },
    );
  }
}
