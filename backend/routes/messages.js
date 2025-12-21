const express = require('express');
const router = express.Router();
const { getCollection } = require('../utils/db');
const { validateMessage } = require('../middleware/validation');
const { optionalAuth } = require('../middleware/auth');
const HashChain = require('../utils/hashChain');

/**
 * @route   POST /api/messages
 * @desc    Add message with hash chain
 * @access  Public (add auth later)
 */
router.post('/', validateMessage, async (req, res) => {
  try {
    const messagesCollection = getCollection('messages');
    const {
      workspaceId,
      channelId,
      senderAddress,
      receiverAddress,
      messageText,
      fileId
    } = req.body;
    
    const timestamp = Date.now();
    const messageId = `msg_${timestamp}_${senderAddress.toLowerCase()}`;
    
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
    
    // Add hash chain fields
    const messageWithHash = await HashChain.addHashFields(
      messagesCollection,
      messageData,
      filter
    );
    
    // Insert message
    await messagesCollection.insertOne(messageWithHash);
    
    console.log(`✅ Message added: ${messageId}`);
    
    return res.status(201).json({
      success: true,
      message: 'Message sent successfully',
      data: {
        message_id: messageId,
        workspace_id: workspaceId,
        sender_address: senderAddress.toLowerCase().trim(),
        message_text: messageText,
        timestamp: timestamp
      }
    });
  } catch (error) {
    console.error('❌ Add message error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to send message',
      message: error.message
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
      data: cleanMessages
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

