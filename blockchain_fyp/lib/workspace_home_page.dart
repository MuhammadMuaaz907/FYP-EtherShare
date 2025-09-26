import 'package:flutter/material.dart';
import 'channel_page.dart';
import 'login_screen.dart';
import 'package:flutter/services.dart';
import 'services/orbitdb_service.dart';

class TeamHomePage extends StatefulWidget {
  final String workspaceName;
  final String channelName;
  const TeamHomePage({super.key, required this.workspaceName, required this.channelName});

  @override
  State<TeamHomePage> createState() => _TeamHomePageState();
}

class _TeamHomePageState extends State<TeamHomePage> {
  String currentUserName = 'You';
  DateTime? _lastBackPressTime;

  @override
  void initState() {
    super.initState();
    print('🏢 Workspace Home Page initialized');
    print('📋 Workspace Name: ${widget.workspaceName}');
    print('📋 Channel Name: ${widget.channelName}');
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    try {
      print('🔍 Loading username for workspace: ${widget.workspaceName}');
      // Load username from OrbitDB instead of SharedPreferences
      final username = await _getUserNameFromOrbitDB() ?? 'You';
      print('👤 Loaded username: $username');
      setState(() {
        currentUserName = username;
      });
    } catch (_) {
      print('❌ Error loading username, using default');
      setState(() {
        currentUserName = 'You';
      });
    }
  }

