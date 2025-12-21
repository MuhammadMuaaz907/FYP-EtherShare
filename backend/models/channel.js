/**
 * Channel Model Schema (for reference)
 * Channels are stored in MongoDB 'channels' collection
 * 
 * Schema Structure:
 * {
 *   channel_id: String (unique, e.g., "general", "random", "test-channel")
 *   workspace_id: String (references workspace)
 *   channel_name: String (display name, e.g., "General", "Test Channel")
 *   creator_address: String (address of user who created the channel)
 *   members: Array<String> (array of member addresses who can access this channel)
 *   is_private: Boolean (default: false, if true, only members can see)
 *   is_default: Boolean (default: false, true for "general" and "random")
 *   created_at: Number (timestamp)
 *   timestamp: Number (timestamp for hash chain)
 *   previous_hash: String (hash of previous channel in chain)
 *   current_hash: String (hash of this channel document)
 * }
 * 
 * Indexes:
 * - channel_id (unique)
 * - workspace_id + channel_id (compound unique)
 * - workspace_id
 * - creator_address
 */

module.exports = {
  // This is a reference schema - actual implementation uses MongoDB native driver
  // See backend/routes/channels.js for implementation
};

