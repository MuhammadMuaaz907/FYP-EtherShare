# PowerShell Script to Fix Network Access Issues
# Run this script as Administrator to diagnose and fix network connectivity

Write-Host "`n" -NoNewline
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "🔧 Network Access Diagnostic & Fix Tool" -ForegroundColor Green
Write-Host "=" * 70 -ForegroundColor Cyan

# Step 1: Check current IP
Write-Host "`n1️⃣ Detecting Network Configuration..." -ForegroundColor Yellow
$ipConfig = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { 
    $_.IPAddress -notlike "127.*" -and 
    $_.IPAddress -notlike "169.254.*" -and
    $_.PrefixOrigin -ne "WellKnown"
} | Select-Object -First 1

if ($ipConfig) {
    $currentIP = $ipConfig.IPAddress
    Write-Host "   ✅ Current IP: $currentIP" -ForegroundColor Green
} else {
    Write-Host "   ❌ Could not detect IP address" -ForegroundColor Red
    exit 1
}

# Step 2: Check if server is running
Write-Host "`n2️⃣ Checking if server is running..." -ForegroundColor Yellow
$portTest = Test-NetConnection -ComputerName localhost -Port 3000 -WarningAction SilentlyContinue
if ($portTest.TcpTestSucceeded) {
    Write-Host "   ✅ Server is running on port 3000" -ForegroundColor Green
} else {
    Write-Host "   ❌ Server is NOT running on port 3000" -ForegroundColor Red
    Write-Host "   💡 Start server: cd backend && npm run dev" -ForegroundColor White
    exit 1
}

