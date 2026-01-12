
import 'package:flutter/material.dart';
import 'channel_page.dart';
import 'login_screen.dart';
import 'package:flutter/services.dart';
import 'services/session_service.dart';
import 'services/distributed_service.dart';
import 'services/hybrid_storage_service.dart';
import 'services/p2p_service.dart';
import 'dart:async';
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
  String? _workspaceId; // Store workspaceId for reuse
  int _currentIndex = 0;
  List<String> _channels = ['General', 'Random'];
  // Map to track display name -> original database name (for proper database lookups)
  final Map<String, String> _displayToOriginalName = {};
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isSearchActive = false;
  List<Map<String, dynamic>> _searchResults = [];

  DateTime? _lastChannelLoadTime;
  
  // Real-time channel updates
  Timer? _channelPollingTimer;
  bool _isCheckingChannels = false;
  
  // Track which channel is showing delete icon (long pressed)
  String? _channelWithDeleteIcon;

  @override
  void initState() {
    super.initState();
    print('🏢 Workspace Home Page initialized');
    print('📋 Workspace Name: ${widget.workspaceName}');
    print('📋 Channel Name: ${widget.channelName}');
    _loadData();
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(_onSearchFocusChanged);
    
    // Set up real-time channel updates
    _setupRealTimeChannelUpdates();
  }
  
  /// Set up real-time channel updates (polling + P2P callbacks)
  void _setupRealTimeChannelUpdates() {
    // Set up P2P callback for channel creation events
    P2PService.instance.onChannelCreated = (channelData) {
      final workspaceId = channelData['workspace_id']?.toString();
      final channelName = channelData['channel_name']?.toString();
      
      // Check if this channel is for the current workspace
      final effectiveWorkspaceId = _workspaceId ?? widget.workspaceName;
      if (workspaceId == effectiveWorkspaceId || workspaceId == widget.workspaceName) {
        print('📢 Real-time P2P channel creation received: $channelName in workspace $workspaceId');
        // Reload channels to show the new channel
        _loadChannels();
      }
    };
    
    // Start periodic polling for new channels (every 3 seconds)
    _channelPollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted && !_isCheckingChannels) {
        _checkForNewChannels();
      }
    });
    
    print('✅ Real-time channel updates enabled (polling every 3s + P2P callbacks)');
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
    // Cancel real-time update timer
    _channelPollingTimer?.cancel();
    _channelPollingTimer = null;
    
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
    // CRITICAL: Resolve workspace ID FIRST before loading members and channels
    // This ensures consistent workspace ID usage throughout
    await _resolveWorkspaceId();
    await _loadWorkspaceMembers();
    await _loadChannels();
  }
  
  /// Resolve workspace ID from workspace name (CRITICAL for consistency)
  Future<void> _resolveWorkspaceId() async {
    if (_workspaceId != null) {
      return; // Already resolved
    }
    
    try {
      if (userAddress == null) {
        await _loadUserAddress();
      }
      
      if (userAddress == null) {
        print('⚠️ Cannot resolve workspace ID: user address is null');
        _workspaceId = widget.workspaceName; // Fallback
        return;
      }
      
      print('🔍 Resolving workspace ID for workspace name: ${widget.workspaceName}');
      
      // Try SQLite first (works offline)
      try {
        final sqliteWorkspaces = await HybridStorageService.instance.getUserWorkspaces(userAddress!);
        final sqliteWorkspace = sqliteWorkspaces.firstWhere(
          (w) => (w['name']?.toString() ?? w['workspaceName']?.toString()) == widget.workspaceName,
          orElse: () => {},
        );
        
        if (sqliteWorkspace.isNotEmpty) {
          _workspaceId = sqliteWorkspace['workspace_id']?.toString() ?? 
                        sqliteWorkspace['workspaceId']?.toString() ??
                        widget.workspaceName;
          print('✅ Resolved workspace ID from SQLite: $_workspaceId');
          return;
        }
      } catch (e) {
        print('⚠️ Could not resolve workspace ID from SQLite: $e');
      }
      
      // Try server (if online)
      try {
        final workspaces = await DistributedService.getUserWorkspaces(userAddress!);
        final workspace = workspaces.firstWhere(
          (w) => (w['name']?.toString() ?? w['workspaceName']?.toString()) == widget.workspaceName,
          orElse: () => {},
        );
        
        if (workspace.isNotEmpty) {
          _workspaceId = workspace['workspace_id']?.toString() ?? 
                        workspace['workspaceId']?.toString() ??
                        widget.workspaceName;
          print('✅ Resolved workspace ID from server: $_workspaceId');
          return;
        }
      } catch (e) {
        print('⚠️ Could not resolve workspace ID from server: $e');
      }
      
      // Fallback to workspace name
      _workspaceId = widget.workspaceName;
      print('⚠️ Using workspace name as ID (fallback): $_workspaceId');
    } catch (e) {
      print('❌ Error resolving workspace ID: $e');
      _workspaceId = widget.workspaceName; // Fallback
    }
  }

  Future<void> _loadChannels() async {
    try {
      if (userAddress == null) {
        await _loadUserAddress();
      }

      print('📋 Loading channels for workspace: ${widget.workspaceName}');
      
      // CRITICAL: Ensure workspace ID is resolved BEFORE loading channels
      // This prevents different channel orders (workspace name vs workspace ID)
      if (_workspaceId == null) {
        await _resolveWorkspaceId();
      }
      
      // Use resolved workspace ID (never use workspace name directly)
      final effectiveWorkspaceId = _workspaceId ?? widget.workspaceName;
      print('📋 Using workspace ID: $effectiveWorkspaceId (name: ${widget.workspaceName})');
      
      // Use HybridStorageService (works offline with SQLite fallback)
      // Pass memberAddress so user only sees channels they have access to
      final channels = await HybridStorageService.instance.getWorkspaceChannels(
        workspaceId: effectiveWorkspaceId,
        memberAddress: userAddress, // Filter channels accessible to this member
      );

      // Ensure General and Random are always present (built-in channels)
      final Set<String> channelSet = channels.toSet();
      if (!channelSet.contains('General')) {
        channels.insert(0, 'General');
      }
      if (!channelSet.contains('Random')) {
        // Insert Random after General
        final generalIndex = channels.indexOf('General');
        channels.insert(generalIndex + 1, 'Random');
      }

      // Ensure proper sorting: General first, Random second, then user-created channels
      channels.sort((a, b) {
        final aLower = a.toLowerCase();
        final bLower = b.toLowerCase();
        if (aLower == 'general') return -1;
        if (bLower == 'general') return 1;
        if (aLower == 'random') return -1;
        if (bLower == 'random') return 1;
        return a.compareTo(b);
      });

      // Ensure initial channel is present if specified (user-created channels)
      if (widget.channelName.isNotEmpty && 
          widget.channelName.toLowerCase() != 'general' && 
          widget.channelName.toLowerCase() != 'random') {
        final normalizedName = widget.channelName.toLowerCase();
        final displayName = widget.channelName;
        if (!channels.any((c) => c.toLowerCase() == normalizedName)) {
          channels.add(displayName);
          // Sort again after adding (maintain General and Random first)
          channels.sort((a, b) {
            final aLower = a.toLowerCase();
            final bLower = b.toLowerCase();
            if (aLower == 'general') return -1;
            if (bLower == 'general') return 1;
            if (aLower == 'random') return -1;
            if (bLower == 'random') return 1;
            return a.compareTo(b);
          });
        }
      }

      if (mounted) {
        setState(() {
          _channels = channels;
          _lastChannelLoadTime = DateTime.now();
        });
        print('📊 Loaded ${channels.length} channels: ${channels.join(", ")}');
      }

    } catch (e) {
      print('❌ Error loading channels: $e');
      // On error, at least show default channels
      if (mounted) {
        setState(() {
          _channels = ['General', 'Random'];
        });
      }
    }
  }

  /// Check for new channels (real-time update)
  Future<void> _checkForNewChannels() async {
    // Prevent multiple simultaneous checks
    if (_isCheckingChannels || !mounted) {
      return;
    }
    
    _isCheckingChannels = true;
    
    try {
      // CRITICAL: Ensure workspace ID is resolved BEFORE checking for new channels
      // This ensures consistent workspace ID usage
      if (_workspaceId == null) {
        await _resolveWorkspaceId();
      }
      
      // Use resolved workspace ID (never use workspace name directly)
      final effectiveWorkspaceId = _workspaceId ?? widget.workspaceName;
      
      // Load channels from server
      final loadedChannels = await HybridStorageService.instance.getWorkspaceChannels(
        workspaceId: effectiveWorkspaceId,
        memberAddress: userAddress,
      );

      // Ensure General and Random are always present
      final Set<String> channelSet = loadedChannels.toSet();
      if (!channelSet.contains('General')) {
        loadedChannels.insert(0, 'General');
      }
      if (!channelSet.contains('Random')) {
        final generalIndex = loadedChannels.indexOf('General');
        loadedChannels.insert(generalIndex + 1, 'Random');
      }

      // Sort channels
      loadedChannels.sort((a, b) {
        final aLower = a.toLowerCase();
        final bLower = b.toLowerCase();
        if (aLower == 'general') return -1;
        if (bLower == 'general') return 1;
        if (aLower == 'random') return -1;
        if (bLower == 'random') return 1;
        return a.compareTo(b);
      });

      // Use proper deduplication - compare channel lists
      final existingChannelsSet = _channels.toSet();
      final loadedChannelsSet = loadedChannels.toSet();
      
      // Find new channels (not already in _channels)
      final newChannels = loadedChannels.where((channel) => 
        !existingChannelsSet.contains(channel)
      ).toList();
      
      // Find removed channels (in _channels but not in loadedChannels)
      final removedChannels = _channels.where((channel) => 
        !loadedChannelsSet.contains(channel)
      ).toList();
      
      // Only update if there are changes
      if ((newChannels.isNotEmpty || removedChannels.isNotEmpty) && mounted) {
        print('📥 Real-time channel update: Found ${newChannels.length} new, ${removedChannels.length} removed (${loadedChannels.length} total, ${_channels.length} existing)');
        
        setState(() {
          _channels = loadedChannels;
          _lastChannelLoadTime = DateTime.now();
        });
        
        if (newChannels.isNotEmpty) {
          print('✅ Real-time update: Added ${newChannels.length} new channels: ${newChannels.join(", ")}');
        }
        if (removedChannels.isNotEmpty) {
          print('⚠️ Real-time update: Removed ${removedChannels.length} channels: ${removedChannels.join(", ")}');
        }
      }
    } catch (e) {
      print('❌ Error checking for new channels: $e');
    } finally {
      _isCheckingChannels = false;
    }
  }

  Future<void> _saveInitialChannel(String channelName) async {
    try {
      // TODO: Implement channel creation in MongoDB
      // For now, just log that we would create it
      print('ℹ️ TODO: Save initial channel "$channelName" to MongoDB');
      print('📝 Would create channel in workspace: ${widget.workspaceName}');
    } catch (e) {
      print('❌ Error saving initial channel: $e');
    }
  }

  Future<void> _loadUserAddress() async {
    try {
      final session = await SessionService.getLoginSession();
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

      print('🔍 Loading username from MongoDB for: $userAddress');
      final profile = await DistributedService.getUserProfile(userAddress!);

      if (profile != null) {
        final username = profile['username']?.toString();
        print('📋 Found username: $username');
        return username;
      } else {
        print('❌ Profile not found in MongoDB');
      }
      return null;
    } catch (e) {
      print('❌ Error loading username from MongoDB: $e');
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

      print('👥 Loading members for workspace: ${widget.workspaceName}');
      
      // Ensure workspace ID is resolved (for offline support)
      if (_workspaceId == null) {
        await _resolveWorkspaceId();
      }
      
      // Use resolved workspace ID or fallback to workspace name
      final effectiveWorkspaceId = _workspaceId ?? widget.workspaceName;
      
      // Get workspace info using HybridStorageService (works offline)
      try {
        final workspaces = await HybridStorageService.instance.getUserWorkspaces(userAddress!);
        final workspace = workspaces.firstWhere(
          (w) => (w['name']?.toString() ?? w['workspaceName']?.toString()) == widget.workspaceName,
          orElse: () => {},
        );
        
        if (workspace.isNotEmpty) {
          final workspaceId = workspace['workspace_id']?.toString() ?? 
                             workspace['workspaceId']?.toString() ??
                             widget.workspaceName;
          _workspaceId = workspaceId; // Store for reuse
          _inviterAddress = workspace['inviter_address']?.toString() ?? 
                           workspace['inviterAddress']?.toString();
        }
      } catch (e) {
        print('⚠️ Could not load workspace info: $e');
      }
      
      // Get members using HybridStorageService (works offline via SQLite fallback)
      if (effectiveWorkspaceId.isEmpty) {
        print('❌ WorkspaceId is empty, cannot load members');
        setState(() {
          _isLoadingMembers = false;
          _memberCount = 0;
        });
        return;
      }
      
      print('📦 Loading members for workspace ID: $effectiveWorkspaceId');
      final allMembers = await HybridStorageService.instance.getWorkspaceMembers(effectiveWorkspaceId);

      // CRITICAL: Deduplicate members by address (case-insensitive)
      // This prevents duplicate members from showing up
      final seenAddresses = <String>{};
      final deduplicatedMembers = <Map<String, dynamic>>[];
      
      for (final member in allMembers) {
        final memberAddr = (member['member_address']?.toString() ?? 
                           member['memberAddress']?.toString() ?? '').toLowerCase().trim();
        
        if (memberAddr.isNotEmpty && !seenAddresses.contains(memberAddr)) {
          seenAddresses.add(memberAddr);
          deduplicatedMembers.add(member);
        } else if (memberAddr.isNotEmpty) {
          print('⚠️ Skipping duplicate member: $memberAddr');
        }
      }
      
      print('📊 After deduplication: ${deduplicatedMembers.length} unique members (from ${allMembers.length} total)');
      final members = deduplicatedMembers;

      // Ensure current logged-in user is in the members list
      if (userAddress != null) {
        final userKey = userAddress!.toLowerCase().trim();
        final userExists = members.any(
            (m) => (m['member_address']?.toString() ?? 
                   m['memberAddress']?.toString() ?? '').toLowerCase() == userKey);

        if (!userExists) {
          print('➕ Adding current user to members list');
          // Get current user's display name
          final userDisplayName = await _getUserNameFromOrbitDB();

          members.add({
            'type': 'member',
            'workspaceName': widget.workspaceName,
            'inviterAddress': _inviterAddress ?? '',
            'member_address': userKey,
            'memberAddress': userKey,
            'memberDisplayName': userDisplayName,
            'display_name': userDisplayName,
            'joinedAt': DateTime.now().millisecondsSinceEpoch,
            'joined_at': DateTime.now().millisecondsSinceEpoch,
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
        final memberAddr = (member['member_address']?.toString() ?? 
                           member['memberAddress']?.toString() ?? '').toLowerCase().trim();
        if (memberAddr.isNotEmpty) {
          print('📝 Processing member ${i + 1}/${members.length}: $memberAddr');

          // Always fetch profile name to ensure we have the latest
          final profileName = await _getProfileNameForAddress(memberAddr);

          if (profileName != null && profileName.isNotEmpty) {
            // Update display name with profile name (prefer profile name over stored display name)
            member['memberDisplayName'] = profileName;
            member['display_name'] = profileName;
            print('✅ Updated member $memberAddr with name: $profileName');
          } else {
            // If no profile name found, check if we have a stored display name
            final storedName = member['memberDisplayName']?.toString() ?? 
                             member['display_name']?.toString();
            if (storedName == null || storedName.isEmpty) {
              print(
                  '⚠️ No profile name found for member: $memberAddr (will use address)');
              // Clear any empty display name
              member.remove('memberDisplayName');
              member.remove('display_name');
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

  /// Get profile name (username) for a given address (hybrid - works offline)
  Future<String?> _getProfileNameForAddress(String address) async {
    try {
      print('🔍 Fetching profile name for: $address (offline-capable)');

      // Use HybridStorageService for offline support (falls back to SQLite)
      final profile = await HybridStorageService.instance.getUserProfile(address);

      if (profile != null) {
        final username = profile['username']?.toString();
        if (username != null && username.isNotEmpty) {
          print('✅ Found username: $username for address: $address');
          return username;
        }
      }

      print('⚠️ No profile found for address: $address');
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
    final isDefaultChannel = name.toLowerCase() == 'general' || name.toLowerCase() == 'random';
    final showDeleteIcon = _channelWithDeleteIcon == name && !isDefaultChannel;
    
    return GestureDetector(
      onLongPress: () {
        if (!isDefaultChannel) {
          setState(() {
            _channelWithDeleteIcon = name;
          });
        }
      },
      child: ListTile(
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
        trailing: showDeleteIcon
            ? IconButton(
                icon: const Icon(Icons.delete, color: Colors.red, size: 22),
                onPressed: () => _deleteChannel(name),
                tooltip: 'Delete channel',
              )
            : (trailing != null
                ? ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 100),
                    child: trailing,
                  )
                : null),
        onTap: () async {
          // Hide delete icon if shown (but still allow navigation)
          if (_channelWithDeleteIcon == name) {
            setState(() {
              _channelWithDeleteIcon = null;
            });
          }
          
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
      ),
    );
  }

  /// Delete channel - Remove from server, SQLite, and clean up all related data
  Future<void> _deleteChannel(String channelName) async {
    try {
      // Hide delete icon immediately
      setState(() {
        _channelWithDeleteIcon = null;
      });
      
      // Prevent deletion of default channels
      final channelLower = channelName.toLowerCase().trim();
      if (channelLower == 'general' || channelLower == 'random') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Default channels (General, Random) cannot be deleted'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }
      
      // Resolve workspace ID
      if (_workspaceId == null) {
        await _resolveWorkspaceId();
      }
      final effectiveWorkspaceId = _workspaceId ?? widget.workspaceName;
      
      // Resolve original channel name if renamed
      var originalChannelName = _displayToOriginalName[channelLower];
      if (originalChannelName == null) {
        final prefs = await SharedPreferences.getInstance();
        final reverseMappingKey = 'channel_old_name_${widget.workspaceName}_$channelName';
        originalChannelName = prefs.getString(reverseMappingKey);
        
        if (originalChannelName == null) {
          final mappingPrefix = 'channel_name_mapping_${widget.workspaceName}_';
          final allKeys = prefs.getKeys();
          for (var key in allKeys) {
            if (key.startsWith(mappingPrefix)) {
              final mappedName = prefs.getString(key);
              if (mappedName != null && mappedName.toLowerCase() == channelLower) {
                originalChannelName = key.substring(mappingPrefix.length);
                break;
              }
            }
          }
        }
      }
      final channelIdForDb = originalChannelName ?? channelName;
      final normalizedChannelId = channelIdForDb.toLowerCase().trim();
      
      print('🗑️ [DeleteChannel] Deleting channel: "$channelName" (ID: "$normalizedChannelId")');
      
      // 1. Delete from server and SQLite using HybridStorageService
      final deleteSuccess = await HybridStorageService.instance.deleteChannel(
        workspaceId: effectiveWorkspaceId,
        channelId: normalizedChannelId,
      );
      
      if (!deleteSuccess) {
        throw Exception('Failed to delete channel from server or SQLite');
      }
      
      // 2. Clean up SharedPreferences mappings
      final prefs = await SharedPreferences.getInstance();
      
      // Remove forward mapping (original -> display)
      final mappingKey = 'channel_name_mapping_${widget.workspaceName}_$normalizedChannelId';
      await prefs.remove(mappingKey);
      print('🗑️ [DeleteChannel] Removed forward mapping: $mappingKey');
      
      // Remove reverse mapping (display -> original)
      final reverseMappingKey = 'channel_old_name_${widget.workspaceName}_$channelName';
      await prefs.remove(reverseMappingKey);
      print('🗑️ [DeleteChannel] Removed reverse mapping: $reverseMappingKey');
      
      // Also check if there are any other mappings for this channel (in case of multiple renames)
      final mappingPrefix = 'channel_name_mapping_${widget.workspaceName}_';
      final oldNamePrefix = 'channel_old_name_${widget.workspaceName}_';
      final allKeys = prefs.getKeys();
      
      for (var key in allKeys) {
        if (key.startsWith(mappingPrefix)) {
          final mappedValue = prefs.getString(key);
          if (mappedValue != null && 
              (mappedValue.toLowerCase() == channelName.toLowerCase() ||
               mappedValue.toLowerCase() == normalizedChannelId)) {
            await prefs.remove(key);
            print('🗑️ [DeleteChannel] Removed related mapping: $key');
          }
        } else if (key.startsWith(oldNamePrefix)) {
          final mappedValue = prefs.getString(key);
          if (mappedValue != null && 
              (mappedValue.toLowerCase() == normalizedChannelId ||
               mappedValue.toLowerCase() == channelName.toLowerCase())) {
            await prefs.remove(key);
            print('🗑️ [DeleteChannel] Removed related reverse mapping: $key');
          }
        }
      }
      
      // 3. Remove notification and mute preferences
      final notificationsKey = 'channel_notifications_${widget.workspaceName}_$channelName';
      final muteKey = 'channel_muted_${widget.workspaceName}_$channelName';
      await prefs.remove(notificationsKey);
      await prefs.remove(muteKey);
      print('🗑️ [DeleteChannel] Removed notification preferences');
      
      // 4. Remove from in-memory mapping
      _displayToOriginalName.remove(channelLower);
      
      // 5. Reload channels list
      await _loadChannels();
      
      print('✅ [DeleteChannel] Channel deleted successfully: "$channelName"');
      
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Channel "# $channelName" has been deleted'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('❌ Error deleting channel: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting channel: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
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
                          // Get original channel name (preserve case)
                          final originalChannelName = channelController.text.trim();
                          final normalizedInput = originalChannelName.toLowerCase().trim();
                          
                          if (normalizedInput.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please enter a channel name'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          // Check if channel already exists (case-insensitive)
                          final reservedNames = ['general', 'random'];
                          
                          if (reservedNames.contains(normalizedInput)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('General and Random are reserved channel names'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }
                          
                          if (_channels.any((c) => c.toLowerCase().trim() == normalizedInput)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Channel "$originalChannelName" already exists'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }

                          setDialogState(() {
                            isLoading = true;
                          });

                          try {
                            // Save channel to database (pass original name to preserve case)
                            await _createChannel(originalChannelName);

                            setDialogState(() {
                              isLoading = false;
                            });

                            if (mounted) {
                              Navigator.of(context).pop();
                              
                              // Reload channels list to show the new channel
                              await _loadChannels();
                              
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Channel "$originalChannelName" created successfully'),
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
                                  content: Text('Error creating channel: ${e.toString()}'),
                                  backgroundColor: Colors.red,
                                  duration: const Duration(seconds: 3),
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
      if (userAddress == null) throw Exception('User not found');

      // Ensure workspaceId is loaded
      if (_workspaceId == null) {
        try {
          final workspaces = await DistributedService.getUserWorkspaces(userAddress!);
          final workspace = workspaces.firstWhere(
            (w) => w['name'] == widget.workspaceName || 
                   w['workspaceName'] == widget.workspaceName,
            orElse: () => {},
          );
          
          if (workspace.isNotEmpty) {
            _workspaceId = workspace['workspace_id']?.toString() ?? 
                          workspace['workspaceId']?.toString();
          } else {
            _workspaceId = widget.workspaceName; // Fallback
          }
        } catch (e) {
          _workspaceId = widget.workspaceName; // Fallback
        }
      }
      
      if (_workspaceId == null) {
        throw Exception('Workspace ID not found');
      }

      // Normalize channel name (lowercase for database, but keep original for display)
      final normalizedChannelName = channelName.toLowerCase().trim();
      
      // Validate channel name
      if (normalizedChannelName.isEmpty) {
        throw Exception('Channel name cannot be empty');
      }
      
      // Check for reserved names
      final reservedNames = ['general', 'random'];
      if (reservedNames.contains(normalizedChannelName)) {
        throw Exception('General and Random are reserved channel names');
      }
      
      // Check for duplicates before creating (case-insensitive)
      // Use try-catch to handle server offline scenarios gracefully
      try {
        final existingChannels = await DistributedService.getWorkspaceChannels(
          workspaceId: _workspaceId!,
        ).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            print('⚠️ Get channels request timed out, checking SQLite for duplicates');
            return <String>[]; // Return empty list on timeout, will check SQLite below
          },
        );
        
        if (existingChannels.any((c) => c.toLowerCase().trim() == normalizedChannelName)) {
          throw Exception('Channel "$channelName" already exists in this workspace');
        }
      } catch (e) {
        // If server is offline or error occurs, check local SQLite
        if (e.toString().contains('already exists')) {
          rethrow; // Re-throw duplicate error
        }
        print('⚠️ Could not check server for duplicates, checking SQLite: $e');
        final sqliteChannels = await HybridStorageService.instance.getWorkspaceChannels(
          workspaceId: _workspaceId!,
        );
        
        if (sqliteChannels.any((c) => c.toLowerCase().trim() == normalizedChannelName)) {
          throw Exception('Channel "$channelName" already exists in this workspace');
        }
      }
      
      // Save channel metadata to database
      // Use try-catch to handle server offline scenarios gracefully
      bool channelCreated = false;
      try {
        channelCreated = await DistributedService.createChannel(
          workspaceId: _workspaceId!,
          channelId: normalizedChannelName,
          creatorAddress: userAddress!,
          channelName: channelName, // Keep original case for display
        ).timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            print('⚠️ Create channel request timed out, saving to SQLite only');
            return false; // Will save to SQLite only
          },
        );
      } catch (e) {
        print('⚠️ Server channel creation failed, will save to SQLite only: $e');
        // Continue to SQLite save even if server fails
        channelCreated = false;
      }

      // If server creation failed, still save to SQLite for offline access
      if (!channelCreated) {
        print('⚠️ Server channel creation failed or timed out, saving to SQLite only');
        // Don't throw error - channel will be saved to SQLite for offline access
      }

      // CRITICAL: Save channel to SQLite immediately (for offline mode)
      // This ensures channel shows up even when server is off
      await HybridStorageService.instance.saveChannelToSQLite(
        workspaceId: _workspaceId!,
        channelId: normalizedChannelName,
        channelName: channelName,
        creatorAddress: userAddress!,
      );
      print('✅ Channel "$channelName" saved to SQLite for offline access');

      // CRITICAL: Broadcast channel creation via P2P to all workspace members
      // This ensures receiver devices know about the new channel even when server is off
      try {
        final members = await HybridStorageService.instance.getWorkspaceMembers(_workspaceId!);
        print('📡 Broadcasting channel creation to ${members.length} workspace members via P2P...');
        
        int broadcastCount = 0;
        for (final member in members) {
          final memberAddress = member['member_address']?.toString() ?? 
                              member['memberAddress']?.toString();
          
          if (memberAddress == null || memberAddress == userAddress) {
            continue; // Skip self
          }
          
          try {
            final broadcasted = await P2PService.instance.broadcastChannelCreated(
              receiverAddress: memberAddress,
              workspaceId: _workspaceId!,
              channelId: normalizedChannelName,
              channelName: channelName,
              creatorAddress: userAddress!,
            );
            
            if (broadcasted) {
              broadcastCount++;
            }
          } catch (e) {
            print('⚠️ Failed to broadcast channel creation to $memberAddress: $e');
          }
        }
        
        print('✅ Channel creation broadcasted to $broadcastCount/${members.length} members via P2P');
      } catch (e) {
        print('⚠️ Could not broadcast channel creation via P2P: $e');
        // Continue - channel is still created locally
      }

      // Also add a notification message to general channel (for backward compatibility)
      try {
        await DistributedService.addMessage(
           workspaceId: _workspaceId!,
           channelId: 'general',
           senderAddress: userAddress!,
           messageText: 'Channel #$channelName created by user',
        );
      } catch (e) {
        print('⚠️ Could not add notification message (server might be off): $e');
        // Continue - channel creation is more important
      }

      // Reload channels from database to ensure consistency
      await _loadChannels();

      print('✅ Channel "$channelName" created successfully and saved to database');
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
        // Use HybridStorageService for offline support (falls back to SQLite)
        final workspaces = await HybridStorageService.instance.getUserWorkspaces(widget.userAddress);
        setState(() {
          _workspaces = workspaces;
          _isLoading = false;
        });
        print('✅ Loaded ${workspaces.length} workspaces (offline-capable)');
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
      // Save new workspace to session
      await SessionService.saveLoginSession(
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
                  await SessionService.clearLoginSession();
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
      final profile = await DistributedService.getUserProfile(widget.userAddress);
      if (profile != null) {
        if (mounted) {
          setState(() {
            _profileData = profile;
            _isLoading = false;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading profile: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _status = 'Error loading profile: $e';
        });
      }
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
      await SessionService.clearLoginSession();
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
