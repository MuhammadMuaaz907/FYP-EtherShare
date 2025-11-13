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
  String? userAddress;
  DateTime? _lastBackPressTime;
  List<Map<String, dynamic>> _workspaceMembers = [];
  int _memberCount = 0;
  bool _isLoadingMembers = true;
  String? _inviterAddress;

  @override
  void initState() {
    super.initState();
    print('🏢 Workspace Home Page initialized');
    print('📋 Workspace Name: ${widget.workspaceName}');
    print('📋 Channel Name: ${widget.channelName}');
    _loadData();
  }

  Future<void> _loadData() async {
    await _loadUserAddress();
    await _loadUserName();
    await _loadWorkspaceMembers();
  }

  Future<void> _loadUserAddress() async {
    try {
      final session = await OrbitDBService.getLoginSession();
      userAddress = session['userAddress'];
      print('👤 User address from session: $userAddress');
    } catch (e) {
      print('❌ Error loading user address: $e');
    }
  }

  Future<void> _loadUserName() async {
    try {
      if (userAddress == null) {
        await _loadUserAddress();
      }
      print('🔍 Loading username for workspace: ${widget.workspaceName}');
      // Load username from OrbitDB
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
      if (userAddress == null) {
        await _loadUserAddress();
      }
      if (userAddress == null) return null;
      
      final key = userAddress!.toLowerCase().trim();
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

  Future<void> _loadWorkspaceMembers() async {
    setState(() {
      _isLoadingMembers = true;
    });

    try {
      // Ensure user address is loaded
      if (userAddress == null) {
        await _loadUserAddress();
      }

      // First, find the inviter address for this workspace
      _inviterAddress = await OrbitDBService.getInviterAddressForWorkspace(widget.workspaceName);
      
      if (_inviterAddress == null) {
        print('❌ Could not find inviter for workspace: ${widget.workspaceName}');
        setState(() {
          _isLoadingMembers = false;
          _memberCount = 0;
        });
        return;
      }

      print('👥 Loading members for workspace: ${widget.workspaceName}');
      final members = await OrbitDBService.getWorkspaceMembers(
        inviterAddress: _inviterAddress!,
        workspaceName: widget.workspaceName,
      );

      // Ensure current logged-in user is in the members list
      if (userAddress != null) {
        final userKey = userAddress!.toLowerCase().trim();
        final userExists = members.any((m) => 
          m['memberAddress']?.toString().toLowerCase() == userKey
        );

        if (!userExists) {
          print('➕ Adding current user to members list');
          // Get current user's display name
          final userDisplayName = await _getUserNameFromOrbitDB();
          
          members.add({
            'type': 'member',
            'workspaceName': widget.workspaceName,
            'inviterAddress': _inviterAddress!,
            'memberAddress': userKey,
            'memberDisplayName': userDisplayName,
            'joinedAt': DateTime.now().millisecondsSinceEpoch,
            'isCurrentUser': true,
          });
        }
      }

      // Fetch profile names for ALL members to ensure we have the latest names
      print('🔄 Fetching profile names for ${members.length} members...');
      
      // Create a copy of members list to avoid modification during iteration
      final updatedMembers = <Map<String, dynamic>>[];
      
      for (int i = 0; i < members.length; i++) {
        final member = Map<String, dynamic>.from(members[i]); // Create a copy
        final memberAddr = member['memberAddress']?.toString();
        if (memberAddr != null) {
          print('📝 Processing member ${i + 1}/${members.length}: $memberAddr');
          
          // Always fetch profile name to ensure we have the latest
          final profileName = await _getProfileNameForAddress(memberAddr);
          
          if (profileName != null && profileName.isNotEmpty) {
            // Update display name with profile name (prefer profile name over stored display name)
            member['memberDisplayName'] = profileName;
            print('✅ Updated member $memberAddr with name: $profileName');
          } else {
            // If no profile name found, check if we have a stored display name
            final storedName = member['memberDisplayName']?.toString();
            if (storedName == null || storedName.isEmpty) {
              print('⚠️ No profile name found for member: $memberAddr (will use address)');
              // Clear any empty display name
              member.remove('memberDisplayName');
            } else {
              print('ℹ️ Using stored display name for $memberAddr: $storedName');
            }
          }
        }
        updatedMembers.add(member);
      }

      print('📊 Final members list:');
      for (var m in updatedMembers) {
        final addr = m['memberAddress'] ?? 'UNKNOWN';
        final name = m['memberDisplayName'] ?? 'NO NAME';
        print('  - $addr: $name');
      }

      if (mounted) {
        setState(() {
          _workspaceMembers = updatedMembers;
          _memberCount = updatedMembers.length;
          _isLoadingMembers = false;
        });
      }

      print('✅ Loaded ${updatedMembers.length} members with names');
    } catch (e) {
      print('❌ Error loading workspace members: $e');
      setState(() {
        _isLoadingMembers = false;
        _memberCount = 0;
      });
    }
  }

  /// Get profile name (username) for a given address
  Future<String?> _getProfileNameForAddress(String address) async {
    try {
      final key = address.toLowerCase().trim();
      final dbName = 'profile_$key';
      print('🔍 Fetching profile name for: $address (db: $dbName)');
      
      // Try to get existing database first
      var dbAddress = await OrbitDBService.getExistingDatabaseAddress(dbName);
      
      // If database doesn't exist, try creating it (it might be a new profile)
      if (dbAddress == null) {
        print('⚠️ Profile database not found in cache, trying to create: $dbName');
        dbAddress = await OrbitDBService.createChatDB(dbName);
        if (dbAddress == null) {
          print('❌ Could not create/find profile database for: $address');
          return null;
        }
      }
      
      print('📌 Using profile database: $dbAddress');
      final messages = await OrbitDBService.getMessages(dbAddress);
      print('📨 Retrieved ${messages.length} messages from profile database');
      
      if (messages.isEmpty) {
        print('⚠️ Profile database is empty for: $address');
        return null;
      }
      
      // Look for profile message
      for (var message in messages) {
        final msgType = message['type']?.toString();
        print('🔍 Checking message: type=$msgType');
        print('🔍 Message keys: ${message.keys.toList()}');
        print('🔍 Full message: ${message.toString()}');
        
        if (msgType == 'profile') {
          final msgUserAddress = message['userAddress']?.toString().toLowerCase().trim();
          print('🔍 Profile message userAddress: $msgUserAddress (looking for: $key)');
          
          if (msgUserAddress == key) {
            // Try multiple ways to get username
            dynamic usernameValue = message['username'];
            String? username;
            
            if (usernameValue != null) {
              username = usernameValue.toString().trim();
            }
            
            print('✅ Found profile - Username value: $usernameValue, Username string: "$username" for address: $address');
            
            if (username != null && username.isNotEmpty) {
              print('✅ Returning username: $username');
              return username;
            } else {
              print('⚠️ Username is null or empty in profile for: $address');
              print('⚠️ Username value type: ${usernameValue.runtimeType}');
            }
          } else {
            print('⚠️ userAddress mismatch: expected=$key, got=$msgUserAddress');
          }
        } else {
          print('⚠️ Message type is not profile: $msgType');
        }
      }
      
      print('⚠️ No valid profile message found for address: $address');
      return null;
    } catch (e, stackTrace) {
      print('❌ Error getting profile name for $address: $e');
      print('Stack trace: $stackTrace');
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Members', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    if (_isLoadingMembers)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Text(
                        '$_memberCount ${_memberCount == 1 ? 'member' : 'members'}',
                        style: const TextStyle(color: Colors.white54, fontSize: 14),
                      ),
                    if (!_isLoadingMembers)
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white54, size: 18),
                        onPressed: () {
                          _loadWorkspaceMembers();
                        },
                        tooltip: 'Refresh members',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (_isLoadingMembers)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            )
          else if (_workspaceMembers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  'No members found',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            )
          else
            ..._workspaceMembers.map((member) => _memberTile(member)),
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

  Widget _memberTile(Map<String, dynamic> member) {
    final memberAddress = member['memberAddress']?.toString() ?? '';
    final isInviter = member['isInviter'] == true;
    final isCurrentUser = member['isCurrentUser'] == true || 
                         (userAddress != null && memberAddress.toLowerCase() == userAddress!.toLowerCase());
    
    // Get display name - prefer memberDisplayName (which should be profile name)
    String? rawDisplayName = member['memberDisplayName']?.toString();
    String displayName = (rawDisplayName ?? '').trim();
    
    // Debug logging
    if (displayName.isEmpty) {
      print('⚠️ Member $memberAddress has no display name, will use address');
    } else {
      print('✅ Member $memberAddress display name: $displayName');
    }
    
    // If no display name, use a shortened address as fallback
    final hasProfileName = displayName.isNotEmpty;
    if (!hasProfileName) {
      displayName = memberAddress.length > 10 
        ? '${memberAddress.substring(0, 6)}...${memberAddress.substring(memberAddress.length - 4)}'
        : memberAddress;
      print('📝 Using address as fallback for $memberAddress: $displayName');
    }
    
    // Add "(you)" suffix if it's the current user
    if (isCurrentUser && !displayName.contains('(you)')) {
      displayName = '$displayName (you)';
    }
    
    // Get initial from display name (remove "(you)" for initial)
    String nameForInitial = displayName.replaceAll('(you)', '').trim();
    final initial = nameForInitial.isNotEmpty ? nameForInitial[0].toUpperCase() : 'M';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isInviter ? const Color(0xFF23C16B) : Colors.white,
        child: Text(
          initial,
          style: TextStyle(
            color: isInviter ? Colors.white : const Color(0xFF4F0E5E),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              displayName,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
          if (isInviter)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF23C16B).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Admin',
                style: TextStyle(
                  color: Color(0xFF23C16B),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      // Only show address in subtitle if we don't have a profile name, or make it less prominent
      subtitle: hasProfileName 
        ? null // Hide address when we have a proper name
        : Text(
            memberAddress.length > 20 
              ? '${memberAddress.substring(0, 10)}...${memberAddress.substring(memberAddress.length - 8)}'
              : memberAddress,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
      onTap: () {
        // TODO: Show member details or profile
      },
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