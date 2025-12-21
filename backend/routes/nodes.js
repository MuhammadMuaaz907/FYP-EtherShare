const express = require('express');
const router = express.Router();
const NodeService = require('../services/nodeService');
const LedgerService = require('../services/ledgerService');
const { optionalAuth } = require('../middleware/auth');

/**
 * @route   POST /api/nodes/register
 * @desc    Register a new node
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
    
    return res.status(201).json({
      success: true,
      message: 'Node registered successfully',
      data: node
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

/**
 * @route   GET /api/nodes/chain
 * @desc    Get chain structure
 * @access  Public
 */
router.get('/chain', optionalAuth, async (req, res) => {
  try {
    const chain = await NodeService.getChain();
    
    return res.json({
      success: true,
      data: chain
    });
  } catch (error) {
    console.error('❌ Get chain error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to get chain',
      message: error.message
    });
  }
});

/**
 * @route   POST /api/nodes/:nodeId/ledger
 * @desc    Add block to node ledger
 * @access  Public
 */
router.post('/:nodeId/ledger', optionalAuth, async (req, res) => {
  try {
    const { nodeId } = req.params;
    const transactionData = req.body;
    
    const block = await LedgerService.addBlock(nodeId, transactionData);
    
    return res.status(201).json({
      success: true,
      message: 'Block added to ledger',
      data: block
    });
  } catch (error) {
    console.error('❌ Add block error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to add block',
      message: error.message
    });
  }
});

/**
 * @route   GET /api/nodes/:nodeId/ledger
 * @desc    Get node ledger
 * @access  Public
 */
router.get('/:nodeId/ledger', optionalAuth, async (req, res) => {
  try {
    const { nodeId } = req.params;
    const { limit = 100 } = req.query;
    
    const ledger = await LedgerService.getLedger(nodeId, parseInt(limit));
    
    return res.json({
      success: true,
      count: ledger.length,
      data: ledger
    });
  } catch (error) {
    console.error('❌ Get ledger error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to get ledger',
      message: error.message
    });
  }
});

/**
 * @route   POST /api/nodes/:nodeId/verify
 * @desc    Verify chain integrity
 * @access  Public
 */
router.post('/:nodeId/verify', optionalAuth, async (req, res) => {
  try {
    const { nodeId } = req.params;
    
    const isValid = await LedgerService.verifyChain(nodeId);
    
    return res.json({
      success: true,
      data: {
        node_id: nodeId,
        chain_valid: isValid
      }
    });
  } catch (error) {
    console.error('❌ Verify chain error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to verify chain',
      message: error.message
    });
  }
});

/**
 * @route   GET /api/nodes/messages/:userA/:userB
 * @desc    Get messages between two users
 * @access  Public
 */
router.get('/messages/:userA/:userB', optionalAuth, async (req, res) => {
  try {
    const { userA, userB } = req.params;
    const { nodeId } = req.query;
    
    const messages = await LedgerService.getMessagesBetweenUsers(userA, userB, nodeId);
    
    return res.json({
      success: true,
      count: messages.length,
      data: messages
    });
  } catch (error) {
    console.error('❌ Get messages error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to get messages',
      message: error.message
    });
  }
});

module.exports = router;

