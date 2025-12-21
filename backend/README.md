# 🚀 EtherShare Backend API

Professional Node.js backend for EtherShare - Blockchain-based File Sharing and Communication System.

## 📋 Features

- ✅ **RESTful API** with Express.js
- ✅ **MongoDB Integration** with Mongoose
- ✅ **Hash Chain Verification** (Blockchain-like integrity)
- ✅ **File Upload** with GridFS
- ✅ **JWT Authentication** (Ready to use)
- ✅ **Input Validation** with express-validator
- ✅ **CORS Support** for Flutter app
- ✅ **Error Handling** with proper error responses
- ✅ **MongoDB Compass Compatible** - Works perfectly with MongoDB Compass

## 🛠️ Tech Stack

- **Node.js** - Runtime environment
- **Express.js** - Web framework
- **MongoDB** - Database (works with MongoDB Compass)
- **Mongoose** - MongoDB ODM
- **JWT** - Authentication tokens
- **Multer** - File upload handling
- **GridFS** - Large file storage

## 📦 Installation

### 1. Install Dependencies

```bash
cd backend
npm install
```

### 2. Setup Environment Variables

Copy `.env.example` to `.env`:

```bash
cp .env.example .env
```

Edit `.env` file:

```env
PORT=3000
NODE_ENV=development

# MongoDB Configuration
MONGODB_URI=mongodb://localhost:27017/EtherShare

# JWT Secret (Change this!)
JWT_SECRET=your_super_secret_jwt_key_change_this
JWT_EXPIRES_IN=7d

# CORS
CORS_ORIGIN=http://localhost:3000,http://localhost:8080

# File Upload
MAX_FILE_SIZE=10485760
UPLOAD_PATH=./uploads
```

### 3. Start MongoDB

Make sure MongoDB is running:

**Windows:**
```powershell
net start MongoDB
```

**Mac/Linux:**
```bash
sudo systemctl start mongod
# or
mongod --dbpath /path/to/data
```

**Verify in MongoDB Compass:**
- Open MongoDB Compass
- Connect to: `mongodb://localhost:27017`
- You should see connection successful ✅

## 🚀 Running the Server

### Development Mode (with auto-reload)

```bash
npm run dev
```

### Production Mode

```bash
npm start
```

Server will start on: `http://localhost:3000`

## 📡 API Endpoints

### Health Check
```
GET /health
```

### Users
```
POST   /api/users/profile          - Create/Update user profile
GET    /api/users/profile/:address - Get user profile
GET    /api/users/search           - Search users
```

### Workspaces
```
POST   /api/workspaces                    - Create workspace
GET    /api/workspaces/user/:address       - Get user workspaces
GET    /api/workspaces/:workspaceId        - Get workspace
POST   /api/workspaces/:workspaceId/verify - Verify hash chain
```

### Messages
```
POST   /api/messages                      - Send message
GET    /api/messages/channel              - Get channel messages
GET    /api/messages/direct               - Get direct messages
GET    /api/messages/workspace/:workspaceId - Get workspace messages
```

### Members
```
POST   /api/members                       - Add member
GET    /api/members/workspace/:workspaceId - Get workspace members
DELETE /api/members                       - Remove member
```

### Files
```
POST   /api/files/upload                  - Upload file
GET    /api/files/:fileId                 - Get file metadata
GET    /api/files/:fileId/download        - Download file
GET    /api/files/workspace/:workspaceId  - Get workspace files
```

## 🧪 Testing with Postman/Thunder Client

### Example: Create User Profile

```http
POST http://localhost:3000/api/users/profile
Content-Type: application/json

{
  "address": "0x1234567890123456789012345678901234567890",
  "username": "john_doe",
  "email": "john@example.com"
}
```

### Example: Create Workspace

```http
POST http://localhost:3000/api/workspaces
Content-Type: application/json

{
  "workspaceName": "My Workspace",
  "inviterAddress": "0x1234567890123456789012345678901234567890"
}
```

### Example: Send Message

```http
POST http://localhost:3000/api/messages
Content-Type: application/json

{
  "workspaceId": "ws_0x123..._1234567890",
  "senderAddress": "0x1234567890123456789012345678901234567890",
  "messageText": "Hello, World!",
  "channelId": "general"
}
```

## 📊 MongoDB Compass Integration

### Viewing Data in MongoDB Compass

1. **Open MongoDB Compass**
2. **Connect to:** `mongodb://localhost:27017`
3. **Navigate to:** `EtherShare` database
4. **View Collections:**
   - `users` - User profiles
   - `workspaces` - Workspaces with hash chains
   - `messages` - Messages with hash chains
   - `members` - Workspace members
   - `files` - File metadata
   - `files.files` - GridFS file metadata
   - `files.chunks` - GridFS file chunks

### Hash Chain Verification

Each workspace and message has:
- `previous_hash` - Hash of previous record
- `current_hash` - SHA-256 hash of current data

**Verify in Compass:**
- Check that `previous_hash` of each record matches `current_hash` of previous record
- Chain starts with `previous_hash: "0"` (genesis)

## 🔒 Security Features

- ✅ Input validation on all endpoints
- ✅ JWT authentication ready (add to routes as needed)
- ✅ CORS protection
- ✅ File size limits
- ✅ Error handling without exposing internals

## 📁 Project Structure

```
backend/
├── config/
│   └── database.js          # MongoDB connection
├── middleware/
│   ├── auth.js              # JWT authentication
│   └── validation.js        # Input validation
├── routes/
│   ├── users.js             # User routes
│   ├── workspaces.js        # Workspace routes
│   ├── messages.js          # Message routes
│   ├── members.js           # Member routes
│   └── files.js             # File routes
├── utils/
│   └── hashChain.js         # Hash chain utilities
├── uploads/                 # Temporary file storage
├── .env                     # Environment variables
├── .env.example             # Environment template
├── server.js                # Main server file
└── package.json             # Dependencies
```

## 🐛 Troubleshooting

### MongoDB Connection Failed

**Error:** `ECONNREFUSED 127.0.0.1:27017`

**Solution:**
1. Make sure MongoDB is running
2. Check connection string in `.env`
3. Verify MongoDB service: `net start MongoDB` (Windows)

### Port Already in Use

**Error:** `EADDRINUSE: address already in use :::3000`

**Solution:**
1. Change PORT in `.env` file
2. Or kill process using port 3000

### File Upload Fails

**Error:** `File too large`

**Solution:**
1. Increase `MAX_FILE_SIZE` in `.env`
2. Check MongoDB GridFS limits

## 📝 Notes

- All addresses are automatically lowercased and trimmed
- Hash chains are automatically maintained
- Indexes are created automatically on startup
- Files are stored in MongoDB GridFS
- All timestamps are in milliseconds since epoch

## 🚀 Next Steps

1. ✅ Backend is ready!
2. Update Flutter app to use HTTP API instead of direct MongoDB
3. Add JWT authentication to protected routes
4. Deploy to production (Heroku, Railway, Render, etc.)

## 📞 Support

For issues or questions, check:
- MongoDB Compass connection
- Server logs in console
- API response errors

---

**Made with ❤️ for EtherShare FYP Project**

