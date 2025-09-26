import 'package:blockchain_fyp/splash.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';
import 'package:get_it/get_it.dart';
import 'package:flutter/services.dart';
import 'services/contract_service.dart';
import 'services/ipfs_service.dart';
import 'services/orbitdb_service.dart';

void main() {
  try {
    print('🚀 Starting EtherShare App...');
    
    // Ensure Flutter binding is initialized first
    WidgetsFlutterBinding.ensureInitialized();
    print('✅ Flutter binding initialized');
    
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
  @override
  void initState() {
    super.initState();
    _setupMethodChannel();
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
              textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
}

// LoginScreen aur uski state ko yahan se hata diya gaya hai, ab yeh login_screen.dart mein hai.


// HomeScreen ki implementation yahan se hata di gayi hai, ab yeh home_screen.dart mein hai.