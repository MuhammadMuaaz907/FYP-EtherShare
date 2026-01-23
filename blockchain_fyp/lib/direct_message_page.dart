import 'package:blockchain_fyp/workspace_home_page.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';

class DirectMessagePage extends StatefulWidget {
  final String memberAddress;
  final String memberDisplayName;
  final String workspaceName;
  
  const DirectMessagePage({
    super.key,
    required this.memberAddress,
    required this.memberDisplayName,
    required this.workspaceName,
  });

  @override
  _DirectMessagePageState createState() => _DirectMessagePageState();
}

class _DirectMessagePageState extends State<DirectMessagePage> {
  // Removed GetIt services
  // final IPFSService ipfsService = GetIt.I<IPFSService>();
  // final OrbitDBService orbitDBService = GetIt.I<OrbitDBService>();
  String status = '';
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  String currentUserName = 'User';
  String? userAddress;
  bool _hasText = false;
  late VoidCallback _textListener;

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

  // Real-time message updates (like channels)
  Timer? _messagePollingTimer;
  bool _isCheckingMessages = false;
  bool _isLoadingMessages = false;
  
  // Workspace ID (resolved from workspace name) - like channels
  String? _workspaceId;
  
  /// Get workspace ID (resolved from workspace name)
  String get _effectiveWorkspaceId {
    return _workspaceId ?? widget.workspaceName;
  }

  @override
  void initState() {
    super.initState();
    _resolveWorkspaceId(); // Resolve workspace ID first (like channels)
    _loadUserNameAndMessages();
    _textListener = () {
      setState(() {
        _hasText = _messageController.text.trim().isNotEmpty;
      });
    };
    _messageController.addListener(_textListener);
    
    // Set up real-time message updates (like channels)
    _setupRealTimeUpdates();
  }

  @override
  void dispose() {
    // Cancel real-time update timer
    _messagePollingTimer?.cancel();
    _messagePollingTimer = null;
    
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
    super.dispose();
  }

