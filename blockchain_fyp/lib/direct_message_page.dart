import 'package:blockchain_fyp/workspace_home_page.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/distributed_service.dart';
import 'services/session_service.dart';
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

  @override
  void initState() {
    super.initState();
    _loadUserNameAndMessages();
    _textListener = () {
      setState(() {
        _hasText = _messageController.text.trim().isNotEmpty;
      });
    };
    _messageController.addListener(_textListener);
  }

  @override
  void dispose() {
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

  Future<void> _checkForNewMessages() async {
    try {
      if (userAddress == null) {
        await _loadUserAddress();
      }
      if (userAddress == null) return;

      List<Map<String, dynamic>> loaded = await DistributedService.getDirectMessages(
        user1Address: userAddress!,
        user2Address: widget.memberAddress,
      );

      for (var msg in loaded) {
        if (msg['timestamp'] is String) {
          msg['timestamp'] = DateTime.tryParse(msg['timestamp']) ?? DateTime.now();
        } else if (msg['timestamp'] is int) {
          msg['timestamp'] = DateTime.fromMillisecondsSinceEpoch(msg['timestamp']);
        }
      }

      if (loaded.length != _messages.length) {
        setState(() {
          _messages.clear();
          _messages.addAll(loaded);
        });
        // _preloadMediaFiles(loaded);
      }
    } catch (e) {
      print('❌ Error checking for new messages: $e');
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
      
      final profile = await DistributedService.getUserProfile(userAddress!);
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
    try {
      if (userAddress == null) {
        await _loadUserAddress();
      }
      if (userAddress == null) {
        setState(() {
          status = 'User address not found';
        });
        return;
      }

      List<Map<String, dynamic>> loaded = await DistributedService.getDirectMessages(
        user1Address: userAddress!,
        user2Address: widget.memberAddress,
      );
      
      for (var msg in loaded) {
        if (msg['timestamp'] is String) {
          msg['timestamp'] = DateTime.tryParse(msg['timestamp']) ?? DateTime.now();
        } else if (msg['timestamp'] is int) {
          msg['timestamp'] = DateTime.fromMillisecondsSinceEpoch(msg['timestamp']);
        }
      }
      
      setState(() {
        _messages.clear();
        _messages.addAll(loaded);
      });

      // _preloadMediaFiles(loaded);
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
        _getCachedFile(cid).catchError((e) => print('Preload error: $e'));
      }
    }
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isNotEmpty) {
      if (userAddress == null) {
        await _loadUserAddress();
      }
      if (userAddress == null) return;
      
      final msg = {
        'type': 'text',
        'content': _messageController.text.trim(),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'senderName': currentUserName,
        'sender': currentUserName,
        'userAddress': userAddress ?? '',
      };
      
      setState(() {
        _messages.add({
          ...msg,
          'timestamp': DateTime.now(),
        });
      });
      
      final messageText = _messageController.text.trim();
      _messageController.clear();
      
      // Get node ID first
      final nodeId = await DistributedService.getFirstNodeId();
      if (nodeId == null) {
        setState(() {
          _messages.removeLast();
          status = 'No node available. Please check backend connection.';
        });
        return;
      }
      
      final messageId = await DistributedService.addMessage(
        workspaceId: widget.workspaceName,
        senderAddress: userAddress!,
        receiverAddress: widget.memberAddress,
        messageText: messageText,
      );
      
      if (messageId == null) {
        setState(() {
          _messages.removeLast();
          status = 'Failed to send message';
        });
      }
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

