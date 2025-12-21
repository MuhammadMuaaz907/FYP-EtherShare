const express = require('express');
const router = express.Router();
const { getCollection } = require('../utils/db');
const { optionalAuth } = require('../middleware/auth');
const HashChain = require('../utils/hashChain');

/**
 * @route   POST /api/channels
 * @desc    Create new channel in workspace with hash chain
 * @access  Public (add auth later)
 */
router.post('/', optionalAuth, async (req, res) => {
  try {
    const channelsCollection = getCollection('channels');
    const { workspaceId, channelId, channelName, creatorAddress, isPrivate = false } = req.body;
    
    if (!workspaceId || !channelId || !creatorAddress) {
      return res.status(400).json({
        success: false,
        error: 'Workspace ID, Channel ID, and Creator Address are required'
      });
    }
    
    // Normalize channel ID (lowercase, no spaces)
    const normalizedChannelId = channelId.toLowerCase().trim().replace(/\s+/g, '-');
    const displayName = (channelName || normalizedChannelId).trim();
    
    // Normalize channel name for comparison (case-insensitive)
    const normalizedChannelName = displayName.toLowerCase().trim();
    
    // Check if channel ID already exists in this workspace
    const existingChannelById = await channelsCollection.findOne({
      workspace_id: workspaceId,
      channel_id: normalizedChannelId,
      deleted: { $ne: true }
    });
    
    if (existingChannelById) {
      return res.status(409).json({
        success: false,
        error: 'Channel with this ID already exists in this workspace',
        details: 'A channel with this name or ID already exists'
      });
    }
    
    // Check if channel name already exists in this workspace (case-insensitive)
    const existingChannelByName = await channelsCollection.findOne({
      workspace_id: workspaceId,
      $or: [
        { channel_name: { $regex: new RegExp(`^${normalizedChannelName}$`, 'i') } },
        { channel_id: normalizedChannelName }
      ],
      deleted: { $ne: true }
    });
    
    if (existingChannelByName) {
      return res.status(409).json({
        success: false,
        error: 'Channel name already exists in this workspace',
        details: `A channel named "${displayName}" already exists. Please choose a different name.`
      });
    }
    
    // Additional check: prevent creating channels with reserved names (case-insensitive)
    const reservedNames = ['general', 'random'];
    if (reservedNames.includes(normalizedChannelId) || reservedNames.includes(normalizedChannelName)) {
      return res.status(400).json({
        success: false,
        error: 'Reserved channel name',
        details: 'General and Random are reserved channel names and cannot be used'
      });
    }
    
    const timestamp = Date.now();
    
    // Default channels are accessible to all workspace members
    const isDefault = ['general', 'random'].includes(normalizedChannelId);
    
    const channelData = {
      channel_id: normalizedChannelId,
      workspace_id: workspaceId,
      channel_name: displayName,
      creator_address: creatorAddress.toLowerCase().trim(),
      members: isDefault ? [] : [creatorAddress.toLowerCase().trim()], // Empty array means all workspace members
      is_private: isPrivate && !isDefault, // Default channels can't be private
      is_default: isDefault,
      created_at: timestamp,
      timestamp: timestamp
    };
    
    // Add hash chain fields
    // Note: Each channel is an independent document, not part of a sequential chain
    // The hash chain is for integrity verification of the channel document itself
    // Messages within each channel maintain their own separate chain (filtered by channel_id)
    const channelWithHash = await HashChain.addHashFields(
      channelsCollection,
      channelData,
      { workspace_id: workspaceId } // Filter for getting previous hash in workspace context
    );
    
    // Insert channel
    await channelsCollection.insertOne(channelWithHash);
    
    console.log(`✅ Channel created: ${normalizedChannelId} in workspace ${workspaceId}`);
    
    // Remove internal fields from response
    const { _id, previous_hash, current_hash, ...cleanChannel } = channelWithHash;
    
    return res.status(201).json({
      success: true,
      message: 'Channel created successfully',
      data: cleanChannel
    });
  } catch (error) {
    console.error('❌ Create channel error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to create channel',
      message: error.message
    });
  }
});

/**
 * @route   GET /api/channels/workspace/:workspaceId
 * @desc    Get all channels for a workspace
 * @access  Public
 */
