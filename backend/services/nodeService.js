const Node = require('../models/node');
const crypto = require('crypto');

/**
 * Node Service - Manages distributed nodes
 */
class NodeService {
  /**
   * Register a new node in the network
   */
  static async registerNode(nodeData) {
    try {
      const nodeId = `node_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`;
      
      const node = new Node({
        node_id: nodeId,
        node_name: nodeData.node_name || `Node-${nodeId.slice(-6)}`,
        ip_address: nodeData.ip_address,
        tcp_port: nodeData.tcp_port || 3001,
        public_key: nodeData.public_key || crypto.randomBytes(32).toString('hex'),
        status: 'online',
        last_seen: new Date(),
        chain_position: 0
      });
      
      await node.save();
      
      console.log(`✅ Node registered: ${nodeId}`);
      return node;
    } catch (error) {
      console.error('❌ Node registration error:', error);
      throw error;
    }
  }

  /**
   * Get all online nodes
   */
  static async getOnlineNodes() {
    try {
      const nodes = await Node.find({ status: 'online' })
        .sort({ chain_position: 1 })
        .lean();
      
      return nodes;
    } catch (error) {
      console.error('❌ Get online nodes error:', error);
      throw error;
    }
  }

  /**
   * Build chain structure - Connect nodes in sequence
   */
  static async buildChain() {
    try {
      const nodes = await Node.find({ status: 'online' })
        .sort({ created_at: 1 })
        .lean();
      
      if (nodes.length === 0) {
        return { message: 'No nodes available' };
      }
      
      // Connect nodes in chain: Node1 → Node2 → Node3
      for (let i = 0; i < nodes.length; i++) {
        const node = nodes[i];
        const updates = {
          chain_position: i,
          last_seen: new Date()
        };
        
        if (i > 0) {
          updates.previous_node_id = nodes[i - 1].node_id;
        }
        
        if (i < nodes.length - 1) {
          updates.next_node_id = nodes[i + 1].node_id;
        }
        
        await Node.updateOne(
          { node_id: node.node_id },
          { $set: updates }
        );
      }
      
      console.log(`✅ Chain built with ${nodes.length} nodes`);
      return {
        chain_length: nodes.length,
        nodes: nodes.map(n => ({
          node_id: n.node_id,
          position: n.chain_position,
          previous: n.previous_node_id,
          next: n.next_node_id
        }))
      };
    } catch (error) {
      console.error('❌ Build chain error:', error);
      throw error;
    }
  }

  /**
   * Get chain structure
   */
  static async getChain() {
    try {
      const nodes = await Node.find({ status: 'online' })
        .sort({ chain_position: 1 })
        .select('node_id node_name ip_address tcp_port chain_position previous_node_id next_node_id status')
        .lean();
      
      return {
        chain: nodes,
        length: nodes.length
      };
    } catch (error) {
      console.error('❌ Get chain error:', error);
      throw error;
    }
  }

  /**
   * Update node status
   */
  static async updateNodeStatus(nodeId, status) {
    try {
      await Node.updateOne(
        { node_id: nodeId },
        { 
          $set: { 
            status: status,
            last_seen: new Date()
          }
        }
      );
      
      return { success: true };
    } catch (error) {
      console.error('❌ Update node status error:', error);
      throw error;
    }
  }
}

module.exports = NodeService;

