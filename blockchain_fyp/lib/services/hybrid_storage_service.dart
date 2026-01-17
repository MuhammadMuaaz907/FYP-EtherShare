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
  bool _isSyncing = false; // CRITICAL: Lock to prevent concurrent syncs

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
      // CRITICAL FIX: Only sync to server if message is not already synced
      // This prevents re-syncing messages that are already on server
      if (_isServerOnline) {
        _syncMessageToServerIfNeeded(message);
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
        print('🔗 Chain state already saved - offline messages will link to server chain');
      } else {
        print('✅ Server is now online - syncing data and discovering peers...');
        // CRITICAL FIX: Don't trigger sync here - let periodic timer handle it
        // This prevents multiple sync triggers when server comes online
        // Sync will happen automatically on next timer tick (within 30 seconds)
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
    // CRITICAL: Determine message state based on server status
    // If server is online, mark as ONLINE_CONFIRMED
    // If server is offline, mark as OFFLINE_LOCAL (will be changed to PENDING_SYNC when syncing)
    final messageState = _isServerOnline ? 'ONLINE_CONFIRMED' : 'OFFLINE_LOCAL';
    
    // Save to SQLite immediately
    final messageId = await SQLiteService.instance.addMessage(
      workspaceId: workspaceId,
      channelId: channelId,
      senderAddress: senderAddress,
      receiverAddress: receiverAddress,
      messageText: messageText,
      fileId: fileId,
      messageState: messageState, // CRITICAL: Set proper state
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
        // CRITICAL FIX: Retrieve message from SQLite to get encrypted fields and hash fields
        // Backend requires encrypted_message + iv + payload_hash for v2 messages
        final db = await SQLiteService.instance.database;
        final messageRecord = await db.query(
          'messages',
          where: 'message_id = ?',
          whereArgs: [messageId],
          limit: 1,
        );
        
        if (messageRecord.isEmpty) {
          print('❌ [SEND FAILED] Message not found in SQLite after insert: $messageId');
          return null;
        }
        
        final msg = messageRecord.first;
        final encryptedMessage = msg['encrypted_message'] as String?;
        final iv = msg['iv'] as String?;
        final payloadHash = msg['payload_hash'] as String?;
        final previousHash = msg['previous_hash'] as String?;
        final currentHash = msg['current_hash'] as String?;
        final hashVersion = msg['hash_version'] as int?;
        
        // CRITICAL: HARD GUARD - Validate ALL required fields before sending
        // This prevents sending messages with incomplete crypto operations
        final effectiveHashVersion = hashVersion ?? 2;
        final isV2 = effectiveHashVersion == 2;
        
        // Safe substring helper (shared across method)
        String safeSubstring(String? str, int len) {
          if (str == null || str.isEmpty) return '';
          return str.length > len ? str.substring(0, len) : str;
        }
        
        // CRITICAL: Log all fields for debugging
        print('📤 [SEND] Preparing to send message to server');
        print('   Message ID: $messageId');
        print('   Workspace: $workspaceId, Channel: ${channelId ?? "DM"}');
        print('   Hash version: $effectiveHashVersion');
        
        // HARD GUARD #1: Validate hash version
        if (effectiveHashVersion != 2 && effectiveHashVersion != 1) {
          print('❌ [SEND BLOCKED] Invalid hash_version: $effectiveHashVersion (must be 1 or 2)');
          return null;
        }
        
        // HARD GUARD #2: For v2, validate ALL required crypto fields
        if (isV2) {
          if (encryptedMessage == null || encryptedMessage.isEmpty) {
            print('❌ [SEND BLOCKED] v2 message missing encrypted_message');
            print('   ⚠️ Crypto operations may not have completed - message not ready to send');
            return null;
          }
          if (iv == null || iv.isEmpty) {
            print('❌ [SEND BLOCKED] v2 message missing iv');
            print('   ⚠️ Crypto operations may not have completed - message not ready to send');
            return null;
          }
          if (payloadHash == null || payloadHash.isEmpty) {
            print('❌ [SEND BLOCKED] v2 message missing payload_hash');
            print('   ⚠️ Crypto operations may not have completed - message not ready to send');
            return null;
          }
          if (currentHash == null || currentHash.isEmpty) {
            print('❌ [SEND BLOCKED] v2 message missing current_hash');
            print('   ⚠️ Hash chain calculation may not have completed - message not ready to send');
            return null;
          }
        }
        
        // HARD GUARD #3: Validate previous_hash (handle genesis properly)
        String validatedPreviousHash;
        if (previousHash == null || previousHash.isEmpty) {
          print('⚠️ [GENESIS] previous_hash is empty - using "0" for genesis message');
          validatedPreviousHash = '0';
        } else {
          validatedPreviousHash = previousHash;
        }
        
        // HARD GUARD #4: Validate current_hash format (should be 64-char hex)
        if (isV2 && currentHash != null && currentHash.isNotEmpty) {
          if (currentHash.length != 64 || !RegExp(r'^[a-f0-9]{64}$', caseSensitive: false).hasMatch(currentHash)) {
            print('❌ [SEND BLOCKED] Invalid current_hash format (expected 64-char hex, got ${currentHash.length} chars)');
            print('   Hash: ${safeSubstring(currentHash, 32)}...');
            return null;
          }
        }
        
        // HARD GUARD #5: Validate payload_hash format (should be 64-char hex)
        if (isV2 && payloadHash != null && payloadHash.isNotEmpty) {
          if (payloadHash.length != 64 || !RegExp(r'^[a-f0-9]{64}$', caseSensitive: false).hasMatch(payloadHash)) {
            print('❌ [SEND BLOCKED] Invalid payload_hash format (expected 64-char hex, got ${payloadHash.length} chars)');
            print('   Hash: ${safeSubstring(payloadHash, 32)}...');
            return null;
          }
        }
        
        // Log validated fields
        print('   ✅ Has encrypted_message: ${encryptedMessage != null && encryptedMessage.isNotEmpty}');
        print('   ✅ Has iv: ${iv != null && iv.isNotEmpty}');
        print('   ✅ Has payload_hash: ${payloadHash != null && payloadHash.isNotEmpty}');
        if (payloadHash != null && payloadHash.isNotEmpty) {
          print('   Payload hash: ${safeSubstring(payloadHash, 16)}...');
        }
        print('   ✅ Has previous_hash: ${validatedPreviousHash.isNotEmpty}');
        print('   Previous hash: ${safeSubstring(validatedPreviousHash, 16)}... (${validatedPreviousHash == '0' ? 'GENESIS' : 'CHAIN'})');
        print('   ✅ Has current_hash: ${currentHash != null && currentHash.isNotEmpty}');
        if (currentHash != null && currentHash.isNotEmpty) {
          print('   Current hash: ${safeSubstring(currentHash, 16)}...');
        }
        
        // CRITICAL: Verify genesis message handling
        if (validatedPreviousHash == '0') {
          print('🔗 [GENESIS] This is the first message in channel (previous_hash = 0)');
        }
        
        print('✅ [SEND VALIDATION] All required fields present - message ready to send');
        
        final serverMessageId = await DistributedService.addMessage(
          workspaceId: workspaceId,
          channelId: channelId,
          senderAddress: senderAddress,
          receiverAddress: receiverAddress,
          messageText: hashVersion == 1 ? messageText : null, // Only send plaintext for v1
          encryptedMessage: encryptedMessage, // REQUIRED for v2
          iv: iv, // REQUIRED for v2
          fileId: fileId,
          messageId: messageId, // Pass message ID for idempotency
          previousHash: validatedPreviousHash, // Pass validated previous_hash for chain integrity
          currentHash: currentHash, // Pass current_hash for chain integrity
          payloadHash: payloadHash, // REQUIRED for v2
          hashVersion: hashVersion ?? 2, // Default to 2 for new messages
        );

        if (serverMessageId != null) {
          // CRITICAL FIX: If server returned different messageId, update SQLite message
          // This prevents duplicates when server messages are cached back
          if (serverMessageId != messageId) {
            print('🔄 Server returned different messageId: $messageId -> $serverMessageId');
            print('   Updating SQLite message to use server messageId to prevent duplicates');
            
            try {
              final updated = await SQLiteService.instance.updateMessageId(
                oldMessageId: messageId,
                newMessageId: serverMessageId,
              );
              
              if (updated) {
                print('✅ Updated SQLite messageId: $messageId -> $serverMessageId');
                // Return server messageId for consistency
                return serverMessageId;
              } else {
                print('⚠️ Failed to update messageId, keeping original: $messageId');
              }
            } catch (e) {
              print('⚠️ Error updating messageId: $e');
              // Continue with original messageId
            }
          } else {
            // Message IDs match, just mark as synced
            await SQLiteService.instance.markMessageSynced(messageId);
          }
          print('✅ Message saved to server with ID: ${serverMessageId != messageId ? serverMessageId : messageId}');
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
  /// [sinceTimestamp] - Optional: Only fetch messages after this timestamp (for incremental loading)
  Future<List<Map<String, dynamic>>> getChannelMessages({
    required String workspaceId,
    required String channelId,
    int? sinceTimestamp, // Only fetch messages after this timestamp (milliseconds)
  }) async {
    List<Map<String, dynamic>> serverMessages = [];
    
    // Try server first if online
    // CRITICAL FIX: If sinceTimestamp is provided, we're doing incremental load (polling)
    // In this case, only fetch from server if we need to, otherwise rely on SQLite
    if (_isServerOnline) {
      // If sinceTimestamp is provided, this is a polling/incremental check
      // For incremental checks, prefer SQLite first (faster, already has latest messages)
      // Only fetch from server if we suspect there might be new messages
      if (sinceTimestamp != null) {
        print('🔄 Incremental message check: Only fetching new messages since ${DateTime.fromMillisecondsSinceEpoch(sinceTimestamp)}');
        // For incremental checks, load from SQLite first (P2P messages are already in SQLite)
        // We'll only check server if SQLite doesn't have recent messages
        final sqliteResult = await SQLiteService.instance.getChannelMessages(
          workspaceId: workspaceId,
          channelId: channelId,
          sinceTimestamp: sinceTimestamp,
        );
        
        final sqliteMessages = sqliteResult['messages'] as List<Map<String, dynamic>>? ?? [];
        final chainIntegrityFailed = sqliteResult['chainIntegrityFailed'] as bool? ?? false;
        
        // Check chain integrity failure
        if (chainIntegrityFailed) {
          final failureReason = sqliteResult['chainFailureReason'] as String? ?? 'unknown';
          final brokenAt = sqliteResult['chainBrokenAt'] as String? ?? 'unknown';
          print('⚠️ Chain integrity failed in SQLite: $failureReason at $brokenAt');
          // Continue to return messages but flag will be propagated to UI
        }
        
        if (sqliteMessages.isNotEmpty) {
          print('✅ Found ${sqliteMessages.length} new message(s) in SQLite (since timestamp)');
          // Convert and return SQLite messages (P2P messages are already here)
          // Include chain integrity status in converted messages
          final converted = _convertSQLiteMessages(sqliteMessages, workspaceId, channelId);
          // Add chain integrity metadata to first message for UI
          if (converted.isNotEmpty && chainIntegrityFailed) {
            converted.first['_chainIntegrityFailed'] = true;
            converted.first['_chainFailureReason'] = sqliteResult['chainFailureReason'];
            converted.first['_chainBrokenAt'] = sqliteResult['chainBrokenAt'];
            converted.first['_chainFailureDetails'] = sqliteResult['chainFailureDetails'];
          }
          return converted;
        }
        
        // No new messages in SQLite, check server for new messages
        // But only if we haven't checked recently (avoid excessive server calls)
        print('📦 No new messages in SQLite, checking server for new messages...');
      }
      
      try {
        print('🌐 Fetching messages from server for channel $channelId in workspace $workspaceId${sinceTimestamp != null ? " (incremental check)" : " (full load)"}');
        
        // For incremental checks, we still fetch all from server but filter later
        // (Server doesn't support sinceTimestamp yet, but we'll filter in SQLite caching)
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
          // CRITICAL FIX: For incremental checks (polling), filter server messages by timestamp
          // Only process messages newer than sinceTimestamp
          List<Map<String, dynamic>> messagesToProcess = serverMessages;
          if (sinceTimestamp != null) {
            messagesToProcess = serverMessages.where((msg) {
              final msgTimestamp = msg['timestamp'];
              int msgTs = 0;
              
              if (msgTimestamp is int) {
                msgTs = msgTimestamp;
              } else if (msgTimestamp is DateTime) {
                msgTs = msgTimestamp.millisecondsSinceEpoch;
              } else if (msgTimestamp is String) {
                final parsed = DateTime.tryParse(msgTimestamp);
                if (parsed != null) msgTs = parsed.millisecondsSinceEpoch;
              }
              
              return msgTs > sinceTimestamp;
            }).toList();
            
            print('🔍 Filtered server messages: ${serverMessages.length} total -> ${messagesToProcess.length} new (after $sinceTimestamp)');
            
            // If no new messages from server, skip caching and return SQLite messages
            if (messagesToProcess.isEmpty) {
              print('ℹ️ No new messages from server (all older than sinceTimestamp), using SQLite');
              final sqliteResult = await SQLiteService.instance.getChannelMessages(
                workspaceId: workspaceId,
                channelId: channelId,
                sinceTimestamp: sinceTimestamp,
              );
              final sqliteMessages = sqliteResult['messages'] as List<Map<String, dynamic>>? ?? [];
              final converted = _convertSQLiteMessages(sqliteMessages, workspaceId, channelId);
              // Add chain integrity metadata if failed
              if (converted.isNotEmpty && (sqliteResult['chainIntegrityFailed'] as bool? ?? false)) {
                converted.first['_chainIntegrityFailed'] = true;
                converted.first['_chainFailureReason'] = sqliteResult['chainFailureReason'];
                converted.first['_chainBrokenAt'] = sqliteResult['chainBrokenAt'];
                converted.first['_chainFailureDetails'] = sqliteResult['chainFailureDetails'];
              }
              return converted;
            }
          }
          
          // First, check how many messages are already in SQLite
          final existingResult = await SQLiteService.instance.getChannelMessages(
            workspaceId: workspaceId,
            channelId: channelId,
          );
          final existingMessages = existingResult['messages'] as List<Map<String, dynamic>>? ?? [];
          final existingMessageIds = existingMessages
              .map((m) => m['message_id']?.toString())
              .whereType<String>()
              .toSet();
          
          // CRITICAL FIX: Get list of already synced messages to prevent re-caching
          // This prevents duplicate messages when sync timer syncs messages and then
          // getChannelMessages fetches them again from server
          final syncedMessageIds = <String>{};
          for (final existingMsg in existingMessages) {
            final synced = existingMsg['synced_to_server'] as int? ?? 0;
            if (synced == 1) {
              final msgId = existingMsg['message_id']?.toString();
              if (msgId != null) {
                syncedMessageIds.add(msgId);
              }
            }
          }
          
          print('💾 Checking ${messagesToProcess.length} server messages against ${existingMessages.length} SQLite messages (${syncedMessageIds.length} already synced)');
          int cached = 0;
          int skipped = 0;
          
          for (final msg in messagesToProcess) {
            try {
              // Use message_id from server if available (CRITICAL for deduplication)
              final messageId = msg['message_id']?.toString() ?? 
                               msg['id']?.toString();
              
              if (messageId == null || messageId.isEmpty) {
                print('⚠️ Skipping message without message_id');
                skipped++;
                continue;
              }
              
          // CRITICAL FIX: Skip if message is already synced OR has state SYNCED/ONLINE_CONFIRMED
          // This prevents duplicate messages when sync timer syncs messages and then
          // getChannelMessages fetches them again from server
          if (syncedMessageIds.contains(messageId)) {
            print('ℹ️ Skipping already synced message: $messageId (prevent re-cache after sync)');
            skipped++;
            continue;
          }
          
          // CRITICAL: Also check message state - skip SYNCED and ONLINE_CONFIRMED messages
          final existingMsgState = existingMessages.firstWhere(
            (m) => m['message_id']?.toString() == messageId,
            orElse: () => <String, dynamic>{},
          );
          final msgState = existingMsgState['message_state']?.toString();
          if (msgState == 'SYNCED' || msgState == 'ONLINE_CONFIRMED') {
            print('ℹ️ Skipping message with state $msgState: $messageId (prevent re-cache)');
            skipped++;
            continue;
          }
              
              // Skip if message already exists in SQLite by messageId
              if (existingMessageIds.contains(messageId)) {
                skipped++;
                continue;
              }
              
              // CRITICAL FIX: Also check for duplicate by content + sender + timestamp
              // This catches duplicates even if messageIds don't match
              // NOTE: MongoDB (v2) messages don't have message_text - only payload_hash (ledger data only)
              final messageText = msg['message_text']?.toString() ?? msg['messageText']?.toString() ?? ''; // Empty for v2 MongoDB messages
              final senderAddress = msg['sender_address']?.toString() ?? msg['senderAddress']?.toString() ?? '';
              final fromMongoDB = msg['_fromMongoDB'] ?? false; // Flag indicating this is ledger data from MongoDB
              final msgTimestamp = msg['timestamp'];
              
              // Check for duplicate by content + sender + timestamp (within 5 seconds tolerance)
              bool isDuplicate = false;
              if (messageText.isNotEmpty && senderAddress.isNotEmpty) {
                for (final existingMsg in existingMessages) {
                  final existingText = existingMsg['message_text']?.toString() ?? '';
                  final existingSender = existingMsg['sender_address']?.toString() ?? '';
                  final existingTimestamp = existingMsg['timestamp'];
                  
                  // Check if content and sender match
                  if (existingText == messageText && 
                      existingSender.toLowerCase() == senderAddress.toLowerCase()) {
                    // Check timestamp (within 5 seconds tolerance for same message)
                    int existingTs = 0;
                    int msgTs = 0;
                    
                    if (existingTimestamp is int) {
                      existingTs = existingTimestamp;
                    } else if (existingTimestamp is DateTime) {
                      existingTs = existingTimestamp.millisecondsSinceEpoch;
                    }
                    
                    if (msgTimestamp is int) {
                      msgTs = msgTimestamp;
                    } else if (msgTimestamp is DateTime) {
                      msgTs = msgTimestamp.millisecondsSinceEpoch;
                    } else if (msgTimestamp is String) {
                      final parsed = DateTime.tryParse(msgTimestamp);
                      if (parsed != null) msgTs = parsed.millisecondsSinceEpoch;
                    }
                    
                    // If timestamps are within 5 seconds, it's likely the same message
                    if (existingTs > 0 && msgTs > 0 && (existingTs - msgTs).abs() < 5000) {
                      print('⚠️ Duplicate message detected by content: "$messageText" from $senderAddress');
                      print('   Existing ID: ${existingMsg['message_id']}, Server ID: $messageId');
                      print('   Updating existing message with server messageId to prevent duplicates');
                      
                      // Update existing message with server messageId for consistency
                      try {
                        final updated = await SQLiteService.instance.updateMessageId(
                          oldMessageId: existingMsg['message_id']?.toString() ?? '',
                          newMessageId: messageId,
                        );
                        if (updated) {
                          print('✅ Updated existing message with server messageId: $messageId');
                          existingMessageIds.add(messageId); // Track updated message
                        }
                      } catch (e) {
                        print('⚠️ Error updating messageId: $e');
                      }
                      
                      isDuplicate = true;
                      skipped++;
                      break;
                    }
                  }
                }
              }
              
              if (isDuplicate) {
                continue; // Skip adding duplicate message
              }
              
              // Only cache messages that don't already exist
              // CRITICAL: MongoDB (v2) messages do NOT contain message_text - only payload_hash
              // MongoDB is ledger data only - message_text is NOT available from server
              // If messageText is empty (v2 MongoDB message), skip caching to SQLite
              // The message should already exist in SQLite from local creation with message_text
              if (messageText.isEmpty && fromMongoDB) {
                // MongoDB ledger message without message_text - message should already exist in SQLite
                print('ℹ️ Skipping MongoDB ledger message without message_text: $messageId (should already exist in SQLite)');
                skipped++;
                continue;
              }
              
              final result = await SQLiteService.instance.addMessage(
                workspaceId: workspaceId,
                channelId: channelId,
                senderAddress: senderAddress,
                messageText: messageText, // For v1 legacy messages only - v2 messages are skipped above
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
        
        // CRITICAL: Save last server hash for chain continuity
        // This ensures when server goes offline, SQLite messages can link to server's chain
        if (serverMessages.isNotEmpty) {
          // Get last hash from server response metadata (if available)
          final lastHash = serverMessages.first['_lastServerHash'] as String?;
          final lastMessageId = serverMessages.first['_lastServerMessageId'] as String?;
          
          if (lastHash != null) {
            // Get last message timestamp from SQLite (after caching)
            final lastSqliteResult = await SQLiteService.instance.getChannelMessages(
              workspaceId: workspaceId,
              channelId: channelId,
              sinceTimestamp: null,
            );
            final lastSqliteMessages = lastSqliteResult['messages'] as List<Map<String, dynamic>>? ?? [];
            
            int? lastTimestamp;
            if (lastSqliteMessages.isNotEmpty) {
              final lastMsg = lastSqliteMessages.last;
              lastTimestamp = lastMsg['timestamp'] as int?;
            }
            
            // Save chain state for this channel
            await SQLiteService.instance.saveChainState(
              workspaceId: workspaceId,
              channelId: channelId,
              lastServerHash: lastHash,
              lastServerMessageId: lastMessageId,
              lastServerTimestamp: lastTimestamp ?? DateTime.now().millisecondsSinceEpoch,
            );
            print('🔗 Saved chain state: workspace=$workspaceId, channel=$channelId, hash=${SQLiteService.safeSubstring(lastHash, 10)}...');
          } else {
            // Fallback: Get last hash from SQLite after caching (if server didn't provide it)
            final lastSqliteResult = await SQLiteService.instance.getChannelMessages(
              workspaceId: workspaceId,
              channelId: channelId,
              sinceTimestamp: null,
            );
            final lastSqliteMessages = lastSqliteResult['messages'] as List<Map<String, dynamic>>? ?? [];
            
            if (lastSqliteMessages.isNotEmpty) {
              final lastMsg = lastSqliteMessages.last;
              final lastHash = lastMsg['current_hash'] as String?;
              final lastMsgId = lastMsg['message_id'] as String?;
              final lastTimestamp = lastMsg['timestamp'] as int?;
              
              if (lastHash != null) {
                await SQLiteService.instance.saveChainState(
                  workspaceId: workspaceId,
                  channelId: channelId,
                  lastServerHash: lastHash,
                  lastServerMessageId: lastMsgId,
                  lastServerTimestamp: lastTimestamp ?? DateTime.now().millisecondsSinceEpoch,
                );
                print('🔗 Saved chain state (fallback): hash=${SQLiteService.safeSubstring(lastHash, 10)}...');
              }
            }
          }
        }
        
        // IMPORTANT: When server is online, cache messages to SQLite but return SQLite messages
        // This prevents duplication from multiple sources (server + P2P + sync timer)
        // Server messages are cached to SQLite above, so SQLite is the single source of truth
        print('📦 Server messages cached to SQLite, loading from SQLite to prevent duplication...');
        
        // Load from SQLite (which now includes server messages + P2P messages)
        // For incremental checks, only load new messages
        final sqliteResult = await SQLiteService.instance.getChannelMessages(
          workspaceId: workspaceId,
          channelId: channelId,
          sinceTimestamp: sinceTimestamp, // Only get new messages if sinceTimestamp provided
        );
        
        final messagesList = sqliteResult['messages'] as List<Map<String, dynamic>>? ?? [];
        final chainIntegrityFailed = sqliteResult['chainIntegrityFailed'] as bool? ?? false;
        
        if (sinceTimestamp != null) {
          print('✅ SQLite returned ${messagesList.length} new message(s) (since timestamp)');
        } else {
          print('✅ SQLite returned ${messagesList.length} messages (includes server + P2P)');
        }
        
        // Check chain integrity failure
        if (chainIntegrityFailed) {
          final failureReason = sqliteResult['chainFailureReason'] as String? ?? 'unknown';
          final brokenAt = sqliteResult['chainBrokenAt'] as String? ?? 'unknown';
          print('⚠️ Chain integrity failed in SQLite: $failureReason at $brokenAt');
        }
        
        // Convert SQLite format to UI format
        final converted = _convertSQLiteMessages(messagesList, workspaceId, channelId);
        
        // Add chain integrity metadata if available
        if (converted.isNotEmpty && chainIntegrityFailed) {
          converted.first['_chainIntegrityFailed'] = true;
          converted.first['_chainFailureReason'] = sqliteResult['chainFailureReason'];
          converted.first['_chainBrokenAt'] = sqliteResult['chainBrokenAt'];
          converted.first['_chainFailureDetails'] = sqliteResult['chainFailureDetails'];
        }
        return converted;
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
    if (sinceTimestamp != null) {
      print('📦 Loading new messages from SQLite for channel $channelId (since timestamp)');
    } else {
      print('📦 Loading messages from SQLite for channel $channelId');
    }
    final sqliteResult = await SQLiteService.instance.getChannelMessages(
      workspaceId: workspaceId,
      channelId: channelId,
      sinceTimestamp: sinceTimestamp, // Only get new messages if sinceTimestamp provided
    );
    
    final messagesList = sqliteResult['messages'] as List<Map<String, dynamic>>? ?? [];
    final chainIntegrityFailed = sqliteResult['chainIntegrityFailed'] as bool? ?? false;
    
    if (sinceTimestamp != null) {
      print('✅ SQLite returned ${messagesList.length} new message(s) (since timestamp)');
    } else {
      print('✅ SQLite returned ${messagesList.length} messages');
    }
    
    // Check chain integrity failure
    if (chainIntegrityFailed) {
      final failureReason = sqliteResult['chainFailureReason'] as String? ?? 'unknown';
      final brokenAt = sqliteResult['chainBrokenAt'] as String? ?? 'unknown';
      print('⚠️ Chain integrity failed in SQLite: $failureReason at $brokenAt');
      print('   Details: ${sqliteResult['chainFailureDetails']}');
    }
    
    // Convert messages and add chain integrity metadata
    final converted = _convertSQLiteMessages(messagesList, workspaceId, channelId);
    
    // Debug: Log first SQLite message if available
    if (converted.isNotEmpty) {
      print('📋 First SQLite message keys: ${converted.first.keys.toList()}');
      print('📋 First SQLite message_text: ${converted.first['message_text']}');
    }
    
    // Add chain integrity metadata to first message for UI
    if (converted.isNotEmpty && chainIntegrityFailed) {
      converted.first['_chainIntegrityFailed'] = true;
      converted.first['_chainFailureReason'] = sqliteResult['chainFailureReason'];
      converted.first['_chainBrokenAt'] = sqliteResult['chainBrokenAt'];
      converted.first['_chainFailureDetails'] = sqliteResult['chainFailureDetails'];
    }
    return converted;
  }

  /// Convert SQLite messages to UI format (helper method)
  List<Map<String, dynamic>> _convertSQLiteMessages(
    List<Map<String, dynamic>> sqliteMessages,
    String workspaceId,
    String channelId,
  ) {
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
  /// CRITICAL: Uses lock to prevent concurrent syncs (race condition prevention)
  /// PHASE 3: Exact sync flow implementation
  Future<void> syncToServer() async {
    if (!_isServerOnline) {
      return;
    }
    
    // CRITICAL FIX: Prevent concurrent syncs (multiple triggers can call this simultaneously)
    if (_isSyncing) {
      print('⚠️ Sync already in progress, skipping duplicate sync request');
      return;
    }
    
    _isSyncing = true;
    try {
      print('🔄 Syncing to server...');

      // PHASE 3 STEP 1: Detect server online (already done - _isServerOnline check above)
      // PHASE 3 STEP 2: Fetch messages WHERE state = PENDING_SYNC
      // CRITICAL: First, mark OFFLINE_LOCAL messages as PENDING_SYNC (transition state)
      // Then fetch only PENDING_SYNC messages for sync
      final offlineMessages = await SQLiteService.instance.getUnsyncedMessages();
      
      // Mark OFFLINE_LOCAL messages as PENDING_SYNC (prepare for sync)
      int markedCount = 0;
      for (final msg in offlineMessages) {
        final messageId = msg['message_id']?.toString();
        final state = msg['message_state']?.toString();
        
        if (messageId != null && state == 'OFFLINE_LOCAL') {
          await SQLiteService.instance.updateMessageState(
            messageId: messageId,
            state: 'PENDING_SYNC',
          );
          markedCount++;
        }
      }
      
      if (markedCount > 0) {
        print('📋 Marked $markedCount OFFLINE_LOCAL message(s) as PENDING_SYNC');
      }
      
      // PHASE 3 STEP 2: Fetch messages WHERE state = PENDING_SYNC (exact requirement)
      final pendingSyncMessages = await SQLiteService.instance.getMessagesByState('PENDING_SYNC');
      
      // Get unsynced channels (created offline)
      final unsyncedChannels = await SQLiteService.instance.getUnsyncedChannels();

      if (pendingSyncMessages.isEmpty && unsyncedChannels.isEmpty) {
        print('ℹ️ No unsynced data to sync');
        return;
      }

      print('📤 Found ${pendingSyncMessages.length} PENDING_SYNC message(s) and ${unsyncedChannels.length} unsynced channel(s) to sync');

      // CRITICAL FIX: Before syncing messages, store last MongoDB hash for each channel
      // This ensures chain continuity - server will calculate hash from MongoDB's last message
      // and SQLite messages will link properly to server's chain
      final channelsToSync = <String, Map<String, String>>{}; // workspaceId:channelId -> {workspaceId, channelId}
      
      for (final msg in pendingSyncMessages) {
        final workspaceId = msg['workspace_id']?.toString();
        final channelId = msg['channel_id']?.toString();
        
        if (workspaceId != null && channelId != null) {
          final key = '$workspaceId:$channelId';
          if (!channelsToSync.containsKey(key)) {
            channelsToSync[key] = {
              'workspaceId': workspaceId,
              'channelId': channelId,
            };
          }
        }
      }
      
      // Store last MongoDB hash for each channel BEFORE syncing
      // This ensures server calculates hash from MongoDB's last message (not SQLite's)
      for (final channelInfo in channelsToSync.values) {
        final workspaceId = channelInfo['workspaceId']!;
        final channelId = channelInfo['channelId']!;
        
        try {
          // Fetch last message from server to get its hash
          final serverMessages = await DistributedService.getChannelMessages(
            workspaceId: workspaceId,
            channelId: channelId,
          );
          
          if (serverMessages.isNotEmpty) {
            // Get last hash from server response metadata
            final lastHash = serverMessages.first['_lastServerHash'] as String?;
            final lastMessageId = serverMessages.first['_lastServerMessageId'] as String?;
            
            if (lastHash != null) {
              // Store chain state BEFORE syncing
              // This ensures server calculates hash from MongoDB's last message
              await SQLiteService.instance.saveChainState(
                workspaceId: workspaceId,
                channelId: channelId,
                lastServerHash: lastHash,
                lastServerMessageId: lastMessageId,
                lastServerTimestamp: DateTime.now().millisecondsSinceEpoch,
              );
              print('🔗 Stored MongoDB last hash BEFORE sync: workspace=$workspaceId, channel=$channelId, hash=${SQLiteService.safeSubstring(lastHash, 10)}...');
            } else {
              // Fallback: Get last hash from SQLite (if server didn't provide it)
              final lastSqliteResult2 = await SQLiteService.instance.getChannelMessages(
                workspaceId: workspaceId,
                channelId: channelId,
                sinceTimestamp: null,
              );
              final lastSqliteMessages2 = lastSqliteResult2['messages'] as List<Map<String, dynamic>>? ?? [];
              
              if (lastSqliteMessages2.isNotEmpty) {
                final lastMsg = lastSqliteMessages2.last;
                final lastHash = lastMsg['current_hash'] as String?;
                final lastMsgId = lastMsg['message_id'] as String?;
                final lastTimestamp = lastMsg['timestamp'] as int?;
                
                if (lastHash != null) {
                  await SQLiteService.instance.saveChainState(
                    workspaceId: workspaceId,
                    channelId: channelId,
                    lastServerHash: lastHash,
                    lastServerMessageId: lastMsgId,
                    lastServerTimestamp: lastTimestamp ?? DateTime.now().millisecondsSinceEpoch,
                  );
                  print('🔗 Stored SQLite last hash BEFORE sync (fallback): hash=${SQLiteService.safeSubstring(lastHash, 10)}...');
                }
              }
            }
          }
        } catch (e) {
          print('⚠️ Error storing chain state before sync: $e');
          // Continue even if chain state storage fails
        }
      }

      // Sync unsynced channels first
      int syncedChannelCount = 0;
      for (final channel in unsyncedChannels) {
        try {
          final workspaceId = channel['workspace_id']?.toString();
          final channelId = channel['channel_id']?.toString();
          final channelName = channel['channel_name']?.toString() ?? channelId;
          final creatorAddress = channel['creator_address']?.toString();
          
          if (workspaceId == null || channelId == null || creatorAddress == null) {
            print('⚠️ Skipping channel with missing data');
            continue;
          }

          print('🔄 Syncing channel "$channelName" to server...');
          
          // Create channel on server
          final channelCreated = await DistributedService.createChannel(
            workspaceId: workspaceId,
            channelId: channelId,
            creatorAddress: creatorAddress,
            channelName: channelName,
            isPrivate: (channel['is_private'] as int? ?? 0) == 1,
          );

          if (channelCreated) {
            // Mark channel as synced
            await SQLiteService.instance.markChannelSynced(
              workspaceId: workspaceId,
              channelId: channelId,
            );
            syncedChannelCount++;
            print('✅ Channel "$channelName" synced to server');
          } else {
            print('⚠️ Failed to sync channel "$channelName" to server');
          }
        } catch (e) {
          print('⚠️ Sync channel error: $e');
        }
      }

      // PHASE 3 STEP 3: Send headers to server (message_id, channel_id, prev_hash, current_hash, timestamp)
      // PHASE 3 STEP 4: Server validates + confirms (handled by server idempotency check)
      // PHASE 3 STEP 5: Client updates state to SYNCED
      // PHASE 3 STEP 6: NO UI re-render (SYNCED messages skipped in getChannelMessages)
      // PHASE 3 STEP 7: NO block re-creation (server uses provided hashes)
      
      int syncedMessageCount = 0;
      final Set<String> syncedChannels = {}; // Track channels that had messages synced
      
      // PHASE 3: Process only PENDING_SYNC messages (already marked above)
      for (final msg in pendingSyncMessages) {
        String? localMessageId; // Declare outside try block for error logging
        try {
          localMessageId = msg['message_id'] as String?;
          final workspaceId = msg['workspace_id'] as String?;
          final channelId = msg['channel_id'] as String?;
          final senderAddress = msg['sender_address'] as String?;
          final messageText = msg['message_text'] as String?;
          final previousHash = msg['previous_hash'] as String?;
          final currentHash = msg['current_hash'] as String?;
          final payloadHash = msg['payload_hash'] as String?;
          final hashVersion = msg['hash_version'] as int?;
          
          // CRITICAL: Validate all required fields before sync
          if (localMessageId == null || localMessageId.isEmpty) {
            print('⚠️ [OFFLINE SYNC] Skipping message without messageId: ${msg.toString()}');
            continue;
          }
          
          if (workspaceId == null || workspaceId.isEmpty) {
            print('⚠️ [OFFLINE SYNC] Skipping message $localMessageId without workspaceId');
            continue;
          }
          
          if (senderAddress == null || senderAddress.isEmpty) {
            print('⚠️ [OFFLINE SYNC] Skipping message $localMessageId without senderAddress');
            continue;
          }
          
          if (messageText == null || messageText.isEmpty) {
            print('⚠️ [OFFLINE SYNC] Skipping message $localMessageId without messageText');
            continue;
          }
          
          // Validate blockchain fields for hash_version 2
          final effectiveHashVersion = hashVersion ?? 2; // Default to 2 for new messages
          if (effectiveHashVersion == 2) {
            if (payloadHash == null || payloadHash.isEmpty) {
              print('⚠️ [OFFLINE SYNC] Skipping v2 message $localMessageId without payload_hash - calculating...');
              // Calculate payload_hash if missing (shouldn't happen, but handle gracefully)
              // This would be a data integrity issue - log it
              print('❌ [DATA INTEGRITY] Message $localMessageId is v2 but missing payload_hash - this should not happen');
            }
          }
          
          if (previousHash == null || previousHash.isEmpty) {
            print('⚠️ [OFFLINE SYNC] Warning: Message $localMessageId has empty previous_hash, using "0"');
          }
          
          if (currentHash == null || currentHash.isEmpty) {
            print('⚠️ [OFFLINE SYNC] Skipping message $localMessageId without current_hash (required for chain integrity)');
            continue;
          }

          // Double-check if message is already synced (race condition protection)
          final isSynced = await SQLiteService.instance.isMessageSynced(localMessageId);
          if (isSynced) {
            print('ℹ️ [OFFLINE SYNC] Message $localMessageId already synced, skipping');
            continue;
          }
          
          // Log offline sync attempt with all fields
          print('📤 [OFFLINE SYNC] Attempting to sync message $localMessageId');
          print('   Workspace: $workspaceId, Channel: $channelId');
          print('   Hash version: ${effectiveHashVersion}, Payload hash: ${SQLiteService.safeSubstring(payloadHash, 10)}...');
          print('   Previous hash: ${SQLiteService.safeSubstring(previousHash, 10)}..., Current hash: ${SQLiteService.safeSubstring(currentHash, 10)}...');

          // PHASE 3 STEP 3: Send headers to server with offline_sync flag
          // Headers: message_id, channel_id, prev_hash, current_hash, payload_hash, hash_version, timestamp
          // Server validates and confirms (idempotent - no re-insert if duplicate)
          // CRITICAL: Mark as offline sync so backend can handle previous_hash mismatch gracefully
          // Note: At this point, workspaceId, senderAddress, messageText, currentHash are guaranteed non-null
          final serverMessageId = await DistributedService.addMessage(
            workspaceId: workspaceId,
            channelId: channelId,
            senderAddress: senderAddress,
            receiverAddress: msg['receiver_address'],
            messageText: messageText,
            fileId: msg['file_id'],
            messageId: localMessageId, // CRITICAL: Pass existing message_id for idempotency
            previousHash: previousHash, // Header: prev_hash (may not match server if offline for long)
            currentHash: currentHash, // Header: current_hash
            payloadHash: payloadHash, // Header: payload_hash (stable hash)
            hashVersion: effectiveHashVersion, // Header: hash_version (preserve version)
            isOfflineSync: true, // NEW: Flag to indicate offline sync (allow hash re-anchoring)
          );

          // PHASE 3 STEP 4: Server validates + confirms (returns message_id if successful)
          if (serverMessageId != null && serverMessageId.isNotEmpty) {
            print('✅ [OFFLINE SYNC] Message $localMessageId successfully synced to server: $serverMessageId');
            // PHASE 3 STEP 5: Client updates state to SYNCED
            // Update SQLite message with server messageId if different
            if (serverMessageId != localMessageId) {
              await SQLiteService.instance.updateMessageId(
                oldMessageId: localMessageId,
                newMessageId: serverMessageId,
              );
              print('✅ Synced and updated messageId: $localMessageId -> $serverMessageId');
            }
            
            // PHASE 3 STEP 5: Update state to SYNCED
            // PHASE 3 STEP 6: NO UI re-render (SYNCED messages skipped in getChannelMessages)
            await SQLiteService.instance.updateMessageState(
              messageId: serverMessageId != localMessageId ? serverMessageId : localMessageId,
              state: 'SYNCED',
            );
            print('✅ [OFFLINE SYNC] PHASE 3: Message synced (state: SYNCED) - NO UI re-render, NO block re-creation');
            
            syncedMessageCount++;
            
            // Track channel for chain state clearing
            syncedChannels.add('$workspaceId:$channelId');
          } else {
            // Server returned null or empty - sync failed
            print('❌ [OFFLINE SYNC] Message $localMessageId sync failed: server returned null or empty messageId');
            print('   This usually indicates server rejected the message - check server logs for details');
          }
        } catch (e) {
          final msgId = localMessageId ?? msg['message_id']?.toString() ?? 'unknown';
          print('❌ [OFFLINE SYNC] Message $msgId sync error: $e');
          print('   Stack trace: ${StackTrace.current}');
          // On error, keep message in PENDING_SYNC state for retry
        }
      }
      
      // CRITICAL: After successful sync, update chain state with new last hash from server
      // This ensures chain continuity for next offline session
      for (final channelKey in syncedChannels) {
        final parts = channelKey.split(':');
        if (parts.length == 2) {
          final workspaceId = parts[0];
          final channelId = parts[1];
          
          try {
            // Fetch messages from server to get updated last hash
            final serverMessages = await DistributedService.getChannelMessages(
              workspaceId: workspaceId,
              channelId: channelId,
            );
            
            if (serverMessages.isNotEmpty) {
              // Get last hash from server response metadata
              final lastHash = serverMessages.first['_lastServerHash'] as String?;
              final lastMessageId = serverMessages.first['_lastServerMessageId'] as String?;
              
              if (lastHash != null) {
                // Update chain state with new last hash AFTER sync
                await SQLiteService.instance.saveChainState(
                  workspaceId: workspaceId,
                  channelId: channelId,
                  lastServerHash: lastHash,
                  lastServerMessageId: lastMessageId,
                  lastServerTimestamp: DateTime.now().millisecondsSinceEpoch,
                );
                print('🔗 Updated chain state AFTER sync: workspace=$workspaceId, channel=$channelId, hash=${SQLiteService.safeSubstring(lastHash, 10)}...');
              } else {
                // If server didn't provide hash, clear chain state (fresh start)
                await SQLiteService.instance.clearChainState(
                  workspaceId: workspaceId,
                  channelId: channelId,
                );
                print('🔗 Cleared chain state (no hash from server): ${channelId}');
              }
            } else {
              // No messages on server, clear chain state
              await SQLiteService.instance.clearChainState(
                workspaceId: workspaceId,
                channelId: channelId,
              );
              print('🔗 Cleared chain state (no server messages): ${channelId}');
            }
          } catch (e) {
            print('⚠️ Error updating chain state after sync: $e');
            // Clear chain state on error (safe fallback)
            try {
              await SQLiteService.instance.clearChainState(
                workspaceId: workspaceId,
                channelId: channelId,
              );
            } catch (clearError) {
              print('⚠️ Error clearing chain state: $clearError');
            }
          }
        }
      }

      print('✅ PHASE 3 Sync completed: $syncedChannelCount/${unsyncedChannels.length} channels, $syncedMessageCount/${pendingSyncMessages.length} messages synced');
      print('   ✅ NO UI re-render (SYNCED messages skipped)');
      print('   ✅ NO block re-creation (server used provided hashes)');
    } catch (e) {
      print('❌ Sync to server error: $e');
      // CRITICAL: On sync failure, reset PENDING_SYNC messages back to OFFLINE_LOCAL for retry
      // This prevents messages from being stuck in PENDING_SYNC state
      // PHASE 3: Failed syncs reset state so they can be retried on next sync
      try {
        final failedMessages = await SQLiteService.instance.getMessagesByState('PENDING_SYNC');
        for (final msg in failedMessages) {
          final messageId = msg['message_id']?.toString();
          if (messageId != null) {
            await SQLiteService.instance.updateMessageState(
              messageId: messageId,
              state: 'OFFLINE_LOCAL', // Reset for retry
            );
            print('🔄 Reset failed sync message to OFFLINE_LOCAL: $messageId (will retry on next sync)');
          }
        }
      } catch (resetError) {
        print('⚠️ Error resetting failed sync messages: $resetError');
      }
    } finally {
      // CRITICAL: Always release sync lock
      _isSyncing = false;
    }
  }

  /// Sync message to server (internal) - only if not already synced
  Future<void> _syncMessageToServerIfNeeded(Map<String, dynamic> message) async {
    if (!_isServerOnline) {
      return;
    }

    try {
      final messageId = message['message_id']?.toString();
      if (messageId == null || messageId.isEmpty) {
        print('⚠️ Cannot sync message without messageId');
        return;
      }

      // CRITICAL FIX: Check if message is already synced before syncing
      final isSynced = await SQLiteService.instance.isMessageSynced(messageId);
      if (isSynced) {
        print('ℹ️ Message $messageId already synced, skipping');
        return;
      }

      print('🔄 Syncing message $messageId to server...');
      final serverMessageId = await DistributedService.addMessage(
        workspaceId: message['workspace_id'] ?? '',
        channelId: message['channel_id'],
        senderAddress: message['sender_address'] ?? '',
        receiverAddress: message['receiver_address'],
        messageText: message['content'] ?? message['message_text'] ?? '',
        fileId: message['file_id'],
      );

      if (serverMessageId != null) {
        // Update SQLite message with server messageId if different
        if (serverMessageId != messageId) {
          await SQLiteService.instance.updateMessageId(
            oldMessageId: messageId,
            newMessageId: serverMessageId,
          );
          print('✅ Updated messageId: $messageId -> $serverMessageId');
        } else {
          await SQLiteService.instance.markMessageSynced(messageId);
        }
        print('✅ Message synced to server: $serverMessageId');
      }
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
            
            // CRITICAL FIX: Don't trigger sync here - let periodic timer handle it
            // This prevents multiple sync triggers when server comes online
            // Sync will happen automatically on next timer tick (within 30 seconds)
            print('🔄 Server came online - sync will happen automatically on next timer tick');
          }
          
          // CRITICAL: Sync deleted channels from server to SQLite
          // When server returns channels, any channel that exists in SQLite but NOT in server response
          // means it was deleted on server - mark it as deleted in SQLite
          final sqliteChannelIds = await SQLiteService.instance.getAllChannelIds(workspaceId);
          
          // CRITICAL: Server returns display names (channel_name), but we need to compare with channel_id
          // Backend stores channel_id with spaces replaced by hyphens (e.g., "check 2" -> "check-2")
          // So we need to normalize display names the same way for comparison
          final serverChannelIds = channels
              .map((name) => name.toLowerCase().trim().replaceAll(RegExp(r'\s+'), '-'))
              .toSet();
          
          // Find channels that exist in SQLite but NOT in server response
          // These are channels that were deleted on server
          final channelsToDelete = sqliteChannelIds
              .where((channelId) => !serverChannelIds.contains(channelId))
              .where((channelId) => 
                  // Don't delete default channels
                  channelId != 'general' && channelId != 'random')
              .toList();
          
          // Mark deleted channels in SQLite
          for (final channelId in channelsToDelete) {
            // Check if channel is already deleted
            final db = await SQLiteService.instance.database;
            final existingChannel = await db.query(
              'channels',
              columns: ['deleted'],
              where: 'workspace_id = ? AND channel_id = ?',
              whereArgs: [workspaceId, channelId],
              limit: 1,
            );
            
            // Only mark as deleted if not already deleted
            if (existingChannel.isNotEmpty && (existingChannel.first['deleted'] as int? ?? 0) == 0) {
              await SQLiteService.instance.deleteChannel(
                workspaceId: workspaceId,
                channelId: channelId,
              );
              print('🗑️ Synced deleted channel from server to SQLite: $channelId');
            }
          }
          
          // Cache ALL active channels from server to SQLite
          // This ensures they are available offline with all metadata
          // Server returns channel names (display names), but we need to normalize them for channel_id
          // CRITICAL: When caching from server, deleted parameter is NOT provided
          // SQLiteService.saveChannel() will preserve existing deleted status if channel already exists
          for (final channelName in channels) {
            // CRITICAL: Normalize channel ID same way as backend (spaces -> hyphens)
            // Backend uses: channelId.toLowerCase().trim().replace(/\s+/g, '-')
            final normalizedChannelId = channelName.toLowerCase().trim().replaceAll(RegExp(r'\s+'), '-');
            
            // Save to SQLite with proper display name
            // Note: Full channel data (members, is_private, etc.) will be saved when channel is created
            // IMPORTANT: deleted parameter is NOT passed - this allows SQLiteService to preserve
            // existing deleted status if channel was previously deleted
            await SQLiteService.instance.saveChannel(
              workspaceId: workspaceId,
              channelId: normalizedChannelId, // Use normalized ID (spaces -> hyphens)
              channelName: channelName, // Keep original case for display
              creatorAddress: null, // Will be updated if available
              syncedToServer: true, // This came from server
              // deleted parameter NOT provided - SQLiteService will preserve existing deleted status
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
    bool? syncedToServer,
  }) async {
    return await SQLiteService.instance.saveChannel(
      workspaceId: workspaceId,
      channelId: channelId,
      channelName: channelName,
      creatorAddress: creatorAddress,
      syncedToServer: syncedToServer, // Pass synced status
    );
  }

  /// Delete channel (from server and SQLite)
  Future<bool> deleteChannel({
    required String workspaceId,
    required String channelId,
  }) async {
    try {
      print('🗑️ [HybridStorageService] Deleting channel: $channelId in workspace $workspaceId');
      
      // 1. Try to delete from server if online
      if (_isServerOnline) {
        try {
          final success = await DistributedService.deleteChannel(
            workspaceId: workspaceId,
            channelId: channelId,
          );
          if (success) {
            print('✅ Channel deleted from server: $channelId');
          }
        } catch (e) {
          print('⚠️ Server delete failed (may be offline or channel already deleted): $e');
          // Continue to SQLite deletion even if server fails
        }
      }
      
      // 2. Always delete from SQLite (works offline)
      final sqliteSuccess = await SQLiteService.instance.deleteChannel(
        workspaceId: workspaceId,
        channelId: channelId,
      );
      
      if (sqliteSuccess) {
        print('✅ Channel deleted from SQLite: $channelId');
        return true;
      } else {
        print('⚠️ Channel not found in SQLite (may already be deleted): $channelId');
        // Still return true if server deletion succeeded
        return _isServerOnline;
      }
    } catch (e) {
      print('❌ Error deleting channel: $e');
      return false;
    }
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