  Future<Uint8List?> _getCachedFile(String cid) async {
    if (_fileCache.containsKey(cid)) {
      return _fileCache[cid];
    }
    // Stub: File download not yet implemented in MongoDB/GridFS
    print('⚠️ MongoDB: File download stub called for CID: $cid');
    return null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_messages.isEmpty) {
      _loadMessages();
    } else {
      _checkForNewMessages();
    }
  }

  /// Set up real-time message updates (polling + P2P callbacks) - like channels
  void _setupRealTimeUpdates() {
    // Set up P2P callback for real-time messages
    P2PService.instance.onMessageReceived = (message) {
      // Check if message is for current DM conversation
      final messageType = message['type']?.toString() ?? '';
      
      // Only handle direct messages (not channel messages)
      if (messageType == 'message') {
        // Ensure user address is loaded
        if (userAddress == null) {
          _loadUserAddress().then((_) {
            _handleP2PMessage(message);
          });
        } else {
          _handleP2PMessage(message);
        }
      }
    };
    
    // Start periodic polling for new messages (every 2 seconds) - like channels
    _messagePollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted && !_isCheckingMessages && !_isLoadingMessages) {
        _checkForNewMessages();
      }
    });
    
    print('✅ Real-time DM message updates enabled (polling every 2s + P2P callbacks)');
  }
  
  /// Resolve workspace ID from workspace name (like channels)
  Future<void> _resolveWorkspaceId() async {
    try {
      if (userAddress == null) {
        await _loadUserAddress();
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
  
  /// Get consistent message ID from message map (like channels)
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
  
  /// Handle P2P message received callback - filters for current DM conversation
  void _handleP2PMessage(Map<String, dynamic> message) {
    if (userAddress == null) return;
    
    final senderAddress = message['sender_address']?.toString().toLowerCase().trim() ?? '';
    final receiverAddress = message['receiver_address']?.toString().toLowerCase().trim() ?? '';
    final messageWorkspaceId = message['workspace_id']?.toString() ?? '';
    final currentUserAddress = userAddress!.toLowerCase().trim();
    final memberAddress = widget.memberAddress.toLowerCase().trim();
    final currentWorkspaceName = widget.workspaceName;
    
    // Check if message is for this DM conversation
    // Message should be between current user and member
    final isForThisDM = (senderAddress == currentUserAddress && receiverAddress == memberAddress) ||
                        (senderAddress == memberAddress && receiverAddress == currentUserAddress);
    
    // Also check workspace (security: only show messages from current workspace)
    final workspaceMatches = messageWorkspaceId.isEmpty || 
                             messageWorkspaceId == currentWorkspaceName ||
                             currentWorkspaceName == messageWorkspaceId;
    
    if (isForThisDM && workspaceMatches) {
      print('📨 Real-time P2P DM message received for current conversation');
      print('   From: $senderAddress, To: $receiverAddress');
      print('   Workspace: $messageWorkspaceId, Current: $currentWorkspaceName');
      print('   Message ID: ${message['message_id']}');
      
      // Force immediate check for new messages (don't wait for polling)
      if (mounted && !_isCheckingMessages && !_isLoadingMessages) {
        _checkForNewMessages();
      } else {
        print('⚠️ Cannot check for new messages: mounted=$mounted, checking=$_isCheckingMessages, loading=$_isLoadingMessages');
      }
    } else {
      print('⚠️ P2P message not for current DM conversation');
      print('   From: $senderAddress, To: $receiverAddress');
      print('   Current user: $currentUserAddress, Member: $memberAddress');
      print('   Workspace: $messageWorkspaceId, Current: $currentWorkspaceName');
      print('   DM match: $isForThisDM, Workspace match: $workspaceMatches');
    }
  }

  Future<void> _checkForNewMessages() async {
    // Prevent multiple simultaneous checks (like channels)
    if (_isCheckingMessages || !mounted) {
      return;
    }
    
    _isCheckingMessages = true;
    
    try {
      // Ensure workspace ID is resolved
      if (_workspaceId == null) {
        await _resolveWorkspaceId();
      }
      
      if (userAddress == null) {
        await _loadUserAddress();
      }
      if (userAddress == null) {
        _isCheckingMessages = false;
        return;
      }

      // CRITICAL: For polling, only fetch NEW messages (incremental loading) - like channels
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
          print('🔄 Polling: Only fetching DM messages after ${DateTime.fromMillisecondsSinceEpoch(sinceTimestamp)}');
        }
      }

      // Use HybridStorageService (works offline)
      // Note: getDirectMessages doesn't support sinceTimestamp yet, but we'll filter client-side
      List<Map<String, dynamic>> loaded = await HybridStorageService.instance.getDirectMessages(
        user1Address: userAddress!,
        user2Address: widget.memberAddress,
      );

      // Filter by timestamp if sinceTimestamp is set
      if (sinceTimestamp != null) {
        final sinceTime = sinceTimestamp; // Capture for closure
        loaded = loaded.where((msg) {
          final msgTimestamp = msg['timestamp'];
          int msgTime = 0;
          if (msgTimestamp is DateTime) {
            msgTime = msgTimestamp.millisecondsSinceEpoch;
          } else if (msgTimestamp is int) {
            msgTime = msgTimestamp;
          } else if (msgTimestamp is String) {
            final parsed = DateTime.tryParse(msgTimestamp);
            if (parsed != null) {
              msgTime = parsed.millisecondsSinceEpoch;
            }
          }
          return msgTime > sinceTime;
        }).toList();
      }

      // PHASE 4: Filter out SYNCED messages - they should NOT appear in real-time updates
      // SYNCED messages are already in UI from initial load, don't re-add them
      final realTimeMessages = loaded.where((msg) {
        final state = msg['message_state']?.toString();
        // Only show real-time messages: ONLINE_CONFIRMED, OFFLINE_LOCAL, PENDING_SYNC
        // Exclude SYNCED (those are from sync, not real-time)
        return state != 'SYNCED';
      }).toList();
      
      if (realTimeMessages.length < loaded.length) {
        print('🚫 PHASE 4: Filtered out ${loaded.length - realTimeMessages.length} SYNCED messages (not real-time)');
      }

      // Transform timestamps
      for (var msg in realTimeMessages) {
        if (msg['timestamp'] is String) {
          msg['timestamp'] = DateTime.tryParse(msg['timestamp']) ?? DateTime.now();
        } else if (msg['timestamp'] is int) {
          msg['timestamp'] = DateTime.fromMillisecondsSinceEpoch(msg['timestamp']);
        }
      }

      // Use proper deduplication instead of length comparison (like channels)
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
      
      // Get current user address to filter out user's own messages
      final currentUserAddress = userAddress!.toLowerCase();
      
      // Find new REAL-TIME messages (not already in _messages)
      final newMessages = <Map<String, dynamic>>[];
      final now = DateTime.now().millisecondsSinceEpoch;
      final recentThreshold = 30000; // 30 seconds - exclude user's own recent messages
      
      for (final msg in realTimeMessages) {
        final msgId = _getMessageId(msg);
        if (msgId == null) continue;
        
        // Skip if message ID already exists in UI
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
        
        // Exclude user's own messages that were sent very recently (within last 30 seconds)
        // This prevents user's own messages from appearing again via polling
        if (currentUserAddress.isNotEmpty && 
            msgSender == currentUserAddress && 
            msgTimestamp > 0 && 
            (now - msgTimestamp) < recentThreshold) {
          print('🚫 Skipping user\'s own recent message (sent ${(now - msgTimestamp) / 1000}s ago): $msgId');
          continue;
        }
        
        // Check if this message matches a temporary message (same content, sender, timestamp)
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
                setState(() {
                  _messages[i] = {
                    ...msg,
                    'timestamp': msg['timestamp'] is DateTime ? msg['timestamp'] : DateTime.fromMillisecondsSinceEpoch(msgTimestamp),
                  };
                });
                replacedTemp = true;
                print('✅ Replaced temporary message $existingId with real message $msgId');
                break;
              }
            }
          }
        }
        
        if (!replacedTemp) {
          // Transform message format for UI
          final transformedMsg = {
            ...msg,
            'type': msg['type'] ?? 'text',
            'content': msgContent.isNotEmpty ? msgContent : (msg['encrypted_message'] != null ? '[Encrypted]' : ''),
            'timestamp': msg['timestamp'] is DateTime ? msg['timestamp'] : DateTime.fromMillisecondsSinceEpoch(msgTimestamp),
            'userAddress': msgSender,
            'senderAddress': msgSender,
            'senderName': msg['senderName'] ?? currentUserName,
          };
          newMessages.add(transformedMsg);
        }
      }
      
      if (newMessages.isNotEmpty) {
        setState(() {
          _messages.addAll(newMessages);
          // Sort by timestamp
          _messages.sort((a, b) {
            final aTime = a['timestamp'] is DateTime 
                ? (a['timestamp'] as DateTime).millisecondsSinceEpoch 
                : (a['timestamp'] is int ? a['timestamp'] as int : 0);
            final bTime = b['timestamp'] is DateTime 
                ? (b['timestamp'] as DateTime).millisecondsSinceEpoch 
                : (b['timestamp'] is int ? b['timestamp'] as int : 0);
            return aTime.compareTo(bTime);
          });
        });
        print('✅ Real-time update: Added ${newMessages.length} new DM messages to UI');
      }
      
      // CRITICAL: ALWAYS perform final deduplication pass (even if no new messages)
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
      
      // Always update _messages with deduplicated list
      if (deduplicatedMessages.length != _messages.length) {
        print('⚠️ Final deduplication: removed ${_messages.length - deduplicatedMessages.length} duplicates');
        setState(() {
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
        });
      }
    } on ChainBrokenException catch (e) {
      // Chain broken - don't update messages, but don't crash
      print('⚠️ Chain integrity compromised during real-time update - skipping message update');
      print('   Broken at: ${e.brokenAt}');
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
      print('❌ Error loading user address: $e');
    }
  }

  Future<void> _loadUserNameAndMessages() async {
    try {
      await _loadUserAddress();
      currentUserName = await _getUserNameFromOrbitDB() ?? 'User';
    } catch (_) {
      currentUserName = 'User';
    }
    await _loadMessages();
  }

  Future<String?> _getUserNameFromOrbitDB() async {
    try {
      if (userAddress == null) {
        await _loadUserAddress();
      }
      if (userAddress == null) return null;
      
      final profile = await HybridStorageService.instance.getUserProfile(userAddress!);
      if (profile != null) {
        return profile['username'];
      }
      return null;
    } catch (e) {
      print('Error loading username from MongoDB: $e');
      return null;
    }
  }

  Future<void> _loadMessages() async {
    // Prevent multiple simultaneous loads (like channels)
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
      print('📥 Loading DM messages for member: ${widget.memberAddress} in workspace: ${widget.workspaceName}');
      
      // Ensure workspace ID is resolved
      if (_workspaceId == null) {
        await _resolveWorkspaceId();
      }
      
      if (userAddress == null) {
        await _loadUserAddress();
      }
      if (userAddress == null) {
        if (mounted) {
          setState(() {
            status = 'User address not found';
            _isLoadingMessages = false;
          });
        }
        return;
      }

      // Use HybridStorageService (works offline) - like channels
      final loaded = await HybridStorageService.instance.getDirectMessages(
        user1Address: userAddress!,
        user2Address: widget.memberAddress,
      );

      print('✅ Loaded ${loaded.length} DM messages from database');
      
      // Transform database format to UI format (like channels)
      final transformedMessages = <Map<String, dynamic>>[];
      
      for (var msg in loaded) {
        // Transform timestamp
        DateTime messageTime;
        if (msg['timestamp'] is DateTime) {
          messageTime = msg['timestamp'] as DateTime;
        } else if (msg['timestamp'] is int) {
          messageTime = DateTime.fromMillisecondsSinceEpoch(msg['timestamp'] as int);
        } else if (msg['timestamp'] is String) {
          messageTime = DateTime.tryParse(msg['timestamp']) ?? DateTime.now();
        } else {
          messageTime = DateTime.now();
        }
        
        // Get message content (decrypted if needed)
        final content = msg['content']?.toString() ?? 
                       msg['message_text']?.toString() ?? 
                       msg['messageText']?.toString() ?? 
                       (msg['encrypted_message'] != null ? '[Encrypted]' : '');
        
        // Get sender address
        final senderAddress = (msg['sender_address']?.toString() ?? 
                              msg['senderAddress']?.toString() ?? 
                              msg['userAddress']?.toString() ?? '').toLowerCase().trim();
        
        // Determine if message is sent by current user
        final isSent = senderAddress == userAddress!.toLowerCase().trim();
        
        // Transform to UI format
        transformedMessages.add({
          'message_id': msg['message_id'] ?? msg['id'],
          'id': msg['message_id'] ?? msg['id'],
          'type': msg['type'] ?? 'text',
          'content': content,
          'message_text': content,
          'messageText': content,
          'timestamp': messageTime,
          'sender_address': senderAddress,
          'senderAddress': senderAddress,
          'userAddress': senderAddress,
          'receiver_address': msg['receiver_address']?.toString() ?? 
                             msg['receiverAddress']?.toString(),
          'receiverAddress': msg['receiver_address']?.toString() ?? 
                            msg['receiverAddress']?.toString(),
          'senderName': isSent ? currentUserName : widget.memberDisplayName,
          'workspace_id': msg['workspace_id'] ?? _effectiveWorkspaceId,
          'message_state': msg['message_state'] ?? msg['state'],
        });
      }
      
      // Sort by timestamp
      transformedMessages.sort((a, b) {
        final aTime = (a['timestamp'] as DateTime).millisecondsSinceEpoch;
        final bTime = (b['timestamp'] as DateTime).millisecondsSinceEpoch;
        return aTime.compareTo(bTime);
      });
      
      if (mounted) {
        setState(() {
          _messages.clear();
          _messages.addAll(transformedMessages);
          _isLoadingMessages = false;
        });
        print('✅ Displayed ${transformedMessages.length} DM messages in UI');
      }

      // _preloadMediaFiles(transformedMessages);
    } on ChainBrokenException catch (e) {
      // Chain integrity compromised - hide all messages and show error
      print('❌ Chain integrity compromised: ${e.message}');
      print('   Broken at: ${e.brokenAt}');
      
      if (mounted) {
        setState(() {
          _messages.clear(); // Hide all messages
          status = '⚠️ Data integrity compromised. Messages cannot be displayed for security reasons.';
        });
        
        // Show error dialog to user
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '⚠️ Data integrity check failed. Messages are hidden for security.',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.red[700],
            duration: const Duration(seconds: 5),
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
        setState(() {
          status = 'Failed to load messages: $e';
          _isLoadingMessages = false;
        });
      }
    } finally {
      if (mounted && _isLoadingMessages) {
        setState(() {
          _isLoadingMessages = false;
        });
      }
    }
  }

  Future<void> _preloadMediaFiles(List<Map<String, dynamic>> messages) async {
    final List<String> mediaCids = [];
    for (var message in messages) {
      final cid = message['cid'] ?? message['fileCid'];
      if (cid != null && cid.toString().isNotEmpty) {
        final cidStr = cid.toString();
        if (!_fileCache.containsKey(cidStr)) {
          mediaCids.add(cidStr);
        }
      }
    }
    
    // Preload in batches of 5
    for (int i = 0; i < mediaCids.length; i += 5) {
      final batch = mediaCids.sublist(i, i + 5 > mediaCids.length ? mediaCids.length : i + 5);
      for (var cid in batch) {
        _getCachedFile(cid).catchError((e) {
          print('Preload error: $e');
          return null;
        });
      }
    }
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    if (userAddress == null) await _loadUserAddress();
    if (userAddress == null) return;
    
    // Ensure workspace ID is resolved
    if (_workspaceId == null) {
      await _resolveWorkspaceId();
    }

    final messageText = _messageController.text.trim();
    _messageController.clear();

    // Generate temporary message ID for local display (will be replaced by server message_id) - like channels
    final tempMessageId = 'temp_${DateTime.now().millisecondsSinceEpoch}_${userAddress}';
    final timestamp = DateTime.now();

    final msg = {
      'type': 'text',
      'content': messageText,
      'timestamp': timestamp,
      'senderName': currentUserName,
      'userAddress': userAddress ?? '',
      'workspace': widget.workspaceName,
      'message_id': tempMessageId, // Temporary ID for deduplication
    };

    // Add to UI immediately with temporary ID (like channels)
    setState(() {
      _messages.add(msg);
    });

    // Use HybridStorageService (works offline + P2P) - like channels
    final result = await HybridStorageService.instance.addMessage(
      workspaceId: _effectiveWorkspaceId,
      senderAddress: userAddress!,
      receiverAddress: widget.memberAddress,
      messageText: messageText,
    );

    if (result == null) {
      // Remove the message if sending failed (like channels)
      setState(() {
        _messages.removeWhere((m) => _getMessageId(m) == tempMessageId);
        status = 'Failed to send message';
      });
    } else {
      // Update the local message with the real message_id from server (like channels)
      // This ensures deduplication works correctly
      setState(() {
        final index = _messages.indexWhere((m) => _getMessageId(m) == tempMessageId);
        if (index >= 0) {
          _messages[index]['message_id'] = result;
          // Also update other fields that might come from server
          _messages[index]['id'] = result;
        }
      });
      print('✅ DM message sent with ID: $result (updated from temp: $tempMessageId)');
    }
  }

  Future<void> _takePicture() async {
     print('⚠️ MongoDB: _takePicture stub called - GridFS implementation pending');
     setState(() {
       status = 'Image upload not yet available';
     });
  }

  Future<void> _pickImageFromGallery() async {
     print('⚠️ MongoDB: _pickImageFromGallery stub called - GridFS implementation pending');
     setState(() {
       status = 'Media upload not yet available';
     });
  }

  Future<void> uploadFile() async {
     print('⚠️ MongoDB: uploadFile stub called - GridFS implementation pending');
     setState(() {
       status = 'File upload not yet available';
     });
  }

  Future<void> _startRecording() async {
    try {
      HapticFeedback.mediumImpact();
      final permissionStatus = await Permission.microphone.request();
      if (!permissionStatus.isGranted) {
        setState(() {
          status = 'Microphone permission denied.';
        });
        return;
      }

      if (await _audioRecorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        _recordingPath = '${dir.path}/voice_$timestamp.m4a';

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 96000,
            sampleRate: 44100,
            numChannels: 1,
          ),
          path: _recordingPath!,
        );

        setState(() {
          _isRecording = true;
          _isLocked = false;
          _recordingDuration = Duration.zero;
          _recordingAmplitude = 0.0;
        });

        _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
          if (mounted) {
            setState(() {
              _recordingDuration = Duration(
                milliseconds: _recordingDuration.inMilliseconds + 100,
              );
            });
          }
        });

        _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) async {
          if (mounted && _isRecording) {
            final amplitude = await _audioRecorder.getAmplitude();
            setState(() {
              _recordingAmplitude = amplitude.current;
              _waveformData.add(amplitude.current);
              if (_waveformData.length > 50) {
                _waveformData.removeAt(0);
              }
            });
          }
        });
      }
    } catch (e) {
      print('❌ Error starting recording: $e');
      setState(() {
        status = 'Error starting recording: $e';
      });
    }
  }

  Future<void> _stopRecording() async {
    try {
      if (_isRecording && _recordingPath != null) {
        final path = await _audioRecorder.stop();
        _recordingTimer?.cancel();
        _amplitudeTimer?.cancel();
        
        setState(() {
          _isRecording = false;
        });
        
        if (path != null && !_isLocked) {
          await _sendVoiceMessage(path);
        } else if (_isLocked) {
          // Keep recording locked, don't send yet
        }
      }
    } catch (e) {
      print('❌ Error stopping recording: $e');
    }
  }

  Future<void> _cancelRecording() async {
    try {
      if (_isRecording) {
        await _audioRecorder.stop();
        _recordingTimer?.cancel();
        _amplitudeTimer?.cancel();
        
        if (_recordingPath != null) {
          final file = File(_recordingPath!);
          if (await file.exists()) {
            await file.delete();
          }
        }
        
        setState(() {
          _isRecording = false;
          _isLocked = false;
          _recordingDuration = Duration.zero;
          _recordingAmplitude = 0.0;
          _waveformData.clear();
          _recordingPath = null;
        });
      }
    } catch (e) {
      print('❌ Error cancelling recording: $e');
    }
  }

  Future<void> _sendVoiceMessage(String path) async {
     print('⚠️ MongoDB: _sendVoiceMessage stub called - GridFS implementation pending');
     setState(() {
       status = 'Voice message not yet available';
     });
  }

  Future<void> _toggleLockRecording() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _isLocked = !_isLocked;
    });
  }

  Future<void> _playAudio(String audioId, String cid) async {
    try {
      if (_playingAudioId == audioId) {
        // Pause if same audio is playing
        await _audioPlayer.pause();
        setState(() {
          _playingAudioId = null;
        });
        return;
      }
      
      // Stop current audio if playing
      if (_playingAudioId != null) {
        await _audioPlayer.stop();
      }
      
      setState(() {
        _playingAudioId = audioId;
      });
      
      final bytes = await _getCachedFile(cid);
      if (bytes == null) {
        setState(() {
          _playingAudioId = null;
          status = 'Failed to load audio';
        });
        return;
      }
      
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/audio_$audioId.m4a');
      await file.writeAsBytes(bytes);
      
      await _audioPlayer.play(DeviceFileSource(file.path));
      
      _playerStateSubscription = _audioPlayer.onPlayerStateChanged.listen((state) {
        if (state == PlayerState.completed) {
          setState(() {
            _playingAudioId = null;
          });
        }
      });
      
      _positionSubscription = _audioPlayer.onPositionChanged.listen((position) {
        setState(() {
          _audioPosition = position;
        });
      });
      
      _audioDuration = await _audioPlayer.getDuration() ?? Duration.zero;
    } catch (e) {
      print('❌ Error playing audio: $e');
      setState(() {
        _playingAudioId = null;
        status = 'Error playing audio: $e';
      });
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatShortDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    if (totalSeconds < 60) {
      return '${totalSeconds}s';
    }
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes}m ${seconds}s';
  }

  void _showFullScreenImage(String cid, String fileName) async {
    try {
      final bytes = await _getCachedFile(cid);
      if (bytes != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => _FullScreenImageViewer(
              imageBytes: bytes,
              fileName: fileName,
            ),
          ),
        );
      }
    } catch (e) {
      print('❌ Error showing full screen image: $e');
    }
  }

  Future<void> downloadAndOpenFile(String cid, String fileName) async {
    try {
      final bytes = await _getCachedFile(cid);
      if (bytes == null) {
        setState(() {
          status = 'Failed to download file';
        });
        return;
      }
      
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);
      
      final result = await OpenFile.open(file.path);
      if (result.type != ResultType.done) {
        setState(() {
          status = 'Could not open file';
        });
      }
    } catch (e) {
      print('❌ Error downloading/opening file: $e');
      setState(() {
        status = 'Error opening file: $e';
      });
    }
  }

  Widget _buildMessageTile(Map<String, dynamic> message, int index) {
    if (userAddress == null) return const SizedBox.shrink();
    
    final senderAddress = message['senderAddress']?.toString().toLowerCase().trim() ?? 
                         message['userAddress']?.toString().toLowerCase().trim() ?? '';
    final isSent = senderAddress == userAddress!.toLowerCase().trim();
    final messageType = message['type']?.toString() ?? 'text';
    final content = message['content']?.toString() ?? '';
    final timestamp = message['timestamp'];
    
    DateTime messageTime;
    if (timestamp is DateTime) {
      messageTime = timestamp;
    } else if (timestamp is int) {
      messageTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    } else {
      messageTime = DateTime.now();
    }
    
    final timeStr = '${messageTime.hour.toString().padLeft(2, '0')}:${messageTime.minute.toString().padLeft(2, '0')}';
    
    if (messageType == 'image') {
      final cid = message['cid'] ?? message['fileCid'] ?? '';
      final fileName = message['fileName']?.toString() ?? 'image.jpg';
      
      return GestureDetector(
        onTap: () => _showFullScreenImage(cid, fileName),
        child: Container(
          margin: EdgeInsets.only(
            bottom: 8,
            left: isSent ? 60 : 16,
            right: isSent ? 16 : 60,
          ),
          child: Row(
            mainAxisAlignment: isSent ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isSent)
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF0F365F),
                  child: Text(
                    widget.memberDisplayName.isNotEmpty 
                        ? widget.memberDisplayName[0].toUpperCase() 
                        : 'U',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              if (!isSent) const SizedBox(width: 8),
              Flexible(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 250),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isSent ? 16 : 4),
                      bottomRight: Radius.circular(isSent ? 4 : 16),
                    ),
                    border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isSent ? 16 : 4),
                      bottomRight: Radius.circular(isSent ? 4 : 16),
                    ),
                    child: FutureBuilder<Uint8List?>(
                      future: _getCachedFile(cid),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return Container(
                            height: 200,
                            color: Colors.grey[200],
                            child: const Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0F365F)),
                              ),
                            ),
                          );
                        }
                        if (snapshot.hasData && snapshot.data != null) {
                          return Image.memory(
                            snapshot.data!,
                            fit: BoxFit.cover,
                            height: 200,
                            width: double.infinity,
                          );
                        }
                        return Container(
                          height: 200,
                          color: Colors.grey[200],
                          child: const Center(child: Icon(Icons.broken_image)),
                        );
                      },
                    ),
                  ),
                ),
              ),
              if (isSent) const SizedBox(width: 8),
              if (isSent)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      timeStr,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Icon(
                      Icons.done_all,
                      color: Colors.white,
                      size: 14,
                    ),
                  ],
                ),
            ],
          ),
        ),
      );
    } else if (messageType == 'file') {
      final cid = message['cid'] ?? message['fileCid'] ?? '';
      final fileName = message['fileName']?.toString() ?? 'file';
      
      return GestureDetector(
        onTap: () => downloadAndOpenFile(cid, fileName),
        child: Container(
          margin: EdgeInsets.only(
            bottom: 8,
            left: isSent ? 60 : 16,
            right: isSent ? 16 : 60,
          ),
          child: Row(
            mainAxisAlignment: isSent ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isSent)
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF0F365F),
                  child: Text(
                    widget.memberDisplayName.isNotEmpty 
                        ? widget.memberDisplayName[0].toUpperCase() 
                        : 'U',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              if (!isSent) const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isSent ? 16 : 4),
                      bottomRight: Radius.circular(isSent ? 4 : 16),
                    ),
                    border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.insert_drive_file, color: Color(0xFF0F365F), size: 24),
                      const SizedBox(width: 8),
                      Flexible(
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
                            Text(
                              'Tap to download',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (isSent) const SizedBox(width: 8),
              if (isSent)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      timeStr,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Icon(
                      Icons.done_all,
                      color: Color(0xFF0F365F),
                      size: 14,
                    ),
                  ],
                ),
            ],
          ),
        ),
      );
    } else if (messageType == 'audio') {
      final cid = message['cid'] ?? message['fileCid'] ?? '';
      final audioId = 'audio_$index';
      final isPlaying = _playingAudioId == audioId;
      final duration = message['duration'] != null
          ? Duration(milliseconds: message['duration'] as int)
          : Duration.zero;
      
      return Container(
        margin: EdgeInsets.only(
          bottom: 8,
          left: isSent ? 60 : 16,
          right: isSent ? 16 : 60,
        ),
        child: Row(
          mainAxisAlignment: isSent ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isSent)
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFF0F365F),
                child: Text(
                  widget.memberDisplayName.isNotEmpty 
                      ? widget.memberDisplayName[0].toUpperCase() 
                      : 'U',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            if (!isSent) const SizedBox(width: 8),
            Flexible(
              child: GestureDetector(
                onTap: () => _playAudio(audioId, cid),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isSent ? 16 : 4),
                      bottomRight: Radius.circular(isSent ? 4 : 16),
                    ),
                    border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        color: const Color(0xFF0F365F),
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatShortDuration(duration),
                              style: const TextStyle(
                                color: Color(0xFF333333),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (isPlaying && _audioDuration.inSeconds > 0)
                              LinearProgressIndicator(
                                value: _audioPosition.inSeconds / _audioDuration.inSeconds,
                                backgroundColor: Colors.grey[200],
                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0F365F)),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (isSent) const SizedBox(width: 8),
            if (isSent)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    timeStr,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Icon(
                    Icons.done_all,
                    color: Color(0xFF0F365F),
                    size: 14,
                  ),
                ],
              ),
          ],
        ),
      );
    } else {
      // Text message
      return Container(
        margin: EdgeInsets.only(
          bottom: 8,
          left: isSent ? 60 : 16,
          right: isSent ? 16 : 60,
        ),
        child: Row(
          mainAxisAlignment: isSent ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isSent)
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFF0F365F),
                child: Text(
                  widget.memberDisplayName.isNotEmpty 
                      ? widget.memberDisplayName[0].toUpperCase() 
                      : 'U',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            if (!isSent) const SizedBox(width: 8),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isSent ? 16 : 4),
                    bottomRight: Radius.circular(isSent ? 4 : 16),
                  ),
                  border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      content,
                      style: const TextStyle(
                        color: Color(0xFF333333),
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          timeStr,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 11,
                          ),
                        ),
                        if (isSent) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.done_all,
                            color: Color(0xFF0F365F),
                            size: 14,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (isSent) const SizedBox(width: 8),
          ],
        ),
      );
    }
  }

  Widget _buildRecordingOverlay() {
    if (!_isRecording) return const SizedBox.shrink();
    
    return Positioned(
      bottom: 80,
      left: 0,
      right: 0,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0F365F),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.mic,
                  color: Colors.red[400],
                  size: 32,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Container(
                    height: 40,
                    child: CustomPaint(
                      painter: WaveformPainter(_waveformData),
                      size: Size.infinite,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  _formatDuration(_recordingDuration),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isLocked)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock, color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text(
                          'Locked',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                if (!_isLocked)
                  GestureDetector(
                    onTap: _toggleLockRecording,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.lock_open, color: Colors.white, size: 20),
                    ),
                  ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: _isLocked ? () async {
                    await _stopRecording();
                    if (_recordingPath != null) {
                      await _sendVoiceMessage(_recordingPath!);
                    }
                  } : null,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _isLocked ? Colors.green : Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isLocked ? Icons.send : Icons.stop,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: _cancelRecording,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.7),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 24),
                  ),
                ),
              ],
            ),
            if (!_isLocked)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Swipe up to lock',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final memberName = widget.memberDisplayName.isNotEmpty 
        ? widget.memberDisplayName 
        : (widget.memberAddress.length > 10
            ? '${widget.memberAddress.substring(0, 6)}...${widget.memberAddress.substring(widget.memberAddress.length - 4)}'
            : widget.memberAddress);
    final memberInitial = memberName.isNotEmpty ? memberName[0].toUpperCase() : 'U';

    return Scaffold(
      backgroundColor: Colors.white,
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    child: Text(
                      memberInitial,
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
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          memberName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          widget.workspaceName,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          if (_messages.isEmpty)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No messages yet',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Start a conversation with ${widget.memberDisplayName.isNotEmpty ? widget.memberDisplayName : 'this member'}',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return _buildMessageTile(_messages[index], index);
              },
            ),
          // Input area
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      // Camera icon
                      GestureDetector(
                        onTap: _takePicture,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.photo_camera,
                            color: Color(0xFF0F365F),
                            size: 24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Attachment menu
                      PopupMenuButton<String>(
                        offset: const Offset(-20, -120),
                        icon: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.add_rounded,
                            color: Color(0xFF0F365F),
                            size: 24,
                          ),
                        ),
                        onSelected: (value) {
                          if (value == 'file') {
                            uploadFile();
                          } else if (value == 'photo') {
                            _pickImageFromGallery();
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'file',
                            child: Row(
                              children: [
                                Icon(Icons.attach_file, color: Color(0xFF0F365F)),
                                SizedBox(width: 12),
                                Text('Attach File'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'photo',
                            child: Row(
                              children: [
                                Icon(Icons.photo_library, color: Color(0xFF0F365F)),
                                SizedBox(width: 12),
                                Text('Photos'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      // Text input
                      Expanded(
                        child: Container(
                          constraints: const BoxConstraints(maxHeight: 100),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                child: TextField(
                                  controller: _messageController,
                                  maxLines: null,
                                  textCapitalization: TextCapitalization.sentences,
                                  decoration: const InputDecoration(
                                    hintText: 'Text Message...',
                                    hintStyle: TextStyle(color: Colors.grey),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  style: const TextStyle(fontSize: 15),
                                  onSubmitted: (_) => _sendMessage(),
                                ),
                              ),
                              // Send/Mic icon
                              Positioned(
                                right: 6,
                                top: 0,
                                bottom: 0,
                                child: Center(
                                  child: _hasText
                                      ? GestureDetector(
                                          onTap: _sendMessage,
                                          child: Container(
                                            width: 32,
                                            height: 32,
                                            decoration: const BoxDecoration(
                                              color: Color(0xFF0F365F),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.send_rounded,
                                              color: Colors.white,
                                              size: 20,
                                            ),
                                          ),
                                        )
                                      : Listener(
                                          onPointerDown: (event) {
                                            if (!_isRecording && !_isLocked) {
                                              _panStartPosition = event.localPosition;
                                              _startRecording();
                                            }
                                          },
                                          onPointerMove: (event) {
                                            if (_isRecording && !_isLocked && _panStartPosition != null) {
                                              final deltaY = _panStartPosition!.dy - event.localPosition.dy;
                                              if (deltaY > 30) {
                                                _toggleLockRecording();
                                                _panStartPosition = null;
                                              }
                                            }
                                          },
                                          onPointerUp: (event) {
                                            _panStartPosition = null;
                                            if (_isRecording && !_isLocked) {
                                              _stopRecording();
                                            }
                                          },
                                          onPointerCancel: (event) {
                                            _panStartPosition = null;
                                            if (_isRecording && !_isLocked) {
                                              _cancelRecording();
                                            }
                                          },
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onPanStart: (details) {
                                              if (!_isRecording && !_isLocked) {
                                                _panStartPosition = details.localPosition;
                                                _startRecording();
                                              }
                                            },
                                            onPanUpdate: (details) {
                                              if (_isRecording && !_isLocked && _panStartPosition != null) {
                                                final deltaY = _panStartPosition!.dy - details.localPosition.dy;
                                                if (deltaY > 30) {
                                                  _toggleLockRecording();
                                                  _panStartPosition = null;
                                                }
                                              }
                                            },
                                            onPanEnd: (details) {
                                              _panStartPosition = null;
                                              if (_isRecording && !_isLocked) {
                                                _stopRecording();
                                              }
                                            },
                                            onPanCancel: () {
                                              _panStartPosition = null;
                                              if (_isRecording && !_isLocked) {
                                                _cancelRecording();
                                              }
                                            },
                                            child: Container(
                                              width: 32,
                                              height: 32,
                                              decoration: BoxDecoration(
                                                color: _isRecording ? Colors.red.withOpacity(0.2) : Colors.transparent,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                _isRecording ? Icons.mic : Icons.mic_none,
                                                color: _isRecording ? Colors.red : const Color(0xFF0F365F),
                                                size: 20,
                                              ),
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Recording overlay
          _buildRecordingOverlay(),
        ],
      ),
    );
  }
}

// Waveform painter for voice messages
class WaveformPainter extends CustomPainter {
  final List<double> amplitudes;
  
  WaveformPainter(this.amplitudes);
  
  @override
  void paint(Canvas canvas, Size size) {
    if (amplitudes.isEmpty) return;
    
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    
    final centerY = size.height / 2;
    final barWidth = size.width / amplitudes.length;
    
    for (int i = 0; i < amplitudes.length; i++) {
      final amplitude = amplitudes[i];
      final barHeight = (amplitude / 100) * size.height * 0.8;
      
      canvas.drawLine(
        Offset(i * barWidth, centerY - barHeight / 2),
        Offset(i * barWidth, centerY + barHeight / 2),
        paint,
      );
    }
  }
  
  @override
  bool shouldRepaint(WaveformPainter oldDelegate) {
    return oldDelegate.amplitudes.length != amplitudes.length;
  }
}

// Full screen image viewer
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
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          fileName,
          style: const TextStyle(color: Colors.white),
        ),
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

