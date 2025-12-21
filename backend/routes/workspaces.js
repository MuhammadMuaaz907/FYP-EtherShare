const express = require('express');
const router = express.Router();
const { getCollection, getDb } = require('../utils/db');
const { validateWorkspace } = require('../middleware/validation');
const { optionalAuth } = require('../middleware/auth');
const HashChain = require('../utils/hashChain');

/**
 * @route   POST /api/workspaces
 * @desc    Create new workspace with hash chain
 * @access  Public (add auth later)
 */
router.post('/', validateWorkspace, async (req, res) => {
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
    
    // Normalize workspace name and inviter address
    const normalizedName = (workspaceName || '').trim();
    const normalizedInviter = inviterAddress.toLowerCase().trim();
    
    if (!normalizedName || normalizedName.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'Workspace name cannot be empty'
      });
    }
    
    // Check if user already has a workspace with the same name (case-insensitive)
    const existingWorkspace = await workspacesCollection.findOne({
      inviter_address: normalizedInviter,
      name: { $regex: new RegExp(`^${normalizedName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 'i') }
    });
    
    if (existingWorkspace) {
      return res.status(409).json({
        success: false,
        error: 'Workspace name already exists',
        details: `You already have a workspace named "${normalizedName}". Please choose a different name.`,
        existingWorkspace: {
          workspace_id: existingWorkspace.workspace_id,
          name: existingWorkspace.name
        }
      });
    }
    
    // Additional check: Get all user's workspaces and check for duplicates
    const userWorkspaces = await workspacesCollection
      .find({ inviter_address: normalizedInviter })
      .toArray();
    
    const duplicateWorkspace = userWorkspaces.find(ws => 
      (ws.name || '').toLowerCase().trim() === normalizedName.toLowerCase().trim()
    );
    
    if (duplicateWorkspace) {
      return res.status(409).json({
        success: false,
        error: 'Workspace name already exists',
        details: `You already have a workspace named "${normalizedName}". Please choose a different name.`,
        existingWorkspace: {
          workspace_id: duplicateWorkspace.workspace_id,
          name: duplicateWorkspace.name
        }
      });
    }
    
    const timestamp = Date.now();
    const workspaceId = `ws_${normalizedInviter}_${timestamp}`;
    
    const workspaceData = {
      workspace_id: workspaceId,
      name: normalizedName, // Store original case
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
      {
        channel_id: 'general',
        channel_name: 'General',
        is_default: true,
        is_private: false
      },
      {
        channel_id: 'random',
        channel_name: 'Random',
        is_default: true,
        is_private: false
      }
    ];
    
    for (const channelData of defaultChannels) {
      const channelDoc = {
        channel_id: channelData.channel_id,
        workspace_id: workspaceId,
        channel_name: channelData.channel_name,
        creator_address: inviterAddress.toLowerCase().trim(),
        members: [], // Empty means all workspace members
        is_private: channelData.is_private,
        is_default: channelData.is_default,
        created_at: timestamp,
        timestamp: timestamp
      };
      
      // Add hash chain fields for channel
      const channelWithHash = await HashChain.addHashFields(
        channelsCollection,
        channelDoc,
        { workspace_id: workspaceId }
      );
      
      await channelsCollection.insertOne(channelWithHash);
      console.log(`✅ Default channel "${channelData.channel_name}" created for workspace ${workspaceId}`);
    }
    
    console.log(`✅ Workspace created: ${workspaceId}`);
    
    return res.status(201).json({
      success: true,
      message: 'Workspace created successfully',
      data: {
        workspace_id: workspaceId,
        name: workspaceName,
        inviter_address: inviterAddress.toLowerCase().trim(),
        created_at: timestamp
      }
    });
  } catch (error) {
    console.error('❌ Create workspace error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to create workspace',
      message: error.message
    });
  }
});

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
    
    // Get workspace details for memberships
    const workspaceIds = memberships.map(m => m.workspace_id);
    const memberWorkspaces = await workspacesCollection
      .find({ workspace_id: { $in: workspaceIds } })
      .toArray();
    
    // Combine and remove duplicates by workspace_id
    const workspaceMap = new Map();
    
    // Add own workspaces
    for (const workspace of ownWorkspaces) {
      workspaceMap.set(workspace.workspace_id, workspace);
    }
    
    // Add member workspaces
    for (const workspace of memberWorkspaces) {
      if (!workspaceMap.has(workspace.workspace_id)) {
        workspaceMap.set(workspace.workspace_id, workspace);
      }
    }
    
    // Convert map to array and remove duplicates by name (case-insensitive) for same inviter
    const uniqueWorkspaces = [];
    const seenNames = new Set();
    
    for (const workspace of workspaceMap.values()) {
      const workspaceName = (workspace.name || '').toLowerCase().trim();
      const workspaceKey = `${workspace.inviter_address}_${workspaceName}`;
      
      // Only check duplicates for workspaces owned by this user
      if (workspace.inviter_address === address) {
        if (seenNames.has(workspaceKey)) {
          console.warn(`⚠️ Duplicate workspace detected and removed: ${workspace.name} (${workspace.workspace_id})`);
          continue;
        }
        seenNames.add(workspaceKey);
      }
      
      uniqueWorkspaces.push(workspace);
    }
    
    // Clean up response (remove _id and hash fields for client)
    const cleanWorkspaces = uniqueWorkspaces.map(ws => {
      const { _id, previous_hash, current_hash, ...rest } = ws;
      return rest;
    });
    
    console.log(`✅ Found ${cleanWorkspaces.length} workspaces for ${address}`);
    
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
    
    // Remove internal fields
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

/**
 * @route   GET /api/workspaces/resolve/slug
 * @desc    Resolve workspace by slug and inviter address (for invite links)
 * @access  Public
 */
router.get('/resolve/slug', optionalAuth, async (req, res) => {
  try {
    const workspacesCollection = getCollection('workspaces');
    let { workspaceSlug, inviterAddress } = req.query;
    
    if (!workspaceSlug || !inviterAddress) {
      return res.status(400).json({
        success: false,
        error: 'workspaceSlug and inviterAddress are required'
      });
    }
    
    // Decode URL-encoded parameters and normalize
    workspaceSlug = decodeURIComponent(workspaceSlug).toLowerCase().trim();
    const inviter = decodeURIComponent(inviterAddress).toLowerCase().trim();
    
    console.log(`🔍 Resolving workspace: slug="${workspaceSlug}", inviter="${inviter}"`);
    
    // Get all workspaces for the inviter
    const workspaces = await workspacesCollection
      .find({ inviter_address: inviter })
      .toArray();
    
    if (workspaces.length === 0) {
      console.log(`❌ No workspaces found for inviter: ${inviter}`);
      return res.status(404).json({
        success: false,
        error: 'No workspaces found for this inviter address'
      });
    }
    
    console.log(`📋 Found ${workspaces.length} workspace(s) for inviter`);
    
    // Helper function to generate slug from workspace name (must match frontend logic)
    const generateSlug = (name) => {
      if (!name || typeof name !== 'string') {
        return 'workspace';
      }
      return name
        .toLowerCase()
        .trim()
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/-{2,}/g, '-')
        .replace(/^-+|-+$/g, '') || 'workspace';
    };
    
    // Find workspace matching the slug
    let matchingWorkspace = null;
    const slugMatches = [];
    
    for (const ws of workspaces) {
      const wsSlug = generateSlug(ws.name || '');
      const match = wsSlug === workspaceSlug;
      slugMatches.push({ name: ws.name, slug: wsSlug, match });
      
      if (match) {
        matchingWorkspace = ws;
        break;
      }
    }
    
    // Log all slug matches for debugging
    console.log('📊 Slug matching results:');
    slugMatches.forEach((m, i) => {
      console.log(`   ${i + 1}. "${m.name}" -> slug: "${m.slug}" ${m.match ? '✅ MATCH' : '❌'}`);
    });
    
    if (!matchingWorkspace) {
      console.log(`❌ No workspace found matching slug: "${workspaceSlug}"`);
      return res.status(404).json({
        success: false,
        error: 'Workspace not found for this invite link',
        details: {
          searchedSlug: workspaceSlug,
          inviterAddress: inviter,
          availableWorkspaces: workspaces.map(ws => ({
            name: ws.name,
            slug: generateSlug(ws.name)
          }))
        }
      });
    }
    
    // Remove internal fields
    const { _id, previous_hash, current_hash, ...cleanWorkspace } = matchingWorkspace;
    
    console.log(`✅ Resolved workspace by slug: "${workspaceSlug}" -> ${cleanWorkspace.workspace_id} (${cleanWorkspace.name})`);
    
    return res.json({
      success: true,
      data: cleanWorkspace
    });
  } catch (error) {
    console.error('❌ Resolve workspace by slug error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to resolve workspace',
      message: error.message
    });
  }
});

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

