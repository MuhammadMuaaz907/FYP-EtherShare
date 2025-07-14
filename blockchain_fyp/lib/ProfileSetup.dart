import 'package:flutter/material.dart';
import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';

class ProfileSetupScreen extends StatefulWidget {
  final String address;

  const ProfileSetupScreen({super.key, required this.address});

  @override
  _ProfileSetupScreenState createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  bool _showPrivateKey = false;
  String? _privateKey;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _privateKey = 'Unable to fetch private key securely. Export from MetaMask.';
  }

  Future<void> _saveProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('username', _usernameController.text.trim());
      await prefs.setString('email', _emailController.text.trim());
      setState(() {
        _status = 'Profile saved successfully!';
      });
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      setState(() {
        _status = 'Error saving profile: $e';
      });
    }
  }

  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Black background
      body: Center(
        child: Container(
          width: 300,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Avatar image
              const CircleAvatar(
                radius: 100,
                backgroundImage: AssetImage('assets/ProfileIcon.png'), // 👈 Your image here
                backgroundColor: Colors.transparent,
              ),
              const SizedBox(height: 24),
              
              // Heading
              const Text(
                'Setup your profile',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),

              // Name Field
              TextField(
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  hintText: 'Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // Email Field
              TextField(
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  hintText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),

              // Save Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {_saveProfile();},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
