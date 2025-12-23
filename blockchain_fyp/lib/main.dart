import 'dart:async';

import 'Splash.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'services/contract_service.dart';
import 'services/invite_service.dart';
import 'services/distributed_service.dart';
import 'services/session_service.dart';
import 'services/invite_link_manager.dart';
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
    
    print('✅ Services initialized');
    
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
    _initializeServices();
    _handleDeepLink();
  }

  /// Initialize Distributed System and other services
  /// Non-blocking: Runs in background, doesn't delay app startup
  Future<void> _initializeServices() async {
    // Don't await - let app start even if backend is unavailable
    // This prevents blocking the UI during startup
    Future.microtask(() async {
      try {
        print('🚀 Initializing Distributed System...');
        
        // Try to connect with timeout - don't block if it fails
        final connected = await DistributedService.connect().timeout(
          const Duration(seconds: 4),
          onTimeout: () {
            print('⚠️ Backend connection timeout - continuing without backend');
            return false;
          },
        ).catchError((e) {
          print('⚠️ Backend connection error - continuing without backend');
          return false;
        });
        
        if (connected) {
          print('✅ Distributed System initialized successfully');
          
          // Build chain if nodes exist (non-blocking)
          try {
            final chain = await DistributedService.buildChain().timeout(
              const Duration(seconds: 5),
              onTimeout: () {
                print('⚠️ Chain build timeout - skipping');
                return null;
              },
            );
            if (chain != null) {
              print('✅ Chain structure ready');
            }
          } catch (e) {
            print('⚠️ Chain build error (non-critical): $e');
          }
        } else {
          print('⚠️ Backend unavailable - app will work in offline mode');
          print('💡 To enable backend features:');
          print('   1. Start backend: cd backend && npm run dev');
          print('   2. Ensure PC and phone are on same WiFi');
          print('   3. Verify PC IP: 192.168.0.35');
        }
      } catch (e) {
        // Don't crash app if initialization fails
        print('⚠️ Distributed System initialization error (non-critical): $e');
      }
    });
  }

  /// Handle deep links for workspace invites
  Future<void> _handleDeepLink() async {
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

    // Check if user is logged in using SessionService
    final session = await SessionService.getLoginSession();
    final isLoggedIn = session['isLoggedIn'] == 'true';
    final userAddress = session['userAddress'] ?? '';

    if (!isLoggedIn || userAddress.isEmpty) {
      print('ℹ️ User not logged in, cannot accept invite yet.');
      // Optionally, you could store the invite and prompt login
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
