# 🧪 Testing Guide: Channels & P2P Communication

## 📋 Pre-Testing Checklist

Before testing, ensure:
- [ ] Two or more mobile devices are available
- [ ] All devices are on the same WiFi network
- [ ] Server can be turned on/off for testing
- [ ] Both devices have the app installed with latest changes
- [ ] Both devices are logged in to the same workspace

---

## 🧪 Test Scenarios

### **Test 1: Channels Visibility (Server Off)**

**Objective:** Verify all channels are visible when server is off

**Steps:**
1. **Setup:**
   - Start server
   - Open app on Device A
   - Login to workspace
   - Create 2-3 new channels (e.g., "Test1", "Test2", "Test3")
   - Send at least one message in each channel
   - Close app

2. **Test:**
   - Turn OFF server
   - Open app on Device A
   - Navigate to workspace home page
   - **Expected:** All channels should be visible:
     - ✅ General
     - ✅ Random
     - ✅ Test1
     - ✅ Test2
     - ✅ Test3

3. **Verify:**
   - [ ] All channels are visible
   - [ ] Channel names are correct
   - [ ] Channels are in correct order (General, Random, then others)

**Success Criteria:** ✅ All channels visible, including user-created ones

---

### **Test 2: P2P Message Sending (Server Off)**

**Objective:** Verify messages are sent and persist on sender device

**Steps:**
1. **Setup:**
   - Turn OFF server
   - Open app on Device A
   - Login to workspace
   - Navigate to "General" channel

2. **Test:**
   - Type a message: "Test P2P message from Device A"
   - Send message
   - **Expected:**
     - ✅ Message appears immediately on Device A
     - ✅ Message persists after closing and reopening app
     - ✅ Message is visible even if P2P fails

3. **Verify:**
   - [ ] Message appears on sender device immediately
   - [ ] Message doesn't disappear after a few seconds
   - [ ] Message persists after app restart
   - [ ] Message is in SQLite database

**Success Criteria:** ✅ Message persists on sender device

---

### **Test 3: P2P Message Receiving (Server Off)**

**Objective:** Verify messages are received on other devices

**Steps:**
1. **Setup:**
   - Turn OFF server
   - Open app on Device A and Device B
   - Both devices login to same workspace
   - Both devices navigate to "General" channel
   - **Important:** Ensure both devices have peer info cached (connect to server once before turning it off)

2. **Test:**
   - On Device A: Send message "Hello from Device A"
   - **Expected on Device B:**
     - ✅ Message appears within 2-5 seconds
     - ✅ Message doesn't disappear
     - ✅ Message persists after app restart

3. **Verify:**
   - [ ] Message appears on Device B
   - [ ] Message appears within reasonable time (2-5 seconds)
   - [ ] Message persists after closing app
   - [ ] No duplicate messages

**Success Criteria:** ✅ Message received and persists on receiver device

---

### **Test 4: P2P Communication in Multiple Channels**

**Objective:** Verify P2P works in different channels

**Steps:**
1. **Setup:**
   - Turn OFF server
   - Open app on Device A and Device B
   - Both devices in same workspace

2. **Test:**
   - **General Channel:**
     - Device A sends: "Message in General"
     - Verify Device B receives it
   
   - **Random Channel:**
     - Device B navigates to Random channel
     - Device A navigates to Random channel
     - Device B sends: "Message in Random"
     - Verify Device A receives it
   
   - **Custom Channel:**
     - Device A navigates to a custom channel (e.g., "Test1")
     - Device B navigates to same channel
     - Device A sends: "Message in Test1"
     - Verify Device B receives it

3. **Verify:**
   - [ ] Messages work in General channel
   - [ ] Messages work in Random channel
   - [ ] Messages work in custom channels
   - [ ] No cross-channel message leakage

**Success Criteria:** ✅ P2P works in all channel types

---

### **Test 5: Multiple Devices P2P Communication**

**Objective:** Verify P2P works with 3+ devices

**Steps:**
1. **Setup:**
   - Turn OFF server
   - Open app on Device A, B, and C
   - All devices in same workspace
   - All devices in "General" channel

2. **Test:**
   - Device A sends: "Message from A"
   - Device B sends: "Message from B"
   - Device C sends: "Message from C"
   
   - **Expected:**
     - ✅ All devices see all 3 messages
     - ✅ Messages appear in correct order
     - ✅ No duplicates

3. **Verify:**
   - [ ] Device A sees messages from B and C
   - [ ] Device B sees messages from A and C
   - [ ] Device C sees messages from A and B
   - [ ] All messages in correct order
   - [ ] No duplicate messages

**Success Criteria:** ✅ P2P works with multiple devices

---

### **Test 6: Offline to Online Sync**

**Objective:** Verify messages sync when server comes back online

**Steps:**
1. **Setup:**
   - Turn OFF server
   - Device A sends message "Offline message"
   - Device B receives message via P2P
   - Both devices have message in SQLite

