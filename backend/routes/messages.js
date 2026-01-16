const express = require('express');
const router = express.Router();
const { getCollection } = require('../utils/db');
const { validateMessage } = require('../middleware/validation');
const { optionalAuth } = require('../middleware/auth');
const HashChain = require('../utils/hashChain');
const GasCalculator = require('../utils/gasCalculator');

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
      messageText,
      fileId,
      messageId: providedMessageId, // CRITICAL: Accept message_id from client for idempotency
      previousHash: providedPreviousHash, // CRITICAL: Accept previous_hash from client for sync
      currentHash: providedCurrentHash, // CRITICAL: Accept current_hash from client for sync
    } = req.body;
    
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
    
    const messageData = {
      message_id: messageId,
      workspace_id: workspaceId,
      sender_address: senderAddress.toLowerCase().trim(),
      message_text: messageText,
      timestamp: timestamp
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
        ...messageData,
        previous_hash: providedPreviousHash,
        current_hash: providedCurrentHash,
      };
      
      // CRITICAL: Verify provided hashes match expected chain state
      const verifyInfo = await HashChain.getAndVerifyLastHash(
        messagesCollection,
        filter,
        providedPreviousHash
      );
      
      if (!verifyInfo.isValid && verifyInfo.hash !== '0') {
        // Previous hash doesn't match - this might be a chain break or out-of-order sync
        console.warn(`⚠️ Provided previous_hash doesn't match chain state for message ${messageId}`);
        console.warn(`   Expected: ${verifyInfo.hash.substring(0, 10)}..., Provided: ${providedPreviousHash.substring(0, 10)}...`);
        // Continue anyway - chain integrity check will catch actual tampering
      }
      
      // Insert message with provided hashes
      try {
        await messagesCollection.insertOne(messageWithHash);
        insertSuccess = true;
        console.log(`✅ Idempotent sync message inserted: ${messageId}`);
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
          messageWithHash = await HashChain.addHashFields(
            messagesCollection,
            messageData,
            filter,
            retryAttempts
          );
          
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
        message_text: messageText,
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
    const cleanMessages = messages.map(msg => {
      const { _id, previous_hash, current_hash, chain_broken, chain_broken_at, createdAt, updatedAt, __v, ...rest } = msg;
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
    const cleanMessages = messages.map(msg => {
      const { _id, previous_hash, current_hash, chain_broken, chain_broken_at, createdAt, updatedAt, __v, ...rest } = msg;
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
    
    // Clean up response
    const cleanMessages = messages.map(msg => {
      const { _id, previous_hash, current_hash, ...rest } = msg;
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

