
param(
    [Parameter(Mandatory = $true)]
    [string]$Image
)

$ErrorActionPreference = "Stop"

# Repository location
$ProjectRoot = Split-Path -Parent $PSScriptRoot

# Persistent deployment configuration
$DeploymentRoot = "C:\product-api-deployment"
$StateFile = Join-Path $DeploymentRoot "active-slot.txt"
$NginxConfig = Join-Path $DeploymentRoot "nginx\nginx.conf"

$ComposeFile = Join-Path $ProjectRoot "docker-compose.yml"
$ComposeProject = "product-api-cicd-poc"

function Invoke-Docker {
    param([string[]]$Arguments)

    & docker @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "Docker command failed: docker $($Arguments -join ' ')"
    }
}

Write-Host "=================================="
Write-Host " BLUE GREEN DEPLOYMENT STARTED"
Write-Host "=================================="

# Validate persistent configuration
if (-not (Test-Path $StateFile)) {
    throw "Persistent active-slot file not found."
}

if (-not (Test-Path $NginxConfig)) {
    throw "Persistent Nginx configuration not found."
}

$Active = (Get-Content $StateFile -Raw).Trim().ToLower()

if ($Active -notin @("blue", "green")) {
    throw "Invalid active slot: $Active"
}

$Target = if ($Active -eq "blue") { "green" } else { "blue" }

Write-Host "Current active: $Active"
Write-Host "Deployment target: $Target"
Write-Host "Image: $Image"

# Determine inactive environment
if ($Target -eq "green") {
    $Service = "product-api-green"
    $Port = 8083
    $env:GREEN_IMAGE = $Image
}
else {
    $Service = "product-api-blue"
    $Port = 8082
    $env:BLUE_IMAGE = $Image
}

# Pull new image
Invoke-Docker @(
    "compose", "-p", $ComposeProject,
    "-f", $ComposeFile,
    "--project-directory", $ProjectRoot,
    "pull", $Service
)

# Deploy inactive environment
Invoke-Docker @(
    "compose", "-p", $ComposeProject,
    "-f", $ComposeFile,
    "--project-directory", $ProjectRoot,
    "up", "-d", "--no-deps", "--force-recreate", $Service
)

# Health check
$Healthy = $false

for ($i = 1; $i -le 30; $i++) {
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
        Write-Host "Attempt ${i}: Application not ready"
    }

    Start-Sleep -Seconds 2
}

if (-not $Healthy) {
    throw "Health check failed. Traffic remains on $Active."
}

Write-Host "$Target environment is healthy!"

# Preserve previous Nginx configuration
$PreviousConfig = Get-Content $NginxConfig -Raw

# Generate new Nginx configuration
$UpstreamService = "product-api-$Target"

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

# Validate and reload Nginx
try {
    Invoke-Docker @(
        "exec", "product-api-nginx",
        "nginx", "-t"
    )

    Invoke-Docker @(
        "exec", "product-api-nginx",
        "nginx", "-s", "reload"
    )
}
catch {
    Write-Host "Traffic switch failed. Restoring previous configuration."

    Set-Content -Path $NginxConfig -Value $PreviousConfig -Encoding ascii

    & docker exec product-api-nginx nginx -s reload

    throw
}

# Save active environment only after successful traffic switch
Set-Content -Path $StateFile -Value $Target -NoNewline

Write-Host "=================================="
Write-Host " DEPLOYMENT SUCCESSFUL"
Write-Host " Previous active: $Active"
Write-Host " New active: $Target"
Write-Host "=================================="
