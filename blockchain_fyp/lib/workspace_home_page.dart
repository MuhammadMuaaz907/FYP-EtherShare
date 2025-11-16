import 'package:flutter/material.dart';
import 'channel_page.dart';
import 'login_screen.dart';
import 'package:flutter/services.dart';
import 'services/orbitdb_service.dart';
import 'pages/dms_page.dart';
import 'pages/activity_page.dart';
import 'invite_teammates_page.dart';
import 'ProfileSetup.dart';
import 'direct_message_page.dart';
import 'create_workspace_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TeamHomePage extends StatefulWidget {
  final String workspaceName;
  final String channelName;
  const TeamHomePage(
      {super.key, required this.workspaceName, required this.channelName});

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
  int _currentIndex = 0;
  List<String> _channels = ['General', 'Random'];
  // Map to track display name -> original database name (for proper database lookups)
  final Map<String, String> _displayToOriginalName = {};
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isSearchActive = false;
  List<Map<String, dynamic>> _searchResults = [];

  DateTime? _lastChannelLoadTime;

  @override
  void initState() {
    super.initState();
    print('🏢 Workspace Home Page initialized');
    print('📋 Workspace Name: ${widget.workspaceName}');
    print('📋 Channel Name: ${widget.channelName}');
    _loadData();
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(_onSearchFocusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload channels when page becomes visible again (e.g., returning from channel page)
    // Only reload if enough time has passed (at least 1 second) to avoid excessive reloads
    final now = DateTime.now();
    if (_lastChannelLoadTime == null || 
        now.difference(_lastChannelLoadTime!).inSeconds > 1) {
      _lastChannelLoadTime = now;
      _loadChannels();
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearchActive = false;
      });
    } else {
      _performSearch(query);
    }
  }

  void _onSearchFocusChanged() {
    setState(() {
      _isSearchActive = _searchFocusNode.hasFocus;
    });
  }

  void _performSearch(String query) {
    final results = <Map<String, dynamic>>[];

    // Search channels
    for (var channel in _channels) {
      if (channel.toLowerCase().contains(query)) {
        results.add({
          'type': 'channel',
          'name': channel,
          'displayName': '# $channel',
        });
      }
    }

    // Search members
    for (var member in _workspaceMembers) {
      final memberName = (member['memberDisplayName']?.toString() ?? '').toLowerCase();
      final memberAddress = (member['memberAddress']?.toString() ?? '').toLowerCase();
      
      if (memberName.contains(query) || memberAddress.contains(query)) {
        final displayName = member['memberDisplayName']?.toString() ?? 
            (memberAddress.length > 10
                ? '${memberAddress.substring(0, 6)}...${memberAddress.substring(memberAddress.length - 4)}'
                : memberAddress);
        
        results.add({
          'type': 'member',
          'name': displayName,
          'memberData': member,
          'displayName': displayName,
        });
      }
    }

    setState(() {
      _searchResults = results;
      _isSearchActive = query.isNotEmpty;
    });
  }

  /// Navigate to user profile page
  Future<void> _navigateToUserProfile() async {
    if (!mounted || userAddress == null) return;
    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => UserProfilePage(
          userAddress: userAddress!,
          workspaceName: widget.workspaceName,
        ),
      ),
    );
  }

  void _handleSearchResultTap(Map<String, dynamic> result) {
    _searchController.clear();
    _searchFocusNode.unfocus();
    
    final type = result['type'];
    
    if (type == 'channel') {
      final channelName = result['name'].toString().replaceAll('#', '').trim();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChannelPage(
            channelName: channelName,
            workspaceName: widget.workspaceName,
          ),
        ),
      );
    } else if (type == 'member') {
      // TODO: Navigate to member profile or start DM
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Member: ${result['displayName']}'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _loadData() async {
    await _loadUserAddress();
    await _loadUserName();
    await _loadWorkspaceMembers();
    await _loadChannels();
  }

  Future<void> _loadChannels() async {
    try {
      if (userAddress == null) {
        await _loadUserAddress();
      }
      if (_inviterAddress == null) {
        _inviterAddress = await OrbitDBService.getInviterAddressForWorkspace(
            widget.workspaceName);
      }

      // Load channels from workspace database
      final workspaceDbName =
          'workspace_${_inviterAddress ?? userAddress}';
      final dbAddress =
          await OrbitDBService.getExistingDatabaseAddress(workspaceDbName);

      // Use a Set to track unique channels by their display name (case-insensitive)
      final channelSet = <String>{'General', 'Random'};
      // Map to track original channel names -> display names (for database lookup)
      final Map<String, String> originalToDisplay = {};
      
      // Clear and rebuild display-to-original mapping
      _displayToOriginalName.clear();
      
      // Add default channels to mapping (they are their own original names)
      _displayToOriginalName['general'] = 'general';
      _displayToOriginalName['random'] = 'random';

      if (dbAddress != null) {
        final messages = await OrbitDBService.getMessages(dbAddress);
        
        // Step 1: Collect deleted channels (to filter them out)
        final Set<String> deletedChannels = {}; // Set of deleted channel original names (lowercase)
        
        for (var message in messages) {
          if (message['type'] == 'channel_delete' &&
              message['workspaceName'] == widget.workspaceName) {
            final deletedChannelName = message['channelName']?.toString();
            if (deletedChannelName != null && deletedChannelName.isNotEmpty) {
              deletedChannels.add(deletedChannelName.toLowerCase());
              print('🗑️ [LoadChannels] Found deleted channel: "$deletedChannelName"');
            }
          }
        }
        
        // Step 2: Build simple rename map (original name -> latest new name)
        // Simple approach: Find the most recent rename for each original channel name
        final Map<String, Map<String, dynamic>> renameMap = {}; // originalName (lowercase) -> {newName, timestamp}
        
        // Collect all rename actions and keep only the latest one for each original name
        for (var message in messages) {
          if (message['type'] == 'channel_rename' &&
              message['workspaceName'] == widget.workspaceName) {
            final oldName = message['oldChannelName']?.toString();
            final newName = message['newChannelName']?.toString();
            final timestamp = message['timestamp'];
            
            if (oldName != null && 
                newName != null && 
                oldName.isNotEmpty && 
                newName.isNotEmpty && 
                timestamp is int) {
              final oldNameLower = oldName.toLowerCase();
              
              // Only keep the most recent rename for each original name
              if (!renameMap.containsKey(oldNameLower) ||
                  (renameMap[oldNameLower]!['timestamp'] as int) < timestamp) {
                renameMap[oldNameLower] = {
                  'newName': newName,
                  'timestamp': timestamp,
                };
                print('📝 [LoadChannels] Found rename: "$oldName" -> "$newName" (timestamp: $timestamp)');
              }
            }
          }
        }
        
        // Convert to simple map for easier access
        final Map<String, String> channelRenames = {};
        renameMap.forEach((key, value) {
          channelRenames[key] = value['newName'] as String;
        });
        
        // Step 2: Process channel messages
        // Get the latest channel message for each channel (in case channel was updated)
        final Map<String, Map<String, dynamic>> latestChannels = {};
        
        for (var message in messages) {
          if (message['type'] == 'channel' &&
              message['workspaceName'] == widget.workspaceName) {
            final channelName = message['channelName']?.toString();
            final originalName = message['originalChannelName']?.toString() ?? channelName;
            
            if (channelName != null && channelName.isNotEmpty) {
              final key = (originalName ?? channelName).toLowerCase();
              
              // Keep only the latest channel message (by timestamp)
              if (!latestChannels.containsKey(key) ||
                  (message['timestamp'] as int? ?? 0) > 
                  (latestChannels[key]!['timestamp'] as int? ?? 0)) {
                latestChannels[key] = message;
              }
            }
          }
        }
        
        // Step 3: Process channels and apply renames (skip deleted channels)
        for (var entry in latestChannels.entries) {
          final message = entry.value;
          final channelName = message['channelName']?.toString();
          final originalName = message['originalChannelName']?.toString() ?? channelName;
          
          if (channelName != null && channelName.isNotEmpty) {
            final originalNameLower = (originalName ?? channelName).toLowerCase();
            
            // Skip if channel is deleted
            if (deletedChannels.contains(originalNameLower)) {
              print('⏭️ [LoadChannels] Skipping deleted channel: "$originalNameLower"');
              continue;
            }
            
            // Determine display name: use renamed name if exists, otherwise use channel name from message
            String displayName = channelName; // Use name from latest channel message
            
            // If there's a rename mapping, use that (takes precedence)
            if (channelRenames.containsKey(originalNameLower)) {
              displayName = channelRenames[originalNameLower]!;
              print('🔄 [LoadChannels] Channel "$originalNameLower" renamed to "$displayName"');
            }
            
            // Store mapping: original name -> display name (for database lookup)
            originalToDisplay[originalNameLower] = displayName;
            
            // Also store reverse mapping: display name -> original name (for navigation)
            final displayNameLower = displayName.toLowerCase();
            _displayToOriginalName[displayNameLower] = originalNameLower;
            print('📝 [LoadChannels] Stored mapping: display="$displayName" -> original="$originalNameLower"');
            
            // Add to set (automatically handles duplicates by case-insensitive comparison)
            if (!channelSet.any((c) => c.toLowerCase() == displayNameLower)) {
                // Remove old name if it exists (in case of rename)
                channelSet.removeWhere((c) => c.toLowerCase() == originalNameLower && 
                                             c.toLowerCase() != displayNameLower);
                channelSet.add(displayName);
                print('✅ [LoadChannels] Added channel: "$displayName" (original: "$originalNameLower")');
              } else {
                print('⏭️ [LoadChannels] Skipped duplicate: "$displayName"');
              }
          }
        }
      }

      // Convert set to sorted list (General and Random first, then alphabetical)
      final channels = <String>[];
      if (channelSet.contains('General')) {
        channels.add('General');
        channelSet.remove('General');
      }
      if (channelSet.contains('Random')) {
        channels.add('Random');
        channelSet.remove('Random');
      }
      channels.addAll(channelSet.toList()..sort());

      // Also check if widget.channelName exists (from workspace creation)
      // and add it if it's not already in the list
      if (widget.channelName.isNotEmpty &&
          widget.channelName.toLowerCase() != 'work' &&
          !channels.any((c) => c.toLowerCase() == widget.channelName.toLowerCase())) {
        channels.add(widget.channelName);
        final initialChannelLower = widget.channelName.toLowerCase();
        // Add to mapping (initial channel is its own original name)
        _displayToOriginalName[initialChannelLower] = initialChannelLower;
        print('✅ Added initial channel from workspace creation: ${widget.channelName}');
        print('📝 [LoadChannels] Stored mapping for initial channel: display="$initialChannelLower" -> original="$initialChannelLower"');
        
        // Save the initial channel to OrbitDB if it's not already saved
        await _saveInitialChannel(widget.channelName);
      }

      print('📊 [LoadChannels] Final channels list: ${channels.length} channels');
      for (var channel in channels) {
        print('   - $channel');
      }

      setState(() {
        _channels = channels;
        _lastChannelLoadTime = DateTime.now(); // Update last load time
      });
    } catch (e) {
      print('❌ Error loading channels: $e');
    }
  }

  Future<void> _saveInitialChannel(String channelName) async {
    try {
      if (userAddress == null) {
        await _loadUserAddress();
      }
      if (_inviterAddress == null) {
        _inviterAddress = await OrbitDBService.getInviterAddressForWorkspace(
            widget.workspaceName);
      }

      if (userAddress == null || _inviterAddress == null) {
        print('⚠️ Cannot save initial channel: missing addresses');
        return;
      }

      // Get or create workspace database
      final workspaceDbName = 'workspace_$_inviterAddress';
      var dbAddress =
          await OrbitDBService.getExistingDatabaseAddress(workspaceDbName);

      if (dbAddress == null) {
        dbAddress = await OrbitDBService.createChatDB(workspaceDbName);
        if (dbAddress == null) {
          print('⚠️ Failed to create workspace database for initial channel');
          return;
        }
      }

      // Check if channel already exists in database
      final messages = await OrbitDBService.getMessages(dbAddress);
      final channelExists = messages.any((msg) =>
          msg['type'] == 'channel' &&
          msg['workspaceName'] == widget.workspaceName &&
          msg['channelName']?.toString().toLowerCase() == channelName.toLowerCase());

      if (!channelExists) {
        // Create channel message
        final channelMessage = {
          'type': 'channel',
          'workspaceName': widget.workspaceName,
          'channelName': channelName,
          'createdBy': userAddress!.toLowerCase().trim(),
          'inviterAddress': _inviterAddress,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };

        // Save channel to workspace database
        final result = await OrbitDBService.addMessage(dbAddress, channelMessage);
        if (result != null) {
          print('✅ Initial channel "$channelName" saved to OrbitDB');

          // Create channel database for messages
          final channelDbName =
              'channel_${_inviterAddress}_${widget.workspaceName}_$channelName';
          final channelDbAddress =
              await OrbitDBService.createChatDB(channelDbName);
          if (channelDbAddress != null) {
            print('✅ Channel database created: $channelDbName');
          }
        } else {
          print('⚠️ Failed to save initial channel to OrbitDB');
        }
      } else {
        print('ℹ️ Initial channel "$channelName" already exists in database');
      }
    } catch (e) {
      print('❌ Error saving initial channel: $e');
    }
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
          print(
              '🔍 Checking message: ${message['type']} for user: ${message['userAddress']}');
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
      _inviterAddress = await OrbitDBService.getInviterAddressForWorkspace(
          widget.workspaceName);

      if (_inviterAddress == null) {
        print(
            '❌ Could not find inviter for workspace: ${widget.workspaceName}');
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
        final userExists = members.any(
            (m) => m['memberAddress']?.toString().toLowerCase() == userKey);

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
              print(
                  '⚠️ No profile name found for member: $memberAddr (will use address)');
              // Clear any empty display name
              member.remove('memberDisplayName');
            } else {
              print(
                  'ℹ️ Using stored display name for $memberAddr: $storedName');
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
        print(
            '⚠️ Profile database not found in cache, trying to create: $dbName');
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
          final msgUserAddress =
              message['userAddress']?.toString().toLowerCase().trim();
          print(
              '🔍 Profile message userAddress: $msgUserAddress (looking for: $key)');

          if (msgUserAddress == key) {
            // Try multiple ways to get username
            dynamic usernameValue = message['username'];
            String? username;

            if (usernameValue != null) {
              username = usernameValue.toString().trim();
            }

            print(
                '✅ Found profile - Username value: $usernameValue, Username string: "$username" for address: $address');

            if (username != null && username.isNotEmpty) {
              print('✅ Returning username: $username');
              return username;
            } else {
              print('⚠️ Username is null or empty in profile for: $address');
              print('⚠️ Username value type: ${usernameValue.runtimeType}');
            }
          } else {
            print(
                '⚠️ userAddress mismatch: expected=$key, got=$msgUserAddress');
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
        if (_lastBackPressTime == null ||
            now.difference(_lastBackPressTime!) > Duration(seconds: 2)) {
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
        backgroundColor: Colors.white,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF0F365F),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, 2),
              ),
              ],
            ),
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (context) => WorkspaceDrawer(
                                currentWorkspaceName: widget.workspaceName,
                                userAddress: userAddress ?? '',
                              ),
                            );
                          },
                          child: CircleAvatar(
                            backgroundColor: Colors.white.withOpacity(0.2),
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
                          widget.workspaceName.isNotEmpty
                              ? widget.workspaceName
                              : 'OnlineWork',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                        fontFamily: 'Inter',
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 22,
                                        letterSpacing: 0.0,
                                      ) ??
                                  const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => _navigateToUserProfile(),
                          child: CircleAvatar(
                          backgroundColor: Colors.white,
                          radius: 18,
                            child: const Icon(Icons.person,
                                color: Color(0xFF0F365F)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: StatefulBuilder(
                              builder: (context, setState) {
                                return TextField(
                                  controller: _searchController,
                                  focusNode: _searchFocusNode,
                                  onChanged: (value) {
                                    setState(() {});
                                    _onSearchChanged();
                                  },
                                  style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            fontFamily: 'Inter',
                                            color: Colors.white,
                                            fontSize: 16,
                                            letterSpacing: 0.0,
                                          ) ??
                                      const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                      ),
                                  decoration: InputDecoration(
                                    hintText: 'Jump to or search...',
                                    hintStyle: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              fontFamily: 'Inter',
                                              color: Colors.white.withOpacity(0.7),
                                              fontSize: 16,
                                              letterSpacing: 0.0,
                                            ) ??
                                        TextStyle(
                                          color: Colors.white.withOpacity(0.7),
                                          fontSize: 16,
                                        ),
                                    prefixIcon: const Icon(
                                      Icons.search,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    suffixIcon: _searchController.text.isNotEmpty
                                        ? IconButton(
                                            icon: const Icon(
                                              Icons.clear,
                                              color: Colors.white,
                                              size: 18,
                                            ),
                                            onPressed: () {
                                              _searchController.clear();
                                              _searchFocusNode.unfocus();
                                              setState(() {});
                                            },
                                          )
                                        : null,
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 10,
                                    ),
                                  ),
                                  onSubmitted: (value) {
                                    if (_searchResults.isNotEmpty) {
                                      _handleSearchResultTap(_searchResults[0]);
                                    }
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                              width: 1,
                          ),
                          ),
                          child: const Icon(Icons.tune, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: Stack(
          children: [
            IndexedStack(
              index: _currentIndex,
              children: [
                // Home Tab (Current content)
                _buildHomeTab(),
                // DMs Tab
                DMsPage(workspaceName: widget.workspaceName),
                // Activity Tab
                ActivityPage(workspaceName: widget.workspaceName),
              ],
            ),
            // Search Results Overlay
            if (_isSearchActive && _searchResults.isNotEmpty)
              Positioned(
                top: 110,
                left: 0,
                right: 0,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  constraints: const BoxConstraints(maxHeight: 400),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Search Results Header
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F365F),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(12),
                            topRight: Radius.circular(12),
                          ),
                        ),
              child: Row(
                children: [
                            const Icon(
                              Icons.search,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${_searchResults.length} ${_searchResults.length == 1 ? 'result' : 'results'}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 20,
                              ),
                              onPressed: () {
                                _searchController.clear();
                                _searchFocusNode.unfocus();
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                ],
              ),
            ),
                      // Search Results List
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final result = _searchResults[index];
                            return _buildSearchResultTile(result);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // Empty state overlay
            if (_isSearchActive &&
                _searchController.text.isNotEmpty &&
                _searchResults.isEmpty)
              Positioned(
                top: 110,
                left: 0,
                right: 0,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_off,
                        color: Colors.grey[400],
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No results found',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Try searching for channels or members',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        floatingActionButton: _currentIndex == 0
            ? FloatingActionButton(
                backgroundColor: const Color(0xFF0F365F),
                onPressed: () {},
                child: const Icon(Icons.add, color: Colors.white),
              )
            : null,
        bottomNavigationBar: BottomNavigationBar(
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFF0F365F),
          unselectedItemColor: Colors.grey[600],
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.forum), label: 'DMs'),
            BottomNavigationBarItem(
                icon: Icon(Icons.notifications), label: 'Activity'),
          ],
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
        ),
              ),
    );
  }

  Widget _buildHomeTab() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
            // Channels Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Channels',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontFamily: 'Inter',
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.0,
                            ) ??
                        const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
            ),
                  TextButton(
                    onPressed: () {
                      // TODO: Navigate to all channels page
                    },
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'See all',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontFamily: 'Inter',
                                color: const Color(0xFF0F365F),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.0,
                              ) ??
                          const TextStyle(
                            color: Color(0xFF0F365F),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            ..._channels.expand((channel) {
              final isNewChannel = channel == widget.channelName &&
                  widget.channelName.isNotEmpty &&
                  !['General', 'Random'].contains(channel);
              return [
            _channelTile(
                  channel,
                  trailing: isNewChannel ? _startHere() : null,
                ),
                // Blue separator line after each channel
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  color: const Color(0xFF0F365F),
                ),
              ];
            }),
            _addChannelTile(),
            // Workspace Members Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Workspace Members',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontFamily: 'Inter',
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.0,
                            ) ??
                        const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          // TODO: Navigate to all members page
                        },
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'See all',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontFamily: 'Inter',
                                    color: const Color(0xFF0F365F),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.0,
                                  ) ??
                              const TextStyle(
                                color: Color(0xFF0F365F),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_isLoadingMembers)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF0F365F),
                          ),
                        )
                      else
                        Text(
                          '$_memberCount ${_memberCount == 1 ? 'member' : 'members'}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                        fontFamily: 'Inter',
                                        color: Colors.grey[600],
                                        fontSize: 14,
                                        letterSpacing: 0.0,
                                      ) ??
                                  TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                        ),
                      if (!_isLoadingMembers)
                        IconButton(
                          icon: const Icon(Icons.refresh,
                              color: Color(0xFF0F365F), size: 18),
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
                  child: CircularProgressIndicator(
                    color: Color(0xFF0F365F),
                  ),
                ),
              )
            else if (_workspaceMembers.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(
                  child: Text(
                    'No members found',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontFamily: 'Inter',
                              color: Colors.grey[600],
                              letterSpacing: 0.0,
                            ) ??
                        TextStyle(
                          color: Colors.grey[600],
                        ),
                  ),
                ),
              )
            else
              ..._workspaceMembers.expand((member) {
                return [
                  _memberTile(member),
                  // Blue separator line after each member
                  Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    color: const Color(0xFF0F365F),
                  ),
                ];
              }),
            _addMembersTile(),
            
            
      ],
    );
  }

  Widget _channelTile(String name, {Widget? trailing}) {
    return ListTile(
      leading: const Icon(Icons.tag, color: Color(0xFF0F365F)),
      title: Text(
        name,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontFamily: 'Inter',
                  color: Colors.black,
                  fontSize: 16,
                  letterSpacing: 0.0,
                ) ??
            const TextStyle(
              color: Colors.black,
              fontSize: 16,
            ),
      ),
      trailing: trailing != null
          ? ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 100),
              child: trailing,
            )
          : null,
      onTap: () async {
        final channel = name.replaceAll('#', '').trim();
        final channelLower = channel.toLowerCase();
        
        // Resolve to original channel name if it was renamed
        // (Channel database uses original name, but we display new name)
        // First, check our in-memory mapping from _loadChannels (fastest and most reliable)
        var originalName = _displayToOriginalName[channelLower];
        
        if (originalName == null) {
          // Fallback: Try SharedPreferences reverse mapping
          final prefs = await SharedPreferences.getInstance();
          final reverseMappingKey = 'channel_old_name_${widget.workspaceName}_$channel';
          originalName = prefs.getString(reverseMappingKey);
          
          // If still not found, check if this is an original name by checking all channel mappings
          if (originalName == null) {
            final mappingPrefix = 'channel_name_mapping_${widget.workspaceName}_';
            final allKeys = prefs.getKeys();
            for (var key in allKeys) {
              if (key.startsWith(mappingPrefix)) {
                final mappedName = prefs.getString(key);
                if (mappedName != null && mappedName.toLowerCase() == channelLower) {
                  // Extract original name from key: channel_name_mapping_{workspace}_{originalName}
                  originalName = key.substring(mappingPrefix.length);
                  print('🔍 [ChannelTile] Found original name via SharedPreferences mapping: "$originalName" for display name "$channel"');
                  break;
                }
              }
            }
          } else {
            print('🔍 [ChannelTile] Found original name via SharedPreferences reverse mapping: "$originalName" for display name "$channel"');
          }
        } else {
          print('✅ [ChannelTile] Found original name via in-memory mapping: "$originalName" for display name "$channel"');
        }
        
        // Use original name for database lookup, or current name if not renamed
        final channelNameForDb = originalName ?? channel;
        print('📂 [ChannelTile] Navigating to channel: display="$channel", db="$channelNameForDb"');
        
        if (mounted) {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChannelPage(
                channelName: channelNameForDb,
                workspaceName: widget.workspaceName,
              ),
            ),
          );
          
          // Check if channel was deleted or renamed
          if (result != null) {
            if (result['deleted'] == true) {
              // Channel was deleted, reload channels list
              print('🗑️ [ChannelTile] Channel was deleted, reloading channels list...');
              await _loadChannels();
              
              // Show feedback to user
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Channel has been deleted'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            } else if (result['channelName'] != null) {
              // Channel was renamed
              final newName = result['channelName'] as String;
              print('🔄 [ChannelTile] Channel name updated to "$newName", reloading channels list...');
              await _loadChannels();
              
              // Show feedback to user
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Channel renamed to "# $newName"'),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            }
          }
        }
      },
    );
  }

  Widget _addChannelTile() {
    return ListTile(
      leading: const Icon(Icons.add, color: Color(0xFF0F365F)),
      title: Text(
        'Add channel',
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontFamily: 'Inter',
                  color: Colors.black,
                  fontSize: 16,
                  letterSpacing: 0.0,
                ) ??
            const TextStyle(
              color: Colors.black,
              fontSize: 16,
            ),
      ),
      onTap: () => _showAddChannelDialog(),
    );
  }

  Future<void> _showAddChannelDialog() async {
    final TextEditingController channelController = TextEditingController();
    bool isLoading = false;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                'Create Channel',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontFamily: 'Inter',
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.0,
                    ) ??
                    const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Channel name',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontFamily: 'Inter',
                          color: Colors.black,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.0,
                        ) ??
                        const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: channelController,
                    autofocus: true,
                    maxLength: 50,
                    decoration: InputDecoration(
                      hintText: 'e.g. marketing, engineering',
                      hintStyle: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(
                            fontFamily: 'Inter',
                            color: Colors.grey[400],
                            letterSpacing: 0.0,
                          ) ??
                          TextStyle(color: Colors.grey[400]),
                      filled: true,
                      fillColor: const Color(0xFFF5F5F5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.grey[300]!,
                          width: 1,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.grey[300]!,
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF0F365F),
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      counterText: '',
                    ),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontFamily: 'Inter',
                          color: Colors.black,
                          letterSpacing: 0.0,
                        ) ??
                        const TextStyle(color: Colors.black),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () {
                          Navigator.of(context).pop();
                        },
                  child: Text(
                    'Cancel',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontFamily: 'Inter',
                          color: Colors.grey[600],
                          letterSpacing: 0.0,
                        ) ??
                        TextStyle(color: Colors.grey[600]),
                  ),
                ),
                FilledButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          final channelName =
                              channelController.text.trim().toLowerCase();
                          if (channelName.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please enter a channel name'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          // Check if channel already exists
                          if (_channels
                              .any((c) => c.toLowerCase() == channelName)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Channel already exists'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }

                          setDialogState(() {
                            isLoading = true;
                          });

                          try {
                            // Save channel to OrbitDB
                            await _createChannel(channelName);

                            setDialogState(() {
                              isLoading = false;
                            });

                            if (mounted) {
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Channel "$channelName" created successfully'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() {
                              isLoading = false;
                            });
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error creating channel: $e'),
                                  backgroundColor: Colors.red,
                                ),
    );
                            }
                          }
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F365F),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Create',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                fontFamily: 'Inter',
                                color: Colors.white,
                                letterSpacing: 0.0,
                              ) ??
                              const TextStyle(color: Colors.white),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _createChannel(String channelName) async {
    try {
      if (userAddress == null) {
        await _loadUserAddress();
      }
      if (_inviterAddress == null) {
        _inviterAddress = await OrbitDBService.getInviterAddressForWorkspace(
            widget.workspaceName);
      }

      if (userAddress == null || _inviterAddress == null) {
        throw Exception('User address or inviter address not found');
      }

      // Get or create workspace database
      final workspaceDbName = 'workspace_$_inviterAddress';
      var dbAddress =
          await OrbitDBService.getExistingDatabaseAddress(workspaceDbName);

      if (dbAddress == null) {
        dbAddress = await OrbitDBService.createChatDB(workspaceDbName);
        if (dbAddress == null) {
          throw Exception('Failed to create workspace database');
        }
      }

      // Create channel message
      final channelMessage = {
        'type': 'channel',
        'workspaceName': widget.workspaceName,
        'channelName': channelName,
        'createdBy': userAddress!.toLowerCase().trim(),
        'inviterAddress': _inviterAddress,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      // Save channel to workspace database
      final result = await OrbitDBService.addMessage(dbAddress, channelMessage);
      if (result == null) {
        throw Exception('Failed to save channel');
      }

      // Create channel database for messages
      final channelDbName =
          'channel_${_inviterAddress}_${widget.workspaceName}_$channelName';
      final channelDbAddress =
          await OrbitDBService.createChatDB(channelDbName);
      if (channelDbAddress == null) {
        print('⚠️ Warning: Could not create channel database');
      }

      // Update local channels list
      setState(() {
        _channels.add(channelName);
      });

      print('✅ Channel "$channelName" created successfully');
    } catch (e) {
      print('❌ Error creating channel: $e');
      rethrow;
    }
  }

  Widget _addMembersTile() {
    return ListTile(
      leading: const Icon(Icons.add, color: Color(0xFF0F365F)),
      title: Text(
        'Add Member',
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontFamily: 'Inter',
                  color: Colors.black,
                  fontSize: 16,
                  letterSpacing: 0.0,
                ) ??
            const TextStyle(
              color: Colors.black,
              fontSize: 16,
            ),
      ),
      onTap: () async {
        // Ensure user address is loaded
        if (userAddress == null) {
          await _loadUserAddress();
        }
        // Navigate to invite teammates page (from workspace home)
        if (userAddress != null) {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => InviteTeammatesPage(
                workspaceName: widget.workspaceName,
                userAddress: userAddress!,
                isFromWorkspaceHome: true,
              ),
            ),
          );
          
          // Reload members if members were added
          if (result == true && mounted) {
            await _loadWorkspaceMembers();
          }
        }
      },
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
          Text('Start here',
              style: TextStyle(color: Colors.black, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildSearchResultTile(Map<String, dynamic> result) {
    final type = result['type'];
    final displayName = result['displayName'] ?? result['name'] ?? '';
    
    IconData icon;
    Color iconColor;
    
    if (type == 'channel') {
      icon = Icons.tag;
      iconColor = const Color(0xFF0F365F);
    } else if (type == 'member') {
      icon = Icons.person;
      iconColor = const Color(0xFF0F365F);
    } else {
      // Default fallback (should not be reached)
      icon = Icons.tag;
      iconColor = const Color(0xFF0F365F);
    }
    
    return InkWell(
      onTap: () => _handleSearchResultTap(result),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Colors.grey[200]!,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: iconColor,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(
                      color: Color(0xFF333333),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    type == 'channel'
                        ? 'Channel'
                        : 'Member',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.grey[400],
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _memberTile(Map<String, dynamic> member) {
    final memberAddress = member['memberAddress']?.toString() ?? '';
    final isInviter = member['isInviter'] == true;
    final isCurrentUser = member['isCurrentUser'] == true ||
        (userAddress != null &&
            memberAddress.toLowerCase() == userAddress!.toLowerCase());

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
    final initial =
        nameForInitial.isNotEmpty ? nameForInitial[0].toUpperCase() : 'M';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor:
            isInviter ? const Color(0xFF23C16B) : const Color(0xFF0F365F),
        child: Text(
          initial,
          style: TextStyle(
            color: Colors.white,
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
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontFamily: 'Inter',
                        color: Colors.black,
                  fontSize: 16,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.0,
                      ) ??
                  const TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
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
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'Inter',
                        color: Colors.grey[600],
                        fontSize: 11,
                        letterSpacing: 0.0,
                      ) ??
                  TextStyle(
                    color: Colors.grey[600],
                    fontSize: 11,
                  ),
            ),
      onTap: () async {
        // Navigate to direct message page
        print('👆 Member tile tapped: $displayName');
        print('📍 Member address: $memberAddress');
        print('👤 Current user address: $userAddress');
        print('🔍 Is current user: $isCurrentUser');
        
        // Ensure user address is loaded
        if (userAddress == null) {
          print('⏳ Loading user address...');
          await _loadUserAddress();
        }
        
        // Check if member address is valid
        if (memberAddress.isEmpty) {
          print('❌ Member address is empty, cannot navigate');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid member address'),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }
        
        // Don't navigate if it's the current user
        if (isCurrentUser) {
          print('ℹ️ Cannot start DM with yourself');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You cannot message yourself'),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }
        
        // Check if user address is still null after loading
        if (userAddress == null) {
          print('❌ User address is still null after loading');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User session not found. Please login again.'),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }
        
        // Navigate to direct message page
        print('✅ Navigating to DirectMessagePage');
        print('   - Member: $memberAddress');
        print('   - Display Name: ${displayName.replaceAll('(you)', '').trim()}');
        print('   - Workspace: ${widget.workspaceName}');
        
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DirectMessagePage(
                memberAddress: memberAddress,
                memberDisplayName: displayName.replaceAll('(you)', '').trim(),
                workspaceName: widget.workspaceName,
              ),
            ),
          );
        }
      },
    );
  }
}

class WorkspaceDrawer extends StatefulWidget {
  final String currentWorkspaceName;
  final String userAddress;
  
  const WorkspaceDrawer({
    super.key,
    required this.currentWorkspaceName,
    required this.userAddress,
  });

  @override
  State<WorkspaceDrawer> createState() => _WorkspaceDrawerState();
}

class _WorkspaceDrawerState extends State<WorkspaceDrawer> {
  List<Map<String, dynamic>> _workspaces = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWorkspaces();
  }

  Future<void> _loadWorkspaces() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (widget.userAddress.isNotEmpty) {
        final workspaces = await OrbitDBService.getUserWorkspaces(widget.userAddress);
        setState(() {
          _workspaces = workspaces;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading workspaces: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _switchWorkspace(String workspaceName, String inviterAddress) async {
    try {
      // Save new workspace to session
      await OrbitDBService.saveLoginSession(
        widget.userAddress,
        workspaceName,
        'general', // Default channel
      );

      // Close drawer
      if (mounted) {
        Navigator.pop(context);
      }

      // Navigate to new workspace
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => TeamHomePage(
              workspaceName: workspaceName,
              channelName: 'general',
            ),
          ),
        );
      }
    } catch (e) {
      print('❌ Error switching workspace: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error switching workspace: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _navigateToCreateWorkspace() async {
    if (widget.userAddress.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User address not found'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Close drawer first
    Navigator.pop(context);

    // Navigate to create workspace page
    if (mounted) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CreateWorkspacePage(
            userAddress: widget.userAddress,
          ),
        ),
      );
      
      // Reload workspaces if a new workspace was created
      if (result == true && mounted) {
        await _loadWorkspaces();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 0.8,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topRight: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 8,
                offset: Offset(2, 0),
          ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top spacing for better visual hierarchy
              const SizedBox(height: 32),
              
              // Workspace Heading
              Padding(
                padding: const EdgeInsets.only(bottom: 20, top: 8),
                child: Text(
                  'Workspace',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontFamily: 'Inter',
                            color: const Color(0xFF1A1A1A),
                            fontWeight: FontWeight.bold,
                            fontSize: 24,
                            letterSpacing: -0.5,
                          ) ??
                      const TextStyle(
                        color: Color(0xFF1A1A1A),
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                        letterSpacing: -0.5,
                      ),
                ),
              ),
              
              // Current Workspace Card - Enhanced Design
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF0F365F).withOpacity(0.08),
                      const Color(0xFF0F365F).withOpacity(0.12),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF0F365F).withOpacity(0.2),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F365F).withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF0F365F),
                            Color(0xFF1A4A7A),
                          ],
                        ),
                      borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0F365F).withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                    ),
                        ],
                      ),
                      child: Center(
                      child: Text(
                          widget.currentWorkspaceName.isNotEmpty
                              ? widget.currentWorkspaceName[0].toUpperCase()
                              : 'W',
                          style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                            fontSize: 20,
                        ),
                      ),
                    ),
                  ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.currentWorkspaceName.isNotEmpty
                                ? widget.currentWorkspaceName
                                : 'Current Workspace',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      fontFamily: 'Inter',
                                      color: const Color(0xFF1A1A1A),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 17,
                                      letterSpacing: -0.3,
                                    ) ??
                                const TextStyle(
                                  color: Color(0xFF1A1A1A),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17,
                                  letterSpacing: -0.3,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.circle,
                                size: 6,
                                color: Colors.grey[500],
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Active workspace',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          fontFamily: 'Inter',
                                          color: Colors.grey[600],
                                          fontSize: 12,
                                          letterSpacing: 0.0,
                                        ) ??
                                    TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 13,
                                    ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F365F).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.check_circle,
                        color: Color(0xFF0F365F),
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 28),
              
              // Workspace Settings - Enhanced
              InkWell(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Workspace settings coming soon'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F365F).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.settings_outlined,
                          color: Color(0xFF0F365F),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'Workspace Settings',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontFamily: 'Inter',
                                  color: const Color(0xFF1A1A1A),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.0,
                                ) ??
                            const TextStyle(
                              color: Color(0xFF1A1A1A),
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Divider with better styling
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.grey[300]!,
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              
              // All Workspaces Section - Enhanced
              Padding(
                padding: const EdgeInsets.only(bottom: 16, top: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.workspaces_outlined,
                      size: 18,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'All Workspaces',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontFamily: 'Inter',
                                color: const Color(0xFF1A1A1A),
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                letterSpacing: -0.2,
                              ) ??
                          const TextStyle(
                            color: Color(0xFF1A1A1A),
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            letterSpacing: -0.2,
                          ),
                    ),
                  ],
                ),
              ),
              
              // Workspaces List
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0F365F)),
                        ),
                      )
                    : _workspaces.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.workspaces_outlined,
                                  size: 48,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No workspaces yet',
                          style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            itemCount: _workspaces.length,
                            itemBuilder: (context, index) {
                              final workspace = _workspaces[index];
                              final workspaceName = workspace['workspaceName']?.toString() ?? 'Unnamed Workspace';
                              final inviterAddress = workspace['inviterAddress']?.toString() ?? '';
                              final isCurrent = workspaceName.toLowerCase() == widget.currentWorkspaceName.toLowerCase();
                              
                              return InkWell(
                                onTap: isCurrent
                                    ? null
                                    : () => _switchWorkspace(workspaceName, inviterAddress),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: isCurrent 
                                        ? const Color(0xFF0F365F).withOpacity(0.05)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                    border: isCurrent
                                        ? Border.all(
                                            color: const Color(0xFF0F365F).withOpacity(0.2),
                                            width: 1,
                                          )
                                        : null,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          gradient: isCurrent
                                              ? const LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  colors: [
                                                    Color(0xFF0F365F),
                                                    Color(0xFF1A4A7A),
                                                  ],
                                                )
                                              : null,
                                          color: isCurrent ? null : Colors.grey[200],
                                          borderRadius: BorderRadius.circular(10),
                                          boxShadow: isCurrent
                                              ? [
                                                  BoxShadow(
                                                    color: const Color(0xFF0F365F).withOpacity(0.2),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ]
                                              : null,
                                        ),
                                        child: Center(
                                          child: Text(
                                            workspaceName.isNotEmpty
                                                ? workspaceName[0].toUpperCase()
                                                : 'W',
                                            style: TextStyle(
                                              color: isCurrent ? Colors.white : Colors.grey[700],
                              fontWeight: FontWeight.bold,
                                              fontSize: 17,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Text(
                                          workspaceName,
                                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                                    fontFamily: 'Inter',
                                                    color: isCurrent 
                                                        ? const Color(0xFF0F365F) 
                                                        : const Color(0xFF1A1A1A),
                                                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
                                                    fontSize: 15,
                                                    letterSpacing: -0.2,
                                                  ) ??
                                              TextStyle(
                                                color: isCurrent 
                                                    ? const Color(0xFF0F365F) 
                                                    : const Color(0xFF1A1A1A),
                                                fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
                                                fontSize: 15,
                                                letterSpacing: -0.2,
                                              ),
                                        ),
                                      ),
                                      if (isCurrent)
                                        Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF0F365F).withOpacity(0.1),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.check_circle,
                                            color: Color(0xFF0F365F),
                                            size: 18,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
              
              // Divider with better styling
              Container(
                margin: const EdgeInsets.symmetric(vertical: 16),
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.grey[300]!,
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              
              // Add Workspace Button - Enhanced
              InkWell(
                onTap: _navigateToCreateWorkspace,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F365F).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF0F365F).withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F365F).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.add_rounded,
                          color: Color(0xFF0F365F),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'Add Workspace',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontFamily: 'Inter',
                                  color: const Color(0xFF0F365F),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                  letterSpacing: 0.0,
                                ) ??
                            const TextStyle(
                              color: Color(0xFF0F365F),
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Logout Button - Enhanced
              InkWell(
                onTap: () async {
                  // Clear login session on logout
                  await OrbitDBService.clearLoginSession();
                  print('🚪 Logging out (session cleared)');

                  Navigator.of(context).pop();
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                        builder: (context) => const LoginScreen()),
                    (route) => false,
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.logout_rounded,
                          color: Colors.redAccent,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Text(
                        'Logout',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Bottom spacing
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// User Profile Page
class UserProfilePage extends StatefulWidget {
  final String userAddress;
  final String workspaceName;

  const UserProfilePage({
    super.key,
    required this.userAddress,
    required this.workspaceName,
  });

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  Map<String, dynamic>? _profileData;
  bool _isLoading = true;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final key = widget.userAddress.toLowerCase().trim();
      final dbName = 'profile_$key';
      final dbAddress = await OrbitDBService.getExistingDatabaseAddress(dbName);

      if (dbAddress != null) {
        final messages = await OrbitDBService.getMessages(dbAddress);
        
        for (var message in messages) {
          if (message['type'] == 'profile' &&
              message['userAddress']?.toString().toLowerCase() == key) {
            setState(() {
              _profileData = message;
              _isLoading = false;
            });
            return;
          }
        }
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error loading profile: $e');
      setState(() {
        _isLoading = false;
        _status = 'Error loading profile: $e';
      });
    }
  }

  Future<void> _editProfile() async {
    if (_profileData == null) return;

    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProfileSetupScreen(
          address: widget.userAddress,
          show2FASetup: false,
        ),
      ),
    );

    // Reload profile after editing
    if (result == true || mounted) {
      await _loadProfileData();
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await OrbitDBService.clearLoginSession();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final firstName = _profileData?['firstName']?.toString() ?? '';
    final lastName = _profileData?['lastName']?.toString() ?? '';
    final fullName = '${firstName} ${lastName}'.trim();
    final username = _profileData?['username']?.toString() ?? fullName;
    final email = _profileData?['email']?.toString() ?? '';
    final designation = _profileData?['designation']?.toString() ?? '';
    final userAddress = widget.userAddress;
    final initial = username.isNotEmpty ? username[0].toUpperCase() : 'U';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F365F),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Profile',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.white),
            onPressed: _editProfile,
            tooltip: 'Edit Profile',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0F365F)),
              ),
            )
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Profile Header Section
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0F365F),
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(24),
                        bottomRight: Radius.circular(24),
                      ),
                    ),
                    child: Column(
                      children: [
                        // Profile Avatar
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.white.withOpacity(0.2),
                          child: Text(
                            initial,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Full Name
                        Text(
                          username.isNotEmpty ? username : 'User',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (designation.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            designation,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Profile Information Section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Profile Information',
                          style: TextStyle(
                            color: Color(0xFF333333),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // First Name
                        _buildInfoCard(
                          icon: Icons.person_outline,
                          label: 'First Name',
                          value: firstName.isNotEmpty ? firstName : 'Not set',
                        ),
                        const SizedBox(height: 12),
                        // Last Name
                        _buildInfoCard(
                          icon: Icons.person_outline,
                          label: 'Last Name',
                          value: lastName.isNotEmpty ? lastName : 'Not set',
                        ),
                        const SizedBox(height: 12),
                        // Email
                        _buildInfoCard(
                          icon: Icons.email_outlined,
                          label: 'Email',
                          value: email.isNotEmpty ? email : 'Not set',
                        ),
                        const SizedBox(height: 12),
                        // Designation
                        _buildInfoCard(
                          icon: Icons.work_outline,
                          label: 'Designation',
                          value: designation.isNotEmpty ? designation : 'Not set',
                        ),
                        const SizedBox(height: 12),
                        // Wallet Address
                        _buildInfoCard(
                          icon: Icons.account_balance_wallet_outlined,
                          label: 'Wallet Address',
                          value: userAddress.length > 20
                              ? '${userAddress.substring(0, 10)}...${userAddress.substring(userAddress.length - 8)}'
                              : userAddress,
                          isCopyable: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Action Buttons Section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        // Edit Profile Button
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _editProfile,
                            icon: const Icon(Icons.edit, size: 20),
                            label: const Text('Edit Profile'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF0F365F),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Account Settings Button
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Account settings coming soon'),
                                ),
                              );
                            },
                            icon: const Icon(Icons.settings_outlined, size: 20),
                            label: const Text('Account Settings'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF0F365F),
                              side: const BorderSide(color: Color(0xFF0F365F)),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Privacy & Security Button
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Privacy & Security coming soon'),
                                ),
                              );
                            },
                            icon: const Icon(Icons.lock_outline, size: 20),
                            label: const Text('Privacy & Security'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF0F365F),
                              side: const BorderSide(color: Color(0xFF0F365F)),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Logout Button
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _logout,
                            icon: const Icon(Icons.logout, size: 20),
                            label: const Text('Logout'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Status message
                  if (_status.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _status.contains('Error')
                              ? Colors.red.withOpacity(0.1)
                              : Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _status,
                          style: TextStyle(
                            color: _status.contains('Error')
                                ? Colors.red[700]
                                : Colors.green[700],
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
    bool isCopyable = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: const Color(0xFF0F365F),
            size: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF333333),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (isCopyable)
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              color: const Color(0xFF0F365F),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: widget.userAddress));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Wallet address copied to clipboard'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}


