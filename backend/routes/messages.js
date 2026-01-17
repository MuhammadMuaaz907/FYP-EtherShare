const express = require('express');
const router = express.Router();
const crypto = require('crypto');
const { getCollection } = require('../utils/db');
const { validateMessage } = require('../middleware/validation');
const { optionalAuth } = require('../middleware/auth');
const HashChain = require('../utils/hashChain');
const GasCalculator = require('../utils/gasCalculator');

/**
 * Calculate payload hash (SHA-256 of message_text)
 * Used for payload-based hashing transition
 * Returns stable hash that remains constant across sync operations
 * @param {String} messageText - The message text to hash
 * @returns {String} SHA-256 hash hex string
 */
function calculatePayloadHash(messageText) {
  return crypto.createHash('sha256').update(messageText, 'utf8').digest('hex');
}

/**
 * @route   POST /api/messages
 * @desc    Add message with hash chain
 * @access  Public (add auth later)
 */
router.post('/', validateMessage, async (req, res) => {
  const startTime = process.hrtime.bigint(); // Start timing
  
  try {
    const messagesCollection = getCollection('messages');
    const {
      workspaceId,
      channelId,
      senderAddress,
      receiverAddress,
      messageText, // DEPRECATED: Plaintext message_text (only for backward compatibility)
      encryptedMessage, // NEW: AES-256-CBC encrypted message (base64)
      iv, // NEW: Initialization vector for encryption (base64)
      fileId,
      messageId: providedMessageId, // CRITICAL: Accept message_id from client for idempotency
      previousHash: providedPreviousHash, // CRITICAL: Accept previous_hash from client for sync
      currentHash: providedCurrentHash, // CRITICAL: Accept current_hash from client for sync
      payloadHash: providedPayloadHash, // CRITICAL: Accept payload_hash from client (calculated from plaintext on client)
    } = req.body;
    
    // CRITICAL: Flag for offline sync (allows hash re-anchoring)
    const isOfflineSync = req.body.isOfflineSync === true;
    
    const timestamp = Date.now();
    
    // CRITICAL: Use provided messageId if available (for idempotent sync), otherwise generate new one
    let messageId = providedMessageId;
    let isIdempotentSync = false;
    
    if (messageId && messageId.trim().length > 0) {
      // CRITICAL: Check if message with this ID already exists (idempotency check)
      const existingMessage = await messagesCollection.findOne({
        message_id: messageId
      });
      
      if (existingMessage) {
        // Message already exists - return existing message (idempotent)
        console.log(`✅ Message with ID ${messageId} already exists - returning existing message (idempotent)`);
        isIdempotentSync = true;
        
        // Calculate execution time and gas
        const endTime = process.hrtime.bigint();
        const executionTimeMs = Number(endTime - startTime) / 1000000;
        const gasUsed = GasCalculator.calculateMessageGas(executionTimeMs, existingMessage);
        const gasPrice = GasCalculator.getCurrentGasPrice();
        const transactionFee = GasCalculator.calculateTransactionFee(gasUsed, gasPrice);
        
        // Clean up response (remove internal hash fields)
        const { _id, previous_hash, current_hash, chain_broken, chain_broken_at, createdAt, updatedAt, __v, ...cleanMessage } = existingMessage;
        
        return res.status(200).json({
          success: true,
          message: 'Message already exists (idempotent)',
          data: {
            ...cleanMessage,
            gas_used: gasUsed,
            gas_price: gasPrice,
            transaction_fee: transactionFee,
            transaction_time_ms: Math.round(executionTimeMs * 100) / 100,
            idempotent: true, // Indicate this was an idempotent response
          }
        });
      }
      
      // Message ID provided but doesn't exist - use it (for sync)
      isIdempotentSync = true;
      console.log(`🔄 Using provided messageId for sync: ${messageId}`);
    } else {
      // No message ID provided - generate new one (normal flow)
      messageId = `msg_${timestamp}_${senderAddress.toLowerCase()}`;
    }
    
    // ========================================================================
    // SECURITY ENFORCEMENT: PLAINTEXT MESSAGE DEPRECATION
    // ========================================================================
    // PHASED SECURITY MIGRATION POLICY:
    // - Phase 1 (COMPLETE): Introduced encrypted_message + iv support
    // - Phase 2 (CURRENT): ENFORCE encryption - reject all plaintext for new messages
    // - Phase 3 (FUTURE): Migrate/archive legacy plaintext messages
    //
    // ZERO-KNOWLEDGE ENFORCEMENT:
    // - Server MUST NOT receive plaintext message_text for new messages
    // - All new messages MUST use encrypted_message + iv + payload_hash
    // - This ensures server cannot read message content (zero-knowledge architecture)
    //
    // LEGACY READ-ONLY POLICY:
    // - Existing plaintext messages remain in database (backward compatibility)
    // - Legacy messages are READ-ONLY (no edits, re-sends, or re-indexing allowed)
    // - This allows gradual migration without breaking existing data
    // ========================================================================
    
    const hasEncryptedFields = encryptedMessage && encryptedMessage.trim().length > 0 && 
                               iv && iv.trim().length > 0;
    const hasPlaintext = messageText && messageText.trim().length > 0;
    const hasPayloadHash = providedPayloadHash && providedPayloadHash.trim().length > 0;
    
    // SECURITY ENFORCEMENT: Reject ALL plaintext messages for new submissions
    // This enforces zero-knowledge architecture - server must never receive plaintext
    if (hasPlaintext) {
      // SECURITY WARNING: Attempt to submit plaintext message (deprecated and blocked)
      console.warn(`🚨 SECURITY WARNING: Plaintext message submission attempt blocked`);
      console.warn(`   Message ID: ${providedMessageId || 'pending'}`);
      console.warn(`   Sender: ${senderAddress}`);
      console.warn(`   Workspace: ${workspaceId}, Channel: ${channelId || 'DM'}`);
      console.warn(`   Reason: Plaintext messages are deprecated for security (zero-knowledge enforcement)`);
      
      return res.status(400).json({
        success: false,
        error: 'Plaintext messages are deprecated',
        message: 'All new messages must be encrypted. Plaintext message_text is no longer accepted for security reasons (zero-knowledge architecture). Use encrypted_message + iv + payload_hash instead.',
        security_notice: 'Server enforces zero-knowledge - it cannot read plaintext messages. Encryption must be performed client-side before submission.',
        required_fields: {
          encrypted_message: 'Base64-encoded AES-256-CBC encrypted message',
          iv: 'Base64-encoded initialization vector',
          payload_hash: 'SHA-256 hash of plaintext (calculated before encryption)',
          hash_version: 2
        },
        deprecated: 'message_text field is deprecated and rejected for new messages'
      });
    }
    
    // SECURITY: Require encrypted fields for all new messages
    if (!hasEncryptedFields) {
      return res.status(400).json({
        success: false,
        error: 'Missing encrypted message fields',
        message: 'encrypted_message and iv are required for all new messages (plaintext is deprecated)',
        required_fields: {
          encrypted_message: 'Base64-encoded AES-256-CBC encrypted message',
          iv: 'Base64-encoded initialization vector',
          payload_hash: 'SHA-256 hash of plaintext (calculated before encryption)',
          hash_version: 2
        }
      });
    }
    
    // SECURITY: Require payload_hash for encrypted messages (cannot calculate without plaintext)
    if (!hasPayloadHash || hasPayloadHash.trim().length === 0) {
      return res.status(400).json({
        success: false,
        error: 'Missing payload_hash',
        message: 'payload_hash is required for encrypted messages (calculated from plaintext on client before encryption)',
        security_note: 'payload_hash ensures hash chain integrity - it must be calculated from plaintext before encryption'
      });
    }
    
    // SECURITY: All new messages MUST use hash_version 2 (encrypted messages)
    // Legacy hash_version 1 (plaintext) is deprecated and rejected
    // Note: hash_version from request is ignored - we enforce v2 for all new messages
    
    // Use provided payload_hash (must be calculated from plaintext on client)
    // Server cannot calculate payload_hash because it never receives plaintext (zero-knowledge)
    const payloadHash = providedPayloadHash;
    
    // Validate payload_hash format (SHA-256 produces 64-character hex string)
    if (!/^[a-f0-9]{64}$/i.test(payloadHash)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid payload_hash format',
        message: 'payload_hash must be a valid SHA-256 hash (64-character hexadecimal string)'
      });
    }
    
    // SECURITY: All new messages MUST use hash_version 2 (encrypted messages)
    // Legacy hash_version 1 (plaintext) is deprecated and rejected
    const enforcedHashVersion = 2; // Enforced for all new messages
    
    // ========================================================================
    // SECURITY: BUILD MESSAGE DATA FOR HASH CALCULATION AND STORAGE
    // ========================================================================
    // HASH CALCULATION:
    // - hash_version 2: Uses payload_hash ONLY (no message_text needed)
    // - Server never receives plaintext, so it cannot calculate payload_hash
    // - Client must calculate payload_hash from plaintext before encryption
    //
    // MONGODB STORAGE:
    // - encrypted_message: Base64-encoded AES-256-CBC ciphertext
    // - iv: Base64-encoded initialization vector
    // - payload_hash: SHA-256 hash of plaintext (for hash chain integrity)
    // - hash_version: Always 2 for new messages (enforced)
    // - message_text: NOT stored (zero-knowledge enforcement)
    // ========================================================================
    
    // Build messageData for hash calculation (v2 uses payload_hash only)
    const messageDataForHash = {
      message_id: messageId,
      workspace_id: workspaceId,
      sender_address: senderAddress.toLowerCase().trim(),
      timestamp: timestamp,
      payload_hash: payloadHash, // Used for v2 hash calculation (calculated from plaintext on client)
      hash_version: enforcedHashVersion, // Always 2 for new messages
    };
    // NOTE: message_text is NOT included - we don't have plaintext (zero-knowledge)
    
    // Build messageData for MongoDB storage (encrypted only)
    const messageData = {
      message_id: messageId,
      workspace_id: workspaceId,
      sender_address: senderAddress.toLowerCase().trim(),
      timestamp: timestamp,
      payload_hash: payloadHash, // Always store payload_hash (for hash chain integrity)
      hash_version: enforcedHashVersion, // Always 2 for new messages (enforced)
      encrypted_message: encryptedMessage, // Base64-encoded encrypted message (required)
      iv: iv, // Base64-encoded IV (required)
      // message_text: NOT stored (zero-knowledge enforcement - server cannot read plaintext)
    };
    
    // Add optional fields
    if (channelId) messageData.channel_id = channelId;
    if (receiverAddress) messageData.receiver_address = receiverAddress.toLowerCase().trim();
    if (fileId) messageData.file_id = fileId;
    
    // Determine filter for hash chain (same conversation)
    const filter = channelId
      ? { workspace_id: workspaceId, channel_id: channelId }
      : receiverAddress
        ? {
            $or: [
              {
                sender_address: senderAddress.toLowerCase(),
                receiver_address: receiverAddress.toLowerCase()
              },
              {
                sender_address: receiverAddress.toLowerCase(),
                receiver_address: senderAddress.toLowerCase()
              }
            ]
          }
        : { workspace_id: workspaceId };
    
    // CRITICAL: Handle hash chain fields based on sync mode
    let messageWithHash;
    let insertSuccess = false;
    let retryAttempts = 0;
    const maxRetries = 5;
    
    if (isIdempotentSync && providedPreviousHash && providedCurrentHash) {
      // CRITICAL: For idempotent sync, use provided hashes directly
      // This prevents re-calculating hashes and breaking chain integrity
      console.log(`🔄 Idempotent sync: Using provided hashes for message ${messageId}`);
      messageWithHash = {
        ...messageData, // messageData already excludes message_text
        previous_hash: providedPreviousHash,
        current_hash: providedCurrentHash,
      };
      
      // CRITICAL: Verify provided hashes match expected chain state
      // For offline sync, allow re-anchoring if previous_hash doesn't match
      const verifyInfo = await HashChain.getAndVerifyLastHash(
        messagesCollection,
        filter,
        providedPreviousHash
      );
      
      if (!verifyInfo.isValid && verifyInfo.hash !== '0') {
        if (isOfflineSync) {
          // OFFLINE SYNC: Previous hash mismatch is expected when offline for extended period
          // Re-anchor the message to the current server chain
          console.log(`🔄 [OFFLINE SYNC] Re-anchoring message ${messageId} to server chain`);
          console.log(`   Expected server hash: ${verifyInfo.hash.substring(0, 10)}...`);
          console.log(`   Provided offline hash: ${providedPreviousHash.substring(0, 10)}...`);
          console.log(`   Message was offline, re-calculating hash with server's chain state`);
          
          // Re-calculate current_hash using server's last hash as previous_hash
          // Keep the provided current_hash structure but update previous_hash
          const reAnchoredPreviousHash = verifyInfo.hash;
          
          // Recalculate current_hash with new previous_hash (keeping same data)
          // Use messageDataForHash for hash calculation (v2 uses payload_hash only, no message_text)
          const reAnchoredMessageData = {
            ...messageDataForHash,
            previous_hash: reAnchoredPreviousHash,
          };
          
          // Recalculate hash with correct previous_hash (using enforced hash_version 2)
          const reAnchoredCurrentHash = HashChain.calculateHash(
            reAnchoredMessageData,
            reAnchoredPreviousHash,
            enforcedHashVersion // Always 2 for encrypted messages
          );
          
          messageWithHash = {
            ...messageData,
            previous_hash: reAnchoredPreviousHash,
            current_hash: reAnchoredCurrentHash,
          };
          
          console.log(`✅ [OFFLINE SYNC] Re-anchored message ${messageId} with new previous_hash`);
        } else {
          // Normal sync: Previous hash doesn't match - this might be a chain break or out-of-order sync
          console.warn(`⚠️ Provided previous_hash doesn't match chain state for message ${messageId}`);
          console.warn(`   Expected: ${verifyInfo.hash.substring(0, 10)}..., Provided: ${providedPreviousHash.substring(0, 10)}...`);
          // Continue anyway - chain integrity check will catch actual tampering
        }
      }
      
      // Insert message with provided (or re-anchored) hashes
      try {
        await messagesCollection.insertOne(messageWithHash);
        insertSuccess = true;
        const syncType = isOfflineSync ? '[OFFLINE SYNC]' : '[IDEMPOTENT SYNC]';
        console.log(`✅ ${syncType} Message inserted: ${messageId}`);
        if (isOfflineSync) {
          console.log(`   Previous hash: ${messageWithHash.previous_hash.substring(0, 10)}...`);
          console.log(`   Current hash: ${messageWithHash.current_hash.substring(0, 10)}...`);
          console.log(`   Hash version: ${messageWithHash.hash_version || enforcedHashVersion}`); // Always 2 for encrypted
        }
      } catch (error) {
        // If duplicate key error, message already exists (race condition)
        if (error.code === 11000 || error.message.includes('E11000')) {
          console.log(`⚠️ Message ${messageId} already exists (race condition) - returning existing`);
          const existingMessage = await messagesCollection.findOne({ message_id: messageId });
          if (existingMessage) {
            insertSuccess = true;
            messageWithHash = existingMessage;
          } else {
            throw error;
          }
        } else {
          throw error;
        }
      }
    } else {
      // Normal flow: Calculate hash chain fields (with retry mechanism for race conditions)
      while (!insertSuccess && retryAttempts < maxRetries) {
        try {
          // Get hash fields with built-in race condition handling
          // Use messageDataForHash for hash calculation (v2 uses payload_hash only, no message_text)
          messageWithHash = await HashChain.addHashFields(
            messagesCollection,
            messageDataForHash,
            filter,
            retryAttempts
          );
          
          // SECURITY: Clean up hash calculation fields before MongoDB insert
          // For v2: Only payload_hash is used (no message_text - we never receive plaintext)
          // Remove any message_text field that might have been added during hash calculation
          const { message_text, ...messageForMongoDB } = messageWithHash;
          messageWithHash = messageForMongoDB;
          // ENFORCEMENT: message_text is NEVER stored for new messages (zero-knowledge)
          
          // CRITICAL: Verify hash is still valid right before insert
          const verifyInfo = await HashChain.getAndVerifyLastHash(
            messagesCollection,
            filter,
            messageWithHash.previous_hash
          );
          
          if (!verifyInfo.isValid) {
            // Hash changed between calculation and insert - retry
            console.log(`⚠️ Hash changed right before insert - retrying (attempt ${retryAttempts + 1}/${maxRetries})`);
            retryAttempts++;
            await new Promise(resolve => setTimeout(resolve, 30 * retryAttempts));
            continue;
          }
          
          // Insert message - this is atomic
          await messagesCollection.insertOne(messageWithHash);
          insertSuccess = true;
          
          // Log success
          if (retryAttempts > 0) {
            console.log(`✅ Message inserted after ${retryAttempts} retries`);
          }
        } catch (error) {
          retryAttempts++;
          if (retryAttempts >= maxRetries) {
            console.error(`❌ Failed to insert message after ${maxRetries} retries: ${error.message}`);
            throw error;
          }
          // If it's a duplicate key error or race condition, retry
          if (error.code === 11000 || error.message.includes('E11000')) {
            console.log(`⚠️ Duplicate key or race condition detected - retrying (attempt ${retryAttempts}/${maxRetries})`);
            // Exponential backoff delay
            await new Promise(resolve => setTimeout(resolve, 50 * Math.pow(2, retryAttempts - 1)));
          } else {
            // For other errors, also retry (might be transient)
            console.log(`⚠️ Insert error (${error.message}) - retrying (attempt ${retryAttempts}/${maxRetries})`);
            await new Promise(resolve => setTimeout(resolve, 50 * retryAttempts));
          }
        }
      }
    }
    
    // Calculate execution time and gas
    const endTime = process.hrtime.bigint();
    const executionTimeMs = Number(endTime - startTime) / 1000000; // Convert nanoseconds to milliseconds
    
    // Calculate gas based on execution time
    const gasUsed = GasCalculator.calculateMessageGas(executionTimeMs, messageData);
    const gasPrice = GasCalculator.getCurrentGasPrice();
    const transactionFee = GasCalculator.calculateTransactionFee(gasUsed, gasPrice);
    
    // Update message with gas information
    await messagesCollection.updateOne(
      { message_id: messageId },
      {
        $set: {
          gas_used: gasUsed,
          gas_price: gasPrice,
          transaction_fee: transactionFee,
          transaction_time_ms: Math.round(executionTimeMs * 100) / 100
        }
      }
    );
    
    console.log(`✅ Message added: ${messageId} | Gas: ${gasUsed} | Time: ${Math.round(executionTimeMs * 100) / 100}ms`);
    
    return res.status(201).json({
      success: true,
      message: 'Message sent successfully',
        data: {
          message_id: messageId,
          workspace_id: workspaceId,
          sender_address: senderAddress.toLowerCase().trim(),
          // SECURITY: Return encrypted fields (if encrypted) or plaintext (if legacy)
          // Server is zero-knowledge - does not decrypt, just stores and returns encrypted payload
          ...(hasEncryptedFields ? {
            encrypted_message: encryptedMessage,
            iv: iv,
          } : {
            message_text: messageText, // Legacy plaintext (deprecated)
          }),
          payload_hash: payloadHash,
          timestamp: timestamp,
          gas_used: gasUsed,
          gas_price: gasPrice,
          transaction_fee: transactionFee,
          transaction_time_ms: Math.round(executionTimeMs * 100) / 100
        }
    });
  } catch (error) {
    // Calculate gas even on error
    const endTime = process.hrtime.bigint();
    const executionTimeMs = Number(endTime - startTime) / 1000000;
    const gasUsed = GasCalculator.calculateMessageGas(executionTimeMs, req.body);
    const gasPrice = GasCalculator.getCurrentGasPrice();
    const transactionFee = GasCalculator.calculateTransactionFee(gasUsed, gasPrice);
    
    console.error(`❌ Add message error: ${error.message} | Gas: ${gasUsed} | Time: ${Math.round(executionTimeMs * 100) / 100}ms`);
    return res.status(500).json({
      success: false,
      error: 'Failed to send message',
      message: error.message,
      gas_used: gasUsed,
      gas_price: gasPrice,
      transaction_fee: transactionFee,
      transaction_time_ms: Math.round(executionTimeMs * 100) / 100
    });
  }
});

