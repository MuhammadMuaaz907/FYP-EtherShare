@echo off
echo 🚀 Starting EtherShare with IPFS Desktop...

REM Check if IPFS Desktop is running
echo 🔍 Checking IPFS Desktop status...
curl -s http://192.168.0.35:5001/api/v0/id >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ❌ IPFS Desktop is not running or not accessible
    echo 📥 Please start IPFS Desktop first:
    echo    1. Open IPFS Desktop application
    echo    2. Wait for "Connected" status
    echo    3. Run this script again
    pause
    exit /b 1
) else (
    echo ✅ IPFS Desktop is running
)

REM Get IPFS Desktop info
echo 📊 IPFS Desktop Info:
curl -s http://192.168.0.35:5001/api/v0/id | findstr "ID"
echo.

REM Start the Node.js server
echo 🚀 Starting OrbitDB server...
echo 📡 Server will connect to IPFS Desktop on port 5001
echo 🌐 WebSocket server will run on port 8080
echo.

npm start

pause
