# IPFS Desktop Setup Guide for EtherShare

## 🖥️ IPFS Desktop Configuration

Agar aap IPFS Desktop use kar rahe hain, to ye steps follow karein:

### 1. IPFS Desktop Installation
- Download from: https://github.com/ipfs/ipfs-desktop/releases
- Install and start IPFS Desktop
- IPFS Desktop automatically starts IPFS daemon

### 2. IPFS Desktop Settings
IPFS Desktop mein ja kar Settings > Advanced mein ye configuration karein:

#### API Settings:
- **API Address**: `192.168.0.35:5001`
- **Gateway Address**: `192.168.0.35:8080`

#### CORS Settings:
- **Access-Control-Allow-Origin**: `*`
- **Access-Control-Allow-Methods**: `GET, POST, PUT`
- **Access-Control-Allow-Headers**: `X-Requested-With, Range, User-Agent`

### 3. Verify IPFS Desktop
- Open IPFS Desktop
- Check "Status" tab - should show "Connected"
- Note down your Peer ID
- Check "Files" tab - should be accessible

### 4. Test IPFS Connection
```bash
# Test API connection
curl http://192.168.0.35:5001/api/v0/id

# Test Gateway
curl http://192.168.0.35:8080/ipfs/QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG/readme
```

## 🔧 Project Configuration

### Update server.mjs for IPFS Desktop
IPFS Desktop use karne ke liye server configuration update karni hogi:

```javascript
// IPFS Desktop uses different ports
const ipfs = await IPFS.create({
  repo: './orbitdb/ipfs',
  config: {
    Addresses: {
      Swarm: [
        '/ip4/0.0.0.0/tcp/4002',
        '/ip4/192.168.0.35/tcp/4003/ws'
      ],
      API: '/ip4/127.0.0.1/tcp/5001',  // IPFS Desktop default
      Gateway: '/ip4/127.0.0.1/tcp/8080'  // IPFS Desktop default
    }
  }
});
```

### Alternative: Use IPFS HTTP Client
IPFS Desktop ke saath HTTP client use karna easier hai:

```javascript
import { create } from 'ipfs-http-client';

// Connect to IPFS Desktop
const ipfs = create({
  host: '127.0.0.1',
  port: 5001,
  protocol: 'http'
});
```

## 🚀 Quick Start with IPFS Desktop

### Step 1: Start IPFS Desktop
1. Open IPFS Desktop application
2. Wait for "Connected" status
3. Note the API address (usually 127.0.0.1:5001)

### Step 2: Update Project Configuration
```bash
# Update server.mjs to use IPFS Desktop
# (Configuration already updated in the files)
```

### Step 3: Start OrbitDB Server
```bash
npm start
```

### Step 4: Test Connection
```bash
# Test IPFS Desktop connection
curl http://192.168.0.35:5001/api/v0/id

# Test OrbitDB server
curl http://localhost:3000/health
```

## 🔍 Troubleshooting IPFS Desktop

### Common Issues:

#### 1. Port Conflicts
- IPFS Desktop uses ports 5001 and 8080
- Ensure no other services are using these ports

#### 2. CORS Issues
- IPFS Desktop mein CORS settings enable karein
- Settings > Advanced > CORS Configuration

#### 3. API Not Accessible
- Check if IPFS Desktop is running
- Verify API address in settings
- Test with: `curl http://192.168.0.35:5001/api/v0/id`

#### 4. Gateway Not Working
- Check Gateway address in settings
- Test with: `curl http://192.168.0.35:8080/ipfs/...`

## 📊 IPFS Desktop Benefits

### Advantages:
- ✅ Easy GUI management
- ✅ Automatic daemon management
- ✅ Built-in file browser
- ✅ Network status monitoring
- ✅ Easy configuration

### For Development:
- ✅ Quick setup
- ✅ Visual debugging
- ✅ File management
- ✅ Peer monitoring

## 🔄 Switching Between IPFS Desktop and CLI

### To Use IPFS Desktop:
1. Start IPFS Desktop
2. Use HTTP client in server.mjs
3. No need to run `ipfs daemon` command

### To Use IPFS CLI:
1. Stop IPFS Desktop
2. Run `ipfs daemon` in terminal
3. Use programmatic IPFS in server.mjs

## 🛠️ Production Considerations

### IPFS Desktop vs CLI:
- **Development**: IPFS Desktop (easier)
- **Production**: IPFS CLI (more control)
- **Docker**: IPFS CLI (containerized)

### Configuration Files:
- IPFS Desktop settings are stored in user directory
- CLI configuration is in `~/.ipfs/config`
- Project uses its own IPFS repo in `./orbitdb/ipfs`

## 📱 Flutter App Integration

Flutter app ko IPFS Desktop ke saath connect karne ke liye:

```dart
// Update base URL if needed
static const String baseUrl = 'http://192.168.0.35:3000';
static const String wsUrl = 'ws://192.168.0.35:8080';
```

## 🎯 Next Steps

1. **Start IPFS Desktop**
2. **Verify connection**: `curl http://192.168.0.35:5001/api/v0/id`
3. **Start OrbitDB server**: `npm start`
4. **Test Flutter app**: Connect to server
5. **Monitor in IPFS Desktop**: Check files and peers

## 🔧 Advanced Configuration

### Custom IPFS Desktop Settings:
```json
{
  "Addresses": {
    "API": "/ip4/192.168.0.35/tcp/5001",
    "Gateway": "/ip4/192.168.0.35/tcp/8080",
    "Swarm": [
      "/ip4/0.0.0.0/tcp/4001",
      "/ip6/::/tcp/4001"
    ]
  },
  "API": {
    "HTTPHeaders": {
      "Access-Control-Allow-Origin": ["*"],
      "Access-Control-Allow-Methods": ["GET", "POST", "PUT"],
      "Access-Control-Allow-Headers": ["X-Requested-With", "Range", "User-Agent"]
    }
  }
}
```

---

**IPFS Desktop ke saath aapka setup ab ready hai! 🎉**
