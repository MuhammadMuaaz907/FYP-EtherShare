# PowerShell Script to Merge Module1-Authentication into Module2-WorkSpace-Management
# Run this script in PowerShell: .\execute_merge.ps1

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Git Merge: Module1-Authentication -> Module2-WorkSpace-Management" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Step 1: Fetch latest changes
Write-Host "`n[Step 1/5] Fetching latest changes from remote..." -ForegroundColor Yellow
git fetch origin
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to fetch from remote" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Fetch completed" -ForegroundColor Green

# Step 2: Checkout Module2-WorkSpace-Management
Write-Host "`n[Step 2/5] Checking out Module2-WorkSpace-Management branch..." -ForegroundColor Yellow
$branchExists = git branch --list Module2-WorkSpace-Management
if ($branchExists) {
    Write-Host "Branch exists locally, switching to it..." -ForegroundColor Gray
    git checkout Module2-WorkSpace-Management
    git pull origin Module2-WorkSpace-Management
} else {
    Write-Host "Creating local branch from remote..." -ForegroundColor Gray
    git checkout -b Module2-WorkSpace-Management origin/Module2-WorkSpace-Management
}
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to checkout branch" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Branch checked out successfully" -ForegroundColor Green

# Step 3: Merge Module1-Authentication
Write-Host "`n[Step 3/5] Merging Module1-Authentication into Module2-WorkSpace-Management..." -ForegroundColor Yellow
Write-Host "This may create merge conflicts that need to be resolved manually." -ForegroundColor Gray
git merge origin/Module1-Authentication --no-edit

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Merge completed successfully without conflicts!" -ForegroundColor Green
} else {
    Write-Host "`n⚠ Merge conflicts detected!" -ForegroundColor Yellow
    Write-Host "You need to resolve conflicts manually:" -ForegroundColor Yellow
    Write-Host "1. Check which files have conflicts: git status" -ForegroundColor Cyan
    Write-Host "2. Open conflicted files and resolve conflicts" -ForegroundColor Cyan
    Write-Host "3. After resolving, run: git add ." -ForegroundColor Cyan
    Write-Host "4. Then commit: git commit -m 'Merge Module1-Authentication into Module2-WorkSpace-Management'" -ForegroundColor Cyan
    exit 1
}

# Step 4: Verify merge
Write-Host "`n[Step 4/5] Verifying merge..." -ForegroundColor Yellow
git status
Write-Host "✓ Verification complete" -ForegroundColor Green

# Step 5: Push to remote (optional)
Write-Host "`n[Step 5/5] Ready to push to remote" -ForegroundColor Yellow
$push = Read-Host "Do you want to push to remote? (y/n)"
if ($push -eq "y" -or $push -eq "Y") {
    git push origin Module2-WorkSpace-Management
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Pushed to remote successfully!" -ForegroundColor Green
    } else {
        Write-Host "Error: Failed to push to remote" -ForegroundColor Red
    }
} else {
    Write-Host "Skipping push. You can push later with: git push origin Module2-WorkSpace-Management" -ForegroundColor Gray
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Merge process completed!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan

