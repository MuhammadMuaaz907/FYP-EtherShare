import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../security/aes_crypto_service.dart';

/// Chain verification result class
/// Used to return detailed chain integrity status without throwing exceptions
class ChainVerificationResult {
  final bool isValid;
  final String? failureReason; // 'previous_hash_mismatch', 'missing_parent', 'fork_detected', 'hash_mismatch'
  final String? brokenAt; // message_id or workspace_id where chain broke
  final Map<String, dynamic>? details; // Additional failure details

  ChainVerificationResult({
    required this.isValid,
    this.failureReason,
    this.brokenAt,
    this.details,
  });

  /// Create success result
  factory ChainVerificationResult.success() {
    return ChainVerificationResult(isValid: true);
  }

  /// Create failure result
  factory ChainVerificationResult.failure({
    required String reason,
    required String brokenAt,
    Map<String, dynamic>? details,
  }) {
    return ChainVerificationResult(
      isValid: false,
      failureReason: reason,
      brokenAt: brokenAt,
      details: details ?? {},
    );
  }

  /// Check if result indicates chain integrity failure
  bool get isChainIntegrityFailed => !isValid;
}

/// SQLite Service for Local Database Storage
/// Mirrors MongoDB functionality for offline support
class SQLiteService {
  static SQLiteService? _instance;
  
  /// Safe substring helper to prevent RangeError
  /// Returns substring of length [len] or full string if shorter
  static String safeSubstring(String? str, int len) {
    if (str == null || str.isEmpty) return '';
    return str.length > len ? str.substring(0, len) : str;
  }
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
      version: 8, // Updated version for encrypted_message and iv columns
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
        encrypted_message TEXT,
        iv TEXT,
        file_id TEXT,
        timestamp INTEGER,
        previous_hash TEXT,
        current_hash TEXT,
        payload_hash TEXT,
        hash_version INTEGER DEFAULT 2,
        synced_to_server INTEGER DEFAULT 0,
        message_state TEXT DEFAULT 'OFFLINE_LOCAL'
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

    // Chain state table - stores last server hash per channel for chain continuity
    await db.execute('''
      CREATE TABLE chain_state (
        workspace_id TEXT NOT NULL,
        channel_id TEXT NOT NULL,
        last_server_hash TEXT NOT NULL,
        last_server_message_id TEXT,
        last_server_timestamp INTEGER,
        updated_at INTEGER DEFAULT (strftime('%s', 'now') * 1000),
        PRIMARY KEY (workspace_id, channel_id)
      )
    ''');

    // Create indexes for better performance
    await db.execute('CREATE INDEX idx_messages_workspace ON messages(workspace_id)');
    await db.execute('CREATE INDEX idx_messages_channel ON messages(channel_id)');
    await db.execute('CREATE INDEX idx_messages_sender ON messages(sender_address)');
    await db.execute('CREATE INDEX idx_messages_receiver ON messages(receiver_address)');
    await db.execute('CREATE INDEX idx_messages_timestamp ON messages(timestamp)');
    await db.execute('CREATE INDEX idx_messages_state ON messages(message_state)'); // CRITICAL: Index for state filtering
    await db.execute('CREATE INDEX idx_members_workspace ON members(workspace_id)');
    await db.execute('CREATE INDEX idx_members_address ON members(member_address)');
    await db.execute('CREATE INDEX idx_channels_workspace ON channels(workspace_id)');
    await db.execute('CREATE INDEX idx_channels_deleted ON channels(deleted)');
    await db.execute('CREATE INDEX idx_channels_creator ON channels(creator_address)');
    await db.execute('CREATE INDEX idx_peers_address ON peers(user_address)');
    await db.execute('CREATE INDEX idx_workspaces_inviter ON workspaces(inviter_address)');
    await db.execute('CREATE INDEX idx_chain_state_workspace ON chain_state(workspace_id)');
    await db.execute('CREATE INDEX idx_chain_state_channel ON chain_state(channel_id)');

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
    
    // Migration from version 3 to 4: Add chain_state table for chain continuity
    if (oldVersion < 4) {
      print('📦 Adding chain_state table for version 4 (chain continuity)...');
      try {
        // Check if chain_state table exists
        final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='chain_state'"
        );
        
        if (tables.isEmpty) {
          // Create chain_state table
          await db.execute('''
            CREATE TABLE chain_state (
              workspace_id TEXT NOT NULL,
              channel_id TEXT NOT NULL,
              last_server_hash TEXT NOT NULL,
              last_server_message_id TEXT,
              last_server_timestamp INTEGER,
              updated_at INTEGER DEFAULT (strftime('%s', 'now') * 1000),
              PRIMARY KEY (workspace_id, channel_id)
            )
          ''');
          
          // Create indexes
          await db.execute('CREATE INDEX IF NOT EXISTS idx_chain_state_workspace ON chain_state(workspace_id)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_chain_state_channel ON chain_state(channel_id)');
          
          print('✅ Chain state table created successfully');
        } else {
          print('ℹ️ Chain state table already exists');
        }
      } catch (e) {
        print('❌ Error creating chain_state table: $e');
        // Continue anyway - partial upgrade is better than nothing
      }
    }
    
    // Migration from version 4 to 5: Add message_state column for state tracking
    if (oldVersion < 5) {
      print('📦 Adding message_state column for version 5 (message state tracking)...');
      try {
        // Check if message_state column exists
        final columns = await db.rawQuery("PRAGMA table_info(messages)");
        final columnNames = columns.map((c) => c['name'] as String).toSet();
        
        if (!columnNames.contains('message_state')) {
          await db.execute('ALTER TABLE messages ADD COLUMN message_state TEXT DEFAULT \'OFFLINE_LOCAL\'');
          
          // Update existing messages: synced_to_server=1 -> ONLINE_CONFIRMED, synced_to_server=0 -> OFFLINE_LOCAL
          await db.execute('''
            UPDATE messages 
            SET message_state = CASE 
              WHEN synced_to_server = 1 THEN 'ONLINE_CONFIRMED'
              ELSE 'OFFLINE_LOCAL'
            END
          ''');
          
          print('✅ Message state column added successfully');
        } else {
          print('ℹ️ Message state column already exists');
        }
      } catch (e) {
        print('❌ Error adding message_state column: $e');
        // Continue anyway - partial upgrade is better than nothing
      }
    }
    
    // Migration from version 5 to 6: Add payload_hash column for payload-based hashing
    if (oldVersion < 6) {
      print('📦 Adding payload_hash column for version 6 (payload-based hashing transition)...');
      try {
        // Check if payload_hash column exists
        final columns = await db.rawQuery("PRAGMA table_info(messages)");
        final columnNames = columns.map((c) => c['name'] as String).toSet();
        
        if (!columnNames.contains('payload_hash')) {
          await db.execute('ALTER TABLE messages ADD COLUMN payload_hash TEXT');
          
          // Calculate payload_hash for existing messages (backfill)
          final allMessages = await db.query('messages');
          for (final msg in allMessages) {
            final messageText = msg['message_text'] as String? ?? '';
            if (messageText.isNotEmpty) {
              final payloadHash = _calculatePayloadHash(messageText);
              await db.update(
                'messages',
                {'payload_hash': payloadHash},
                where: 'message_id = ?',
                whereArgs: [msg['message_id']],
              );
            }
          }
          
          print('✅ Payload hash column added and backfilled successfully');
        } else {
          print('ℹ️ Payload hash column already exists');
        }
      } catch (e) {
        print('❌ Error adding payload_hash column: $e');
        // Continue anyway - partial upgrade is better than nothing
      }
    }
    
    // Migration from version 6 to 7: Add hash_version column for version-based hashing
    if (oldVersion < 7) {
      print('📦 Adding hash_version column for version 7 (hash version migration)...');
      try {
        // Check if hash_version column exists
        final columns = await db.rawQuery("PRAGMA table_info(messages)");
        final columnNames = columns.map((c) => c['name'] as String).toSet();
        
        if (!columnNames.contains('hash_version')) {
          await db.execute('ALTER TABLE messages ADD COLUMN hash_version INTEGER DEFAULT 1');
          
          // Existing messages without hash_version are treated as version 1 (plaintext hashing)
          // New messages will use version 2 (payload_hash hashing)
          // No need to update existing messages - they default to 1 which is correct
          
          print('✅ Hash version column added successfully (existing messages default to v1)');
        } else {
          print('ℹ️ Hash version column already exists');
        }
      } catch (e) {
        print('❌ Error adding hash_version column: $e');
        // Continue anyway - partial upgrade is better than nothing
      }
    }
    
    // Migration from version 7 to 8: Add encrypted_message and iv columns for AES encryption
    if (oldVersion < 8) {
      print('📦 Adding encrypted_message and iv columns for version 8 (AES encryption)...');
      try {
        // Check if encrypted_message and iv columns exist
        final columns = await db.rawQuery("PRAGMA table_info(messages)");
        final columnNames = columns.map((c) => c['name'] as String).toSet();
        
        if (!columnNames.contains('encrypted_message')) {
          await db.execute('ALTER TABLE messages ADD COLUMN encrypted_message TEXT');
          print('✅ encrypted_message column added successfully');
        } else {
          print('ℹ️ encrypted_message column already exists');
        }
        
        if (!columnNames.contains('iv')) {
          await db.execute('ALTER TABLE messages ADD COLUMN iv TEXT');
          print('✅ iv column added successfully');
        } else {
          print('ℹ️ iv column already exists');
        }
        
        // Note: Existing messages keep message_text for backward compatibility
        // New messages will use encrypted_message instead
        
        print('✅ Encryption columns added successfully (existing messages remain unencrypted for compatibility)');
      } catch (e) {
        print('❌ Error adding encryption columns: $e');
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
            'display_name': displayName ?? safeSubstring(normalizedAddress, 10),
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
    String? messageState, // Optional: message state (ONLINE_CONFIRMED, OFFLINE_LOCAL, PENDING_SYNC, SYNCED)
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
      // CRITICAL: First check if we have a stored server hash (when server was offline)
      // This ensures chain continuity when syncing back to server
      String? storedServerHash;
      if (channelId != null) {
        storedServerHash = await getLastServerHash(
          workspaceId: workspaceId,
          channelId: channelId,
        );
      }
      
      // Get last SQLite message hash
      final lastMessage = await db.query(
        'messages',
        where: 'workspace_id = ? AND channel_id = ?',
        whereArgs: [workspaceId, channelId ?? ''],
        orderBy: 'timestamp DESC',
        limit: 1,
      );

      // CRITICAL GENESIS HANDLING: previous_hash must NEVER be null or empty
      // - For genesis (first message): previous_hash = "0" (exactly, not empty)
      // - For chain messages: previous_hash = last message's current_hash (64-char hex)
      // - previous_hash is ALWAYS a valid string (never null/empty)
      String previousHash = '0'; // Default to genesis
      bool isGenesis = true;
      
      // Determine previous_hash based on channel state
      if (lastMessage.isNotEmpty) {
        // Channel has messages - use last message's current_hash
        final lastCurrentHash = lastMessage.first['current_hash'] as String?;
        if (lastCurrentHash != null && lastCurrentHash.isNotEmpty && lastCurrentHash != '0') {
          previousHash = lastCurrentHash;
          isGenesis = false;
          print('🔗 [CHAIN] Using last message current_hash as previous_hash: ${safeSubstring(previousHash, 16)}...');
        } else {
          // Last message has invalid hash - this is an error condition
          print('❌ [GENESIS ERROR] Last message has invalid current_hash: ${lastCurrentHash ?? "null"}');
          print('   Falling back to genesis (previous_hash = "0")');
          previousHash = '0';
          isGenesis = true;
        }
      } else if (storedServerHash != null && storedServerHash.isNotEmpty && storedServerHash != '0') {
        // No local messages but have server hash - link to server chain
        previousHash = storedServerHash;
        isGenesis = false;
        print('🔗 [CHAIN] Using stored server hash as previous_hash: ${safeSubstring(storedServerHash, 16)}...');
      } else {
        // No messages and no server hash - this is genesis
        previousHash = '0';
        isGenesis = true;
        print('🔗 [GENESIS] First message in channel (previous_hash = "0")');
      }
      
      // CRITICAL VALIDATION: previous_hash must NEVER be null or empty
      if (previousHash.isEmpty) {
        print('❌ [CRYPTO ERROR] previous_hash is empty - cannot proceed');
        return null;
      }
      
      // For non-genesis, validate previous_hash format (should be 64-char hex)
      if (!isGenesis && (previousHash.length != 64 || !RegExp(r'^[a-f0-9]{64}$', caseSensitive: false).hasMatch(previousHash))) {
        print('❌ [CRYPTO ERROR] Invalid previous_hash format: length=${previousHash.length}, value=${safeSubstring(previousHash, 32)}...');
        print('   Expected: 64-char hex string');
        return null;
      }

      // CRITICAL: Calculate payload_hash from PLAINTEXT message_text
      // This must happen BEFORE encryption to ensure hash chain integrity
      // payload_hash is used in hash chain verification and must remain stable
      // 
      // SECURITY RULE: payload_hash is derived from plaintext ONLY (encryption-independent)
      // - Encryption randomness (AES-CBC IV) must NOT affect hash chain
      // - payload_hash MUST be calculated BEFORE encryption
      // - payload_hash MUST NEVER be derived from encrypted_message or iv
      final payloadHash = _calculatePayloadHash(messageText);
      
      // REGRESSION LOG: Log payload_hash at insert time for verification debugging
      print('🔍 INSERT: Calculating payload_hash for new message');
      print('   Plaintext length: ${messageText.length} chars');
      print('   Payload hash: ${safeSubstring(payloadHash, 16)}...');
      print('   Note: payload_hash is from plaintext ONLY (encryption-independent)');

      // SECURITY: Encrypt message_text AFTER payload_hash calculation
      // This ensures payload_hash is calculated from plaintext (for hash chain integrity)
      // while message_text is stored encrypted in SQLite
      String? encryptedMessage;
      String? iv;
      
      try {
        final encryptedPayload = await AESCryptoService.encrypt(messageText);
        encryptedMessage = encryptedPayload.cipherText;
        iv = encryptedPayload.iv;
        print('🔒 Message encrypted successfully (ciphertext length: ${encryptedMessage.length})');
      } catch (e) {
        print('⚠️ Encryption failed: $e - Storing message as plaintext (legacy mode)');
        // If encryption fails, store as plaintext for backward compatibility
        // This ensures messages are not lost if encryption service has issues
        encryptedMessage = null;
        iv = null;
      }

      // CRITICAL: Check for duplicate message by payload_hash BEFORE hash chain calculations
      // This prevents re-inserting the same message when syncing from server
      // A message with same workspace_id + channel_id + payload_hash is considered duplicate
      // This check runs AFTER payload_hash calculation but BEFORE current_hash/previous_hash computation
      // to prevent chain integrity issues from duplicate messages
      if (channelId != null) {
        final duplicateCheck = await db.query(
          'messages',
          columns: ['message_id'],
          where: 'workspace_id = ? AND channel_id = ? AND payload_hash = ?',
          whereArgs: [workspaceId, channelId, payloadHash],
          limit: 1,
        );
        
        if (duplicateCheck.isNotEmpty) {
          final existingMessageId = duplicateCheck.first['message_id'] as String;
          print('⚠️ Message with same payload_hash already exists in SQLite, skipping duplicate');
          print('   Existing message_id: $existingMessageId');
          print('   Payload hash: ${safeSubstring(payloadHash, 10)}...');
          print('   Workspace: $workspaceId, Channel: $channelId');
          print('   ➡️ Returning existing message_id (idempotent behavior)');
          // Return existing message_id without modifying hash chain
          // This ensures chain integrity is preserved during offline → online sync
          return existingMessageId;
        }
      } else if (receiverAddress != null) {
        // For direct messages (no channel_id), check by workspace_id + receiver_address + payload_hash
        final duplicateCheck = await db.query(
          'messages',
          columns: ['message_id'],
          where: 'workspace_id = ? AND (sender_address = ? OR receiver_address = ?) AND payload_hash = ?',
          whereArgs: [workspaceId, senderAddress, receiverAddress, payloadHash],
          limit: 1,
        );
        
        if (duplicateCheck.isNotEmpty) {
          final existingMessageId = duplicateCheck.first['message_id'] as String;
          print('⚠️ Direct message with same payload_hash already exists in SQLite, skipping duplicate');
          print('   Existing message_id: $existingMessageId');
          print('   Payload hash: ${safeSubstring(payloadHash, 10)}...');
          print('   ➡️ Returning existing message_id (idempotent behavior)');
          return existingMessageId;
        }
      }

      // NEW MESSAGES USE HASH VERSION 2 (payload_hash-based hashing)
      const hashVersion = 2;

      // Calculate current hash using hash_version-aware logic
      // Version 2: Uses payload_hash instead of message_text
      // 
      // CRITICAL: Only include fields that are used in hash calculation
      // DO NOT include: encrypted_message, iv, synced_to_server, message_state, file_id, channel_id
      // These fields are metadata and should not affect hash chain integrity
      final dataToHash = {
        'message_id': messageId,
        'workspace_id': workspaceId,
        'sender_address': senderAddress,
        'receiver_address': receiverAddress,
        'payload_hash': payloadHash, // Version 2: Use payload_hash (calculated from plaintext)
        'timestamp': now,
        'previous_hash': previousHash,
      };
      
      // REGRESSION LOG: Log hash calculation inputs
      print('🔍 INSERT: Calculating current_hash (v$hashVersion)');
      print('   payload_hash: ${safeSubstring(payloadHash, 16)}...');
      print('   previous_hash: ${safeSubstring(previousHash, 16)}...');
      
      final currentHash = _calculateHash(dataToHash, hashVersion: hashVersion);
      
      if (currentHash.isEmpty) {
        print('❌ [CRYPTO ERROR] current_hash calculation returned empty string');
        return null;
      }
      
      print('   current_hash: ${safeSubstring(currentHash, 16)}...');

      // Determine message state
      // If state provided, use it; otherwise default based on sync status
      final state = messageState ?? 'OFFLINE_LOCAL';
      
      // SECURITY: Store encrypted message (if encryption succeeded) or plaintext (for backward compatibility)
      // encrypted_message and iv are stored for new encrypted messages
      // message_text is kept NULL for encrypted messages, but may be populated for legacy messages
      final messageData = <String, dynamic>{
          'message_id': messageId,
          'workspace_id': workspaceId,
          'channel_id': channelId,
          'sender_address': senderAddress,
          'receiver_address': receiverAddress,
          'file_id': fileId,
          'timestamp': now,
          'previous_hash': previousHash,
          'current_hash': currentHash,
        'payload_hash': payloadHash,
        'hash_version': hashVersion, // NEW: Hash version (2 for new messages)
          'synced_to_server': 0,
          'message_state': state, // CRITICAL: Track message state
      };
      
      // Store encrypted message if encryption succeeded, otherwise store plaintext (legacy mode)
      if (encryptedMessage != null && iv != null) {
        // New encrypted message: store encrypted_message and iv, keep message_text NULL
        messageData['encrypted_message'] = encryptedMessage;
        messageData['iv'] = iv;
        messageData['message_text'] = null; // DO NOT store plaintext for encrypted messages
      } else {
        // Legacy mode: store plaintext (encryption failed or not available)
        messageData['message_text'] = messageText;
        messageData['encrypted_message'] = null;
        messageData['iv'] = null;
      }
      
      // CRITICAL: STRICT VALIDATION - Block insertion if ANY crypto field is invalid
      // This prevents chain integrity issues from incomplete or malformed messages
      if (hashVersion == 2) {
        // Validation 1: payload_hash must be valid 64-char hex
        if (payloadHash.isEmpty) {
          print('❌ [CRYPTO VALIDATION FAILED] payload_hash is empty - BLOCKING INSERT');
          return null;
        }
        if (payloadHash.length != 64 || !RegExp(r'^[a-f0-9]{64}$', caseSensitive: false).hasMatch(payloadHash)) {
          print('❌ [CRYPTO VALIDATION FAILED] Invalid payload_hash format: length=${payloadHash.length}');
          print('   Expected: 64-char hex string');
          return null;
        }
        
        // Validation 2: encrypted_message must be present and non-empty
        if (encryptedMessage == null || encryptedMessage.isEmpty) {
          print('❌ [CRYPTO VALIDATION FAILED] encrypted_message is missing - BLOCKING INSERT');
          return null;
        }
        
        // Validation 3: iv must be present and non-empty
        if (iv == null || iv.isEmpty) {
          print('❌ [CRYPTO VALIDATION FAILED] iv is missing - BLOCKING INSERT');
          return null;
        }
        
        // Validation 4: previous_hash must NEVER be null or empty
        // - Genesis: previous_hash = "0" (exactly)
        // - Chain: previous_hash = 64-char hex
        if (previousHash.isEmpty) {
          print('❌ [CRYPTO VALIDATION FAILED] previous_hash is empty - BLOCKING INSERT');
          print('   Genesis messages must use previous_hash = "0" (not empty)');
          return null;
        }
        if (previousHash != '0') {
          // Non-genesis: validate format
          if (previousHash.length != 64 || !RegExp(r'^[a-f0-9]{64}$', caseSensitive: false).hasMatch(previousHash)) {
            print('❌ [CRYPTO VALIDATION FAILED] Invalid previous_hash format: length=${previousHash.length}');
            print('   Expected: "0" for genesis OR 64-char hex for chain');
            return null;
          }
        }
        
        // Validation 5: current_hash must be valid 64-char hex
        if (currentHash.isEmpty) {
          print('❌ [CRYPTO VALIDATION FAILED] current_hash is empty - BLOCKING INSERT');
          return null;
        }
        if (currentHash.length != 64 || !RegExp(r'^[a-f0-9]{64}$', caseSensitive: false).hasMatch(currentHash)) {
          print('❌ [CRYPTO VALIDATION FAILED] Invalid current_hash format: length=${currentHash.length}');
          print('   Expected: 64-char hex string');
          return null;
        }
        
        print('✅ [CRYPTO VALIDATION PASSED] All v2 fields valid');
        print('   Genesis: ${previousHash == "0"}');
        print('   Payload hash: ${safeSubstring(payloadHash, 16)}...');
        print('   Previous hash: ${safeSubstring(previousHash, 16)}...');
        print('   Current hash: ${safeSubstring(currentHash, 16)}...');
      }
      
      // Use conflictAlgorithm to handle race conditions gracefully
      // If message_id already exists (race condition), ignore the insert
      await db.insert(
        'messages',
        messageData,
        conflictAlgorithm: ConflictAlgorithm.ignore, // Ignore if duplicate (race condition)
      );

      // CRITICAL: Verify message was inserted with all required fields
      // This ensures crypto operations completed successfully
      final verifyInsert = await db.query(
        'messages',
        columns: ['message_id', 'payload_hash', 'encrypted_message', 'iv', 'previous_hash', 'current_hash', 'hash_version'],
        where: 'message_id = ?',
        whereArgs: [messageId],
        limit: 1,
      );
      
      if (verifyInsert.isEmpty) {
        print('❌ [CRYPTO VALIDATION] Message insert failed - message not found after insert');
        return null;
      }
      
      final inserted = verifyInsert.first;
      if (hashVersion == 2) {
        final insertedPayloadHash = inserted['payload_hash'] as String? ?? '';
        final insertedEncrypted = inserted['encrypted_message'] as String? ?? '';
        final insertedIv = inserted['iv'] as String? ?? '';
        final insertedCurrentHash = inserted['current_hash'] as String? ?? '';
        
        if (insertedPayloadHash.isEmpty || insertedEncrypted.isEmpty || 
            insertedIv.isEmpty || insertedCurrentHash.isEmpty) {
          print('❌ [CRYPTO VALIDATION] Message inserted but required fields are missing');
          print('   payload_hash: ${insertedPayloadHash.isNotEmpty}');
          print('   encrypted_message: ${insertedEncrypted.isNotEmpty}');
          print('   iv: ${insertedIv.isNotEmpty}');
          print('   current_hash: ${insertedCurrentHash.isNotEmpty}');
          return null;
        }
      }
      
      print('✅ Message added to SQLite: $messageId');
      print('   ✅ All crypto operations completed successfully');
      print('   ✅ Payload hash: ${safeSubstring(payloadHash, 16)}...');
      print('   ✅ Previous hash: ${safeSubstring(previousHash, 16)}... (${previousHash == '0' ? 'GENESIS' : 'CHAIN'})');
      print('   ✅ Current hash: ${safeSubstring(currentHash, 16)}...');
      print('   ✅ Encrypted: ${encryptedMessage != null && iv != null}');
      return messageId;
    } catch (e) {
      print('❌ Add message error: $e');
      return null;
    }
  }

  /// Get channel messages with chain integrity verification
  /// Returns messages with chain integrity status flag
  /// [sinceTimestamp] - Optional: Only fetch messages after this timestamp (for incremental loading)
  Future<Map<String, dynamic>> getChannelMessages({
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

      // CRITICAL: Verify chain integrity before returning messages
      // This detects: previous_hash mismatch, missing parent, fork, hash mismatch
      final chainVerification = await verifyChannelChainIntegrity(
        workspaceId: workspaceId,
        channelId: channelId,
      );

      // SECURITY: Decrypt messages before sending to UI
      // Transform messages to UI format with decryption
      final transformedMessages = <Map<String, dynamic>>[];
      
      for (final m in messages) {
        String? messageText;
        
        // Check if message is encrypted (has encrypted_message and iv)
        final encryptedMessage = m['encrypted_message'] as String?;
        final iv = m['iv'] as String?;
        
        if (encryptedMessage != null && encryptedMessage.isNotEmpty && 
            iv != null && iv.isNotEmpty) {
          // Encrypted message: decrypt before sending to UI
          try {
            messageText = await AESCryptoService.decrypt(
              cipherText: encryptedMessage,
              iv: iv,
            );
            print('🔓 Message decrypted successfully (message_id: ${m['message_id']})');
          } catch (e) {
            print('❌ Decryption error for message ${m['message_id']}: $e');
            // If decryption fails, use fallback (empty string or legacy message_text)
            // This ensures UI doesn't break if decryption fails
            messageText = m['message_text'] as String? ?? '';
            print('⚠️ Using fallback message_text for failed decryption');
          }
        } else {
          // Legacy message: use plaintext message_text (backward compatibility)
          messageText = m['message_text'] as String? ?? '';
        }
        
        // Build transformed message with decrypted text
        transformedMessages.add({
        'message_id': m['message_id'],
          'messageText': messageText,
          'message_text': messageText,
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
          'content': messageText, // Add content field for UI compatibility (decrypted)
        'message_state': m['message_state'], // PHASE 4: Include message state for UI indicators
        });
      }

      // Return messages with chain integrity status
      return {
        'messages': transformedMessages,
        'chainIntegrity': chainVerification.isValid,
        'chainIntegrityFailed': chainVerification.isChainIntegrityFailed,
        'chainFailureReason': chainVerification.failureReason,
        'chainBrokenAt': chainVerification.brokenAt,
        'chainFailureDetails': chainVerification.details,
      };
    } catch (e) {
      print('❌ Get channel messages error: $e');
      // Return empty messages with chain integrity failure flag
      return {
        'messages': <Map<String, dynamic>>[],
        'chainIntegrity': false,
        'chainIntegrityFailed': true,
        'chainFailureReason': 'query_error',
        'chainBrokenAt': 'unknown',
        'chainFailureDetails': {'error': e.toString()},
      };
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

  /// Get unsynced messages (messages with state PENDING_SYNC or OFFLINE_LOCAL)
  /// Used for marking OFFLINE_LOCAL as PENDING_SYNC before sync
  Future<List<Map<String, dynamic>>> getUnsyncedMessages() async {
    try {
      final db = await database;
      // CRITICAL: Only get messages that need syncing (PENDING_SYNC or OFFLINE_LOCAL)
      // Exclude messages already synced (SYNCED, ONLINE_CONFIRMED)
      return await db.query(
        'messages',
        where: 'message_state IN (?, ?) OR (synced_to_server = ? AND message_state IS NULL)',
        whereArgs: ['PENDING_SYNC', 'OFFLINE_LOCAL', 0],
        orderBy: 'timestamp ASC',
      );
    } catch (e) {
      print('❌ Get unsynced messages error: $e');
      return [];
    }
  }
  
  /// Get messages by state (PHASE 3: Fetch messages WHERE state = PENDING_SYNC)
  Future<List<Map<String, dynamic>>> getMessagesByState(String state) async {
    try {
      final db = await database;
      return await db.query(
        'messages',
        where: 'message_state = ?',
        whereArgs: [state],
        orderBy: 'timestamp ASC',
      );
    } catch (e) {
      print('❌ Get messages by state error: $e');
      return [];
    }
  }

  /// Get unsynced channels (created offline, not yet synced to server)
  Future<List<Map<String, dynamic>>> getUnsyncedChannels() async {
    try {
      final db = await database;
      return await db.query(
        'channels',
        where: 'synced_to_server = ? AND deleted = 0',
        whereArgs: [0],
        orderBy: 'timestamp ASC',
      );
    } catch (e) {
      print('❌ Get unsynced channels error: $e');
      return [];
    }
  }

  /// Mark channel as synced to server
  Future<bool> markChannelSynced({
    required String workspaceId,
    required String channelId,
  }) async {
    try {
      final db = await database;
      final normalizedChannelId = channelId.toLowerCase().trim();
      
      await db.update(
        'channels',
        {'synced_to_server': 1},
        where: 'workspace_id = ? AND channel_id = ?',
        whereArgs: [workspaceId, normalizedChannelId],
      );
      
      print('✅ Channel marked as synced: $channelId in workspace $workspaceId');
      return true;
    } catch (e) {
      print('❌ Mark channel synced error: $e');
      return false;
    }
  }

  /// Mark message as synced
  Future<bool> markMessageSynced(String messageId) async {
    try {
      final db = await database;
      await db.update(
        'messages',
        {
          'synced_to_server': 1,
          'message_state': 'SYNCED', // CRITICAL: Update state to SYNCED
        },
        where: 'message_id = ?',
        whereArgs: [messageId],
      );
      return true;
    } catch (e) {
      print('❌ Mark message synced error: $e');
      return false;
    }
  }
  
  /// Update message state
  Future<bool> updateMessageState({
    required String messageId,
    required String state, // ONLINE_CONFIRMED, OFFLINE_LOCAL, PENDING_SYNC, SYNCED
  }) async {
    try {
      final db = await database;
      final rowsAffected = await db.update(
        'messages',
        {
          'message_state': state,
          'synced_to_server': (state == 'SYNCED' || state == 'ONLINE_CONFIRMED') ? 1 : 0,
        },
        where: 'message_id = ?',
        whereArgs: [messageId],
      );
      
      if (rowsAffected > 0) {
        print('✅ Updated message state: $messageId -> $state');
        return true;
      }
      
      return false;
    } catch (e) {
      print('❌ Update message state error: $e');
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

  /// Update message hash (for chain integrity after sync)
  /// This updates the hash of a message after it's synced to server
  /// to match the server's calculated hash
  Future<bool> updateMessageHash({
    required String messageId,
    required String previousHash,
    required String currentHash,
  }) async {
    try {
      final db = await database;
      final rowsAffected = await db.update(
        'messages',
        {
          'previous_hash': previousHash,
          'current_hash': currentHash,
        },
        where: 'message_id = ?',
        whereArgs: [messageId],
      );
      
      if (rowsAffected > 0) {
        print('✅ Updated message hash: $messageId');
        return true;
      }
      
      return false;
    } catch (e) {
      print('❌ Update message hash error: $e');
      return false;
    }
  }

  // ============ CHAIN VERIFICATION ============

  /// Verify chain integrity with detailed error reporting
  /// Returns ChainVerificationResult instead of throwing exceptions
  /// Detects: previous_hash mismatch, missing parent, fork (multiple messages with same previous_hash), hash mismatch
  Future<ChainVerificationResult> verifyChainIntegrity(String tableName) async {
    try {
      final db = await database;
      final records = await db.query(
        tableName,
        orderBy: 'timestamp ASC',
      );

      if (records.isEmpty) {
        return ChainVerificationResult.success();
      }

      // Build hash map for parent lookup (current_hash -> message_id)
      final hashToMessageId = <String, String>{};
      final previousHashCounts = <String, int>{};
      
      for (final record in records) {
        final messageId = record['message_id'] as String? ?? 
                         record['workspace_id'] as String? ?? 
                         'unknown';
        final currentHash = record['current_hash'] as String?;
        final previousHash = record['previous_hash'] as String?;
        
        // Track current_hash -> message_id mapping (for parent lookup)
        if (currentHash != null && currentHash.isNotEmpty) {
          // Check for duplicate current_hash (shouldn't happen, but detect it)
          if (hashToMessageId.containsKey(currentHash)) {
            final existingMessageId = hashToMessageId[currentHash];
            return ChainVerificationResult.failure(
              reason: 'duplicate_current_hash',
              brokenAt: messageId,
              details: {
                'message_id': messageId,
                'duplicate_hash': currentHash,
                'existing_message_id': existingMessageId,
                'message': 'Multiple messages have the same current_hash - chain integrity compromised',
              },
            );
          }
          hashToMessageId[currentHash] = messageId;
        }
        
        // Track previous_hash counts (for fork detection)
        if (previousHash != null && previousHash.isNotEmpty) {
          previousHashCounts[previousHash] = (previousHashCounts[previousHash] ?? 0) + 1;
        }
      }

      // Check for forks: multiple messages pointing to same previous_hash
      for (final entry in previousHashCounts.entries) {
        if (entry.value > 1 && entry.key != '0') {
          // Find all messages with this previous_hash
          final forkMessages = records.where((r) => 
            (r['previous_hash'] as String?) == entry.key
          ).map((r) => (r['message_id'] as String?) ?? (r['workspace_id'] as String?) ?? 'unknown').toList();
          
          return ChainVerificationResult.failure(
            reason: 'fork_detected',
            brokenAt: forkMessages.isNotEmpty ? forkMessages.first : 'unknown',
            details: {
              'previous_hash': entry.key,
              'fork_count': entry.value,
              'fork_message_ids': forkMessages,
              'message': 'Multiple messages point to the same previous_hash - chain fork detected',
            },
          );
        }
      }

      // Verify chain links: previous_hash -> current_hash
      String expectedPreviousHash = '0';
      for (int i = 0; i < records.length; i++) {
        final record = records[i];
        final messageId = record['message_id'] as String? ?? 
                         record['workspace_id'] as String? ?? 
                         'unknown';
        final currentHash = record['current_hash'] as String?;
        final recordPreviousHash = record['previous_hash'] as String?;

        // CRITICAL VALIDATION: previous_hash must NEVER be null or empty
        // - Genesis: previous_hash = "0" (exactly)
        // - Chain: previous_hash = 64-char hex
        if (recordPreviousHash == null || recordPreviousHash.isEmpty) {
          return ChainVerificationResult.failure(
            reason: 'invalid_previous_hash',
            brokenAt: messageId,
            details: {
              'message_id': messageId,
              'index': i + 1,
              'error': 'previous_hash is null or empty (must be "0" for genesis or 64-char hex for chain)',
              'expected_previous_hash': expectedPreviousHash,
            },
          );
        }

        // Check 1: Verify previous hash matches expected
        if (recordPreviousHash != expectedPreviousHash) {
          return ChainVerificationResult.failure(
            reason: 'previous_hash_mismatch',
            brokenAt: messageId,
            details: {
              'message_id': messageId,
              'index': i + 1,
              'expected_previous_hash': expectedPreviousHash,
              'found_previous_hash': recordPreviousHash,
              'message': 'Previous hash does not match expected chain state',
            },
          );
        }

        // Check 2: Verify parent message exists (unless this is genesis with previous_hash='0')
        if (expectedPreviousHash != '0' && !hashToMessageId.containsKey(expectedPreviousHash)) {
          return ChainVerificationResult.failure(
            reason: 'missing_parent',
            brokenAt: messageId,
            details: {
              'message_id': messageId,
              'index': i + 1,
              'missing_previous_hash': expectedPreviousHash,
              'message': 'Parent message with current_hash matching previous_hash not found',
            },
          );
        }

        // Check 3: Verify current hash calculation
        if (currentHash != null && currentHash.isNotEmpty) {
          final hashVersion = record['hash_version'] as int? ?? 2;
          
          // CRITICAL: Reconstruct hash using ONLY the fields used during insert
          // DO NOT include: encrypted_message, iv, synced_to_server, message_state, file_id, channel_id
          // For hash_version 2: Use stored payload_hash (calculated from plaintext at insert time)
          // For hash_version 1: Use message_text (legacy)
          final storedPayloadHash = record['payload_hash'] as String?;
          final storedMessageText = record['message_text'] as String?;
          
          // Build dataForHash with EXACT same structure as insert (line 923-931)
          // CRITICAL: Must match insert structure exactly for hash consistency
          final dataForHash = {
            'message_id': record['message_id'],
            'workspace_id': record['workspace_id'],
            'sender_address': record['sender_address'],
            'receiver_address': record['receiver_address'],
            'timestamp': record['timestamp'],
            'previous_hash': expectedPreviousHash, // Use expectedPreviousHash (chain state)
          };
          
          // Add payload_hash or message_text based on hash version
          // CRITICAL: payload_hash is derived from plaintext ONLY (encryption-independent)
          if (hashVersion == 2) {
            // Version 2: Use stored payload_hash (calculated from plaintext before encryption)
            if (storedPayloadHash == null || storedPayloadHash.isEmpty) {
              // Fallback: try to calculate from message_text if available (legacy migration)
              if (storedMessageText != null && storedMessageText.isNotEmpty) {
                final fallbackPayloadHash = _calculatePayloadHash(storedMessageText);
                dataForHash['payload_hash'] = fallbackPayloadHash;
              } else {
                // Cannot verify without payload_hash
                return ChainVerificationResult.failure(
                  reason: 'hash_mismatch',
                  brokenAt: messageId,
                  details: {
                    'message_id': messageId,
                    'index': i + 1,
                    'error': 'hash_version 2 requires payload_hash but it is missing',
                    'hash_version': hashVersion,
                  },
                );
              }
            } else {
              // Use stored payload_hash (this is what was used during insert)
              dataForHash['payload_hash'] = storedPayloadHash;
            }
          } else {
            // Version 1: Use message_text (legacy plaintext hashing)
            dataForHash['message_text'] = storedMessageText ?? '';
          }
          
          final calculatedHash = _calculateHash(dataForHash, hashVersion: hashVersion);

          if (currentHash != calculatedHash) {
            return ChainVerificationResult.failure(
              reason: 'hash_mismatch',
              brokenAt: messageId,
              details: {
                'message_id': messageId,
                'index': i + 1,
                'expected_current_hash': calculatedHash,
                'found_current_hash': currentHash,
                'hash_version': hashVersion,
                'payload_hash_used': hashVersion == 2 ? storedPayloadHash : null,
                'message_text_used': hashVersion == 1 ? storedMessageText : null,
                'message': 'Current hash does not match calculated hash - data may have been modified',
              },
            );
          }
        }

        // Update expected previous hash for next iteration
        if (currentHash != null && currentHash.isNotEmpty) {
          expectedPreviousHash = currentHash;
        } else {
          // If current_hash is null/empty, chain is broken
          return ChainVerificationResult.failure(
            reason: 'missing_current_hash',
            brokenAt: messageId,
            details: {
              'message_id': messageId,
              'index': i + 1,
              'message': 'Message missing current_hash - chain integrity compromised',
            },
          );
        }
      }

      print('✅ Chain integrity verified for $tableName');
      return ChainVerificationResult.success();
    } catch (e) {
      print('❌ Verify chain integrity error: $e');
      // Return failure result instead of throwing
      return ChainVerificationResult.failure(
        reason: 'verification_error',
        brokenAt: 'unknown',
        details: {
          'error': e.toString(),
          'message': 'Chain verification failed due to exception',
        },
      );
    }
  }

  /// Verify chain integrity for channel messages
  /// Returns ChainVerificationResult with detailed failure information
  Future<ChainVerificationResult> verifyChannelChainIntegrity({
    required String workspaceId,
    required String channelId,
  }) async {
    try {
      final db = await database;
      final messages = await db.query(
        'messages',
        where: 'workspace_id = ? AND channel_id = ?',
        whereArgs: [workspaceId, channelId],
        orderBy: 'timestamp ASC',
      );

      if (messages.isEmpty) {
        return ChainVerificationResult.success();
      }

      // Build hash map for parent lookup
      final hashToMessageId = <String, String>{};
      final previousHashCounts = <String, int>{};
      
      for (final msg in messages) {
        final messageId = msg['message_id'] as String? ?? 'unknown';
        final currentHash = msg['current_hash'] as String?;
        final previousHash = msg['previous_hash'] as String?;
        
        if (currentHash != null && currentHash.isNotEmpty) {
          if (hashToMessageId.containsKey(currentHash)) {
            final existingMessageId = hashToMessageId[currentHash];
            return ChainVerificationResult.failure(
              reason: 'duplicate_current_hash',
              brokenAt: messageId,
              details: {
                'workspace_id': workspaceId,
                'channel_id': channelId,
                'message_id': messageId,
                'duplicate_hash': currentHash,
                'existing_message_id': existingMessageId,
              },
            );
          }
          hashToMessageId[currentHash] = messageId;
        }
        
        if (previousHash != null && previousHash.isNotEmpty) {
          previousHashCounts[previousHash] = (previousHashCounts[previousHash] ?? 0) + 1;
        }
      }

      // Check for forks
      for (final entry in previousHashCounts.entries) {
        if (entry.value > 1 && entry.key != '0') {
          final forkMessages = messages.where((m) => 
            (m['previous_hash'] as String?) == entry.key
          ).map((m) => m['message_id'] as String? ?? 'unknown').toList();
          
          return ChainVerificationResult.failure(
            reason: 'fork_detected',
            brokenAt: forkMessages.isNotEmpty ? forkMessages.first : 'unknown',
            details: {
              'workspace_id': workspaceId,
              'channel_id': channelId,
              'previous_hash': entry.key,
              'fork_count': entry.value,
              'fork_message_ids': forkMessages,
            },
          );
        }
      }

      // Verify chain links
      String expectedPreviousHash = '0';
      for (int i = 0; i < messages.length; i++) {
        final msg = messages[i];
        final messageId = msg['message_id'] as String? ?? 'unknown';
        final currentHash = msg['current_hash'] as String?;
        final recordPreviousHash = msg['previous_hash'] as String?;

        // CRITICAL VALIDATION: previous_hash must NEVER be null or empty
        // - Genesis: previous_hash = "0" (exactly)
        // - Chain: previous_hash = 64-char hex
        if (recordPreviousHash == null || recordPreviousHash.isEmpty) {
          return ChainVerificationResult.failure(
            reason: 'invalid_previous_hash',
            brokenAt: messageId,
            details: {
              'workspace_id': workspaceId,
              'channel_id': channelId,
              'message_id': messageId,
              'index': i + 1,
              'error': 'previous_hash is null or empty (must be "0" for genesis or 64-char hex for chain)',
              'expected_previous_hash': expectedPreviousHash,
            },
          );
        }

        if (recordPreviousHash != expectedPreviousHash) {
          return ChainVerificationResult.failure(
            reason: 'previous_hash_mismatch',
            brokenAt: messageId,
            details: {
              'workspace_id': workspaceId,
              'channel_id': channelId,
              'message_id': messageId,
              'index': i + 1,
              'expected_previous_hash': expectedPreviousHash,
              'found_previous_hash': recordPreviousHash,
            },
          );
        }

        if (expectedPreviousHash != '0' && !hashToMessageId.containsKey(expectedPreviousHash)) {
          return ChainVerificationResult.failure(
            reason: 'missing_parent',
            brokenAt: messageId,
            details: {
              'workspace_id': workspaceId,
              'channel_id': channelId,
              'message_id': messageId,
              'index': i + 1,
              'missing_previous_hash': expectedPreviousHash,
            },
          );
        }

        if (currentHash != null && currentHash.isNotEmpty) {
          final hashVersion = msg['hash_version'] as int? ?? 2;
          
          // CRITICAL: Reconstruct hash using ONLY the fields used during insert
          // This ensures verification matches the original hash calculation
          // DO NOT include: encrypted_message, iv, synced_to_server, message_state, file_id, channel_id
          // For hash_version 2: Use stored payload_hash (calculated from plaintext at insert time)
          // For hash_version 1: Use message_text (legacy)
          final storedPayloadHash = msg['payload_hash'] as String?;
          final storedMessageText = msg['message_text'] as String?;
          
          // Build dataForHash with EXACT same structure as insert (line 901-910)
          final dataForHash = {
            'message_id': msg['message_id'],
            'workspace_id': msg['workspace_id'],
            'sender_address': msg['sender_address'],
            'receiver_address': msg['receiver_address'],
            'timestamp': msg['timestamp'],
            'previous_hash': expectedPreviousHash,
          };
          
          // Add payload_hash or message_text based on hash version
          // CRITICAL: payload_hash is derived from plaintext ONLY (encryption-independent)
          // payload_hash was calculated BEFORE encryption during insert, so we use stored value
          if (hashVersion == 2) {
            // Version 2: Use stored payload_hash (calculated from plaintext before encryption)
            if (storedPayloadHash == null || storedPayloadHash.isEmpty) {
              // This should never happen, but log it for debugging
              print('⚠️ WARNING: hash_version 2 but payload_hash is missing for message $messageId');
              // Fallback: try to calculate from message_text if available (legacy migration)
              if (storedMessageText != null && storedMessageText.isNotEmpty) {
                final fallbackPayloadHash = _calculatePayloadHash(storedMessageText);
                dataForHash['payload_hash'] = fallbackPayloadHash;
                print('   Used fallback: calculated payload_hash from message_text');
              } else {
                // Cannot verify without payload_hash - treat as integrity failure
                return ChainVerificationResult.failure(
                  reason: 'hash_mismatch',
                  brokenAt: messageId,
                  details: {
                    'workspace_id': workspaceId,
                    'channel_id': channelId,
                    'message_id': messageId,
                    'index': i + 1,
                    'error': 'hash_version 2 requires payload_hash but it is missing',
                    'hash_version': hashVersion,
                  },
                );
              }
            } else {
              // Use stored payload_hash (this is what was used during insert)
              dataForHash['payload_hash'] = storedPayloadHash;
            }
          } else {
            // Version 1: Use message_text (legacy plaintext hashing)
            dataForHash['message_text'] = storedMessageText ?? '';
          }
          
          // REGRESSION LOG: Log hash calculation inputs for debugging
          print('🔍 VERIFY: Recalculating hash for message $messageId (v$hashVersion)');
          if (hashVersion == 2) {
            print('   Using stored payload_hash: ${safeSubstring(storedPayloadHash, 16)}...');
          } else {
            final msgText = storedMessageText ?? '';
            final previewLength = msgText.length < 20 ? msgText.length : 20;
            print('   Using message_text: ${msgText.substring(0, previewLength)}...');
          }
          print('   previous_hash: ${safeSubstring(expectedPreviousHash, 16)}...');
          
          final calculatedHash = _calculateHash(dataForHash, hashVersion: hashVersion);
          
          print('   Calculated hash: ${safeSubstring(calculatedHash, 16)}...');
          print('   Stored hash: ${safeSubstring(currentHash, 16)}...');
          print('   Match: ${calculatedHash == currentHash ? '✅' : '❌'}');

          if (currentHash != calculatedHash) {
            return ChainVerificationResult.failure(
              reason: 'hash_mismatch',
              brokenAt: messageId,
              details: {
                'workspace_id': workspaceId,
                'channel_id': channelId,
                'message_id': messageId,
                'index': i + 1,
                'expected_current_hash': calculatedHash,
                'found_current_hash': currentHash,
                'hash_version': hashVersion,
                'payload_hash_used': hashVersion == 2 ? storedPayloadHash : null,
                'message_text_used': hashVersion == 1 ? storedMessageText : null,
              },
            );
          }
          
          expectedPreviousHash = currentHash;
        } else {
          return ChainVerificationResult.failure(
            reason: 'missing_current_hash',
            brokenAt: messageId,
            details: {
              'workspace_id': workspaceId,
              'channel_id': channelId,
              'message_id': messageId,
              'index': i + 1,
            },
          );
        }
      }

      return ChainVerificationResult.success();
    } catch (e) {
      print('❌ Verify channel chain integrity error: $e');
      return ChainVerificationResult.failure(
        reason: 'verification_error',
        brokenAt: 'unknown',
        details: {
          'workspace_id': workspaceId,
          'channel_id': channelId,
          'error': e.toString(),
        },
      );
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
          final capitalized = displayName.isNotEmpty 
              ? (safeSubstring(displayName, 1).toUpperCase() + (displayName.length > 1 ? displayName.substring(1) : ''))
              : displayName;
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
          final capitalized = channelId.isNotEmpty
              ? (safeSubstring(channelId, 1).toUpperCase() + (channelId.length > 1 ? channelId.substring(1) : ''))
              : channelId;
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
        // CRITICAL: Normalize channel_id for comparison (spaces -> hyphens)
        final normalizedChannelIdForQuery = normalizedChannelId.replaceAll(RegExp(r'\s+'), '-');
        final existingChannel = await db.query(
          'channels',
          where: 'workspace_id = ? AND channel_id = ?',
          whereArgs: [workspaceId, normalizedChannelIdForQuery],
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
      
      // CRITICAL: Use normalized channel_id for database storage (consistent with backend)
      // Backend stores channel_id with spaces replaced by hyphens
      // This ensures consistency across all devices
      final normalizedChannelIdForStorage = normalizedChannelId.replaceAll(RegExp(r'\s+'), '-');
      
      // Prepare channel data (MongoDB-aligned)
      final channelData = {
        'channel_id': normalizedChannelIdForStorage, // Use normalized ID for storage
        'workspace_id': workspaceId,
        'channel_name': channelName ?? normalizedChannelIdForStorage, // Use display name or normalized ID
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
        print('✅ Channel saved to SQLite: $channelName (ID: $normalizedChannelIdForStorage, deleted: $shouldMarkDeleted)');
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
                'channel_id': normalizedChannelIdForStorage, // Use normalized ID
                'workspace_id': workspaceId,
                'channel_name': channelName ?? normalizedChannelIdForStorage,
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
      final normalizedChannelId = channelId.toLowerCase().trim().replaceAll(RegExp(r'\s+'), '-');
      
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

  // ============ CHAIN STATE OPERATIONS ============
  /// Save last server hash for a channel (for chain continuity when server goes offline)
  /// This ensures SQLite messages can properly link to server's chain when syncing
  Future<bool> saveChainState({
    required String workspaceId,
    required String channelId,
    required String lastServerHash,
    String? lastServerMessageId,
    int? lastServerTimestamp,
  }) async {
    try {
      final db = await database;
      final now = DateTime.now().millisecondsSinceEpoch;
      
      await db.insert(
        'chain_state',
        {
          'workspace_id': workspaceId,
          'channel_id': channelId,
          'last_server_hash': lastServerHash,
          'last_server_message_id': lastServerMessageId,
          'last_server_timestamp': lastServerTimestamp ?? now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      print('✅ Chain state saved: workspace=$workspaceId, channel=$channelId, hash=${safeSubstring(lastServerHash, 10)}...');
      return true;
    } catch (e) {
      print('❌ Save chain state error: $e');
      return false;
    }
  }

  /// Get last server hash for a channel (returns null if not found)
  Future<String?> getLastServerHash({
    required String workspaceId,
    required String channelId,
  }) async {
    try {
      final db = await database;
      final result = await db.query(
        'chain_state',
        columns: ['last_server_hash'],
        where: 'workspace_id = ? AND channel_id = ?',
        whereArgs: [workspaceId, channelId],
        limit: 1,
      );
      
      if (result.isNotEmpty) {
        final hash = result.first['last_server_hash'] as String?;
        print('✅ Retrieved chain state: workspace=$workspaceId, channel=$channelId, hash=${safeSubstring(hash, 10)}...');
        return hash;
      }
      
      return null;
    } catch (e) {
      print('❌ Get last server hash error: $e');
      return null;
    }
  }

  /// Get full chain state for a channel
  Future<Map<String, dynamic>?> getChainState({
    required String workspaceId,
    required String channelId,
  }) async {
    try {
      final db = await database;
      final result = await db.query(
        'chain_state',
        where: 'workspace_id = ? AND channel_id = ?',
        whereArgs: [workspaceId, channelId],
        limit: 1,
      );
      
      if (result.isNotEmpty) {
        return {
          'last_server_hash': result.first['last_server_hash'],
          'last_server_message_id': result.first['last_server_message_id'],
          'last_server_timestamp': result.first['last_server_timestamp'],
          'updated_at': result.first['updated_at'],
        };
      }
      
      return null;
    } catch (e) {
      print('❌ Get chain state error: $e');
      return null;
    }
  }

  /// Clear chain state for a channel (after successful sync)
  Future<bool> clearChainState({
    required String workspaceId,
    required String channelId,
  }) async {
    try {
      final db = await database;
      final rowsAffected = await db.delete(
        'chain_state',
        where: 'workspace_id = ? AND channel_id = ?',
        whereArgs: [workspaceId, channelId],
      );
      
      if (rowsAffected > 0) {
        print('✅ Chain state cleared: workspace=$workspaceId, channel=$channelId');
        return true;
      }
      
      return false;
    } catch (e) {
      print('❌ Clear chain state error: $e');
      return false;
    }
  }

  // ============ HELPER METHODS ============

  /// Generate unique ID
  String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString() +
        DateTime.now().microsecondsSinceEpoch.toString();
  }

  /// Calculate SHA-256 hash with hash version support
  /// Version 1: Uses message_text in hash calculation (legacy)
  /// Version 2: Uses payload_hash in hash calculation (new)
  /// 
  /// CRITICAL SECURITY RULE:
  /// - payload_hash MUST be derived from plaintext ONLY (encryption-independent)
  /// - payload_hash is calculated BEFORE encryption during insert
  /// - payload_hash MUST NEVER be derived from encrypted_message or iv
  /// - This function uses the stored payload_hash value (already calculated from plaintext)
  /// 
  /// CRITICAL CONSISTENCY RULE:
  /// - Keys are sorted before JSON encoding to ensure consistent hash calculation
  /// - This prevents hash mismatches due to JSON key ordering differences
  String _calculateHash(Map<String, dynamic> data, {int hashVersion = 1}) {
    // Create a copy of data for modification
    final dataToHash = Map<String, dynamic>.from(data);
    
    // For hash version 2, replace message_text with payload_hash
    if (hashVersion == 2) {
      final payloadHash = dataToHash['payload_hash'] as String?;
      if (payloadHash != null && payloadHash.isNotEmpty) {
        // Remove message_text and use payload_hash instead
        // payload_hash is already in the map (calculated from plaintext at insert time)
        dataToHash.remove('message_text');
        // NOTE: payload_hash is encryption-independent (calculated before encryption)
      } else {
        // Fallback: if payload_hash not available (legacy migration), calculate it from message_text
        // This should only happen for legacy messages being migrated
        final messageText = dataToHash['message_text'] as String? ?? '';
        if (messageText.isNotEmpty) {
          // CRITICAL: Calculate payload_hash from plaintext (if message_text is still available)
          final calculatedPayloadHash = _calculatePayloadHash(messageText);
          dataToHash.remove('message_text');
          dataToHash['payload_hash'] = calculatedPayloadHash;
        }
      }
    }
    // For hash version 1, keep message_text (default behavior)
    
    // CRITICAL: Sort keys before JSON encoding to ensure consistent hash calculation
    // JSON key order is not guaranteed in Dart, so we must sort to prevent hash mismatches
    final sortedKeys = dataToHash.keys.toList()..sort();
    final sortedData = <String, dynamic>{};
    for (final key in sortedKeys) {
      sortedData[key] = dataToHash[key];
    }
    
    final jsonString = jsonEncode(sortedData);
    final bytes = utf8.encode(jsonString);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Calculate payload hash (SHA-256 of message_text)
  /// Used for payload-based hashing transition
  /// Returns stable hash that remains constant across sync operations
  /// 
  /// CRITICAL SECURITY RULE:
  /// - payload_hash MUST be calculated from PLAINTEXT messageText ONLY
  /// - payload_hash MUST be calculated BEFORE encryption
  /// - payload_hash MUST NEVER be derived from encrypted_message or iv
  /// - Encryption randomness (AES-CBC IV) must NOT affect hash chain
  /// - This ensures hash chain integrity is independent of encryption
  String _calculatePayloadHash(String messageText) {
    final bytes = utf8.encode(messageText);
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

