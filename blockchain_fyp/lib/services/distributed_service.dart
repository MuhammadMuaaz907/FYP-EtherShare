import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Exception thrown when chain integrity is compromised
class ChainBrokenException implements Exception {
  final String message;
  final String? brokenAt;
  final Map<String, dynamic>? details;
  
  ChainBrokenException(this.message, [this.brokenAt, this.details]);
  
  @override
  String toString() => message;
}

/// Distributed System Service
/// Handles communication with distributed MongoDB backend via HTTP API
class DistributedService {
  // Host configuration for different platforms
  static const String emulatorHost = '10.0.2.2'; // Android Emulator
  static const String localHost = 'localhost'; // Desktop/Web
  static const String realDeviceHost = '192.168.0.35'; // Real Android Device - Your PC IP on local network
  
  // Port for backend server
  static const int backendPort = 3000;
  
  // Base URL for backend API
  static String get baseUrl {
    // If custom URL is set, use it
    if (_customBackendUrl != null) {
      return _customBackendUrl!;
    }
    
    // First, check if BACKEND_URL is set in .env
    final envUrl = dotenv.env['BACKEND_URL'];
    if (envUrl != null && envUrl.isNotEmpty) {
      return envUrl;
    }
    
    // Auto-detect platform and use appropriate host
    if (kIsWeb) {
      // Web platform - use localhost
      return 'http://$localHost:$backendPort';
    } else if (Platform.isAndroid) {
      // Android - check if emulator or real device
      // For real device, use your PC's IP address
      // For emulator, use 10.0.2.2
      try {
        // Try to detect if running on emulator
        // Emulator typically has specific hostname patterns
        final hostname = Platform.localHostname.toLowerCase();
        if (hostname.contains('generic') || 
            hostname.contains('sdk') ||
            hostname.contains('emulator')) {
          // Likely emulator
          print('📱 Detected Android Emulator, using: http://$emulatorHost:$backendPort');
          return 'http://$emulatorHost:$backendPort';
        } else {
          // Real device - use configured IP
          // IMPORTANT: Update realDeviceHost to your PC's IP address
          print('📱 Detected Real Android Device, using: http://$realDeviceHost:$backendPort');
          print('⚠️ Make sure your PC IP is correct and backend server is running!');
          return 'http://$realDeviceHost:$backendPort';
        }
      } catch (e) {
        // Fallback to real device IP
        print('⚠️ Could not detect Android type, using real device IP: http://$realDeviceHost:$backendPort');
        return 'http://$realDeviceHost:$backendPort';
      }
    } else if (Platform.isIOS) {
      // iOS - use localhost for simulator, IP for real device
      return 'http://$localHost:$backendPort';
    } else {
      // Desktop (Windows, Linux, macOS)
      return 'http://$localHost:$backendPort';
    }
  }
  
  /// Get the current backend URL (for debugging)
  static String getCurrentBackendUrl() {
    return baseUrl;
  }
  
  /// Set custom backend URL (for testing)
  static String? _customBackendUrl;
  static void setCustomBackendUrl(String? url) {
    _customBackendUrl = url;
    print('🔧 Custom backend URL set: $url');
  }

  // Headers for API requests
  static Map<String, String> get headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  // ============ NODE OPERATIONS ============