  Future<String?> _getUserNameFromOrbitDB() async {
    try {
      // This is a simplified approach - in real implementation, you'd need to pass user address
      // For now, we'll use a default user address or get it from context
      final userAddress = '0xc79d923c6b52b62c2b77de6ce9d1e434e3b3fe99'; // This should be passed as parameter
      final key = userAddress.toLowerCase().trim();
      final dbName = 'profile_$key';
      
      print('🔍 Looking for username in database: $dbName');
      final dbAddress = await OrbitDBService.getExistingDatabaseAddress(dbName);
      
      if (dbAddress != null) {
        print('📌 Found profile database: $dbAddress');
        final messages = await OrbitDBService.getMessages(dbAddress);
        print('📨 Retrieved ${messages.length} messages from profile database');
        
        for (var message in messages) {
          print('🔍 Checking message: ${message['type']} for user: ${message['userAddress']}');
          if (message['type'] == 'profile' && message['userAddress'] == key) {
            print('📋 Found profile data - Username: ${message['username']}');
            return message['username'];
          }
        }
      } else {
        print('❌ Profile database not found');
      }
      return null;
    } catch (e) {
      print('❌ Error loading username from OrbitDB: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        DateTime now = DateTime.now();
        if (_lastBackPressTime == null || now.difference(_lastBackPressTime!) > Duration(seconds: 2)) {
          _lastBackPressTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('If you want to exit please back once again'),
              duration: Duration(seconds: 2),
            ),
          );
          return false;
        }
        await SystemNavigator.pop();
        return false;
      },
      child: Scaffold(
      backgroundColor: const Color(0xFF1A2236),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(110),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF4F0E5E), Color(0xFF350D36)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (context) => const WorkspaceDrawer(),
                          );
                        },
                        child: CircleAvatar(
                          backgroundColor: Colors.black.withOpacity(0.2),
                          radius: 16,
                          child: Text(
                            (widget.workspaceName.isNotEmpty
                                    ? widget.workspaceName[0].toUpperCase()
                                    : 'W'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        widget.workspaceName.isNotEmpty ? widget.workspaceName : 'OnlineWork',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                        ),
                      ),
                      const Spacer(),
                      CircleAvatar(
                        backgroundColor: Colors.white,
                        radius: 18,
                        child: Icon(Icons.person, color: Color(0xFF4F0E5E)),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFF5F2B6B),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 10),
                              const Icon(Icons.search, color: Colors.white54),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Jump to or search...',
                                  style: TextStyle(color: Colors.white54, fontSize: 16),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFF5F2B6B),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.tune, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _quickAction(Icons.bookmark_border, 'Later'),
                _quickAction(Icons.play_arrow, 'Drafts & Sent'),
                _quickAction(Icons.headphones, 'Huddles'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Text('Channels', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          _channelTile('General'),
          _channelTile('Random'),
          _channelTile('${widget.channelName.isNotEmpty ? widget.channelName : 'work'}', trailing: _startHere()),
          _addChannelTile(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Text('Direct messages', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          _dmTile('$currentUserName (you)'),
          _addTeammatesTile(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF5F2B6B),
        onPressed: () {},
        child: const Icon(Icons.add, color: Colors.white),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF232B3E),
        selectedItemColor: const Color(0xFF4F0E5E),
        unselectedItemColor: Colors.white54,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.forum), label: 'DMs'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'Activity'),
          BottomNavigationBarItem(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
        currentIndex: 0,
        onTap: (i) {},
      ),
    ),
  );
  }

  Widget _quickAction(IconData icon, String label) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF232B3E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white, size: 26),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ],
    );
  }

  Widget _channelTile(String name, {Widget? trailing}) {
    return ListTile(
      leading: const Icon(Icons.tag, color: Colors.white54),
      title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 16)),
      trailing: trailing != null
          ? ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 100),
              child: trailing,
            )
          : null,
      onTap: () {
        final channel = name.replaceAll('#', '').trim();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChannelPage(
              channelName: channel,
              workspaceName: widget.workspaceName,
            ),
          ),
        );
      },
    );
  }

  Widget _addChannelTile() {
    return ListTile(
      leading: const Icon(Icons.add, color: Colors.white54),
      title: const Text('Add channel', style: TextStyle(color: Colors.white, fontSize: 16)),
      onTap: () {},
    );
  }

  Widget _dmTile(String name) {
    String initial = 'U';
    if (name.isNotEmpty) {
      // Remove (you) if present, and trim
      String baseName = name.replaceAll('(you)', '').trim();
      if (baseName.isNotEmpty) {
        initial = baseName[0].toUpperCase();
      }
    }
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.white,
        child: Text(
          initial,
          style: const TextStyle(
            color: Color(0xFF4F0E5E),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 16)),
      onTap: () {},
    );
  }

  Widget _addTeammatesTile() {
    return ListTile(
      leading: const Icon(Icons.add, color: Colors.white54),
      title: const Text('Add teammates', style: TextStyle(color: Colors.white, fontSize: 16)),
      onTap: () {},
    );
  }

  Widget _startHere() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.yellow[700],
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.touch_app, size: 16, color: Colors.black),
          SizedBox(width: 4),
          Text('Start here', style: TextStyle(color: Colors.black, fontSize: 13)),
        ],
      ),
    );
  }
}

class WorkspaceDrawer extends StatelessWidget {
  const WorkspaceDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 0.8,
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF232B3E),
            borderRadius: BorderRadius.only(
              topRight: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text(
                        'E',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 28,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Ethershare', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                      Text('ethershare.slack.com', style: TextStyle(color: Colors.white54, fontSize: 14)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 30),
              ListTile(
                leading: const Icon(Icons.add, color: Colors.white54),
                title: const Text('Add a workspace', style: TextStyle(color: Colors.white, fontSize: 16)),
                onTap: () {},
                contentPadding: EdgeInsets.zero,
              ),
              ListTile(
                leading: const Icon(Icons.settings, color: Colors.white54),
                title: const Text('Preferences', style: TextStyle(color: Colors.white, fontSize: 16)),
                onTap: () {},
                contentPadding: EdgeInsets.zero,
              ),
              const Spacer(),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.redAccent),
                title: const Text('Logout', style: TextStyle(color: Colors.redAccent, fontSize: 16)),
                onTap: () async {
                  // Clear login session on logout
                  await OrbitDBService.clearLoginSession();
                  print('🚪 Logging out (session cleared)');
                  
                  Navigator.of(context).pop();
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                    (route) => false,
                  );
                },
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
    );
  }
}