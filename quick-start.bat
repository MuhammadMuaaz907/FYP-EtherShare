@echo off
echo 🚀 EtherShare Quick Start Guide
echo ================================

echo.
echo 📋 Step 1: IPFS Desktop Setup
echo ------------------------------
echo 1. Open IPFS Desktop application
echo 2. Wait for "Connected" status
echo 3. Go to Settings → Advanced
echo 4. Enable CORS for all origins
echo 5. Set API Address: 192.168.0.35:5001
echo 6. Set Gateway Address: 192.168.0.35:8080
echo.

echo Press any key when IPFS Desktop is ready...
pause

echo.
echo 📋 Step 2: Testing Connection
echo ------------------------------
.\test-ipfs-connection.bat

echo.
echo Press any key to continue...
pause

echo.
echo 📋 Step 3: Starting OrbitDB Server
echo ----------------------------------
echo Starting server in new window...
start "OrbitDB Server" cmd /k "npm start"

echo.
echo 📋 Step 4: Starting Flutter App
echo --------------------------------
echo Starting Flutter app in new window...
start "Flutter App" cmd /k "cd blockchain_fyp && flutter run"

echo.
echo ✅ Setup Complete!
echo ==================
echo.
echo 📊 Services Running:
echo - IPFS Desktop: http://192.168.0.35:5001
echo - OrbitDB Server: http://localhost:3000
echo - Flutter App: Check the Flutter window
echo.
echo 🔍 To test: Open http://localhost:3000/health in browser
echo.
pause
