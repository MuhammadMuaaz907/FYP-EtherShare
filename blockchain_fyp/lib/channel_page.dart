import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:get_it/get_it.dart';
import 'services/ipfs_service.dart';
import 'services/orbitdb_service.dart';
import 'package:dio/dio.dart';
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

  Future<void> uploadFile() async {
    try {
      // Pick a file
      FilePickerResult? result = await FilePicker.platform.pickFiles();
      if (result != null) {
        File file = File(result.files.single.path!);
        // Upload to IPFS
        String cid = await ipfsService.uploadFileToIPFS(file);
        if (cid.isNotEmpty) {
          // Pin the file
          await ipfsService.pinFile(cid);
          // Create OrbitDB database
          String dbAddress = await orbitDBService.createDatabase('file-metadata-${DateTime.now().millisecondsSinceEpoch}');
          // Store CID in OrbitDB
          bool success = await orbitDBService.addData(dbAddress, 'file-cid', cid);
          
          if (success) {
            // Add file message to the channel
            setState(() {
              _messages.add({
                'type': 'file',
                'content': 'File uploaded! CID: $cid',
                'timestamp': DateTime.now(),
                'fileName': result.files.single.name,
                'cid': cid,
              });
              status = 'File uploaded successfully!';
            });
          } else {
            setState(() {
              status = 'Failed to store in OrbitDB';
            });
          }
        } else {
          setState(() {
            status = 'Failed to upload to IPFS';
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

  void _sendMessage() {
    if (_messageController.text.trim().isNotEmpty) {
      setState(() {
        _messages.add({
          'type': 'text',
          'content': _messageController.text.trim(),
          'timestamp': DateTime.now(),
        });
      });
      _messageController.clear();
    }
  }

  Future<void> downloadAndOpenFile(String cid, String fileName) async {
    try {
      setState(() {
        status = 'Downloading file...';
      });
      // Use a public IPFS gateway or your own node
      final url = 'https://ipfs.io/ipfs/$cid';
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/$fileName';

      final dio = Dio();
      await dio.download(url, filePath);

      setState(() {
        status = 'File downloaded. Opening...';
      });
      await OpenFile.open(filePath);
      setState(() {
        status = '';
      });
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
                    const Text(
                      'User',
                      style: TextStyle(
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
                if (message['type'] == 'file')
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