# Step 3: Check Windows Firewall
Write-Host "`n3️⃣ Checking Windows Firewall..." -ForegroundColor Yellow
$firewallRule = Get-NetFirewallRule -DisplayName "Node.js Backend Port 3000" -ErrorAction SilentlyContinue
if ($firewallRule) {
    if ($firewallRule.Enabled) {
        Write-Host "   ✅ Firewall rule exists and is ENABLED" -ForegroundColor Green
    } else {
        Write-Host "   ⚠️  Firewall rule exists but is DISABLED" -ForegroundColor Yellow
        Write-Host "   🔧 Enabling firewall rule..." -ForegroundColor Cyan
        Enable-NetFirewallRule -DisplayName "Node.js Backend Port 3000"
        Write-Host "   ✅ Firewall rule enabled!" -ForegroundColor Green
    }
} else {
    Write-Host "   ⚠️  Firewall rule does NOT exist" -ForegroundColor Yellow
    Write-Host "   🔧 Creating firewall rule..." -ForegroundColor Cyan
    try {
        New-NetFirewallRule `
            -DisplayName "Node.js Backend Port 3000" `
            -Direction Inbound `
            -LocalPort 3000 `
            -Protocol TCP `
            -Action Allow `
            -Profile Domain,Private,Public `
            -Description "Allow inbound connections to Node.js backend server on port 3000"
        Write-Host "   ✅ Firewall rule created!" -ForegroundColor Green
    } catch {
        Write-Host "   ❌ Failed to create firewall rule: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "   💡 Run PowerShell as Administrator!" -ForegroundColor Yellow
        exit 1
    }
}

# Step 4: Check if server is listening on all interfaces
Write-Host "`n4️⃣ Checking server binding..." -ForegroundColor Yellow
$listening = Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue
if ($listening) {
    $localAddress = $listening.LocalAddress
    if ($localAddress -eq "0.0.0.0") {
        Write-Host "   ✅ Server is listening on ALL interfaces (0.0.0.0)" -ForegroundColor Green
    } else {
        Write-Host "   ⚠️  Server is listening on: $localAddress" -ForegroundColor Yellow
        Write-Host "   💡 Server should listen on 0.0.0.0 for network access" -ForegroundColor White
        Write-Host "   💡 Check server.js line 119: app.listen(PORT, '0.0.0.0', ...)" -ForegroundColor White
    }
} else {
    Write-Host "   ❌ Could not detect server binding" -ForegroundColor Red
}

# Step 5: Test localhost access
Write-Host "`n5️⃣ Testing localhost access..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "http://localhost:3000/health" -TimeoutSec 5 -UseBasicParsing
    if ($response.StatusCode -eq 200) {
        Write-Host "   ✅ Localhost access: OK" -ForegroundColor Green
        $healthData = $response.Content | ConvertFrom-Json
        Write-Host "   Response: $($healthData.message)" -ForegroundColor Gray
    } else {
        Write-Host "   ⚠️  Localhost access: Status $($response.StatusCode)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   ❌ Localhost access: FAILED" -ForegroundColor Red
    Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
}

# Step 6: Test network IP access
Write-Host "`n6️⃣ Testing network IP access..." -ForegroundColor Yellow
try {
    $networkUrl = "http://$currentIP:3000/health"
    $response = Invoke-WebRequest -Uri $networkUrl -TimeoutSec 5 -UseBasicParsing
    if ($response.StatusCode -eq 200) {
        Write-Host "   ✅ Network IP access: OK" -ForegroundColor Green
        Write-Host "   URL: $networkUrl" -ForegroundColor Gray
    } else {
        Write-Host "   ⚠️  Network IP access: Status $($response.StatusCode)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   ❌ Network IP access: FAILED" -ForegroundColor Red
    Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "   💡 This might be a firewall or network configuration issue" -ForegroundColor Yellow
}

# Step 7: Check network profile
Write-Host "`n7️⃣ Checking network profile..." -ForegroundColor Yellow
$networkProfile = Get-NetConnectionProfile
if ($networkProfile) {
    Write-Host "   Network Name: $($networkProfile.Name)" -ForegroundColor Cyan
    Write-Host "   Network Category: $($networkProfile.NetworkCategory)" -ForegroundColor Cyan
    if ($networkProfile.NetworkCategory -eq "Public") {
        Write-Host "   ⚠️  Network is set to PUBLIC - firewall may be stricter" -ForegroundColor Yellow
        Write-Host "   💡 Consider changing to Private network for better connectivity" -ForegroundColor White
    }
}

# Step 8: Summary and instructions
Write-Host "`n" -NoNewline
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "📋 Summary & Next Steps" -ForegroundColor Green
Write-Host "=" * 70 -ForegroundColor Cyan

Write-Host "`n📍 Server URLs:" -ForegroundColor Yellow
Write-Host "   Local: http://localhost:3000/health" -ForegroundColor White
Write-Host "   Network: http://$currentIP:3000/health" -ForegroundColor White

Write-Host "`n📱 To test from phone:" -ForegroundColor Yellow
Write-Host "   1. Make sure phone and PC are on SAME WiFi network" -ForegroundColor White
Write-Host "   2. Open phone browser: http://$currentIP:3000/health" -ForegroundColor White
Write-Host "   3. If still not accessible, check:" -ForegroundColor White
Write-Host "      - Router firewall settings" -ForegroundColor Gray
Write-Host "      - Windows Defender Firewall" -ForegroundColor Gray
Write-Host "      - Antivirus software blocking connections" -ForegroundColor Gray

Write-Host "`n🔧 If phone still can't access:" -ForegroundColor Yellow
Write-Host "   1. Temporarily disable Windows Firewall to test" -ForegroundColor White
Write-Host "   2. Check if router has AP isolation enabled (disable it)" -ForegroundColor White
Write-Host "   3. Try ping from phone: ping $currentIP" -ForegroundColor White
Write-Host "   4. Check server logs for connection attempts" -ForegroundColor White

Write-Host "`n💡 Flutter App Configuration:" -ForegroundColor Yellow
Write-Host "   Update IP in distributed_service.dart:" -ForegroundColor White
Write-Host "   DistributedService.setRealDeviceHost('$currentIP');" -ForegroundColor Cyan

Write-Host "`n" -NoNewline
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host ""
