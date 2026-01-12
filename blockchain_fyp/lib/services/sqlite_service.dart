import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

/// SQLite Service for Local Database Storage
/// Mirrors MongoDB functionality for offline support
class SQLiteService {
  static SQLiteService? _instance;
  static Database? _database;

  // Singleton pattern
  static SQLiteService get instance {
    _instance ??= SQLiteService._();
    return _instance!;
  }

  SQLiteService._();

  /// Get database instance
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Initialize database
  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'ethershare.db');
    
    print('📦 Initializing SQLite database at: $path');

    return await openDatabase(
      path,
      version: 3, // Updated version for complete MongoDB-aligned schema
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Create tables
  Future<void> _onCreate(Database db, int version) async {
    print('🔨 Creating SQLite tables...');

    // Users table
    await db.execute('''
      CREATE TABLE users (
        address TEXT PRIMARY KEY,
        username TEXT,
        email TEXT,
        created_at INTEGER,
        updated_at INTEGER
      )
    ''');

    // Workspaces table
    await db.execute('''
      CREATE TABLE workspaces (
        workspace_id TEXT PRIMARY KEY,
        name TEXT,
        inviter_address TEXT,
        created_at INTEGER,
        timestamp INTEGER,
        previous_hash TEXT,
        current_hash TEXT,
        synced_to_server INTEGER DEFAULT 0
      )
    ''');

    // Messages table
    await db.execute('''
      CREATE TABLE messages (
        message_id TEXT PRIMARY KEY,
        workspace_id TEXT,
        channel_id TEXT,
        sender_address TEXT,
        receiver_address TEXT,
        message_text TEXT,
        file_id TEXT,
        timestamp INTEGER,
        previous_hash TEXT,
        current_hash TEXT,
        synced_to_server INTEGER DEFAULT 0
      )
    ''');

    // Members table
    await db.execute('''
      CREATE TABLE members (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        workspace_id TEXT,
        member_address TEXT,
        display_name TEXT,
        joined_at INTEGER,
        synced_to_server INTEGER DEFAULT 0
      )
    ''');

    // Files table
    await db.execute('''
      CREATE TABLE files (
        file_id TEXT PRIMARY KEY,
        filename TEXT,
        workspace_id TEXT,
        uploader_address TEXT,
        file_size INTEGER,
        upload_timestamp INTEGER,
        local_path TEXT,
        synced_to_server INTEGER DEFAULT 0
      )
    ''');

    // Peers table (for P2P connections)
    await db.execute('''
      CREATE TABLE peers (
        user_address TEXT PRIMARY KEY,
        ip_address TEXT,
        port INTEGER,
        last_seen INTEGER,
        is_online INTEGER DEFAULT 0
      )
    ''');

    // Channels table (MongoDB-aligned schema for complete offline support)
    await db.execute('''
      CREATE TABLE channels (
        channel_id TEXT,
        workspace_id TEXT,
        channel_name TEXT,
        creator_address TEXT,
        members TEXT,              -- JSON array of member addresses
        is_private INTEGER DEFAULT 0,  -- 0 = public, 1 = private
        is_default INTEGER DEFAULT 0,  -- 0 = user-created, 1 = default (general/random)
        created_at INTEGER,
        timestamp INTEGER,
        previous_hash TEXT,
        current_hash TEXT,
        deleted INTEGER DEFAULT 0,     -- 0 = active, 1 = deleted (soft delete)
        synced_to_server INTEGER DEFAULT 0,
        PRIMARY KEY (channel_id, workspace_id)
      )
    ''');

    // Create indexes for better performance
    await db.execute('CREATE INDEX idx_messages_workspace ON messages(workspace_id)');
    await db.execute('CREATE INDEX idx_messages_channel ON messages(channel_id)');
    await db.execute('CREATE INDEX idx_messages_sender ON messages(sender_address)');
    await db.execute('CREATE INDEX idx_messages_receiver ON messages(receiver_address)');
    await db.execute('CREATE INDEX idx_messages_timestamp ON messages(timestamp)');
    await db.execute('CREATE INDEX idx_members_workspace ON members(workspace_id)');
    await db.execute('CREATE INDEX idx_members_address ON members(member_address)');
    await db.execute('CREATE INDEX idx_channels_workspace ON channels(workspace_id)');
    await db.execute('CREATE INDEX idx_channels_deleted ON channels(deleted)');
    await db.execute('CREATE INDEX idx_channels_creator ON channels(creator_address)');
    await db.execute('CREATE INDEX idx_peers_address ON peers(user_address)');
    await db.execute('CREATE INDEX idx_workspaces_inviter ON workspaces(inviter_address)');

    print('✅ SQLite tables created successfully');
  }

  /// Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print('🔄 Upgrading database from version $oldVersion to $newVersion');
    
    // Migration from version 1 to 2: Add channels table if it doesn't exist
    if (oldVersion < 2) {
      print('📦 Adding channels table for version 2...');
      try {
        // Check if channels table exists
        final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='channels'"
        );
        
        if (tables.isEmpty) {
          // Create channels table (old schema)
          await db.execute('''
            CREATE TABLE channels (
              channel_id TEXT,
              workspace_id TEXT,
              channel_name TEXT,
              creator_address TEXT,
              created_at INTEGER,
              is_default INTEGER DEFAULT 0,
              PRIMARY KEY (channel_id, workspace_id)
            )
          ''');
          
          // Create index
          await db.execute('CREATE INDEX IF NOT EXISTS idx_channels_workspace ON channels(workspace_id)');
          
          print('✅ Channels table created successfully');
        } else {
          print('ℹ️ Channels table already exists');
        }
      } catch (e) {
        print('❌ Error creating channels table: $e');
        // Continue anyway - table might already exist
      }
    }
    
    // Migration from version 2 to 3: Add MongoDB-aligned fields to channels table
    if (oldVersion < 3) {
      print('📦 Upgrading channels table to version 3 (MongoDB-aligned schema)...');
      try {
        // Check if new columns already exist
        final columns = await db.rawQuery("PRAGMA table_info(channels)");
        final columnNames = columns.map((c) => c['name'] as String).toSet();
        
        // Add missing columns
        if (!columnNames.contains('members')) {
          await db.execute('ALTER TABLE channels ADD COLUMN members TEXT');
          print('✅ Added members column');
        }
        
        if (!columnNames.contains('is_private')) {
          await db.execute('ALTER TABLE channels ADD COLUMN is_private INTEGER DEFAULT 0');
          print('✅ Added is_private column');
        }
        
        if (!columnNames.contains('timestamp')) {
          await db.execute('ALTER TABLE channels ADD COLUMN timestamp INTEGER');
          // Set timestamp = created_at for existing records
          await db.execute('UPDATE channels SET timestamp = created_at WHERE timestamp IS NULL');
          print('✅ Added timestamp column');
        }
        
        if (!columnNames.contains('previous_hash')) {
          await db.execute('ALTER TABLE channels ADD COLUMN previous_hash TEXT');
          print('✅ Added previous_hash column');
        }
        
        if (!columnNames.contains('current_hash')) {
          await db.execute('ALTER TABLE channels ADD COLUMN current_hash TEXT');
          print('✅ Added current_hash column');
        }
        
        if (!columnNames.contains('deleted')) {
          await db.execute('ALTER TABLE channels ADD COLUMN deleted INTEGER DEFAULT 0');
          print('✅ Added deleted column');
        }
        
        if (!columnNames.contains('synced_to_server')) {
          await db.execute('ALTER TABLE channels ADD COLUMN synced_to_server INTEGER DEFAULT 0');
          print('✅ Added synced_to_server column');
        }
        
        // Create new indexes
        await db.execute('CREATE INDEX IF NOT EXISTS idx_channels_deleted ON channels(deleted)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_channels_creator ON channels(creator_address)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_members_address ON members(member_address)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_workspaces_inviter ON workspaces(inviter_address)');
        
        print('✅ Channels table upgraded to version 3 successfully');
      } catch (e) {
        print('❌ Error upgrading channels table: $e');
        // Continue anyway - partial upgrade is better than nothing
      }
    }
  }

  // ============ USER OPERATIONS ============

  /// Get user profile
  Future<Map<String, dynamic>?> getUserProfile(String address) async {
    try {
      final db = await database;
      final results = await db.query(
        'users',
        where: 'address = ?',
        whereArgs: [address],
        limit: 1,
      );

      if (results.isEmpty) return null;
      return results.first;
    } catch (e) {
      print('❌ Get user profile error: $e');
      return null;
    }
  }

  /// Save user profile
  Future<bool> saveUserProfile({
    required String address,
    required String username,
    required String email,
  }) async {
    try {
      final db = await database;
      final now = DateTime.now().millisecondsSinceEpoch;

      await db.insert(
        'users',
        {
          'address': address,
          'username': username,
          'email': email,
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      print('✅ User profile saved to SQLite: $address');
      return true;
    } catch (e) {
      print('❌ Save user profile error: $e');
      return false;
    }
  }

  // ============ WORKSPACE OPERATIONS ============

  /// Create workspace
  Future<String?> createWorkspace({
    required String workspaceName,
    required String inviterAddress,
  }) async {
    try {
      final db = await database;
      final workspaceId = _generateId();
      final now = DateTime.now().millisecondsSinceEpoch;

      // Get previous hash for chain
      final lastWorkspace = await db.query(
        'workspaces',
        orderBy: 'timestamp DESC',
        limit: 1,
      );

      String previousHash = '0';
      if (lastWorkspace.isNotEmpty) {
        previousHash = lastWorkspace.first['current_hash'] as String? ?? '0';
      }

      // Calculate current hash
      final dataToHash = {
        'workspace_id': workspaceId,
        'name': workspaceName,
        'inviter_address': inviterAddress,
        'timestamp': now,
        'previous_hash': previousHash,
      };
      final currentHash = _calculateHash(dataToHash);

      await db.insert(
        'workspaces',
        {
          'workspace_id': workspaceId,
          'name': workspaceName,
          'inviter_address': inviterAddress,
          'created_at': now,
          'timestamp': now,
          'previous_hash': previousHash,
          'current_hash': currentHash,
          'synced_to_server': 0,
        },
      );

      print('✅ Workspace created in SQLite: $workspaceId');
      return workspaceId;
    } catch (e) {
      print('❌ Create workspace error: $e');
      return null;
    }
  }

  /// Save workspace (for caching from server)
  Future<bool> saveWorkspace({
    required String workspaceId,
    required String workspaceName,
    required String inviterAddress,
    int? createdAt,
    int? timestamp,
    String? previousHash,
    String? currentHash,
  }) async {
    try {
      final db = await database;
      final now = DateTime.now().millisecondsSinceEpoch;
      
      await db.insert(
        'workspaces',
        {
          'workspace_id': workspaceId,
          'name': workspaceName,
          'inviter_address': inviterAddress,
          'created_at': createdAt ?? now,
          'timestamp': timestamp ?? now,
          'previous_hash': previousHash,
          'current_hash': currentHash,
          'synced_to_server': 1, // This came from server
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      print('✅ Workspace saved to SQLite: $workspaceName (ID: $workspaceId)');
      return true;
    } catch (e) {
      print('❌ Save workspace error: $e');
      return false;
    }
  }

  /// Get user workspaces
  Future<List<Map<String, dynamic>>> getUserWorkspaces(String userAddress) async {
    try {
      final db = await database;
      
      // Get workspaces where user is inviter or member
      final workspaces = await db.rawQuery('''
        SELECT DISTINCT w.*
        FROM workspaces w
        LEFT JOIN members m ON w.workspace_id = m.workspace_id
        WHERE w.inviter_address = ? OR m.member_address = ?
        ORDER BY w.timestamp DESC
      ''', [userAddress, userAddress]);

      return workspaces.map((ws) => {
        'workspace_id': ws['workspace_id'],
        'workspaceId': ws['workspace_id'],
        'workspaceName': ws['name'],
        'name': ws['name'],
        'inviter_address': ws['inviter_address'],
        'inviterAddress': ws['inviter_address'],
        'created_at': ws['created_at'],
        'timestamp': ws['timestamp'],
      }).toList();
    } catch (e) {
      print('❌ Get user workspaces error: $e');
      return [];
    }
  }

  /// Get workspace members
  Future<List<Map<String, dynamic>>> getWorkspaceMembers(String workspaceId) async {
    try {
      final db = await database;
      final members = await db.query(
        'members',
        where: 'workspace_id = ?',
        whereArgs: [workspaceId],
        orderBy: 'joined_at ASC',
      );

      return members.map((m) => {
        'member_address': m['member_address'],
        'memberAddress': m['member_address'],
        'display_name': m['display_name'],
        'memberDisplayName': m['display_name'],
        'workspace_id': m['workspace_id'],
        'workspaceId': m['workspace_id'],
        'joined_at': m['joined_at'],
        'joinedAt': m['joined_at'],
      }).toList();
    } catch (e) {
      print('❌ Get workspace members error: $e');
      return [];
    }
  }

  /// Add workspace member (with deduplication)
  Future<bool> addWorkspaceMember({
    required String workspaceId,
    required String memberAddress,
    String? displayName,
  }) async {
    try {
      final db = await database;
      final now = DateTime.now().millisecondsSinceEpoch;
      
      // Normalize address (lowercase, trim)
      final normalizedAddress = memberAddress.toLowerCase().trim();

      // Check if member already exists to avoid duplicates
      final existing = await db.query(
        'members',
        where: 'workspace_id = ? AND member_address = ?',
        whereArgs: [workspaceId, normalizedAddress],
        limit: 1,
      );
      
      if (existing.isNotEmpty) {
        // Update existing member (in case display name changed)
        await db.update(
          'members',
          {
            'display_name': displayName ?? normalizedAddress.substring(0, 10),
            'joined_at': now,
          },
          where: 'workspace_id = ? AND member_address = ?',
          whereArgs: [workspaceId, normalizedAddress],
        );
        print('🔄 Updated existing member in SQLite: $normalizedAddress');
        return true;
      }

      // Insert new member
      await db.insert(
        'members',
        {
          'workspace_id': workspaceId,
          'member_address': normalizedAddress,
          'display_name': displayName ?? normalizedAddress.substring(0, 10),
          'joined_at': now,
          'synced_to_server': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      print('✅ Member added to workspace in SQLite: $normalizedAddress');
      return true;
    } catch (e) {
      print('❌ Add workspace member error: $e');
      return false;
    }
  }

  // ============ MESSAGE OPERATIONS ============

  /// Add message
  Future<String?> addMessage({
    required String workspaceId,
    String? channelId,
    required String senderAddress,
    String? receiverAddress,
    required String messageText,
    String? fileId,
    String? providedMessageId, // Allow providing message ID for consistency
  }) async {
    try {
      final db = await database;
      // Use provided message ID if available, otherwise generate new one
      final messageId = providedMessageId ?? _generateId();
      final now = DateTime.now().millisecondsSinceEpoch;
      
      // Check for duplicate message_id (prevent duplicates) - use efficient query
      final existing = await db.query(
        'messages',
        columns: ['message_id'],
        where: 'message_id = ?',
        whereArgs: [messageId],
        limit: 1, // Only need to check existence, not fetch full data
      );
      
      if (existing.isNotEmpty) {
        print('⚠️ Message with ID $messageId already exists, skipping duplicate');
        return messageId; // Return existing ID
      }

      // Get previous hash for chain
      final lastMessage = await db.query(
        'messages',
        where: 'workspace_id = ?',
        whereArgs: [workspaceId],
        orderBy: 'timestamp DESC',
        limit: 1,
      );

      String previousHash = '0';
      if (lastMessage.isNotEmpty) {
        previousHash = lastMessage.first['current_hash'] as String? ?? '0';
      }

      // Calculate current hash
      final dataToHash = {
        'message_id': messageId,
        'workspace_id': workspaceId,
        'sender_address': senderAddress,
        'receiver_address': receiverAddress,
        'message_text': messageText,
        'timestamp': now,
        'previous_hash': previousHash,
      };
      final currentHash = _calculateHash(dataToHash);

      // Use conflictAlgorithm to handle race conditions gracefully
      // If message_id already exists (race condition), ignore the insert
      await db.insert(
        'messages',
        {
          'message_id': messageId,
          'workspace_id': workspaceId,
          'channel_id': channelId,
          'sender_address': senderAddress,
          'receiver_address': receiverAddress,
          'message_text': messageText,
          'file_id': fileId,
          'timestamp': now,
          'previous_hash': previousHash,
          'current_hash': currentHash,
          'synced_to_server': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore, // Ignore if duplicate (race condition)
      );

      print('✅ Message added to SQLite: $messageId');
      return messageId;
    } catch (e) {
      print('❌ Add message error: $e');
      return null;
    }
  }

  /// Get channel messages
  /// [sinceTimestamp] - Optional: Only fetch messages after this timestamp (for incremental loading)
  Future<List<Map<String, dynamic>>> getChannelMessages({
    required String workspaceId,
    required String channelId,
    int? sinceTimestamp, // Only fetch messages after this timestamp (milliseconds)
  }) async {
    try {
      final db = await database;
      
      // Normalize channel ID for query (case-insensitive)
      final normalizedChannelId = channelId.toLowerCase().trim();
      
      // Build WHERE clause
      String whereClause = 'workspace_id = ? AND (channel_id = ? OR LOWER(channel_id) = ?)';
      List<dynamic> whereArgs = [workspaceId, channelId, normalizedChannelId];
      
      // Add timestamp filter if provided (for incremental loading)
      if (sinceTimestamp != null) {
        whereClause += ' AND timestamp > ?';
        whereArgs.add(sinceTimestamp);
      }
      
      // Query messages - try exact match first, then case-insensitive
      final messages = await db.query(
        'messages',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'timestamp ASC',
      );

      print('📦 SQLite query: workspace=$workspaceId, channel=$channelId (normalized=$normalizedChannelId), found ${messages.length} messages');

      return messages.map((m) => {
        'message_id': m['message_id'],
        'messageText': m['message_text'],
        'message_text': m['message_text'],
        'sender_address': m['sender_address'],
        'senderAddress': m['sender_address'],
        'receiver_address': m['receiver_address'],
        'receiverAddress': m['receiver_address'],
        'workspace_id': m['workspace_id'],
        'workspaceId': m['workspace_id'],
        'channel_id': m['channel_id'],
        'channelId': m['channel_id'],
        'file_id': m['file_id'],
        'fileId': m['file_id'],
        'timestamp': m['timestamp'],
        'content': m['message_text'], // Add content field for UI compatibility
      }).toList();
    } catch (e) {
      print('❌ Get channel messages error: $e');
      return [];
    }
  }

  /// Get direct messages
  Future<List<Map<String, dynamic>>> getDirectMessages({
    required String user1Address,
    required String user2Address,
  }) async {
    try {
      final db = await database;
      final messages = await db.rawQuery('''
        SELECT * FROM messages
        WHERE workspace_id IS NULL
        AND (
          (sender_address = ? AND receiver_address = ?)
          OR (sender_address = ? AND receiver_address = ?)
        )
        ORDER BY timestamp ASC
      ''', [user1Address, user2Address, user2Address, user1Address]);

      return messages.map((m) => {
        'message_id': m['message_id'],
        'messageText': m['message_text'],
        'message_text': m['message_text'],
        'sender_address': m['sender_address'],
        'senderAddress': m['sender_address'],
        'receiver_address': m['receiver_address'],
        'receiverAddress': m['receiver_address'],
        'timestamp': m['timestamp'],
      }).toList();
    } catch (e) {
      print('❌ Get direct messages error: $e');
      return [];
    }
  }

  // ============ PEER OPERATIONS ============

  /// Save peer information
  Future<bool> savePeer({
    required String userAddress,
    required String ipAddress,
    required int port,
  }) async {
    try {
      final db = await database;
      final now = DateTime.now().millisecondsSinceEpoch;

      await db.insert(
        'peers',
        {
          'user_address': userAddress,
          'ip_address': ipAddress,
          'port': port,
          'last_seen': now,
          'is_online': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      return true;
    } catch (e) {
      print('❌ Save peer error: $e');
      return false;
    }
  }

  /// Get peer by user address
  Future<Map<String, dynamic>?> getPeer(String userAddress) async {
    try {
      final db = await database;
      final results = await db.query(
        'peers',
        where: 'user_address = ?',
        whereArgs: [userAddress],
        limit: 1,
      );

      if (results.isEmpty) return null;
      return results.first;
    } catch (e) {
      print('❌ Get peer error: $e');
      return null;
    }
  }

  /// Get all peers
  Future<List<Map<String, dynamic>>> getAllPeers() async {
    try {
      final db = await database;
      return await db.query('peers', orderBy: 'last_seen DESC');
    } catch (e) {
      print('❌ Get all peers error: $e');
      return [];
    }
  }

  // ============ SYNC OPERATIONS ============

  /// Get unsynced messages
  Future<List<Map<String, dynamic>>> getUnsyncedMessages() async {
    try {
      final db = await database;
      return await db.query(
        'messages',
        where: 'synced_to_server = ?',
        whereArgs: [0],
        orderBy: 'timestamp ASC',
      );
    } catch (e) {
      print('❌ Get unsynced messages error: $e');
      return [];
    }
  }

  /// Mark message as synced
  Future<bool> markMessageSynced(String messageId) async {
    try {
      final db = await database;
      await db.update(
        'messages',
        {'synced_to_server': 1},
        where: 'message_id = ?',
        whereArgs: [messageId],
      );
      return true;
    } catch (e) {
      print('❌ Mark message synced error: $e');
      return false;
    }
  }

  /// Update message ID (when server returns different ID)
  Future<bool> updateMessageId({
    required String oldMessageId,
    required String newMessageId,
  }) async {
    try {
      final db = await database;
      
      // Check if new messageId already exists
      final existing = await db.query(
        'messages',
        columns: ['message_id'],
        where: 'message_id = ?',
        whereArgs: [newMessageId],
        limit: 1,
      );
      
      if (existing.isNotEmpty) {
        print('⚠️ Message with new ID $newMessageId already exists, deleting old message: $oldMessageId');
        // Delete old message if new one already exists
        await db.delete(
          'messages',
          where: 'message_id = ?',
          whereArgs: [oldMessageId],
        );
        return true;
      }
      
      // Update message ID
      await db.update(
        'messages',
        {'message_id': newMessageId, 'synced_to_server': 1},
        where: 'message_id = ?',
        whereArgs: [oldMessageId],
      );
      print('✅ Updated message ID: $oldMessageId -> $newMessageId');
      return true;
    } catch (e) {
      print('❌ Update message ID error: $e');
      return false;
    }
  }

  /// Check if message is already synced
  Future<bool> isMessageSynced(String messageId) async {
    try {
      final db = await database;
      final result = await db.query(
        'messages',
        columns: ['synced_to_server'],
        where: 'message_id = ?',
        whereArgs: [messageId],
        limit: 1,
      );
      
      if (result.isEmpty) return false;
      return (result.first['synced_to_server'] as int? ?? 0) == 1;
    } catch (e) {
      print('❌ Check message synced error: $e');
      return false;
    }
  }

  // ============ CHAIN VERIFICATION ============

  /// Verify chain integrity
  Future<bool> verifyChainIntegrity(String tableName) async {
    try {
      final db = await database;
      final records = await db.query(
        tableName,
        orderBy: 'timestamp ASC',
      );

      if (records.isEmpty) return true;

      String previousHash = '0';
      for (final record in records) {
        final currentHash = record['current_hash'] as String?;
        final recordPreviousHash = record['previous_hash'] as String?;

        // Verify previous hash matches
        if (recordPreviousHash != previousHash) {
          print('❌ Chain broken at ${record['workspace_id'] ?? record['message_id']}');
          return false;
        }

        // Verify current hash
        final dataToHash = Map<String, dynamic>.from(record);
        dataToHash.remove('current_hash');
        final calculatedHash = _calculateHash(dataToHash);

        if (currentHash != calculatedHash) {
          print('❌ Hash mismatch at ${record['workspace_id'] ?? record['message_id']}');
          return false;
        }

        previousHash = currentHash!;
      }

      print('✅ Chain integrity verified for $tableName');
      return true;
    } catch (e) {
      print('❌ Verify chain integrity error: $e');
      return false;
    }
  }

  // ============ CHANNEL OPERATIONS ============

  /// Get workspace channels (MongoDB-aligned filtering)
  /// memberAddress: If provided, filters channels based on membership and privacy
  Future<List<String>> getWorkspaceChannels(
    String workspaceId, {
    String? memberAddress,
  }) async {
    try {
      final db = await database;
      
      // First, check if user is a workspace member (MongoDB logic)
      bool isWorkspaceMember = false;
      if (memberAddress != null) {
        final memberCheck = await db.query(
          'members',
          where: 'workspace_id = ? AND member_address = ?',
          whereArgs: [workspaceId, memberAddress.toLowerCase().trim()],
          limit: 1,
        );
        isWorkspaceMember = memberCheck.isNotEmpty;
      }
      
      // Build query based on MongoDB logic
      List<Map<String, dynamic>> cachedChannels;
      
      if (isWorkspaceMember) {
        // Workspace members see ALL channels (except deleted)
        cachedChannels = await db.query(
          'channels',
          where: 'workspace_id = ? AND deleted = 0',
          whereArgs: [workspaceId],
          orderBy: 'created_at ASC',
        );
        print('✅ User $memberAddress is workspace member - showing all channels');
      } else if (memberAddress != null) {
        // Non-members see only: default channels, public channels, or channels where they're in members array
        final memberAddr = memberAddress.toLowerCase().trim();
        
        // Get all channels for this workspace
        final allChannels = await db.query(
          'channels',
          where: 'workspace_id = ? AND deleted = 0',
          whereArgs: [workspaceId],
        );
        
        // Filter channels based on MongoDB logic
        cachedChannels = allChannels.where((ch) {
          final isDefault = (ch['is_default'] as int? ?? 0) == 1;
          final isPrivate = (ch['is_private'] as int? ?? 0) == 1;
          final membersJson = ch['members']?.toString() ?? '[]';
          
          // Parse members array
          List<String> members = [];
          try {
            final membersList = jsonDecode(membersJson);
            if (membersList is List) {
              members = membersList.map((m) => m.toString().toLowerCase().trim()).toList();
            }
          } catch (e) {
            // Invalid JSON, treat as empty
          }
          
          // Show if:
          // 1. Default channel (general/random)
          // 2. Public channel (not private)
          // 3. User is in members array
          // 4. Members array is empty (accessible to all)
          return isDefault || !isPrivate || members.contains(memberAddr) || members.isEmpty;
        }).toList();
        
        print('⚠️ User $memberAddress is not workspace member - using restrictive filter');
      } else {
        // No member address provided - show all non-deleted channels
        cachedChannels = await db.query(
          'channels',
          where: 'workspace_id = ? AND deleted = 0',
          whereArgs: [workspaceId],
          orderBy: 'created_at ASC',
        );
      }
      
      // Also get channels from messages (for backward compatibility)
      final messageChannels = await db.rawQuery('''
        SELECT DISTINCT channel_id
        FROM messages
        WHERE workspace_id = ? AND channel_id IS NOT NULL AND channel_id != ''
      ''', [workspaceId]);
      
      // CRITICAL: Get list of deleted channel IDs to exclude them from messages
      final deletedChannels = await db.query(
        'channels',
        columns: ['channel_id'],
        where: 'workspace_id = ? AND deleted = 1',
        whereArgs: [workspaceId],
      );
      final deletedChannelIds = deletedChannels
          .map((ch) => ch['channel_id']?.toString().toLowerCase().trim())
          .whereType<String>()
          .toSet();
      
      final channelSet = <String>{};
      
      // Add channels from channels table (prioritize channel_name for display)
      for (final ch in cachedChannels) {
        final channelName = ch['channel_name']?.toString();
        final channelId = ch['channel_id']?.toString();
        
        // Prefer channel_name for display, but fallback to channel_id
        final displayName = channelName ?? channelId;
        if (displayName != null && displayName.isNotEmpty) {
          // Capitalize first letter for display
          final capitalized = displayName.substring(0, 1).toUpperCase() + 
                             (displayName.length > 1 ? displayName.substring(1) : '');
          channelSet.add(capitalized);
        }
      }
      
      // Add channels from messages (for channels that might not be in channels table yet)
      // BUT EXCLUDE deleted channels (channels that are marked as deleted in channels table)
      for (final ch in messageChannels) {
        final channelId = ch['channel_id']?.toString();
        if (channelId != null && channelId.isNotEmpty) {
          final normalizedChannelId = channelId.toLowerCase().trim();
          
          // Skip if this channel is marked as deleted in channels table
          if (deletedChannelIds.contains(normalizedChannelId)) {
            print('🚫 Skipping deleted channel from messages: $channelId');
            continue;
          }
          
          // Capitalize first letter
          final capitalized = channelId.substring(0, 1).toUpperCase() + 
                             (channelId.length > 1 ? channelId.substring(1) : '');
          channelSet.add(capitalized);
        }
      }
      
      // Sort channels: General first, Random second, then others by creation time
      final sortedChannels = channelSet.toList();
      sortedChannels.sort((a, b) {
        final aLower = a.toLowerCase();
        final bLower = b.toLowerCase();
        if (aLower == 'general') return -1;
        if (bLower == 'general') return 1;
        if (aLower == 'random') return -1;
        if (bLower == 'random') return 1;
        return a.compareTo(b);
      });
      
      print('✅ SQLite returned ${sortedChannels.length} channels for workspace $workspaceId');
      return sortedChannels;
    } catch (e) {
      print('❌ Get workspace channels error: $e');
      return [];
    }
  }

  /// Save channel to cache (MongoDB-aligned with all fields)
  Future<bool> saveChannel({
    required String workspaceId,
    required String channelId,
    String? channelName,
    String? creatorAddress,
    List<String>? members,  // Array of member addresses
    bool? isPrivate,        // true = private channel
    bool? isDefault,        // true = default channel (general/random)
    int? timestamp,
    String? previousHash,
    String? currentHash,
    bool? deleted,          // true = soft deleted
    bool? syncedToServer,
  }) async {
    try {
      final db = await database;
      final now = DateTime.now().millisecondsSinceEpoch;
      
      // Determine is_default if not provided
      final normalizedChannelId = channelId.toLowerCase().trim();
      final defaultChannels = ['general', 'random'];
      final isDefaultChannel = isDefault ?? defaultChannels.contains(normalizedChannelId);
      
      // CRITICAL: Check if channel already exists and is deleted
      // If deleted flag is not explicitly provided, preserve existing deleted status
      bool shouldMarkDeleted = deleted ?? false;
      if (deleted == null) {
        // deleted parameter not provided - check existing channel status
        final existingChannel = await db.query(
          'channels',
          where: 'workspace_id = ? AND channel_id = ?',
          whereArgs: [workspaceId, normalizedChannelId],
          limit: 1,
        );
        
        if (existingChannel.isNotEmpty) {
          final existingDeleted = (existingChannel.first['deleted'] as int? ?? 0) == 1;
          if (existingDeleted) {
            // Channel is already deleted - preserve deleted status
            shouldMarkDeleted = true;
            print('🛡️ Preserving deleted status for channel: $channelId (was already deleted)');
          }
        }
      }
      
      // Prepare channel data (MongoDB-aligned)
      final channelData = {
        'channel_id': channelId,
        'workspace_id': workspaceId,
        'channel_name': channelName ?? channelId,
        'creator_address': creatorAddress,
        'members': members != null ? jsonEncode(members) : '[]',  // Store as JSON array
        'is_private': (isPrivate ?? false) ? 1 : 0,
        'is_default': isDefaultChannel ? 1 : 0,
        'created_at': timestamp ?? now,
        'timestamp': timestamp ?? now,
        'previous_hash': previousHash,
        'current_hash': currentHash,
        'deleted': shouldMarkDeleted ? 1 : 0,  // Use preserved deleted status
        'synced_to_server': (syncedToServer ?? false) ? 1 : 0,
      };
      
      try {
        await db.insert(
          'channels',
          channelData,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        print('✅ Channel saved to SQLite: $channelName (ID: $channelId, deleted: $shouldMarkDeleted)');
        return true;
      } catch (e) {
        // Table might not exist or schema mismatch, try to create/upgrade
        print('⚠️ Error saving channel, checking table schema: $e');
        
        // Check if table exists
        final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='channels'"
        );
        
        if (tables.isEmpty) {
          // Create table with full schema
          await db.execute('''
            CREATE TABLE IF NOT EXISTS channels (
              channel_id TEXT,
              workspace_id TEXT,
              channel_name TEXT,
              creator_address TEXT,
              members TEXT,
              is_private INTEGER DEFAULT 0,
              is_default INTEGER DEFAULT 0,
              created_at INTEGER,
              timestamp INTEGER,
              previous_hash TEXT,
              current_hash TEXT,
              deleted INTEGER DEFAULT 0,
              synced_to_server INTEGER DEFAULT 0,
              PRIMARY KEY (channel_id, workspace_id)
            )
          ''');
          
          await db.execute('CREATE INDEX IF NOT EXISTS idx_channels_workspace ON channels(workspace_id)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_channels_deleted ON channels(deleted)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_channels_creator ON channels(creator_address)');
          
          // Retry insert
          await db.insert('channels', channelData, conflictAlgorithm: ConflictAlgorithm.replace);
          print('✅ Channel table created and channel saved');
          return true;
        } else {
          // Table exists but might have old schema - try with minimal fields
          try {
            await db.insert(
              'channels',
              {
                'channel_id': channelId,
                'workspace_id': workspaceId,
                'channel_name': channelName ?? channelId,
                'creator_address': creatorAddress,
                'created_at': now,
                'is_default': isDefaultChannel ? 1 : 0,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            print('✅ Channel saved with minimal fields (old schema)');
            return true;
          } catch (e2) {
            print('❌ Save channel error: $e2');
            return false;
          }
        }
      }
    } catch (e) {
      print('❌ Save channel error: $e');
      return false;
    }
  }

  /// Delete channel (soft delete - mark as deleted)
  Future<bool> deleteChannel({
    required String workspaceId,
    required String channelId,
  }) async {
    try {
      final db = await database;
      final normalizedChannelId = channelId.toLowerCase().trim();
      
      // Update channel to mark as deleted
      final rowsAffected = await db.update(
        'channels',
        {
          'deleted': 1,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'workspace_id = ? AND channel_id = ?',
        whereArgs: [workspaceId, normalizedChannelId],
      );
      
      if (rowsAffected > 0) {
        print('✅ Channel deleted from SQLite: $channelId in workspace $workspaceId');
        return true;
      } else {
        print('⚠️ Channel not found in SQLite: $channelId in workspace $workspaceId');
        return false;
      }
    } catch (e) {
      print('❌ Delete channel from SQLite error: $e');
      return false;
    }
  }

  /// Get all channel IDs for a workspace (including deleted ones)
  /// Used for syncing deleted channels from server
  Future<List<String>> getAllChannelIds(String workspaceId) async {
    try {
      final db = await database;
      final channels = await db.query(
        'channels',
        columns: ['channel_id'],
        where: 'workspace_id = ?',
        whereArgs: [workspaceId],
      );
      
      return channels
          .map((ch) => (ch['channel_id']?.toString() ?? '').toLowerCase().trim())
          .where((id) => id.isNotEmpty)
          .toList();
    } catch (e) {
      print('❌ Get all channel IDs error: $e');
      return [];
    }
  }

  // ============ HELPER METHODS ============

  /// Generate unique ID
  String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString() +
        DateTime.now().microsecondsSinceEpoch.toString();
  }

  /// Calculate SHA-256 hash
  String _calculateHash(Map<String, dynamic> data) {
    final jsonString = jsonEncode(data);
    final bytes = utf8.encode(jsonString);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Close database
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      print('✅ SQLite database closed');
    }
  }
}

