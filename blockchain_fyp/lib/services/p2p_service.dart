import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'sqlite_service.dart';

/// P2P Service for Direct Device-to-Device TCP Communication
/// Enables UserA to UserB messaging without server
class P2PService {
  static P2PService? _instance;
  
  // Singleton pattern
  static P2PService get instance {
    _instance ??= P2PService._();
    return _instance!;
  }

  P2PService._();

  ServerSocket? _serverSocket;
  final Map<String, Socket> _connectedPeers = {}; // peerId -> Socket
  final Map<String, String> _userToPeerId = {}; // userAddress -> peerId
  final Map<String, StreamSubscription> _peerSubscriptions = {};
  final Map<String, Completer<Map<String, dynamic>>> _pendingAcks = {};
  
  String? _myUserAddress;
  String? _myIpAddress;
  int _myPort = 8080;
  bool _isServerRunning = false;
  
  // Callbacks
  Function(Map<String, dynamic>)? onMessageReceived;
  Function(String, bool)? onPeerStatusChanged;
  Function(Map<String, dynamic>)? onChannelCreated; // Callback for channel creation events

  /// Get current IP address
  Future<String?> getMyIpAddress() async {
    try {
      // Try to get local network IP
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );

      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            return addr.address;
          }
        }
      }

      // Fallback to loopback
      return '127.0.0.1';
    } catch (e) {
      print('❌ Get IP address error: $e');
      return '127.0.0.1';
    }
  }

  /// Start TCP server
  Future<bool> startServer({
    required String userAddress,
    int? port,
  }) async {
    try {
      // IMPORTANT: If server is already running but user address changed, restart it
      if (_isServerRunning && _myUserAddress == userAddress) {
        print('✅ P2P server already running for user $userAddress');
        return true;
      }
      
      // If server is running but user address changed, stop and restart
      if (_isServerRunning && _myUserAddress != userAddress) {
        print('🔄 P2P server running for different user, restarting...');
        await stopServer();
      }
      
      // If server socket exists but flag is false (app restart scenario), cleanup
      if (_serverSocket != null && !_isServerRunning) {
        print('🧹 Cleaning up stale server socket...');
        try {
          await _serverSocket?.close();
        } catch (e) {
          print('⚠️ Error closing stale socket: $e');
        }
        _serverSocket = null;
      }

      _myUserAddress = userAddress;
      _myPort = port ?? 8080;
      _myIpAddress = await getMyIpAddress();

      print('🌐 Starting P2P TCP server...');
      print('   IP: $_myIpAddress');
      print('   Port: $_myPort');
      print('   User: $userAddress');

      _serverSocket = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        _myPort,
      );

      _isServerRunning = true;
      print('✅ P2P TCP server started on $_myIpAddress:$_myPort');

      // Save peer info to SQLite
      await SQLiteService.instance.savePeer(
        userAddress: userAddress,
        ipAddress: _myIpAddress!,
        port: _myPort,
      );

      // Listen for incoming connections
      _serverSocket!.listen(
        _handleIncomingConnection,
        onError: (error) {
          print('❌ Server socket error: $error');
        },
        onDone: () {
          print('⚠️ Server socket closed');
          _isServerRunning = false;
        },
      );

      return true;
    } catch (e) {
      print('❌ Start P2P server error: $e');
      _isServerRunning = false;
      return false;
    }
  }

  /// Handle incoming TCP connection
  void _handleIncomingConnection(Socket socket) {
    final peerId = '${socket.remoteAddress.address}:${socket.remotePort}';
    print('📡 New P2P connection: $peerId');

    // Store connection (user address will be mapped during handshake)
    _connectedPeers[peerId] = socket;

    // Listen for data
    final subscription = socket.listen(
      (data) => _handlePeerData(peerId, data),
      onError: (error) {
        print('❌ Peer socket error ($peerId): $error');
        _disconnectPeer(peerId);
      },
      onDone: () {
        print('🔌 Peer disconnected: $peerId');
        _disconnectPeer(peerId);
      },
      cancelOnError: true,
    );

    _peerSubscriptions[peerId] = subscription;

    // Send handshake
    _sendToPeer(peerId, {
      'type': 'handshake',
      'user_address': _myUserAddress,
      'ip_address': _myIpAddress,
      'port': _myPort,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Handle data from peer
  void _handlePeerData(String peerId, List<int> data) {
    try {
      final messageStr = utf8.decode(data);
      final message = jsonDecode(messageStr) as Map<String, dynamic>;
      
      print('📨 Received P2P message from $peerId: ${message['type']}');

      switch (message['type']) {
        case 'handshake':
          _handleHandshake(peerId, message);
          break;
          
        case 'handshake_ack':
          _handleHandshakeAck(peerId, message);
          break;
          
        case 'message':
        case 'channel_message':
          _handleMessage(peerId, message);
          break;
          
        case 'ack':
          _handleAck(peerId, message);
          break;
          
        case 'ping':
          _handlePing(peerId, message);
          break;
          
        case 'pong':
          _handlePong(peerId, message);
          break;
          
        default:
          print('⚠️ Unknown message type: ${message['type']}');
      }
    } catch (e) {
      print('❌ Handle peer data error: $e');
    }
  }

  /// Handle handshake
  void _handleHandshake(String peerId, Map<String, dynamic> message) {
    final userAddress = message['user_address'] as String?;
    final ipAddress = message['ip_address'] as String?;
    final port = message['port'] as int?;

    if (userAddress != null && ipAddress != null && port != null) {
      // Normalize address for consistent lookup (case-insensitive)
      final normalizedAddress = userAddress.toLowerCase().trim();
      
      // Map user address to peer ID (store both normalized and original for compatibility)
      _userToPeerId[normalizedAddress] = peerId;
      if (normalizedAddress != userAddress) {
        _userToPeerId[userAddress] = peerId;
      }
      
      // Save peer info
      SQLiteService.instance.savePeer(
        userAddress: normalizedAddress, // Save normalized address
        ipAddress: ipAddress,
        port: port,
      );

      // Send acknowledgment
      _sendToPeer(peerId, {
        'type': 'handshake_ack',
        'user_address': _myUserAddress,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      print('✅ Handshake completed with $userAddress (normalized: $normalizedAddress, peerId: $peerId)');
      onPeerStatusChanged?.call(userAddress, true);
    }
  }

  /// Handle handshake acknowledgment
  void _handleHandshakeAck(String peerId, Map<String, dynamic> message) {
    final userAddress = message['user_address'] as String?;
    if (userAddress != null) {
      // Normalize address for consistent lookup (case-insensitive)
      final normalizedAddress = userAddress.toLowerCase().trim();
      
      // Map user address to peer ID (store both normalized and original for compatibility)
      _userToPeerId[normalizedAddress] = peerId;
      if (normalizedAddress != userAddress) {
        _userToPeerId[userAddress] = peerId;
      }
      
      print('✅ Handshake acknowledged by $userAddress (normalized: $normalizedAddress, peerId: $peerId)');
      onPeerStatusChanged?.call(userAddress, true);
    }
  }

  /// Check if message is duplicate
  Future<bool> _checkDuplicateMessage({
    required String workspaceId,
    required String channelId,
    required String? messageId,
    required String? senderAddress,
    required String? content,
    int? timestamp,
  }) async {
    try {
      final existingMessagesResult = await SQLiteService.instance.getChannelMessages(
        workspaceId: workspaceId,
        channelId: channelId,
      );
      
      // Extract messages list from the result map
      final existingMessages = existingMessagesResult['messages'] as List<Map<String, dynamic>>? ?? [];
      
      return existingMessages.any((m) => 
        m['message_id']?.toString() == messageId ||
        (m['sender_address']?.toString().toLowerCase() == senderAddress?.toLowerCase() &&
         m['message_text']?.toString() == content &&
         (m['timestamp'] is int 
           ? (m['timestamp'] as int) 
           : (m['timestamp'] is DateTime 
              ? (m['timestamp'] as DateTime).millisecondsSinceEpoch 
              : 0)) == timestamp)
      );
    } catch (e) {
      print('⚠️ Error checking for duplicate message: $e');
      return false; // If check fails, allow message (better than blocking)
    }
  }

  /// Handle incoming message
  void _handleMessage(String peerId, Map<String, dynamic> message) {
    final messageType = message['type'] as String?;
    final messageId = message['message_id'] as String?;
    final senderAddress = message['sender_address'] as String?;
    final receiverAddress = message['receiver_address'] as String?;
    final content = message['content'] as String?;
    final workspaceId = message['workspace_id'] as String?;
    final channelId = message['channel_id'] as String?;

    if (messageId == null || senderAddress == null || content == null) {
      print('❌ Invalid message format');
      return;
    }

    // Handle channel creation events
    if (messageType == 'channel_created' && channelId != null && workspaceId != null) {
      print('📢 Received channel creation event: $channelId in workspace $workspaceId from $senderAddress');
      
      final channelName = message['channel_name'] as String? ?? channelId;
      final creatorAddress = message['creator_address'] as String? ?? senderAddress;
      
      // Save channel to SQLite (mark as not synced to server since it came via P2P)
      SQLiteService.instance.saveChannel(
        workspaceId: workspaceId,
        channelId: channelId,
        channelName: channelName,
        creatorAddress: creatorAddress,
        syncedToServer: false, // Mark as unsynced - will sync when server comes online
      ).then((saved) {
        if (saved) {
          print('✅ Channel "$channelName" saved to SQLite from P2P broadcast (will sync to server when online)');
          
          // Send acknowledgment
          _sendToPeer(peerId, {
            'type': 'ack',
            'message_id': messageId,
            'status': 'received',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
          
          // Notify callback (for UI updates - reload channels)
          // This triggers UI reload on receiver devices
          onChannelCreated?.call({
            'workspace_id': workspaceId,
            'channel_id': channelId,
            'channel_name': channelName,
            'creator_address': creatorAddress,
          });
          
          print('📢 Channel creation callback triggered for UI update');
        } else {
          print('⚠️ Failed to save channel to SQLite');
        }
      }).catchError((e) {
        print('❌ Error saving channel from P2P: $e');
      });
      
      return;
    }

    // Handle channel messages (broadcast to all members)
    if (messageType == 'channel_message' && channelId != null && workspaceId != null) {
      print('📢 Received channel message: $channelId in workspace $workspaceId from $senderAddress');
      
      // Check if message already exists (deduplication) - async check
      _checkDuplicateMessage(
        workspaceId: workspaceId,
        channelId: channelId,
        messageId: messageId,
        senderAddress: senderAddress,
        content: content,
        timestamp: message['timestamp'] as int?,
      ).then((messageExists) async {
        if (messageExists) {
          print('⚠️ Duplicate channel message detected, skipping: $messageId');
          // Still send ack to avoid timeout
          _sendToPeer(peerId, {
            'type': 'ack',
            'message_id': messageId,
            'status': 'duplicate',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
          return;
        }
        
        // CRITICAL FIX: Determine message state based on server status
        // P2P messages should be OFFLINE_LOCAL if server is offline
        // If server is online, message might already be on server (via another path)
        // We'll mark as OFFLINE_LOCAL and let sync handle it (sync will check idempotency)
        final messageState = 'OFFLINE_LOCAL'; // Always start as offline, sync will update if needed
        
        // Save channel message to SQLite
        final saved = await SQLiteService.instance.addMessage(
          workspaceId: workspaceId,
          channelId: channelId,
          senderAddress: senderAddress,
          receiverAddress: null, // Channel message, no specific receiver
          messageText: content,
          providedMessageId: messageId, // Use same message ID from P2P
          messageState: messageState, // CRITICAL: Set proper state
        );

        if (saved != null) {
          print('✅ Channel message saved to SQLite: $messageId');
        } else {
          print('⚠️ Failed to save channel message to SQLite: $messageId');
        }

        // Send acknowledgment
        _sendToPeer(peerId, {
          'type': 'ack',
          'message_id': messageId,
          'status': 'received',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });

        // Notify callback (for UI updates) - IMPORTANT: Call after saving to SQLite
        if (onMessageReceived != null) {
          print('📢 Triggering onMessageReceived callback for message: $messageId');
          print('   Workspace: $workspaceId, Channel: $channelId');
          onMessageReceived!(message);
        } else {
          print('⚠️ onMessageReceived callback is null - UI will not update automatically');
          print('   💡 Message is saved to SQLite, will appear on next poll or page reload');
        }

        print('✅ Channel message received and processed: $messageId');
      }).catchError((e) {
        print('❌ Error handling channel message: $e');
      });
      return;
    }

    // Handle direct messages (for specific receiver)
    if (messageType == 'message') {
      // Check if message is for this user
      if (receiverAddress != _myUserAddress) {
        print('⚠️ Message not for this user, ignoring');
        return;
      }

      // CRITICAL FIX: Set proper state for P2P direct messages
      final messageState = 'OFFLINE_LOCAL'; // Always start as offline, sync will update if needed
      
      // Save message to SQLite
      SQLiteService.instance.addMessage(
        workspaceId: workspaceId ?? '',
        senderAddress: senderAddress,
        receiverAddress: receiverAddress,
        messageText: content,
        providedMessageId: messageId, // Use same message ID from P2P
        messageState: messageState, // CRITICAL: Set proper state
      );

      // Send acknowledgment
      _sendToPeer(peerId, {
        'type': 'ack',
        'message_id': messageId,
        'status': 'received',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      // Notify callback
      onMessageReceived?.call(message);

      print('✅ Message received and saved: $messageId');
    }
  }

  /// Handle acknowledgment
  void _handleAck(String peerId, Map<String, dynamic> message) {
    final messageId = message['message_id'] as String?;
    if (messageId != null && _pendingAcks.containsKey(messageId)) {
      _pendingAcks[messageId]!.complete(message);
      _pendingAcks.remove(messageId);
      print('✅ Message acknowledged: $messageId');
    }
  }

  /// Handle ping
  void _handlePing(String peerId, Map<String, dynamic> message) {
    _sendToPeer(peerId, {
      'type': 'pong',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Handle pong
  void _handlePong(String peerId, Map<String, dynamic> message) {
    // Connection is alive
    print('💓 Pong received from $peerId');
  }

  /// Connect to peer (with retry mechanism)
  Future<bool> connectToPeer({
    required String ipAddress,
    required int port,
    String? userAddress,
    int maxRetries = 2,
  }) async {
    try {
      final peerId = '$ipAddress:$port';
      
      // Check if already connected
      if (_connectedPeers.containsKey(peerId)) {
        final socket = _connectedPeers[peerId];
        if (socket != null) {
          // Check if socket is still alive (non-blocking check)
          try {
            // If socket is done, it means connection is closed
            socket.done.then((_) {
              // Connection closed, remove it
              _disconnectPeer(peerId);
            }).catchError((_) {
              // Error checking, assume connection is dead
              _disconnectPeer(peerId);
            });
            
            // For now, assume connection is alive if socket exists
            print('✅ Already connected to $peerId');
            return true;
          } catch (e) {
            // Error checking socket, remove it
            print('⚠️ Error checking connection, removing: $peerId');
            _disconnectPeer(peerId);
          }
        }
      }

      print('🔗 Connecting to peer: $ipAddress:$port (user: ${userAddress ?? "unknown"})');

      // Try to connect with retries
      Socket? socket;
      Exception? lastError;
      
      for (int attempt = 1; attempt <= maxRetries; attempt++) {
        try {
          socket = await Socket.connect(
            ipAddress,
            port,
            timeout: const Duration(seconds: 5),
          ).timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              throw TimeoutException('Connection timeout after 5 seconds');
            },
          );
          
          // Connection successful
          break;
        } catch (e) {
          lastError = e is Exception ? e : Exception(e.toString());
          print('   ⚠️ Connection attempt $attempt/$maxRetries failed: $e');
          
          if (attempt < maxRetries) {
            // Wait before retry (exponential backoff)
            final delay = Duration(milliseconds: 500 * attempt);
            print('   ⏳ Retrying in ${delay.inMilliseconds}ms...');
            await Future.delayed(delay);
          }
        }
      }
      
      if (socket == null) {
        print('❌ Failed to connect to $ipAddress:$port after $maxRetries attempts');
        if (lastError != null) {
          print('   Last error: $lastError');
        }
        return false;
      }

      _connectedPeers[peerId] = socket;

      // Listen for data
      final subscription = socket.listen(
        (data) => _handlePeerData(peerId, data),
        onError: (error) {
          print('❌ Peer connection error ($peerId): $error');
          _disconnectPeer(peerId);
        },
        onDone: () {
          print('🔌 Peer connection closed: $peerId');
          _disconnectPeer(peerId);
        },
        cancelOnError: true,
      );

      _peerSubscriptions[peerId] = subscription;

      // Send handshake
      _sendToPeer(peerId, {
        'type': 'handshake',
        'user_address': _myUserAddress,
        'ip_address': _myIpAddress,
        'port': _myPort,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      print('✅ Connected to peer: $ipAddress:$port');
      return true;
    } catch (e) {
      print('❌ Connect to peer error: $e');
      return false;
    }
  }

  /// Connect to peer by user address
  Future<bool> connectToPeerByAddress(String userAddress) async {
    try {
      // Normalize address for lookup (case-insensitive)
      final normalizedAddress = userAddress.toLowerCase().trim();
      
      // Try to get peer info from SQLite (try both normalized and original)
      var peer = await SQLiteService.instance.getPeer(normalizedAddress);
      if (peer == null && normalizedAddress != userAddress) {
        peer = await SQLiteService.instance.getPeer(userAddress);
      }
      
      if (peer == null) {
        print('❌ Peer not found in SQLite: $userAddress (normalized: $normalizedAddress)');
        print('   💡 Tip: Peer info needs to be cached in SQLite for offline P2P');
        return false;
      }

      final ipAddress = peer['ip_address'] as String?;
      final port = peer['port'] as int?;

      if (ipAddress == null || port == null) {
        print('❌ Invalid peer info for $userAddress: ip=$ipAddress, port=$port');
        return false;
      }

      print('🔗 Connecting to peer $userAddress at $ipAddress:$port');
      return await connectToPeer(
        ipAddress: ipAddress,
        port: port,
        userAddress: normalizedAddress, // Use normalized address for consistency
      );
    } catch (e) {
      print('❌ Connect to peer by address error: $e');
      return false;
    }
  }

  /// Send message to peer
  Future<bool> sendMessageToPeer({
    required String receiverAddress,
    required String content,
    String? workspaceId,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      // Find peer connection by user address
      String? peerId = _userToPeerId[receiverAddress];
      Socket? peerSocket = peerId != null ? _connectedPeers[peerId] : null;

      // If no connection, try to connect
      if (peerSocket == null || peerId == null) {
        print('🔗 No existing connection, connecting to peer: $receiverAddress');
        final connected = await connectToPeerByAddress(receiverAddress);
        if (!connected) {
          print('❌ Could not connect to peer: $receiverAddress');
          return false;
        }
        
        // Wait a bit for connection to establish and handshake
        await Future.delayed(const Duration(milliseconds: 1000));
        
        // Find the connection again
        peerId = _userToPeerId[receiverAddress];
        peerSocket = peerId != null ? _connectedPeers[peerId] : null;
      }

      if (peerSocket == null || peerId == null) {
        print('❌ No peer connection available for $receiverAddress');
        return false;
      }
      
      print('📤 Sending message to $receiverAddress via peerId: $peerId');

      // Generate message ID
      final messageId = DateTime.now().millisecondsSinceEpoch.toString();

      // Create message
      final message = {
        'type': 'message',
        'message_id': messageId,
        'sender_address': _myUserAddress,
        'receiver_address': receiverAddress,
        'content': content,
        'workspace_id': workspaceId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      // Send message
      _sendToPeer(peerId, message);

      // Wait for acknowledgment
      final completer = Completer<Map<String, dynamic>>();
      _pendingAcks[messageId] = completer;

      try {
        await completer.future.timeout(timeout);
        print('✅ Message sent and acknowledged: $messageId');
        
        // NOTE: Message is already saved to SQLite in HybridStorageService.addMessage()
        // before P2P is attempted, so we don't need to save it again here
        // This prevents duplicate saves and ensures message persists even if P2P fails

        return true;
      } on TimeoutException {
        print('⚠️ Message acknowledgment timeout: $messageId');
        print('   💡 Message is already saved to SQLite, will be visible on reload');
        _pendingAcks.remove(messageId);
        return false; // Return false but message is still in SQLite
      }
    } catch (e) {
      print('❌ Send message to peer error: $e');
      return false;
    }
  }

  /// Send channel message to peer (for channel broadcasting)
  Future<bool> sendChannelMessageToPeer({
    required String receiverAddress,
    required String content,
    required String workspaceId,
    required String channelId,
    String? messageId, // Use provided message ID (from SQLite) instead of generating new one
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      // Normalize receiver address for lookup (case-insensitive)
      final normalizedReceiverAddress = receiverAddress.toLowerCase().trim();
      
      // Find peer connection by user address (try both normalized and original)
      String? peerId = _userToPeerId[normalizedReceiverAddress] ?? 
                      _userToPeerId[receiverAddress];
      Socket? peerSocket = peerId != null ? _connectedPeers[peerId] : null;

      // Check if connection is alive
      if (peerSocket != null && peerId != null) {
        try {
          // Check if socket is still alive (non-blocking check)
          // socket.done is a Future, so we check it asynchronously
          final currentPeerId = peerId; // Capture for async callback
          peerSocket.done.then((_) {
            // Connection closed, remove it
            print('⚠️ Existing connection is dead, removing: $receiverAddress');
            if (currentPeerId != null) {
              _disconnectPeer(currentPeerId);
            }
          }).catchError((_) {
            // Error checking, assume connection is dead
            print('⚠️ Error checking connection, removing: $receiverAddress');
            if (currentPeerId != null) {
              _disconnectPeer(currentPeerId);
            }
          });
          
          // For now, assume connection is alive if socket exists
          // If it's actually dead, it will be removed by the done handler above
        } catch (e) {
          print('⚠️ Error checking connection, reconnecting: $e');
          if (peerId != null) {
            _disconnectPeer(peerId);
          }
          peerSocket = null;
          peerId = null;
        }
      }
      
      // If no connection, try to connect
      if (peerSocket == null || peerId == null) {
        print('🔗 No existing connection, connecting to peer: $receiverAddress');
        final connected = await connectToPeerByAddress(receiverAddress);
        if (!connected) {
          print('❌ Could not connect to peer: $receiverAddress');
          print('   💡 Peer info might be outdated or peer server not running');
          return false;
        }
        
        // Wait a bit for connection to establish and handshake
        await Future.delayed(const Duration(milliseconds: 1500));
        
        // Find the connection again (try both normalized and original)
        peerId = _userToPeerId[normalizedReceiverAddress] ?? 
                _userToPeerId[receiverAddress];
        peerSocket = peerId != null ? _connectedPeers[peerId] : null;
        
        // Verify connection is alive (non-blocking check)
        if (peerSocket != null && peerId != null) {
          try {
            // socket.done is a Future, so we check it asynchronously
            final currentPeerId = peerId; // Capture for async callback
            peerSocket.done.then((_) {
              // Connection closed immediately, remove it
              print('⚠️ Connection established but immediately closed: $receiverAddress');
              if (currentPeerId != null) {
                _disconnectPeer(currentPeerId);
              }
            }).catchError((_) {
              // Error checking, assume connection is dead
              print('⚠️ Error verifying connection, removing: $receiverAddress');
              if (currentPeerId != null) {
                _disconnectPeer(currentPeerId);
              }
            });
            
            // For now, assume connection is alive if socket exists
            // If it's actually dead, it will be removed by the done handler above
          } catch (e) {
            print('⚠️ Error verifying connection: $e');
            if (peerId != null) {
              _disconnectPeer(peerId);
            }
            peerSocket = null;
            peerId = null;
          }
        }
      }

      if (peerSocket == null || peerId == null) {
        print('❌ No peer connection available for $receiverAddress');
        print('   Available peer addresses: ${_userToPeerId.keys.join(", ")}');
        print('   💡 Tip: Make sure peer server is running and peer info is up-to-date');
        return false;
      }
      
      print('📤 Sending channel message to $receiverAddress via peerId: $peerId');

      // Use provided message ID or generate new one
      final finalMessageId = messageId ?? DateTime.now().millisecondsSinceEpoch.toString();
      
      if (messageId != null) {
        print('   Using provided message ID: $messageId');
      } else {
        print('   Generated new message ID: $finalMessageId');
      }

      // Create channel message
      final message = {
        'type': 'channel_message',
        'message_id': finalMessageId,
        'sender_address': _myUserAddress,
        'receiver_address': receiverAddress, // For routing, but message is for channel
        'content': content,
        'workspace_id': workspaceId,
        'channel_id': channelId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      print('   Message details: workspace=$workspaceId, channel=$channelId, content=${content.substring(0, content.length > 50 ? 50 : content.length)}...');

      // Send message
      _sendToPeer(peerId, message);

      // Wait for acknowledgment
      final completer = Completer<Map<String, dynamic>>();
      _pendingAcks[finalMessageId] = completer;

      try {
        await completer.future.timeout(timeout);
        print('✅ Channel message sent and acknowledged: $finalMessageId');
        
        // NOTE: Message is already saved to SQLite in HybridStorageService.addMessage()
        // before P2P is attempted, so we don't need to save it again here
        // This prevents duplicate saves and ensures message persists even if P2P fails

        return true;
      } on TimeoutException {
        print('⚠️ Channel message acknowledgment timeout: $finalMessageId');
        print('   💡 Message is already saved to SQLite, will be visible on reload');
        _pendingAcks.remove(finalMessageId);
        return false; // Return false but message is still in SQLite
      }
    } catch (e) {
      print('❌ Send channel message to peer error: $e');
      return false;
    }
  }

  /// Broadcast channel creation to a peer
  Future<bool> broadcastChannelCreated({
    required String receiverAddress,
    required String workspaceId,
    required String channelId,
    required String channelName,
    required String creatorAddress,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      // Find peer connection by user address
      String? peerId = _userToPeerId[receiverAddress];
      Socket? peerSocket = peerId != null ? _connectedPeers[peerId] : null;

      // If no connection, try to connect
      if (peerSocket == null || peerId == null) {
        print('🔗 No existing connection, connecting to peer: $receiverAddress');
        final connected = await connectToPeerByAddress(receiverAddress);
        if (!connected) {
          print('❌ Could not connect to peer: $receiverAddress');
          return false;
        }
        
        // Wait a bit for connection to establish and handshake
        await Future.delayed(const Duration(milliseconds: 1000));
        
        // Find the connection again
        peerId = _userToPeerId[receiverAddress];
        peerSocket = peerId != null ? _connectedPeers[peerId] : null;
      }

      if (peerSocket == null || peerId == null) {
        print('❌ No peer connection available for $receiverAddress');
        return false;
      }
      
      print('📤 Broadcasting channel creation to $receiverAddress via peerId: $peerId');

      // Generate event ID
      final eventId = DateTime.now().millisecondsSinceEpoch.toString();

      // Create channel creation event
      final event = {
        'type': 'channel_created',
        'message_id': eventId,
        'sender_address': _myUserAddress,
        'receiver_address': receiverAddress,
        'workspace_id': workspaceId,
        'channel_id': channelId,
        'channel_name': channelName,
        'creator_address': creatorAddress,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      // Send event
      _sendToPeer(peerId, event);

      // Wait for acknowledgment
      final completer = Completer<Map<String, dynamic>>();
      _pendingAcks[eventId] = completer;

      try {
        await completer.future.timeout(timeout);
        print('✅ Channel creation broadcasted and acknowledged: $eventId');
        return true;
      } on TimeoutException {
        print('⚠️ Channel creation acknowledgment timeout: $eventId');
        _pendingAcks.remove(eventId);
        return false;
      }
    } catch (e) {
      print('❌ Broadcast channel creation error: $e');
      return false;
    }
  }

  /// Send data to peer
  void _sendToPeer(String peerId, Map<String, dynamic> data) {
    try {
      final socket = _connectedPeers[peerId];
      if (socket == null) {
        print('❌ Peer not connected: $peerId');
        return;
      }

      final jsonStr = jsonEncode(data);
      final bytes = utf8.encode(jsonStr);
      socket.add(bytes);
    } catch (e) {
      print('❌ Send to peer error: $e');
    }
  }

  /// Disconnect peer
  void _disconnectPeer(String peerId) {
    _peerSubscriptions[peerId]?.cancel();
    _peerSubscriptions.remove(peerId);
    _connectedPeers[peerId]?.close();
    _connectedPeers.remove(peerId);
    
    // Remove from user mapping
    _userToPeerId.removeWhere((key, value) => value == peerId);
  }

  /// Ping peer
  Future<bool> pingPeer(String peerId) async {
    try {
      _sendToPeer(peerId, {
        'type': 'ping',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      return true;
    } catch (e) {
      print('❌ Ping peer error: $e');
      return false;
    }
  }

  /// Get connected peers
  List<String> getConnectedPeers() {
    return _connectedPeers.keys.toList();
  }

  /// Get my IP address
  String? getMyIp() => _myIpAddress;

  /// Get my port
  int getMyPort() => _myPort;

  /// Check if server is running
  bool isServerRunning() => _isServerRunning;

  /// Stop P2P server
  Future<void> stopServer() async {
    try {
      print('🛑 Stopping P2P server...');

      // Close all peer connections
      for (final peerId in _connectedPeers.keys.toList()) {
        _disconnectPeer(peerId);
      }

      // Close server socket
      await _serverSocket?.close();
      _serverSocket = null;
      _isServerRunning = false;

      print('✅ P2P server stopped');
    } catch (e) {
      print('❌ Stop P2P server error: $e');
    }
  }
}

