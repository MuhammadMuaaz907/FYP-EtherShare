# Complete API Code for FYP Report - EtherShare Project

## Table of Contents
1. [User Management APIs](#1-user-management-apis)
2. [Workspace Management APIs](#2-workspace-management-apis)
3. [Channel Management APIs](#3-channel-management-apis)
4. [Message Management APIs](#4-message-management-apis)
5. [Member Management APIs](#5-member-management-apis)
6. [File Management APIs](#6-file-management-apis)
7. [Node Management APIs](#7-node-management-apis)
8. [Peer-to-Peer APIs](#8-peer-to-peer-apis)
9. [Health Check & Root APIs](#9-health-check--root-apis)
10. [Server Configuration](#10-server-configuration)

---

## 1. User Management APIs

### File: `backend/routes/users.js`

#### 1.1 POST /api/users/profile - Create or Update User Profile

```javascript
const express = require('express');
const router = express.Router();
const { getCollection } = require('../utils/db');
const { validateUserProfile } = require('../middleware/validation');

/**
 * @route   POST /api/users/profile
 * @desc    Create or update user profile
 * @access  Public
 */
router.post('/profile', validateUserProfile, async (req, res) => {
  try {
    const usersCollection = getCollection('users');
    const { address, username, email, firstName, lastName, designation } = req.body;
    const timestamp = Date.now();
    
    const normalizedAddress = address.toLowerCase().trim();
    const normalizedUsername = (username || '').trim();
    
    if (!normalizedUsername || normalizedUsername.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'Username is required'
      });
    }
    
    // Check if username already exists
    const existingUsername = await usersCollection.findOne({
      username: { $regex: new RegExp(`^${normalizedUsername.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 'i') },
      address: { $ne: normalizedAddress }
    });
    
    if (existingUsername) {
      return res.status(409).json({
        success: false,
        error: 'Username already taken'
      });
    }
    
    // Check if user exists by address
    const existing = await usersCollection.findOne({ 
      address: normalizedAddress 
    });
    
    if (existing) {
      // Update existing user
      const updateData = {
        username: normalizedUsername,
        email,
        updated_at: timestamp
      };
      
      if (normalizedFirstName) updateData.firstName = normalizedFirstName;
      if (normalizedLastName) updateData.lastName = normalizedLastName;
      if (normalizedDesignation) updateData.designation = normalizedDesignation;
      
      await usersCollection.updateOne(
        { address: normalizedAddress },
        { $set: updateData }
      );
      
      const updatedUser = await usersCollection.findOne({ address: normalizedAddress });
      delete updatedUser._id;
      
      return res.json({
        success: true,
        message: 'User profile updated successfully',
        data: updatedUser
      });
    } else {
      // Create new user
      const userData = {
        address: normalizedAddress,
        username: normalizedUsername,
        email,
        created_at: timestamp,
        updated_at: timestamp
      };
      
      if (normalizedFirstName) userData.firstName = normalizedFirstName;
      if (normalizedLastName) userData.lastName = normalizedLastName;
      if (normalizedDesignation) userData.designation = normalizedDesignation;
      
      await usersCollection.insertOne(userData);
      delete userData._id;
      
      return res.status(201).json({
        success: true,
        message: 'User profile created successfully',
        data: userData
      });
    }
  } catch (error) {
    console.error('❌ Save user profile error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to save user profile',
      message: error.message
    });
  }
});
```

#### 1.2 GET /api/users/profile/:address - Get User Profile

```javascript
/**
 * @route   GET /api/users/profile/:address
 * @desc    Get user profile by address
 * @access  Public
 */
router.get('/profile/:address', optionalAuth, async (req, res) => {
  try {
    const usersCollection = getCollection('users');
    const address = req.params.address.toLowerCase().trim();
    
    const user = await usersCollection.findOne({ address });
    
    if (!user) {
      return res.status(404).json({
        success: false,
        error: 'User not found',
        message: `No profile found for address: ${address}`
      });
    }
    
    delete user._id;
    
    return res.json({
      success: true,
      data: user
    });
  } catch (error) {
    console.error('❌ Get user profile error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to get user profile',
      message: error.message
    });
  }
});
```

#### 1.3 GET /api/users/search - Search Users

```javascript
/**
 * @route   GET /api/users/search
 * @desc    Search users by username or email
 * @access  Public
 */
router.get('/search', optionalAuth, async (req, res) => {
  try {
    const usersCollection = getCollection('users');
    const { query } = req.query;
    
    if (!query || query.trim().length < 2) {
      return res.status(400).json({
        success: false,
        error: 'Invalid search query',
        message: 'Search query must be at least 2 characters'
      });
    }
    
    const searchRegex = new RegExp(query.trim(), 'i');
    
    const users = await usersCollection
      .find({
        $or: [
          { username: searchRegex },
          { email: searchRegex }
        ]
      })
      .limit(20)
      .toArray();
    
    const cleanUsers = users.map(user => {
      const { _id, ...rest } = user;
      return rest;
    });
    
    return res.json({
      success: true,
      count: cleanUsers.length,
      data: cleanUsers
    });
  } catch (error) {
    console.error('❌ Search users error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to search users',
      message: error.message
    });
  }
});

module.exports = router;
```

---

## 2. Workspace Management APIs

### File: `backend/routes/workspaces.js`

#### 2.1 POST /api/workspaces - Create Workspace

```javascript
const express = require('express');
const router = express.Router();
const { getCollection } = require('../utils/db');
const HashChain = require('../utils/hashChain');
const GasCalculator = require('../utils/gasCalculator');

/**
 * @route   POST /api/workspaces
 * @desc    Create new workspace with hash chain
 * @access  Public
 */
router.post('/', validateWorkspace, async (req, res) => {
  const startTime = process.hrtime.bigint();
  
  try {
    const workspacesCollection = getCollection('workspaces');
    const membersCollection = getCollection('members');
    
    const { workspaceName, inviterAddress } = req.body;
    
    if (!inviterAddress) {
      return res.status(400).json({
        success: false,
        error: 'Inviter address is required'
      });
    }
    
    const normalizedName = (workspaceName || '').trim();
    const normalizedInviter = inviterAddress.toLowerCase().trim();
    
    if (!normalizedName || normalizedName.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'Workspace name cannot be empty'
      });
    }
    
    // Check if workspace name already exists
    const existingWorkspace = await workspacesCollection.findOne({
      inviter_address: normalizedInviter,
      name: { $regex: new RegExp(`^${normalizedName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 'i') }
    });
    
    if (existingWorkspace) {
      return res.status(409).json({
        success: false,
        error: 'Workspace name already exists'
      });
    }
    
    const timestamp = Date.now();
    const workspaceId = `ws_${normalizedInviter}_${timestamp}`;
    
    const workspaceData = {
      workspace_id: workspaceId,
      name: normalizedName,
      inviter_address: normalizedInviter,
      created_at: timestamp,
      timestamp: timestamp
    };
    
    // Add hash chain fields
    const workspaceWithHash = await HashChain.addHashFields(
      workspacesCollection,
      workspaceData
    );
    
    // Insert workspace
    await workspacesCollection.insertOne(workspaceWithHash);
    
    // Add inviter as member
    await membersCollection.insertOne({
      workspace_id: workspaceId,
      member_address: inviterAddress.toLowerCase().trim(),
      display_name: null,
      joined_at: timestamp
    });
    
    // Create default channels (General and Random)
    const channelsCollection = getCollection('channels');
    const defaultChannels = [
      { channel_id: 'general', channel_name: 'General', is_default: true, is_private: false },
      { channel_id: 'random', channel_name: 'Random', is_default: true, is_private: false }
    ];
    
    for (const channelData of defaultChannels) {
      const channelDoc = {
        channel_id: channelData.channel_id,
        workspace_id: workspaceId,
        channel_name: channelData.channel_name,
        creator_address: inviterAddress.toLowerCase().trim(),
        members: [],
        is_private: channelData.is_private,
        is_default: channelData.is_default,
        created_at: timestamp,
        timestamp: timestamp
      };
      
      const channelWithHash = await HashChain.addHashFields(
        channelsCollection,
        channelDoc,
        { workspace_id: workspaceId }
      );
      
      await channelsCollection.insertOne(channelWithHash);
    }
    
    // Calculate execution time and gas
    const endTime = process.hrtime.bigint();
    const executionTimeMs = Number(endTime - startTime) / 1000000;
    
    const gasUsed = GasCalculator.calculateWorkspaceGas(executionTimeMs, workspaceData);
    const gasPrice = GasCalculator.getCurrentGasPrice();
    const transactionFee = GasCalculator.calculateTransactionFee(gasUsed, gasPrice);
    
    // Update workspace with gas information
    await workspacesCollection.updateOne(
      { workspace_id: workspaceId },
      {
        $set: {
          gas_used: gasUsed,
          gas_price: gasPrice,
          transaction_fee: transactionFee,
          transaction_time_ms: Math.round(executionTimeMs * 100) / 100
        }
      }
    );
    
    return res.status(201).json({
      success: true,
      message: 'Workspace created successfully',
      data: {
        workspace_id: workspaceId,
        name: workspaceName,
        inviter_address: inviterAddress.toLowerCase().trim(),
        created_at: timestamp,
        gas_used: gasUsed,
        gas_price: gasPrice,
        transaction_fee: transactionFee,
        transaction_time_ms: Math.round(executionTimeMs * 100) / 100
      }
    });
  } catch (error) {
    const endTime = process.hrtime.bigint();
    const executionTimeMs = Number(endTime - startTime) / 1000000;
    const gasUsed = GasCalculator.calculateWorkspaceGas(executionTimeMs, req.body);
    const gasPrice = GasCalculator.getCurrentGasPrice();
    const transactionFee = GasCalculator.calculateTransactionFee(gasUsed, gasPrice);
    
    return res.status(500).json({
      success: false,
      error: 'Failed to create workspace',
      message: error.message,
      gas_used: gasUsed,
      gas_price: gasPrice,
      transaction_fee: transactionFee,
      transaction_time_ms: Math.round(executionTimeMs * 100) / 100
    });
  }
});
```

#### 2.2 GET /api/workspaces/user/:address - Get User Workspaces

```javascript
/**
 * @route   GET /api/workspaces/user/:address
 * @desc    Get all workspaces for a user
 * @access  Public
 */
router.get('/user/:address', optionalAuth, async (req, res) => {
  try {
    const workspacesCollection = getCollection('workspaces');
    const membersCollection = getCollection('members');
    const address = req.params.address.toLowerCase().trim();
    
    // Get workspaces where user is inviter
    const ownWorkspaces = await workspacesCollection
      .find({ inviter_address: address })
      .toArray();
    
    // Get workspaces where user is a member
    const memberships = await membersCollection
      .find({ member_address: address })
      .toArray();
    
    const workspaceIds = memberships.map(m => m.workspace_id);
    const memberWorkspaces = await workspacesCollection
      .find({ workspace_id: { $in: workspaceIds } })
      .toArray();
    
    // Combine and remove duplicates
    const workspaceMap = new Map();
    
    for (const workspace of ownWorkspaces) {
      workspaceMap.set(workspace.workspace_id, workspace);
    }
    
    for (const workspace of memberWorkspaces) {
      if (!workspaceMap.has(workspace.workspace_id)) {
        workspaceMap.set(workspace.workspace_id, workspace);
      }
    }
    
    const cleanWorkspaces = Array.from(workspaceMap.values()).map(ws => {
      const { _id, previous_hash, current_hash, ...rest } = ws;
      return rest;
    });
    
    return res.json({
      success: true,
      count: cleanWorkspaces.length,
      data: cleanWorkspaces
    });
  } catch (error) {
    console.error('❌ Get user workspaces error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to get workspaces',
      message: error.message
    });
  }
});
```

#### 2.3 GET /api/workspaces/:workspaceId - Get Workspace by ID

```javascript
/**
 * @route   GET /api/workspaces/:workspaceId
 * @desc    Get workspace by ID
 * @access  Public
 */
router.get('/:workspaceId', optionalAuth, async (req, res) => {
  try {
    const workspacesCollection = getCollection('workspaces');
    const { workspaceId } = req.params;
    
    const workspace = await workspacesCollection.findOne({ 
      workspace_id: workspaceId 
    });
    
    if (!workspace) {
      return res.status(404).json({
        success: false,
        error: 'Workspace not found'
      });
    }
    
    const { _id, previous_hash, current_hash, ...cleanWorkspace } = workspace;
    
    return res.json({
      success: true,
      data: cleanWorkspace
    });
  } catch (error) {
    console.error('❌ Get workspace error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to get workspace',
      message: error.message
    });
  }
});
```

#### 2.4 POST /api/workspaces/:workspaceId/verify - Verify Hash Chain

```javascript
/**
 * @route   POST /api/workspaces/:workspaceId/verify
 * @desc    Verify workspace hash chain integrity
 * @access  Public
 */
router.post('/:workspaceId/verify', optionalAuth, async (req, res) => {
  try {
    const workspacesCollection = getCollection('workspaces');
    const { workspaceId } = req.params;
    
    const isValid = await HashChain.verifyChainIntegrity(
      workspacesCollection,
      { workspace_id: workspaceId }
    );
    
    return res.json({
      success: true,
      data: {
        workspace_id: workspaceId,
        chain_valid: isValid
      }
    });
  } catch (error) {
    console.error('❌ Verify workspace chain error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to verify workspace chain',
      message: error.message
    });
  }
});

module.exports = router;
```

---

## 3. Channel Management APIs

### File: `backend/routes/channels.js`

#### 3.1 POST /api/channels - Create Channel

```javascript
const express = require('express');
const router = express.Router();
const { getCollection } = require('../utils/db');
const HashChain = require('../utils/hashChain');
const GasCalculator = require('../utils/gasCalculator');

/**
 * @route   POST /api/channels
 * @desc    Create new channel in workspace with hash chain
 * @access  Public
 */
router.post('/', optionalAuth, async (req, res) => {
  const startTime = process.hrtime.bigint();
  
  try {
    const channelsCollection = getCollection('channels');
    const { workspaceId, channelId, channelName, creatorAddress, isPrivate = false } = req.body;
    
    if (!workspaceId || !channelId || !creatorAddress) {
      return res.status(400).json({
        success: false,
        error: 'Workspace ID, Channel ID, and Creator Address are required'
      });
    }
    
    const normalizedChannelId = channelId.toLowerCase().trim().replace(/\s+/g, '-');
    const displayName = (channelName || normalizedChannelId).trim();
    
    // Check if channel already exists
    const existingChannel = await channelsCollection.findOne({
      workspace_id: workspaceId,
      channel_id: normalizedChannelId,
      deleted: { $ne: true }
    });
    
    if (existingChannel) {
      return res.status(409).json({
        success: false,
        error: 'Channel with this ID already exists in this workspace'
      });
    }
    
    const timestamp = Date.now();
    const isDefault = ['general', 'random'].includes(normalizedChannelId);
    
    const channelData = {
      channel_id: normalizedChannelId,
      workspace_id: workspaceId,
      channel_name: displayName,
      creator_address: creatorAddress.toLowerCase().trim(),
      members: isDefault ? [] : [creatorAddress.toLowerCase().trim()],
      is_private: isPrivate && !isDefault,
      is_default: isDefault,
      created_at: timestamp,
      timestamp: timestamp
    };
    
    // Add hash chain fields
    const channelWithHash = await HashChain.addHashFields(
      channelsCollection,
      channelData,
      { workspace_id: workspaceId }
    );
    
    await channelsCollection.insertOne(channelWithHash);
    
    // Calculate gas
    const endTime = process.hrtime.bigint();
    const executionTimeMs = Number(endTime - startTime) / 1000000;
    const gasUsed = GasCalculator.calculateChannelGas(executionTimeMs, channelData);
    const gasPrice = GasCalculator.getCurrentGasPrice();
    const transactionFee = GasCalculator.calculateTransactionFee(gasUsed, gasPrice);
    
    await channelsCollection.updateOne(
      { channel_id: normalizedChannelId, workspace_id: workspaceId },
      {
        $set: {
          gas_used: gasUsed,
          gas_price: gasPrice,
          transaction_fee: transactionFee,
          transaction_time_ms: Math.round(executionTimeMs * 100) / 100
        }
      }
    );
    
    const { _id, previous_hash, current_hash, ...cleanChannel } = channelWithHash;
    cleanChannel.gas_used = gasUsed;
    cleanChannel.gas_price = gasPrice;
    cleanChannel.transaction_fee = transactionFee;
    
    return res.status(201).json({
      success: true,
      message: 'Channel created successfully',
      data: cleanChannel
    });
  } catch (error) {
    const endTime = process.hrtime.bigint();
    const executionTimeMs = Number(endTime - startTime) / 1000000;
    const gasUsed = GasCalculator.calculateChannelGas(executionTimeMs, req.body);
    const gasPrice = GasCalculator.getCurrentGasPrice();
    const transactionFee = GasCalculator.calculateTransactionFee(gasUsed, gasPrice);
    
    return res.status(500).json({
      success: false,
      error: 'Failed to create channel',
      message: error.message,
      gas_used: gasUsed,
      gas_price: gasPrice,
      transaction_fee: transactionFee
    });
  }
});
```

#### 3.2 GET /api/channels/workspace/:workspaceId - Get Workspace Channels

```javascript
/**
 * @route   GET /api/channels/workspace/:workspaceId
 * @desc    Get all channels for a workspace
 * @access  Public
 */
router.get('/workspace/:workspaceId', optionalAuth, async (req, res) => {
  try {
    const channelsCollection = getCollection('channels');
    const { workspaceId } = req.params;
    const { memberAddress } = req.query;
    
    let query = { 
      workspace_id: workspaceId,
      deleted: { $ne: true }
    };
    
    if (memberAddress) {
      const memberAddr = memberAddress.toLowerCase().trim();
      const membersCollection = getCollection('members');
      const isWorkspaceMember = await membersCollection.findOne({
        workspace_id: workspaceId,
        member_address: memberAddr
      });
      
      if (!isWorkspaceMember) {
        query = {
          workspace_id: workspaceId,
          deleted: { $ne: true },
          $or: [
            { is_default: true },
            { is_private: false },
            { members: { $in: [memberAddr] } },
            { members: { $size: 0 } }
          ]
        };
      }
    }
    
    let channels = await channelsCollection.find(query).toArray();
    
    // Remove duplicates
    const uniqueChannels = [];
    const seenChannelIds = new Set();
    
    for (const channel of channels) {
      const channelId = (channel.channel_id || '').toLowerCase().trim();
      if (!seenChannelIds.has(channelId)) {
        seenChannelIds.add(channelId);
        uniqueChannels.push(channel);
      }
    }
    
    // Sort: General first, Random second, then others
    uniqueChannels.sort((a, b) => {
      const aId = (a.channel_id || '').toLowerCase();
      const bId = (b.channel_id || '').toLowerCase();
      
      if (aId === 'general') return -1;
      if (bId === 'general') return 1;
      if (aId === 'random') return -1;
      if (bId === 'random') return 1;
      
      return (a.created_at || 0) - (b.created_at || 0);
    });
    
    const cleanChannels = uniqueChannels.map(ch => {
      const { _id, previous_hash, current_hash, ...rest } = ch;
      return rest;
    });
    
    return res.json({
      success: true,
      count: cleanChannels.length,
      data: cleanChannels
    });
  } catch (error) {
    console.error('❌ Get workspace channels error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to get channels',
      message: error.message
    });
  }
});
```

---

## 4. Message Management APIs

### File: `backend/routes/messages.js`

#### 4.1 POST /api/messages - Send Message

```javascript
const express = require('express');
const router = express.Router();
const { getCollection } = require('../utils/db');
const { validateMessage } = require('../middleware/validation');
const HashChain = require('../utils/hashChain');
const GasCalculator = require('../utils/gasCalculator');

/**
 * @route   POST /api/messages
 * @desc    Add message with hash chain
 * @access  Public
 */
router.post('/', validateMessage, async (req, res) => {
  const startTime = process.hrtime.bigint();
  
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
    
    if (channelId) messageData.channel_id = channelId;
    if (receiverAddress) messageData.receiver_address = receiverAddress.toLowerCase().trim();
    if (fileId) messageData.file_id = fileId;
    
    // Determine filter for hash chain
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
    
    // Add hash chain fields with retry mechanism
    let messageWithHash;
    let insertSuccess = false;
    let retryAttempts = 0;
    const maxRetries = 5;
    
    while (!insertSuccess && retryAttempts < maxRetries) {
      try {
        messageWithHash = await HashChain.addHashFields(
          messagesCollection,
          messageData,
          filter,
          retryAttempts
        );
        
        // Verify hash is still valid
        const verifyInfo = await HashChain.getAndVerifyLastHash(
          messagesCollection,
          filter,
          messageWithHash.previous_hash
        );
        
        if (!verifyInfo.isValid) {
          retryAttempts++;
          await new Promise(resolve => setTimeout(resolve, 30 * retryAttempts));
          continue;
        }
        
        await messagesCollection.insertOne(messageWithHash);
        insertSuccess = true;
      } catch (error) {
        retryAttempts++;
        if (retryAttempts >= maxRetries) {
          throw error;
        }
        await new Promise(resolve => setTimeout(resolve, 50 * Math.pow(2, retryAttempts - 1)));
      }
    }
    
    // Calculate gas
    const endTime = process.hrtime.bigint();
    const executionTimeMs = Number(endTime - startTime) / 1000000;
    const gasUsed = GasCalculator.calculateMessageGas(executionTimeMs, messageData);
    const gasPrice = GasCalculator.getCurrentGasPrice();
    const transactionFee = GasCalculator.calculateTransactionFee(gasUsed, gasPrice);
    
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
    const endTime = process.hrtime.bigint();
    const executionTimeMs = Number(endTime - startTime) / 1000000;
    const gasUsed = GasCalculator.calculateMessageGas(executionTimeMs, req.body);
    const gasPrice = GasCalculator.getCurrentGasPrice();
    const transactionFee = GasCalculator.calculateTransactionFee(gasUsed, gasPrice);
    
    return res.status(500).json({
      success: false,
      error: 'Failed to send message',
      message: error.message,
      gas_used: gasUsed,
      gas_price: gasPrice,
      transaction_fee: transactionFee
    });
  }
});
```

#### 4.2 GET /api/messages/channel - Get Channel Messages

```javascript
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
    
    const filter = {
      workspace_id: workspaceId,
      channel_id: channelId
    };
    
    const messageCount = await messagesCollection.countDocuments(filter);
    
    if (messageCount === 0) {
      return res.json({
        success: true,
        chainValid: true,
        count: 0,
        data: []
      });
    }
    
    // Verify chain integrity
    const chainVerification = await HashChain.verifyChainIntegrity(messagesCollection, filter);
    
    if (!chainVerification.valid) {
      return res.status(403).json({
        success: false,
        error: 'Chain integrity compromised',
        message: 'Data integrity check failed. Messages cannot be displayed.',
        chainBroken: true,
        brokenAt: chainVerification.brokenAt,
        data: []
      });
    }
    
    // Fetch messages (excluding chain_broken)
    const messages = await messagesCollection
      .find({
        workspace_id: workspaceId,
        channel_id: channelId,
        chain_broken: { $ne: true }
      })
      .sort({ timestamp: 1 })
      .toArray();
    
    const cleanMessages = messages.map(msg => {
      const { _id, previous_hash, current_hash, chain_broken, ...rest } = msg;
      return rest;
    });
    
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
```

#### 4.3 GET /api/messages/direct - Get Direct Messages

```javascript
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
    
    const messageCount = await messagesCollection.countDocuments(filter);
    
    if (messageCount === 0) {
      return res.json({
        success: true,
        chainValid: true,
        count: 0,
        data: []
      });
    }
    
    // Verify chain integrity
    const chainVerification = await HashChain.verifyChainIntegrity(messagesCollection, filter);
    
    if (!chainVerification.valid) {
      return res.status(403).json({
        success: false,
        error: 'Chain integrity compromised',
        chainBroken: true,
        brokenAt: chainVerification.brokenAt,
        data: []
      });
    }
    
    const messages = await messagesCollection
      .find({
        ...filter,
        chain_broken: { $ne: true }
      })
      .sort({ timestamp: 1 })
      .toArray();
    
    const cleanMessages = messages.map(msg => {
      const { _id, previous_hash, current_hash, chain_broken, ...rest } = msg;
      return rest;
    });
    
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

module.exports = router;
```

---

## 5. Member Management APIs

### File: `backend/routes/members.js`

#### 5.1 POST /api/members - Add Member

```javascript
const express = require('express');
const router = express.Router();
const { getCollection } = require('../utils/db');

/**
 * @route   POST /api/members
 * @desc    Add workspace member
 * @access  Public
 */
router.post('/', validateMember, async (req, res) => {
  try {
    const membersCollection = getCollection('members');
    const { workspaceId, memberAddress, displayName } = req.body;
    
    const timestamp = Date.now();
    const normalizedAddress = memberAddress.toLowerCase().trim();
    
    // Check if member already exists
    const existing = await membersCollection.findOne({
      workspace_id: workspaceId,
      member_address: normalizedAddress
    });
    
    if (existing) {
      return res.json({
        success: true,
        message: 'Member already exists',
        data: existing
      });
    }
    
    const memberData = {
      workspace_id: workspaceId,
      member_address: normalizedAddress,
      display_name: displayName || null,
      joined_at: timestamp
    };
    
    await membersCollection.insertOne(memberData);
    
    return res.status(201).json({
      success: true,
      message: 'Member added successfully',
      data: memberData
    });
  } catch (error) {
    console.error('❌ Add member error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to add member',
      message: error.message
    });
  }
});
```

#### 5.2 GET /api/members/workspace/:workspaceId - Get Workspace Members

```javascript
/**
 * @route   GET /api/members/workspace/:workspaceId
 * @desc    Get all members of a workspace
 * @access  Public
 */
router.get('/workspace/:workspaceId', optionalAuth, async (req, res) => {
  try {
    const membersCollection = getCollection('members');
    const { workspaceId } = req.params;
    
    const members = await membersCollection
      .find({ workspace_id: workspaceId })
      .toArray();
    
    const cleanMembers = members.map(member => {
      const { _id, ...rest } = member;
      return rest;
    });
    
    return res.json({
      success: true,
      count: cleanMembers.length,
      data: cleanMembers
    });
  } catch (error) {
    console.error('❌ Get members error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to get members',
      message: error.message
    });
  }
});
```

#### 5.3 DELETE /api/members - Remove Member

```javascript
/**
 * @route   DELETE /api/members
 * @desc    Remove member from workspace
 * @access  Public
 */
router.delete('/', async (req, res) => {
  try {
    const membersCollection = getCollection('members');
    const { workspaceId, memberAddress } = req.body;
    
    if (!workspaceId || !memberAddress) {
      return res.status(400).json({
        success: false,
        error: 'Workspace ID and Member Address are required'
      });
    }
    
    const result = await membersCollection.deleteOne({
      workspace_id: workspaceId,
      member_address: memberAddress.toLowerCase().trim()
    });
    
    if (result.deletedCount === 0) {
      return res.status(404).json({
        success: false,
        error: 'Member not found'
      });
    }
    
    return res.json({
      success: true,
      message: 'Member removed successfully'
    });
  } catch (error) {
    console.error('❌ Remove member error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to remove member',
      message: error.message
    });
  }
});

module.exports = router;
```

---

## 6. File Management APIs

### File: `backend/routes/files.js`

#### 6.1 POST /api/files/upload - Upload File

```javascript
const express = require('express');
const router = express.Router();
const multer = require('multer');
const fs = require('fs');
const path = require('path');
const { GridFSBucket } = require('mongodb');
const { getCollection, getDb } = require('../utils/db');

// Configure multer
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const uploadPath = process.env.UPLOAD_PATH || './uploads';
    if (!fs.existsSync(uploadPath)) {
      fs.mkdirSync(uploadPath, { recursive: true });
    }
    cb(null, uploadPath);
  },
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    cb(null, file.fieldname + '-' + uniqueSuffix + path.extname(file.originalname));
  }
});

const upload = multer({
  storage: storage,
  limits: {
    fileSize: parseInt(process.env.MAX_FILE_SIZE) || 10 * 1024 * 1024 // 10MB
  }
});

/**
 * @route   POST /api/files/upload
 * @desc    Upload file and save metadata
 * @access  Public
 */
router.post('/upload', upload.single('file'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({
        success: false,
        error: 'No file uploaded'
      });
    }

    const filesCollection = getCollection('files');
    const db = getDb();
    const { workspaceId, uploaderAddress } = req.body;
    
    if (!workspaceId || !uploaderAddress) {
      fs.unlinkSync(req.file.path);
      return res.status(400).json({
        success: false,
        error: 'Workspace ID and Uploader Address are required'
      });
    }

    const timestamp = Date.now();
    const fileId = `file_${timestamp}_${uploaderAddress.toLowerCase()}`;
    
    // Read file for GridFS
    const fileBuffer = fs.readFileSync(req.file.path);
    
    // Create GridFS bucket
    const bucket = new GridFSBucket(db, { bucketName: 'files' });
    
    // Upload to GridFS
    const uploadStream = bucket.openUploadStream(req.file.originalname, {
      metadata: {
        fileId: fileId,
        workspaceId: workspaceId,
        uploaderAddress: uploaderAddress.toLowerCase().trim()
      }
    });
    
    uploadStream.end(fileBuffer);
    
    // Wait for upload to complete
    await new Promise((resolve, reject) => {
      uploadStream.on('finish', resolve);
      uploadStream.on('error', reject);
    });
    
    const gridfsId = uploadStream.id.toString();
    
    // Save file metadata
    const fileData = {
      file_id: fileId,
      filename: req.file.originalname,
      workspace_id: workspaceId,
      uploader_address: uploaderAddress.toLowerCase().trim(),
      gridfs_id: gridfsId,
      file_size: req.file.size,
      upload_timestamp: timestamp,
      mime_type: req.file.mimetype
    };
    
    await filesCollection.insertOne(fileData);
    
    // Delete temporary file
    fs.unlinkSync(req.file.path);
    
    return res.status(201).json({
      success: true,
      message: 'File uploaded successfully',
      data: {
        file_id: fileId,
        filename: req.file.originalname,
        file_size: req.file.size,
        upload_timestamp: timestamp
      }
    });
  } catch (error) {
    if (req.file && fs.existsSync(req.file.path)) {
      fs.unlinkSync(req.file.path);
    }
    
    console.error('❌ File upload error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to upload file',
      message: error.message
    });
  }
});
```

#### 6.2 GET /api/files/:fileId - Get File Metadata

```javascript
/**
 * @route   GET /api/files/:fileId
 * @desc    Get file metadata
 * @access  Public
 */
router.get('/:fileId', optionalAuth, async (req, res) => {
  try {
    const filesCollection = getCollection('files');
    const { fileId } = req.params;
    
    const file = await filesCollection.findOne({ file_id: fileId });
    
    if (!file) {
      return res.status(404).json({
        success: false,
        error: 'File not found'
      });
    }
    
    const { _id, ...cleanFile } = file;
    
    return res.json({
      success: true,
      data: cleanFile
    });
  } catch (error) {
    console.error('❌ Get file metadata error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to get file metadata',
      message: error.message
    });
  }
});
```

#### 6.3 GET /api/files/:fileId/download - Download File

```javascript
/**
 * @route   GET /api/files/:fileId/download
 * @desc    Download file from GridFS
 * @access  Public
 */
router.get('/:fileId/download', optionalAuth, async (req, res) => {
  try {
    const filesCollection = getCollection('files');
    const db = getDb();
    const { fileId } = req.params;
    
    const file = await filesCollection.findOne({ file_id: fileId });
    
    if (!file) {
      return res.status(404).json({
        success: false,
        error: 'File not found'
      });
    }
    
    const bucket = new GridFSBucket(db, { bucketName: 'files' });
    const downloadStream = bucket.openDownloadStream(
      new ObjectId(file.gridfs_id)
    );
    
    // Set response headers
    res.setHeader('Content-Type', file.mime_type || 'application/octet-stream');
    res.setHeader('Content-Disposition', `attachment; filename="${file.filename}"`);
    
    downloadStream.pipe(res);
    
    downloadStream.on('error', (error) => {
      console.error('❌ File download error:', error);
      if (!res.headersSent) {
        res.status(500).json({
          success: false,
          error: 'Failed to download file'
        });
      }
    });
  } catch (error) {
    console.error('❌ Download file error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to download file',
      message: error.message
    });
  }
});

module.exports = router;
```

---

## 7. Node Management APIs

### File: `backend/routes/nodes.js`

#### 7.1 POST /api/nodes/register - Register Node

```javascript
const express = require('express');
const router = express.Router();
const NodeService = require('../services/nodeService');

/**
 * @route   POST /api/nodes/register
 * @desc    Register a new node (blockchain-like)
 * @access  Public
 */
router.post('/register', async (req, res) => {
  try {
    const { node_name, ip_address, tcp_port } = req.body;
    
    const node = await NodeService.registerNode({
      node_name,
      ip_address,
      tcp_port
    });
    
    const chainValid = await NodeService.verifyNodeChain();
    
    return res.status(201).json({
      success: true,
      message: 'Node registered successfully',
      data: {
        node_id: node.node_id,
        node_name: node.node_name,
        ip_address: node.ip_address,
        tcp_port: node.tcp_port,
        chain_position: node.chain_position,
        previous_hash: node.previous_hash,
        current_hash: node.current_hash,
        gas_used: node.gas_used,
        gas_price: node.gas_price,
        transaction_fee: node.transaction_fee,
        transaction_time_ms: node.transaction_time_ms,
        chain_valid: chainValid
      }
    });
  } catch (error) {
    console.error('❌ Register node error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to register node',
      message: error.message
    });
  }
});
```

#### 7.2 GET /api/nodes - Get All Nodes

```javascript
/**
 * @route   GET /api/nodes
 * @desc    Get all nodes
 * @access  Public
 */
router.get('/', optionalAuth, async (req, res) => {
  try {
    const nodes = await NodeService.getOnlineNodes();
    
    return res.json({
      success: true,
      count: nodes.length,
      data: nodes
    });
  } catch (error) {
    console.error('❌ Get nodes error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to get nodes',
      message: error.message
    });
  }
});
```

#### 7.3 POST /api/nodes/build-chain - Build Chain Structure

```javascript
/**
 * @route   POST /api/nodes/build-chain
 * @desc    Build chain structure
 * @access  Public
 */
router.post('/build-chain', optionalAuth, async (req, res) => {
  try {
    const chain = await NodeService.buildChain();
    
    return res.json({
      success: true,
      message: 'Chain built successfully',
      data: chain
    });
  } catch (error) {
    console.error('❌ Build chain error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to build chain',
      message: error.message
    });
  }
});
```

---

## 8. Peer-to-Peer APIs

### File: `backend/routes/peers.js`

#### 8.1 POST /api/peers/register - Register Peer

```javascript
const express = require('express');
const router = express.Router();
const { getCollection } = require('../utils/db');

/**
 * @route   POST /api/peers/register
 * @desc    Register peer info (IP + Port) for P2P communication
 * @access  Public
 */
router.post('/register', async (req, res) => {
  try {
    const { user_address, ip_address, port } = req.body;
    
    if (!user_address || !ip_address || !port) {
      return res.status(400).json({
        success: false,
        error: 'user_address, ip_address, and port are required'
      });
    }

    const peersCollection = getCollection('peers');
    const normalizedAddress = user_address.toLowerCase().trim();
    
    // Update or insert peer info
    await peersCollection.updateOne(
      { user_address: normalizedAddress },
      {
        $set: {
          user_address: normalizedAddress,
          ip_address: ip_address,
          port: port,
          last_seen: new Date(),
          updated_at: new Date()
        },
        $setOnInsert: {
          created_at: new Date()
        }
      },
      { upsert: true }
    );

    return res.status(200).json({
      success: true,
      message: 'Peer registered successfully',
      data: {
        user_address: normalizedAddress,
        ip_address: ip_address,
        port: port
      }
    });
  } catch (error) {
    console.error('❌ Register peer error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to register peer',
      message: error.message
    });
  }
});
```

#### 8.2 GET /api/peers/:user_address - Get Peer by Address

```javascript
/**
 * @route   GET /api/peers/:user_address
 * @desc    Get peer info by user address
 * @access  Public
 */
router.get('/:user_address', async (req, res) => {
  try {
    const { user_address } = req.params;
    const peersCollection = getCollection('peers');
    const normalizedAddress = user_address.toLowerCase().trim();
    
    const peer = await peersCollection.findOne({
      user_address: normalizedAddress
    });

    if (!peer) {
      return res.status(404).json({
        success: false,
        error: 'Peer not found'
      });
    }

    return res.status(200).json({
      success: true,
      data: {
        user_address: peer.user_address,
        ip_address: peer.ip_address,
        port: peer.port,
        last_seen: peer.last_seen
      }
    });
  } catch (error) {
    console.error('❌ Get peer error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to get peer',
      message: error.message
    });
  }
});

module.exports = router;
```

---

## 9. Health Check & Root APIs

### File: `backend/server.js`

#### 9.1 GET /health - Health Check

```javascript
const express = require('express');
const app = express();
const database = require('./config/database');

/**
 * @route   GET /health
 * @desc    Health check endpoint
 * @access  Public
 */
app.get('/health', (req, res) => {
  res.json({
    success: true,
    message: 'EtherShare Backend API is running',
    timestamp: new Date().toISOString(),
    database: database.isConnected() ? 'connected' : 'disconnected'
  });
});
```

#### 9.2 GET / - Root Endpoint

```javascript
/**
 * @route   GET /
 * @desc    Root endpoint with API information
 * @access  Public
 */
app.get('/', (req, res) => {
  res.json({
    success: true,
    message: 'Welcome to EtherShare Backend API',
    version: '1.0.0',
    endpoints: {
      health: '/health',
      users: '/api/users',
      workspaces: '/api/workspaces',
      messages: '/api/messages',
      members: '/api/members',
      files: '/api/files',
      nodes: '/api/nodes',
      channels: '/api/channels'
    }
  });
});
```

---

## 10. Server Configuration

### File: `backend/server.js` - Complete Setup

```javascript
require('dotenv').config();
const express = require('express');
const cors = require('cors');
const database = require('./config/database');

// Import routes
const usersRoutes = require('./routes/users');
const workspacesRoutes = require('./routes/workspaces');
const messagesRoutes = require('./routes/messages');
const membersRoutes = require('./routes/members');
const filesRoutes = require('./routes/files');
const nodesRoutes = require('./routes/nodes');
const channelsRoutes = require('./routes/channels');
const peersRoutes = require('./routes/peers');

// Initialize Express app
const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors({
  origin: process.env.CORS_ORIGIN?.split(',') || '*',
  credentials: true
}));

app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Request logging middleware
app.use((req, res, next) => {
  console.log(`📥 ${req.method} ${req.path} - ${new Date().toISOString()}`);
  next();
});

// API Routes
app.use('/api/users', usersRoutes);
app.use('/api/workspaces', workspacesRoutes);
app.use('/api/messages', messagesRoutes);
app.use('/api/members', membersRoutes);
app.use('/api/files', filesRoutes);
app.use('/api/nodes', nodesRoutes);
app.use('/api/channels', channelsRoutes);
app.use('/api/peers', peersRoutes);

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    success: true,
    message: 'EtherShare Backend API is running',
    timestamp: new Date().toISOString(),
    database: database.isConnected() ? 'connected' : 'disconnected'
  });
});

// Root endpoint
app.get('/', (req, res) => {
  res.json({
    success: true,
    message: 'Welcome to EtherShare Backend API',
    version: '1.0.0',
    endpoints: {
      health: '/health',
      users: '/api/users',
      workspaces: '/api/workspaces',
      messages: '/api/messages',
      members: '/api/members',
      files: '/api/files',
      nodes: '/api/nodes',
      channels: '/api/channels'
    }
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    success: false,
    error: 'Route not found',
    message: `Cannot ${req.method} ${req.path}`
  });
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('❌ Server Error:', err);
  res.status(err.status || 500).json({
    success: false,
    error: 'Internal server error',
    message: process.env.NODE_ENV === 'development' ? err.message : 'Something went wrong'
  });
});

// Start server
async function startServer() {
  try {
    await database.connect();
    
    app.listen(PORT, '0.0.0.0', () => {
      console.log('\n' + '='.repeat(60));
      console.log('🚀 EtherShare Backend Server Started');
      console.log('='.repeat(60));
      console.log(`📍 Local: http://localhost:${PORT}`);
      console.log(`🌐 Network: http://${localIP}:${PORT}`);
      console.log('='.repeat(60) + '\n');
    });
  } catch (error) {
    console.error('❌ Failed to start server:', error);
    process.exit(1);
  }
}

startServer();

module.exports = app;
```

---

## Summary

**Total API Endpoints Documented:** 42 REST endpoints  
**Total Code Files:** 8 route files + 1 server file  
**Key Features:**
- Hash Chain Integrity Verification
- Gas Calculation for all write operations
- Comprehensive Error Handling
- Input Validation
- MongoDB Integration
- GridFS for File Storage
- P2P Node Management

**Technology Stack:**
- Express.js (Node.js Framework)
- MongoDB (Database)
- GridFS (File Storage)
- Multer (File Upload)
- Crypto (Hash Chain)

---

**Document Prepared For:** FYP Report  
**Project:** EtherShare - Blockchain-Based Secure File Sharing System  
**Last Updated:** 2024
