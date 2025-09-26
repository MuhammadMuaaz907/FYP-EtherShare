@echo off
echo 🔍 Testing IPFS Desktop Connection...

echo.
echo 📡 Testing API connection...
powershell -Command "try { Invoke-WebRequest -Uri 'http://192.168.0.33:5001/api/v0/id' -Method POST | Out-Null; Write-Host '✅ IPFS API is accessible' } catch { Write-Host '❌ IPFS API is not accessible' }"

echo.
echo 🌐 Testing Gateway connection...
powershell -Command "try { Invoke-WebRequest -Uri 'http://192.168.0.33:8081/ipfs/QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG/readme' | Out-Null; Write-Host '✅ IPFS Gateway is accessible' } catch { Write-Host '❌ IPFS Gateway is not accessible' }"

echo.
echo 🚀 Testing OrbitDB server...
powershell -Command "try { Invoke-WebRequest -Uri 'http://localhost:3000/health' | Out-Null; Write-Host '✅ OrbitDB server is running' } catch { Write-Host '❌ OrbitDB server is not running' }"

echo.
echo 📊 Connection test complete!
pause
