import 'dart:io';
import 'dart:typed_data';
import 'package:blockchain_fyp/workspace_home_page.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:get_it/get_it.dart';
import 'services/distributed_service.dart' show DistributedService, ChainBrokenException;
import 'services/hybrid_storage_service.dart';
import 'services/session_service.dart';
import 'services/p2p_service.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChannelPage extends StatefulWidget {
  final String channelName;
  final String workspaceName;

  const ChannelPage({
    super.key,
    required this.channelName,
    required this.workspaceName,
  });

  @override
  State<ChannelPage> createState() => _ChannelPageState();
}

class _ChannelPageState extends State<ChannelPage> {
  String status = '';
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  String currentUserName = 'User';
  String? userAddress;
  int _memberCount = 0;
  bool _isLoadingMembers = false;
  bool _isLoadingMessages = false;
  bool _hasText = false;
  late VoidCallback _textListener;
  String _currentChannelName = '';
  bool _messagesLoaded = false;

  // Cache for downloaded files/images
  final Map<String, Uint8List?> _fileCache = {};
  final Map<String, Future<Uint8List?>> _downloadFutures = {};

  // Voice recording
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  String? _recordingPath;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  String? _playingAudioId;
  bool _isLocked = false;
  double _recordingAmplitude = 0.0;
  Timer? _amplitudeTimer;
  bool _isUploading = false;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  Duration _audioPosition = Duration.zero;
  Duration _audioDuration = Duration.zero;
  List<double> _waveformData = [];
  Offset? _panStartPosition;

  // Real-time message updates
  Timer? _messagePollingTimer;
  bool _isCheckingMessages = false;
  DateTime? _lastMessageCheckTime;
  
  // Auto-scroll controller for messages list
  final ScrollController _scrollController = ScrollController();
  
  // Workspace ID (resolved from workspace name)
  String? _workspaceId;
  
  /// Get workspace ID (resolved from workspace name)
  /// This ensures consistent workspace ID usage throughout the page
  String get _effectiveWorkspaceId {
    return _workspaceId ?? widget.workspaceName;
  }

