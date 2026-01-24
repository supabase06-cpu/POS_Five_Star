import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'providers/auth_provider.dart';
import 'services/realtime_service.dart';
import 'services/printer_service.dart';
import 'services/image_cache_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

late AuthProvider globalAuthProvider;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Suppress accessibility errors on Windows
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exception.toString().contains('accessibility_plugin') ||
        details.exception.toString().contains('viewId') ||
        details.exception.toString().contains('FlutterViewId')) {
      // Ignore accessibility errors - they're Windows Flutter framework bugs
      return;
    }
    FlutterError.presentError(details);
  };
  
  // Load environment variables first
  await dotenv.load(fileName: ".env");
  
  // Initialize Supabase BEFORE anything else
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );
  
  // Create AuthProvider AFTER Supabase is initialized
  globalAuthProvider = AuthProvider(Supabase.instance.client);
  
  // Wait for auth to check session
  await globalAuthProvider.waitForInitialization();
  
  // Initialize printer service globally
  final printerService = PrinterService();
  await printerService.initialize();
  
  // Initialize image cache service globally
  try {
    final imageCacheService = ImageCacheService();
    await imageCacheService.initialize();
  } catch (e) {
    debugPrint('⚠️ Image cache initialization failed: $e');
    // Continue without image cache if it fails
  }
  
  // Initialize window manager for desktop platforms (title bar hidden)
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    await windowManager.setMinimumSize(const Size(800, 600));
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: globalAuthProvider),
        ChangeNotifierProvider(create: (_) => RealtimeService()),
      ],
      child: MaterialApp(
        title: 'Five Star Chicken POS v1.0.6',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.orange,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          appBarTheme: AppBarTheme(
            backgroundColor: Colors.orange[600],
            foregroundColor: Colors.white,
            elevation: 2,
          ),
        ),
        home: const MainApp(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  bool _realtimeInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _setupRealtime();
  }

  void _setupRealtime() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final realtimeService = Provider.of<RealtimeService>(context, listen: false);

    if (authProvider.isAuthenticated && !_realtimeInitialized && authProvider.user != null) {
      _realtimeInitialized = true;
      realtimeService.onUserDataChanged = () {
        authProvider.reloadUserProfile();
      };
      // Use post-frame callback to avoid calling during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        realtimeService.initialize(userId: authProvider.user!.id);
      });
    } else if (!authProvider.isAuthenticated && _realtimeInitialized) {
      _realtimeInitialized = false;
      realtimeService.onUserDataChanged = null;
      realtimeService.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    if (authProvider.isAuthenticated) {
      return const HomeScreen();
    }
    
    return const LoginScreen();
  }
}