/**
 * @route   GET /api/messages/channel
 * @desc    Get channel messages with chain integrity verification
 * @access  Public
 * 
 * LEGACY READ-ONLY POLICY:
 * - Returns encrypted_message + iv for encrypted messages (new format)
 * - Returns message_text for legacy plaintext messages (backward compatibility)
 * - Legacy messages are READ-ONLY: server does not allow edits, re-sends, or re-indexing
 * - This ensures backward compatibility while enforcing encryption for new messages
 * 
 * ZERO-KNOWLEDGE:
 * - Server never decrypts messages (zero-knowledge architecture)
 * - Returns encrypted payload as-is for client-side decryption
 */
router.get('/channel', optionalAuth, async (req, res) => {
  try {
    const messagesCollection = getCollection('messages');
    const { workspaceId, channelId } = req.query;
    
    if (!workspaceId || !channelId) {
      return res.status(400).json({
        success: false,
        error: 'Workspace ID and Channel ID are required'
      });
    }
    
    // Verify chain integrity before returning messages
    const filter = {
      workspace_id: workspaceId,
      channel_id: channelId
    };
    
    // First, check if there are any messages
    const messageCount = await messagesCollection.countDocuments(filter);
    
    if (messageCount === 0) {
      // No messages - return empty array
      return res.json({
        success: true,
        chainValid: true,
        count: 0,
        data: []
      });
    }
    
    // Verify chain integrity (only if messages exist)
    const chainVerification = await HashChain.verifyChainIntegrity(messagesCollection, filter);
    
    // If chain is broken, return error and hide messages (STRICT MODE)
    if (!chainVerification.valid) {
      console.error(`❌ Chain broken for channel ${channelId} in workspace ${workspaceId}`);
      console.error(`   Broken at: ${chainVerification.brokenAt}`);
      console.error(`   Details:`, JSON.stringify(chainVerification.details, null, 2));
      
      // STRICT: Block all messages when chain is broken
      return res.status(403).json({
        success: false,
        error: 'Chain integrity compromised',
        message: 'Data integrity check failed. Messages cannot be displayed for security reasons. A message may have been modified.',
        chainBroken: true,
        brokenAt: chainVerification.brokenAt,
        details: chainVerification.details,
        data: [] // Hide all messages
      });
    }
    
    // Chain is valid, fetch messages (excluding chain_broken messages)
    const messages = await messagesCollection
      .find({
        workspace_id: workspaceId,
        channel_id: channelId,
        chain_broken: { $ne: true } // Exclude chain broken messages
      })
      .sort({ timestamp: 1 })
      .toArray();
    
    // Get last message hash for chain continuity (before cleaning)
    let lastHash = null;
    let lastMessageId = null;
    if (messages.length > 0) {
      const lastMsg = messages[messages.length - 1];
      lastHash = lastMsg.current_hash || null;
      lastMessageId = lastMsg.message_id || null;
    }
    
    // Clean up response (remove internal hash fields)
    // SECURITY: Return encrypted_message + iv for encrypted messages
    // Return legacy message_text only for backward compatibility (deprecated)
    // Server is zero-knowledge: never decrypts, just stores and returns encrypted payload
    const cleanMessages = messages.map(msg => {
      const { 
        _id, 
        previous_hash, 
        current_hash, 
        chain_broken, 
        chain_broken_at, 
        createdAt, 
        updatedAt, 
        __v,
        ...rest 
      } = msg;
      // Return: message_id, workspace_id, channel_id, sender_address, receiver_address,
      //         encrypted_message (if encrypted), iv (if encrypted),
      //         message_text (if legacy plaintext - deprecated),
      //         payload_hash, hash_version, timestamp, file_id
      return rest;
    });
    
    console.log(`✅ Retrieved ${cleanMessages.length} channel messages (chain verified)`);
    
    return res.json({
      success: true,
      chainValid: true,
      count: cleanMessages.length,
      data: cleanMessages,
      // Include last hash for chain continuity (when syncing offline messages)
      lastHash: lastHash,
      lastMessageId: lastMessageId
    });
  } catch (error) {
    console.error('❌ Get channel messages error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to get messages',
      message: error.message
    });
  }
});