  @override
  void initState() {
    super.initState();
    _currentChannelName = widget.channelName;
    _resolveChannelDisplayName();
    _resolveWorkspaceId(); // Resolve workspace ID first
    _loadUserNameAndMessages();
    _loadWorkspaceMembers();
    _textListener = () {
      setState(() {
        _hasText = _messageController.text.trim().isNotEmpty;
      });
    };
    _messageController.addListener(_textListener);
    
    // Set up real-time message updates
    _setupRealTimeUpdates();
    
    // WhatsApp/Instagram style: Scroll to bottom (newest messages) after first frame
    // This ensures channel opens showing latest messages
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _messages.isNotEmpty) {
        _scrollToBottom(smooth: false); // Instant scroll to show newest messages
      }
    });
  }
  
  /// Set up real-time message updates (polling + P2P callbacks)
  void _setupRealTimeUpdates() {
    // Set up P2P callback for real-time messages
    P2PService.instance.onMessageReceived = (message) {
      // Check if message is for current channel
      final messageChannelId = message['channel_id']?.toString() ?? '';
      final messageWorkspaceId = message['workspace_id']?.toString() ?? '';
      
      // Ensure workspace ID is resolved for comparison
      if (_workspaceId == null) {
        _resolveWorkspaceId().then((_) {
          _handleP2PMessage(message);
        });
      } else {
        _handleP2PMessage(message);
      }
    };
    
    // Start periodic polling for new messages (every 2 seconds)
    _messagePollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted && !_isCheckingMessages && !_isLoadingMessages) {
        _checkForNewMessages();
      }
    });
  }
  
  /// Handle P2P message received callback
  void _handleP2PMessage(Map<String, dynamic> message) {
    final messageChannelId = message['channel_id']?.toString() ?? '';
    final messageWorkspaceId = message['workspace_id']?.toString() ?? '';
    
    // Ensure workspace ID is resolved for comparison
    final effectiveWorkspaceId = _workspaceId ?? widget.workspaceName;
    
    // Match by both workspace ID and workspace name (for backward compatibility)
    final workspaceMatches = messageWorkspaceId == effectiveWorkspaceId || 
                             messageWorkspaceId == widget.workspaceName ||
                             effectiveWorkspaceId == messageWorkspaceId;
    
    // Match channel (case-insensitive)
    final channelMatches = messageChannelId.toLowerCase() == widget.channelName.toLowerCase();
    
    if (channelMatches && workspaceMatches) {
      print('📨 Real-time P2P message received for current channel');
      print('   Message workspace: $messageWorkspaceId, Current workspace: $effectiveWorkspaceId');
      print('   Message channel: $messageChannelId, Current channel: ${widget.channelName}');
      print('   Message ID: ${message['message_id']}');
      
      // Force immediate check for new messages (don't wait for polling)
      if (mounted && !_isCheckingMessages && !_isLoadingMessages) {
        _checkForNewMessages();
      } else {
        print('⚠️ Cannot check for new messages: mounted=$mounted, checking=$_isCheckingMessages, loading=$_isLoadingMessages');
      }
    } else {
      print('⚠️ P2P message not for current channel/workspace');
      print('   Message workspace: $messageWorkspaceId, Current: $effectiveWorkspaceId');
      print('   Message channel: $messageChannelId, Current: ${widget.channelName}');
      print('   Workspace match: $workspaceMatches, Channel match: $channelMatches');
    }
    
    print('✅ Real-time message updates enabled (polling every 2s + P2P callbacks)');
  }

  /// Resolve workspace ID from workspace name
  /// This ensures we use the correct workspace ID for all operations
  Future<void> _resolveWorkspaceId() async {
    try {
      if (userAddress == null) {
        userAddress = await SessionService.getUserAddress();
      }
      
      if (userAddress == null) {
        print('⚠️ Cannot resolve workspace ID: user address is null');
        _workspaceId = widget.workspaceName; // Fallback to name
        return;
      }
      
      print('🔍 Resolving workspace ID for workspace name: ${widget.workspaceName}');
      
      // Try to get workspace ID from SQLite first (works offline)
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
      
      // If not in SQLite, try server (if online)
      try {
        final serverWorkspaces = await DistributedService.getUserWorkspaces(userAddress!);
        final serverWorkspace = serverWorkspaces.firstWhere(
          (w) => (w['name']?.toString() ?? w['workspaceName']?.toString()) == widget.workspaceName,
          orElse: () => {},
        );
        
        if (serverWorkspace.isNotEmpty) {
          _workspaceId = serverWorkspace['workspace_id']?.toString() ?? 
                        serverWorkspace['workspaceId']?.toString() ??
                        widget.workspaceName;
          print('✅ Resolved workspace ID from server: $_workspaceId');
          return;
        }
      } catch (e) {
        print('⚠️ Could not resolve workspace ID from server: $e');
      }
      
      // Fallback to workspace name (might be the ID already)
      _workspaceId = widget.workspaceName;
      print('⚠️ Using workspace name as ID (fallback): $_workspaceId');
    } catch (e) {
      print('❌ Error resolving workspace ID: $e');
      _workspaceId = widget.workspaceName; // Fallback
    }
  }

  /// Resolve channel display name from SharedPreferences (takes priority)
  Future<void> _resolveChannelDisplayName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mappingKey = 'channel_name_mapping_${widget.workspaceName}_${widget.channelName}';
      final mappedName = prefs.getString(mappingKey);

      if (mappedName != null && mappedName.isNotEmpty) {
        setState(() {
          _currentChannelName = mappedName;
        });
        return;
      }

      // Fallback to original name (OrbitDB rename logic disabled/stubbed)
      setState(() {
        _currentChannelName = widget.channelName;
      });
    } catch (e) {
      print('Error resolving channel display name: $e');
      setState(() {
        _currentChannelName = widget.channelName;
      });
    }
  }

  @override
  void dispose() {
    // Cancel real-time update timer
    _messagePollingTimer?.cancel();
    _messagePollingTimer = null;
    
    // IMPORTANT: Don't set callback to null - let it be overwritten by next channel page
    // OR set it back to HybridStorageService callback for server sync
    // Setting to null breaks P2P message reception when channel page is closed
    // P2PService.instance.onMessageReceived = null; // REMOVED - causes callback loss
    
    // Dispose scroll controller
    _scrollController.dispose();
    
    _messageController.removeListener(_textListener);
    _messageController.dispose();
    _fileCache.clear();
    _downloadFutures.clear();
    _stopRecording();
    _recordingTimer?.cancel();
    _amplitudeTimer?.cancel();
    _playerStateSubscription?.cancel();
    _positionSubscription?.cancel();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    // Reset flag so messages reload when page is reopened
    _messagesLoaded = false;
    super.dispose();
  }
  
  /// Auto-scroll to bottom when new message arrives
  /// WhatsApp/Instagram style: Scroll to maxScrollExtent (bottom) to show newest messages
  void _scrollToBottom({bool smooth = true}) {
    if (_scrollController.hasClients && _messages.isNotEmpty) {
      // When reverse: false, maxScrollExtent = bottom (newest messages)
      // Position 0 = top (oldest messages)
      if (smooth) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent, // Scroll to bottom (newest messages)
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent); // Instant scroll to bottom (newest messages)
      }
    }
  }

  Future<Uint8List?> _getCachedFile(String cid) async {
    // Check cache first
    if (_fileCache.containsKey(cid)) {
      return _fileCache[cid];
    }
    
    // Check if download is already in progress
    if (_downloadFutures.containsKey(cid)) {
      return _downloadFutures[cid];
    }

    // Try to download from backend
    // Check if cid looks like a fileId (starts with 'file_') or is a local ID
    if (cid.startsWith('file_')) {
      // It's a fileId from backend, download it
      print('📥 Downloading file from backend: $cid');
      final future = DistributedService.downloadFile(cid);
      _downloadFutures[cid] = future;
      
      try {
        final bytes = await future;
        if (bytes != null && mounted) {
          _fileCache[cid] = bytes;
          print('✅ File downloaded and cached: $cid (${bytes.length} bytes)');
        }
        return bytes;
      } catch (e) {
        print('❌ Error downloading file: $e');
        return null;
      }
    } else if (cid.startsWith('local_')) {
      // It's a local file ID, check cache
      print('ℹ️ Local file ID: $cid (not available for download)');
      return null;
    } else {
      // Unknown format, try as fileId anyway
      print('📥 Attempting to download file: $cid');
      final future = DistributedService.downloadFile(cid);
      _downloadFutures[cid] = future;
      
      try {
        final bytes = await future;
        if (bytes != null && mounted) {
          _fileCache[cid] = bytes;
          print('✅ File downloaded and cached: $cid');
        }
        return bytes;
      } catch (e) {
        print('❌ Error downloading file: $e');
        return null;
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveChannelDisplayName();

    // Reload messages when page is reopened (only if not already loading)
    // Reset _messagesLoaded flag to allow fresh load when returning to page
    // The _isLoadingMessages flag prevents multiple simultaneous loads
    if (!_isLoadingMessages && mounted) {
      _messagesLoaded = false; // Reset to allow fresh load
      _loadMessages();
    }
  }

  Future<void> _checkForNewMessages() async {
    // Prevent multiple simultaneous checks
    if (_isCheckingMessages || !mounted) {
      return;
    }
    
    _isCheckingMessages = true;
    
    try {
      // Ensure workspace ID is resolved
      if (_workspaceId == null) {
        await _resolveWorkspaceId();
      }
      
      // CRITICAL FIX: For polling, only fetch NEW messages (incremental loading)
      // Calculate last message timestamp to only fetch messages after that
      int? sinceTimestamp;
      if (_messages.isNotEmpty) {
        // Get timestamp of last message
        final lastMessage = _messages.last;
        final lastTimestamp = lastMessage['timestamp'];
        
        if (lastTimestamp is DateTime) {
          sinceTimestamp = lastTimestamp.millisecondsSinceEpoch;
        } else if (lastTimestamp is int) {
          sinceTimestamp = lastTimestamp;
        } else if (lastTimestamp is String) {
          final parsed = DateTime.tryParse(lastTimestamp);
          if (parsed != null) {
            sinceTimestamp = parsed.millisecondsSinceEpoch;
          }
        }
        
        if (sinceTimestamp != null) {
          print('🔄 Polling: Only fetching messages after ${DateTime.fromMillisecondsSinceEpoch(sinceTimestamp)}');
        }
      }
      
      // PHASE 4: Real-time message updates ONLY
      // Use HybridStorageService (works offline)
      // Pass sinceTimestamp to only fetch new messages (prevents loading ALL messages every time)
      // CRITICAL: Only fetch real-time messages (not SYNCED - those are already displayed)
      final loaded = await HybridStorageService.instance.getChannelMessages(
        workspaceId: _effectiveWorkspaceId,
        channelId: widget.channelName,
        sinceTimestamp: sinceTimestamp, // Only fetch new messages during polling
      );
      
      // PHASE 4 RULE: Filter out SYNCED messages - they should NOT appear in real-time updates
      // SYNCED messages are already in UI from initial load, don't re-add them
      // PHASE 4: Messages appear ONLY when user sends or receives in real-time
      // Server sync must NEVER auto-append messages (SYNCED filtered out)
      final realTimeMessages = loaded.where((msg) {
        final state = msg['message_state']?.toString();
        // Only show real-time messages: ONLINE_CONFIRMED, OFFLINE_LOCAL, PENDING_SYNC
        // Exclude SYNCED (those are from sync, not real-time - PHASE 4 requirement)
        return state != 'SYNCED';
      }).toList();
      
      if (realTimeMessages.length < loaded.length) {
        print('🚫 PHASE 4: Filtered out ${loaded.length - realTimeMessages.length} SYNCED messages (not real-time)');
      }

      // PHASE 4: Process only real-time messages (SYNCED filtered out above)
      for (var msg in realTimeMessages) {
        if (msg['timestamp'] is String) {
          msg['timestamp'] = DateTime.tryParse(msg['timestamp']) ?? DateTime.now();
        } else if (msg['timestamp'] is int) {
          msg['timestamp'] = DateTime.fromMillisecondsSinceEpoch(msg['timestamp']);
        }
      }

      // Use proper deduplication instead of length comparison
      final existingMessageIds = _messages.map((m) => _getMessageId(m)).whereType<String>().toSet();
      
      // Also check for temporary message IDs that need to be replaced with real IDs
      final tempMessageIds = _messages
          .where((m) {
            final id = _getMessageId(m);
            return id != null && id.toString().startsWith('temp_');
          })
          .map((m) => _getMessageId(m))
          .whereType<String>()
          .toList();
      
      // CRITICAL FIX: Get current user address to filter out user's own messages
      if (userAddress == null) await _loadUserAddress();
      final currentUserAddress = userAddress?.toLowerCase() ?? '';
      
      // PHASE 4: Find new REAL-TIME messages (not already in _messages)
      // Only messages that are real-time (user sends or receives) should appear
      final newMessages = <Map<String, dynamic>>[];
      final now = DateTime.now().millisecondsSinceEpoch;
      final recentThreshold = 30000; // 30 seconds - exclude user's own recent messages
      
      // PHASE 4: Process only real-time messages (SYNCED already filtered out)
      for (final msg in realTimeMessages) {
        final msgId = _getMessageId(msg);
        if (msgId == null) continue;
        
        // CRITICAL FIX: Skip if message ID already exists in UI
        if (existingMessageIds.contains(msgId)) {
          continue;
        }
        
        // Get message details for deduplication
        final msgContent = (msg['content']?.toString() ?? 
                         msg['message_text']?.toString() ?? 
                         msg['messageText']?.toString() ?? '').trim();
        final msgSender = (msg['sender_address']?.toString() ?? 
                        msg['senderAddress']?.toString() ?? 
                        msg['userAddress']?.toString() ?? '').toLowerCase();
        final msgTimestamp = msg['timestamp'] is DateTime 
            ? (msg['timestamp'] as DateTime).millisecondsSinceEpoch 
            : (msg['timestamp'] is int ? msg['timestamp'] as int : 0);
        
        // CRITICAL FIX: Exclude user's own messages that were sent very recently (within last 30 seconds)
        // This prevents user's own messages from appearing again via polling
        if (currentUserAddress.isNotEmpty && 
            msgSender == currentUserAddress && 
            msgTimestamp > 0 && 
            (now - msgTimestamp) < recentThreshold) {
          print('🚫 Skipping user\'s own recent message (sent ${(now - msgTimestamp) / 1000}s ago): $msgId');
          continue;
        }
        
        // Check if this message matches a temporary message (same content, sender, timestamp)
        // This handles the case where we added a message locally with temp ID, and now we got the real one
        bool replacedTemp = false;
        if (tempMessageIds.isNotEmpty && msgContent.isNotEmpty && msgSender.isNotEmpty) {
          for (int i = 0; i < _messages.length; i++) {
            final existingMsg = _messages[i];
            final existingId = _getMessageId(existingMsg);
            if (existingId != null && existingId.toString().startsWith('temp_')) {
              final existingContent = (existingMsg['content']?.toString() ?? 
                                     existingMsg['message_text']?.toString() ?? 
                                     existingMsg['messageText']?.toString() ?? '').trim();
              final existingSender = (existingMsg['userAddress']?.toString() ?? 
                                     existingMsg['sender_address']?.toString() ?? 
                                     existingMsg['senderAddress']?.toString() ?? '').toLowerCase();
              final existingTimestamp = existingMsg['timestamp'] is DateTime 
                  ? (existingMsg['timestamp'] as DateTime).millisecondsSinceEpoch 
                  : (existingMsg['timestamp'] is int ? existingMsg['timestamp'] as int : 0);
              
              // Match if content, sender, and timestamp are close (within 5 seconds)
              if (existingContent == msgContent && 
                  existingSender == msgSender &&
                  (existingTimestamp - msgTimestamp).abs() < 5000) {
                // Replace temporary message with real one
                _messages[i] = msg;
                replacedTemp = true;
                print('🔄 Replaced temporary message (${existingId.substring(0, 20)}...) with real message_id: $msgId');
                break;
              }
            }
          }
        }
        
        // CRITICAL FIX: Also check if message already exists by content + sender + timestamp (not just message_id)
        // This catches duplicates even if message IDs don't match
        bool isDuplicate = false;
        if (!replacedTemp && msgContent.isNotEmpty && msgSender.isNotEmpty) {
          for (final existingMsg in _messages) {
            final existingContent = (existingMsg['content']?.toString() ?? 
                                   existingMsg['message_text']?.toString() ?? 
                                   existingMsg['messageText']?.toString() ?? '').trim();
            final existingSender = (existingMsg['userAddress']?.toString() ?? 
                                   existingMsg['sender_address']?.toString() ?? 
                                   existingMsg['senderAddress']?.toString() ?? '').toLowerCase();
            final existingTimestamp = existingMsg['timestamp'] is DateTime 
                ? (existingMsg['timestamp'] as DateTime).millisecondsSinceEpoch 
                : (existingMsg['timestamp'] is int ? existingMsg['timestamp'] as int : 0);
            
            // Match if content, sender, and timestamp are close (within 5 seconds)
            if (existingContent == msgContent && 
                existingSender == msgSender &&
                (existingTimestamp - msgTimestamp).abs() < 5000) {
              isDuplicate = true;
              print('🚫 Skipping duplicate message (content + sender + timestamp match): $msgId');
              break;
            }
          }
        }
        
        if (!replacedTemp && !isDuplicate) {
          newMessages.add(msg);
          existingMessageIds.add(msgId);
        }
      }
      
      // CRITICAL: Always perform final deduplication, even if no new messages
      // This ensures any duplicates that somehow got into _messages are removed
      if (mounted) {
        print('📥 PHASE 4: Real-time update: Found ${newMessages.length} new REAL-TIME messages (${realTimeMessages.length} real-time, ${_messages.length} existing)');
        print('   ✅ SYNCED messages filtered out (not real-time)');
        
        setState(() {
          // Add new messages if any
          if (newMessages.isNotEmpty) {
            _messages.addAll(newMessages);
          }
          
          // Sort by timestamp after adding
          _messages.sort((a, b) {
            final aTime = a['timestamp'] is DateTime 
                ? (a['timestamp'] as DateTime).millisecondsSinceEpoch 
                : (a['timestamp'] is int ? a['timestamp'] as int : 0);
            final bTime = b['timestamp'] is DateTime 
                ? (b['timestamp'] as DateTime).millisecondsSinceEpoch 
                : (b['timestamp'] is int ? b['timestamp'] as int : 0);
            return aTime.compareTo(bTime);
          });
          
          // Auto-scroll to bottom when new messages arrive
          if (newMessages.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollToBottom(smooth: true);
            });
          }
          
          // CRITICAL: ALWAYS perform final deduplication pass (even if no new messages)
          // This removes any duplicates that might have been added previously
          final finalMessageIds = <String>{};
          final deduplicatedMessages = <Map<String, dynamic>>[];
          for (final msg in _messages) {
            final msgId = _getMessageId(msg);
            if (msgId != null && !finalMessageIds.contains(msgId)) {
              deduplicatedMessages.add(msg);
              finalMessageIds.add(msgId);
            } else if (msgId != null) {
              print('⚠️ Duplicate detected and removed: $msgId');
            }
          }
          
          // Always update _messages with deduplicated list (even if no changes)
          // This ensures clean state and prevents accumulation of duplicates
          if (deduplicatedMessages.length != _messages.length) {
            print('⚠️ Final deduplication: removed ${_messages.length - deduplicatedMessages.length} duplicates');
            _messages.clear();
            _messages.addAll(deduplicatedMessages);
            _messages.sort((a, b) {
              final aTime = a['timestamp'] is DateTime 
                  ? (a['timestamp'] as DateTime).millisecondsSinceEpoch 
                  : (a['timestamp'] is int ? a['timestamp'] as int : 0);
              final bTime = b['timestamp'] is DateTime 
                  ? (b['timestamp'] as DateTime).millisecondsSinceEpoch 
                  : (b['timestamp'] is int ? b['timestamp'] as int : 0);
              return aTime.compareTo(bTime);
            });
          } else if (newMessages.isNotEmpty) {
            print('✅ Real-time update: Added ${newMessages.length} new messages to UI (no duplicates found)');
          }
        });
        
        if (newMessages.isNotEmpty) {
          _preloadMediaFiles(newMessages);
        }
      }
    } on ChainBrokenException catch (e) {
      // Chain broken - don't update messages, but don't crash
      print('⚠️ Chain integrity compromised during real-time update - skipping message update');
      print('   Broken at: ${e.brokenAt}');
      // Don't show error to user for real-time updates - just skip
    } catch (e) {
      print('❌ Error checking for new messages: $e');
    } finally {
      _isCheckingMessages = false;
    }
  }

  Future<void> _loadUserAddress() async {
    try {
      final session = await SessionService.getLoginSession();
      userAddress = session['userAddress'];
    } catch (e) {
      print('Error loading user address: $e');
    }
  }

  Future<void> _loadUserNameAndMessages() async {
    try {
      await _loadUserAddress();
      currentUserName = (await _getUserNameFromMongoDB()) ?? 'User';
    } catch (_) {
      currentUserName = 'User';
    }
    await _loadMessages();
  }

  Future<String?> _getUserNameFromMongoDB() async {
    if (userAddress == null) return null;
      final profile = await HybridStorageService.instance.getUserProfile(userAddress!);
    return profile?['username'];
  }

  Future<void> _loadWorkspaceMembers() async {
    setState(() => _isLoadingMembers = true);
    try {
      if (userAddress == null) await _loadUserAddress();
      
      // Ensure workspace ID is resolved
      if (_workspaceId == null) {
        await _resolveWorkspaceId();
      }
      
      // Use resolved workspace ID (critical for P2P to work)
      print('👥 Loading workspace members for workspace ID: $_effectiveWorkspaceId (name: ${widget.workspaceName})');
      
      // Use HybridStorageService (works offline)
      final members = await HybridStorageService.instance.getWorkspaceMembers(_effectiveWorkspaceId);
      print('✅ Loaded ${members.length} workspace members');
      
      setState(() {
        _memberCount = members.length;
        _isLoadingMembers = false;
      });
    } catch (e) {
      print('❌ Error loading workspace members: $e');
      setState(() {
        _isLoadingMembers = false;
        _memberCount = 0;
      });
    }
  }

  Future<String?> _getProfileNameForAddress(String address) async {
    try {
      final profile = await DistributedService.getUserProfile(address);
      return profile?['username'];
    } catch (e) {
      debugPrint('Error getting profile name: $e');
      return null;
    }
  }

  /// Get consistent message ID from message map
  String? _getMessageId(Map<String, dynamic> msg) {
    // Try message_id first (most reliable)
    final messageId = msg['message_id']?.toString();
    if (messageId != null && messageId.isNotEmpty) {
      return messageId;
    }
    
    // Try id as fallback
    final id = msg['id']?.toString();
    if (id != null && id.isNotEmpty) {
      return id;
    }
    
    // Generate composite ID from timestamp, sender, and content (last resort)
    final timestamp = msg['timestamp'];
    final sender = msg['userAddress']?.toString() ?? 
                   msg['sender_address']?.toString() ?? 
                   msg['senderAddress']?.toString() ?? '';
    final content = (msg['content']?.toString() ?? 
                    msg['message_text']?.toString() ?? 
                    msg['messageText']?.toString() ?? '').trim();
    
    if (timestamp != null && sender.isNotEmpty && content.isNotEmpty) {
      final timestampStr = timestamp is DateTime 
          ? timestamp.millisecondsSinceEpoch.toString()
          : (timestamp is int ? timestamp.toString() : timestamp.toString());
      return '${timestampStr}_${sender}_${content.substring(0, content.length > 50 ? 50 : content.length)}';
    }
    
    return null;
  }

  Future<void> _loadMessages() async {
    // Prevent multiple simultaneous loads
    if (_isLoadingMessages) {
      print('⚠️ Messages already loading, skipping...');
      return;
    }

    // Check if widget is still mounted before setting state
    if (!mounted) {
      print('⚠️ Widget not mounted, skipping message load');
      return;
    }

    setState(() {
      _isLoadingMessages = true;
    });

    try {
      print('📥 Loading messages for channel: ${widget.channelName} in workspace: ${widget.workspaceName}');
      
      // Ensure workspace ID is resolved
      if (_workspaceId == null) {
        await _resolveWorkspaceId();
      }
      
      // Use HybridStorageService (works offline)
      final loaded = await HybridStorageService.instance.getChannelMessages(
        workspaceId: _effectiveWorkspaceId,
        channelId: widget.channelName,
      );

      print('✅ Loaded ${loaded.length} messages from database');
      
      // Debug: Log first message structure if available
      if (loaded.isNotEmpty) {
        print('📋 First message structure: ${loaded.first.keys.toList()}');
        print('📋 First message content fields:');
        print('   - content: ${loaded.first['content']}');
        print('   - message_text: ${loaded.first['message_text']}');
        print('   - messageText: ${loaded.first['messageText']}');
        print('   - sender_address: ${loaded.first['sender_address']}');
        print('   - timestamp type: ${loaded.first['timestamp'].runtimeType}');
        print('   - timestamp value: ${loaded.first['timestamp']}');
      } else {
        print('⚠️ No messages loaded from database!');
      }

      // Transform database format to UI format
      final transformedMessages = <Map<String, dynamic>>[];
      
      for (var msg in loaded) {
        // Convert timestamp to DateTime (should already be DateTime from DistributedService, but handle all cases)
        DateTime timestamp;
        if (msg['timestamp'] is DateTime) {
          timestamp = msg['timestamp'] as DateTime;
        } else if (msg['timestamp'] is String) {
          timestamp = DateTime.tryParse(msg['timestamp']) ?? DateTime.now();
        } else if (msg['timestamp'] is int) {
          timestamp = DateTime.fromMillisecondsSinceEpoch(msg['timestamp'] as int);
        } else {
          timestamp = DateTime.now();
        }

        // Get sender address (try multiple field names)
        final senderAddress = msg['sender_address']?.toString() ?? 
                            msg['senderAddress']?.toString() ??
                            msg['userAddress']?.toString() ?? 
                            msg['sender']?.toString() ?? 
                            '';

        // Get message content (try multiple field names)
        final messageContent = (msg['content']?.toString() ?? '').trim() +
                              (msg['message_text']?.toString() ?? '').trim() +
                              (msg['messageText']?.toString() ?? '').trim();
        
        // Check if message has content or file
        final hasContent = messageContent.isNotEmpty;
      final hasFile = (msg['fileId']?.toString() ?? '').isNotEmpty ||
                     (msg['file_id']?.toString() ?? '').isNotEmpty ||
                     (msg['cid']?.toString() ?? '').isNotEmpty ||
                     (msg['fileCid']?.toString() ?? '').isNotEmpty ||
                     (msg['fileName']?.toString() ?? '').isNotEmpty;
      
        // Only skip if message is truly empty (no content AND no file)
      if (!hasContent && !hasFile) {
          print('⚠️ Skipping empty message (no content, no file): message_id=${msg['message_id']}');
        continue; // Skip this message
      }

      // Detect message type from content or fileName
      String? detectedType = msg['type']?.toString();
      final fileName = msg['fileName']?.toString() ?? '';
      final content = (msg['content']?.toString() ?? 
                      msg['message_text']?.toString() ?? 
                      msg['messageText']?.toString() ?? 
                      '').trim().toLowerCase();
      
      // If type is not set, try to detect from content or fileName
      if (detectedType == null || detectedType.isEmpty || detectedType == 'text') {
        if (content.contains('voice message') || fileName.endsWith('.m4a') || fileName.endsWith('.mp3') || fileName.endsWith('.wav') || fileName.endsWith('.aac')) {
          detectedType = 'audio';
        } else if (content.contains('image:') || fileName.endsWith('.jpg') || fileName.endsWith('.jpeg') || fileName.endsWith('.png') || fileName.endsWith('.gif') || fileName.endsWith('.webp')) {
          detectedType = 'image';
        } else if (content.contains('video:') || fileName.endsWith('.mp4') || fileName.endsWith('.mov') || fileName.endsWith('.avi') || fileName.endsWith('.mkv') || fileName.endsWith('.webm') || fileName.endsWith('.3gp') || fileName.endsWith('.m4v')) {
          detectedType = 'video';
        } else if (content.contains('file:') || hasFile) {
          detectedType = 'file';
        } else {
          detectedType = 'text';
        }
      }

      // Extract fileId/cid (priority: fileId > file_id > cid > fileCid)
      final fileId = msg['fileId']?.toString() ?? 
                     msg['file_id']?.toString() ?? 
                     msg['cid']?.toString() ?? 
                     msg['fileCid']?.toString() ?? 
                     '';

      // Transform message to UI format
        final transformedMsg = <String, dynamic>{
          // Keep all original fields first (for compatibility)
          ...msg,
          
          // Then override with transformed values (these take priority)
          // Content field (priority: content > message_text > messageText)
          'content': (msg['content']?.toString() ?? 
                     msg['message_text']?.toString() ?? 
                     msg['messageText']?.toString() ?? 
                     '').trim(),
          
          // Type field - use detected type
          'type': detectedType,
          
          // Timestamp - MUST be DateTime, not int (set after spread to override)
          'timestamp': timestamp,
          
          // Sender information
          'userAddress': senderAddress,
          'sender': msg['sender']?.toString() ?? 
                   msg['senderName']?.toString() ?? 
                   '',
          'senderName': msg['senderName']?.toString() ?? 
                       msg['sender']?.toString() ?? 
                       '',
          
          // File information (if present) - prioritize fileId
          'fileName': fileName.isNotEmpty ? fileName : msg['fileName']?.toString(),
          'fileSize': msg['fileSize'],
          'fileId': fileId.isNotEmpty ? fileId : null,
          'cid': fileId.isNotEmpty ? fileId : (msg['cid']?.toString() ?? msg['fileCid']?.toString() ?? ''),
          'fileCid': fileId.isNotEmpty ? fileId : (msg['fileCid']?.toString() ?? msg['cid']?.toString() ?? ''),
          
          // Workspace and channel
          'workspace': msg['workspace']?.toString() ?? widget.workspaceName,
          'channel': msg['channel']?.toString() ?? widget.channelName,
        };
        
        // Debug print for media messages
        if (detectedType != 'text') {
          print('📎 Media message detected: type=$detectedType, fileId=$fileId, fileName=$fileName');
        }

        transformedMessages.add(transformedMsg);
      }

      // Fetch sender names for all messages (in parallel for better performance)
      print('🔄 Fetching sender names for ${transformedMessages.length} messages...');
      final senderAddresses = transformedMessages
          .map((m) => m['userAddress']?.toString())
          .whereType<String>() // Filter out null values and cast to String
          .where((addr) => addr.isNotEmpty) // Filter out empty strings
          .toSet()
          .toList();

      final senderNameMap = <String, String>{};
      await Future.wait(
        senderAddresses.map((address) async {
          try {
            final profile = await DistributedService.getUserProfile(address);
            final username = profile?['username']?.toString();
            if (username != null && username.isNotEmpty) {
              senderNameMap[address] = username; // address is String, username is String
            }
          } catch (e) {
            print('⚠️ Error fetching profile for $address: $e');
          }
        }),
      );

      // Update sender names in messages
      for (var msg in transformedMessages) {
        final address = msg['userAddress']?.toString();
        if (address != null && senderNameMap.containsKey(address)) {
          msg['senderName'] = senderNameMap[address];
          msg['sender'] = senderNameMap[address];
        }
        
        // If still no sender name, use a fallback
        if ((msg['senderName'] == null || msg['senderName'].toString().isEmpty) && 
            address != null && address.isNotEmpty) {
          msg['senderName'] = address.length > 10 
              ? '${address.substring(0, 6)}...${address.substring(address.length - 4)}'
              : address;
          msg['sender'] = msg['senderName'];
        }
      }

      print('✅ Transformed ${transformedMessages.length} messages with sender names');

      // Only update state if widget is still mounted
      if (mounted) {
        print('📊 Message transformation summary:');
        print('   - Loaded from DB: ${loaded.length} messages');
        print('   - Transformed: ${transformedMessages.length} messages');
        print('   - Skipped: ${loaded.length - transformedMessages.length} messages');
        
        setState(() {
          // Always use proper deduplication using consistent message ID
          final existingMessageIds = _messages.map((m) => _getMessageId(m)).whereType<String>().toSet();
          
          // Filter out duplicates from transformed messages
          final uniqueMessages = <Map<String, dynamic>>[];
          for (final msg in transformedMessages) {
            final msgId = _getMessageId(msg);
            
            if (msgId != null && !existingMessageIds.contains(msgId)) {
              uniqueMessages.add(msg);
              existingMessageIds.add(msgId);
            } else if (msgId != null) {
              print('⚠️ Skipping duplicate message: $msgId');
            } else {
              print('⚠️ Skipping message with no valid ID');
            }
          }
          
          print('📊 Deduplication: ${transformedMessages.length} total loaded, ${_messages.length} existing, ${uniqueMessages.length} new unique');
          
          // Always clear and reload on fresh load to ensure clean state
          // This prevents duplicates when reopening channel
          if (!_messagesLoaded) {
            print('🔄 Fresh load: clearing existing messages and loading ${uniqueMessages.length} unique messages');
            _messages.clear();
            _messages.addAll(uniqueMessages);
          } else {
            // Incremental: only add new unique messages
            print('➕ Incremental load: adding ${uniqueMessages.length} new messages');
            _messages.addAll(uniqueMessages);
          }
          
          // Always sort by timestamp to maintain order
          _messages.sort((a, b) {
            final aTime = a['timestamp'] is DateTime 
                ? (a['timestamp'] as DateTime).millisecondsSinceEpoch 
                : (a['timestamp'] is int ? a['timestamp'] as int : 0);
            final bTime = b['timestamp'] is DateTime 
                ? (b['timestamp'] as DateTime).millisecondsSinceEpoch 
                : (b['timestamp'] is int ? b['timestamp'] as int : 0);
            return aTime.compareTo(bTime);
          });
          
          // WhatsApp/Instagram style: Auto-scroll to bottom (newest messages) after loading
          // This ensures channel opens showing latest messages, not oldest
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _messages.isNotEmpty) {
              _scrollToBottom(smooth: false); // Instant scroll to show newest messages on channel open
            }
          });
          
          // Final deduplication pass (safety check) - use consistent ID function
          final finalMessageIds = <String>{}; 
          final deduplicatedMessages = <Map<String, dynamic>>[];
          for (final msg in _messages) {
            final msgId = _getMessageId(msg);
            
            if (msgId != null && !finalMessageIds.contains(msgId)) {
              deduplicatedMessages.add(msg);
              finalMessageIds.add(msgId);
            } else if (msgId != null) {
              print('⚠️ Final deduplication: removed duplicate $msgId');
            }
          }
          
          if (deduplicatedMessages.length != _messages.length) {
            print('⚠️ Final deduplication: removed ${_messages.length - deduplicatedMessages.length} duplicates');
            _messages.clear();
            _messages.addAll(deduplicatedMessages);
            // Re-sort after deduplication
            _messages.sort((a, b) {
              final aTime = a['timestamp'] is DateTime 
                  ? (a['timestamp'] as DateTime).millisecondsSinceEpoch 
                  : (a['timestamp'] is int ? a['timestamp'] as int : 0);
              final bTime = b['timestamp'] is DateTime 
                  ? (b['timestamp'] as DateTime).millisecondsSinceEpoch 
                  : (b['timestamp'] is int ? b['timestamp'] as int : 0);
              return aTime.compareTo(bTime);
            });
          }
        });
        print('✅ Messages loaded into UI: ${_messages.length} unique messages');
      } else {
        print('⚠️ Widget disposed, skipping setState');
      }
      
      // Preload media files (async, doesn't need mounted check)
      _preloadMediaFiles(transformedMessages);
      
      // Mark messages as loaded
      _messagesLoaded = true;
    } on ChainBrokenException catch (e) {
      // Chain integrity compromised - hide all messages and show error
      print('❌ Chain integrity compromised: ${e.message}');
      print('   Broken at: ${e.brokenAt}');
      print('   Details: ${e.details}');
      
      if (mounted) {
        setState(() {
          _messages.clear(); // Hide all messages
          _isLoadingMessages = false;
          status = '⚠️ Data integrity compromised. Messages cannot be displayed for security reasons.';
        });
        
        // Show prominent error dialog to user
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '⚠️ Chain Integrity Compromised',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Data integrity check failed. Messages are hidden for security. A message may have been modified.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
                if (e.brokenAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Broken at: ${e.brokenAt}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
            backgroundColor: Colors.red[700],
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      print('❌ Error loading messages: $e');
      if (mounted) {
        setState(() => status = 'Failed to load messages: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMessages = false;
        });
      }
    }
  }

  Future<void> _preloadMediaFiles(List<Map<String, dynamic>> messages) async {
    final mediaCids = <String>[];
    for (var message in messages) {
      final cid = message['cid'] ?? message['fileCid'];
      if (cid != null && cid.toString().isNotEmpty && !_fileCache.containsKey(cid.toString())) {
        mediaCids.add(cid.toString());
      }
    }

    if (mediaCids.isEmpty) return;

    const maxConcurrent = 5;
    for (var i = 0; i < mediaCids.length; i += maxConcurrent) {
      final batch = mediaCids.skip(i).take(maxConcurrent).toList();
      await Future.wait(batch.map((cid) => _getCachedFile(cid)));
      if (i + maxConcurrent < mediaCids.length) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  // Upload stubs (simulated failure since not implemented)
  Future<Map<String, dynamic>?> _simulateUpload(Uint8List bytes, String fileName) async {
    // Stub: returns failure
    return {'success': false, 'error': 'Uploads not implemented'};
    // For testing success, uncomment:
    // final timestamp = DateTime.now().millisecondsSinceEpoch;
    // return {'success': true, 'fileCid': 'stub_cid_$timestamp'};
  }

  Future<void> _takePicture() async {
    try {
      // Ensure user address is loaded
      if (userAddress == null) {
        await _loadUserAddress();
      }

      setState(() {
        status = 'Opening camera...';
      });

      // Initialize ImagePicker
      final ImagePicker picker = ImagePicker();

      // Capture image from camera
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85, // Compress image to 85% quality
        maxWidth: 1920, // Limit width to reduce file size
        maxHeight: 1920, // Limit height to reduce file size
      );

      if (image != null) {
        // Read image file as bytes
        final Uint8List imageBytes = await image.readAsBytes();
        final fileSize = imageBytes.length;

        setState(() {
          status =
              'Uploading image... (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)';
        });

        // Generate filename with timestamp
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileName = 'IMG_$timestamp.jpg';

        print('📷 Starting image upload: $fileName (${fileSize} bytes)');
        print('📷 User info - Name: $currentUserName, Address: $userAddress');

        // Upload image to backend
        print('📤 Uploading image to backend: $fileName');
        final fileId = await DistributedService.uploadFile(
          fileBytes: imageBytes,
          fileName: fileName,
          workspaceId: _effectiveWorkspaceId,
          uploaderAddress: userAddress!,
          mimeType: 'image/jpeg',
        );

        // Determine if it's an image based on file extension
        final isImageFile = fileName.toLowerCase().endsWith('.jpg') ||
            fileName.toLowerCase().endsWith('.jpeg') ||
            fileName.toLowerCase().endsWith('.png') ||
            fileName.toLowerCase().endsWith('.gif');

        // Create message (even if upload failed, save for offline support)
        final msg = {
          'type': isImageFile ? 'image' : 'file',
          'content': isImageFile ? 'Image: $fileName' : 'File: $fileName',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'fileName': fileName,
          'fileSize': fileSize,
          'fileId': fileId, // Store fileId from backend
          'cid': fileId, // For backward compatibility
          'fileCid': fileId, // For backward compatibility
          'senderName': currentUserName,
          'sender': currentUserName,
          'userAddress': userAddress ?? '',
          'workspace': widget.workspaceName,
          'channel': widget.channelName,
        };

        // Cache image bytes locally for immediate display
        if (fileId != null) {
          if (!_fileCache.containsKey(fileId)) {
            _fileCache[fileId] = imageBytes;
            print('✅ [Cache] Image cached locally: $fileId (${imageBytes.length} bytes)');
          }
        } else {
          // If upload failed, still cache locally
          final localCid = 'local_img_$timestamp';
          _fileCache[localCid] = imageBytes;
          msg['cid'] = localCid;
          msg['fileCid'] = localCid;
          print('⚠️ Upload failed, cached locally with ID: $localCid');
        }

        print('💬 Saving image message with user info:');
        print('  - senderName: ${msg['senderName']}');
        print('  - userAddress: ${msg['userAddress']}');
        print('  - fileName: ${msg['fileName']}');
        print('  - fileId: ${msg['fileId']}');
        print('  - type: ${msg['type']}');

        // Generate temporary message ID for local display (will be replaced by server message_id)
        final tempMessageId = 'temp_img_${DateTime.now().millisecondsSinceEpoch}_${userAddress}';
        final messageTimestamp = DateTime.now();
        
        // Add to local state immediately with temporary ID
        if (mounted) {
          setState(() {
            _messages.add({
              ...msg,
              'timestamp': messageTimestamp,
              'message_id': tempMessageId, // Temporary ID for deduplication
            });
            status = fileId != null 
                ? 'Image sent successfully!' 
                : 'Image saved locally (upload failed)';
            // Auto-scroll to bottom when image message is added
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollToBottom(smooth: true);
            });
          });
        }

        // Save to database (works offline + P2P)
        final result = await HybridStorageService.instance.addMessage(
          workspaceId: _effectiveWorkspaceId,
          channelId: widget.channelName,
          senderAddress: userAddress!,
          messageText: msg['content'].toString(),
          fileId: fileId, // Link message with file
        );
        
        final success = result != null;
        if (!success) {
          if (mounted) {
            setState(() {
              _messages.removeWhere((m) => _getMessageId(m) == tempMessageId);
              status = 'Failed to save image message';
            });
          }
          print('❌ Failed to save image message to database');
        } else {
          // Update the local message with the real message_id from server
          if (mounted) {
            setState(() {
              final index = _messages.indexWhere((m) => _getMessageId(m) == tempMessageId);
              if (index >= 0) {
                _messages[index]['message_id'] = result;
                _messages[index]['id'] = result;
              }
            });
          }
          print('✅ Image message saved successfully${fileId != null ? " with fileId: $fileId" : " (local only)"}, message_id: $result');
          // Clear status after a short delay
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              setState(() {
                status = '';
              });
            }
          });
        }
      } else {
        setState(() {
          status = '';
        });
        print('📷 Camera capture cancelled by user');
      }
    } catch (e) {
      print('❌ Error taking picture: $e');
      setState(() {
        status = 'Error taking picture: $e';
      });
    }
  }

  /// Picks an image or video from gallery and uploads it
  Future<void> _pickImageFromGallery() async {
    try {
      // Ensure user address is loaded
      if (userAddress == null) {
        await _loadUserAddress();
      }

      setState(() {
        status = 'Opening gallery...';
      });

      // Initialize ImagePicker
      final ImagePicker picker = ImagePicker();

      // Pick media (image or video) from gallery
      final XFile? media = await picker.pickMedia(
        imageQuality: 85, // Compress image to 85% quality
        maxWidth: 1920, // Limit width to reduce file size
        maxHeight: 1920, // Limit height to reduce file size
      );

      if (media != null) {
        // Read media file as bytes
        final Uint8List mediaBytes = await media.readAsBytes();
        final fileSize = mediaBytes.length;

        // Determine if it's a video based on file extension or mime type
        final fileName = media.name;
        final isVideo = fileName.toLowerCase().endsWith('.mp4') ||
            fileName.toLowerCase().endsWith('.mov') ||
            fileName.toLowerCase().endsWith('.avi') ||
            fileName.toLowerCase().endsWith('.mkv') ||
            fileName.toLowerCase().endsWith('.webm') ||
            fileName.toLowerCase().endsWith('.3gp') ||
            fileName.toLowerCase().endsWith('.m4v');

        setState(() {
          status = isVideo
              ? 'Uploading video... (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)'
              : 'Uploading image... (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)';
        });

        // Get original filename or generate one with timestamp
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final finalFileName = fileName.isNotEmpty && fileName.contains('.')
            ? fileName
            : (isVideo ? 'VID_$timestamp.mp4' : 'IMG_$timestamp.jpg');

        print(
            '🖼️ Starting gallery media upload: $finalFileName (${fileSize} bytes)');
        print('🖼️ Media type: ${isVideo ? 'Video' : 'Image'}');
        print('🖼️ User info - Name: $currentUserName, Address: $userAddress');

        // Upload media to backend
        print('📤 Uploading gallery media to backend: $finalFileName');
        final mimeType = isVideo 
            ? 'video/mp4' 
            : (finalFileName.toLowerCase().endsWith('.png') 
                ? 'image/png' 
                : 'image/jpeg');
        
        final fileId = await DistributedService.uploadFile(
          fileBytes: mediaBytes,
          fileName: finalFileName,
          workspaceId: _effectiveWorkspaceId,
          uploaderAddress: userAddress!,
          mimeType: mimeType,
        );

        // Determine if it's an image based on file extension
        final isImageFile = finalFileName.toLowerCase().endsWith('.jpg') ||
            finalFileName.toLowerCase().endsWith('.jpeg') ||
            finalFileName.toLowerCase().endsWith('.png') ||
            finalFileName.toLowerCase().endsWith('.gif') ||
            finalFileName.toLowerCase().endsWith('.webp');

        // Create message (even if upload failed, save for offline support)
        final msg = {
          'type': isVideo ? 'video' : (isImageFile ? 'image' : 'file'),
          'content': isVideo
              ? 'Video: $finalFileName'
              : (isImageFile
                  ? 'Image: $finalFileName'
                  : 'File: $finalFileName'),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'fileName': finalFileName,
          'fileSize': fileSize,
          'fileId': fileId, // Store fileId from backend
          'cid': fileId, // For backward compatibility
          'fileCid': fileId, // For backward compatibility
          'senderName': currentUserName,
          'sender': currentUserName,
          'userAddress': userAddress ?? '',
          'workspace': widget.workspaceName,
          'channel': widget.channelName,
        };

        // Cache media bytes locally for immediate display
        if (fileId != null) {
          if (!_fileCache.containsKey(fileId)) {
            _fileCache[fileId] = mediaBytes;
            print('✅ [Cache] Media cached locally: $fileId (${mediaBytes.length} bytes)');
          }
        } else {
          // If upload failed, still cache locally
          final localCid = 'local_media_$timestamp';
          _fileCache[localCid] = mediaBytes;
          msg['cid'] = localCid;
          msg['fileCid'] = localCid;
          print('⚠️ Upload failed, cached locally with ID: $localCid');
        }

        print('💬 Saving gallery media message with user info:');
        print('  - senderName: ${msg['senderName']}');
        print('  - userAddress: ${msg['userAddress']}');
        print('  - fileName: ${msg['fileName']}');
        print('  - fileId: ${msg['fileId']}');
        print('  - type: ${msg['type']}');

        // Generate temporary message ID for local display (will be replaced by server message_id)
        final tempMessageId = 'temp_media_${DateTime.now().millisecondsSinceEpoch}_${userAddress}';
        final messageTimestamp = DateTime.now();
        
        // Add to local state immediately with temporary ID
        if (mounted) {
          setState(() {
            _messages.add({
              ...msg,
              'timestamp': messageTimestamp,
              'message_id': tempMessageId, // Temporary ID for deduplication
            });
            status = fileId != null
                ? (isVideo ? 'Video sent successfully!' : 'Image sent successfully!')
                : 'Media saved locally (upload failed)';
            // Auto-scroll to bottom when media message is added
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollToBottom(smooth: true);
            });
          });
        }

        // Save to database (works offline + P2P)
        final result = await HybridStorageService.instance.addMessage(
          workspaceId: _effectiveWorkspaceId,
          channelId: widget.channelName,
          senderAddress: userAddress!,
          messageText: msg['content'].toString(),
          fileId: fileId, // Link message with file
        );
        
        final success = result != null;
        if (!success) {
          if (mounted) {
            setState(() {
              _messages.removeWhere((m) => _getMessageId(m) == tempMessageId);
              status = 'Failed to save media message';
            });
          }
          print('❌ Failed to save gallery media message to database');
        } else {
          // Update the local message with the real message_id from server
          if (mounted) {
            setState(() {
              final index = _messages.indexWhere((m) => _getMessageId(m) == tempMessageId);
              if (index >= 0) {
                _messages[index]['message_id'] = result;
                _messages[index]['id'] = result;
              }
            });
          }
          print('✅ Gallery media message saved successfully${fileId != null ? " with fileId: $fileId" : " (local only)"}, message_id: $result');
          // Clear status after a short delay
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              setState(() {
                status = '';
              });
            }
          });
        }
      } else {
        setState(() {
          status = '';
        });
        print('🖼️ Gallery media selection cancelled by user');
      }
    } catch (e) {
      print('❌ Error picking media from gallery: $e');
      setState(() {
        status = 'Error selecting media: $e';
      });
    }
  }

  Future<void> uploadFile() async {
    try {
      // Ensure user address is loaded
      if (userAddress == null) {
        await _loadUserAddress();
      }
      
      setState(() {
        status = 'Selecting file...';
      });
      
      // Pick a file - allow ALL file types (photos, videos, documents, everything)
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any, // Allow all file types
      );
      if (result != null) {
        File file = File(result.files.single.path!);
        final fileSize = await file.length();
        Uint8List fileBytes = await file.readAsBytes();
        
        setState(() {
          status =
              'Uploading file... (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)';
        });
        
        print(
            '📎 Starting file upload: ${result.files.single.name} (${fileSize} bytes)');
        print('📎 User info - Name: $currentUserName, Address: $userAddress');
        
        // Upload file to backend
        print('📤 Uploading file to backend: ${result.files.single.name}');
        final fileId = await DistributedService.uploadFile(
          fileBytes: fileBytes,
          fileName: result.files.single.name,
          workspaceId: _effectiveWorkspaceId,
          uploaderAddress: userAddress!,
          mimeType: result.files.single.extension != null 
              ? 'application/${result.files.single.extension}' 
              : 'application/octet-stream',
        );

        // Create message (even if upload failed, save for offline support)
        final msg = {
          'type': 'file',
          'content': 'File: ${result.files.single.name}',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'fileName': result.files.single.name,
          'fileSize': fileSize,
          'fileId': fileId, // Store fileId from backend
          'cid': fileId, // For backward compatibility
          'fileCid': fileId, // For backward compatibility
          'senderName': currentUserName,
          'sender': currentUserName,
          'userAddress': userAddress ?? '',
          'workspace': widget.workspaceName,
          'channel': widget.channelName,
        };

        // Cache file bytes locally (for small files only, to avoid memory issues)
        if (fileSize < 10 * 1024 * 1024) { // Only cache files < 10MB
          if (fileId != null) {
            if (!_fileCache.containsKey(fileId)) {
              _fileCache[fileId] = fileBytes;
              print('✅ [Cache] File cached locally: $fileId (${fileBytes.length} bytes)');
            }
          } else {
            // If upload failed, still cache locally for small files
            final localCid = 'local_file_${DateTime.now().millisecondsSinceEpoch}';
            _fileCache[localCid] = fileBytes;
            msg['cid'] = localCid;
            msg['fileCid'] = localCid;
            print('⚠️ Upload failed, cached locally with ID: $localCid');
          }
        }
          
        print('💬 Saving file message with user info:');
        print('  - senderName: ${msg['senderName']}');
        print('  - userAddress: ${msg['userAddress']}');
        print('  - fileName: ${msg['fileName']}');
        print('  - fileId: ${msg['fileId']}');
        print('  - fileSize: ${msg['fileSize']} bytes');
          
        // Generate temporary message ID for local display (will be replaced by server message_id)
        final tempMessageId = 'temp_file_${DateTime.now().millisecondsSinceEpoch}_${userAddress}';
        final timestamp = DateTime.now();
        
        // Add to local state immediately with temporary ID
        if (mounted) {
          setState(() {
            _messages.add({
              ...msg,
              'timestamp': timestamp,
              'message_id': tempMessageId, // Temporary ID for deduplication
            });
            status = fileId != null 
                ? 'File uploaded successfully!' 
                : 'File saved locally (upload failed)';
          });
        }
        
        // Save to database
        final mongoResult = await DistributedService.addMessage(
          workspaceId: _effectiveWorkspaceId,
          channelId: widget.channelName,
          senderAddress: userAddress!,
          messageText: msg['content'].toString(),
          fileId: fileId, // Link message with file
        );
        
        final success = mongoResult != null;
        if (!success) {
          if (mounted) {
            setState(() {
              _messages.removeWhere((m) => _getMessageId(m) == tempMessageId);
              status = 'Failed to save file message';
            });
          }
          print('❌ Failed to save file message to database');
        } else {
          // Update the local message with the real message_id from server
          if (mounted) {
            setState(() {
              final index = _messages.indexWhere((m) => _getMessageId(m) == tempMessageId);
              if (index >= 0) {
                _messages[index]['message_id'] = mongoResult;
                _messages[index]['id'] = mongoResult;
              }
            });
          }
          print('✅ File message saved successfully${fileId != null ? " with fileId: $fileId" : " (local only)"}, message_id: $mongoResult');
        }
      } else {
        setState(() {
          status = 'No file selected';
        });
      }
    } catch (e) {
      print('❌ Error uploading file: $e');
      setState(() {
        status = 'Error uploading file: $e';
      });
    }
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    if (userAddress == null) await _loadUserAddress();

    final messageText = _messageController.text.trim();
    _messageController.clear();

    // Generate temporary message ID for local display (will be replaced by server message_id)
    final tempMessageId = 'temp_${DateTime.now().millisecondsSinceEpoch}_${userAddress}';
    final timestamp = DateTime.now();

    final msg = {
      'type': 'text',
      'content': messageText,
      'timestamp': timestamp,
      'senderName': currentUserName,
      'userAddress': userAddress ?? '',
      'workspace': widget.workspaceName,
      'channel': widget.channelName,
      'message_id': tempMessageId, // Temporary ID for deduplication
    };

    // Add to UI immediately with temporary ID
    setState(() {
      _messages.add(msg);
      // Auto-scroll to bottom when user sends message
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom(smooth: true);
      });
    });

    // Use HybridStorageService (works offline + P2P)
    final result = await HybridStorageService.instance.addMessage(
      workspaceId: _effectiveWorkspaceId,
      channelId: widget.channelName,
      senderAddress: userAddress!,
      messageText: messageText,
    );

    if (result == null) {
      // Remove the message if sending failed
      setState(() {
        _messages.removeWhere((m) => _getMessageId(m) == tempMessageId);
        status = 'Failed to send message';
      });
    } else {
      // Update the local message with the real message_id from server
      // This ensures deduplication works correctly
      setState(() {
        final index = _messages.indexWhere((m) => _getMessageId(m) == tempMessageId);
        if (index >= 0) {
          _messages[index]['message_id'] = result;
          // Also update other fields that might come from server
          _messages[index]['id'] = result;
        }
      });
      print('✅ Message sent with ID: $result (updated from temp: $tempMessageId)');
    }
  }

  /// Start voice recording
  Future<void> _startRecording() async {
    try {
      // Haptic feedback
      HapticFeedback.mediumImpact();

      // Request microphone permission
      final permissionStatus = await Permission.microphone.request();
      if (!permissionStatus.isGranted) {
        setState(() {
          status =
              'Microphone permission denied. Please enable it in settings.';
        });
        HapticFeedback.mediumImpact();
        return;
      }

      // Check if recorder is available
      if (await _audioRecorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        _recordingPath = '${dir.path}/voice_$timestamp.m4a';

        // Optimized audio settings for better quality and smaller file size
        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 96000, // Reduced from 128k for better compression
            sampleRate: 44100,
            numChannels: 1, // Mono for smaller file size
          ),
          path: _recordingPath!,
        );

        setState(() {
          _isRecording = true;
          _isLocked = false;
          _recordingDuration = Duration.zero;
          _recordingAmplitude = 0.0;
        });

        // Start timer to update duration (more frequent for smoother UI)
        _recordingTimer =
            Timer.periodic(const Duration(milliseconds: 100), (timer) {
          if (mounted) {
            setState(() {
              _recordingDuration = Duration(milliseconds: timer.tick * 100);
            });
          }
        });

        // Generate waveform data for visual feedback
        _waveformData = List.generate(20, (index) => 0.0);

        // Simulate amplitude for visual feedback (animated waveform)
        _amplitudeTimer =
            Timer.periodic(const Duration(milliseconds: 100), (timer) {
          if (mounted && _isRecording) {
            setState(() {
              // Simulate audio level (0.0 to 1.0) for visual feedback
              _recordingAmplitude =
                  (DateTime.now().millisecondsSinceEpoch % 1000) / 1000.0;

              // Update waveform data (remove first, add new at end)
              _waveformData.removeAt(0);
              _waveformData
                  .add(0.3 + (_recordingAmplitude * 0.7)); // Range: 0.3 to 1.0
            });
          }
        });

        print('🎤 Started recording: $_recordingPath');
      } else {
        setState(() {
          status =
              'Microphone permission not granted. Please enable it in settings.';
        });
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      print('❌ Error starting recording: $e');
      setState(() {
        status = 'Error starting recording: $e';
      });
      HapticFeedback.mediumImpact();
    }
  }

  /// Stop voice recording
  Future<void> _stopRecording({bool forceUnlock = false}) async {
    try {
      if (_isRecording && _recordingPath != null) {
        // If locked and not forcing unlock, don't stop
        if (_isLocked && !forceUnlock) {
          return;
        }

        // Haptic feedback
        HapticFeedback.lightImpact();

        final path = await _audioRecorder.stop();
        _recordingTimer?.cancel();
        _amplitudeTimer?.cancel();

        if (path != null && mounted) {
          setState(() {
            _isRecording = false;
            _isLocked = false;
            _recordingAmplitude = 0.0;
          });

          // Check if recording is long enough (at least 0.5 seconds)
          if (_recordingDuration.inMilliseconds < 500) {
            // Delete short recording
            try {
              final file = File(_recordingPath!);
              if (await file.exists()) {
                await file.delete();
              }
            } catch (_) {}

            setState(() {
              status =
                  'Recording too short. Please record at least 0.5 seconds.';
            });
            HapticFeedback.mediumImpact();
            _recordingPath = null;
            _recordingDuration = Duration.zero;
            _waveformData.clear();

            // Clear status after delay
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) {
                setState(() {
                  status = '';
                });
              }
            });
            return;
          }

          // Send the voice message
          await _sendVoiceMessage(_recordingPath!);
        }
      }
    } catch (e) {
      print('❌ Error stopping recording: $e');
      setState(() {
        status = 'Error stopping recording: $e';
        _isRecording = false;
        _isLocked = false;
        _recordingAmplitude = 0.0;
        _waveformData.clear();
      });
      _recordingTimer?.cancel();
      _amplitudeTimer?.cancel();
      HapticFeedback.mediumImpact();
    }
  }

  /// Cancel voice recording
  Future<void> _cancelRecording() async {
    try {
      if (_isRecording && !_isLocked) {
        // Haptic feedback
        HapticFeedback.mediumImpact();

        await _audioRecorder.stop();
        _recordingTimer?.cancel();
        _amplitudeTimer?.cancel();

        // Delete the recording file
        if (_recordingPath != null) {
          try {
            final file = File(_recordingPath!);
            if (await file.exists()) {
              await file.delete();
            }
          } catch (_) {}
        }

        setState(() {
          _isRecording = false;
          _isLocked = false;
          _recordingPath = null;
          _recordingDuration = Duration.zero;
          _recordingAmplitude = 0.0;
          _waveformData.clear();
        });
      }
    } catch (e) {
      print('❌ Error canceling recording: $e');
      setState(() {
        _isRecording = false;
        _isLocked = false;
        _recordingAmplitude = 0.0;
      });
      _recordingTimer?.cancel();
      _amplitudeTimer?.cancel();
    }
  }

  /// Lock/unlock recording
  void _toggleLockRecording() {
    setState(() {
      _isLocked = !_isLocked;
    });
    HapticFeedback.mediumImpact();
  }

  /// Send voice message
  Future<void> _sendVoiceMessage(String audioPath) async {
    try {
      // Ensure user address is loaded
      if (userAddress == null) {
        await _loadUserAddress();
      }

      setState(() {
        _isUploading = true;
        status = 'Uploading voice message...';
      });

      // Read audio file
      final audioFile = File(audioPath);
      final audioBytes = await audioFile.readAsBytes();
      final fileSize = audioBytes.length;

      // Generate filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'voice_$timestamp.m4a';

      print(
          '🎤 Uploading voice message: $fileName (${fileSize} bytes, ${_formatDuration(_recordingDuration)})');

      // Upload audio file to backend
      print('📤 Uploading voice message to backend: $fileName');
      final fileId = await DistributedService.uploadFile(
        fileBytes: audioBytes,
        fileName: fileName,
        workspaceId: _effectiveWorkspaceId,
        uploaderAddress: userAddress!,
        mimeType: 'audio/m4a',
      );

      // Create message with metadata (even if upload failed, save message for offline support)
      final msg = {
        'type': 'audio',
        'content': 'Voice message: $fileName',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'fileName': fileName,
        'fileSize': fileSize,
        'duration': _recordingDuration.inSeconds, // Store duration in seconds
        'fileId': fileId, // Store fileId from backend
        'cid': fileId, // For backward compatibility
        'fileCid': fileId, // For backward compatibility
        'senderName': currentUserName,
        'sender': currentUserName,
        'userAddress': userAddress ?? '',
        'workspace': widget.workspaceName,
        'channel': widget.channelName,
      };

      // Cache audio bytes locally for immediate playback
      if (fileId != null) {
        if (!_fileCache.containsKey(fileId)) {
          _fileCache[fileId] = audioBytes;
          print('✅ [Cache] Voice message cached locally: $fileId');
        }
      } else {
        // If upload failed, still cache locally for offline playback
        final localCid = 'local_voice_$timestamp';
        _fileCache[localCid] = audioBytes;
        msg['cid'] = localCid;
        msg['fileCid'] = localCid;
        print('⚠️ Upload failed, cached locally with ID: $localCid');
      }

      print('💬 Saving voice message with user info:');
      print('  - senderName: ${msg['senderName']}');
      print('  - userAddress: ${msg['userAddress']}');
      print('  - fileName: ${msg['fileName']}');
      print('  - duration: ${msg['duration']} seconds');
      print('  - fileId: ${msg['fileId']}');

      // Generate temporary message ID for local display (will be replaced by server message_id)
      final tempMessageId = 'temp_voice_${DateTime.now().millisecondsSinceEpoch}_${userAddress}';
      final messageTimestamp = DateTime.now();
      
      // Add to local state immediately with temporary ID
      if (mounted) {
        setState(() {
          _messages.add({
            ...msg,
            'timestamp': messageTimestamp,
            'message_id': tempMessageId, // Temporary ID for deduplication
          });
          status = fileId != null 
              ? 'Voice message sent! ✓' 
              : 'Voice message saved locally (upload failed)';
          _recordingPath = null;
          _recordingDuration = Duration.zero;
          // Auto-scroll to bottom when voice message is added
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToBottom(smooth: true);
          });
          _isUploading = false;
        });
      }

      // Save message to database (with fileId if available)
      final messageText = fileId != null 
          ? 'Voice message: $fileName (${_formatDuration(_recordingDuration)})'
          : 'Voice message: $fileName (${_formatDuration(_recordingDuration)}) [Local]';
      
      // Use HybridStorageService (works offline + P2P)
      final result = await HybridStorageService.instance.addMessage(
        workspaceId: _effectiveWorkspaceId,
        channelId: widget.channelName,
        senderAddress: userAddress!,
        messageText: messageText,
        fileId: fileId, // Pass fileId to link message with file
      );
      
      final success = result != null;
      if (!success) {
        if (mounted) {
          setState(() {
            _messages.removeWhere((m) => _getMessageId(m) == tempMessageId);
            status = 'Failed to save voice message. Please try again.';
            _isUploading = false;
          });
        }
        print('❌ Failed to save voice message to database');
        HapticFeedback.mediumImpact();
      } else {
        print('✅ Voice message saved successfully${fileId != null ? " with fileId: $fileId" : " (local only)"}');
        HapticFeedback.lightImpact();
        // Clear status after delay
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() {
              status = '';
            });
          }
        });
      }

      // Delete temporary file after a delay (to ensure upload completed)
      Future.delayed(const Duration(seconds: 5), () async {
        try {
          if (await audioFile.exists()) {
            await audioFile.delete();
            print('🗑️ Deleted temporary voice file: $audioPath');
          }
        } catch (e) {
          print('⚠️ Error deleting temp file: $e');
        }
      });
    } catch (e) {
      print('❌ Error sending voice message: $e');
      setState(() {
        status = 'Error: ${e.toString()}';
        _isUploading = false;
      });
      HapticFeedback.mediumImpact();
    }
  }

  /// Play audio message
  Future<void> _playAudio(String cid, String audioId) async {
    try {
      // If same audio is playing, pause it
      if (_playingAudioId == audioId) {
        await _audioPlayer.pause();
        setState(() {
          _playingAudioId = null;
          _audioPosition = Duration.zero;
        });
        HapticFeedback.lightImpact();
        return;
      }

      // Stop any currently playing audio
      if (_playingAudioId != null) {
        await _audioPlayer.stop();
        _playerStateSubscription?.cancel();
        _positionSubscription?.cancel();
      }

      setState(() {
        status = 'Loading audio...';
        _playingAudioId = audioId;
        _audioPosition = Duration.zero;
      });

      // Get audio bytes from cache or download
      Uint8List? audioBytes;
      if (_fileCache.containsKey(cid) && _fileCache[cid] != null) {
        audioBytes = _fileCache[cid]!;
        print('✅ [Play] Using cached audio: $cid');
      } else {
        audioBytes = await _getCachedFile(cid);
      }

      if (audioBytes != null) {
        // Save to temporary file for playback
        final dir = await getTemporaryDirectory();
        final tempPath = '${dir.path}/playback_$audioId.m4a';
        final tempFile = File(tempPath);
        await tempFile.writeAsBytes(audioBytes);

        // Play audio
        await _audioPlayer.play(DeviceFileSource(tempPath));
        HapticFeedback.lightImpact();

        // Get audio duration
        _audioDuration = await _audioPlayer.getDuration() ?? Duration.zero;

        // Listen for position updates
        _positionSubscription =
            _audioPlayer.onPositionChanged.listen((position) {
          if (mounted) {
            setState(() {
              _audioPosition = position;
            });
          }
        });

        // Listen for completion
        _playerStateSubscription =
            _audioPlayer.onPlayerStateChanged.listen((state) {
          if (mounted) {
            if (state == PlayerState.completed) {
              setState(() {
                _playingAudioId = null;
                _audioPosition = Duration.zero;
                status = '';
              });
              _positionSubscription?.cancel();
            }
          }
        });

        setState(() {
          status = '';
        });
      } else {
        setState(() {
          status = 'Failed to load audio. Please try again.';
          _playingAudioId = null;
        });
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      print('❌ Error playing audio: $e');
      setState(() {
        status = 'Error playing audio: $e';
        _playingAudioId = null;
      });
      HapticFeedback.mediumImpact();
    }
  }

  /// Format duration for display
  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return minutes > 0 ? '$minutes:${seconds.toString().padLeft(2, '0')}' : '0:${seconds.toString().padLeft(2, '0')}';
  }

  /// Format duration for short display (e.g., "1:23" or "0:45")
  String _formatShortDuration(Duration d) {
    final totalSeconds = d.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Shows image in full screen viewer
  Future<void> _showFullScreenImage(String cid, String fileName) async {
    final bytes = await _getCachedFile(cid);
    if (bytes != null && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _FullScreenImageViewer(imageBytes: bytes, fileName: fileName),
          fullscreenDialog: true,
        ),
      );
    }
  }

  Future<void> downloadAndOpenFile(String cid, String fileName) async {
    final bytes = await _getCachedFile(cid);
    if (bytes != null) {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/$fileName';
      await File(path).writeAsBytes(bytes);
      await OpenFile.open(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCurrentUser = (String? address) {
      if (userAddress == null || address == null) return false;
      return address.toLowerCase().trim() == userAddress!.toLowerCase().trim();
    };

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        resizeToAvoidBottomInset: true, // Auto-adjust when keyboard opens
      appBar: PreferredSize(
          preferredSize: const Size.fromHeight(70),
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
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 12, 8),
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                            size: 22,
                          ),
                onPressed: () => Navigator.pop(context),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 40,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Clickable channel profile picture
                        GestureDetector(
                          onTap: () => _navigateToChannelInfo(),
                          child: Container(
                            width: 38,
                            height: 38,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.2),
                            ),
                            child: Center(
                              child: Text(
                                '#',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Clickable channel name and workspace name
                        GestureDetector(
                          onTap: () => _navigateToChannelInfo(),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '# $_currentChannelName',
                    style: const TextStyle(
                      color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                  letterSpacing: 0.0,
                    ),
                  ),
                              const SizedBox(height: 2),
                  Text(
                    widget.workspaceName,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                      fontSize: 12,
                                  letterSpacing: 0.0,
                    ),
                  ),
                ],
              ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                if (_isLoadingMembers)
                  const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4.0),
                    child: SizedBox(
                              width: 18,
                              height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: () {
                      _showChannelInfo();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.people,
                              color: Colors.white, size: 18),
                          if (_memberCount > 0) ...[
                            const SizedBox(width: 4),
                            Text(
                              '$_memberCount',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
                  ],
          ),
        ),
      ),
          ),
        ),
        body: SafeArea(
          top: true,
          child: Stack(
            children: [
              Column(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Status message
          if (status.isNotEmpty)
            Container(
              width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      color:
                          status.contains('Error') || status.contains('Failed')
                  ? Colors.red.withOpacity(0.1) 
                  : Colors.green.withOpacity(0.1),
              child: Text(
                status,
                style: TextStyle(
                          color: status.contains('Error') ||
                                  status.contains('Failed')
                              ? Colors.red[700]
                              : Colors.green[700],
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          
          // Messages list
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                                  color: Color(0xFF0F365F),
                          size: 64,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No messages yet',
                          style: TextStyle(
                                    color: Color(0xFF828282),
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Start the conversation!',
                          style: TextStyle(
                                    color: Color(0xFFBDBDBD),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                            controller: _scrollController, // Auto-scroll controller
                            reverse: false, // Messages: oldest at top, newest at bottom (WhatsApp/Instagram style)
                            padding: const EdgeInsetsDirectional.fromSTEB(
                                20, 0, 20, 0),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                              final isSent = isCurrentUser(
                                  message['userAddress']?.toString());
                              return _buildMessageTile(message, isSent: isSent);
                    },
                  ),
          ),
          
                  // Input area - iMessage style
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(0, 10, 0, 8),
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(
                        minHeight: 56,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xB3FFFFFF),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding:
                            const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 8),
            child: Row(
                          mainAxisSize: MainAxisSize.max,
                          crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                            // Camera icon
                            GestureDetector(
                              onTap: _takePicture,
                  child: Container(
                                padding: const EdgeInsets.all(8),
                                child: const Icon(
                                  Icons.photo_camera,
                                  color: Color(0xFF0F365F),
                                  size: 22,
                                ),
                              ),
                            ),
                            // Attach/App Store icon with upward popup menu
                            PopupMenuButton<String>(
                              offset: const Offset(
                                  -20, -120), // Position above the icon
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              color: Colors.white,
                              elevation: 8,
                              padding: EdgeInsets.zero,
                              icon: Container(
                                padding: const EdgeInsets.all(8),
                                child: const Icon(
                                  Icons.add_rounded,
                                  color: Color(0xFF0F365F),
                                  size: 24,
                                ),
                              ),
                              itemBuilder: (BuildContext context) => [
                                PopupMenuItem<String>(
                                  value: 'attach_file',
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.attach_file,
                                        color: Color(0xFF0F365F),
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      const Text(
                                        'Attach File',
                                        style: TextStyle(
                                          color: Color(0xFF0F365F),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuItem<String>(
                                  value: 'photos',
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.photo_library,
                                        color: Color(0xFF0F365F),
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      const Text(
                                        'Photos',
                                        style: TextStyle(
                                          color: Color(0xFF0F365F),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              onSelected: (String value) {
                                if (value == 'attach_file') {
                                  uploadFile();
                                } else if (value == 'photos') {
                                  _pickImageFromGallery();
                                }
                              },
                            ),
                            const SizedBox(width: 4),
                            // Text input field with Stack for conditional icons
                            Expanded(
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  // TextField
                                  Padding(
                                    padding:
                                        const EdgeInsetsDirectional.fromSTEB(
                                            8, 0, 0, 0),
                    child: TextField(
                      controller: _messageController,
                                      autofocus: false,
                                      textCapitalization:
                                          TextCapitalization.sentences,
                                      style: const TextStyle(
                                        color: Color(0xFF333333),
                                        fontSize: 16,
                                        letterSpacing: 0.0,
                                        height: 1.2,
                                      ),
                      decoration: InputDecoration(
                                        isDense: true,
                                        hintText: 'Text Message...',
                                        hintStyle: const TextStyle(
                                          color: Color(0xFFBDBDBD),
                                          fontSize: 16,
                                          letterSpacing: 0.0,
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderSide: const BorderSide(
                                            color: Color(0xFF828282),
                                            width: 1.0,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(24),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderSide: const BorderSide(
                                            color: Color(0x00000000),
                                            width: 1.0,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(24),
                                        ),
                                        errorBorder: OutlineInputBorder(
                                          borderSide: const BorderSide(
                                            color: Color(0x00000000),
                                            width: 1.0,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(24),
                                        ),
                                        focusedErrorBorder: OutlineInputBorder(
                                          borderSide: const BorderSide(
                                            color: Color(0x00000000),
                                            width: 1.0,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(24),
                                        ),
                                        filled: true,
                                        fillColor: const Color(0x7FFFFFFF),
                                        contentPadding:
                                            EdgeInsetsDirectional.fromSTEB(
                                          16,
                                          12,
                                          _hasText
                                              ? 50
                                              : 50, // Right padding for icon space
                                          12,
                                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                                  // Conditional icons inside input field - positioned absolutely
                                  Positioned(
                                    right: 6,
                                    top: 0,
                                    bottom: 0,
                                    child: Center(
                                      child: _hasText
                                          ? GestureDetector(
                                              onTap: _sendMessage,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.all(8),
                                                child: const Icon(
                                                  Icons.send_rounded,
                                                  color: Color(0xFF0F365F),
                                                  size: 20,
                                                ),
                                              ),
                                            )
                                          : _isLocked && _isRecording
                                              ? GestureDetector(
                                                  // When locked, only tap to send
                                                  onTap: () {
                                                    print(
                                                        '🎤 [Tap] Sending locked recording...');
                                                    _stopRecording(
                                                        forceUnlock: true);
                                                  },
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.all(8),
                                                    child: const Icon(
                                                      Icons.fiber_manual_record,
                                                      color: Colors.red,
                                                      size: 18,
                                                    ),
                                                  ),
                                                )
                                              : Listener(
                                                  onPointerDown: (event) {
                                                    // Start recording immediately on pointer down
                                                    if (!_isRecording &&
                                                        !_isLocked) {
                                                      _panStartPosition =
                                                          event.localPosition;
                                                      _startRecording();
                                                    }
                                                  },
                                                  onPointerMove: (event) {
                                                    // Handle swipe up to lock during recording
                                                    if (_isRecording &&
                                                        !_isLocked &&
                                                        _panStartPosition !=
                                                            null) {
                                                      final deltaY =
                                                          _panStartPosition!
                                                                  .dy -
                                                              event
                                                                  .localPosition
                                                                  .dy;
                                                      // Swipe up to lock (threshold: 30 pixels)
                                                      if (deltaY > 30) {
                                                        _toggleLockRecording();
                                                        _panStartPosition =
                                                            null;
                                                      }
                                                    }
                                                  },
                                                  onPointerUp: (event) {
                                                    // Release to send (if not locked)
                                                    _panStartPosition = null;
                                                    if (_isRecording &&
                                                        !_isLocked) {
                                                      _stopRecording(
                                                          forceUnlock: false);
                                                    }
                                                  },
                                                  onPointerCancel: (event) {
                                                    // Cancel recording if pointer is cancelled
                                                    _panStartPosition = null;
                                                    if (_isRecording &&
                                                        !_isLocked) {
                                                      _cancelRecording();
                                                    }
                                                  },
                                                  child: GestureDetector(
                                                    behavior:
                                                        HitTestBehavior.opaque,
                                                    // Fallback: also handle pan gestures
                                                    onPanStart: (details) {
                                                      if (!_isRecording &&
                                                          !_isLocked) {
                                                        _panStartPosition =
                                                            details
                                                                .localPosition;
                                                        _startRecording();
                                                      }
                                                    },
                                                    onPanUpdate: (details) {
                                                      if (_isRecording &&
                                                          !_isLocked &&
                                                          _panStartPosition !=
                                                              null) {
                                                        final deltaY =
                                                            _panStartPosition!
                                                                    .dy -
                                                                details
                                                                    .localPosition
                                                                    .dy;
                                                        // Swipe up to lock (threshold: 30 pixels)
                                                        if (deltaY > 30) {
                                                          _toggleLockRecording();
                                                          _panStartPosition =
                                                              null;
                                                        }
                                                      }
                                                    },
                                                    onPanEnd: (details) {
                                                      _panStartPosition = null;
                                                      if (_isRecording &&
                                                          !_isLocked) {
                                                        _stopRecording(
                                                            forceUnlock: false);
                                                      }
                                                    },
                                                    onPanCancel: () {
                                                      _panStartPosition = null;
                                                      if (_isRecording &&
                                                          !_isLocked) {
                                                        _cancelRecording();
                                                      }
                                                    },
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              8),
                                                      child: AnimatedSwitcher(
                                                        duration:
                                                            const Duration(
                                                                milliseconds:
                                                                    200),
                                                        child: Icon(
                                                          _isRecording
                                                              ? Icons.mic
                                                              : Icons.mic_none,
                                                          key: ValueKey(
                                                              'mic_${_isRecording}'),
                                                          color: _isRecording
                                                              ? Colors.red
                                                              : const Color(
                                                                  0xFF0F365F),
                                                          size: 18,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                    ),
                ),
              ],
            ),
          ),
        ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // Recording overlay
              _buildRecordingOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  /// Recording overlay widget with professional design and wave line
  Widget _buildRecordingOverlay() {
    if (!_isRecording && !_isUploading) return const SizedBox.shrink();

    return Positioned(
      bottom: 100,
      left: 0,
      right: 0,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        constraints: const BoxConstraints(maxHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: _isUploading
              ? const Color(0xFF0F365F).withOpacity(0.95)
              : const Color(0xFF0F365F).withOpacity(0.95),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: _isUploading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Uploading...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Animated recording indicator (red dot)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.8),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Waveform visualization
                  if (_waveformData.isNotEmpty)
                    SizedBox(
                      height: 24,
                      width: 120,
                      child: CustomPaint(
                        painter: WaveformPainter(_waveformData),
                      ),
                    )
                  else
                    const SizedBox(width: 120, height: 24),
                  const SizedBox(width: 12),
                  // Duration display
                  Text(
                    _formatShortDuration(_recordingDuration),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (_isLocked) ...[
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.lock,
                      color: Colors.white,
                      size: 14,
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  /// Navigate to channel information page
  Future<void> _navigateToChannelInfo() async {
    if (!mounted) return;
    
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ChannelInfoPage(
          channelName: widget.channelName, // Pass original DB name, not display name
          workspaceName: widget.workspaceName,
          userAddress: userAddress,
        ),
      ),
    );
    
    // Check if channel was deleted
    if (result != null && result['deleted'] == true) {
      print('🗑️ [NavigateToInfo] Channel was deleted, navigating back to workspace');
      // Navigate back to workspace home page
      if (mounted) {
        Navigator.pop(context);
      }
      return;
    }
    
    // If channel name was updated, reload the display name from both sources
    if (result != null && result['channelName'] != null && result['deleted'] != true) {
      final newName = result['channelName'] as String;
      print('🔄 [NavigateToInfo] Channel name updated to: "$newName"');
      
      // Update local state immediately
      setState(() {
        _currentChannelName = newName;
      });
      
      // Re-resolve to ensure consistency with database
      await _resolveChannelDisplayName();
      
      // Reload messages to ensure everything is in sync
      await _loadMessages();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Channel renamed to "# $newName"'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      // Even if no rename, re-resolve name in case it was changed elsewhere
      await _resolveChannelDisplayName();
    }
  }

  Future<void> _showChannelInfo() async {
    // Use MongoDB members
    final members = await DistributedService.getWorkspaceMembers(widget.workspaceName);
    String? inviterAddress = null; // Not needed for MongoDB lookup usually

    // Ensure current logged-in user is in the members list
    if (userAddress != null) {
      final userKey = userAddress!.toLowerCase().trim();
      final userExists = members
          .any((m) => m['memberAddress']?.toString().toLowerCase() == userKey);

      if (!userExists) {
        // Get current user's display name
        final userDisplayName = await _getUserNameFromMongoDB();
        
        members.add({
          'type': 'member',
          'workspaceName': widget.workspaceName,
          'inviterAddress': inviterAddress ?? '',
          'memberAddress': userKey,
          'memberDisplayName': userDisplayName,
          'joinedAt': DateTime.now().millisecondsSinceEpoch,
          'isCurrentUser': true,
        });
      }
    }

    // Fetch profile names for ALL members to ensure we have the latest names
    print(
        '🔄 [Channel] Fetching profile names for ${members.length} members...');
    
    // Create a copy of members list to avoid modification during iteration
    final updatedMembers = <Map<String, dynamic>>[];
    
    for (int i = 0; i < members.length; i++) {
      final member = Map<String, dynamic>.from(members[i]); // Create a copy
      final memberAddr = member['memberAddress']?.toString();
      if (memberAddr != null) {
        print(
            '📝 [Channel] Processing member ${i + 1}/${members.length}: $memberAddr');
        
        // Always fetch profile name to ensure we have the latest
        final profileName = await _getProfileNameForAddress(memberAddr);
        
        if (profileName != null && profileName.isNotEmpty) {
          // Update display name with profile name (prefer profile name over stored display name)
          member['memberDisplayName'] = profileName;
          print(
              '✅ [Channel] Updated member $memberAddr with name: $profileName');
        } else {
          // If no profile name found, check if we have a stored display name
          final storedName = member['memberDisplayName']?.toString();
          if (storedName == null || storedName.isEmpty) {
            print(
                '⚠️ [Channel] No profile name found for member: $memberAddr (will use address)');
            // Clear any empty display name
            member.remove('memberDisplayName');
          } else {
            print(
                'ℹ️ [Channel] Using stored display name for $memberAddr: $storedName');
          }
        }
      }
      updatedMembers.add(member);
    }
    
    print('📊 [Channel] Final members list:');
    for (var m in updatedMembers) {
      final addr = m['memberAddress'] ?? 'UNKNOWN';
      final name = m['memberDisplayName'] ?? 'NO NAME';
      print('  - $addr: $name');
    }
    
    // Update the members list
    members.clear();
    members.addAll(updatedMembers);

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F365F),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '# $_currentChannelName',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.workspaceName,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 24),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Divider(color: Colors.white.withOpacity(0.2), height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  const Icon(Icons.people, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    'Members (${members.length})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: members.isEmpty
                  ? Center(
                      child: Text(
                        'No members found',
                        style: TextStyle(color: Colors.white.withOpacity(0.7)),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: members.length,
                      itemBuilder: (context, index) {
                        final member = members[index];
                        return _buildMemberTile(member);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberTile(Map<String, dynamic> member) {
    final memberAddress = member['memberAddress']?.toString() ?? '';
    final isInviter = member['isInviter'] == true;
    final isCurrentUser = userAddress != null && 
                         memberAddress.toLowerCase() == userAddress!.toLowerCase();
    
    // Get display name - prefer memberDisplayName (which should be profile name)
    String displayName = (member['memberDisplayName']?.toString() ?? '').trim();
    
    // If no display name, use shortened address as fallback
    final hasProfileName = displayName.isNotEmpty;
    if (!hasProfileName) {
      displayName = memberAddress.length > 10 
        ? '${memberAddress.substring(0, 6)}...${memberAddress.substring(memberAddress.length - 4)}'
        : memberAddress;
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
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: CircleAvatar(
        backgroundColor:
            isInviter ? const Color(0xFF23C16B) : Colors.white.withOpacity(0.2),
        radius: 20,
        child: Text(
          initial,
          style: TextStyle(
            color: isInviter ? Colors.white : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              displayName,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500),
            ),
          ),
          if (isInviter)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF23C16B).withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Admin',
                style: TextStyle(
                  color: Color(0xFF23C16B),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      // Only show address in subtitle if we don't have a profile name
      subtitle: hasProfileName 
        ? null // Hide address when we have a proper name
        : Text(
            memberAddress.length > 20 
              ? '${memberAddress.substring(0, 10)}...${memberAddress.substring(memberAddress.length - 8)}'
              : memberAddress,
              style:
                  TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11),
          ),
    );
  }

  /// PHASE 4: Get message state indicator widget
  /// Returns visual indicator for message state: ⏳ Pending (offline), ✅ Confirmed (online)
  Widget _getMessageStateIndicator(String? messageState, bool isSent) {
    // Only show indicators for sent messages (user's own messages)
    if (!isSent) {
      return const SizedBox.shrink();
    }
    
    if (messageState == null || messageState.isEmpty) {
      // Default: show confirmed icon for sent messages (fallback)
      return const Icon(Icons.check_circle, color: Colors.green, size: 16);
    }
    
    switch (messageState) {
      case 'ONLINE_CONFIRMED':
      case 'SYNCED':
        // ✅ Confirmed (online) - message is on server
        return const Icon(
          Icons.check_circle,
          color: Colors.green,
          size: 16,
        );
      case 'OFFLINE_LOCAL':
      case 'PENDING_SYNC':
        // ⏳ Pending (offline) - message not yet synced
        return const Icon(
          Icons.access_time,
          color: Colors.orange,
          size: 16,
        );
      default:
        // Default: show confirmed icon (fallback)
        return const Icon(Icons.check_circle, color: Colors.green, size: 16);
    }
  }

  Widget _buildMessageTile(Map<String, dynamic> message,
      {required bool isSent}) {
    final timestamp = _formatTimestamp(message['timestamp']);
    // PHASE 4: Get message state for visual indicator
    final messageState = message['message_state']?.toString();

    // Priority: If type is explicitly set, use it. Otherwise, infer from extension or content.
    // If type is 'file', always treat as file regardless of extension
    final messageType = message['type']?.toString()?.toLowerCase() ?? '';
    final fileName = message['fileName']?.toString() ?? '';
    final content = (message['content']?.toString() ?? '').toLowerCase();
    final cid = message['cid']?.toString() ?? 
                message['fileCid']?.toString() ?? 
                message['fileId']?.toString() ?? 
                '';
    
    // Detect type from messageType, fileName, or content
    String detectedType = messageType;
    if (detectedType.isEmpty || detectedType == 'text') {
      // Try to detect from content
      if (content.contains('voice message') || content.contains('audio')) {
        detectedType = 'audio';
      } else if (content.contains('image:') || content.contains('photo')) {
        detectedType = 'image';
      } else if (content.contains('video:')) {
        detectedType = 'video';
      } else if (content.contains('file:')) {
        detectedType = 'file';
      } else if (fileName.isNotEmpty) {
        // Detect from file extension
        final lowerFileName = fileName.toLowerCase();
        if (lowerFileName.endsWith('.m4a') || lowerFileName.endsWith('.mp3') || 
            lowerFileName.endsWith('.wav') || lowerFileName.endsWith('.aac')) {
          detectedType = 'audio';
        } else if (lowerFileName.endsWith('.jpg') || lowerFileName.endsWith('.jpeg') || 
                   lowerFileName.endsWith('.png') || lowerFileName.endsWith('.gif') || 
                   lowerFileName.endsWith('.webp')) {
          detectedType = 'image';
        } else if (lowerFileName.endsWith('.mp4') || lowerFileName.endsWith('.mov') || 
                   lowerFileName.endsWith('.avi') || lowerFileName.endsWith('.mkv') || 
                   lowerFileName.endsWith('.webm') || lowerFileName.endsWith('.3gp') || 
                   lowerFileName.endsWith('.m4v')) {
          detectedType = 'video';
        } else if (cid.isNotEmpty) {
          detectedType = 'file';
        }
      } else if (cid.isNotEmpty) {
        detectedType = 'file';
      }
    }
    
    final isFile = detectedType == 'file';
    final isImage = detectedType == 'image';
    final isVideo = detectedType == 'video';
    final isAudio = detectedType == 'audio';

    // Fallback: if no type is set and it has cid/fileId, treat as file
    final isFileFallback = !isFile &&
        !isImage &&
        !isVideo &&
        !isAudio &&
        cid.isNotEmpty;

    if (isSent) {
      // Sent message (right aligned)
      return Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(0, 24, 0, 0),
      child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            if (isImage)
              GestureDetector(
                onTap: () {
                  _showFullScreenImage(
                    message['cid'] ?? message['fileCid'] ?? message['fileId'] ?? '',
                    message['fileName'] ?? 'image.jpg',
                  );
                },
                child: Container(
                  width: 300,
                  height: 180,
                  constraints: const BoxConstraints(minHeight: 180),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(3),
                    ),
                    border: Border.all(color: const Color(0xFFF9F2F2)),
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(3),
                    ),
                    child: Stack(
                      children: [
                        Builder(
                          builder: (context) {
                            final cid = message['cid'] ?? message['fileCid'];

                            // If cached, show immediately without FutureBuilder
                            if (_fileCache.containsKey(cid) &&
                                _fileCache[cid] != null) {
                              return Image.memory(
                                _fileCache[cid]!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                              );
                            }

                            // Only use FutureBuilder if not cached
                            return FutureBuilder<Uint8List?>(
                              key: ValueKey(
                                  'image_$cid'), // Unique key to prevent rebuilds
                              future: _getCachedFile(cid),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Center(
                                      child: CircularProgressIndicator());
                                }
                                if (snapshot.hasData && snapshot.data != null) {
                                  return Image.memory(
                                    snapshot.data!,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                  );
                                }
    return Container(
                                  color: const Color(0xFFF5F5F5),
                                  child: const Center(
                                    child: Icon(Icons.broken_image,
                                        color: Color(0xFF0F365F)),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                        Align(
                          alignment: const AlignmentDirectional(0.92, 0.86),
      child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                timestamp,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black26,
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              // PHASE 4: Show state indicator (⏳ Pending or ✅ Confirmed)
                              _getMessageStateIndicator(messageState, isSent),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (isVideo)
              GestureDetector(
                onTap: () {
                  downloadAndOpenFile(
                    message['cid'] ?? message['fileCid'] ?? message['fileId'] ?? '',
                    message['fileName'] ?? 'video.mp4',
                  );
                },
                child: Container(
                  width: 300,
                  height: 180,
                  constraints: const BoxConstraints(minHeight: 180),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(3),
                    ),
                    border: Border.all(color: const Color(0xFFF9F2F2)),
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(3),
                    ),
                    child: Stack(
                      children: [
                        // Video thumbnail placeholder
                        Container(
                          color: const Color(0xFF1A1A1A),
                          child: const Center(
                            child: Icon(
                              Icons.videocam,
                              color: Colors.white54,
                              size: 48,
                            ),
                          ),
                        ),
                        // Play icon overlay
                        const Center(
                          child: Icon(
                            Icons.play_circle_filled,
                            color: Colors.white,
                            size: 64,
                          ),
                        ),
                        Align(
                          alignment: const AlignmentDirectional(0.92, 0.86),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                timestamp,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black26,
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
          ),
                              const SizedBox(width: 4),
                              // PHASE 4: Show state indicator (⏳ Pending or ✅ Confirmed)
                              _getMessageStateIndicator(messageState, isSent),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (isAudio)
              GestureDetector(
                onTap: () {
                  final audioId = message['cid'] ?? message['fileCid'] ?? message['fileId'] ?? '';
                  _playAudio(audioId, audioId);
                },
                child: Container(
                  width: 300,
                  constraints: const BoxConstraints(maxWidth: 260),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(3),
                    ),
                    border: Border.all(color: const Color(0xFF828282)),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 12),
            child: Column(
                      mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
                Row(
                          mainAxisSize: MainAxisSize.max,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _playingAudioId ==
                                          (message['cid'] ?? message['fileCid'] ?? message['fileId'])
                                      ? Icons.pause_circle_filled
                                      : Icons.play_circle_filled,
                                  color: const Color(0xFF0F365F),
                                  size: 24,
          ),
          const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                                      'Voice message',
                      style: const TextStyle(
                                        color: Color(0xFF828282),
                                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                                    const SizedBox(height: 2),
                    Text(
                                      _playingAudioId ==
                                              (message['cid'] ??
                                                  message['fileCid'] ??
                                                  message['fileId'])
                                          ? '${_formatShortDuration(_audioPosition)} / ${_formatShortDuration(_audioDuration.inMilliseconds > 0 ? _audioDuration : Duration(seconds: message['duration'] ?? 0))}'
                                          : (message['duration'] != null
                                              ? _formatShortDuration(Duration(
                                                  seconds: message['duration']))
                                              : 'Tap to play'),
                      style: const TextStyle(
                                        color: Color(0xFFBDBDBD),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  timestamp,
                                  style: const TextStyle(
                                    color: Color(0xFFBDBDBD),
                        fontSize: 12,
                                    letterSpacing: 0.0,
                    ),
                ),
                                const SizedBox(width: 6),
                                // PHASE 4: Show state indicator (⏳ Pending or ✅ Confirmed)
                                _getMessageStateIndicator(messageState, isSent),
                  ],
                ),
                          ],
                        ),
                        // Progress bar for playing audio
                        if (_playingAudioId ==
                                (message['cid'] ?? message['fileCid'] ?? message['fileId']) &&
                            _audioDuration.inMilliseconds > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: _audioPosition.inMilliseconds /
                                    _audioDuration.inMilliseconds,
                                backgroundColor: const Color(0xFFE0E0E0),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                    Color(0xFF0F365F)),
                                minHeight: 2,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              )
            else
              GestureDetector(
                onTap: (isFile || isFileFallback)
                    ? () {
                        downloadAndOpenFile(
                          message['cid'] ?? message['fileCid'],
                          message['fileName'] ?? 'file',
                        );
                      }
                    : null,
                child: Container(
                  width: 300,
                  constraints: const BoxConstraints(maxWidth: 260),
                    decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(3),
                    ),
                    border: Border.all(color: const Color(0xFF828282)),
                    ),
                  child: Padding(
                    padding:
                        const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: (isFile || isFileFallback)
                              ? Row(
                                  children: [
                                    const Icon(Icons.file_present,
                                        color: Color(0xFF0F365F), size: 20),
                        const SizedBox(width: 8),
          Expanded(
            child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
              children: [
                              Text(
                                message['fileName'] ?? 'File',
                                style: const TextStyle(
                                              color: Color(0xFF828282),
                                  fontWeight: FontWeight.w500,
                                              fontSize: 14,
                                ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                              ),
                                          const SizedBox(height: 2),
                              Text(
                                            'Tap to open',
                                style: const TextStyle(
                                              color: Color(0xFFBDBDBD),
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
                                  message['content'] ?? '',
                                  style: const TextStyle(
                                    color: Color(0xFF828282),
                                    fontSize: 14,
                                    letterSpacing: 0.0,
                                  ),
                                ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                              timestamp,
                              style: const TextStyle(
                                color: Color(0xFFBDBDBD),
                                  fontSize: 12,
                                letterSpacing: 0.0,
                                ),
                            ),
                            const SizedBox(width: 6),
                            // PHASE 4: Show state indicator (⏳ Pending or ✅ Confirmed)
                            _getMessageStateIndicator(messageState, isSent),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    } else {
      // Received message (left aligned)
      return Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(0, 24, 0, 0),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF0F365F),
              ),
              child: Center(
                child: Text(
                  (message['senderName'] ?? 'U')[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 0, 0),
              child: isImage
                  ? GestureDetector(
                      onTap: () {
                        _showFullScreenImage(
                          message['cid'] ?? message['fileCid'] ?? message['fileId'] ?? '',
                          message['fileName'] ?? 'image.jpg',
                        );
                          },
                      child: Container(
                        width: 300,
                        height: 180,
                        constraints: const BoxConstraints(minHeight: 180),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(24),
                            bottomRight: Radius.circular(24),
                            topLeft: Radius.circular(3),
                            topRight: Radius.circular(24),
                          ),
                          border: Border.all(color: const Color(0xFFF9F2F2)),
                        ),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(24),
                            bottomRight: Radius.circular(24),
                            topLeft: Radius.circular(3),
                            topRight: Radius.circular(24),
                          ),
                          child: Stack(
                            children: [
                              Builder(
                                builder: (context) {
                                  final cid =
                                      message['cid'] ?? message['fileCid'] ?? message['fileId'] ?? '';

                                  // If cached, show immediately without FutureBuilder
                                  if (_fileCache.containsKey(cid) &&
                                      _fileCache[cid] != null) {
                                    return Image.memory(
                                      _fileCache[cid]!,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      height: double.infinity,
                                    );
                                  }

                                  // Only use FutureBuilder if not cached
                                  return FutureBuilder<Uint8List?>(
                                    key: ValueKey(
                                        'image_$cid'), // Unique key to prevent rebuilds
                                    future: _getCachedFile(cid),
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState ==
                                          ConnectionState.waiting) {
                                        return const Center(
                                            child: CircularProgressIndicator());
                                      }
                                      if (snapshot.hasData &&
                                          snapshot.data != null) {
                                        return Image.memory(
                                          snapshot.data!,
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                          height: double.infinity,
                                        );
                                      }
                                      return Container(
                                        color: const Color(0xFFF5F5F5),
                                        child: const Center(
                                          child: Icon(Icons.broken_image,
                                              color: Color(0xFF0F365F)),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                              Align(
                                alignment:
                                    const AlignmentDirectional(0.92, 0.86),
                                child: Text(
                                  timestamp,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black26,
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : isVideo
                      ? GestureDetector(
                          onTap: () {
                            downloadAndOpenFile(
                              message['cid'] ?? message['fileCid'] ?? message['fileId'] ?? '',
                              message['fileName'] ?? 'video.mp4',
                            );
                          },
                          child: Container(
                            width: 300,
                            height: 180,
                            constraints: const BoxConstraints(minHeight: 180),
                    decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(24),
                                bottomRight: Radius.circular(24),
                                topLeft: Radius.circular(3),
                                topRight: Radius.circular(24),
                              ),
                              border:
                                  Border.all(color: const Color(0xFFF9F2F2)),
                            ),
                            child: ClipRRect(
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(24),
                                bottomRight: Radius.circular(24),
                                topLeft: Radius.circular(3),
                                topRight: Radius.circular(24),
                              ),
                              child: Stack(
                                children: [
                                  // Video thumbnail placeholder
                                  Container(
                                    color: const Color(0xFF1A1A1A),
                                    child: const Center(
                                      child: Icon(
                                        Icons.videocam,
                                  color: Colors.white54,
                                        size: 48,
                                      ),
                    ),
                                  ),
                                  // Play icon overlay
                                  const Center(
                                    child: Icon(
                                      Icons.play_circle_filled,
                                      color: Colors.white,
                                      size: 64,
                                    ),
                                  ),
                                  Align(
                                    alignment:
                                        const AlignmentDirectional(0.92, 0.86),
                    child: Text(
                                      timestamp,
                                      style: const TextStyle(
                                        color: Colors.white,
                                  fontSize: 12,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black26,
                                            blurRadius: 4,
                                          ),
                                        ],
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                          ),
                        )
                      : isAudio
                          ? GestureDetector(
                              onTap: () {
                                final audioId =
                                    message['cid'] ?? message['fileCid'] ?? message['fileId'] ?? '';
                                _playAudio(audioId, audioId);
                              },
                              child: Container(
                                width: 300,
                                constraints:
                                    const BoxConstraints(maxWidth: 260),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: const BorderRadius.only(
                                    bottomLeft: Radius.circular(24),
                                    bottomRight: Radius.circular(24),
                                    topLeft: Radius.circular(3),
                                    topRight: Radius.circular(24),
                                  ),
                                  border: Border.all(
                                      color: const Color(0xFF828282)),
                                ),
                                child: Padding(
                                  padding: const EdgeInsetsDirectional.fromSTEB(
                                      12, 12, 12, 12),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.max,
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                _playingAudioId ==
                                                        (message['cid'] ??
                                                            message['fileCid'] ??
                                                            message['fileId'])
                                                    ? Icons.pause_circle_filled
                                                    : Icons.play_circle_filled,
                                                color: const Color(0xFF0F365F),
                                                size: 24,
                                              ),
                                              const SizedBox(width: 12),
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Voice message',
                                                    style: const TextStyle(
                                                      color: Color(0xFF828282),
                                                      fontWeight:
                                                          FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    _playingAudioId ==
                                                            (message['cid'] ??
                                                                message[
                                                                    'fileCid'] ??
                                                                message['fileId'])
                                                        ? '${_formatShortDuration(_audioPosition)} / ${_formatShortDuration(_audioDuration.inMilliseconds > 0 ? _audioDuration : Duration(seconds: message['duration'] ?? 0))}'
                                                        : (message['duration'] !=
                                                                null
                                                            ? _formatShortDuration(
                                                                Duration(
                                                                    seconds:
                                                                        message[
                                                                            'duration']))
                                                            : 'Tap to play'),
                                                    style: const TextStyle(
                                                      color: Color(0xFFBDBDBD),
                                                      fontSize: 11,
            ),
          ),
        ],
      ),
                                            ],
                                          ),
                                          Column(
                                            mainAxisSize: MainAxisSize.max,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                timestamp,
                                                style: const TextStyle(
                                                  color: Color(0xFFBDBDBD),
                                                  fontSize: 12,
                                                  letterSpacing: 0.0,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      // Progress bar for playing audio
                                      if (_playingAudioId ==
                                              (message['cid'] ??
                                                  message['fileCid'] ??
                                                  message['fileId']) &&
                                          _audioDuration.inMilliseconds > 0)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 8),
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(2),
                                            child: LinearProgressIndicator(
                                              value: _audioPosition
                                                      .inMilliseconds /
                                                  _audioDuration.inMilliseconds,
                                              backgroundColor:
                                                  const Color(0xFFE0E0E0),
                                              valueColor:
                                                  const AlwaysStoppedAnimation<
                                                      Color>(Color(0xFF0F365F)),
                                              minHeight: 2,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : GestureDetector(
                              onTap: (isFile || isFileFallback)
                                  ? () {
                                      downloadAndOpenFile(
                                        message['cid'] ?? message['fileCid'] ?? message['fileId'] ?? '',
                                        message['fileName'] ?? 'file',
                                      );
                                    }
                                  : null,
                              child: Container(
                                width: 300,
                                constraints:
                                    const BoxConstraints(maxWidth: 260),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: const BorderRadius.only(
                                    bottomLeft: Radius.circular(24),
                                    bottomRight: Radius.circular(24),
                                    topLeft: Radius.circular(3),
                                    topRight: Radius.circular(24),
                                  ),
                                  border: Border.all(
                                      color: const Color(0xFF828282)),
                                ),
                                child: Padding(
                                  padding: const EdgeInsetsDirectional.fromSTEB(
                                      12, 12, 12, 12),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.max,
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: (isFile || isFileFallback)
                                            ? Row(
                                                children: [
                                                  const Icon(Icons.file_present,
                                                      color: Color(0xFF0F365F),
                                                      size: 20),
                    const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                    Text(
                                                          message['fileName'] ??
                                                              'File',
                                                          style:
                                                              const TextStyle(
                                                            color: Color(
                                                                0xFF828282),
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            fontSize: 14,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                        const SizedBox(
                                                            height: 2),
                                                        Text(
                                                          'Tap to open',
                                                          style:
                                                              const TextStyle(
                                                            color: Color(
                                                                0xFFBDBDBD),
                                                            fontSize: 11,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              )
                                            : Text(
                                                message['content'] ?? '',
                      style: const TextStyle(
                                                  color: Color(0xFF828282),
                                                  fontSize: 14,
                                                  letterSpacing: 0.0,
                                                ),
                                              ),
                                      ),
                                      Column(
                                        mainAxisSize: MainAxisSize.max,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            timestamp,
                                            style: const TextStyle(
                                              color: Color(0xFFBDBDBD),
                        fontSize: 12,
                                              letterSpacing: 0.0,
                      ),
                    ),
                  ],
                ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
            ),
          ],
        ),
      );
    }
  }

  String _formatTimestamp(dynamic timestamp) {
    // Handle both DateTime and int (milliseconds since epoch)
    DateTime dateTime;
    if (timestamp is DateTime) {
      dateTime = timestamp;
    } else if (timestamp is int) {
      dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    } else if (timestamp is String) {
      dateTime = DateTime.tryParse(timestamp) ?? DateTime.now();
    } else {
      // Fallback to current time
      dateTime = DateTime.now();
    }
    
    final hour = dateTime.hour;
    final minute = dateTime.minute;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '${displayHour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
  }
}

/// Custom painter for waveform visualization
class WaveformPainter extends CustomPainter {
  final List<double> waveformData;

  WaveformPainter(this.waveformData);

  @override
  void paint(Canvas canvas, Size size) {
    if (waveformData.isEmpty) return;

    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final centerY = size.height / 2;
    final barWidth = size.width / waveformData.length;
    final maxHeight = size.height * 0.8;

    for (int i = 0; i < waveformData.length; i++) {
      final amplitude = waveformData[i];
      final barHeight = amplitude * maxHeight;
      final x = i * barWidth + barWidth / 2;

      // Draw vertical line from center
      canvas.drawLine(
        Offset(x, centerY - barHeight / 2),
        Offset(x, centerY + barHeight / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) {
    return oldDelegate.waveformData != waveformData;
  }
}

/// Channel Information Page
class ChannelInfoPage extends StatefulWidget {
  final String channelName;
  final String workspaceName;
  final String? userAddress;

  const ChannelInfoPage({
    super.key,
    required this.channelName,
    required this.workspaceName,
    this.userAddress,
  });

  @override
  State<ChannelInfoPage> createState() => _ChannelInfoPageState();
}

class _ChannelInfoPageState extends State<ChannelInfoPage> {
  List<Map<String, dynamic>> _members = [];
  String? _inviterAddress;
  bool _isLoading = true;
  String? _workspaceId;
  
  /// Get workspace ID (resolved from workspace name)
  String get _effectiveWorkspaceId {
    return _workspaceId ?? widget.workspaceName;
  }
  
  /// Resolve workspace ID from workspace name
  Future<void> _resolveWorkspaceId() async {
    try {
      if (widget.userAddress == null) return;
      
      print('🔍 [ChannelInfo] Resolving workspace ID for workspace name: ${widget.workspaceName}');
      
      // Try to get workspace ID from SQLite first (works offline)
      final sqliteWorkspaces = await HybridStorageService.instance.getUserWorkspaces(widget.userAddress!);
      final sqliteWorkspace = sqliteWorkspaces.firstWhere(
        (w) => (w['name']?.toString() ?? w['workspaceName']?.toString()) == widget.workspaceName,
        orElse: () => {},
      );
      
      if (sqliteWorkspace.isNotEmpty) {
        _workspaceId = sqliteWorkspace['workspace_id']?.toString() ?? 
                      sqliteWorkspace['workspaceId']?.toString() ??
                      widget.workspaceName;
        print('✅ [ChannelInfo] Resolved workspace ID from SQLite: $_workspaceId');
        return;
      }
      
      // If not in SQLite, try server (if online)
      try {
        final serverWorkspaces = await DistributedService.getUserWorkspaces(widget.userAddress!);
        final serverWorkspace = serverWorkspaces.firstWhere(
          (w) => (w['name']?.toString() ?? w['workspaceName']?.toString()) == widget.workspaceName,
          orElse: () => {},
        );
        
        if (serverWorkspace.isNotEmpty) {
          _workspaceId = serverWorkspace['workspace_id']?.toString() ?? 
                        serverWorkspace['workspaceId']?.toString() ??
                        widget.workspaceName;
          print('✅ [ChannelInfo] Resolved workspace ID from server: $_workspaceId');
          return;
        }
      } catch (e) {
        print('⚠️ [ChannelInfo] Could not resolve workspace ID from server: $e');
      }
      
      // Fallback to workspace name
      _workspaceId = widget.workspaceName;
      print('⚠️ [ChannelInfo] Using workspace name as ID (fallback): $_workspaceId');
    } catch (e) {
      print('❌ [ChannelInfo] Error resolving workspace ID: $e');
      _workspaceId = widget.workspaceName; // Fallback
    }
  }
  bool _showAllMembers = false;
  
  // Media, Documents, Links
  List<Map<String, dynamic>> _mediaItems = [];
  List<Map<String, dynamic>> _documentItems = [];
  List<Map<String, dynamic>> _linkItems = [];
  String _activeTab = 'media'; // 'media', 'docx', 'link'
  
  // Channel Settings
  bool _isAdmin = false;
  String _currentChannelName = '';
  bool _notificationsEnabled = true;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    _currentChannelName = widget.channelName;
    _resolveWorkspaceId(); // Resolve workspace ID first
    _loadChannelInfo();
  }

  Future<void> _loadChannelInfo() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Ensure workspace ID is resolved
      if (_workspaceId == null) {
        await _resolveWorkspaceId();
      }
      
      // Load inviter address
      // Load members from MongoDB
      // Use HybridStorageService (works offline) with resolved workspace ID
      print('👥 [ChannelInfo] Loading workspace members for workspace ID: $_effectiveWorkspaceId (name: ${widget.workspaceName})');
      final members = await HybridStorageService.instance.getWorkspaceMembers(_effectiveWorkspaceId);
      
      if (true) { // Flatten logic structure to minimize diff churn
         _inviterAddress = null; // Not strictly needed for basic member list

        // Ensure current user is in the list
        if (widget.userAddress != null) {
          final userKey = widget.userAddress!.toLowerCase().trim();
          final userExists = members.any((m) =>
              m['memberAddress']?.toString().toLowerCase() == userKey);

          if (!userExists) {
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

        // Fetch profile names for all members
        final updatedMembers = <Map<String, dynamic>>[];
        for (var member in members) {
          final memberCopy = Map<String, dynamic>.from(member);
          final memberAddr = memberCopy['memberAddress']?.toString();
          if (memberAddr != null) {
            final profileName = await _getProfileNameForAddress(memberAddr);
            if (profileName != null && profileName.isNotEmpty) {
              memberCopy['memberDisplayName'] = profileName;
            }
          }
          updatedMembers.add(memberCopy);
        }

        // Load channel messages to filter media, documents, and links
        await _loadChannelContent();
        
        // Check if current user is admin/inviter
        if (widget.userAddress != null) {
          final userKey = widget.userAddress!.toLowerCase().trim();
          _isAdmin = _inviterAddress != null && 
                     _inviterAddress!.toLowerCase().trim() == userKey;
        }

        setState(() {
          _members = updatedMembers;
          _isLoading = false;
        });
        
        // Load notification and mute preferences
        await _loadPreferences();
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading channel info: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadChannelContent() async {
    try {
      // Ensure workspace ID is resolved
      if (_workspaceId == null) {
        await _resolveWorkspaceId();
      }
      final workspaceId = _workspaceId ?? widget.workspaceName;
      
      final messages = await DistributedService.getChannelMessages(
          workspaceId: workspaceId, channelId: widget.channelName);

      // Parse timestamps
      for (var msg in messages) {
        if (msg['timestamp'] is String) {
          msg['timestamp'] =
              DateTime.tryParse(msg['timestamp']) ?? DateTime.now();
        } else if (msg['timestamp'] is int) {
          msg['timestamp'] =
              DateTime.fromMillisecondsSinceEpoch(msg['timestamp']);
        }
      }

      // Filter messages by type
      _mediaItems = messages.where((msg) {
        final type = msg['type']?.toString() ?? '';
        final fileName = msg['fileName']?.toString().toLowerCase() ?? '';
        return type == 'image' || 
               type == 'video' ||
               fileName.endsWith('.jpg') ||
               fileName.endsWith('.jpeg') ||
               fileName.endsWith('.png') ||
               fileName.endsWith('.gif') ||
               fileName.endsWith('.webp') ||
               fileName.endsWith('.mp4') ||
               fileName.endsWith('.mov') ||
               fileName.endsWith('.avi') ||
               fileName.endsWith('.mkv');
      }).toList();

      _documentItems = messages.where((msg) {
        final type = msg['type']?.toString() ?? '';
        final fileName = msg['fileName']?.toString().toLowerCase() ?? '';
        return type == 'file' ||
               (!['image', 'video', 'audio'].contains(type) && 
                msg['cid'] != null &&
                !fileName.endsWith('.jpg') &&
                !fileName.endsWith('.jpeg') &&
                !fileName.endsWith('.png') &&
                !fileName.endsWith('.gif') &&
                !fileName.endsWith('.webp') &&
                !fileName.endsWith('.mp4') &&
                !fileName.endsWith('.mov') &&
                !fileName.endsWith('.avi') &&
                !fileName.endsWith('.mkv') &&
                !fileName.endsWith('.m4a') &&
                !fileName.endsWith('.mp3'));
      }).toList();

      _linkItems = messages.where((msg) {
        final content = msg['content']?.toString() ?? '';
        return content.startsWith('http://') || 
               content.startsWith('https://') ||
               content.startsWith('www.');
      }).toList();

      print('📊 Loaded content: ${_mediaItems.length} media, ${_documentItems.length} docs, ${_linkItems.length} links');
    } catch (e) {
      print('❌ Error loading channel content: $e');
    }
  }

  Future<String?> _getUserNameFromOrbitDB() async {
    try {
      if (widget.userAddress == null) return null;
      final profile = await DistributedService.getUserProfile(widget.userAddress!);
      return profile?['username'];
    } catch (e) {
      return null;
    }
  }

  Future<String?> _getProfileNameForAddress(String address) async {
    try {
      final profile = await DistributedService.getUserProfile(address);
      return profile?['username'];
    } catch (e) {
      debugPrint('Error getting profile name: $e');
      return null;
    }
  }

  /// Show edit channel name dialog
  Future<void> _showEditChannelNameDialog() async {
    final TextEditingController nameController = TextEditingController(
      text: _currentChannelName,
    );
    
    try {
      final result = await showDialog<Map<String, dynamic>?>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Edit Channel Name',
            style: TextStyle(
              color: Color(0xFF333333),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter new channel name:',
                style: TextStyle(
                  color: Color(0xFF666666),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                autofocus: true,
                maxLength: 80,
                decoration: InputDecoration(
                  hintText: 'Channel name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF0F365F), width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF333333),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(null);
              },
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Color(0xFF666666),
                  fontSize: 16,
                ),
              ),
            ),
            FilledButton(
              onPressed: () {
                final newName = nameController.text.trim();
                if (newName.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Channel name cannot be empty'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 2),
                    ),
                  );
                  return;
                }
                if (newName == _currentChannelName) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a different channel name'),
                      backgroundColor: Colors.orange,
                      duration: Duration(seconds: 2),
                    ),
                  );
                  return;
                }
                Navigator.of(context).pop({'newName': newName});
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F365F),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Save',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
      
      // Only update if result is not null and contains newName
      if (result != null && result['newName'] != null) {
        await _updateChannelName(result['newName']);
      }
    } finally {
      // Dispose controller after dialog is closed
      nameController.dispose();
    }
  }
  
  /// Update channel name - Simple approach: Update channel message in workspace DB
  /// This is cleaner than rename chains - just update the channel name directly
  Future<void> _updateChannelName(String newName) async {
    try {
      setState(() {
        _isLoading = true;
      });
      
      // Get inviter address if not already loaded
      if (_inviterAddress == null) {
        // Stub: Inviter address not strictly needed for basic rename in MongoDB
        _inviterAddress = null;
      }
      
      if (_inviterAddress == null) {
        throw Exception('Could not find workspace inviter address');
      }
      
      // Use the original channel name from widget (this is the database name)
      // widget.channelName is always the original name used for database operations
      final originalDbName = widget.channelName;
      final oldDisplayName = _currentChannelName;
      
      print('🔄 [UpdateChannel] Renaming channel: "$originalDbName" (display: "$oldDisplayName") -> "$newName"');
      
      // 1. Store simple mapping in SharedPreferences (original DB name -> new display name)
      // IMPORTANT: Update SharedPreferences FIRST so UI can immediately reflect the change
      final prefs = await SharedPreferences.getInstance();
      final mappingKey = 'channel_name_mapping_${widget.workspaceName}_$originalDbName';
      await prefs.setString(mappingKey, newName);
      
      // Store reverse mapping (new name -> original DB name) for database lookup
      final reverseMappingKey = 'channel_old_name_${widget.workspaceName}_$newName';
      await prefs.setString(reverseMappingKey, originalDbName);
      
      // Remove old reverse mapping if channel was previously renamed
      if (oldDisplayName != originalDbName && oldDisplayName != newName) {
        final oldReverseKey = 'channel_old_name_${widget.workspaceName}_$oldDisplayName';
        await prefs.remove(oldReverseKey);
        print('🗑️ [UpdateChannel] Removed old reverse mapping for: "$oldDisplayName"');
      }
      
      // Update UI state immediately after SharedPreferences is updated
      // This ensures UI reflects the change even before OrbitDB sync completes
      setState(() {
        _currentChannelName = newName;
      });
      print('🔄 [UpdateChannel] UI state updated immediately: "$oldDisplayName" -> "$newName"');
      
      // 2. Update channel message in workspace database
      // Since OrbitDB is append-only, we add a new channel message with updated name
      // The latest channel message with this workspaceName will be used
        // Add updated channel message to MongoDB (as a system message or metadata)
        // Use HybridStorageService (works offline)
        final channelUpdateSuccess = await HybridStorageService.instance.addMessage(
          workspaceId: _effectiveWorkspaceId,
          channelId: 'general', // Use general channel for workspace updates
          senderAddress: widget.userAddress ?? '',
          messageText: 'Channel renamed: $originalDbName -> $newName',
          // metadata: updatedChannelMessage, // TODO: Add metadata support
        ) != null;
        
        if (channelUpdateSuccess == null) {
          print('⚠️ Warning: Could not update channel message in workspace database');
        } else {
          print('✅ Channel message updated in workspace database: "$originalDbName" -> "$newName"');
        }
        
        // Also store rename action for tracking (optional, for history)
        final renameMessage = {
          'type': 'channel_rename',
          'workspaceName': widget.workspaceName,
          'oldChannelName': originalDbName,
          'newChannelName': newName,
          'renamedBy': widget.userAddress?.toLowerCase().trim() ?? '',
          'inviterAddress': _inviterAddress,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };
        
        // Stub: Detailed rename tracking in MongoDB
        // await MongoDBService.addMessage(...); // Implement if needed
        print('⚠️ MongoDB: Rename tracking stub called');
      
      // 3. Store channel metadata in channel's message database (using original DB name)
      final channelMetadata = {
        'type': 'channel_metadata',
        'action': 'rename',
        'oldName': originalDbName,
        'newName': newName,
        'workspace': widget.workspaceName,
        'channel': originalDbName, // Always use original DB name for database lookup
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'userAddress': widget.userAddress ?? '',
      };
      
      // Add metadata message to channel (using original DB name for database)
      // Add metadata message to channel
      // Use HybridStorageService (works offline)
      final channelMetadataSuccess = await HybridStorageService.instance.addMessage(
        workspaceId: _effectiveWorkspaceId,
        channelId: originalDbName,
        senderAddress: widget.userAddress ?? '',
        messageText: 'Channel renamed to $newName',
        // metadata: channelMetadata, // TODO: Add metadata support to addMessage
      ) != null;
      
      if (channelMetadataSuccess) {
        // State is already updated above, just set loading to false
        setState(() {
          _isLoading = false;
        });
        
        // Reload preferences with new channel name
        await _loadPreferences();
        
        print('✅ [UpdateChannel] Channel name updated successfully: "$originalDbName" -> "$newName"');
        print('🔄 [NavigateToInfo] Channel name updated to: "$newName"');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Channel renamed to "# $newName"'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
          
          // Pop back to channel page with updated name
          // Note: widget.channelName remains the original DB name, but _currentChannelName is updated
          Navigator.pop(context, {'channelName': newName});
        }
      } else {
        setState(() {
          _isLoading = false;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to update channel name'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Error updating channel name: $e');
      setState(() {
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  /// Toggle notifications
  void _toggleNotifications() {
    setState(() {
      _notificationsEnabled = !_notificationsEnabled;
      if (_notificationsEnabled) {
        _muted = false; // Unmute if enabling notifications
      }
    });
    
    // Save notification preference (can be stored in SharedPreferences)
    _saveNotificationPreference();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _notificationsEnabled
              ? 'Notifications enabled for this channel'
              : 'Notifications disabled for this channel',
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }
  
  /// Toggle mute
  void _toggleMute() {
    setState(() {
      _muted = !_muted;
      if (_muted) {
        _notificationsEnabled = false; // Disable notifications if muting
      }
    });
    
    // Save mute preference
    _saveMutePreference();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _muted
              ? 'Channel muted'
              : 'Channel unmuted',
        ),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 2),
      ),
    );
  }
  
  /// Save notification preference
  Future<void> _saveNotificationPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'channel_notifications_${widget.workspaceName}_${_currentChannelName}';
      await prefs.setBool(key, _notificationsEnabled);
    } catch (e) {
      print('❌ Error saving notification preference: $e');
    }
  }
  
  /// Save mute preference
  Future<void> _saveMutePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'channel_muted_${widget.workspaceName}_${_currentChannelName}';
      await prefs.setBool(key, _muted);
    } catch (e) {
      print('❌ Error saving mute preference: $e');
    }
  }
  
  /// Load notification and mute preferences
  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notificationsKey = 'channel_notifications_${widget.workspaceName}_${_currentChannelName}';
      final muteKey = 'channel_muted_${widget.workspaceName}_${_currentChannelName}';
      
      setState(() {
        _notificationsEnabled = prefs.getBool(notificationsKey) ?? true;
        _muted = prefs.getBool(muteKey) ?? false;
      });
    } catch (e) {
      print('❌ Error loading preferences: $e');
    }
  }
  
  /// Show delete channel confirmation dialog
  Future<void> _showDeleteChannelDialog() async {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only workspace admins can delete channels'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning, color: Colors.red, size: 24),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Delete Channel',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete "# $_currentChannelName"?',
              style: const TextStyle(
                color: Color(0xFF333333),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'This action cannot be undone. All messages, media, and data in this channel will be permanently deleted.',
              style: TextStyle(
                color: Color(0xFF666666),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Type the channel name to confirm: $_currentChannelName',
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: Color(0xFF666666),
                fontSize: 16,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Delete Channel',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    
    if (result == true) {
      await _deleteChannel();
    }
  }
  
  /// Delete channel - Remove from database and clean up all related data
  Future<void> _deleteChannel() async {
    try {
      setState(() {
        _isLoading = true;
      });
      
      // Get inviter address if not already loaded
      if (_inviterAddress == null) {
        // Stub: Inviter not needed for MongoDB ops usually, or fetch from workspace metadata
        _inviterAddress = null;
      }
      
      if (_inviterAddress == null) {
        throw Exception('Could not find workspace inviter address');
      }
      
      // Use the original channel name from widget (this is the database name)
      final originalDbName = widget.channelName;
      final displayName = _currentChannelName;
      
      print('🗑️ [DeleteChannel] Deleting channel: "$originalDbName" (display: "$displayName")');
      
      // 1. Add channel_delete message to workspace
      // Use HybridStorageService (works offline)
      final deleteSuccess = await HybridStorageService.instance.addMessage(
          workspaceId: _effectiveWorkspaceId,
          channelId: 'general', // Use general channel or system channel for workspace-level events
          senderAddress: widget.userAddress ?? '',
          messageText: 'Channel deleted: $displayName (ID: $originalDbName)',
      ) != null;
      
      if (!deleteSuccess) {
        print('⚠️ Warning: Could not add delete message to workspace database');
      } else {
        print('✅ Delete message added to workspace database');
      }
      
      // 2. Clean up SharedPreferences mappings
      final prefs = await SharedPreferences.getInstance();
      
      // Remove forward mapping (original -> display)
      final mappingKey = 'channel_name_mapping_${widget.workspaceName}_$originalDbName';
      await prefs.remove(mappingKey);
      print('🗑️ [DeleteChannel] Removed forward mapping: $mappingKey');
      
      // Remove reverse mapping (display -> original)
      final reverseMappingKey = 'channel_old_name_${widget.workspaceName}_$displayName';
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
              (mappedValue.toLowerCase() == displayName.toLowerCase() ||
               mappedValue.toLowerCase() == originalDbName.toLowerCase())) {
            await prefs.remove(key);
            print('🗑️ [DeleteChannel] Removed related mapping: $key');
          }
        } else if (key.startsWith(oldNamePrefix)) {
          final mappedValue = prefs.getString(key);
          if (mappedValue != null && 
              (mappedValue.toLowerCase() == originalDbName.toLowerCase() ||
               mappedValue.toLowerCase() == displayName.toLowerCase())) {
            await prefs.remove(key);
            print('🗑️ [DeleteChannel] Removed related reverse mapping: $key');
          }
        }
      }
      
      // 3. Remove notification and mute preferences
      final notificationsKey = 'channel_notifications_${widget.workspaceName}_${_currentChannelName}';
      final muteKey = 'channel_muted_${widget.workspaceName}_${_currentChannelName}';
      await prefs.remove(notificationsKey);
      await prefs.remove(muteKey);
      print('🗑️ [DeleteChannel] Removed notification preferences');
      
      // 4. Add delete metadata to channel's message database (for tracking)
      final channelMetadata = {
        'type': 'channel_metadata',
        'action': 'delete',
        'channelName': originalDbName,
        'deletedChannelName': displayName,
        'workspace': widget.workspaceName,
        'channel': originalDbName,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'userAddress': widget.userAddress ?? '',
      };
      
      // Add metadata message to channel (using original DB name)
      // Add metadata message to channel (using original DB name)
      // Use HybridStorageService (works offline)
      await HybridStorageService.instance.addMessage(
        workspaceId: _effectiveWorkspaceId,
        channelId: originalDbName,
        senderAddress: widget.userAddress ?? '',
        messageText: 'Channel deleted: $displayName',
      );
      
      setState(() {
        _isLoading = false;
      });
      
      print('✅ [DeleteChannel] Channel deleted successfully: "$originalDbName"');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Channel "# $displayName" has been deleted'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        
        // Navigate back with deletion flag
        Navigator.pop(context, {'deleted': true, 'channelName': originalDbName});
      }
    } catch (e) {
      debugPrint('❌ Error deleting channel: $e');
      setState(() {
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting channel: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
          'Channel Information',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0F365F)),
              ),
            )
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Channel Header Section
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
                        // Channel Icon
                        Container(
                          width: 80,
                          height: 80,
                    decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.2),
                          ),
                          child: const Center(
                            child: Text(
                              '#',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Channel Name (use _currentChannelName which updates)
                        Text(
                          '# $_currentChannelName',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Workspace Name
                        Text(
                          widget.workspaceName,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Channel Settings Section (if admin)
                  if (_isAdmin) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.settings,
                            color: Color(0xFF0F365F),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Channel Settings',
                            style: TextStyle(
                              color: Color(0xFF333333),
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Edit Channel Name
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: InkWell(
                        onTap: () => _showEditChannelNameDialog(),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE0E0E0)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F365F).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.edit,
                                  color: Color(0xFF0F365F),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Edit Channel Name',
                                      style: TextStyle(
                                        color: Color(0xFF333333),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Current: # $_currentChannelName',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: Color(0xFF0F365F),
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Delete Channel (Danger Zone)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: InkWell(
                        onTap: () => _showDeleteChannelDialog(),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.delete_forever,
                                  color: Colors.red,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Delete Channel',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Permanently delete this channel and all its messages',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: Colors.red,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // Notification Settings
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: InkWell(
                      onTap: () => _toggleNotifications(),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE0E0E0)),
                    ),
                    child: Row(
                      children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _notificationsEnabled
                                    ? const Color(0xFF0F365F).withOpacity(0.1)
                                    : Colors.grey.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                _notificationsEnabled
                                    ? Icons.notifications_active
                                    : Icons.notifications_off,
                                color: _notificationsEnabled
                                    ? const Color(0xFF0F365F)
                                    : Colors.grey,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                    _notificationsEnabled
                                        ? 'Notifications Enabled'
                                        : 'Notifications Disabled',
                                style: const TextStyle(
                                      color: Color(0xFF333333),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _notificationsEnabled
                                        ? 'You\'ll receive notifications for new messages'
                                        : 'You won\'t receive notifications',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _notificationsEnabled,
                              onChanged: (value) => _toggleNotifications(),
                              activeColor: const Color(0xFF0F365F),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Mute Channel
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: InkWell(
                      onTap: () => _toggleMute(),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                                  color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE0E0E0)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _muted
                                    ? Colors.orange.withOpacity(0.1)
                                    : Colors.grey.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                _muted ? Icons.volume_off : Icons.volume_up,
                                color: _muted ? Colors.orange : Colors.grey,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(
                                    _muted ? 'Channel Muted' : 'Mute Channel',
                                style: const TextStyle(
                                      color: Color(0xFF333333),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _muted
                                        ? 'This channel is muted'
                                        : 'Mute this channel to stop notifications',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                            Switch(
                              value: _muted,
                              onChanged: (value) => _toggleMute(),
                              activeColor: Colors.orange,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Members Section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.people,
                          color: Color(0xFF0F365F),
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Members (${_members.length})',
                          style: const TextStyle(
                            color: Color(0xFF333333),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Members List (Max 4, with See All)
                  if (_members.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: Text(
                          'No members found',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ),
                    )
                  else
                    Column(
                      children: [
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: _showAllMembers ? _members.length : (_members.length > 4 ? 4 : _members.length),
                          itemBuilder: (context, index) {
                            final member = _members[index];
                            return _buildMemberTile(member);
                          },
                        ),
                        if (_members.length > 4 && !_showAllMembers)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            child: TextButton(
                          onPressed: () {
                                setState(() {
                                  _showAllMembers = true;
                                });
                              },
                              child: Text(
                                'See all (${_members.length})',
                                style: const TextStyle(
                                  color: Color(0xFF0F365F),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 24),
                  // Blue Divider (Solid Blue)
                  Container(
                    height: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    color: const Color(0xFF0F365F),
                  ),
                  const SizedBox(height: 24),
                  // Main Heading: Media, Docx and Links with Total Count
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Media, Docx and Links (${_mediaItems.length + _documentItems.length + _linkItems.length})',
                      style: const TextStyle(
                        color: Color(0xFF333333),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Media/Docx/Link Tabs with Counts
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildTabButton(
                            'Media (${_mediaItems.length})',
                            _activeTab == 'media',
                            onTap: () => setState(() => _activeTab = 'media'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTabButton(
                            'Docx (${_documentItems.length})',
                            _activeTab == 'docx',
                            onTap: () => setState(() => _activeTab = 'docx'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTabButton(
                            'Link (${_linkItems.length})',
                            _activeTab == 'link',
                            onTap: () => setState(() => _activeTab = 'link'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Content based on active tab
                  if (_activeTab == 'media')
                    _buildMediaGrid()
                  else if (_activeTab == 'docx')
                    _buildDocumentsList()
                  else if (_activeTab == 'link')
                    _buildLinksList(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildTabButton(String label, bool isActive, {required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        decoration: BoxDecoration(
          color: isActive 
              ? const Color(0xFF0F365F).withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive 
                ? const Color(0xFF0F365F)
                : Colors.grey[300]!,
            width: isActive ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isActive 
                  ? const Color(0xFF0F365F)
                  : Colors.grey[700],
              fontSize: 14,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMediaGrid() {
    if (_mediaItems.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.photo_library_outlined,
                size: 48,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 12),
              Text(
                'No media files',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1,
        ),
        itemCount: _mediaItems.length,
        itemBuilder: (context, index) {
          final item = _mediaItems[index];
          return _buildMediaItem(item);
        },
      ),
    );
  }

  Widget _buildMediaItem(Map<String, dynamic> item) {
    final cid = item['cid'] ?? item['fileCid'];
    final fileName = item['fileName']?.toString() ?? 'media';
    final isVideo = item['type'] == 'video' ||
        fileName.toLowerCase().endsWith('.mp4') ||
        fileName.toLowerCase().endsWith('.mov') ||
        fileName.toLowerCase().endsWith('.avi') ||
        fileName.toLowerCase().endsWith('.mkv');

    return GestureDetector(
      onTap: () {
        if (isVideo) {
          _downloadAndOpenFile(cid, fileName);
        } else {
          _showFullScreenImage(cid, fileName);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (cid != null)
              FutureBuilder<Uint8List?>(
                future: Future.value(null), // OrbitDBService.downloadFile(cid) stubbed
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0F365F)),
                      ),
                    );
                  }
                  if (snapshot.hasData && snapshot.data != null) {
                    if (isVideo) {
                      return Container(
                        color: Colors.black,
                        child: const Center(
                          child: Icon(
                            Icons.play_circle_filled,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      );
                    } else {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          snapshot.data!,
                          fit: BoxFit.cover,
                        ),
                      );
                    }
                  }
                  return Container(
                    color: Colors.grey[200],
                    child: const Center(
                      child: Icon(
                        Icons.broken_image,
                        color: Colors.grey,
                        size: 24,
                      ),
                    ),
                  );
                },
                  )
                else
                  Container(
                color: Colors.grey[200],
                child: const Center(
                  child: Icon(
                    Icons.image,
                    color: Colors.grey,
                    size: 24,
                  ),
                ),
              ),
            if (isVideo)
              Positioned(
                bottom: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentsList() {
    if (_documentItems.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.description_outlined,
                size: 48,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 12),
              Text(
                'No documents',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _documentItems.length,
        itemBuilder: (context, index) {
          final item = _documentItems[index];
          return _buildDocumentItem(item);
        },
      ),
    );
  }

  Widget _buildDocumentItem(Map<String, dynamic> item) {
    final fileName = item['fileName']?.toString() ?? 'Document';
    final fileSize = item['fileSize'];
    final cid = item['cid'] ?? item['fileCid'];
    final timestamp = item['timestamp'];
    
    String fileSizeStr = '';
    if (fileSize != null) {
      if (fileSize is int) {
        final sizeInMB = fileSize / (1024 * 1024);
        if (sizeInMB >= 1) {
          fileSizeStr = '${sizeInMB.toStringAsFixed(2)} MB';
        } else {
          fileSizeStr = '${(fileSize / 1024).toStringAsFixed(2)} KB';
        }
      }
    }

    String timeStr = '';
    if (timestamp != null) {
      DateTime dateTime;
      if (timestamp is DateTime) {
        dateTime = timestamp;
      } else if (timestamp is int) {
        dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      } else if (timestamp is String) {
        dateTime = DateTime.tryParse(timestamp) ?? DateTime.now();
      } else {
        dateTime = DateTime.now();
      }
      timeStr = '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }

    return InkWell(
      onTap: () {
        if (cid != null) {
          _downloadAndOpenFile(cid, fileName);
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
          color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F365F).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.description,
                color: Color(0xFF0F365F),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: const TextStyle(
                      color: Color(0xFF333333),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (fileSizeStr.isNotEmpty) ...[
                        Text(
                          fileSizeStr,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                        if (timeStr.isNotEmpty) ...[
                          Text(
                            ' • ',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                      if (timeStr.isNotEmpty)
                        Text(
                          timeStr,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.download,
              color: Color(0xFF0F365F),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinksList() {
    if (_linkItems.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.link_outlined,
                size: 48,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 12),
              Text(
                'No links',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _linkItems.length,
        itemBuilder: (context, index) {
          final item = _linkItems[index];
          return _buildLinkItem(item);
        },
      ),
    );
  }

  Widget _buildLinkItem(Map<String, dynamic> item) {
    final content = item['content']?.toString() ?? '';
    final timestamp = item['timestamp'];
    
    String timeStr = '';
    if (timestamp != null) {
      DateTime dateTime;
      if (timestamp is DateTime) {
        dateTime = timestamp;
      } else if (timestamp is int) {
        dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      } else if (timestamp is String) {
        dateTime = DateTime.tryParse(timestamp) ?? DateTime.now();
      } else {
        dateTime = DateTime.now();
      }
      timeStr = '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }

    // Extract URL from content
    String url = content;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      if (url.startsWith('www.')) {
        url = 'https://$url';
      } else {
        url = 'https://$url';
      }
    }

    return InkWell(
      onTap: () {
        // Open URL in browser
        print('Opening URL: $url');
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F365F).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.link,
                color: Color(0xFF0F365F),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    content,
                    style: const TextStyle(
                      color: Color(0xFF0F365F),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.underline,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (timeStr.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      timeStr,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.open_in_new,
              color: Color(0xFF0F365F),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showFullScreenImage(String cid, String fileName) async {
    try {
      // Stub: Download
      print('⚠️ MongoDB: Download stub called for: $cid');
      final Uint8List? imageBytes = null;
      if (imageBytes != null && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => _FullScreenImageViewer(
              imageBytes: imageBytes,
              fileName: fileName,
            ),
            fullscreenDialog: true,
          ),
        );
      }
    } catch (e) {
      print('❌ Error showing full screen image: $e');
    }
  }

  Future<void> _downloadAndOpenFile(String cid, String fileName) async {
    try {
      // Stub: Download
      print('⚠️ MongoDB: Download stub called for: $cid');
      final Uint8List? fileBytes = null;
      if (fileBytes != null) {
        final dir = await getTemporaryDirectory();
        final filePath = '${dir.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(fileBytes);
        await OpenFile.open(filePath);
      }
    } catch (e) {
      print('❌ Error downloading/opening file: $e');
    }
  }

  Widget _buildMemberTile(Map<String, dynamic> member) {
    final memberAddress = member['memberAddress']?.toString() ?? '';
    final isInviter = member['isInviter'] == true;
    final isCurrentUser = widget.userAddress != null &&
        memberAddress.toLowerCase() == widget.userAddress!.toLowerCase();

    String displayName =
        (member['memberDisplayName']?.toString() ?? '').trim();
    final hasProfileName = displayName.isNotEmpty;
    if (!hasProfileName) {
      displayName = memberAddress.length > 10
          ? '${memberAddress.substring(0, 6)}...${memberAddress.substring(memberAddress.length - 4)}'
          : memberAddress;
    }

    if (isCurrentUser && !displayName.contains('(you)')) {
      displayName = '$displayName (you)';
    }

    String nameForInitial = displayName.replaceAll('(you)', '').trim();
    final initial = nameForInitial.isNotEmpty
        ? nameForInitial[0].toUpperCase()
        : 'M';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: isInviter
                ? const Color(0xFF23C16B)
                : const Color(0xFF0F365F),
            radius: 24,
                    child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        displayName,
                        style: const TextStyle(
                          color: Color(0xFF333333),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isInviter)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF23C16B).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                        child: const Text(
                          'Admin',
                          style: TextStyle(
                            color: Color(0xFF23C16B),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                if (!hasProfileName)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      memberAddress.length > 20
                          ? '${memberAddress.substring(0, 10)}...${memberAddress.substring(memberAddress.length - 8)}'
                          : memberAddress,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  }


/// Full Screen Image Viewer Widget
class _FullScreenImageViewer extends StatelessWidget {
  final Uint8List imageBytes;
  final String fileName;

  const _FullScreenImageViewer({
    required this.imageBytes,
    required this.fileName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          fileName,
          style: const TextStyle(color: Colors.white),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download, color: Colors.white),
            onPressed: () async {
              try {
                final dir = await getTemporaryDirectory();
                final filePath = '${dir.path}/$fileName';
                final file = File(filePath);
                await file.writeAsBytes(imageBytes);
                await OpenFile.open(filePath);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Image saved to downloads'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error saving image: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
  }
              }
            },
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.memory(
            imageBytes,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
