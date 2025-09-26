import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:get_it/get_it.dart';
import 'services/ipfs_service.dart';
import 'services/orbitdb_service.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

class ChannelPage extends StatefulWidget {
  final String channelName;
  final String workspaceName;
  
  const ChannelPage({super.key, required this.channelName, required this.workspaceName});

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

  @override
  void initState() {
    super.initState();
    _loadUserNameAndMessages();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload messages when returning to this page
    _loadMessages();
  }

  Future<void> _loadUserNameAndMessages() async {
    // Load user name from OrbitDB instead of SharedPreferences
    try {
      // Get user address from workspace context (you might need to pass this as parameter)
      // For now, using a default approach
      currentUserName = await _getUserNameFromOrbitDB() ?? 'User';
    } catch (_) {
      currentUserName = 'User';
    }
    await _loadMessages();
  }

  Future<String?> _getUserNameFromOrbitDB() async {
    try {
      // This is a simplified approach - in real implementation, you'd need to pass user address
      // For now, we'll use a default user address or get it from context
      final userAddress = '0xc79d923c6b52b62c2b77de6ce9d1e434e3b3fe99'; // This should be passed as parameter
      final key = userAddress.toLowerCase().trim();
      final dbName = 'profile_$key';
      final dbAddress = await OrbitDBService.createChatDB(dbName);
      
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

  Future<void> _loadMessages() async {
    try {
      List<Map<String, dynamic>> loaded = await OrbitDBService.getChannelMessages(widget.workspaceName, widget.channelName);
      
      // Debug: Print loaded messages to see their structure
      print('📨 Loaded ${loaded.length} messages:');
      for (var msg in loaded) {
        print('  - Type: ${msg['type']}, Content: ${msg['content']}, FileName: ${msg['fileName']}');
      }
      
    // Parse timestamps back to DateTime
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
    } catch (e) {
      print('❌ Error loading messages: $e');
      setState(() {
        status = 'Failed to load messages: $e';
      });
    }
  }

  Future<void> uploadFile() async {
    try {
      // Pick a file
      FilePickerResult? result = await FilePicker.platform.pickFiles();
      if (result != null) {
        File file = File(result.files.single.path!);
        Uint8List fileBytes = await file.readAsBytes();
        
        // Upload file using OrbitDB service (which uses server)
        final uploadResult = await OrbitDBService.uploadFile(
          widget.workspaceName, 
          result.files.single.name, 
          fileBytes
        );
        
        if (uploadResult != null && uploadResult['success'] == true) {
            final msg = {
              'type': 'file',
            'content': 'File uploaded successfully!',
            'timestamp': DateTime.now().millisecondsSinceEpoch, // Use milliseconds for consistency
              'fileName': result.files.single.name,
            'cid': uploadResult['fileCid'],
              'senderName': currentUserName,
            'workspace': widget.workspaceName,
            'channel': widget.channelName,
            };
          
          // Add to local state immediately
            setState(() {
              _messages.add({
                ...msg,
                'timestamp': DateTime.now(),
              });
              status = 'File uploaded successfully!';
            });
          
            // Save to OrbitDB
          final success = await OrbitDBService.addChannelMessage(widget.workspaceName, widget.channelName, msg);
          if (!success) {
            // If save failed, remove from local state
            setState(() {
              _messages.removeLast();
              status = 'Failed to save file message';
            });
          }
        } else {
          setState(() {
            status = 'Failed to upload file to server';
          });
        }
      } else {
        setState(() {
          status = 'No file selected';
        });
      }
    } catch (e) {
      setState(() {
        status = 'Error: $e';
      });
    }
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isNotEmpty) {
      final msg = {
        'type': 'text',
        'content': _messageController.text.trim(),
        'timestamp': DateTime.now().millisecondsSinceEpoch, // Use milliseconds for consistency
        'senderName': currentUserName,
        'workspace': widget.workspaceName,
        'channel': widget.channelName,
      };
      
      // Add to local state immediately for UI responsiveness
      setState(() {
        _messages.add({
          ...msg,
          'timestamp': DateTime.now(),
        });
      });
      
      _messageController.clear();
      
      // Save to OrbitDB
      final success = await OrbitDBService.addChannelMessage(widget.workspaceName, widget.channelName, msg);
      if (!success) {
        // If save failed, remove from local state
        setState(() {
          _messages.removeLast();
        });
        setState(() {
          status = 'Failed to send message';
        });
      }
    }
  }

  Future<void> downloadAndOpenFile(String cid, String fileName) async {
    try {
      setState(() {
        status = 'Downloading file...';
      });
      
      // Download file using OrbitDB service (which uses server)
      final fileBytes = await OrbitDBService.downloadFile(cid);
      
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
    return Scaffold(
      backgroundColor: const Color(0xFF1A2236),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF4F0E5E), Color(0xFF350D36)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '# ${widget.channelName}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    widget.workspaceName,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.info_outline, color: Colors.white),
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Status message
          if (status.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              color: status.contains('Error') || status.contains('Failed') 
                  ? Colors.red.withOpacity(0.1) 
                  : Colors.green.withOpacity(0.1),
              child: Text(
                status,
                style: TextStyle(
                  color: status.contains('Error') || status.contains('Failed') 
                      ? Colors.red[300] 
                      : Colors.green[300],
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
                          color: Colors.white54,
                          size: 64,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No messages yet',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Start the conversation!',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      return _buildMessageTile(message);
                    },
                  ),
          ),
          
          // Input area
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF232B3E),
              border: Border(
                top: BorderSide(color: Color(0xFF3A3140)),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file, color: Colors.white54),
                  onPressed: uploadFile,
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2236),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: TextField(
                      controller: _messageController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Message #${widget.channelName}',
                        hintStyle: const TextStyle(color: Colors.white54),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send, color: Color(0xFF4F0E5E)),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageTile(Map<String, dynamic> message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF4F0E5E),
            radius: 16,
            child: const Icon(Icons.person, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      message['senderName'] ?? 'User',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatTimestamp(message['timestamp']),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (message['type'] == 'file' || (message['fileName'] != null && message['cid'] != null))
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF232B3E),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.file_present, color: Color(0xFF4F0E5E)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                message['fileName'] ?? 'File',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                'CID: ${message['cid']}',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.download, color: Color(0xFF4F0E5E)),
                          onPressed: () {
                            downloadAndOpenFile(message['cid'], message['fileName']);
                          },
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF232B3E),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      message['content'],
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }
} 