// Real OrbitDB implementation with P2P messaging
// Files are handled by real IPFS implementation
// Messages are handled by real OrbitDB with Helia IPFS

import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'ipfs_service.dart';

class OrbitDBService {
  // MethodChannel for communicating with Node.js bridge
  static const MethodChannel _channel = MethodChannel('orbitdb_channel');

  // Legacy properties for backward compatibility
  static const String workspaceDbName = 'workspaces';
  static String workspaceDbAddress = 'placeholder://workspace-address';
  
  // Stream controllers for real-time updates
  static final Map<String, StreamController<List<Map<String, dynamic>>>> _messageStreams = {};
  
  // Store database addresses for consistency
  static final Map<String, String> _databaseAddresses = {};
  
  // Load database addresses from persistent storage
  static Future<void> _loadDatabaseAddresses() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final addressesJson = prefs.getString('database_addresses');
      if (addressesJson != null) {
        final Map<String, dynamic> addresses = jsonDecode(addressesJson);
        _databaseAddresses.clear();
        addresses.forEach((key, value) {
          _databaseAddresses[key] = value.toString();
        });
        print('📌 Loaded ${_databaseAddresses.length} database addresses from storage:');
        _databaseAddresses.forEach((key, value) {
          print('  - $key: $value');
        });
      } else {
        print('📌 No database addresses found in storage');
      }
    } catch (e) {
      print('❌ Error loading database addresses: $e');
    }
  }
  
  // Save database addresses to persistent storage
  static Future<void> _saveDatabaseAddresses() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final addressesJson = jsonEncode(_databaseAddresses);
      await prefs.setString('database_addresses', addressesJson);
      print('💾 Saved ${_databaseAddresses.length} database addresses to storage');
    } catch (e) {
      print('❌ Error saving database addresses: $e');
    }
  }
  
  // Clear database cache (useful for testing or when switching users)
  static void clearDatabaseCache() {
    _databaseAddresses.clear();
    print('🧹 Database cache cleared');
  }
  
  // Save login session to persistent storage
  static Future<void> saveLoginSession(String userAddress, String workspaceName, String channelName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', true);
      await prefs.setString('userAddress', userAddress);
      await prefs.setString('workspaceName', workspaceName);
      await prefs.setString('channelName', channelName);
      print('💾 Login session saved: $userAddress');
    } catch (e) {
      print('❌ Error saving login session: $e');
    }
  }
  
  // Clear login session
  static Future<void> clearLoginSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('isLoggedIn');
      await prefs.remove('userAddress');
      await prefs.remove('workspaceName');
      await prefs.remove('channelName');
      print('🧹 Login session cleared');
    } catch (e) {
      print('❌ Error clearing login session: $e');
    }
  }
  
  // Check if user is logged in
  static Future<Map<String, String?>> getLoginSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
      
      if (isLoggedIn) {
        return {
          'isLoggedIn': 'true',
          'userAddress': prefs.getString('userAddress'),
          'workspaceName': prefs.getString('workspaceName'),
          'channelName': prefs.getString('channelName'),
        };
      }
      return {'isLoggedIn': 'false'};
    } catch (e) {
      print('❌ Error getting login session: $e');
      return {'isLoggedIn': 'false'};
    }
  }
  
  // Initialize OrbitDB Bridge
  static Future<Map<String, dynamic>> initOrbitDB() async {
    try {
      print('🚀 Initializing OrbitDB Bridge...');
      
      // Load existing database addresses
      await _loadDatabaseAddresses();
      
      final result = await _channel.invokeMethod('initOrbitDB');
      
      // Fix type casting issue
      Map<String, dynamic> resultMap;
      if (result is Map<String, dynamic>) {
        resultMap = result;
      } else if (result is Map) {
        resultMap = Map<String, dynamic>.from(result);
      } else {
        resultMap = {'success': false, 'error': 'Invalid result type'};
      }
      
      if (resultMap['success'] == true) {
        print('✅ OrbitDB Bridge initialized successfully');
        print('📊 Helia ID: ${resultMap['heliaId']}');
        print('📊 OrbitDB ID: ${resultMap['orbitdbId']}');
      } else {
        print('❌ OrbitDB Bridge initialization failed: ${resultMap['error']}');
      }
      
      return resultMap;
    } catch (e) {
      print('❌ Error initializing OrbitDB Bridge: $e');
      return {
        'success': false,
        'error': e.toString()
      };
    }
  }
  
  // Create a chat database
  static Future<String?> createChatDB(String name) async {
    try {
      print('📁 Creating chat database: $name');
      
      // Check if we already have this database
      if (_databaseAddresses.containsKey(name)) {
        print('📌 Using existing database address: ${_databaseAddresses[name]}');
        return _databaseAddresses[name];
      }
      
      final result = await _channel.invokeMethod('createChatDB', {'dbName': name});
      
      if (result['success'] == true) {
        print('✅ Chat database created: ${result['address']}');
        // Store the address for future use
        _databaseAddresses[name] = result['address'];
        // Save to persistent storage
        await _saveDatabaseAddresses();
        return result['address'];
      } else {
        print('❌ Failed to create chat database: ${result['error']}');
        return null;
      }
    } catch (e) {
      print('❌ Error creating chat database: $e');
      return null;
    }
  }

  // Get consistent database address for a given name
  static Future<String?> getConsistentDatabaseAddress(String name) async {
    try {
      // First check if we have this database in our cache
      if (_databaseAddresses.containsKey(name)) {
        print('📌 Found cached database address: ${_databaseAddresses[name]}');
        return _databaseAddresses[name];
      }
      
      // If not in cache, try to create/get the database
      final result = await _channel.invokeMethod('createChatDB', {'dbName': name});
      
      if (result['success'] == true) {
        print('📌 Database created/found: ${result['address']}');
        // Store the address for future use
        _databaseAddresses[name] = result['address'];
        return result['address'];
      } else {
        print('❌ Database not found: $name');
        return null;
      }
    } catch (e) {
      print('❌ Error getting consistent database address: $e');
      return null;
    }
  }

  // Check if database exists and get its address
  static Future<String?> getExistingDatabaseAddress(String name) async {
    try {
      // First check if we have this database in our cache
      if (_databaseAddresses.containsKey(name)) {
        print('📌 Found cached database address: ${_databaseAddresses[name]}');
        return _databaseAddresses[name];
      }
      
      // If not in cache, try to create/get the database
      final result = await _channel.invokeMethod('createChatDB', {'dbName': name});
      
      if (result['success'] == true) {
        print('📌 Database created/found: ${result['address']}');
        // Store the address for future use
        _databaseAddresses[name] = result['address'];
        // Save to persistent storage
        await _saveDatabaseAddresses();
        return result['address'];
      } else {
        print('❌ Database not found: $name');
        return null;
      }
    } catch (e) {
      print('❌ Error getting existing database: $e');
      return null;
    }
  }

  // Add a message to chat database
  static Future<String?> addMessage(String address, Map<String, dynamic> message) async {
    try {
      print('💬 Adding message to database: $address');
      
      final result = await _channel.invokeMethod('addMessage', {
        'address': address,
        'msgObj': message
      });
      
      if (result['success'] == true) {
        print('✅ Message added with hash: ${result['hash']}');
        return result['hash'];
      } else {
        print('❌ Failed to add message: ${result['error']}');
        return null;
      }
    } catch (e) {
      print('❌ Error adding message: $e');
      return null;
    }
  }

  // Get all messages from chat database
  static Future<List<Map<String, dynamic>>> getMessages(String address) async {
    try {
      print('📨 Getting messages from database: $address');
      
      final result = await _channel.invokeMethod('getMessages', {'address': address});
      
      if (result['success'] == true) {
        // Fix type casting issue
        final messagesList = result['messages'] as List<dynamic>? ?? [];
        final messages = messagesList.map((msg) {
          if (msg is Map<String, dynamic>) {
            return msg;
          } else if (msg is Map) {
            // Convert Map<Object?, Object?> to Map<String, dynamic>
            return Map<String, dynamic>.from(msg);
          } else {
            return <String, dynamic>{};
          }
        }).toList();
        
        print('✅ Retrieved ${messages.length} messages');
        return messages;
      } else {
        print('❌ Failed to get messages: ${result['error']}');
        return [];
      }
    } catch (e) {
      print('❌ Error getting messages: $e');
      return [];
    }
  }

  // Get real-time message stream
  static Stream<List<Map<String, dynamic>>> getMessagesStream(String address) {
    if (!_messageStreams.containsKey(address)) {
      _messageStreams[address] = StreamController<List<Map<String, dynamic>>>.broadcast();
      
      // Set up real-time updates
      _setupRealTimeUpdates(address);
    }
    
    return _messageStreams[address]!.stream;
  }
  
  // Set up real-time updates for a database
  static Future<void> _setupRealTimeUpdates(String address) async {
    try {
      print('🔄 Setting up real-time updates for: $address');
      
      // Set up the callback for real-time updates
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onMessageUpdate' && call.arguments['address'] == address) {
          final newMessage = Map<String, dynamic>.from(call.arguments['message']);
          
          // Get current messages and add the new one
          final currentMessages = await getMessages(address);
          currentMessages.add(newMessage);
          
          // Emit the updated messages
          _messageStreams[address]?.add(currentMessages);
        }
      });
      
      // Enable real-time updates on the bridge
      await _channel.invokeMethod('loadUpdates', {
        'address': address,
        'callback': true
      });
      
      print('✅ Real-time updates enabled for: $address');
    } catch (e) {
      print('❌ Error setting up real-time updates: $e');
    }
  }
  
  // Upload file to IPFS - Uses Android Bridge
  static Future<Map<String, dynamic>?> uploadFile(String workspaceId, String fileName, Uint8List fileData) async {
    try {
      final fileSizeMB = (fileData.length / 1024 / 1024).toStringAsFixed(2);
      print('📎 Uploading file via Android Bridge: $fileName (${fileSizeMB} MB)');
      
      // Create a temporary file to upload
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(fileData);
      
      // Use IPFS service for file upload (with fallback mechanism)
      final ipfsService = IPFSService();
      final cid = await ipfsService.uploadFileToIPFS(tempFile);
      
      // Clean up temp file
      try {
        await tempFile.delete();
      } catch (e) {
        print('⚠️ Could not delete temp file: $e');
      }
      
      if (cid.isNotEmpty) {
        print('✅ File uploaded to IPFS successfully. CID: $cid');
        
        // Optionally pin the file (non-blocking)
        ipfsService.pinFile(cid).catchError((e) {
          print('⚠️ Could not pin file (non-critical): $e');
        });
        
        // Store file reference in OrbitDB
        final fileMessage = {
          'type': 'file',
          'fileName': fileName,
          'fileCid': cid,
          'fileSize': fileData.length,
          'workspaceId': workspaceId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };
        
        // Add to workspace database
        final dbName = 'workspace_$workspaceId';
        final address = await createChatDB(dbName);
        if (address != null) {
          await addMessage(address, fileMessage);
          print('✅ File reference saved to OrbitDB');
        } else {
          print('⚠️ Could not save file reference to OrbitDB (database not found)');
        }
        
        return {
          'success': true,
          'fileName': fileName,
          'fileSize': fileData.length,
          'fileCid': cid,
          'messageId': 'msg_${DateTime.now().millisecondsSinceEpoch}'
        };
      } else {
        print('❌ File upload failed - no CID returned');
        return {
          'success': false,
          'error': 'IPFS upload failed. Please check IPFS connection.',
        };
      }
    } catch (e) {
      print('❌ Error uploading file: $e');
      return {
        'success': false,
        'error': 'Upload error: $e',
      };
    }
  }

  // Download file from IPFS - Uses real IPFS service with fallback mechanism
  static Future<Uint8List?> downloadFile(String cid) async {
    // Fallback URLs in order of preference (matching IPFS Desktop config)
    // Gateway: http://127.0.0.1:8081 (from IPFS Desktop config)
    // Public Gateways: https://dweb.link and https://ipfs.io (from IPFS Desktop config)
    final List<String> gatewayUrls = [
      'http://127.0.0.1:8081/ipfs/',      // Primary: Local IPFS Desktop gateway (localhost) - from config
      'http://192.168.0.39:8081/ipfs/',   // Fallback: Local IPFS Desktop gateway (network IP)
      'https://dweb.link/ipfs/',          // Public gateway 1 (from IPFS Desktop config - fast)
      'https://ipfs.io/ipfs/',            // Public gateway 2 (from IPFS Desktop config - reliable)
      'https://gateway.pinata.cloud/ipfs/', // Public gateway 3 (backup)
    ];
    
    for (int i = 0; i < gatewayUrls.length; i++) {
      try {
        final url = '${gatewayUrls[i]}$cid';
        print('📥 Downloading file from IPFS (Attempt ${i + 1}): $url');
        
        final response = await http.get(
          Uri.parse(url),
          headers: {
            'User-Agent': 'EtherShare-Mobile/1.0',
          },
        ).timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw Exception('Request timeout');
          },
        );
        
        if (response.statusCode == 200) {
          print('✅ File downloaded successfully from ${gatewayUrls[i]}');
          return response.bodyBytes;
        } else {
          print('❌ Failed to download from ${gatewayUrls[i]}: HTTP ${response.statusCode}');
        }
      } catch (e) {
        print('❌ Error downloading from ${gatewayUrls[i]}: $e');
        // Continue to next gateway
      }
    }
    
    print('❌ All gateways failed to download file: $cid');
    return null;
  }

  // Get status of OrbitDB Bridge
  static Future<Map<String, dynamic>> getStatus() async {
    try {
      final result = await _channel.invokeMethod('getStatus');
      return result;
    } catch (e) {
      print('❌ Error getting status: $e');
      return {
        'success': false,
        'error': e.toString()
      };
    }
  }

  // Stop OrbitDB Bridge
  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
      print('✅ OrbitDB Bridge stopped');
    } catch (e) {
      print('❌ Error stopping OrbitDB Bridge: $e');
    }
  }

  // =====================================================
  // LEGACY METHODS FOR BACKWARD COMPATIBILITY - PLACEHOLDERS
  // =====================================================

  // Helper to create the shared workspace DB - PLACEHOLDER
  Future<void> ensureWorkspaceDbExists() async {
    print('🔧 Ensure workspace DB exists placeholder');
  }

  // Helper to save workspace details for a user - Now uses real OrbitDB
  static Future<bool> saveWorkspaceForUser(String userAddress, String workspaceDetails) async {
    try {
      print('💾 Save workspace for user: $userAddress');
      
      // Create a workspace database for this user
      final dbName = 'workspace_$userAddress';
      final address = await createChatDB(dbName);
      
      if (address != null) {
        // Save workspace details as a message
        final workspaceMessage = {
          'type': 'workspace',
          'userAddress': userAddress,
          'workspaceDetails': workspaceDetails,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };
        
        print('📋 Workspace message: $workspaceMessage');
        final result = await addMessage(address, workspaceMessage);
        print('✅ Workspace saved with result: $result');
        return result != null;
      }
      
      return false;
    } catch (e) {
      print('❌ Error saving workspace for user: $e');
      return false;
    }
  }

  // Create a database (legacy) - PLACEHOLDER
  Future<String> createDatabase(String dbName, {String dbType = 'keyvalue'}) async {
    print('🗄️ Create database placeholder: $dbName');
    return 'placeholder://$dbName';
  }

  // Add data to a database (legacy) - PLACEHOLDER
  Future<bool> addData(String dbAddress, String key, String value) async {
    print('➕ Add data placeholder: $key');
    return false; // Not implemented
  }

  // Get data from database (legacy) - Now uses real OrbitDB
  static Future<String> getData(String dbAddress, String key) async {
    try {
      print('🔍 Get data: $key');
      
      // If it's a workspace database, get workspace details
      if (dbAddress.contains('workspace_')) {
        final messages = await getMessages(dbAddress);
        
        // Find workspace message for this key
        for (var message in messages) {
          if (message['type'] == 'workspace' && message['userAddress'] == key) {
            return message['workspaceDetails'] ?? '';
          }
        }
      }
      
      return ''; // Return empty string if not found
    } catch (e) {
      print('❌ Error getting data: $e');
      return '';
    }
  }

  // Store a message in a channel - Now uses real OrbitDB
  static Future<bool> addChannelMessage(String workspace, String channel, Map<String, dynamic> message) async {
    try {
      print('💬 Add channel message: $workspace/$channel');
      
      // Create a unique database name for this channel
      final dbName = 'chat_${workspace}_$channel';
      
      // Use the same consistent address as getChannelMessages
      final address = 'db_${dbName}_consistent';
      
      // Ensure database exists
      await createChatDB(dbName);
      
      // Add the message with channel and workspace info
      final messageWithChannel = {
        ...message,
        'channel': channel,
        'workspace': workspace,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final result = await addMessage(address, messageWithChannel);
      return result != null;
    } catch (e) {
      print('❌ Error adding channel message: $e');
      return false;
    }
  }

  // Retrieve all messages for a channel - Now uses real OrbitDB
  static Future<List<Map<String, dynamic>>> getChannelMessages(String workspace, String channel) async {
    try {
      print('📨 Get channel messages: $workspace/$channel');
      
      // Create the same database name as used in addChannelMessage
      final dbName = 'chat_${workspace}_$channel';
      
      // Use a consistent address based on the database name
      final address = 'db_${dbName}_consistent';
      
      // Check if database exists, if not create it
      final messages = await getMessages(address);
      
      // Convert timestamps back to DateTime objects for display
      for (var message in messages) {
        if (message['timestamp'] is int) {
          message['timestamp'] = DateTime.fromMillisecondsSinceEpoch(message['timestamp']);
        }
      }
      
      print('📨 Retrieved ${messages.length} messages for channel $channel');
      return messages;
    } catch (e) {
      print('❌ Error getting channel messages: $e');
      return [];
    }
  }

  // ============ WORKSPACE MEMBER MANAGEMENT ============

  /// Add a member to a workspace
  /// [inviterAddress] is the address of the workspace creator/inviter
  /// [memberAddress] is the address of the member being added
  /// [workspaceName] is the name of the workspace
  /// [memberDisplayName] is optional display name for the member
  static Future<bool> addWorkspaceMember({
    required String inviterAddress,
    required String memberAddress,
    required String workspaceName,
    String? memberDisplayName,
  }) async {
    try {
      print('👤 Adding member to workspace: $memberAddress');
      
      final inviterKey = inviterAddress.toLowerCase().trim();
      final memberKey = memberAddress.toLowerCase().trim();
      
      // Use the inviter's workspace database to store members
      final dbName = 'workspace_$inviterKey';
      final address = await createChatDB(dbName);
      
      if (address == null) {
        print('❌ Failed to get workspace database for inviter: $inviterKey');
        return false;
      }
      
      // Check if member already exists
      final existingMembers = await getWorkspaceMembers(
        inviterAddress: inviterAddress,
        workspaceName: workspaceName,
      );
      
      final memberExists = existingMembers.any((m) => 
        m['memberAddress']?.toString().toLowerCase() == memberKey
      );
      
      if (memberExists) {
        print('ℹ️ Member already exists in workspace');
        return true; // Already a member, return success
      }
      
      // Add member as a message
      final memberMessage = {
        'type': 'member',
        'workspaceName': workspaceName,
        'inviterAddress': inviterKey,
        'memberAddress': memberKey,
        'memberDisplayName': memberDisplayName,
        'joinedAt': DateTime.now().millisecondsSinceEpoch,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      
      final result = await addMessage(address, memberMessage);
      print('✅ Member added with result: $result');
      return result != null;
    } catch (e) {
      print('❌ Error adding workspace member: $e');
      return false;
    }
  }

  /// Get all members of a workspace
  /// [inviterAddress] is the address of the workspace creator/inviter
  /// [workspaceName] is the name of the workspace
  static Future<List<Map<String, dynamic>>> getWorkspaceMembers({
    required String inviterAddress,
    required String workspaceName,
  }) async {
    try {
      print('👥 Getting workspace members for: $workspaceName');
      
      final inviterKey = inviterAddress.toLowerCase().trim();
      final dbName = 'workspace_$inviterKey';
      final dbAddress = await getExistingDatabaseAddress(dbName);
      
      if (dbAddress == null) {
        print('❌ Workspace database not found: $dbName');
        return [];
      }
      
      final messages = await getMessages(dbAddress);
      final members = <Map<String, dynamic>>[];
      
      // Get all member messages for this workspace
      for (var message in messages) {
        if (message['type'] == 'member' && 
            message['workspaceName']?.toString().toLowerCase() == workspaceName.toLowerCase().trim()) {
          members.add(message);
        }
      }
      
      // Also include the inviter as a member if not already in the list
      final inviterExists = members.any((m) => 
        m['memberAddress']?.toString().toLowerCase() == inviterKey
      );
      
      if (!inviterExists) {
        // Try to get inviter's display name from profile
        String? inviterDisplayName;
        try {
          final profileDbName = 'profile_$inviterKey';
          final profileDbAddress = await getExistingDatabaseAddress(profileDbName);
          if (profileDbAddress != null) {
            final profileMessages = await getMessages(profileDbAddress);
            for (var msg in profileMessages) {
              if (msg['type'] == 'profile' && msg['userAddress']?.toString().toLowerCase() == inviterKey) {
                inviterDisplayName = msg['username']?.toString();
                break;
              }
            }
          }
        } catch (e) {
          print('⚠️ Could not fetch inviter profile: $e');
        }
        
        members.add({
          'type': 'member',
          'workspaceName': workspaceName,
          'inviterAddress': inviterKey,
          'memberAddress': inviterKey,
          'memberDisplayName': inviterDisplayName,
          'joinedAt': DateTime.now().millisecondsSinceEpoch,
          'isInviter': true,
        });
      }
      
      print('✅ Retrieved ${members.length} members for workspace: $workspaceName');
      return members;
    } catch (e) {
      print('❌ Error getting workspace members: $e');
      return [];
    }
  }

  /// Get member count for a workspace
  static Future<int> getWorkspaceMemberCount({
    required String inviterAddress,
    required String workspaceName,
  }) async {
    try {
      final members = await getWorkspaceMembers(
        inviterAddress: inviterAddress,
        workspaceName: workspaceName,
      );
      return members.length;
    } catch (e) {
      print('❌ Error getting workspace member count: $e');
      return 0;
    }
  }

  /// Get inviter address from workspace name
  /// This searches all workspace databases to find which inviter owns this workspace
  static Future<String?> getInviterAddressForWorkspace(String workspaceName) async {
    try {
      print('🔍 Finding inviter for workspace: $workspaceName');
      
      // Load all database addresses
      await _loadDatabaseAddresses();
      
      // Search through all workspace databases
      for (var entry in _databaseAddresses.entries) {
        if (entry.key.startsWith('workspace_')) {
          try {
            final messages = await getMessages(entry.value);
            for (var message in messages) {
              if (message['type'] == 'workspace') {
                final details = message['workspaceDetails'];
                Map<String, dynamic>? parsed;
                if (details is String) {
                  try {
                    parsed = jsonDecode(details) as Map<String, dynamic>;
                  } catch (_) {
                    continue;
                  }
                } else if (details is Map) {
                  parsed = Map<String, dynamic>.from(details);
                }
                
                if (parsed?['workspaceName']?.toString().toLowerCase() == workspaceName.toLowerCase().trim()) {
                  final inviterAddress = message['userAddress']?.toString();
                  if (inviterAddress != null) {
                    print('✅ Found inviter: $inviterAddress');
                    return inviterAddress;
                  }
                }
              }
            }
          } catch (e) {
            print('⚠️ Error checking database ${entry.key}: $e');
            continue;
          }
        }
      }
      
      print('❌ Inviter not found for workspace: $workspaceName');
      return null;
    } catch (e) {
      print('❌ Error finding inviter for workspace: $e');
      return null;
    }
  }
}