2. **Test:**
   - Turn ON server
   - Wait 10-15 seconds
   - Check server database
   - **Expected:**
     - ✅ Message appears in server database
     - ✅ Message marked as synced in SQLite

3. **Verify:**
   - [ ] Message synced to server
   - [ ] Message marked as synced in SQLite
   - [ ] No duplicate messages on server

**Success Criteria:** ✅ Messages sync to server when online

---

### **Test 7: Channel Case Sensitivity**

**Objective:** Verify channels work with different case variations

**Steps:**
1. **Setup:**
   - Turn OFF server
   - Create channel "TestChannel"
   - Send messages in channel

2. **Test:**
   - Query messages with:
     - "TestChannel" (original case)
     - "testchannel" (lowercase)
     - "TESTCHANNEL" (uppercase)
   
   - **Expected:**
     - ✅ All queries return same messages
     - ✅ Channel appears correctly in UI

3. **Verify:**
   - [ ] Case-insensitive channel matching works
   - [ ] Messages retrieved correctly regardless of case

**Success Criteria:** ✅ Case-insensitive channel queries work

---

## 🐛 Common Issues & Solutions

### **Issue 1: Channels Not Showing**

**Symptoms:**
- Only General and Random visible
- User-created channels missing

**Solutions:**
1. Check if channels table exists in SQLite
2. Verify channels are cached when server is online
3. Check logs for channel loading errors
4. Ensure channels are saved to SQLite when created

**Debug:**
```dart
// Check SQLite database
final channels = await SQLiteService.instance.getWorkspaceChannels(workspaceId);
print('Channels in SQLite: $channels');
```

---

### **Issue 2: Messages Not Received**

**Symptoms:**
- Message sent but not received on other device
- Message disappears from sender device

**Solutions:**
1. Verify peer info is cached in SQLite
2. Check if devices are on same network
3. Verify P2P server is running on both devices
4. Check firewall/network settings
5. Ensure message is saved to SQLite before P2P attempt

**Debug:**
```dart
// Check peer info
final peer = await SQLiteService.instance.getPeer(userAddress);
print('Peer info: $peer');

// Check P2P connections
final connected = P2PService.instance.getConnectedPeers();
print('Connected peers: $connected');
```

---

### **Issue 3: Duplicate Messages**

**Symptoms:**
- Same message appears multiple times
- Message saved twice

**Solutions:**
1. Verify message_id deduplication is working
2. Check if message is saved multiple times
3. Ensure providedMessageId is used correctly

**Debug:**
```dart
// Check message IDs
final messages = await SQLiteService.instance.getChannelMessages(...);
final messageIds = messages.map((m) => m['message_id']).toSet();
print('Unique message IDs: ${messageIds.length}');
print('Total messages: ${messages.length}');
```

---

### **Issue 4: P2P Connection Fails**

**Symptoms:**
- Cannot connect to peer
- Connection timeout

**Solutions:**
1. Verify devices are on same WiFi network
2. Check IP addresses are correct
3. Verify P2P port is not blocked by firewall
4. Ensure P2P server is running
5. Check peer info is correct in SQLite

**Debug:**
```dart
// Check P2P server status
final isRunning = P2PService.instance.isServerRunning();
print('P2P server running: $isRunning');

// Check my P2P info
final myInfo = HybridStorageService.instance.getMyP2PInfo();
print('My P2P info: $myInfo');
```

---

## 📊 Expected Logs

### **Successful Channel Loading:**
```
📦 Loading channels from SQLite for workspace <workspaceId>
✅ SQLite returned X channels
✅ Final channels list: X channels (General and Random ensured)
```

### **Successful Message Send:**
```
📡 Broadcasting channel message via P2P to workspace members...
   Found X workspace members for P2P broadcast
   Connecting to peer: <address> (<ip>:<port>)
   ✅ Channel message sent via P2P to <address>
✅ Channel message broadcasted to X/Y members via P2P
```

### **Successful Message Receive:**
```
📢 Received channel message: <channelId> in workspace <workspaceId> from <sender>
✅ Channel message received and saved: <messageId>
📨 Real-time P2P message received for current channel
```

---

## ✅ Final Verification

After completing all tests, verify:

- [ ] All channels visible when server is off
- [ ] Messages persist on sender device
- [ ] Messages received on other devices
- [ ] P2P works in all channel types
- [ ] P2P works with multiple devices
- [ ] Messages sync when server comes online
- [ ] Case-insensitive channel queries work
- [ ] No duplicate messages
- [ ] No memory leaks
- [ ] App doesn't crash

---

## 🎯 Success Criteria

**All tests pass if:**
- ✅ Channels are visible offline
- ✅ Messages persist and don't disappear
- ✅ P2P communication works reliably
- ✅ Messages sync when server comes online
- ✅ No duplicates or data loss

---

**Date:** $(date)  
**Status:** Ready for Testing

