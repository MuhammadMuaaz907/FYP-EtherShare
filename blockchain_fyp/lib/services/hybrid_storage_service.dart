import 'dart:async';
import 'distributed_service.dart' show DistributedService, ChainBrokenException;
import 'sqlite_service.dart';
import 'p2p_service.dart';

/// Hybrid Storage Service
/// Manages dual storage: SQLite (local) + MongoDB (server)
/// Handles sync and offline/online modes
class HybridStorageService {
  static HybridStorageService? _instance;
  
  // Singleton pattern
  static HybridStorageService get instance {
    _instance ??= HybridStorageService._();
    return _instance!;
  }

  HybridStorageService._();

  bool _isServerOnline = false;
  Timer? _syncTimer;
  String? _currentUserAddress;

  /// Initialize hybrid storage
  Future<void> initialize({required String userAddress}) async {
    _currentUserAddress = userAddress;
    
    // Check server status (with fallback to API call if health check fails)
    // Use longer timeout for Cloudflare Tunnel
    try {
      final backendUrl = DistributedService.getCurrentBackendUrl();
      final isCloudflareTunnel = backendUrl.contains('trycloudflare.com') || 
                                 backendUrl.contains('cloudflare');
      
      if (isCloudflareTunnel) {
        print('🌐 Cloudflare Tunnel detected, using extended timeout for server check...');
        _isServerOnline = await checkServerStatus().timeout(
          const Duration(seconds: 20), // Longer timeout for Cloudflare Tunnel
          onTimeout: () {
            print('⚠️ Server status check timed out, will try actual API calls when needed');
            return false;
          },
        );
      } else {
        _isServerOnline = await checkServerStatus();
      }
    } catch (e) {
      print('⚠️ Server status check error: $e');
      _isServerOnline = false;
    }
    
    // Start P2P server
    final p2pStarted = await P2PService.instance.startServer(
      userAddress: userAddress,
      port: 8080,
    );

    if (!p2pStarted) {
      print('⚠️ P2P server failed to start');
    }

    // Register peer info with server if online
    if (_isServerOnline && p2pStarted) {
      final myIp = P2PService.instance.getMyIp();
      final myPort = P2PService.instance.getMyPort();
      
      if (myIp != null && myIp != '127.0.0.1') {
        await DistributedService.registerPeer(
          userAddress: userAddress,
          ipAddress: myIp,
          port: myPort,
        );
        print('✅ Peer registered with server: $myIp:$myPort');
      }
    }

    // Set up message callback
    P2PService.instance.onMessageReceived = (message) {
      // Message already saved to SQLite by P2P service
      // Try to sync to server if online
      if (_isServerOnline) {
        _syncMessageToServer(message);
      }
    };

    // Start periodic sync
    _startSyncTimer();
    
    // Discover peers from server if online
    if (_isServerOnline) {
      await _discoverPeersFromServer();
    }
    
    // IMPORTANT: Restore peer connections from SQLite on app restart
    // This ensures P2P works even when server is offline
    await _restorePeerConnectionsFromSQLite();

    print('✅ Hybrid storage initialized');
    print('   Server online: $_isServerOnline');
    print('   P2P server: ${P2PService.instance.isServerRunning()}');
    print('   My IP: ${P2PService.instance.getMyIp()}');
    print('   My Port: ${P2PService.instance.getMyPort()}');
  }
  
  /// Restore peer connections from SQLite (for offline P2P after app restart)
  Future<void> _restorePeerConnectionsFromSQLite() async {
    try {
      print('🔄 Restoring peer connections from SQLite...');
      
      // CRITICAL FIX: When server is offline, load directly from SQLite to avoid delays
      // Don't try server first as it will timeout and waste time
      List<Map<String, dynamic>> allWorkspaces;
      if (_isServerOnline) {
        // Server is online - use hybrid method (tries server first, falls back to SQLite)
        allWorkspaces = await getUserWorkspaces(_currentUserAddress ?? '');
      } else {
        // Server is offline - load directly from SQLite (no server call, no timeout delay)
        print('   Server is offline - loading workspaces directly from SQLite...');
        allWorkspaces = await SQLiteService.instance.getUserWorkspaces(_currentUserAddress ?? '');
        print('   ✅ Loaded ${allWorkspaces.length} workspaces from SQLite');
      }
      
      if (allWorkspaces.isEmpty) {
        print('   No workspaces found - skipping peer restoration');
        return;
      }
      
      // Collect all unique member addresses from all workspaces
      final Set<String> memberAddresses = {};
      
      for (final workspace in allWorkspaces) {
        final workspaceId = workspace['workspace_id']?.toString() ?? 
                           workspace['workspaceId']?.toString() ?? '';
        if (workspaceId.isEmpty) continue;
        
        try {
          // CRITICAL FIX: When server is offline, load members directly from SQLite
          List<Map<String, dynamic>> members;
          if (_isServerOnline) {
            // Server is online - use hybrid method
            members = await getWorkspaceMembers(workspaceId);
          } else {
            // Server is offline - load directly from SQLite (no server call, no timeout delay)
            members = await SQLiteService.instance.getWorkspaceMembers(workspaceId);
            print('   ✅ Loaded ${members.length} members from SQLite for workspace $workspaceId');
          }
          
          for (final member in members) {
            final memberAddress = member['member_address']?.toString() ?? 
                                member['memberAddress']?.toString() ?? '';
            if (memberAddress.isNotEmpty && 
                memberAddress.toLowerCase() != _currentUserAddress?.toLowerCase()) {
              memberAddresses.add(memberAddress.toLowerCase());
            }
          }
        } catch (e) {
          print('   ⚠️ Error loading members for workspace $workspaceId: $e');
        }
      }
      
      print('   Found ${memberAddresses.length} unique workspace member(s) to connect');
      
      if (memberAddresses.isEmpty) {
        print('   No workspace members found - skipping peer restoration');
        print('   💡 Tip: Workspace members need to be cached in SQLite for offline P2P');
        return;
      }
      
      // Restore connections to each peer (non-blocking, in background)
      int successCount = 0;
      int attemptedCount = 0;
      final List<Future<bool>> connectionFutures = [];
      
      for (final memberAddress in memberAddresses) {
        attemptedCount++;
        
        // Try to get peer info from SQLite
        final peer = await SQLiteService.instance.getPeer(memberAddress);
        
        if (peer == null) {
          print('   ⚠️ Peer info not found in SQLite: $memberAddress');
          print('   💡 Tip: Peer info needs to be cached in SQLite for offline P2P');
          continue;
        }
        
        final ipAddress = peer['ip_address'] as String?;
        final port = peer['port'] as int?;
        
        if (ipAddress == null || port == null) {
          print('   ⚠️ Invalid peer info for $memberAddress: ip=$ipAddress, port=$port');
          continue;
        }
        
        // Try to connect (async, track result)
        final connectionFuture = P2PService.instance.connectToPeer(
          ipAddress: ipAddress,
          port: port,
          userAddress: memberAddress,
        );
        
        connectionFutures.add(connectionFuture);
        
        connectionFuture.then((connected) {
          if (connected) {
            successCount++;
            print('   ✅ Restored connection to peer: $memberAddress ($ipAddress:$port)');
          } else {
            print('   ⚠️ Failed to restore connection to $memberAddress (will retry on message send)');
          }
        }).catchError((e) {
          print('   ❌ Error restoring connection to $memberAddress: $e');
        });
      }
      
      // Wait longer for connections to establish (3 seconds for handshake)
      await Future.delayed(const Duration(seconds: 3));
      
      // Wait for all connection attempts to complete
      final results = await Future.wait(connectionFutures, eagerError: false);
      successCount = results.where((r) => r == true).length;
      
      print('✅ Peer restoration completed: $successCount/$attemptedCount connections attempted');
      if (successCount > 0) {
        print('   ✅ $successCount connection(s) successfully restored');
      }
      if (attemptedCount > successCount) {
        print('   ⚠️ ${attemptedCount - successCount} connection(s) failed (will retry on message send)');
      }
      if (successCount == 0 && attemptedCount > 0) {
        print('   💡 All connections failed - peers might be offline or on different network');
        print('   💡 P2P will retry connections when messages are sent');
      } else {
        print('   💡 Remaining connections will be established when messages are sent');
      }
    } catch (e) {
      print('❌ Restore peer connections error: $e');
    }
  }
  
