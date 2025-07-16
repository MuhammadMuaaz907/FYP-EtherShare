import 'package:blockchain_fyp/splash.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web3dart/web3dart.dart';
import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';
import 'package:get_it/get_it.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:hex/hex.dart';
import 'dart:typed_data';
import 'services/contract_service.dart';
import 'ProfileSetup.dart';
import 'login_screen.dart';
import 'home_screen.dart';

void main() {
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

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureProvider<ContractService?>(
      create: (_) async {
        try {
          return await ContractService.create();
        } catch (e) {
          print('FutureProvider error: $e');
          return null;
        }
      },
      initialData: null,
      child: MaterialApp(
        title: 'FYP - Secure File Sharing',
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
      ),
    );
  }
}

// LoginScreen aur uski state ko yahan se hata diya gaya hai, ab yeh login_screen.dart mein hai.


// HomeScreen ki implementation yahan se hata di gayi hai, ab yeh home_screen.dart mein hai.