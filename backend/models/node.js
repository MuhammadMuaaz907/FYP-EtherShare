const mongoose = require('mongoose');

/**
 * Node Schema - Represents a node in the distributed network
 */
const nodeSchema = new mongoose.Schema({
  node_id: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  node_name: {
    type: String,
    required: true
  },
  ip_address: {
    type: String,
    required: true
  },
  tcp_port: {
    type: Number,
    required: true,
    default: 3001
  },
  public_key: {
    type: String,
    required: true
  },
  status: {
    type: String,
    enum: ['online', 'offline', 'syncing'],
    default: 'offline'
  },
  last_seen: {
    type: Date,
    default: Date.now
  },
  connected_nodes: [{
    node_id: String,
    connection_type: {
      type: String,
      enum: ['tcp', 'http']
    },
    last_connected: Date
  }],
  chain_position: {
    type: Number,
    default: 0
  },
  previous_node_id: {
    type: String,
    default: null
  },
  next_node_id: {
    type: String,
    default: null
  },
  // Blockchain-like hash chain fields
  previous_hash: {
    type: String,
    required: true,
    default: '0' // Genesis node
  },
  current_hash: {
    type: String,
    required: true
  },
  // Gas calculation (like real blockchain)
  gas_used: {
    type: Number,
    default: 0
  },
  gas_price: {
    type: Number,
    default: 1 // Base gas price
  },
  transaction_fee: {
    type: Number,
    default: 0 // Calculated as gas_used * gas_price
  },
  // Immutability - if node is modified, mark as deprecated
  is_deprecated: {
    type: Boolean,
    default: false
  },
  deprecated_by: {
    type: String, // New node_id that replaced this one
    default: null
  },
  deprecated_at: {
    type: Date,
    default: null
  },
  // Chain integrity
  chain_broken: {
    type: Boolean,
    default: false
  },
  created_at: {
    type: Date,
    default: Date.now
  }
}, {
  timestamps: true
});

// Indexes for blockchain-like operations
nodeSchema.index({ previous_hash: 1 });
nodeSchema.index({ current_hash: 1 });
nodeSchema.index({ chain_position: 1, is_deprecated: 1 });
nodeSchema.index({ is_deprecated: 1 });

module.exports = mongoose.model('Node', nodeSchema);

