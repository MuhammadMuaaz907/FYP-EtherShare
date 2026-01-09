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

/**
 * @route   GET /api/peers/workspace/:workspace_id
 * @desc    Get all peers in a workspace (for P2P discovery)
 * @access  Public
 */
router.get('/workspace/:workspace_id', async (req, res) => {
  try {
    const { workspace_id } = req.params;
    const membersCollection = getCollection('members');
    const peersCollection = getCollection('peers');
    
    // Get all members of the workspace
    const members = await membersCollection.find({
      workspace_id: workspace_id
    }).toArray();

    if (!members || members.length === 0) {
      return res.status(200).json({
        success: true,
        data: []
      });
    }

    // Get peer info for all members
    const memberAddresses = members.map(m => m.member_address.toLowerCase());
    const peers = await peersCollection.find({
      user_address: { $in: memberAddresses }
    }).toArray();

    const peerList = peers.map(peer => ({
      user_address: peer.user_address,
      ip_address: peer.ip_address,
      port: peer.port,
      last_seen: peer.last_seen
    }));

    return res.status(200).json({
      success: true,
      data: peerList
    });
  } catch (error) {
    console.error('❌ Get workspace peers error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to get workspace peers',
      message: error.message
    });
  }
});

/**
 * @route   GET /api/peers
 * @desc    Get all registered peers
 * @access  Public
 */
router.get('/', async (req, res) => {
  try {
    const peersCollection = getCollection('peers');
    
    // Get peers seen in last 5 minutes (active peers)
    const fiveMinutesAgo = new Date(Date.now() - 5 * 60 * 1000);
    const peers = await peersCollection.find({
      last_seen: { $gte: fiveMinutesAgo }
    }).toArray();

    const peerList = peers.map(peer => ({
      user_address: peer.user_address,
      ip_address: peer.ip_address,
      port: peer.port,
      last_seen: peer.last_seen
    }));

    return res.status(200).json({
      success: true,
      data: peerList
    });
  } catch (error) {
    console.error('❌ Get all peers error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to get peers',
      message: error.message
    });
  }
});

module.exports = router;