  /// Discover peers from server (when online)
  Future<void> _discoverPeersFromServer() async {
    try {
      print('🔍 Discovering peers from server...');
      
      // Get all active peers from server
      final peers = await DistributedService.getAllPeers();
      
      if (peers.isEmpty) {
        print('   No active peers found');
        return;
      }

      print('   Found ${peers.length} active peer(s)');
      
      // Connect to each peer (except self)
      for (final peer in peers) {
        final peerAddress = peer['user_address'] as String?;
        final peerIp = peer['ip_address'] as String?;
        final peerPort = peer['port'] as int?;
        
        if (peerAddress == null || peerIp == null || peerPort == null) {
          continue;
        }
        
        // Skip self
        if (peerAddress.toLowerCase() == _currentUserAddress?.toLowerCase()) {
          continue;
        }
        
        // Save peer info to SQLite
        await SQLiteService.instance.savePeer(
          userAddress: peerAddress,
          ipAddress: peerIp,
          port: peerPort,
        );
        
        // Try to connect (non-blocking)
        P2PService.instance.connectToPeer(
          ipAddress: peerIp,
          port: peerPort,
          userAddress: peerAddress,
        ).then((connected) {
          if (connected) {
            print('   ✅ Connected to peer: $peerAddress ($peerIp:$peerPort)');
          } else {
            print('   ⚠️ Failed to connect to peer: $peerAddress');
          }
        }).catchError((e) {
          print('   ❌ Error connecting to peer $peerAddress: $e');
        });
      }
      
      print('✅ Peer discovery completed');
    } catch (e) {
      print('⚠️ Peer discovery error: $e');
    }
  }

  /// Start periodic sync timer
  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      // Refresh server status
      final wasOnline = _isServerOnline;
      await checkServerStatus();
      
      // If server just came back online, discover peers
      if (!wasOnline && _isServerOnline) {
        print('🔄 Server came back online - discovering peers...');
        await _discoverPeersFromServer();
      }
      
      // Sync unsynced data
      await syncToServer();
      
