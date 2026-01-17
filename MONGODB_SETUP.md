# MongoDB Setup Guide for EtherShare

## Installation

### Windows
1. Download MongoDB Community Server from: https://www.mongodb.com/try/download/community
2. Run the installer
3. Select "Complete" installation type
4. Choose "Run service as Network Service user"
5. Install MongoDB Compass (GUI tool) - optional but recommended
6. Default installation path: `C:\Program Files\MongoDB\Server\7.0\bin\`

### Verify Installation
```powershell
# Add MongoDB to PATH (if not already)
$env:PATH += ";C:\Program Files\MongoDB\Server\7.0\bin"

# Test MongoDB
mongod --version

# Start MongoDB service (should start automatically)
net start MongoDB
```

## Configuration for EtherShare

The app is configured to use:
- **Host**: localhost
- **Port**: 27017 (default)
- **Database**: EtherShare
- **Connection**: `mongodb://localhost:27017/EtherShare`

### If MongoDB requires authentication:
Update `mongodb_service.dart`:
```dart
static const String username = 'your_username';
static const String password = 'your_password';
static String get connectionString => 
  'mongodb://$username:$password@$host:$port/$databaseName';
```

## Testing MongoDB Connection

### Method 1: MongoDB Compass (GUI)
1. Open MongoDB Compass
2. Connect to: `mongodb://localhost:27017`
3. You should see the connection successful
4. Database `EtherShare` will be created automatically when first data is inserted

### Method 2: Command Line
```powershell
# Connect to MongoDB shell
mongosh

# Show databases
show dbs

# Use EtherShare database
use EtherShare

# Show collections (will be empty initially)
show collections
```

## Database Schema

The app creates these collections automatically:

### users
```javascript
{
  address: String (primary key),
  username: String,
  email: String,
  created_at: Number,
  updated_at: Number
}
```

### workspaces
```javascript
{
  workspace_id: String (primary key),
  name: String,
  inviter_address: String,
  created_at: Number,
  timestamp: Number,
  previous_hash: String,  // Blockchain chain
  current_hash: String    // Hash of data
}
```

### messages
```javascript
{
  message_id: String (primary key),
  workspace_id: String,
  channel_id: String (optional),
  sender_address: String,
  receiver_address: String (for DMs),
  payload_hash: String,  // SHA-256 hash of message_text (not stored in MongoDB)
  hash_version: Number,   // Hash version (1 = legacy with message_text, 2 = payload_hash only)
  file_id: String (optional),
  timestamp: Number,
  previous_hash: String,  // Blockchain chain
  current_hash: String    // Hash of data
}
```

### members
```javascript
{
  workspace_id: String,
  member_address: String,
  display_name: String,
  joined_at: Number
}
```

### files
```javascript
{
  file_id: String (primary key),
  filename: String,
  workspace_id: String,
  uploader_address: String,
  gridfs_id: String,      // Reference to GridFS
  file_size: Number,
  upload_timestamp: Number
}
```

### fs.files & fs.chunks (GridFS)
Automatically created by MongoDB for file storage

## Blockchain-like Chain

Every workspace and message has:
- **previous_hash**: Hash of previous record
- **current_hash**: SHA-256 hash of current data + previous hash

### Verify Chain Integrity
```dart
// In your code
final isValid = await MongoDBService.verifyChainIntegrity('messages');
print('Chain is valid: $isValid');
```

If someone modifies data, the chain breaks and verification fails! 🔒

## Troubleshooting

### Connection Failed
```
❌ MongoDB: Connection failed - Error: connect ECONNREFUSED 127.0.0.1:27017
```
**Solution**: Start MongoDB service
```powershell
net start MongoDB
```

### Authentication Failed
```
❌ MongoDB: Connection failed - Authentication failed
```
**Solution**: Update connection string with correct username/password

### Database Not Found
This is normal! MongoDB creates databases automatically when first data is inserted.

## Next Steps

1. ✅ Start MongoDB service
2. ✅ Run your Flutter app
3. ✅ Create a user profile - this will create the database
4. ✅ Check MongoDB Compass to see the `EtherShare` database appear
5. ✅ View collections and data in Compass

## MongoDB Compass Tips

- **Connection String**: `mongodb://localhost:27017`
- **View Data**: Navigate to EtherShare database → collections
- **Query Data**: Use the filter bar to search
- **Verify Hashes**: Check `previous_hash` and `current_hash` fields
- **Monitor**: See real-time updates as app creates data

## Performance Tips

Indexes are automatically created for:
- `users.address` (unique)
- `workspaces.workspace_id` (unique)
- `messages.timestamp` (for sorting)

This ensures fast queries! 🚀
