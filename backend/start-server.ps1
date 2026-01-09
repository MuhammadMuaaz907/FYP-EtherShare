# PowerShell Script to Start Backend Server with Verification
# This script ensures server is accessible before starting

Write-Host "`n" -NoNewline
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "🚀 Starting EtherShare Backend Server" -ForegroundColor Green
Write-Host "=" * 60 -ForegroundColor Cyan

# Check if Node.js is installed
Write-Host "`n1️⃣ Checking Node.js..." -ForegroundColor Yellow
try {
    $nodeVersion = node --version
    Write-Host "   ✅ Node.js: $nodeVersion" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Node.js not found! Please install Node.js" -ForegroundColor Red
    exit 1
}

# Check if MongoDB is running
Write-Host "`n2️⃣ Checking MongoDB..." -ForegroundColor Yellow
try {
    $mongoTest = Test-NetConnection -ComputerName localhost -Port 27017 -WarningAction SilentlyContinue
    if ($mongoTest.TcpTestSucceeded) {
        Write-Host "   ✅ MongoDB: Running on port 27017" -ForegroundColor Green
    } else {
        Write-Host "   ⚠️  MongoDB: Not accessible on port 27017" -ForegroundColor Yellow
        Write-Host "   💡 Start MongoDB: net start MongoDB" -ForegroundColor White
    }
} catch {
    Write-Host "   ⚠️  MongoDB: Could not check status" -ForegroundColor Yellow
}

# Check if port 3000 is available
Write-Host "`n3️⃣ Checking port 3000..." -ForegroundColor Yellow
try {
    $portTest = Test-NetConnection -ComputerName localhost -Port 3000 -WarningAction SilentlyContinue
    if ($portTest.TcpTestSucceeded) {
        Write-Host "   ⚠️  Port 3000: Already in use" -ForegroundColor Yellow
        Write-Host "   💡 Kill process or change PORT in .env" -ForegroundColor White
        $process = Get-NetTCPConnection -LocalPort 3000 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -First 1
        if ($process) {
            Write-Host "   Process ID: $process" -ForegroundColor White
        }
    } else {
        Write-Host "   ✅ Port 3000: Available" -ForegroundColor Green
    }
} catch {
    Write-Host "   ✅ Port 3000: Available" -ForegroundColor Green
}

# Check Windows Firewall
Write-Host "`n4️⃣ Checking Windows Firewall..." -ForegroundColor Yellow
$firewallRule = Get-NetFirewallRule -DisplayName "Node.js Backend Port 3000" -ErrorAction SilentlyContinue
if ($firewallRule) {
    if ($firewallRule.Enabled) {
        Write-Host "   ✅ Firewall: Port 3000 is allowed" -ForegroundColor Green
    } else {
        Write-Host "   ⚠️  Firewall: Port 3000 rule exists but is disabled" -ForegroundColor Yellow
        Write-Host "   💡 Enable rule: .\allow-port-3000.ps1" -ForegroundColor White
    }
} else {
    Write-Host "   ⚠️  Firewall: Port 3000 rule not found" -ForegroundColor Yellow
    Write-Host "   💡 Create rule: .\allow-port-3000.ps1" -ForegroundColor White
}

# Get current IP address
Write-Host "`n5️⃣ Network Configuration..." -ForegroundColor Yellow
$ipConfig = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } | Select-Object -First 1
if ($ipConfig) {
    $currentIP = $ipConfig.IPAddress
    Write-Host "   📍 Current IP: $currentIP" -ForegroundColor Cyan
    Write-Host "   💡 Update Flutter app IP if different:" -ForegroundColor White
    Write-Host "      DistributedService.setRealDeviceHost('$currentIP');" -ForegroundColor Gray
} else {
    Write-Host "   ⚠️  Could not detect IP address" -ForegroundColor Yellow
}

# Start server
Write-Host "`n6️⃣ Starting server..." -ForegroundColor Yellow
Write-Host "   Running: npm run dev" -ForegroundColor White
Write-Host "`n" -NoNewline

# Start server in new window
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$PWD'; npm run dev"

Write-Host "`n" -NoNewline
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "✅ Server starting in new window..." -ForegroundColor Green
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "`n💡 After server starts, verify:" -ForegroundColor Yellow
Write-Host "   1. Check server window for IP address" -ForegroundColor White
Write-Host "   2. Test: http://localhost:3000/health" -ForegroundColor White
Write-Host "   3. Test from phone: http://$currentIP:3000/health" -ForegroundColor White
Write-Host "`n"

