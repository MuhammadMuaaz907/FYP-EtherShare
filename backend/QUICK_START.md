# 🚀 Quick Start Guide

## Step 1: Install Dependencies

```bash
cd backend
npm install
```

## Step 2: Start MongoDB

**Windows:**
```powershell
net start MongoDB
```

**Verify in MongoDB Compass:**
- Open MongoDB Compass
- Connect to: `mongodb://localhost:27017`
- Should connect successfully ✅

## Step 3: Start Backend Server

```bash
npm run dev
```

Server will start on: `http://localhost:3000`

## Step 4: Test API

Open browser or Postman:
```
http://localhost:3000/health
```

Should return:
```json
{
  "success": true,
  "message": "EtherShare Backend API is running",
  "database": "connected"
}
```

## ✅ Done!

Your backend is now running and ready to use with MongoDB Compass!

## 📊 View Data in MongoDB Compass

1. Open MongoDB Compass
2. Connect to: `mongodb://localhost:27017`
3. Navigate to: `EtherShare` database
4. View collections as you create data through API

## 🧪 Test API Endpoints

### Create User Profile
```bash
POST http://localhost:3000/api/users/profile
Content-Type: application/json

{
  "address": "0x1234567890123456789012345678901234567890",
  "username": "test_user",
  "email": "test@example.com"
}
```

### Create Workspace
```bash
POST http://localhost:3000/api/workspaces
Content-Type: application/json

{
  "workspaceName": "My First Workspace",
  "inviterAddress": "0x1234567890123456789012345678901234567890"
}
```

Check MongoDB Compass - you'll see the data appear! 🎉

