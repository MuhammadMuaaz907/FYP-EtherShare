# 📱 Multi-Device Communication Setup Guide

## Problem Analysis

### Issue 1: One Device Can Access Server, Other Cannot
**Possible Causes:**
1. **Windows Firewall**: May be blocking connections from specific devices
2. **Router AP Isolation**: Router may be isolating devices from each other
3. **Network Configuration**: Devices may be on different network segments
4. **Device-Specific Firewall**: Antivirus or device firewall blocking connections

### Issue 2: P2P Communication Not Working
**Possible Causes:**
1. **Peer Discovery**: Peers not being discovered from server
2. **Port Blocking**: Port 8080 (P2P port) may be blocked
3. **Connection Logic**: Devices not connecting to each other automatically

## Solutions Implemented

### 1. Backend Peer Registration API
- **Endpoint**: `POST /api/peers/register`
- **Purpose**: Register device IP and port for P2P communication
- **Usage**: Devices register their P2P info when they come online

### 2. Peer Discovery API
- **Endpoints**:
  - `GET /api/peers` - Get all active peers
  - `GET /api/peers/:user_address` - Get specific peer info
  - `GET /api/peers/workspace/:workspace_id` - Get peers in a workspace
- **Purpose**: Enable devices to discover each other through server

### 3. Enhanced HybridStorageService
- **Auto Peer Registration**: Registers peer info when server is online
- **Auto Peer Discovery**: Discovers and connects to peers automatically
- **Periodic Updates**: Re-discovers peers every 30 seconds

### 4. P2P Service Improvements
- **Automatic Connection**: Connects to discovered peers automatically
- **Handshake Protocol**: Proper handshake for peer identification
- **Connection Retry**: Retries failed connections

## Setup Instructions

### Step 1: Fix Network Connectivity

#### For Device That Can't Access Server:

1. **Check Windows Firewall**:
   ```powershell
   # Run as Administrator
   cd backend
   .\allow-port-3000.ps1
   ```

2. **Check Router Settings**:
   - Disable "AP Isolation" or "Client Isolation"
   - Ensure both devices on same network segment
   - Check if router has device-specific firewall rules

3. **Test Connectivity**:
   ```powershell
   # From device that can't access, test:
   ping 192.168.0.35
   # Should get responses
   ```

4. **Check Device Firewall**:
   - Temporarily disable antivirus/firewall
   - Test if server becomes accessible
   - If yes, add exception for port 3000

### Step 2: Verify Server Configuration

1. **Check Server is Listening on All Interfaces**:
   ```powershell
   netstat -an | findstr :3000
   # Should show: TCP    0.0.0.0:3000           0.0.0.0:0              LISTENING
   ```

2. **Verify Server Output**:
   Server console should show:
   ```
   🌐 Network: http://192.168.0.35:3000
   ```

### Step 3: Test from Both Devices

#### Device 1 (Working):
```
http://192.168.0.35:3000/health
```

#### Device 2 (Not Working):
```
http://192.168.0.35:3000/health
```

**If Device 2 still can't access:**
1. Check if devices are on same WiFi network
2. Check router AP isolation settings
3. Try accessing from Device 2's browser first
4. Check Windows Firewall logs

### Step 4: Enable P2P Communication

1. **Start Backend Server**:
   ```bash
   cd backend
   npm run dev
   ```

2. **Run Flutter App on Both Devices**:
   - App will automatically:
     - Register peer info with server
     - Discover other peers
     - Connect to peers automatically

3. **Check Logs**:
   Look for:
   ```
   ✅ Peer registered with server: 192.168.0.XX:8080
   🔍 Discovering peers from server...
   ✅ Connected to peer: 0x... (192.168.0.XX:8080)
   ```

## Troubleshooting

### Issue: Device 2 Can't Access Server

**Solution 1: Check Router AP Isolation**
- Login to router admin panel
- Find "AP Isolation" or "Client Isolation" setting
- Disable it
- Restart router if needed

**Solution 2: Windows Firewall Exception**
```powershell
# Add specific device IP exception (if needed)
New-NetFirewallRule -DisplayName "Allow Device 2" -Direction Inbound -RemoteAddress "192.168.0.XX" -LocalPort 3000 -Protocol TCP -Action Allow
```

**Solution 3: Test Network Connectivity**
```powershell
# From Device 2, test:
Test-NetConnection -ComputerName 192.168.0.35 -Port 3000
```

### Issue: P2P Not Working

**Check 1: Port 8080 Not Blocked**
```powershell
# Check if port 8080 is listening on devices
netstat -an | findstr :8080
```

**Check 2: Peer Registration**
- Check server logs for peer registration
- Verify peer info in MongoDB: `db.peers.find()`

**Check 3: Peer Discovery**
- Check Flutter app logs for peer discovery
- Verify peers are being discovered from server

**Check 4: Connection Attempts**
- Check Flutter app logs for connection attempts
- Verify P2P handshake is completing

## Testing Multi-Device Communication

### Test 1: Server Online
1. Start backend server
2. Run app on Device 1
3. Run app on Device 2
4. Send message from Device 1 to Device 2
5. **Expected**: Message should appear on Device 2

### Test 2: Server Offline
1. Stop backend server
2. Send message from Device 1 to Device 2
3. **Expected**: Message should still work via P2P

### Test 3: Both Offline Then Online
1. Both devices offline (no server)
2. Send messages (should work via P2P)
3. Start server
4. **Expected**: Messages should sync to server

## Network Configuration Checklist

- [ ] Both devices on same WiFi network
- [ ] Router AP isolation disabled
- [ ] Windows Firewall allows port 3000
- [ ] Server listening on `0.0.0.0:3000`
- [ ] Both devices can ping server IP
- [ ] Both devices can access `http://192.168.0.35:3000/health`
- [ ] P2P port 8080 not blocked
- [ ] Peer registration working
- [ ] Peer discovery working
- [ ] P2P connections established

## API Endpoints for Peer Management

### Register Peer
```http
POST /api/peers/register
Content-Type: application/json

{
  "user_address": "0x...",
  "ip_address": "192.168.0.XX",
  "port": 8080
}
```

### Get Peer Info
```http
GET /api/peers/:user_address
```

### Get Workspace Peers
```http
GET /api/peers/workspace/:workspace_id
```

### Get All Active Peers
```http
GET /api/peers
```

## Success Indicators

✅ Both devices can access server health endpoint
✅ Peer registration successful in server logs
✅ Peer discovery finds other devices
✅ P2P connections established
✅ Messages work with server on
✅ Messages work with server off
✅ Messages sync when server comes back online