  /// Register a new node in the network
  static Future<Map<String, dynamic>?> registerNode({
    required String nodeName,
    required String ipAddress,
    int tcpPort = 3001,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/nodes/register');
      
      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode({
          'node_name': nodeName,
          'ip_address': ipAddress,
          'tcp_port': tcpPort,
        }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        print('✅ Node registered: ${data['data']['node_id']}');
        return data['data'];
      } else {
        print('❌ Node registration failed: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Register node error: $e');
      return null;
    }
  }

  /// Get all online nodes
  static Future<List<Map<String, dynamic>>> getNodes() async {
    try {
      final url = Uri.parse('$baseUrl/api/nodes');
      
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['data'] ?? []);
      } else {
        print('❌ Get nodes failed: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('❌ Get nodes error: $e');
      return [];
    }
  }

  /// Build chain structure
  static Future<Map<String, dynamic>?> buildChain() async {
    try {
      final url = Uri.parse('$baseUrl/api/nodes/build-chain');
      
      final response = await http.post(url, headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ Chain built: ${data['data']['chain_length']} nodes');
        return data['data'];
      } else {
        print('❌ Build chain failed: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Build chain error: $e');
      return null;
    }
  }

  /// Get chain structure
  static Future<Map<String, dynamic>?> getChain() async {
    try {
      final url = Uri.parse('$baseUrl/api/nodes/chain');
      
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data'];
      } else {
        print('❌ Get chain failed: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Get chain error: $e');
      return null;
    }
  }

  // ============ LEDGER OPERATIONS ============

  /// Add block to node ledger (send message)
  static Future<Map<String, dynamic>?> addBlockToLedger({
    required String nodeId,
    required String senderAddress,
    String? receiverAddress,
    required String content,
    String? workspaceId,
    String type = 'message',
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/nodes/$nodeId/ledger');
      
      final blockData = {
        'type': type,
        'sender_address': senderAddress,
        'content': content,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      if (receiverAddress != null) {
        blockData['receiver_address'] = receiverAddress;
      }
      if (workspaceId != null) {
        blockData['workspace_id'] = workspaceId;
      }

      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(blockData),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        print('✅ Block added to ledger: ${data['data']['block_id']}');
        return data['data'];
      } else {
        print('❌ Add block failed: ${response.statusCode}');
        print('Response: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ Add block error: $e');
      return null;
    }
  }

  /// Get ledger for a node
  static Future<List<Map<String, dynamic>>> getLedger({
    required String nodeId,
    int limit = 100,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/nodes/$nodeId/ledger?limit=$limit');
      
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['data'] ?? []);
      } else {
        print('❌ Get ledger failed: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('❌ Get ledger error: $e');
      return [];
    }
  }

  /// Verify chain integrity
  static Future<bool> verifyChain(String nodeId) async {
    try {
      final url = Uri.parse('$baseUrl/api/nodes/$nodeId/verify');
      
      final response = await http.post(url, headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final isValid = data['data']['chain_valid'] ?? false;
        print('✅ Chain verification: ${isValid ? "Valid" : "Invalid"}');
        return isValid;
      } else {
        print('❌ Verify chain failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('❌ Verify chain error: $e');
      return false;
    }
  }

  // ============ MESSAGE OPERATIONS ============

  /// Get messages between two users
  static Future<List<Map<String, dynamic>>> getMessagesBetweenUsers({
    required String userA,
    required String userB,
    String? nodeId,
  }) async {
    try {
      var url = Uri.parse('$baseUrl/api/nodes/messages/$userA/$userB');
      if (nodeId != null) {
        url = Uri.parse('$baseUrl/api/nodes/messages/$userA/$userB?nodeId=$nodeId');
      }
      
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final messages = List<Map<String, dynamic>>.from(data['data'] ?? []);
        print('✅ Retrieved ${messages.length} messages between $userA and $userB');
        return messages;
      } else {
        print('❌ Get messages failed: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('❌ Get messages error: $e');
      return [];
    }
  }

  /// Send message from UserA to UserB through distributed chain
  static Future<bool> sendMessage({
    required String nodeId,
    required String senderAddress,
    required String receiverAddress,
    required String messageText,
    String? workspaceId,
  }) async {
    try {
      final block = await addBlockToLedger(
        nodeId: nodeId,
        senderAddress: senderAddress,
        receiverAddress: receiverAddress,
        content: messageText,
        workspaceId: workspaceId,
        type: 'message',
      );

      if (block != null) {
        print('✅ Message sent: ${block['block_id']}');
        
        // Verify chain after adding message
        final isValid = await verifyChain(nodeId);
        if (!isValid) {
          print('⚠️ Warning: Chain verification failed after sending message');
        }
        
        return true;
      } else {
        print('❌ Failed to send message');
        return false;
      }
    } catch (e) {
      print('❌ Send message error: $e');
      return false;
    }
  }

  // ============ HEALTH CHECK ============

  /// Check if backend is available
  /// Returns true if backend is healthy, false otherwise
  /// Uses shorter timeout for faster failure detection
  static Future<bool> checkHealth() async {
    try {
      final url = Uri.parse('$baseUrl/health');
      print('🔍 Checking backend health at: $url');
      
      // Reduced timeout to 3 seconds for faster failure detection
      final response = await http.get(url, headers: headers).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          throw TimeoutException('Health check timeout - backend server may not be running');
        },
      );

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body);
          final dbStatus = data['database'] ?? 'unknown';
          print('✅ Backend health: OK, Database: $dbStatus');
          return dbStatus == 'connected';
        } catch (e) {
          // If response is 200 but JSON parsing fails, still consider it healthy
          print('✅ Backend health: OK (response received)');
          return true;
        }
      } else {
        print('❌ Health check failed: ${response.statusCode}');
        return false;
      }
    } on TimeoutException {
      // Don't print verbose error messages for timeout - it's expected if backend is down
      print('⚠️ Backend health check timeout - server may not be running at $baseUrl');
      return false;
    } on SocketException catch (e) {
      // Network errors are common - handle gracefully
      final errorMsg = e.message.isNotEmpty ? e.message : 'Connection failed';
      print('⚠️ Backend unreachable at $baseUrl - $errorMsg');
      return false;
    } catch (e) {
      // Other errors - log but don't spam
      print('⚠️ Health check error: ${e.toString().split('\n').first}');
      return false;
    }
  }

  // ============ HELPER METHODS ============

  /// Get first available node ID
  static Future<String?> getFirstNodeId() async {
    try {
      final nodes = await getNodes();
      if (nodes.isNotEmpty) {
        return nodes.first['node_id'] as String?;
      }
      return null;
    } catch (e) {
      print('❌ Get first node ID error: $e');
      return null;
    }
  }

  /// Get node by ID
  static Future<Map<String, dynamic>?> getNodeById(String nodeId) async {
    try {
      final nodes = await getNodes();
      return nodes.firstWhere(
        (node) => node['node_id'] == nodeId,
        orElse: () => <String, dynamic>{},
      );
    } catch (e) {
      print('❌ Get node by ID error: $e');
      return null;
    }
  }

  // ============ USER OPERATIONS (Compatibility with MongoDBService) ============

  /// Get user profile (compatible with MongoDBService)
  /// Returns user profile or null if not found/unavailable
  /// Gracefully handles timeouts and network errors
  static Future<Map<String, dynamic>?> getUserProfile(String address) async {
    try {
      final url = Uri.parse('$baseUrl/api/users/profile/${Uri.encodeComponent(address)}');
      
      // Reduced timeout to 6 seconds for faster failure detection
      final response = await http.get(url, headers: headers).timeout(
        const Duration(seconds: 6),
        onTimeout: () {
          throw TimeoutException('Get user profile request timed out after 6 seconds');
        },
      );

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body);
          return data['data'];
        } catch (e) {
          print('⚠️ Failed to parse profile response');
          return null;
        }
      } else if (response.statusCode == 404) {
        return null; // User not found - this is expected
      } else {
        print('⚠️ Get user profile failed: ${response.statusCode}');
        return null;
      }
    } on TimeoutException {
      // Don't log verbose timeout errors - they're expected if backend is down
      return null;
    } on SocketException {
      // Network errors are common - handle gracefully
      return null;
    } catch (e) {
      // Only log unexpected errors
      if (!e.toString().contains('timeout') && !e.toString().contains('SocketException')) {
        print('⚠️ Get user profile error: ${e.toString().split('\n').first}');
      }
      return null;
    }
  }

  /// Save user profile (compatible with MongoDBService)
  /// Returns a map with success status and error message if failed
  static Future<Map<String, dynamic>> saveUserProfile({
    required String address,
    required String username,
    required String email,
  }) async {
    try {
      // First, check if backend is reachable
      final healthCheck = await checkHealth();
      if (!healthCheck) {
        final errorMsg = 'Backend server is not reachable at $baseUrl. '
            'Please ensure:\n'
            '1. Backend server is running (cd backend && npm run dev)\n'
            '2. PC IP address is correct: ${realDeviceHost}\n'
            '3. Firewall allows connections on port 3000\n'
            '4. Device and PC are on the same network';
        
        print('⚠️ Backend health check failed: $errorMsg');
        return {
          'success': false,
          'error': errorMsg,
          'isNetworkError': true,
        };
      }

      final url = Uri.parse('$baseUrl/api/users/profile');
      
      print('📤 Sending profile data to: $url');
      print('   Address: $address');
      print('   Username: $username');
      print('   Email: $email');
      
      // Add timeout to prevent hanging
      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode({
          'address': address,
          'username': username,
          'email': email,
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Request timed out after 10 seconds');
        },
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        try {
          final responseData = jsonDecode(response.body);
          print('✅ User profile saved: $address');
          return {
            'success': true,
            'data': responseData['data'],
          };
        } catch (e) {
          // Response is success but JSON parsing failed
          print('✅ User profile saved: $address (response parsing failed: $e)');
          return {
            'success': true,
            'data': null,
          };
        }
      } else if (response.statusCode == 409) {
        // Duplicate username or address
        try {
          final errorData = jsonDecode(response.body);
          final errorMsg = errorData['details'] ?? errorData['error'] ?? 'Username or address already exists';
          print('❌ Save user profile failed: Username or address already exists - $errorMsg');
          return {
            'success': false,
            'error': errorMsg,
            'isDuplicate': true,
          };
        } catch (e) {
          return {
            'success': false,
            'error': 'Username or address already exists',
            'isDuplicate': true,
          };
        }
      } else {
        String errorMsg = 'Unknown error';
        try {
          final errorData = jsonDecode(response.body);
          errorMsg = errorData['error'] ?? errorData['message'] ?? 'Unknown error';
        } catch (e) {
          // If JSON parsing fails, use response body as error message
          errorMsg = response.body.isNotEmpty 
              ? response.body 
              : 'Server returned status ${response.statusCode}';
        }
        print('❌ Save user profile failed: ${response.statusCode} - $errorMsg');
        return {
          'success': false,
          'error': 'Server error: $errorMsg',
          'statusCode': response.statusCode,
        };
      }
    } on SocketException catch (e) {
      final errorMsg = 'Cannot connect to backend server at $baseUrl.\n'
          'Error: ${e.message}\n\n'
          'Troubleshooting:\n'
          '1. Check if backend is running: cd backend && npm run dev\n'
          '2. Verify PC IP address: $realDeviceHost\n'
          '3. Ensure device and PC are on same WiFi network\n'
          '4. Check Windows Firewall settings';
      
      print('❌ Network error saving profile: $e');
      return {
        'success': false,
        'error': errorMsg,
        'isNetworkError': true,
        'exception': e.toString(),
      };
    } on TimeoutException catch (e) {
      final errorMsg = 'Request timed out. Backend server may be slow or unreachable.\n'
          'Please check if backend is running at $baseUrl';
      
      print('❌ Timeout error saving profile: $e');
      return {
        'success': false,
        'error': errorMsg,
        'isNetworkError': true,
        'exception': e.toString(),
      };
    } on http.ClientException catch (e) {
      final errorMsg = 'Connection error: ${e.message}\n'
          'Please check if backend server is running at $baseUrl';
      
      print('❌ Client error saving profile: $e');
      return {
        'success': false,
        'error': errorMsg,
        'isNetworkError': true,
        'exception': e.toString(),
      };
    } catch (e) {
      final errorMsg = 'Unexpected error: ${e.toString()}';
      print('❌ Save user profile error: $e');
      return {
        'success': false,
        'error': errorMsg,
        'exception': e.toString(),
      };
    }
  }

  // ============ WORKSPACE OPERATIONS (Compatibility with MongoDBService) ============

  /// Create workspace (compatible with MongoDBService)
  /// Returns workspaceId on success, null on failure
  /// Throws exception with error message if duplicate workspace name
  /// Optimized: Backend handles duplicate checking, so we skip local check for speed
  static Future<String?> createWorkspace({
    required String workspaceName,
    required String inviterAddress,
  }) async {
    try {
      // Skip local duplicate check - backend will handle it faster
      // This saves a network call and speeds up the flow
      
      final url = Uri.parse('$baseUrl/api/workspaces');
      
      print('📤 Creating workspace: $workspaceName for $inviterAddress');
      
      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode({
          'workspaceName': workspaceName,
          'inviterAddress': inviterAddress,
        }),
      ).timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          throw TimeoutException('Workspace creation request timed out after 12 seconds');
        },
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final workspaceId = data['data']['workspace_id'] as String?;
        print('✅ Workspace created: $workspaceId');
        return workspaceId;
      } else if (response.statusCode == 409) {
        // Duplicate workspace name - backend detected it
        final errorData = jsonDecode(response.body);
        final errorMessage = errorData['details'] ?? errorData['error'] ?? 'Workspace name already exists';
        throw Exception(errorMessage);
      } else {
        final errorBody = response.body;
        print('❌ Create workspace failed: ${response.statusCode} - $errorBody');
        throw Exception('Failed to create workspace. Please try again.');
      }
    } catch (e) {
      print('❌ Create workspace error: $e');
      rethrow; // Re-throw to let caller handle the error
    }
  }

  /// Get user workspaces (compatible with MongoDBService)
  /// Returns list of workspaces or empty list if unavailable
  /// Gracefully handles timeouts and network errors
  static Future<List<Map<String, dynamic>>> getUserWorkspaces(String userAddress) async {
    try {
      final url = Uri.parse('$baseUrl/api/workspaces/user/${Uri.encodeComponent(userAddress)}');
      
      // Reduced timeout to 6 seconds for faster failure detection
      final response = await http.get(url, headers: headers).timeout(
        const Duration(seconds: 6),
        onTimeout: () {
          throw TimeoutException('Get user workspaces request timed out after 6 seconds');
        },
      );

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body);
          final workspaces = List<Map<String, dynamic>>.from(data['data'] ?? []);
          
          // Map backend fields to Flutter expected fields
          return workspaces.map((ws) {
            return {
              ...ws,
              'workspaceName': ws['name'] ?? ws['workspaceName'] ?? 'Unnamed Workspace',
              'workspace_id': ws['workspace_id'] ?? ws['workspaceId'],
              'inviterAddress': ws['inviter_address'] ?? ws['inviterAddress'],
            };
          }).toList();
        } catch (e) {
          print('⚠️ Failed to parse workspaces response');
          return [];
        }
      } else {
        print('⚠️ Get user workspaces failed: ${response.statusCode}');
        return [];
      }
    } on TimeoutException {
      // Don't log verbose timeout errors - they're expected if backend is down
      return [];
    } on SocketException {
      // Network errors are common - handle gracefully
      return [];
    } catch (e) {
      // Only log unexpected errors
      if (!e.toString().contains('timeout') && !e.toString().contains('SocketException')) {
        print('⚠️ Get user workspaces error: ${e.toString().split('\n').first}');
      }
      return [];
    }
  }

  /// Get workspace members (compatible with MongoDBService)
  static Future<List<Map<String, dynamic>>> getWorkspaceMembers(String workspaceId) async {
    try {
      final url = Uri.parse('$baseUrl/api/members/workspace/${Uri.encodeComponent(workspaceId)}');
      
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final members = List<Map<String, dynamic>>.from(data['data'] ?? []);
        
        // Map backend fields to Flutter expected fields
        return members.map((member) {
          return {
            ...member,
            'memberAddress': member['member_address'] ?? member['memberAddress'],
            'memberDisplayName': member['display_name'] ?? member['memberDisplayName'],
            'workspaceId': member['workspace_id'] ?? member['workspaceId'],
            'joinedAt': member['joined_at'] ?? member['joinedAt'],
          };
        }).toList();
      } else {
        print('❌ Get workspace members failed: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('❌ Get workspace members error: $e');
      return [];
    }
  }

  /// Add workspace member (compatible with MongoDBService)
  static Future<bool> addWorkspaceMember({
    required String workspaceId,
    required String memberAddress,
    String? displayName,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/members');
      
      print('📤 Adding member to workspace: $workspaceId');
      
      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode({
          'workspaceId': workspaceId,
          'memberAddress': memberAddress,
          'displayName': displayName,
        }),
      ).timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          throw TimeoutException('Add workspace member request timed out after 8 seconds');
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        print('✅ Member added to workspace');
        return true;
      } else {
        print('❌ Add workspace member failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('❌ Add workspace member error: $e');
      return false;
    }
  }

  /// Resolve workspace by slug and inviter address (for invite links)
  static Future<Map<String, dynamic>?> resolveWorkspaceBySlug({
    required String workspaceSlug,
    required String inviterAddress,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/workspaces/resolve/slug').replace(
        queryParameters: {
          'workspaceSlug': workspaceSlug,
          'inviterAddress': inviterAddress,
        },
      );
      
      print('🔍 Resolving workspace by slug: $workspaceSlug, inviter: $inviterAddress');
      
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final workspace = data['data'];
        print('✅ Workspace resolved: ${workspace['workspace_id']} - ${workspace['name']}');
        return workspace;
      } else if (response.statusCode == 404) {
        print('❌ Workspace not found for slug: $workspaceSlug');
        return null;
      } else {
        print('❌ Resolve workspace failed: ${response.statusCode}');
        print('Response: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ Resolve workspace error: $e');
      return null;
    }
  }

  // ============ MESSAGE OPERATIONS (Compatibility with MongoDBService) ============

  /// Add message (compatible with MongoDBService)
  /// Uses both messages API (legacy) and distributed ledger system
  static Future<String?> addMessage({
    required String workspaceId,
    String? channelId,
    required String senderAddress,
    String? receiverAddress,
    required String messageText,
    String? fileId,
  }) async {
    try {
      String? messageId;
      
      // First, add to messages API (for backward compatibility and immediate access)
      try {
        final messagesUrl = Uri.parse('$baseUrl/api/messages');
        final messagesResponse = await http.post(
          messagesUrl,
          headers: headers,
          body: jsonEncode({
            'workspaceId': workspaceId,
            'channelId': channelId,
            'senderAddress': senderAddress,
            'receiverAddress': receiverAddress,
            'messageText': messageText,
            'fileId': fileId,
          }),
        );

        if (messagesResponse.statusCode == 201) {
          final messagesData = jsonDecode(messagesResponse.body);
          messageId = messagesData['data']['message_id'] as String?;
          print('✅ Message added to messages API: $messageId');
        }
      } catch (e) {
        print('⚠️ Messages API error (continuing with ledger): $e');
      }

      // Also add to distributed ledger system (for chain integrity)
      try {
        final nodeId = await getFirstNodeId();
        if (nodeId != null) {
          final block = await addBlockToLedger(
            nodeId: nodeId,
            senderAddress: senderAddress,
            receiverAddress: receiverAddress,
            content: messageText,
            workspaceId: workspaceId,
            type: 'message',
          );

          if (block != null) {
            final blockId = block['block_id'] as String? ?? block['_id']?.toString();
            print('✅ Message added to ledger: $blockId');
            // Use block ID if message ID not available
            messageId ??= blockId;
          }
        } else {
          print('⚠️ No node available for ledger (message still saved to API)');
        }
      } catch (e) {
        print('⚠️ Ledger error (message still saved to API): $e');
      }

      return messageId;
    } catch (e) {
      print('❌ Add message error: $e');
      return null;
    }
  }

  /// Create new channel in workspace
  static Future<bool> createChannel({
    required String workspaceId,
    required String channelId,
    required String creatorAddress,
    String? channelName,
    bool isPrivate = false,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/channels');
      final body = {
        'workspaceId': workspaceId,
        'channelId': channelId,
        'channelName': channelName ?? channelId,
        'creatorAddress': creatorAddress,
        'isPrivate': isPrivate,
      };

      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(body),
      );

      if (response.statusCode == 201) {
        print('✅ Channel "$channelId" created successfully');
        return true;
      } else if (response.statusCode == 409) {
        print('⚠️ Channel "$channelId" already exists');
        return true; // Already exists, consider it success
      } else {
        final errorData = jsonDecode(response.body);
        print('❌ Failed to create channel: ${errorData['error']}');
        return false;
      }
    } catch (e) {
      print('❌ Error creating channel: $e');
      return false;
    }
  }

  /// Get all channels for a workspace
  static Future<List<String>> getWorkspaceChannels({
    required String workspaceId,
    String? memberAddress, // Optional: filter channels accessible to this member
  }) async {
    try {
      String urlString = '$baseUrl/api/channels/workspace/${Uri.encodeComponent(workspaceId)}';
      if (memberAddress != null) {
        urlString += '?memberAddress=${Uri.encodeComponent(memberAddress)}';
      }
      final url = Uri.parse(urlString);

      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final channels = List<Map<String, dynamic>>.from(data['data'] ?? []);
        
        // Filter out deleted channels
        final activeChannels = channels.where((ch) => ch['deleted'] != true).toList();
        
        // Sort channels: General first, then Random, then user-created channels
        activeChannels.sort((a, b) {
          final aId = (a['channel_id']?.toString() ?? '').toLowerCase();
          final bId = (b['channel_id']?.toString() ?? '').toLowerCase();
          
          // General always first
          if (aId == 'general') return -1;
          if (bId == 'general') return 1;
          
          // Random always second
          if (aId == 'random') return -1;
          if (bId == 'random') return 1;
          
          // Default channels before user-created
          if (a['is_default'] == true && b['is_default'] != true) return -1;
          if (a['is_default'] != true && b['is_default'] == true) return 1;
          
          // Then by creation time
          final aTime = a['created_at'] ?? 0;
          final bTime = b['created_at'] ?? 0;
          return aTime.compareTo(bTime);
        });
        
        // Extract channel names (display names) and remove duplicates
        final channelMap = <String, String>{}; // channel_id (lowercase) -> display name
        for (final ch in activeChannels) {
          final channelId = (ch['channel_id']?.toString() ?? '').toLowerCase().trim();
          final name = ch['channel_name']?.toString() ?? ch['channel_id']?.toString() ?? '';
          
          if (channelId.isNotEmpty && name.isNotEmpty) {
            // Capitalize first letter
            final displayName = name.substring(0, 1).toUpperCase() + name.substring(1);
            
            // Only add if not already present (case-insensitive duplicate check)
            if (!channelMap.containsKey(channelId)) {
              channelMap[channelId] = displayName;
            } else {
              print('⚠️ Duplicate channel detected and removed: $channelId');
            }
          }
        }
        
        final channelList = channelMap.values.toList();

        // Ensure General and Random are always present (built-in channels)
        final Set<String> channelSet = channelList.map((c) => c.toLowerCase()).toSet();
        if (!channelSet.contains('general')) {
          channelList.insert(0, 'General');
        }
        if (!channelSet.contains('random')) {
          // Insert Random after General
          final generalIndex = channelList.indexOf('General');
          channelList.insert(generalIndex + 1, 'Random');
        }
        
        // Final sort to ensure correct order: General, Random, then others
        channelList.sort((a, b) {
          final aLower = a.toLowerCase();
          final bLower = b.toLowerCase();
          if (aLower == 'general') return -1;
          if (bLower == 'general') return 1;
          if (aLower == 'random') return -1;
          if (bLower == 'random') return 1;
          return a.compareTo(b);
        });
        
        // Remove any remaining duplicates (case-insensitive)
        final uniqueChannels = <String>[];
        final seenNames = <String>{};
        for (final channel in channelList) {
          final normalized = channel.toLowerCase().trim();
          if (!seenNames.contains(normalized)) {
            seenNames.add(normalized);
            uniqueChannels.add(channel);
          }
        }

        print('✅ Loaded ${uniqueChannels.length} unique channels for workspace: $workspaceId');
        print('📋 Channel order: ${uniqueChannels.join(" → ")}');
        return uniqueChannels;
      } else {
        print('❌ Get workspace channels failed: ${response.statusCode}');
        // Return default channels on error
        return ['General', 'Random'];
      }
    } catch (e) {
      print('❌ Error getting workspace channels: $e');
      // Return default channels on error
      return ['General', 'Random'];
    }
  }

  /// Get channel messages (compatible with MongoDBService)
  /// Get channel messages with chain integrity check
  /// Returns empty list if chain is broken
  /// Throws ChainBrokenException if chain integrity is compromised
  static Future<List<Map<String, dynamic>>> getChannelMessages({
    required String workspaceId,
    required String channelId,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/messages/channel?workspaceId=${Uri.encodeComponent(workspaceId)}&channelId=${Uri.encodeComponent(channelId)}');
      
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final chainValid = data['chainValid'] ?? true;
        final chainWarning = data['chainWarning'];
        
        // Log warning if chain verification failed but messages are still returned
        if (chainWarning != null) {
          print('⚠️ Chain verification warning: $chainWarning');
        }
        
        final messages = List<Map<String, dynamic>>.from(data['data'] ?? []);
        
        // Only throw exception if chain is explicitly broken AND no messages returned
        if (!chainValid && messages.isEmpty) {
          throw ChainBrokenException(
            'Data integrity check failed. Messages cannot be displayed for security reasons.',
            data['brokenAt'],
            data['details'],
          );
        }
        
        // Transform ledger format to message format for compatibility
        return messages.map((msg) {
          // If it's from ledger, extract data
          if (msg.containsKey('data') && msg['data'] is Map) {
            final msgData = msg['data'] as Map<String, dynamic>;
            return {
              'message_id': msg['block_id'] ?? msg['_id'],
              'message_text': msgData['content'] ?? msgData['message_text'] ?? '',
              'sender_address': msgData['sender_address'] ?? msg['sender_address'],
              'receiver_address': msgData['receiver_address'] ?? msg['receiver_address'],
              'timestamp': msg['timestamp'] ?? msgData['timestamp'],
              ...msgData, // Include all original data
            };
          }
          return msg;
        }).toList();
      } else if (response.statusCode == 403) {
        // Chain integrity compromised
        final errorData = jsonDecode(response.body);
        final chainBroken = errorData['chainBroken'] ?? false;
        
        if (chainBroken) {
          print('❌ Chain integrity compromised for channel $channelId');
          print('   Broken at: ${errorData['brokenAt']}');
          throw ChainBrokenException(
            'Data integrity check failed. Messages cannot be displayed for security reasons.',
            errorData['brokenAt'],
            errorData['details'],
          );
        }
        
        print('❌ Get channel messages failed: ${response.statusCode}');
        return [];
      } else {
        print('❌ Get channel messages failed: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      if (e is ChainBrokenException) {
        rethrow;
      }
      print('❌ Get channel messages error: $e');
      return [];
    }
  }

  /// Get direct messages with chain integrity check
  /// Returns empty list if chain is broken
  /// Throws ChainBrokenException if chain integrity is compromised
  static Future<List<Map<String, dynamic>>> getDirectMessages({
    required String user1Address,
    required String user2Address,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/messages/direct?user1Address=${Uri.encodeComponent(user1Address)}&user2Address=${Uri.encodeComponent(user2Address)}');
      
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final chainValid = data['chainValid'] ?? true;
        final chainWarning = data['chainWarning'];
        
        // Log warning if chain verification failed but messages are still returned
        if (chainWarning != null) {
          print('⚠️ Chain verification warning: $chainWarning');
        }
        
        final messages = List<Map<String, dynamic>>.from(data['data'] ?? []);
        
        // Only throw exception if chain is explicitly broken AND no messages returned
        if (!chainValid && messages.isEmpty) {
          throw ChainBrokenException(
            'Data integrity check failed. Messages cannot be displayed for security reasons.',
            data['brokenAt'],
            data['details'],
          );
        }
        
        // Transform to MongoDBService format
        return messages.map((msg) {
          // If it's from ledger, extract data
          if (msg.containsKey('data') && msg['data'] is Map) {
            final msgData = msg['data'] as Map<String, dynamic>;
            return {
              'message_id': msg['block_id'] ?? msg['_id'],
              'message_text': msgData['content'] ?? msgData['message_text'] ?? '',
              'sender_address': msgData['sender_address'] ?? msg['sender_address'],
              'receiver_address': msgData['receiver_address'] ?? msg['receiver_address'],
              'timestamp': msg['timestamp'] ?? msgData['timestamp'],
              ...msgData, // Include all original data
            };
          }
          return msg;
        }).toList();
      } else if (response.statusCode == 403) {
        // Chain integrity compromised
        final errorData = jsonDecode(response.body);
        final chainBroken = errorData['chainBroken'] ?? false;
        
        if (chainBroken) {
          print('❌ Chain integrity compromised for direct messages between $user1Address and $user2Address');
          print('   Broken at: ${errorData['brokenAt']}');
          throw ChainBrokenException(
            'Data integrity check failed. Messages cannot be displayed for security reasons.',
            errorData['brokenAt'],
            errorData['details'],
          );
        }
        
        print('❌ Get direct messages failed: ${response.statusCode}');
        return [];
      } else {
        print('❌ Get direct messages failed: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      if (e is ChainBrokenException) {
        rethrow;
      }
      print('❌ Get direct messages error: $e');
      return [];
    }
  }

  // ============ FILE UPLOAD OPERATIONS ============

  /// Upload file to backend
  /// Returns fileId on success, null on failure
  static Future<String?> uploadFile({
    required Uint8List fileBytes,
    required String fileName,
    required String workspaceId,
    required String uploaderAddress,
    String? mimeType,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/files/upload');
      
      // Create multipart request
      final request = http.MultipartRequest('POST', url);
      
      // Add file
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: fileName,
        ),
      );
      
      // Add form fields
      request.fields['workspaceId'] = workspaceId;
      request.fields['uploaderAddress'] = uploaderAddress;
      
      // Add headers
      request.headers.addAll(headers);
      
      print('📤 Uploading file: $fileName (${fileBytes.length} bytes) to $url');
      
      // Send request with timeout
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('File upload timed out after 30 seconds');
        },
      );
      
      final response = await http.Response.fromStream(streamedResponse);
      
      print('📥 Upload response status: ${response.statusCode}');
      
      if (response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        final fileId = responseData['data']?['file_id'] as String?;
        if (fileId != null) {
          print('✅ File uploaded successfully: $fileId');
          return fileId;
        } else {
          print('⚠️ Upload succeeded but no file_id in response');
          return null;
        }
      } else {
        final errorData = jsonDecode(response.body);
        final errorMsg = errorData['error'] ?? errorData['message'] ?? 'Unknown error';
        print('❌ File upload failed: ${response.statusCode} - $errorMsg');
        return null;
      }
    } on SocketException catch (e) {
      print('❌ Network error uploading file: $e');
      return null;
    } on TimeoutException catch (e) {
      print('❌ Timeout error uploading file: $e');
      return null;
    } catch (e) {
      print('❌ Error uploading file: $e');
      return null;
    }
  }

  /// Download file from backend using fileId
  static Future<Uint8List?> downloadFile(String fileId) async {
    try {
      final url = Uri.parse('$baseUrl/api/files/$fileId/download');
      
      print('📥 Downloading file: $fileId from $url');
      
      final response = await http.get(url, headers: headers).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('File download timed out after 30 seconds');
        },
      );
      
      if (response.statusCode == 200) {
        print('✅ File downloaded successfully: $fileId (${response.bodyBytes.length} bytes)');
        return response.bodyBytes;
      } else {
        print('❌ File download failed: ${response.statusCode}');
        return null;
      }
    } on SocketException catch (e) {
      print('❌ Network error downloading file: $e');
      return null;
    } on TimeoutException catch (e) {
      print('❌ Timeout error downloading file: $e');
      return null;
    } catch (e) {
      print('❌ Error downloading file: $e');
      return null;
    }
  }

  // ============ CONNECTION (Compatibility with MongoDBService) ============

  /// Connect to backend (compatible with MongoDBService.connect())
  /// Non-blocking: Returns false if backend is unavailable but doesn't throw
  static Future<bool> connect() async {
    try {
      final isHealthy = await checkHealth();
      if (isHealthy) {
        print('✅ Connected to backend successfully');
      } else {
        print('⚠️ Backend connection unavailable - app will work in offline mode');
      }
      return isHealthy;
    } catch (e) {
      // Don't throw - gracefully handle connection failures
      print('⚠️ Backend connection check failed: ${e.toString().split('\n').first}');
      return false;
    }
  }
}

