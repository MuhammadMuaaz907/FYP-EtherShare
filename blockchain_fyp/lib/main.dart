import 'dart:async';

import 'package:blockchain_fyp/splash.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';
import 'package:get_it/get_it.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:app_links/app_links.dart';

import 'services/contract_service.dart';
import 'services/invite_link_manager.dart';
import 'services/invite_service.dart';
import 'services/ipfs_service.dart';
import 'services/orbitdb_service.dart';
import 'screens/accept_invite_screen.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  try {
    print('🚀 Starting EtherShare App...');
    
    // Ensure Flutter binding is initialized first
    WidgetsFlutterBinding.ensureInitialized();
    print('✅ Flutter binding initialized');
    
    // Load environment variables
    try {
      await dotenv.load(fileName: '.env');
      print('Environment file (.env) loaded successfully');
    } catch (e) {
      // If .env is missing, log warning but continue
      print('Warning: Could not load .env file: $e');
      print('SMTP configuration will be required when sending emails.');
    }
    
    GetIt.I.registerSingleton<IPFSService>(IPFSService());
    GetIt.I.registerSingleton<OrbitDBService>(OrbitDBService());
    print('✅ Services registered');
    
    GetIt.I.registerSingletonAsync<Web3App>(() async {
      final app = await Web3App.createInstance(
        projectId: '1f976613b40ddd232f1339e8ae5f1634',
        metadata: const PairingMetadata(
          name: 'FYP Secure File Sharing',
          description: 'Blockchain-based file sharing app',
          url: 'https://example.com',
          icons: ['https://example.com/icon.png'],
        ),
      );
      return app;
    });
    print('✅ Web3App registered');

    // Initialize OrbitDB in background after app starts
    _initializeOrbitDBInBackground();

    print('🎬 Running MyApp...');
    runApp(const MyApp());
  } catch (e) {
    print('❌ Critical error in main(): $e');
    // Fallback: try to run a minimal app
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('App Error: $e'),
        ),
      ),
    ));
  }
}

// Initialize OrbitDB in background to avoid blocking app startup
void _initializeOrbitDBInBackground() async {
  try {
    await OrbitDBService.initOrbitDB();
    print('✅ OrbitDB initialized successfully');
  } catch (e) {
    print('❌ Failed to initialize OrbitDB: $e');
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  StreamSubscription<Uri>? _linkSubscription;
  AppLinks? _appLinks;
  bool _isHandlingInviteNavigation = false;

  @override
  void initState() {
    super.initState();
    _setupMethodChannel();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    await InviteLinkManager.instance.loadFromStorage();

    _appLinks = AppLinks();

    try {
      final initialUri = await _appLinks!.getInitialAppLink();
      if (initialUri != null) {
        await _handleIncomingLink(initialUri);
      }
    } catch (e) {
      print('Error parsing initial deep link: $e');
    }

    _linkSubscription = _appLinks!.uriLinkStream.listen(
      (uri) {
        _handleIncomingLink(uri);
      },
      onError: (err) {
        print('Deep link stream error: $err');
      },
    );

    _maybeNavigateToInvite();
  }

  Future<void> _handleIncomingLink(Uri uri) async {
    if (uri.scheme.toLowerCase() != 'ethershare') {
      return;
    }

    if (uri.host.toLowerCase() != 'invite') {
      return;
    }

    final workspaceSlug = uri.queryParameters['workspace'] ?? '';
    final inviter = uri.queryParameters['inviter'] ?? '';

    if (workspaceSlug.isEmpty || inviter.isEmpty) {
      return;
    }

    final invite = InviteLinkData(
      workspaceSlug: workspaceSlug,
      inviterAddress: inviter,
    );

    await InviteLinkManager.instance.setPendingInvite(invite);
    await _maybeNavigateToInvite();
  }

  Future<void> _maybeNavigateToInvite() async {
    if (_isHandlingInviteNavigation) {
      return;
    }

    final pendingInvite = InviteLinkManager.instance.currentInvite;
    if (pendingInvite == null) {
      return;
    }

    final session = await OrbitDBService.getLoginSession();
    if (session['isLoggedIn'] != 'true') {
      return;
    }

    final userAddress = session['userAddress'];
    if (userAddress == null || userAddress.isEmpty) {
      return;
    }

    if (rootNavigatorKey.currentState == null) {
      return;
    }

    _isHandlingInviteNavigation = true;

    final resolved = await InviteService.resolveInvite(pendingInvite);

    if (resolved == null) {
      await InviteLinkManager.instance.clearPendingInvite();
      _isHandlingInviteNavigation = false;
      return;
    }

    if (!mounted) {
      _isHandlingInviteNavigation = false;
      return;
    }

    rootNavigatorKey.currentState!.push(
      MaterialPageRoute(
        builder: (_) => AcceptInviteScreen(
          invite: resolved,
          userAddress: userAddress,
          onComplete: () async {
            await InviteLinkManager.instance.clearPendingInvite();
            _isHandlingInviteNavigation = false;
          },
          onCancel: () async {
            _isHandlingInviteNavigation = false;
          },
        ),
        fullscreenDialog: true,
      ),
    );
  }

  void _setupMethodChannel() {
    // Initialize MethodChannel for OrbitDB Bridge
    const MethodChannel channel = MethodChannel('orbitdb_channel');

    // Set up method call handler for real-time updates
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onMessageUpdate':
          // Handle real-time message updates
          print('📨 Real-time message update received: ${call.arguments}');
          break;
        default:
          print('❌ Unknown method call: ${call.method}');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureProvider<ContractService?>(
      create: (_) async {
        try {
          // Add timeout to prevent hanging
          return await ContractService.create().timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              print('⚠️ ContractService initialization timed out');
              throw Exception('ContractService initialization timed out');
            },
          );
        } catch (e) {
          print('FutureProvider error: $e');
          // Return a dummy ContractService instead of null
          return ContractService.dummy();
        }
      },
      initialData: null,
      child: MaterialApp(
        navigatorKey: rootNavigatorKey,
        title: 'FYP - Secure File Sharing',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[700],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              textStyle:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        home: const SplashScreen(),
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
            child: child!,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _appLinks = null;
    super.dispose();
  }
}

// LoginScreen and HomeScreen are now in separate files (login_screen.dart and home_screen.dart)
// This keeps the code organized and maintainable
