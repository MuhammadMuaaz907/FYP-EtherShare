import 'dart:async';
import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'ProfileSetup.dart';
import 'workspace_preview_page.dart';
import 'workspace_home_page.dart';
import 'services/contract_service.dart';
import 'services/session_service.dart';


class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _rotation;
  late final Animation<Offset> _slide;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    print('🚀 SplashScreen initState called');

    try {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1200),
      );

      _rotation = Tween<double>(begin: -1.0, end: 0.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
      );

      _slide =
          Tween<Offset>(begin: const Offset(0, -0.4), end: Offset.zero).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
      );

      _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeIn),
      );

      _controller.forward();
      print('🎬 Animation started');

      Future.delayed(const Duration(seconds: 2), () {
        print('⏰ Timer completed, checking session...');
        if (mounted) {
          _checkSessionAndNavigate();
        }
      });
    } catch (e) {
      print('❌ SplashScreen initState error: $e');
      // Fallback: navigate immediately if animation fails
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        }
      });
    }
  }

  // Check session and navigate accordingly
  Future<void> _checkSessionAndNavigate() async {
    try {
      print('🔍 Checking user session...');
      
      // Check if user is logged in using SessionService
      final session = await SessionService.getLoginSession();
      
      if (session['isLoggedIn'] == 'true') {
        final userAddress = session['userAddress'];
        final workspaceName = session['workspaceName'] ?? 'YourWorkspace';
        final channelName = session['channelName'] ?? 'general';
        
        if (userAddress != null) {
          print('✅ User is logged in, redirecting to workspace');
          print('📋 User: $userAddress, Workspace: $workspaceName, Channel: $channelName');
          
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => TeamHomePage(
                workspaceName: workspaceName,
                channelName: channelName,
              ),
            ),
          );
          return;
        }
      }
      
      // If not logged in or session invalid, go to login screen
      print('➡️ User not logged in, redirecting to LoginScreen');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } catch (e) {
      print('❌ Error in session check: $e');
      // Fallback to login screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    print('🎨 SplashScreen build method called');
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Opacity(
              opacity: _opacity.value,
              child: Transform.rotate(
                angle: _rotation.value,
                child: SlideTransition(position: _slide, child: child!),
              ),
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo with error handling
              Container(
                width: 120,
                height: 120,
                child: Image.asset(
                  'assets/logo.png', 
                  width: 120,
                  errorBuilder: (context, error, stackTrace) {
                    print('❌ Logo image error: $error');
                    return Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(60),
                      ),
                      child: Icon(
                        Icons.share,
                        size: 60,
                        color: Colors.blue.shade800,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Ether Share',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue.shade800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
