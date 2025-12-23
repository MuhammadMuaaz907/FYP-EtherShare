const express = require('express');
const router = express.Router();
const NodeService = require('../services/nodeService');
const LedgerService = require('../services/ledgerService');
const { optionalAuth } = require('../middleware/auth');

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
    
    // Verify chain after registration
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
        transaction_fee: node.transaction_fee,
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
 * @desc    Verify ledger chain integrity for a node
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
 * @route   POST /api/nodes/verify-chain
 * @desc    Verify node chain integrity (blockchain-like)
 * @access  Public
 */
router.post('/verify-chain', optionalAuth, async (req, res) => {
  try {
    const isValid = await NodeService.verifyNodeChain();
    
    return res.json({
      success: true,
      data: {
        chain_valid: isValid,
        message: isValid ? 'Node chain is valid' : 'Node chain integrity compromised'
      }
    });
  } catch (error) {
    console.error('❌ Verify node chain error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to verify node chain',
      message: error.message
    });
  }
});

/**
 * @route   PUT /api/nodes/:nodeId
 * @desc    Update node (blockchain-like: creates new node, deprecates old)
 * @access  Public
 */
router.put('/:nodeId', optionalAuth, async (req, res) => {
  try {
    const { nodeId } = req.params;
    const updateData = req.body;
    
    // Update node (creates new node, deprecates old)
    const newNode = await NodeService.updateNode(nodeId, updateData);
    
    return res.json({
      success: true,
      message: 'Node updated successfully (new node created)',
      data: {
        old_node_id: nodeId,
        new_node_id: newNode.node_id,
        gas_used: newNode.gas_used,
        transaction_fee: newNode.transaction_fee,
        current_hash: newNode.current_hash.substring(0, 16) + '...'
      }
    });
  } catch (error) {
    console.error('❌ Update node error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to update node',
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

/**
 * @route   DELETE /api/nodes/clean
 * @desc    Clean all nodes from database (for testing)
 * @access  Public
 */
router.delete('/clean', optionalAuth, async (req, res) => {
  try {
    const Node = require('../models/node');
    const result = await Node.deleteMany({});
    
    return res.json({
      success: true,
      message: 'All nodes deleted successfully',
      deleted_count: result.deletedCount
    });
  } catch (error) {
    console.error('❌ Clean nodes error:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to clean nodes',
      message: error.message
    });
  }
});

module.exports = router;

