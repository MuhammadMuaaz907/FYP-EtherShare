const mongoose = require('mongoose');

/**
 * Ledger Schema - Chain of transactions/blocks
 * Maintains blockchain-like structure
 */
const ledgerSchema = new mongoose.Schema({
  block_id: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  block_number: {
    type: Number,
    required: true,
    index: true
  },
  node_id: {
    type: String,
    required: true,
    index: true
  },
  previous_hash: {
    type: String,
    required: true,
    default: '0' // Genesis block
  },
  current_hash: {
    type: String,
    required: true
  },
  data: {
    type: mongoose.Schema.Types.Mixed,
    required: true
  },
  transaction_type: {
    type: String,
    enum: ['message', 'file', 'user', 'workspace', 'member'],
    required: true
  },
  sender_address: {
    type: String,
    required: true,
    index: true
  },
  receiver_address: {
    type: String,
    index: true
  },
  workspace_id: {
    type: String,
    index: true
  },
  timestamp: {
    type: Number,
    required: true,
    index: true
  },
  verified: {
    type: Boolean,
    default: false
  },
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

// Index for chain traversal
ledgerSchema.index({ block_number: 1, node_id: 1 });
ledgerSchema.index({ previous_hash: 1 });

module.exports = mongoose.model('Ledger', ledgerSchema);