/**
 * @route   GET /api/messages/direct
 * @desc    Get direct messages between two users with chain integrity verification
 * @access  Public
 * 
 * LEGACY READ-ONLY POLICY:
 * - Returns encrypted_message + iv for encrypted messages (new format)
 * - Returns message_text for legacy plaintext messages (backward compatibility)
 * - Legacy messages are READ-ONLY: server does not allow edits, re-sends, or re-indexing
 * - This ensures backward compatibility while enforcing encryption for new messages
 * 
 * ZERO-KNOWLEDGE:
 * - Server never decrypts messages (zero-knowledge architecture)
 * - Returns encrypted payload as-is for client-side decryption
 */
router.get('/direct', optionalAuth, async (req, res) => {
  try {
    const messagesCollection = getCollection('messages');
    const { user1Address, user2Address } = req.query;
    
    if (!user1Address || !user2Address) {
      return res.status(400).json({
        success: false,
        error: 'Both user addresses are required'
      });
    }
    
    const addr1 = user1Address.toLowerCase().trim();
    const addr2 = user2Address.toLowerCase().trim();
    
    // Verify chain integrity before returning messages
    const filter = {
      $or: [
        {
          sender_address: addr1,
          receiver_address: addr2
        },
        {
          sender_address: addr2,
          receiver_address: addr1
        }
      ]
    };
    
    // First, check if there are any messages
    const messageCount = await messagesCollection.countDocuments(filter);
    
    if (messageCount === 0) {
      // No messages - return empty array
      return res.json({
        success: true,
        chainValid: true,
        count: 0,
        data: []
      });
    }
    
    // Verify chain integrity (only if messages exist)
    const chainVerification = await HashChain.verifyChainIntegrity(messagesCollection, filter);
    
    // If chain is broken, return error and hide messages (STRICT MODE)
    if (!chainVerification.valid) {
      console.error(`❌ Chain broken for direct messages between ${addr1} and ${addr2}`);
      console.error(`   Broken at: ${chainVerification.brokenAt}`);
      console.error(`   Details:`, JSON.stringify(chainVerification.details, null, 2));
      
      // STRICT: Block all messages when chain is broken
      return res.status(403).json({
        success: false,
        error: 'Chain integrity compromised',
        message: 'Data integrity check failed. Messages cannot be displayed for security reasons. A message may have been modified.',
        chainBroken: true,
        brokenAt: chainVerification.brokenAt,
        details: chainVerification.details,
        data: [] // Hide all messages
      });
    }
    
    // Chain is valid, fetch messages (excluding chain_broken messages)
    const messages = await messagesCollection
      .find({
        ...filter,
        chain_broken: { $ne: true } // Exclude chain broken messages
      })
      .sort({ timestamp: 1 })
      .toArray();
    
    // Clean up response (remove internal hash fields)
    // SECURITY: Return encrypted_message + iv for encrypted messages
    // Return legacy message_text only for backward compatibility (deprecated)
    // Server is zero-knowledge: never decrypts, just stores and returns encrypted payload
    const cleanMessages = messages.map(msg => {
      const { 
        _id, 
        previous_hash, 
        current_hash, 
        chain_broken, 
        chain_broken_at, 
        createdAt, 
        updatedAt, 
        __v,
        ...rest 
      } = msg;
      // Return: message_id, workspace_id, channel_id, sender_address, receiver_address,
      //         encrypted_message (if encrypted), iv (if encrypted),
      //         message_text (if legacy plaintext - deprecated),
      //         payload_hash, hash_version, timestamp, file_id
      return rest;
    });
    
    console.log(`✅ Retrieved ${cleanMessages.length} direct messages (chain verified)`);
    
    return res.json({
      success: true,
      chainValid: true,
      count: cleanMessages.length,
      data: cleanMessages
    });
  } catch (error) {
    console.error('❌ Get direct messages error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to get messages',
      message: error.message
    });
  }
});

