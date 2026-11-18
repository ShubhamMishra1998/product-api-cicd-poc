$ErrorActionPreference = "Stop"

$DeploymentRoot = "C:\product-api-deployment"
$StateFile = Join-Path $DeploymentRoot "active-slot.txt"
$NginxConfig = Join-Path $DeploymentRoot "nginx\nginx.conf"

Write-Host "=================================="
Write-Host " BLUE GREEN ROLLBACK STARTED"
Write-Host "=================================="

if (-not (Test-Path $StateFile)) {
    throw "Active slot state file not found."
}

$Current = (Get-Content $StateFile -Raw).Trim().ToLower()

if ($Current -notin @("blue", "green")) {
    throw "Invalid active slot: $Current"
}

$Previous = if ($Current -eq "blue") { "green" } else { "blue" }

$Port = if ($Previous -eq "blue") { 8082 } else { 8083 }

Write-Host "Current active: $Current"
Write-Host "Rollback target: $Previous"

# Verify previous environment health
$Healthy = $false

for ($i = 1; $i -le 15; $i++) {
    try {
        $Response = Invoke-RestMethod `
            -Uri "http://localhost:$Port/actuator/health" `
            -TimeoutSec 5

        if ($Response.status -eq "UP") {
            $Healthy = $true
            break
        }
    }
    catch {
        Write-Host "Attempt ${i}: Previous environment not ready"
    }

    Start-Sleep -Seconds 2
}

if (-not $Healthy) {
    throw "Rollback target is unhealthy. No traffic switch performed."
}

Write-Host "$Previous environment is healthy!"

# Save current configuration
$PreviousConfig = Get-Content $NginxConfig -Raw

# Generate rollback configuration
$UpstreamService = "product-api-$Previous"

$NewConfig = @"
upstream product_api {
    server ${UpstreamService}:8080;
}

server {
    listen 80;

    location / {
        proxy_pass http://product_api;

        proxy_set_header Host `$host;
        proxy_set_header X-Real-IP `$remote_addr;
        proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto `$scheme;
    }
}
"@

Set-Content -Path $NginxConfig -Value $NewConfig -Encoding ascii

# Validate Nginx configuration
docker exec product-api-nginx nginx -t

if ($LASTEXITCODE -ne 0) {
    Set-Content -Path $NginxConfig -Value $PreviousConfig -Encoding ascii
    throw "Rollback configuration invalid."
}

# Reload Nginx
docker exec product-api-nginx nginx -s reload

if ($LASTEXITCODE -ne 0) {
    Set-Content -Path $NginxConfig -Value $PreviousConfig -Encoding ascii
    docker exec product-api-nginx nginx -s reload
    throw "Rollback traffic switch failed."
}

# Update persistent state
Set-Content -Path $StateFile -Value $Previous -NoNewline

Write-Host "=================================="
Write-Host " ROLLBACK SUCCESSFUL"
Write-Host " Previous active: $Current"
Write-Host " Current active: $Previous"
Write-Host "=================================="
