import 'package:flutter/material.dart';
import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'create_workspace_page.dart';
import 'services/orbitdb_service.dart';

class ProfileSetupScreen extends StatefulWidget {
  final String address;

  const ProfileSetupScreen({super.key, required this.address});

  @override
  _ProfileSetupScreenState createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  String _status = '';

  @override
  void initState() {
    super.initState();
  }

  Future<void> _saveProfile() async {
    try {
      // Save profile to OrbitDB instead of local storage
      final key = widget.address.toLowerCase().trim();
      final dbName = 'profile_$key';
      
      // Create the database first (this will store the address in cache)
      final dbAddress = await OrbitDBService.createChatDB(dbName);
      
      print('💾 Saving profile to database: $dbAddress');
      
      if (dbAddress != null) {
        final profileMessage = {
          'type': 'profile',
          'userAddress': key,
          'username': _usernameController.text.trim(),
          'email': _emailController.text.trim(),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };
        
        print('📋 Profile message: $profileMessage');
        
        final result = await OrbitDBService.addMessage(dbAddress, profileMessage);
        
        if (result != null) {
          print('✅ Profile saved successfully with hash: $result');
          print('📌 Database address cached for future use: $dbAddress');
          setState(() {
            _status = 'Profile saved successfully to OrbitDB!';
          });
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => CreateWorkspacePage(userAddress: widget.address)),
          );
        } else {
          print('❌ Failed to save profile message');
          setState(() {
            _status = 'Error saving profile to OrbitDB';
          });
        }
      } else {
        print('❌ Failed to create profile database');
        setState(() {
          _status = 'Error creating profile database';
        });
      }
    } catch (e) {
      print('❌ Error saving profile: $e');
      setState(() {
        _status = 'Error saving profile: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A2236),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Profile Setup',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.topCenter,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 60),
                    width: 350,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                    decoration: BoxDecoration(
                      color: const Color(0xFF232B3E),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.18),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 60),
                        const Text(
                          'Setup your profile',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Name Field
                        TextField(
                          controller: _usernameController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Name',
                            labelStyle: const TextStyle(color: Colors.white70),
                            filled: true,
                            fillColor: const Color(0xFF2D3754),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            hintText: 'Enter your name',
                            hintStyle: const TextStyle(color: Colors.white38),
                          ),
                        ),
                        const SizedBox(height: 18),
                        // Email Field
                        TextField(
                          controller: _emailController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Email',
                            labelStyle: const TextStyle(color: Colors.white70),
                            filled: true,
                            fillColor: const Color(0xFF2D3754),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            hintText: 'Enter your email',
                            hintStyle: const TextStyle(color: Colors.white38),
                          ),
                        ),
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _saveProfile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue[700],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Save'),
                          ),
                        ),
                        if (_status.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            _status,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _status.contains('success') ? Colors.greenAccent : Colors.redAccent,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Avatar image (overlapping card)
                  const Positioned(
                    top: 0,
                    child: CircleAvatar(
                      radius: 48,
                      backgroundImage: AssetImage('assets/ProfileIcon.png'),
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