/**
 * @route   GET /api/messages/workspace/:workspaceId
 * @desc    Get all messages in a workspace
 * @access  Public
 */
router.get('/workspace/:workspaceId', optionalAuth, async (req, res) => {
  try {
    const messagesCollection = getCollection('messages');
    const { workspaceId } = req.params;
    const { limit = 100, skip = 0 } = req.query;
    
    const messages = await messagesCollection
      .find({ workspace_id: workspaceId })
      .sort({ timestamp: -1 })
      .limit(parseInt(limit))
      .skip(parseInt(skip))
      .toArray();
    
    // Clean up response (remove internal hash fields)
    // SECURITY: Return encrypted_message + iv for encrypted messages
    // Return legacy message_text only for backward compatibility (deprecated, read-only)
    // Server is zero-knowledge: never decrypts, just stores and returns encrypted payload
    const cleanMessages = messages.map(msg => {
      const { 
        _id, 
        previous_hash, 
        current_hash,
        ...rest 
      } = msg;
      // Return: message_id, workspace_id, channel_id, sender_address, receiver_address,
      //         encrypted_message (if encrypted), iv (if encrypted),
      //         message_text (if legacy plaintext - deprecated, read-only),
      //         payload_hash, hash_version, timestamp, file_id
      return rest;
    });
    
    return res.json({
      success: true,
      count: cleanMessages.length,
      data: cleanMessages
    });
  } catch (error) {
    console.error('❌ Get workspace messages error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to get messages',
      message: error.message
    });
  }
});

module.exports = router;