      // Periodically refresh peer info from server (if online)
      if (_isServerOnline) {
        await _discoverPeersFromServer();
      }
    });
  }

  /// Check server status
  /// Tries health check first, then falls back to actual API call if health check fails
  Future<bool> checkServerStatus() async {
    final wasOnline = _isServerOnline;
    
    // Try health check first
    _isServerOnline = await DistributedService.checkHealth();
    
    // If health check fails, try an actual API call to verify server is accessible
    // Health check can timeout but API calls might still work (especially with Cloudflare Tunnel)
    if (!_isServerOnline) {
      print('⚠️ Health check failed, trying actual API call to verify server...');
      try {
        // Try a lightweight API call (get user workspaces with timeout)
        // This is more reliable than health check for Cloudflare Tunnel
        final testUrl = DistributedService.getCurrentBackendUrl();
        print('🧪 Testing server with actual API call: $testUrl');
        
        // Try a simple API call with shorter timeout
        await DistributedService.getUserWorkspaces(
          '0x0000000000000000000000000000000000000000' // Dummy address for test
        ).timeout(
          const Duration(seconds: 8),
          onTimeout: () {
            return <Map<String, dynamic>>[];
          },
        );
        
        // If we got a response (even empty), server is online
        // Empty response means server responded but no workspaces (expected for dummy address)
        _isServerOnline = true;
        print('✅ Server is actually online (API call succeeded, health check was false negative)');
      } catch (e) {
        // API call also failed, server is likely offline
        print('❌ Server API call also failed: $e');
        _isServerOnline = false;
      }
    }
    
    if (wasOnline != _isServerOnline) {
      print('🔄 Server status changed: ${wasOnline ? "online" : "offline"} -> ${_isServerOnline ? "online" : "offline"}');
      if (!_isServerOnline) {
        print('⚠️ Server is now offline - app will use SQLite and P2P');
        print('💡 P2P will continue to work using cached peer info from SQLite');
      } else {
        print('✅ Server is now online - syncing data and discovering peers...');
        // Trigger sync when server comes back online
        syncToServer();
        // Discover peers when server comes back online
        _discoverPeersFromServer();
      }
    }
    
    return _isServerOnline;
  }

  /// Get user profile (hybrid)
  Future<Map<String, dynamic>?> getUserProfile(String address) async {
    // Always try server first (even if health check failed)
    // Individual API calls often work even when health check times out
    try {
      final profile = await DistributedService.getUserProfile(address).timeout(
        const Duration(seconds: 10),
        onTimeout: () => null,
      );
      
      if (profile != null) {
        // Mark server as online if we got data
        if (!_isServerOnline) {
          _isServerOnline = true;
          print('✅ Server is actually online (getUserProfile succeeded)');
        }
        
        // Cache to SQLite
        await SQLiteService.instance.saveUserProfile(
          address: address,
          username: profile['username'] ?? '',
          email: profile['email'] ?? '',
        );
        return profile;
      }
    } catch (e) {
      print('⚠️ Server get profile failed, trying local: $e');
      // Don't mark server as offline based on one failed call
    }

    // Fallback to SQLite
    return await SQLiteService.instance.getUserProfile(address);
  }

  /// Save user profile (hybrid)
  Future<Map<String, dynamic>> saveUserProfile({
    required String address,
    required String username,
    required String email,
  }) async {
    // Save to SQLite immediately (local)
    await SQLiteService.instance.saveUserProfile(
      address: address,
      username: username,
      email: email,
    );

    // Try to save to server if online
    if (_isServerOnline) {
      try {
        final result = await DistributedService.saveUserProfile(
          address: address,
          username: username,
          email: email,
        );
        
        if (result['success'] == true) {
          print('✅ Profile saved to server');
          return result;
        }
      } catch (e) {
        print('⚠️ Server save profile failed: $e');
      }
    }

    // Return success even if server is offline
    return {
      'success': true,
      'data': {
        'address': address,
        'username': username,
        'email': email,
      },
    };
  }

  /// Create workspace (hybrid)
  Future<String?> createWorkspace({
    required String workspaceName,
    required String inviterAddress,
  }) async {
    // Create in SQLite immediately
    final workspaceId = await SQLiteService.instance.createWorkspace(
      workspaceName: workspaceName,
      inviterAddress: inviterAddress,
    );

    if (workspaceId == null) {
      return null;
    }

    // Try to create on server if online
    if (_isServerOnline) {
      try {
        final serverWorkspaceId = await DistributedService.createWorkspace(
          workspaceName: workspaceName,
          inviterAddress: inviterAddress,
        );
        
        if (serverWorkspaceId != null) {
          print('✅ Workspace created on server');
          // Update SQLite with server ID if different
          // (For now, we use local ID)
        }
      } catch (e) {
        print('⚠️ Server create workspace failed: $e');
      }
    }

    return workspaceId;
  }

  /// Get user workspaces (hybrid)
  Future<List<Map<String, dynamic>>> getUserWorkspaces(String userAddress) async {
    // Try server first only if server was online (to avoid unnecessary timeouts when server is clearly off)
    // If server is offline, go directly to SQLite
    if (_isServerOnline) {
      try {
        print('🌐 Fetching workspaces from server for user $userAddress');
        final workspaces = await DistributedService.getUserWorkspaces(userAddress).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            print('⚠️ Get workspaces request timed out - falling back to SQLite');
            _isServerOnline = false; // Mark server as offline after timeout
            return <Map<String, dynamic>>[];
          },
        );
      
        if (workspaces.isNotEmpty) {
          print('✅ Server returned ${workspaces.length} workspaces');
          
          // Mark server as online if we got data
          if (!_isServerOnline) {
            _isServerOnline = true;
            print('✅ Server is actually online (getUserWorkspaces succeeded)');
          }
          
          // CRITICAL: Cache ALL workspaces to SQLite for offline access
          // This ensures workspaces show up even when server is off
          for (final workspace in workspaces) {
            final workspaceId = workspace['workspace_id']?.toString() ?? 
                               workspace['workspaceId']?.toString();
            final workspaceName = workspace['name']?.toString() ?? 
                                 workspace['workspaceName']?.toString() ?? '';
            final inviterAddress = workspace['inviter_address']?.toString() ?? 
                                  workspace['inviterAddress']?.toString() ?? '';
            
            if (workspaceId != null && workspaceId.isNotEmpty) {
              // Save workspace to SQLite (cache from server)
              await SQLiteService.instance.saveWorkspace(
                workspaceId: workspaceId,
                workspaceName: workspaceName,
                inviterAddress: inviterAddress,
                createdAt: workspace['created_at'] is int 
                    ? workspace['created_at'] as int
                    : (workspace['created_at'] is String
                        ? int.tryParse(workspace['created_at'] as String)
                        : null),
                timestamp: workspace['timestamp'] is int
                    ? workspace['timestamp'] as int
                    : (workspace['timestamp'] is String
                        ? int.tryParse(workspace['timestamp'] as String)
                        : null),
                previousHash: workspace['previous_hash']?.toString(),
                currentHash: workspace['current_hash']?.toString(),
              );
              print('💾 Cached workspace to SQLite: $workspaceName (ID: $workspaceId)');
            }
          }
          
          return workspaces;
        } else {
          // Server returned empty list - this is valid (user might have no workspaces)
          print('ℹ️ Server returned empty workspaces list - checking SQLite');
          // Continue to SQLite fallback below
        }
      } on TimeoutException catch (e) {
        print('⚠️ Server get workspaces timed out, trying local: $e');
        _isServerOnline = false; // Mark server as offline after timeout
        // Continue to SQLite fallback
      } catch (e) {
        print('⚠️ Server get workspaces failed, trying local: $e');
        _isServerOnline = false; // Mark server as offline after failure
        // Continue to SQLite fallback
      }
    } else {
      print('📦 Server is offline - loading workspaces directly from SQLite');
    }

    // Fallback to SQLite
    print('📦 Loading workspaces from SQLite for user $userAddress');
    final sqliteWorkspaces = await SQLiteService.instance.getUserWorkspaces(userAddress);
    print('✅ SQLite returned ${sqliteWorkspaces.length} workspaces');
    return sqliteWorkspaces;
  }

  /// Add message (hybrid - with P2P)
  Future<String?> addMessage({
    required String workspaceId,
    String? channelId,
    required String senderAddress,
    String? receiverAddress,
    required String messageText,
    String? fileId,
  }) async {
    // Save to SQLite immediately
    final messageId = await SQLiteService.instance.addMessage(
      workspaceId: workspaceId,
      channelId: channelId,
      senderAddress: senderAddress,
      receiverAddress: receiverAddress,
      messageText: messageText,
      fileId: fileId,
    );

    if (messageId == null) {
      return null;
    }

    // ALWAYS try P2P communication for channel messages (works even when server is off)
    // For direct messages: send to specific receiver
    // For channel messages: broadcast to all workspace members
    if (channelId != null) {
      // Channel message: ALWAYS broadcast via P2P (even if server is online or offline)
      print('📡 Broadcasting channel message via P2P to workspace members...');
      try {
        // Get workspace members (from server if online, from SQLite if offline)
        final members = await getWorkspaceMembers(workspaceId);
        print('   Found ${members.length} workspace members for P2P broadcast');
        
        if (members.isEmpty) {
          print('   ⚠️ No workspace members found - P2P broadcast cannot proceed');
          print('   💡 Tip: Make sure workspace members are cached to SQLite');
          print('   💡 Message is already saved to SQLite, will sync when server comes back');
          // Message is already saved to SQLite, so we can continue
          // P2P broadcast will work once members are cached
        }
        
        int successCount = 0;
        int attemptedCount = 0;
        
        for (final member in members) {
          final memberAddress = member['member_address']?.toString() ?? 
                              member['memberAddress']?.toString() ?? '';
          
          // Skip self
          if (memberAddress.isEmpty || memberAddress.toLowerCase() == senderAddress.toLowerCase()) {
            continue;
          }
          
          attemptedCount++;
          
          try {
            // Try to get peer info from SQLite first (works offline)
            var peer = await SQLiteService.instance.getPeer(memberAddress);
            
            // If not in SQLite and server is online, try to discover from server
            if (peer == null && _isServerOnline) {
              print('   Peer not in SQLite, trying to discover from server: $memberAddress');
              try {
                final serverPeer = await DistributedService.getPeer(memberAddress);
                if (serverPeer != null) {
                  // Save to SQLite for future use (even when server goes offline)
                  await SQLiteService.instance.savePeer(
                    userAddress: memberAddress,
                    ipAddress: serverPeer['ip_address'] as String,
                    port: serverPeer['port'] as int,
                  );
                  peer = {
                    'ip_address': serverPeer['ip_address'],
                    'port': serverPeer['port'],
                  };
                }
              } catch (e) {
                print('   ⚠️ Could not get peer from server: $e');
              }
            }
            
            if (peer != null) {
              final ipAddress = peer['ip_address'] as String?;
              final port = peer['port'] as int?;
              
              if (ipAddress != null && port != null) {
                print('   Connecting to peer: $memberAddress ($ipAddress:$port)');
                
                // Ensure connection exists
                final connected = await P2PService.instance.connectToPeer(
                  ipAddress: ipAddress,
                  port: port,
                  userAddress: memberAddress,
                );
                
                if (connected) {
                  // Wait a bit for connection to establish and handshake
                  await Future.delayed(const Duration(milliseconds: 500));
                  
                  // Send channel message via P2P (use the actual message ID from SQLite)
                  final sent = await P2PService.instance.sendChannelMessageToPeer(
                    receiverAddress: memberAddress,
                    content: messageText,
                    workspaceId: workspaceId,
                    channelId: channelId,
                    messageId: messageId, // Pass the actual message ID from SQLite
                  );

                  if (sent) {
                    successCount++;
                    print('   ✅ Channel message sent via P2P to $memberAddress');
                  } else {
                    print('   ⚠️ Failed to send to $memberAddress (connection timeout)');
                  }
                } else {
                  print('   ⚠️ Failed to connect to $memberAddress');
                }
            } else {
              print('   ⚠️ Invalid peer info for $memberAddress');
            }
            } else {
              print('   ⚠️ Peer info not found for $memberAddress');
              print('   💡 Tip: Peer info needs to be in SQLite for P2P to work offline');
              print('   💡 Solution: Connect to server once to cache peer info, or manually add peer info');
            }
          } catch (e) {
            print('   ⚠️ P2P send to $memberAddress failed: $e');
          }
        }
        
        if (successCount > 0) {
          print('✅ Channel message broadcasted to $successCount/$attemptedCount members via P2P');
        } else if (attemptedCount > 0) {
          print('⚠️ No P2P connections available for channel broadcast (attempted: $attemptedCount)');
          print('   💡 Tip: Make sure peers are on same network and have P2P server running');
        }
      } catch (e) {
        print('⚠️ P2P broadcast error: $e');
      }
    } else if (receiverAddress != null && receiverAddress.isNotEmpty) {
      // Direct message: send to specific receiver (works even when server is off)
      try {
        print('📡 Sending direct message via P2P to $receiverAddress...');
        
        // Try to get peer info from SQLite first (works offline)
        var peer = await SQLiteService.instance.getPeer(receiverAddress);
        
        // If not in SQLite and server is online, try to discover from server
        if (peer == null && _isServerOnline) {
          print('   Peer not in SQLite, trying to discover from server: $receiverAddress');
          try {
            final serverPeer = await DistributedService.getPeer(receiverAddress);
            if (serverPeer != null) {
              // Save to SQLite for future use (even when server goes offline)
              await SQLiteService.instance.savePeer(
                userAddress: receiverAddress,
                ipAddress: serverPeer['ip_address'] as String,
                port: serverPeer['port'] as int,
              );
              peer = {
                'ip_address': serverPeer['ip_address'],
                'port': serverPeer['port'],
              };
            }
          } catch (e) {
            print('   ⚠️ Could not get peer from server: $e');
          }
        }
        
        if (peer != null) {
          final ipAddress = peer['ip_address'] as String?;
          final port = peer['port'] as int?;
          
          if (ipAddress != null && port != null) {
            // Ensure connection exists
            final connected = await P2PService.instance.connectToPeer(
              ipAddress: ipAddress,
              port: port,
              userAddress: receiverAddress,
            );
            
            if (connected) {
              // Wait a bit for connection to establish and handshake
              await Future.delayed(const Duration(milliseconds: 500));
              
              // Send via P2P
              final sent = await P2PService.instance.sendMessageToPeer(
                receiverAddress: receiverAddress,
                content: messageText,
                workspaceId: workspaceId,
              );

              if (sent) {
                print('✅ Direct message sent via P2P to $receiverAddress');
              } else {
                print('⚠️ P2P message failed (connection timeout), will sync via server when online');
              }
            } else {
              print('⚠️ Failed to connect to peer $receiverAddress');
            }
          } else {
            print('⚠️ Invalid peer info for $receiverAddress');
          }
        } else {
          print('⚠️ Peer info not found for $receiverAddress (will work when peer comes online)');
        }
      } catch (e) {
        print('⚠️ P2P send error: $e');
      }
    }

    // Try to save to server if online
    if (_isServerOnline) {
      try {
        final serverMessageId = await DistributedService.addMessage(
          workspaceId: workspaceId,
          channelId: channelId,
          senderAddress: senderAddress,
          receiverAddress: receiverAddress,
          messageText: messageText,
          fileId: fileId,
        );

        if (serverMessageId != null) {
          // Mark as synced
          await SQLiteService.instance.markMessageSynced(messageId);
          print('✅ Message saved to server');
        }
      } catch (e) {
        print('⚠️ Server save message failed: $e');
      }
    }

    return messageId;
  }

  /// Get channel messages (hybrid)
  /// Returns messages from server if online and chain is valid
  /// Falls back to SQLite if server is off, chain is broken, or server fails
  /// Throws ChainBrokenException only if chain is broken (to hide messages)
  Future<List<Map<String, dynamic>>> getChannelMessages({
    required String workspaceId,
    required String channelId,
  }) async {
    List<Map<String, dynamic>> serverMessages = [];
    
    // Try server first if online
    if (_isServerOnline) {
      try {
        print('🌐 Fetching messages from server for channel $channelId in workspace $workspaceId');
        serverMessages = await DistributedService.getChannelMessages(
          workspaceId: workspaceId,
          channelId: channelId,
        );
        
        print('✅ Server returned ${serverMessages.length} messages for channel $channelId');
        
        // Debug: Log message structure
        if (serverMessages.isNotEmpty) {
          print('📋 First server message keys: ${serverMessages.first.keys.toList()}');
          print('📋 First server message content: ${serverMessages.first['content']}');
          print('📋 First server message_text: ${serverMessages.first['message_text']}');
          print('📋 First server timestamp: ${serverMessages.first['timestamp']} (type: ${serverMessages.first['timestamp'].runtimeType})');
        } else {
          print('⚠️ Server returned empty messages array!');
        }
        
        // Cache server messages to SQLite (for offline access)
        // IMPORTANT: Only cache messages that don't already exist in SQLite
        // This prevents unnecessary re-caching and potential duplication issues
        if (serverMessages.isNotEmpty) {
          // First, check how many messages are already in SQLite
          final existingMessages = await SQLiteService.instance.getChannelMessages(
            workspaceId: workspaceId,
            channelId: channelId,
          );
          final existingMessageIds = existingMessages
              .map((m) => m['message_id']?.toString())
              .whereType<String>()
              .toSet();
          
          print('💾 Checking ${serverMessages.length} server messages against ${existingMessages.length} SQLite messages');
          int cached = 0;
          int skipped = 0;
          
          for (final msg in serverMessages) {
            try {
              // Use message_id from server if available (CRITICAL for deduplication)
              final messageId = msg['message_id']?.toString() ?? 
                               msg['id']?.toString();
              
              if (messageId == null || messageId.isEmpty) {
                print('⚠️ Skipping message without message_id');
                skipped++;
                continue;
              }
              
              // Skip if message already exists in SQLite (avoid unnecessary caching)
              if (existingMessageIds.contains(messageId)) {
                skipped++;
                continue;
              }
              
              // Only cache messages that don't already exist
              final result = await SQLiteService.instance.addMessage(
                workspaceId: workspaceId,
                channelId: channelId,
                senderAddress: msg['sender_address'] ?? msg['senderAddress'] ?? '',
                messageText: msg['message_text'] ?? msg['messageText'] ?? '',
                fileId: msg['file_id'] ?? msg['fileId'],
                providedMessageId: messageId, // CRITICAL: Pass server message_id to prevent duplicates
              );
              
              if (result != null && result == messageId) {
                cached++;
                existingMessageIds.add(messageId); // Track cached message
              } else {
                skipped++; // Message failed to add
              }
            } catch (e) {
              // Ignore duplicate errors (message might already exist)
              if (e.toString().contains('UNIQUE constraint') || 
                  e.toString().contains('already exists') ||
                  e.toString().contains('duplicate')) {
                skipped++;
              } else {
                print('⚠️ Cache message error: $e');
                skipped++; // Count as skipped on error
              }
            }
          }
          
          if (cached > 0) {
            print('✅ Messages cached: $cached new, $skipped skipped (already exist)');
          } else if (skipped > 0) {
            print('ℹ️ All ${serverMessages.length} server messages already cached ($skipped skipped)');
          }
        }
        
        // IMPORTANT: When server is online, cache messages to SQLite but return SQLite messages
        // This prevents duplication from multiple sources (server + P2P + sync timer)
        // Server messages are cached to SQLite above, so SQLite is the single source of truth
        print('📦 Server messages cached to SQLite, loading from SQLite to prevent duplication...');
        
        // Load from SQLite (which now includes server messages + P2P messages)
        final sqliteMessages = await SQLiteService.instance.getChannelMessages(
          workspaceId: workspaceId,
          channelId: channelId,
        );
        
        print('✅ SQLite returned ${sqliteMessages.length} messages (includes server + P2P)');
        
        // Convert SQLite format to UI format
        final convertedMessages = sqliteMessages.map((msg) {
          // Handle timestamp conversion
          dynamic timestamp = msg['timestamp'];
          DateTime dateTime;
          if (timestamp is int) {
            dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
          } else if (timestamp is String) {
            dateTime = DateTime.tryParse(timestamp) ?? DateTime.now();
          } else if (timestamp is DateTime) {
            dateTime = timestamp;
          } else {
            dateTime = DateTime.now();
          }
          
          return {
            'message_id': msg['message_id'],
            'messageText': msg['message_text'] ?? msg['messageText'] ?? '',
            'message_text': msg['message_text'] ?? msg['messageText'] ?? '',
            'sender_address': msg['sender_address'] ?? msg['senderAddress'] ?? '',
            'senderAddress': msg['sender_address'] ?? msg['senderAddress'] ?? '',
            'receiver_address': msg['receiver_address'] ?? msg['receiverAddress'],
            'receiverAddress': msg['receiver_address'] ?? msg['receiverAddress'],
            'workspace_id': msg['workspace_id'] ?? msg['workspaceId'] ?? workspaceId,
            'workspaceId': msg['workspace_id'] ?? msg['workspaceId'] ?? workspaceId,
            'channel_id': msg['channel_id'] ?? msg['channelId'] ?? channelId,
            'channelId': msg['channel_id'] ?? msg['channelId'] ?? channelId,
            'file_id': msg['file_id'] ?? msg['fileId'],
            'fileId': msg['file_id'] ?? msg['fileId'],
            'timestamp': dateTime,
            'sender': msg['sender_address'] ?? msg['senderAddress'] ?? '',
            'senderName': msg['sender_address'] ?? msg['senderAddress'] ?? '',
            'content': msg['message_text'] ?? msg['messageText'] ?? '',
            'type': 'text',
            'userAddress': msg['sender_address'] ?? msg['senderAddress'] ?? '',
          };
        }).toList();
        
        // Log if server returned empty but SQLite has messages
        if (serverMessages.isEmpty && sqliteMessages.isNotEmpty) {
          print('⚠️ Server returned empty messages but SQLite has ${sqliteMessages.length} cached messages');
          print('   This might indicate:');
          print('   1. Server database is empty for this channel');
          print('   2. Workspace/channel ID mismatch');
          print('   3. Server query issue');
          print('   💡 Using SQLite messages (includes P2P messages)');
        }
        
        return convertedMessages;
      } on ChainBrokenException catch (e) {
        // Chain is broken - this channel's integrity is compromised
        print('❌ Chain broken for channel $channelId - hiding messages');
        print('   Broken at: ${e.brokenAt}');
        print('   Details: ${e.details}');
        // Don't fallback to SQLite for broken chains - hide all messages (security)
        // This ensures chain broken validation is shown to user
        rethrow;
      } catch (e) {
        // Server error (network, timeout, etc.) - fallback to SQLite
        print('⚠️ Server get messages failed, trying local: $e');
        print('   Error type: ${e.runtimeType}');
      }
    }

    // Fallback to SQLite (when server is off, or server failed, or no server messages)
    print('📦 Loading messages from SQLite for channel $channelId');
    final sqliteMessages = await SQLiteService.instance.getChannelMessages(
      workspaceId: workspaceId,
      channelId: channelId,
    );
    
    print('✅ SQLite returned ${sqliteMessages.length} messages');
    
    // Debug: Log first SQLite message if available
    if (sqliteMessages.isNotEmpty) {
      print('📋 First SQLite message keys: ${sqliteMessages.first.keys.toList()}');
      print('📋 First SQLite message_text: ${sqliteMessages.first['message_text']}');
    }
    
    // Convert SQLite format to UI format
    final convertedMessages = sqliteMessages.map((msg) {
      // Handle timestamp conversion
      dynamic timestamp = msg['timestamp'];
      DateTime dateTime;
      if (timestamp is int) {
        dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      } else if (timestamp is String) {
        dateTime = DateTime.tryParse(timestamp) ?? DateTime.now();
      } else if (timestamp is DateTime) {
        dateTime = timestamp;
      } else {
        dateTime = DateTime.now();
      }
      
      return {
        'message_id': msg['message_id'],
        'messageText': msg['message_text'] ?? msg['messageText'] ?? '',
        'message_text': msg['message_text'] ?? msg['messageText'] ?? '',
        'sender_address': msg['sender_address'] ?? msg['senderAddress'] ?? '',
        'senderAddress': msg['sender_address'] ?? msg['senderAddress'] ?? '',
        'receiver_address': msg['receiver_address'] ?? msg['receiverAddress'],
        'receiverAddress': msg['receiver_address'] ?? msg['receiverAddress'],
        'workspace_id': msg['workspace_id'] ?? msg['workspaceId'] ?? workspaceId,
        'workspaceId': msg['workspace_id'] ?? msg['workspaceId'] ?? workspaceId,
        'channel_id': msg['channel_id'] ?? msg['channelId'] ?? channelId,
        'channelId': msg['channel_id'] ?? msg['channelId'] ?? channelId,
        'file_id': msg['file_id'] ?? msg['fileId'],
        'fileId': msg['file_id'] ?? msg['fileId'],
        'timestamp': dateTime,
        'sender': msg['sender_address'] ?? msg['senderAddress'] ?? '',
        'senderName': msg['sender_address'] ?? msg['senderAddress'] ?? '',
        'content': msg['message_text'] ?? msg['messageText'] ?? '',
        'type': 'text',
        'userAddress': msg['sender_address'] ?? msg['senderAddress'] ?? '',
      };
    }).toList();
    
    if (convertedMessages.isEmpty && serverMessages.isEmpty) {
      print('⚠️ No messages found in SQLite or server for channel $channelId');
    }
    
    return convertedMessages;
  }

  /// Get direct messages (hybrid)
  Future<List<Map<String, dynamic>>> getDirectMessages({
    required String user1Address,
    required String user2Address,
  }) async {
    // Try server first if online
    if (_isServerOnline) {
      try {
        final messages = await DistributedService.getDirectMessages(
          user1Address: user1Address,
          user2Address: user2Address,
        );
        
        if (messages.isNotEmpty) {
          // Cache to SQLite
          for (final msg in messages) {
            await SQLiteService.instance.addMessage(
              workspaceId: '',
              senderAddress: msg['sender_address'] ?? msg['senderAddress'] ?? '',
              receiverAddress: msg['receiver_address'] ?? msg['receiverAddress'],
              messageText: msg['message_text'] ?? msg['messageText'] ?? '',
            );
          }
          return messages;
        }
      } catch (e) {
        print('⚠️ Server get direct messages failed, trying local: $e');
      }
    }

    // Fallback to SQLite - convert format for UI
    final sqliteMessages = await SQLiteService.instance.getDirectMessages(
      user1Address: user1Address,
      user2Address: user2Address,
    );
    
    // Convert SQLite format to UI format
    return sqliteMessages.map((msg) => {
      'message_id': msg['message_id'],
      'messageText': msg['message_text'] ?? msg['messageText'] ?? '',
      'message_text': msg['message_text'] ?? msg['messageText'] ?? '',
      'sender_address': msg['sender_address'] ?? msg['senderAddress'] ?? '',
      'senderAddress': msg['sender_address'] ?? msg['senderAddress'] ?? '',
      'receiver_address': msg['receiver_address'] ?? msg['receiverAddress'],
      'receiverAddress': msg['receiver_address'] ?? msg['receiverAddress'],
      'timestamp': msg['timestamp'] is int 
          ? DateTime.fromMillisecondsSinceEpoch(msg['timestamp'] as int)
          : (msg['timestamp'] is String 
              ? DateTime.tryParse(msg['timestamp'] as String) ?? DateTime.now()
              : DateTime.now()),
      'sender': msg['sender_address'] ?? msg['senderAddress'] ?? '',
      'senderName': msg['sender_address'] ?? msg['senderAddress'] ?? '',
      'content': msg['message_text'] ?? msg['messageText'] ?? '',
      'type': 'text',
    }).toList();
  }

  /// Sync unsynced data to server
  Future<void> syncToServer() async {
    if (!_isServerOnline) {
      return;
    }

    try {
      print('🔄 Syncing to server...');

      // Get unsynced messages
      final unsyncedMessages = await SQLiteService.instance.getUnsyncedMessages();

      for (final msg in unsyncedMessages) {
        try {
          final messageId = await DistributedService.addMessage(
            workspaceId: msg['workspace_id'] ?? '',
            channelId: msg['channel_id'],
            senderAddress: msg['sender_address'] ?? '',
            receiverAddress: msg['receiver_address'],
            messageText: msg['message_text'] ?? '',
            fileId: msg['file_id'],
          );

          if (messageId != null) {
            await SQLiteService.instance.markMessageSynced(msg['message_id'] as String);
            print('✅ Synced message: ${msg['message_id']}');
          }
        } catch (e) {
          print('⚠️ Sync message error: $e');
        }
      }

      print('✅ Sync completed: ${unsyncedMessages.length} messages');
    } catch (e) {
      print('❌ Sync to server error: $e');
    }
  }

  /// Sync message to server (internal)
  Future<void> _syncMessageToServer(Map<String, dynamic> message) async {
    if (!_isServerOnline) {
      return;
    }

    try {
      await DistributedService.addMessage(
        workspaceId: message['workspace_id'] ?? '',
        senderAddress: message['sender_address'] ?? '',
        receiverAddress: message['receiver_address'],
        messageText: message['content'] ?? '',
      );
    } catch (e) {
      print('⚠️ Sync message to server error: $e');
    }
  }

  /// Connect to peer by IP
  Future<bool> connectToPeer({
    required String ipAddress,
    required int port,
    String? userAddress,
  }) async {
    return await P2PService.instance.connectToPeer(
      ipAddress: ipAddress,
      port: port,
      userAddress: userAddress,
    );
  }

  /// Connect to peer by user address
  Future<bool> connectToPeerByAddress(String userAddress) async {
    return await P2PService.instance.connectToPeerByAddress(userAddress);
  }

  /// Get workspace members (hybrid)
  /// Tries server first only if server is online, otherwise uses SQLite directly
  Future<List<Map<String, dynamic>>> getWorkspaceMembers(String workspaceId) async {
    // Try server first only if server was online (to avoid unnecessary timeouts when server is clearly off)
    // If server is offline, go directly to SQLite
    if (_isServerOnline) {
      try {
        print('🌐 Fetching workspace members from server for workspace $workspaceId');
        final members = await DistributedService.getWorkspaceMembers(workspaceId).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            print('⚠️ Get workspace members request timed out - falling back to SQLite');
            _isServerOnline = false; // Mark server as offline after timeout
            return <Map<String, dynamic>>[];
          },
        );
      
        if (members.isNotEmpty) {
          print('✅ Server returned ${members.length} workspace members');
          
          // Mark server as online if we got data
          if (!_isServerOnline) {
            _isServerOnline = true;
            print('✅ Server is actually online (health check was false negative)');
          }
          
          // Cache ALL members to SQLite (critical for P2P to work offline)
          for (final member in members) {
            final memberAddress = member['member_address'] ?? member['memberAddress'] ?? '';
            final displayName = member['display_name'] ?? member['memberDisplayName'];
            
            await SQLiteService.instance.addWorkspaceMember(
              workspaceId: workspaceId,
              memberAddress: memberAddress,
              displayName: displayName,
            );
            print('✅ Cached member to SQLite: $memberAddress (${displayName ?? 'No name'})');
          }
          
          return members;
        }
      } catch (e) {
        print('⚠️ Server get workspace members failed, trying local: $e');
        print('   Error type: ${e.runtimeType}');
        // Mark server as offline if we get a clear server error
        if (e.toString().contains('502') || 
            e.toString().contains('500') || 
            e.toString().contains('503') ||
            e.toString().contains('504') ||
            e.toString().contains('SocketException') ||
            e.toString().contains('TimeoutException')) {
          print('🔄 Server appears to be offline (error ${e.toString()})');
          _isServerOnline = false;
        }
      }
    } else {
      print('📦 Server is offline - loading workspace members directly from SQLite');
    }

    // Fallback to SQLite (works offline)
    print('📦 Loading workspace members from SQLite for workspace $workspaceId');
    final sqliteMembers = await SQLiteService.instance.getWorkspaceMembers(workspaceId);
    print('✅ SQLite returned ${sqliteMembers.length} workspace members');
    return sqliteMembers;
  }

  /// Get workspace channels (hybrid)
  Future<List<String>> getWorkspaceChannels({
    required String workspaceId,
    String? memberAddress,
  }) async {
    // Try server first only if server is online (to avoid unnecessary timeouts when server is clearly off)
    // If server is offline, go directly to SQLite
    if (_isServerOnline) {
      try {
        print('🌐 Fetching channels from server for workspace $workspaceId');
        final channels = await DistributedService.getWorkspaceChannels(
          workspaceId: workspaceId,
          memberAddress: memberAddress,
        ).timeout(
          const Duration(seconds: 15), // Longer timeout for Cloudflare Tunnel
          onTimeout: () {
            print('⚠️ Get channels request timed out - falling back to SQLite');
            _isServerOnline = false; // Mark server as offline after timeout
            throw TimeoutException('Channel fetch timed out', const Duration(seconds: 15));
          },
        );
      
        // If we got here, server responded successfully
        if (channels.isNotEmpty) {
          print('✅ Server returned ${channels.length} channels');
          
          // Mark server as online if we got data
          if (!_isServerOnline) {
            _isServerOnline = true;
            print('✅ Server is actually online (health check was false negative)');
          }
          
          // Cache ALL channels to SQLite with complete MongoDB data
          // This ensures they are available offline with all metadata
          // Server returns channel names (strings), but we need to get full channel data
          // For now, save what we have - full channel objects will be cached when available
          for (final channelName in channels) {
            // Normalize channel ID (lowercase for database)
            final normalizedChannelId = channelName.toLowerCase().trim();
            
            // Save to SQLite with proper display name
            // Note: Full channel data (members, is_private, etc.) will be saved when channel is created
            await SQLiteService.instance.saveChannel(
              workspaceId: workspaceId,
              channelId: normalizedChannelId,
              channelName: channelName, // Keep original case for display
              creatorAddress: null, // Will be updated if available
              syncedToServer: true, // This came from server
            );
            print('✅ Cached channel to SQLite: $channelName (ID: $normalizedChannelId)');
          }
          
          return channels;
        } else {
          // Server responded with empty list - this is valid (workspace might have no channels)
          // But we should still fall back to SQLite to show cached channels
          print('ℹ️ Server returned empty channels list - checking SQLite for cached channels');
          // Continue to SQLite fallback below
        }
      } on TimeoutException catch (e) {
        print('⚠️ Server get workspace channels timed out, trying local: $e');
        _isServerOnline = false; // Mark server as offline after timeout
        // Continue to SQLite fallback
      } catch (e) {
        print('⚠️ Server get workspace channels failed, trying local: $e');
        print('   Error type: ${e.runtimeType}');
        // Mark server as offline if we get a clear server error (502, 500, etc.)
        if (e.toString().contains('502') || 
            e.toString().contains('500') || 
            e.toString().contains('503') ||
            e.toString().contains('504') ||
            e.toString().contains('SocketException') ||
            e.toString().contains('TimeoutException')) {
          print('🔄 Server appears to be offline (error ${e.toString()})');
          _isServerOnline = false;
        }
        // Continue to SQLite fallback
      }
    } else {
      print('📦 Server is offline - loading channels directly from SQLite');
    }

    // Fallback to SQLite (with member filtering like MongoDB)
    print('📦 Loading channels from SQLite for workspace $workspaceId');
    final sqliteChannels = await SQLiteService.instance.getWorkspaceChannels(
      workspaceId,
      memberAddress: memberAddress,  // Pass member address for proper filtering
    );
    print('✅ SQLite returned ${sqliteChannels.length} channels');
    
    // CRITICAL FIX: Ensure ALL channels are properly loaded from SQLite
    // SQLiteService.getWorkspaceChannels() already combines channels from both:
    // 1. channels table (explicitly saved channels)
    // 2. messages table (channels that have messages)
    // So we just need to ensure General and Random are present
    
    // Ensure General and Random are always present
    final channelSet = sqliteChannels.toSet();
    bool generalExists = channelSet.contains('General') || channelSet.contains('general');
    bool randomExists = channelSet.contains('Random') || channelSet.contains('random');
    
    if (!generalExists) {
      sqliteChannels.insert(0, 'General');
      // Save General to SQLite for offline access
      await SQLiteService.instance.saveChannel(
        workspaceId: workspaceId,
        channelId: 'general',
        channelName: 'General',
        creatorAddress: null,
      );
      print('✅ Saved General channel to SQLite');
    }
    if (!randomExists) {
      final generalIndex = sqliteChannels.indexWhere((c) => c.toLowerCase() == 'general');
      sqliteChannels.insert(generalIndex >= 0 ? generalIndex + 1 : 0, 'Random');
      // Save Random to SQLite for offline access
      await SQLiteService.instance.saveChannel(
        workspaceId: workspaceId,
        channelId: 'random',
        channelName: 'Random',
        creatorAddress: null,
      );
      print('✅ Saved Random channel to SQLite');
    }
    
    print('✅ Final channels list: ${sqliteChannels.length} channels (General and Random ensured)');
    
    return sqliteChannels;
  }

  /// Save channel to SQLite (for offline access)
  Future<bool> saveChannelToSQLite({
    required String workspaceId,
    required String channelId,
    String? channelName,
    String? creatorAddress,
  }) async {
    return await SQLiteService.instance.saveChannel(
      workspaceId: workspaceId,
      channelId: channelId,
      channelName: channelName,
      creatorAddress: creatorAddress,
    );
  }

  /// Get peer info
  Future<Map<String, dynamic>?> getPeer(String userAddress) async {
    return await SQLiteService.instance.getPeer(userAddress);
  }

  /// Save peer info
  Future<bool> savePeer({
    required String userAddress,
    required String ipAddress,
    required int port,
  }) async {
    // Save to SQLite
    final saved = await SQLiteService.instance.savePeer(
      userAddress: userAddress,
      ipAddress: ipAddress,
      port: port,
    );

    // Try to connect
    if (saved) {
      await P2PService.instance.connectToPeer(
        ipAddress: ipAddress,
        port: port,
        userAddress: userAddress,
      );
    }

    return saved;
  }

  /// Get my P2P info
  Map<String, dynamic>? getMyP2PInfo() {
    final ip = P2PService.instance.getMyIp();
    final port = P2PService.instance.getMyPort();
    
    if (ip == null) return null;

    return {
      'ip_address': ip,
      'port': port,
      'user_address': _currentUserAddress,
    };
  }

  /// Check if server is online
  bool isServerOnline() => _isServerOnline;

  /// Cleanup
  void dispose() {
    _syncTimer?.cancel();
    P2PService.instance.stopServer();
  }
}

