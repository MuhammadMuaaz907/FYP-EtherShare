import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:get_it/get_it.dart';
import 'services/ipfs_service.dart';
import 'services/orbitdb_service.dart';
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
  
  const ChannelPage(
      {super.key, required this.channelName, required this.workspaceName});

  @override
  _ChannelPageState createState() => _ChannelPageState();
}

class _ChannelPageState extends State<ChannelPage> {
  final IPFSService ipfsService = GetIt.I<IPFSService>();
  final OrbitDBService orbitDBService = GetIt.I<OrbitDBService>();
  String status = '';
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  String currentUserName = 'User';
  String? userAddress;
  int _memberCount = 0;
  bool _isLoadingMembers = false;
  String? _inviterAddress;
  bool _hasText = false;
  late VoidCallback _textListener;
  String _currentChannelName = ''; // Track current channel name (for updates)

  // Cache for downloaded files/images to avoid reloading
  final Map<String, Uint8List?> _fileCache = {};
  final Map<String, Future<Uint8List?>> _downloadFutures =
      {}; // Track ongoing downloads

  // Voice recording
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  String? _recordingPath;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  String? _playingAudioId; // Track which audio is currently playing
  bool _isLocked = false; // Lock recording mode
  double _recordingAmplitude = 0.0; // For visual feedback
  Timer? _amplitudeTimer;
  bool _isUploading = false; // Track upload state
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  Duration _audioPosition = Duration.zero;
  Duration _audioDuration = Duration.zero;
  List<double> _waveformData = []; // For wave line animation
  Offset? _panStartPosition; // Track pan gesture start

  @override
  void initState() {
    super.initState();
    _currentChannelName = widget.channelName; // Initialize with widget channel name
    _resolveChannelDisplayName(); // Resolve display name if channel was renamed
    _loadUserNameAndMessages();
    _loadWorkspaceMembers();
    _textListener = () {
      setState(() {
        _hasText = _messageController.text.trim().isNotEmpty;
      });
    };
    _messageController.addListener(_textListener);
  }
  
  /// Resolve channel display name (check if channel was renamed)
  /// Checks both SharedPreferences and OrbitDB for rename actions
  /// SharedPreferences takes priority as it's updated immediately after rename
  Future<void> _resolveChannelDisplayName() async {
    try {
      String? resolvedName;
      final prefs = await SharedPreferences.getInstance();
      
      // Step 1: First, check SharedPreferences (fastest and most up-to-date)
      // SharedPreferences is updated immediately after rename, so it's the most reliable source
      final mappingKey = 'channel_name_mapping_${widget.workspaceName}_${widget.channelName}';
      final mappedName = prefs.getString(mappingKey);
      
      if (mappedName != null && mappedName.isNotEmpty) {
        resolvedName = mappedName;
        print('✅ [ResolveName] Found rename in SharedPreferences: "${widget.channelName}" -> "$resolvedName"');
        
        // If SharedPreferences has the mapping, use it directly (it's the most recent)
        // No need to check OrbitDB chain if SharedPreferences already has the answer
        setState(() {
          _currentChannelName = resolvedName!; // Safe: we checked it's not null above
        });
        print('✅ [ResolveName] Channel display name resolved from SharedPreferences: "$_currentChannelName"');
        return; // Early return - SharedPreferences takes precedence
      }
      
      // Step 2: If not in SharedPreferences, check OrbitDB for rename actions
      // This handles cases where SharedPreferences might be missing (e.g., after app reinstall)
      // Build a rename chain to handle multiple renames
      if (_inviterAddress == null) {
        _inviterAddress = await OrbitDBService.getInviterAddressForWorkspace(
            widget.workspaceName);
      }
      
      if (_inviterAddress != null) {
        final workspaceDbName = 'workspace_$_inviterAddress';
        final dbAddress = await OrbitDBService.getExistingDatabaseAddress(workspaceDbName);
        
        if (dbAddress != null) {
          final messages = await OrbitDBService.getMessages(dbAddress);
          
          // Collect all rename actions for this workspace
          final List<Map<String, dynamic>> renameActions = [];
          for (var message in messages) {
            if (message['type'] == 'channel_rename' &&
                message['workspaceName'] == widget.workspaceName) {
              final oldName = message['oldChannelName']?.toString();
              final newName = message['newChannelName']?.toString();
              final timestamp = message['timestamp'];
              
              if (oldName != null && newName != null && timestamp is int) {
                renameActions.add({
                  'oldName': oldName.toLowerCase(),
                  'newName': newName,
                  'timestamp': timestamp,
                });
              }
            }
          }
          
          if (renameActions.isNotEmpty) {
            // Use widget.channelName as the starting point (this is the original DB name)
            // Don't trace backwards - widget.channelName is always the original name used for DB operations
            String startName = widget.channelName.toLowerCase();
            print('📍 [ResolveName] Starting rename chain from original DB name: "$startName"');
            
            // Build rename chain forward from original name to get latest name
            String currentName = startName;
            String? finalName;
            bool foundChain = false;
            final Set<String> visitedNames = {}; // Track visited names to prevent cycles
            final int maxIterations = 100; // Safety limit
            int iterations = 0;
            
            // Keep following the rename chain forward until we can't find more renames
            while (iterations < maxIterations) {
              iterations++;
              
              // Prevent infinite loops: if we've seen this name before, we're in a cycle
              if (visitedNames.contains(currentName)) {
                print('⚠️ [ResolveName] Detected cycle at "$currentName", breaking chain');
                break;
              }
              visitedNames.add(currentName);
              
              // Find the most recent rename where oldName matches currentName
              Map<String, dynamic>? bestRename;
              int bestTimestamp = 0;
              
              for (var rename in renameActions) {
                final renameOldName = rename['oldName']?.toString().toLowerCase();
                if (renameOldName == currentName &&
                    rename['timestamp'] is int &&
                    rename['timestamp'] > bestTimestamp) {
                  bestRename = rename;
                  bestTimestamp = rename['timestamp'] as int;
                }
              }
              
              if (bestRename != null) {
                foundChain = true;
                finalName = bestRename['newName'] as String;
                final newNameLower = finalName.toLowerCase();
                
                // Check if we're about to create a cycle
                if (visitedNames.contains(newNameLower)) {
                  print('⚠️ [ResolveName] Would create cycle: "$currentName" -> "$finalName" (already visited), stopping');
                  break;
                }
                
                currentName = newNameLower;
                print('🔗 [ResolveName] Following rename chain: "${bestRename['oldName']}" -> "$finalName" (timestamp: $bestTimestamp)');
              } else {
                // No more renames in chain - current name is the latest
                break;
              }
            }
            
            if (iterations >= maxIterations) {
              print('⚠️ [ResolveName] Reached max iterations ($maxIterations), breaking to prevent infinite loop');
            }
            
            if (foundChain && finalName != null && finalName.isNotEmpty) {
              // Found rename chain in OrbitDB
              resolvedName = finalName;
              print('✅ [ResolveName] Found rename chain in OrbitDB: "$startName" -> "$resolvedName"');
              
              // Update SharedPreferences to keep it in sync for future lookups
              final originalMappingKey = 'channel_name_mapping_${widget.workspaceName}_$startName';
              await prefs.setString(originalMappingKey, resolvedName);
              final reverseMappingKey = 'channel_old_name_${widget.workspaceName}_$resolvedName';
              await prefs.setString(reverseMappingKey, startName);
            }
          } else {
            print('ℹ️ [ResolveName] No rename actions found in OrbitDB for this workspace');
          }
        }
      }
      
      // Update display name if we found a rename
      if (resolvedName != null && resolvedName.isNotEmpty) {
        setState(() {
          _currentChannelName = resolvedName!; // Safe: we checked it's not null above
        });
        print('✅ [ResolveName] Channel display name resolved: "$_currentChannelName"');
      } else {
        // No rename found, use original name
        setState(() {
          _currentChannelName = widget.channelName;
        });
        print('ℹ️ [ResolveName] No rename found, using original name: "${widget.channelName}"');
      }
    } catch (e) {
      print('❌ Error resolving channel display name: $e');
      // Fallback to original name on error
      setState(() {
        _currentChannelName = widget.channelName;
      });
    }
  }

