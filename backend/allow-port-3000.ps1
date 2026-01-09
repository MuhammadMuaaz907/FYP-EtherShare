# PowerShell Script to Allow Port 3000 in Windows Firewall
# Run this script as Administrator

Write-Host "Configuring Windows Firewall for Port 3000..." -ForegroundColor Cyan

try {
    # Check if rule already exists
    $existingRule = Get-NetFirewallRule -DisplayName "Node.js Backend Port 3000" -ErrorAction SilentlyContinue
    
    if ($existingRule) {
        Write-Host "Firewall rule already exists!" -ForegroundColor Green
        Write-Host "   Rule Name: Node.js Backend Port 3000" -ForegroundColor Yellow
        Write-Host "   Status: $($existingRule.Enabled)" -ForegroundColor Yellow
        
        if (-not $existingRule.Enabled) {
            Write-Host "Rule exists but is disabled. Enabling..." -ForegroundColor Yellow
            Enable-NetFirewallRule -DisplayName "Node.js Backend Port 3000"
            Write-Host "Rule enabled!" -ForegroundColor Green
        }
    } else {
        # Create new firewall rule
        Write-Host "Creating new firewall rule..." -ForegroundColor Yellow
        
        New-NetFirewallRule `
            -DisplayName "Node.js Backend Port 3000" `
            -Direction Inbound `
            -LocalPort 3000 `
            -Protocol TCP `
            -Action Allow `
            -Profile Domain,Private,Public `
            -Description "Allow inbound connections to Node.js backend server on port 3000"
        
        Write-Host "Firewall rule created successfully!" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "Firewall configuration complete!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Cyan
    Write-Host "   1. Make sure backend server is running: npm run dev" -ForegroundColor White
    Write-Host "   2. Test from Android device: http://192.168.0.35:3000/health" -ForegroundColor White
    Write-Host "   3. Verify PC and phone are on same WiFi network" -ForegroundColor White
    Write-Host "   4. Check if server is listening: netstat -an | findstr :3000" -ForegroundColor White
    Write-Host ""
    
} catch {
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Make sure you're running PowerShell as Administrator!" -ForegroundColor Yellow
    Write-Host "   Right-click PowerShell -> Run as Administrator" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}
