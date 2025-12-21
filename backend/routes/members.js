const express = require('express');
const router = express.Router();
const { getCollection } = require('../utils/db');
const { validateMember } = require('../middleware/validation');
const { optionalAuth } = require('../middleware/auth');

/**
 * @route   POST /api/members
 * @desc    Add workspace member
 * @access  Public (add auth later)
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
    
    console.log(`✅ Member added to workspace: ${workspaceId}`);
    
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
    
    // Clean up response
    const cleanMembers = members.map(member => {
      const { _id, ...rest } = member;
      return rest;
    });
    
    console.log(`✅ Retrieved ${cleanMembers.length} workspace members`);
    
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

/**
 * @route   DELETE /api/members
 * @desc    Remove member from workspace
 * @access  Public (add auth later)
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
    
    console.log(`✅ Member removed from workspace: ${workspaceId}`);
    
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