  @override
  void dispose() {
    _messageController.removeListener(_textListener);
    _messageController.dispose();
    // Clear cache on dispose to free memory
    _fileCache.clear();
    _downloadFutures.clear();
    // Stop recording and release resources
    _stopRecording();
    _recordingTimer?.cancel();
    _amplitudeTimer?.cancel();
    _playerStateSubscription?.cancel();
    _positionSubscription?.cancel();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  /// Get file from cache or download if not cached
  Future<Uint8List?> _getCachedFile(String cid) async {
    // Check cache first
    if (_fileCache.containsKey(cid)) {
      print('✅ [Cache] File found in cache: $cid');
      return _fileCache[cid];
    }

    // Check if download is already in progress
    if (_downloadFutures.containsKey(cid)) {
      print('⏳ [Cache] Download already in progress: $cid');
      return _downloadFutures[cid];
    }

    // Start download and cache it
    print('📥 [Cache] Downloading file: $cid');
    final downloadFuture = OrbitDBService.downloadFile(cid).then((bytes) {
      // Cache the result
      if (bytes != null) {
        _fileCache[cid] = bytes;
        print('✅ [Cache] File cached: $cid (${bytes.length} bytes)');
      }
      // Remove from ongoing downloads
      _downloadFutures.remove(cid);
      return bytes;
    }).catchError((error) {
      // Remove from ongoing downloads on error
      _downloadFutures.remove(cid);
      print('❌ [Cache] Download failed: $cid - $error');
      throw error;
    });

    // Store the future to prevent duplicate downloads
    _downloadFutures[cid] = downloadFuture;
    return downloadFuture;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-resolve channel name in case it was renamed while away
    _resolveChannelDisplayName();
    
    // Only reload messages if they're empty (first load)
    // Cache is preserved, so images/files won't reload
    if (_messages.isEmpty) {
    _loadMessages();
    } else {
      // If messages exist, just check for new ones without clearing cache
      _checkForNewMessages();
    }
  }

  /// Check for new messages without clearing existing cache
  Future<void> _checkForNewMessages() async {
    try {
      List<Map<String, dynamic>> loaded =
          await OrbitDBService.getChannelMessages(
              widget.workspaceName, widget.channelName);

      // Parse timestamps
      for (var msg in loaded) {
        if (msg['timestamp'] is String) {
          msg['timestamp'] =
              DateTime.tryParse(msg['timestamp']) ?? DateTime.now();
        } else if (msg['timestamp'] is int) {
          msg['timestamp'] =
              DateTime.fromMillisecondsSinceEpoch(msg['timestamp']);
        }
      }

      // Only update if message count changed (new messages)
      if (loaded.length != _messages.length) {
        setState(() {
          _messages.clear();
          _messages.addAll(loaded);
        });
        // Preload any new media files
        _preloadMediaFiles(loaded);
      }
    } catch (e) {
      print('❌ Error checking for new messages: $e');
    }
  }

  Future<void> _loadUserAddress() async {
    try {
      final session = await OrbitDBService.getLoginSession();
      userAddress = session['userAddress'];
    } catch (e) {
      print('❌ Error loading user address: $e');
    }
  }

  Future<void> _loadUserNameAndMessages() async {
    // Load user name from OrbitDB instead of SharedPreferences
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
      
      final key = userAddress!.toLowerCase().trim();
      final dbName = 'profile_$key';
      final dbAddress = await OrbitDBService.getExistingDatabaseAddress(dbName);
      
      if (dbAddress != null) {
        final messages = await OrbitDBService.getMessages(dbAddress);
        
        for (var message in messages) {
          if (message['type'] == 'profile' && message['userAddress'] == key) {
            return message['username'];
          }
        }
      }
      return null;
    } catch (e) {
      print('Error loading username from OrbitDB: $e');
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

      // Find the inviter address for this workspace
      _inviterAddress = await OrbitDBService.getInviterAddressForWorkspace(
          widget.workspaceName);
      
      if (_inviterAddress == null) {
        setState(() {
          _isLoadingMembers = false;
          _memberCount = 0;
        });
        return;
      }

      final members = await OrbitDBService.getWorkspaceMembers(
        inviterAddress: _inviterAddress!,
        workspaceName: widget.workspaceName,
      );

      // Ensure current logged-in user is in the count
      if (userAddress != null) {
        final userKey = userAddress!.toLowerCase().trim();
        final userExists = members.any(
            (m) => m['memberAddress']?.toString().toLowerCase() == userKey);
        if (!userExists) {
          // User is not in the list, but they should be counted
          // The actual list will be updated when showing channel info
        }
      }

      setState(() {
        _memberCount = members.length +
            (userAddress != null &&
                    !members.any((m) =>
                        m['memberAddress']?.toString().toLowerCase() ==
                        userAddress!.toLowerCase())
                ? 1
                : 0);
        _isLoadingMembers = false;
      });
    } catch (e) {
      print('❌ Error loading workspace member count: $e');
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
      print('🔍 [Channel] Fetching profile name for: $address (db: $dbName)');
      
      // Try to get existing database first
      var dbAddress = await OrbitDBService.getExistingDatabaseAddress(dbName);
      
      // If database doesn't exist, try creating it (it might be a new profile)
      if (dbAddress == null) {
        print(
            '⚠️ [Channel] Profile database not found in cache, trying to create: $dbName');
        dbAddress = await OrbitDBService.createChatDB(dbName);
        if (dbAddress == null) {
          print(
              '❌ [Channel] Could not create/find profile database for: $address');
          return null;
        }
      }
      
      print('📌 [Channel] Using profile database: $dbAddress');
      final messages = await OrbitDBService.getMessages(dbAddress);
      print(
          '📨 [Channel] Retrieved ${messages.length} messages from profile database');
      
      if (messages.isEmpty) {
        print('⚠️ [Channel] Profile database is empty for: $address');
        return null;
      }
      
      // Look for profile message
      for (var message in messages) {
        final msgType = message['type']?.toString();
        print('🔍 [Channel] Checking message: type=$msgType');
        print('🔍 [Channel] Message keys: ${message.keys.toList()}');
        print('🔍 [Channel] Full message: ${message.toString()}');
        
        if (msgType == 'profile') {
          final msgUserAddress =
              message['userAddress']?.toString().toLowerCase().trim();
          print(
              '🔍 [Channel] Profile message userAddress: $msgUserAddress (looking for: $key)');
          
          if (msgUserAddress == key) {
            // Try multiple ways to get username
            dynamic usernameValue = message['username'];
            String? username;
            
            if (usernameValue != null) {
              username = usernameValue.toString().trim();
            }
            
            print(
                '✅ [Channel] Found profile - Username value: $usernameValue, Username string: "$username" for address: $address');
            
            if (username != null && username.isNotEmpty) {
              print('✅ [Channel] Returning username: $username');
              return username;
            } else {
              print(
                  '⚠️ [Channel] Username is null or empty in profile for: $address');
              print(
                  '⚠️ [Channel] Username value type: ${usernameValue.runtimeType}');
            }
          } else {
            print(
                '⚠️ [Channel] userAddress mismatch: expected=$key, got=$msgUserAddress');
          }
        } else {
          print('⚠️ [Channel] Message type is not profile: $msgType');
        }
      }
      
      print(
          '⚠️ [Channel] No valid profile message found for address: $address');
      return null;
    } catch (e, stackTrace) {
      print('❌ [Channel] Error getting profile name for $address: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }

  Future<void> _loadMessages() async {
    try {
      print('📨 [LoadMessages] Loading messages for channel: "${widget.channelName}" in workspace: "${widget.workspaceName}"');
      print('📨 [LoadMessages] Database will use: chat_${widget.workspaceName}_${widget.channelName}');
      
      List<Map<String, dynamic>> loaded =
          await OrbitDBService.getChannelMessages(
              widget.workspaceName, widget.channelName);
      
      // Debug: Print loaded messages to see their structure
      print('📨 [LoadMessages] Loaded ${loaded.length} messages from database');
      if (loaded.isNotEmpty) {
        for (var msg in loaded.take(3)) { // Only print first 3 to avoid spam
          final content = msg['content']?.toString() ?? '';
          final contentPreview = content.length > 30 ? '${content.substring(0, 30)}...' : content;
          print('  - Type: ${msg['type']}, Content: $contentPreview, FileName: ${msg['fileName']}');
        }
        if (loaded.length > 3) {
          print('  ... and ${loaded.length - 3} more messages');
        }
      } else {
        print('⚠️ [LoadMessages] No messages found in database. This might be normal for a new channel.');
      }
      
    // Parse timestamps back to DateTime
    for (var msg in loaded) {
      if (msg['timestamp'] is String) {
          msg['timestamp'] =
              DateTime.tryParse(msg['timestamp']) ?? DateTime.now();
        } else if (msg['timestamp'] is int) {
          msg['timestamp'] =
              DateTime.fromMillisecondsSinceEpoch(msg['timestamp']);
      }
    }
      
    setState(() {
      _messages.clear();
      _messages.addAll(loaded);
    });

      // Preload images/files immediately and aggressively (non-blocking)
      _preloadMediaFiles(loaded);
    } catch (e) {
      print('❌ Error loading messages: $e');
      setState(() {
        status = 'Failed to load messages: $e';
      });
    }
  }

  /// Preload media files (images/videos) aggressively for instant display
  Future<void> _preloadMediaFiles(List<Map<String, dynamic>> messages) async {
    // Collect all media CIDs
    final List<String> mediaCids = [];
    for (var message in messages) {
      final cid = message['cid'] ?? message['fileCid'];
      if (cid != null && cid.toString().isNotEmpty) {
        final cidStr = cid.toString();
        // Only preload if not already cached
        if (!_fileCache.containsKey(cidStr)) {
          mediaCids.add(cidStr);
        }
      }
    }

    if (mediaCids.isEmpty) {
      print('✅ [Preload] All media files already cached');
      return;
    }

    print('📥 [Preload] Preloading ${mediaCids.length} media files...');

    // Preload all files concurrently (but limit concurrency to avoid overwhelming)
    final int maxConcurrent = 5; // Download 5 files at a time
    for (int i = 0; i < mediaCids.length; i += maxConcurrent) {
      final batch = mediaCids.skip(i).take(maxConcurrent).toList();

      // Download batch concurrently
      await Future.wait(
        batch.map((cid) => _getCachedFile(cid).catchError((error) {
              print('⚠️ [Preload] Failed to preload $cid: $error');
              return null;
            })),
      );

      // Small delay between batches to avoid overwhelming network
      if (i + maxConcurrent < mediaCids.length) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    print('✅ [Preload] Completed preloading ${mediaCids.length} media files');
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

        // Upload image using OrbitDB service (which uses IPFS)
        final uploadResult = await OrbitDBService.uploadFile(
            widget.workspaceName, fileName, imageBytes);

        if (uploadResult != null && uploadResult['success'] == true) {
          print(
              '✅ Image uploaded successfully. CID: ${uploadResult['fileCid']}');

          final fileCid = uploadResult['fileCid'];

          // Immediately cache the uploaded image bytes (we already have them)
          if (!_fileCache.containsKey(fileCid)) {
            _fileCache[fileCid] = imageBytes;
            print(
                '✅ [Cache] Uploaded image cached immediately: $fileCid (${imageBytes.length} bytes)');
          }

          // Determine if it's an image based on file extension
          final isImageFile = fileName.toLowerCase().endsWith('.jpg') ||
              fileName.toLowerCase().endsWith('.jpeg') ||
              fileName.toLowerCase().endsWith('.png') ||
              fileName.toLowerCase().endsWith('.gif');

          final msg = {
            'type': isImageFile ? 'image' : 'file',
            'content': isImageFile ? 'Image: $fileName' : 'File: $fileName',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'fileName': fileName,
            'fileSize': fileSize,
            'cid': fileCid,
            'fileCid': fileCid, // For compatibility
            'senderName': currentUserName,
            'sender': currentUserName, // For compatibility
            'userAddress': userAddress ?? '', // Add user address
            'workspace': widget.workspaceName,
            'channel': widget.channelName,
          };

          print('💬 Saving image message with user info:');
          print('  - senderName: ${msg['senderName']}');
          print('  - userAddress: ${msg['userAddress']}');
          print('  - fileName: ${msg['fileName']}');
          print('  - fileCid: ${msg['fileCid']}');
          print('  - type: ${msg['type']}');

          // Add to local state immediately
          setState(() {
            _messages.add({
              ...msg,
              'timestamp': DateTime.now(),
            });
            status = 'Image sent successfully!';
          });

          // Save to OrbitDB
          final success = await OrbitDBService.addChannelMessage(
              widget.workspaceName, widget.channelName, msg);
          if (!success) {
            // If save failed, remove from local state
            setState(() {
              _messages.removeLast();
              status = 'Failed to save image message';
            });
            print('❌ Failed to save image message to OrbitDB');
          } else {
            print('✅ Image message saved successfully with user info');
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
          print(
              '❌ Image upload failed: ${uploadResult?['error'] ?? 'Unknown error'}');
          setState(() {
            status = 'Failed to upload image. Please check IPFS connection.';
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

        // Upload media using OrbitDB service (which uses IPFS)
        final uploadResult = await OrbitDBService.uploadFile(
            widget.workspaceName, finalFileName, mediaBytes);

        if (uploadResult != null && uploadResult['success'] == true) {
          print(
              '✅ Gallery media uploaded successfully. CID: ${uploadResult['fileCid']}');

          final fileCid = uploadResult['fileCid'];

          // Immediately cache the uploaded media bytes (we already have them)
          if (!_fileCache.containsKey(fileCid)) {
            _fileCache[fileCid] = mediaBytes;
            print(
                '✅ [Cache] Uploaded media cached immediately: $fileCid (${mediaBytes.length} bytes)');
          }

          // Determine if it's an image based on file extension
          final isImageFile = finalFileName.toLowerCase().endsWith('.jpg') ||
              finalFileName.toLowerCase().endsWith('.jpeg') ||
              finalFileName.toLowerCase().endsWith('.png') ||
              finalFileName.toLowerCase().endsWith('.gif') ||
              finalFileName.toLowerCase().endsWith('.webp');

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
            'cid': fileCid,
            'fileCid': fileCid, // For compatibility
            'senderName': currentUserName,
            'sender': currentUserName, // For compatibility
            'userAddress': userAddress ?? '', // Add user address
            'workspace': widget.workspaceName,
            'channel': widget.channelName,
          };

          print('💬 Saving gallery media message with user info:');
          print('  - senderName: ${msg['senderName']}');
          print('  - userAddress: ${msg['userAddress']}');
          print('  - fileName: ${msg['fileName']}');
          print('  - fileCid: ${msg['fileCid']}');
          print('  - type: ${msg['type']}');

          // Add to local state immediately
          setState(() {
            _messages.add({
              ...msg,
              'timestamp': DateTime.now(),
            });
            status = isVideo
                ? 'Video sent successfully!'
                : 'Image sent successfully!';
          });

          // Save to OrbitDB
          final success = await OrbitDBService.addChannelMessage(
              widget.workspaceName, widget.channelName, msg);
          if (!success) {
            // If save failed, remove from local state
            setState(() {
              _messages.removeLast();
              status = 'Failed to save media message';
            });
            print('❌ Failed to save gallery media message to OrbitDB');
          } else {
            print('✅ Gallery media message saved successfully with user info');
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
          print(
              '❌ Gallery media upload failed: ${uploadResult?['error'] ?? 'Unknown error'}');
          setState(() {
            status = 'Failed to upload media. Please check IPFS connection.';
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
        
        // Upload file using OrbitDB service (which uses IPFS)
        final uploadResult = await OrbitDBService.uploadFile(
            widget.workspaceName, result.files.single.name, fileBytes);
        
        if (uploadResult != null && uploadResult['success'] == true) {
          print(
              '✅ File uploaded successfully. CID: ${uploadResult['fileCid']}');

          final fileCid = uploadResult['fileCid'];

          // Immediately cache the uploaded file bytes (we already have them)
          if (!_fileCache.containsKey(fileCid)) {
            _fileCache[fileCid] = fileBytes;
            print(
                '✅ [Cache] Uploaded file cached immediately: $fileCid (${fileBytes.length} bytes)');
          }
          
          final msg = {
            'type': 'file',
            'content': 'File: ${result.files.single.name}',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'fileName': result.files.single.name,
            'fileSize': fileSize,
            'cid': fileCid,
            'fileCid': fileCid, // For compatibility
            'senderName': currentUserName,
            'sender': currentUserName, // For compatibility
            'userAddress': userAddress ?? '', // Add user address
            'workspace': widget.workspaceName,
            'channel': widget.channelName,
          };
          
          print('💬 Saving file message with user info:');
          print('  - senderName: ${msg['senderName']}');
          print('  - userAddress: ${msg['userAddress']}');
          print('  - fileName: ${msg['fileName']}');
          print('  - fileCid: ${msg['fileCid']}');
          
          // Add to local state immediately
          setState(() {
            _messages.add({
              ...msg,
              'timestamp': DateTime.now(),
            });
            status = 'File uploaded successfully!';
          });
          
          // Save to OrbitDB
          final success = await OrbitDBService.addChannelMessage(
              widget.workspaceName, widget.channelName, msg);
          if (!success) {
            // If save failed, remove from local state
            setState(() {
              _messages.removeLast();
              status = 'Failed to save file message';
            });
            print('❌ Failed to save file message to OrbitDB');
          } else {
            print('✅ File message saved successfully with user info');
          }
        } else {
          print(
              '❌ File upload failed: ${uploadResult?['error'] ?? 'Unknown error'}');
          setState(() {
            status = 'Failed to upload file. Please check IPFS connection.';
          });
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
    if (_messageController.text.trim().isNotEmpty) {
      // Ensure user address is loaded
      if (userAddress == null) {
        await _loadUserAddress();
      }
      
      final msg = {
        'type': 'text',
        'content': _messageController.text.trim(),
        'timestamp': DateTime.now()
            .millisecondsSinceEpoch, // Use milliseconds for consistency
        'senderName': currentUserName,
        'sender': currentUserName, // For compatibility
        'userAddress': userAddress ?? '', // Add user address
        'workspace': widget.workspaceName,
        'channel': widget.channelName,
      };
      
      print('💬 Sending message with user info:');
      print('  - senderName: ${msg['senderName']}');
      print('  - userAddress: ${msg['userAddress']}');
      print('  - content: ${msg['content']}');
      
      // Add to local state immediately for UI responsiveness
      setState(() {
        _messages.add({
          ...msg,
          'timestamp': DateTime.now(),
        });
      });
      
      _messageController.clear();
      
      // Save to OrbitDB
      final success = await OrbitDBService.addChannelMessage(
          widget.workspaceName, widget.channelName, msg);
      if (!success) {
        // If save failed, remove from local state
        setState(() {
          _messages.removeLast();
        });
        setState(() {
          status = 'Failed to send message';
        });
      } else {
        print('✅ Message saved successfully with user info');
      }
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

      // Upload audio file
      final uploadResult = await OrbitDBService.uploadFile(
          widget.workspaceName, fileName, audioBytes);

      if (uploadResult != null && uploadResult['success'] == true) {
        final fileCid = uploadResult['fileCid'];

        // Immediately cache the uploaded audio bytes
        if (!_fileCache.containsKey(fileCid)) {
          _fileCache[fileCid] = audioBytes;
          print(
              '✅ [Cache] Uploaded voice message cached immediately: $fileCid');
        }

        final msg = {
          'type': 'audio',
          'content': 'Voice message: $fileName',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'fileName': fileName,
          'fileSize': fileSize,
          'duration': _recordingDuration.inSeconds, // Store duration in seconds
          'cid': fileCid,
          'fileCid': fileCid,
          'senderName': currentUserName,
          'sender': currentUserName,
          'userAddress': userAddress ?? '',
          'workspace': widget.workspaceName,
          'channel': widget.channelName,
        };

        print('💬 Saving voice message with user info:');
        print('  - senderName: ${msg['senderName']}');
        print('  - userAddress: ${msg['userAddress']}');
        print('  - fileName: ${msg['fileName']}');
        print('  - duration: ${msg['duration']} seconds');

        // Add to local state immediately
        setState(() {
          _messages.add({
            ...msg,
            'timestamp': DateTime.now(),
          });
          status = 'Voice message sent! ✓';
          _recordingPath = null;
          _recordingDuration = Duration.zero;
          _isUploading = false;
        });

        // Save to OrbitDB
        final success = await OrbitDBService.addChannelMessage(
            widget.workspaceName, widget.channelName, msg);
        if (!success) {
          setState(() {
            _messages.removeLast();
            status = 'Failed to save voice message. Please try again.';
            _isUploading = false;
          });
          print('❌ Failed to save voice message to OrbitDB');
          HapticFeedback.mediumImpact();
        } else {
          print('✅ Voice message saved successfully');
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

        // Delete temporary file
        try {
          if (await audioFile.exists()) {
            await audioFile.delete();
          }
        } catch (_) {}
      } else {
        print('❌ Voice message upload failed: ${uploadResult?['error']}');
        setState(() {
          status = 'Upload failed. Please check your connection and try again.';
          _isUploading = false;
        });
        HapticFeedback.mediumImpact();
      }
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
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    if (minutes > 0) {
      return '${minutes.toString()}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '0:${seconds.toString().padLeft(2, '0')}';
    }
  }

  /// Format duration for short display (e.g., "1:23" or "0:45")
  String _formatShortDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Shows image in full screen viewer
  Future<void> _showFullScreenImage(String cid, String fileName) async {
    try {
      // Check cache first
      Uint8List? imageBytes;

      if (_fileCache.containsKey(cid) && _fileCache[cid] != null) {
        // Use cached image
        imageBytes = _fileCache[cid]!;
        print('✅ [FullScreen] Using cached image: $cid');
      } else {
        // Download if not cached
        setState(() {
          status = 'Loading image...';
        });
        imageBytes = await _getCachedFile(cid);
      }

      if (imageBytes != null && mounted) {
        setState(() {
          status = '';
        });

        // Show full screen image viewer
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => _FullScreenImageViewer(
              imageBytes: imageBytes!,
              fileName: fileName,
            ),
            fullscreenDialog: true,
          ),
        );
      } else {
        setState(() {
          status = 'Failed to load image';
        });
      }
    } catch (e) {
      setState(() {
        status = 'Error loading image: $e';
      });
    }
  }

  Future<void> downloadAndOpenFile(String cid, String fileName) async {
    try {
      // Check cache first
      Uint8List? fileBytes;

      if (_fileCache.containsKey(cid) && _fileCache[cid] != null) {
        // Use cached file
        fileBytes = _fileCache[cid]!;
        print('✅ [Download] Using cached file: $cid');
        setState(() {
          status = 'Opening file...';
        });
      } else {
        // Download if not cached
      setState(() {
        status = 'Downloading file...';
      });
        fileBytes = await _getCachedFile(cid);
      }
      
      if (fileBytes != null) {
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/$fileName';

        // Write file to local storage
        final file = File(filePath);
        await file.writeAsBytes(fileBytes);

      setState(() {
        status = 'File downloaded. Opening...';
      });
        
      await OpenFile.open(filePath);
      setState(() {
        status = '';
      });
      } else {
        setState(() {
          status = 'Failed to download file from server';
        });
      }
    } catch (e) {
      setState(() {
        status = 'Error downloading/opening file: $e';
      });
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
    if (_inviterAddress == null) {
      _inviterAddress = await OrbitDBService.getInviterAddressForWorkspace(
          widget.workspaceName);
    }

    if (_inviterAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load channel information'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Ensure user address is loaded
    if (userAddress == null) {
      await _loadUserAddress();
    }

    final members = await OrbitDBService.getWorkspaceMembers(
      inviterAddress: _inviterAddress!,
      workspaceName: widget.workspaceName,
    );

    // Ensure current logged-in user is in the members list
    if (userAddress != null) {
      final userKey = userAddress!.toLowerCase().trim();
      final userExists = members
          .any((m) => m['memberAddress']?.toString().toLowerCase() == userKey);

      if (!userExists) {
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

  Widget _buildMessageTile(Map<String, dynamic> message,
      {required bool isSent}) {
    final timestamp = _formatTimestamp(message['timestamp']);

    // Priority: If type is explicitly set, use it. Otherwise, infer from extension.
    // If type is 'file', always treat as file regardless of extension
    final messageType = message['type']?.toString();
    final isFile = messageType == 'file';
    final isImage = !isFile &&
        (messageType == 'image' ||
            (message['fileName'] != null &&
                (message['fileName']
                        .toString()
                        .toLowerCase()
                        .endsWith('.jpg') ||
                    message['fileName']
                        .toString()
                        .toLowerCase()
                        .endsWith('.jpeg') ||
                    message['fileName']
                        .toString()
                        .toLowerCase()
                        .endsWith('.png') ||
                    message['fileName']
                        .toString()
                        .toLowerCase()
                        .endsWith('.gif') ||
                    message['fileName']
                        .toString()
                        .toLowerCase()
                        .endsWith('.webp'))));
    final isVideo = !isFile &&
        !isImage &&
        (messageType == 'video' ||
            (message['fileName'] != null &&
                (message['fileName']
                        .toString()
                        .toLowerCase()
                        .endsWith('.mp4') ||
                    message['fileName']
                        .toString()
                        .toLowerCase()
                        .endsWith('.mov') ||
                    message['fileName']
                        .toString()
                        .toLowerCase()
                        .endsWith('.avi') ||
                    message['fileName']
                        .toString()
                        .toLowerCase()
                        .endsWith('.mkv') ||
                    message['fileName']
                        .toString()
                        .toLowerCase()
                        .endsWith('.webm') ||
                    message['fileName']
                        .toString()
                        .toLowerCase()
                        .endsWith('.3gp') ||
                    message['fileName']
                        .toString()
                        .toLowerCase()
                        .endsWith('.m4v'))));
    final isAudio = messageType == 'audio' ||
        (message['fileName'] != null &&
            (message['fileName'].toString().toLowerCase().endsWith('.m4a') ||
                message['fileName'].toString().toLowerCase().endsWith('.mp3') ||
                message['fileName'].toString().toLowerCase().endsWith('.wav') ||
                message['fileName'].toString().toLowerCase().endsWith('.aac')));

    // Fallback: if no type is set and it has cid, treat as file
    final isFileFallback = !isFile &&
        !isImage &&
        !isVideo &&
        !isAudio &&
        (message['fileName'] != null && message['cid'] != null);

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
                    message['cid'] ?? message['fileCid'],
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
                              const Icon(
                                Icons.done_all_sharp,
                                color: Color(0xFF0F365F),
                                size: 16,
                              ),
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
                    message['cid'] ?? message['fileCid'],
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
                              const Icon(
                                Icons.done_all_sharp,
                                color: Colors.white,
                                size: 16,
                              ),
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
                  final audioId = message['cid'] ?? message['fileCid'] ?? '';
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
                                          (message['cid'] ?? message['fileCid'])
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
                                                  message['fileCid'])
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
                                const Icon(
                                  Icons.done_all,
                                  color: Color(0xFF0F365F),
                                  size: 16,
                    ),
                  ],
                ),
                          ],
                        ),
                        // Progress bar for playing audio
                        if (_playingAudioId ==
                                (message['cid'] ?? message['fileCid']) &&
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
                            const Icon(
                              Icons.done_all,
                              color: Color(0xFF0F365F),
                              size: 16,
                              ),
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
                          message['cid'] ?? message['fileCid'],
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
                                      message['cid'] ?? message['fileCid'];

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
                              message['cid'] ?? message['fileCid'],
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
                                    message['cid'] ?? message['fileCid'] ?? '';
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
                                                            message['fileCid'])
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
                                                                    'fileCid'])
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
                                                  message['fileCid']) &&
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
                                        message['cid'] ?? message['fileCid'],
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

  String _formatTimestamp(DateTime timestamp) {
    final hour = timestamp.hour;
    final minute = timestamp.minute;
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
    _loadChannelInfo();
  }

  Future<void> _loadChannelInfo() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load inviter address
      _inviterAddress = await OrbitDBService.getInviterAddressForWorkspace(
          widget.workspaceName);

      if (_inviterAddress != null) {
        // Load members
        final members = await OrbitDBService.getWorkspaceMembers(
          inviterAddress: _inviterAddress!,
          workspaceName: widget.workspaceName,
        );

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
      final messages = await OrbitDBService.getChannelMessages(
          widget.workspaceName, widget.channelName);

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
      final key = widget.userAddress!.toLowerCase().trim();
      final dbName = 'profile_$key';
      final dbAddress = await OrbitDBService.getExistingDatabaseAddress(dbName);
      if (dbAddress != null) {
        final messages = await OrbitDBService.getMessages(dbAddress);
        for (var message in messages) {
          if (message['type'] == 'profile' &&
              message['userAddress'] == key) {
            return message['username'];
          }
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<String?> _getProfileNameForAddress(String address) async {
    try {
      final key = address.toLowerCase().trim();
      final dbName = 'profile_$key';
      var dbAddress = await OrbitDBService.getExistingDatabaseAddress(dbName);
      if (dbAddress == null) {
        dbAddress = await OrbitDBService.createChatDB(dbName);
        if (dbAddress == null) return null;
      }
      final messages = await OrbitDBService.getMessages(dbAddress);
      for (var message in messages) {
        if (message['type'] == 'profile' &&
            message['userAddress']?.toString().toLowerCase() == key) {
          return message['username']?.toString();
        }
      }
      return null;
    } catch (e) {
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
        _inviterAddress = await OrbitDBService.getInviterAddressForWorkspace(
            widget.workspaceName);
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
      final workspaceDbName = 'workspace_$_inviterAddress';
      final workspaceDbAddress = await OrbitDBService.getExistingDatabaseAddress(workspaceDbName);
      
      if (workspaceDbAddress != null) {
        // Add updated channel message (this will be the latest one)
        final updatedChannelMessage = {
          'type': 'channel',
          'workspaceName': widget.workspaceName,
          'channelName': newName, // New name
          'originalChannelName': originalDbName, // Keep original for DB operations
          'createdBy': widget.userAddress?.toLowerCase().trim() ?? '',
          'inviterAddress': _inviterAddress,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };
        
        final channelUpdateSuccess = await OrbitDBService.addMessage(
          workspaceDbAddress,
          updatedChannelMessage,
        );
        
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
        
        await OrbitDBService.addMessage(workspaceDbAddress, renameMessage);
      }
      
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
      final channelMetadataSuccess = await OrbitDBService.addChannelMessage(
        widget.workspaceName,
        originalDbName, // Always use original DB name
        channelMetadata,
      );
      
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
        _inviterAddress = await OrbitDBService.getInviterAddressForWorkspace(
            widget.workspaceName);
      }
      
      if (_inviterAddress == null) {
        throw Exception('Could not find workspace inviter address');
      }
      
      // Use the original channel name from widget (this is the database name)
      final originalDbName = widget.channelName;
      final displayName = _currentChannelName;
      
      print('🗑️ [DeleteChannel] Deleting channel: "$originalDbName" (display: "$displayName")');
      
      // 1. Add channel_delete message to workspace database
      final workspaceDbName = 'workspace_$_inviterAddress';
      final workspaceDbAddress = await OrbitDBService.getExistingDatabaseAddress(workspaceDbName);
      
      if (workspaceDbAddress != null) {
        final deleteMessage = {
          'type': 'channel_delete',
          'workspaceName': widget.workspaceName,
          'channelName': originalDbName, // Original database name
          'deletedChannelName': displayName, // Display name for reference
          'deletedBy': widget.userAddress?.toLowerCase().trim() ?? '',
          'inviterAddress': _inviterAddress,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };
        
        final deleteSuccess = await OrbitDBService.addMessage(
          workspaceDbAddress,
          deleteMessage,
        );
        
        if (deleteSuccess == null) {
          print('⚠️ Warning: Could not add delete message to workspace database');
        } else {
          print('✅ Delete message added to workspace database');
        }
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
      await OrbitDBService.addChannelMessage(
        widget.workspaceName,
        originalDbName,
        channelMetadata,
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
      print('❌ Error deleting channel: $e');
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
                future: OrbitDBService.downloadFile(cid),
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
      final imageBytes = await OrbitDBService.downloadFile(cid);
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
      final fileBytes = await OrbitDBService.downloadFile(cid);
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
