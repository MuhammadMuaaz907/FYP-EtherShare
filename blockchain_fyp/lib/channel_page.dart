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
  String? userAddress;
  int _memberCount = 0;
  bool _isLoadingMembers = false;
  String? _inviterAddress;

  @override
  void initState() {
    super.initState();
    _loadUserNameAndMessages();
    _loadWorkspaceMembers();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload messages when returning to this page
    _loadMessages();
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
      _inviterAddress = await OrbitDBService.getInviterAddressForWorkspace(widget.workspaceName);
      
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
        final userExists = members.any((m) => 
          m['memberAddress']?.toString().toLowerCase() == userKey
        );
        if (!userExists) {
          // User is not in the list, but they should be counted
          // The actual list will be updated when showing channel info
        }
      }

      setState(() {
        _memberCount = members.length + (userAddress != null && !members.any((m) => 
          m['memberAddress']?.toString().toLowerCase() == userAddress!.toLowerCase()
        ) ? 1 : 0);
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
        print('⚠️ [Channel] Profile database not found in cache, trying to create: $dbName');
        dbAddress = await OrbitDBService.createChatDB(dbName);
        if (dbAddress == null) {
          print('❌ [Channel] Could not create/find profile database for: $address');
          return null;
        }
      }
      
      print('📌 [Channel] Using profile database: $dbAddress');
      final messages = await OrbitDBService.getMessages(dbAddress);
      print('📨 [Channel] Retrieved ${messages.length} messages from profile database');
      
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
          final msgUserAddress = message['userAddress']?.toString().toLowerCase().trim();
          print('🔍 [Channel] Profile message userAddress: $msgUserAddress (looking for: $key)');
          
          if (msgUserAddress == key) {
            // Try multiple ways to get username
            dynamic usernameValue = message['username'];
            String? username;
            
            if (usernameValue != null) {
              username = usernameValue.toString().trim();
            }
            
            print('✅ [Channel] Found profile - Username value: $usernameValue, Username string: "$username" for address: $address');
            
            if (username != null && username.isNotEmpty) {
              print('✅ [Channel] Returning username: $username');
              return username;
            } else {
              print('⚠️ [Channel] Username is null or empty in profile for: $address');
              print('⚠️ [Channel] Username value type: ${usernameValue.runtimeType}');
            }
          } else {
            print('⚠️ [Channel] userAddress mismatch: expected=$key, got=$msgUserAddress');
          }
        } else {
          print('⚠️ [Channel] Message type is not profile: $msgType');
        }
      }
      
      print('⚠️ [Channel] No valid profile message found for address: $address');
      return null;
    } catch (e, stackTrace) {
      print('❌ [Channel] Error getting profile name for $address: $e');
      print('Stack trace: $stackTrace');
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
      // Ensure user address is loaded
      if (userAddress == null) {
        await _loadUserAddress();
      }
      
      setState(() {
        status = 'Selecting file...';
      });
      
      // Pick a file
      FilePickerResult? result = await FilePicker.platform.pickFiles();
      if (result != null) {
        File file = File(result.files.single.path!);
        final fileSize = await file.length();
        Uint8List fileBytes = await file.readAsBytes();
        
        setState(() {
          status = 'Uploading file... (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)';
        });
        
        print('📎 Starting file upload: ${result.files.single.name} (${fileSize} bytes)');
        print('📎 User info - Name: $currentUserName, Address: $userAddress');
        
        // Upload file using OrbitDB service (which uses IPFS)
        final uploadResult = await OrbitDBService.uploadFile(
          widget.workspaceName, 
          result.files.single.name, 
          fileBytes
        );
        
        if (uploadResult != null && uploadResult['success'] == true) {
          print('✅ File uploaded successfully. CID: ${uploadResult['fileCid']}');
          
          final msg = {
            'type': 'file',
            'content': 'File: ${result.files.single.name}',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'fileName': result.files.single.name,
            'fileSize': fileSize,
            'cid': uploadResult['fileCid'],
            'fileCid': uploadResult['fileCid'], // For compatibility
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
          final success = await OrbitDBService.addChannelMessage(widget.workspaceName, widget.channelName, msg);
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
          print('❌ File upload failed: ${uploadResult?['error'] ?? 'Unknown error'}');
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
        'timestamp': DateTime.now().millisecondsSinceEpoch, // Use milliseconds for consistency
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
      final success = await OrbitDBService.addChannelMessage(widget.workspaceName, widget.channelName, msg);
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
                if (_isLoadingMembers)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  )
                else if (_memberCount > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.people, color: Colors.white70, size: 18),
                          const SizedBox(width: 4),
                          Text(
                            '$_memberCount',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.info_outline, color: Colors.white),
                  onPressed: () {
                    _showChannelInfo();
                  },
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

  Future<void> _showChannelInfo() async {
    if (_inviterAddress == null) {
      _inviterAddress = await OrbitDBService.getInviterAddressForWorkspace(widget.workspaceName);
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
      final userExists = members.any((m) => 
        m['memberAddress']?.toString().toLowerCase() == userKey
      );

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
    print('🔄 [Channel] Fetching profile names for ${members.length} members...');
    
    // Create a copy of members list to avoid modification during iteration
    final updatedMembers = <Map<String, dynamic>>[];
    
    for (int i = 0; i < members.length; i++) {
      final member = Map<String, dynamic>.from(members[i]); // Create a copy
      final memberAddr = member['memberAddress']?.toString();
      if (memberAddr != null) {
        print('📝 [Channel] Processing member ${i + 1}/${members.length}: $memberAddr');
        
        // Always fetch profile name to ensure we have the latest
        final profileName = await _getProfileNameForAddress(memberAddr);
        
        if (profileName != null && profileName.isNotEmpty) {
          // Update display name with profile name (prefer profile name over stored display name)
          member['memberDisplayName'] = profileName;
          print('✅ [Channel] Updated member $memberAddr with name: $profileName');
        } else {
          // If no profile name found, check if we have a stored display name
          final storedName = member['memberDisplayName']?.toString();
          if (storedName == null || storedName.isEmpty) {
            print('⚠️ [Channel] No profile name found for member: $memberAddr (will use address)');
            // Clear any empty display name
            member.remove('memberDisplayName');
          } else {
            print('ℹ️ [Channel] Using stored display name for $memberAddr: $storedName');
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
      backgroundColor: const Color(0xFF232B3E),
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
                color: Colors.white24,
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
                          '# ${widget.channelName}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.workspaceName,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  const Icon(Icons.people, color: Colors.white70, size: 20),
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
                  ? const Center(
                      child: Text(
                        'No members found',
                        style: TextStyle(color: Colors.white54),
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
    final initial = nameForInitial.isNotEmpty ? nameForInitial[0].toUpperCase() : 'M';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: CircleAvatar(
        backgroundColor: isInviter ? const Color(0xFF23C16B) : Colors.white,
        radius: 20,
        child: Text(
          initial,
          style: TextStyle(
            color: isInviter ? Colors.white : const Color(0xFF4F0E5E),
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
            style: const TextStyle(color: Colors.white38, fontSize: 11),
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