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
  created_at: {
    type: Date,
    default: Date.now
  }
}, {
  timestamps: true
});

module.exports = mongoose.model('Node', nodeSchema);