router.get('/workspace/:workspaceId', optionalAuth, async (req, res) => {
  try {
    const channelsCollection = getCollection('channels');
    const { workspaceId } = req.params;
    const { memberAddress } = req.query; // Optional: filter by member access
    
    // Get all channels for this workspace (exclude deleted)
    let query = { 
      workspace_id: workspaceId,
      deleted: { $ne: true } // Exclude deleted channels
    };
    
    // If member address provided, filter channels accessible to this member
    if (memberAddress) {
      const memberAddr = memberAddress.toLowerCase().trim();
      query = {
        workspace_id: workspaceId,
        deleted: { $ne: true },
        $or: [
          { is_default: true }, // Default channels are accessible to all
          { is_private: false }, // Public channels
          { members: { $in: [memberAddr] } }, // Member is in members list
          { members: { $size: 0 } } // Empty members array means all workspace members
        ]
      };
    }
    
    let channels = await channelsCollection
      .find(query)
      .toArray();
    
    // Remove duplicates based on channel_id (case-insensitive)
    const uniqueChannels = [];
    const seenChannelIds = new Set();
    
    for (const channel of channels) {
      const channelId = (channel.channel_id || '').toLowerCase().trim();
      if (!seenChannelIds.has(channelId)) {
        seenChannelIds.add(channelId);
        uniqueChannels.push(channel);
      } else {
        console.warn(`⚠️ Duplicate channel detected and removed: ${channelId} in workspace ${workspaceId}`);
      }
    }
    
    channels = uniqueChannels;
    
    // Ensure default channels (General and Random) exist
    const defaultChannels = [
      { channel_id: 'general', channel_name: 'General' },
      { channel_id: 'random', channel_name: 'Random' }
    ];
    
    for (const defaultChannel of defaultChannels) {
      const exists = channels.find(ch => 
        ch.channel_id === defaultChannel.channel_id && 
        ch.workspace_id === workspaceId
      );
      
      if (!exists) {
        // Create missing default channel
        const timestamp = Date.now();
        const channelDoc = {
          channel_id: defaultChannel.channel_id,
          workspace_id: workspaceId,
          channel_name: defaultChannel.channel_name,
          creator_address: 'system', // System-created
          members: [], // Empty means all workspace members
          is_private: false,
          is_default: true,
          created_at: timestamp,
          timestamp: timestamp
        };
        
        // Add hash chain fields
        const channelWithHash = await HashChain.addHashFields(
          channelsCollection,
          channelDoc,
          { workspace_id: workspaceId }
        );
        
        await channelsCollection.insertOne(channelWithHash);
        console.log(`✅ Auto-created default channel "${defaultChannel.channel_name}" for workspace ${workspaceId}`);
        
        // Add to channels array
        const { _id, previous_hash, current_hash, ...cleanChannel } = channelWithHash;
        channels.push(cleanChannel);
      }
    }
    
    // Sort channels: General first, Random second, then user-created channels
    channels.sort((a, b) => {
      const aId = (a.channel_id || '').toLowerCase();
      const bId = (b.channel_id || '').toLowerCase();
      
      // General always first
      if (aId === 'general') return -1;
      if (bId === 'general') return 1;
      
      // Random always second
      if (aId === 'random') return -1;
      if (bId === 'random') return 1;
      
      // Default channels before user-created
      if (a.is_default === true && b.is_default !== true) return -1;
      if (a.is_default !== true && b.is_default === true) return 1;
      
      // Then by creation time
      const aTime = a.created_at || 0;
      const bTime = b.created_at || 0;
      return aTime - bTime;
    });
    
    // Clean up response
    const cleanChannels = channels.map(ch => {
      const { _id, previous_hash, current_hash, ...rest } = ch;
      return rest;
    });
    
    console.log(`✅ Retrieved ${cleanChannels.length} channels for workspace ${workspaceId}`);
    console.log(`📋 Channel order: ${cleanChannels.map(ch => ch.channel_name || ch.channel_id).join(' → ')}`);
    
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

/**
 * @route   GET /api/channels/:channelId
 * @desc    Get channel by ID
 * @access  Public
 */
router.get('/:channelId', optionalAuth, async (req, res) => {
  try {
    const channelsCollection = getCollection('channels');
    const { channelId } = req.params;
    const { workspaceId } = req.query;
    
    if (!workspaceId) {
      return res.status(400).json({
        success: false,
        error: 'Workspace ID is required'
      });
    }
    
    const normalizedChannelId = channelId.toLowerCase().trim();
    
    const channel = await channelsCollection.findOne({
      workspace_id: workspaceId,
      channel_id: normalizedChannelId
    });
    
    if (!channel) {
      return res.status(404).json({
        success: false,
        error: 'Channel not found'
      });
    }
    
    // Remove internal fields
    const { _id, previous_hash, current_hash, ...cleanChannel } = channel;
    
    return res.json({
      success: true,
      data: cleanChannel
    });
  } catch (error) {
    console.error('❌ Get channel error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to get channel',
      message: error.message
    });
  }
});

/**
 * @route   POST /api/channels/:channelId/members
 * @desc    Add member to channel
 * @access  Public
 */
router.post('/:channelId/members', optionalAuth, async (req, res) => {
  try {
    const channelsCollection = getCollection('channels');
    const { channelId } = req.params;
    const { workspaceId, memberAddress } = req.body;
    
    if (!workspaceId || !memberAddress) {
      return res.status(400).json({
        success: false,
        error: 'Workspace ID and Member Address are required'
      });
    }
    
    const normalizedChannelId = channelId.toLowerCase().trim();
    const memberAddr = memberAddress.toLowerCase().trim();
    
    const channel = await channelsCollection.findOne({
      workspace_id: workspaceId,
      channel_id: normalizedChannelId
    });
    
    if (!channel) {
      return res.status(404).json({
        success: false,
        error: 'Channel not found'
      });
    }
    
    // Default channels don't need explicit member addition (all workspace members have access)
    if (channel.is_default) {
      return res.json({
        success: true,
        message: 'Default channels are accessible to all workspace members',
        data: channel
      });
    }
    
    // Check if member already in channel
    const members = channel.members || [];
    if (members.includes(memberAddr)) {
      return res.json({
        success: true,
        message: 'Member already in channel',
        data: channel
      });
    }
    
    // Add member to channel
    await channelsCollection.updateOne(
      { workspace_id: workspaceId, channel_id: normalizedChannelId },
      { 
        $addToSet: { members: memberAddr },
        $set: { updated_at: Date.now() }
      }
    );
    
    console.log(`✅ Member ${memberAddr} added to channel ${normalizedChannelId}`);
    
    // Get updated channel
    const updatedChannel = await channelsCollection.findOne({
      workspace_id: workspaceId,
      channel_id: normalizedChannelId
    });
    
    const { _id, previous_hash, current_hash, ...cleanChannel } = updatedChannel;
    
    return res.json({
      success: true,
      message: 'Member added to channel',
      data: cleanChannel
    });
  } catch (error) {
    console.error('❌ Add channel member error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to add member to channel',
      message: error.message
    });
  }
});

/**
 * @route   DELETE /api/channels/:channelId
 * @desc    Delete channel (soft delete by marking as deleted)
 * @access  Public
 */
router.delete('/:channelId', optionalAuth, async (req, res) => {
  try {
    const channelsCollection = getCollection('channels');
    const { channelId } = req.params;
    const { workspaceId } = req.query;
    
    if (!workspaceId) {
      return res.status(400).json({
        success: false,
        error: 'Workspace ID is required'
      });
    }
    
    const normalizedChannelId = channelId.toLowerCase().trim();
    
    // Don't allow deletion of default channels
    const channel = await channelsCollection.findOne({
      workspace_id: workspaceId,
      channel_id: normalizedChannelId
    });
    
    if (!channel) {
      return res.status(404).json({
        success: false,
        error: 'Channel not found'
      });
    }
    
    if (channel.is_default) {
      return res.status(403).json({
        success: false,
        error: 'Default channels cannot be deleted'
      });
    }
    
    // Soft delete: mark as deleted
    await channelsCollection.updateOne(
      { workspace_id: workspaceId, channel_id: normalizedChannelId },
      { 
        $set: { 
          deleted: true,
          deleted_at: Date.now()
        }
      }
    );
    
    console.log(`✅ Channel ${normalizedChannelId} deleted from workspace ${workspaceId}`);
    
    return res.json({
      success: true,
      message: 'Channel deleted successfully'
    });
  } catch (error) {
    console.error('❌ Delete channel error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to delete channel',
      message: error.message
    });
  }
});

/**
 * @route   POST /api/channels/:channelId/verify
 * @desc    Verify channel hash chain integrity
 * @access  Public
 */
router.post('/:channelId/verify', optionalAuth, async (req, res) => {
  try {
    const channelsCollection = getCollection('channels');
    const { channelId } = req.params;
    const { workspaceId } = req.query;
    
    if (!workspaceId) {
      return res.status(400).json({
        success: false,
        error: 'Workspace ID is required'
      });
    }
    
    const normalizedChannelId = channelId.toLowerCase().trim();
    
    const isValid = await HashChain.verifyChainIntegrity(
      channelsCollection,
      { workspace_id: workspaceId, channel_id: normalizedChannelId }
    );
    
    return res.json({
      success: true,
      data: {
        workspace_id: workspaceId,
        channel_id: normalizedChannelId,
        chain_valid: isValid
      }
    });
  } catch (error) {
    console.error('❌ Verify channel chain error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to verify channel chain',
      message: error.message
    });
  }
});

module.exports = router;

