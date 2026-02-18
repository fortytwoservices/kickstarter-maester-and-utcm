<#
.SYNOPSIS
    Onboards UTCM (Unified Tenant Configuration Management) in a Microsoft Entra tenant.

.DESCRIPTION
    This script provisions the UTCM first-party service principal in the tenant and grants it
    the Graph API permissions required to read workload configuration data. This is a prerequisite
    before monitors can be created or snapshots taken via the Maester Dashboard.

    It performs the following steps:
    1. Connects to Microsoft Graph with admin scopes.
    2. Provisions the UTCM service principal (AppId 03b07b79-c5bc-4b5e-9bfa-13acf4a99998)
       if it does not already exist.
    3. Grants the UTCM service principal workload-reading permissions so that monitors can
       access Entra ID, Exchange, and Teams configuration data.
    4. Verifies UTCM access by calling the configurationMonitors endpoint.

    Reference: https://learn.microsoft.com/en-us/graph/utcm-authentication-setup

.PARAMETER TenantId
    The Entra tenant ID (GUID).

.PARAMETER SkipVerification
    If specified, skips the post-grant verification call to the configurationMonitors endpoint.

.EXAMPLE
    # Onboard UTCM in the tenant (provision SP + grant workload permissions)
    ./Enable-UTCM.ps1 -TenantId "00000000-0000-0000-0000-000000000000"

.EXAMPLE
    # Onboard UTCM without verification
    ./Enable-UTCM.ps1 -TenantId "00000000-0000-0000-0000-000000000000" -SkipVerification
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$TenantId,

    [switch]$SkipVerification
)

$ErrorActionPreference = 'Stop'

$GraphAppId = '00000003-0000-0000-c000-000000000000'
$UTCMAppId = '03b07b79-c5bc-4b5e-9bfa-13acf4a99998'

# Permissions the UTCM service principal needs to read workload data
$UTCMWorkloadPermissions = @(
    'Directory.Read.All',
    'Policy.Read.All',
    'Policy.Read.ConditionalAccess',
    'User.Read.All',
    'Application.Read.All',
    'Group.Read.All',
    'RoleManagement.Read.Directory',
    'Policy.Read.AuthenticationMethod',
    'Organization.Read.All',
    'SharePointTenantSettings.Read.All'
)

Write-Host "`n=== UTCM Onboarding ===" -ForegroundColor Cyan
Write-Host "Tenant: $TenantId"
Write-Host ""

if (Get-Module -ListAvailable Microsoft.Graph.Applications) {
    Write-Host "Microsoft.Graph.Applications module: installed" -ForegroundColor Green
}
else {
    Write-Host "Installing Microsoft.Graph.Applications module..." -ForegroundColor Yellow
    Install-Module Microsoft.Graph.Applications -Scope CurrentUser -Force
}

Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -TenantId $TenantId -Scopes 'AppRoleAssignment.ReadWrite.All', 'Application.ReadWrite.All' -NoWelcome | Out-Null

$ctx = Get-MgContext
Write-Host "Connected to tenant: $($ctx.TenantId)" -ForegroundColor Green

# --- Step 1: Provision the UTCM service principal ---
Write-Host "`n--- Step 1: Provision UTCM service principal ---" -ForegroundColor Cyan

$utcmSP = Get-MgServicePrincipal -Filter "appId eq '$UTCMAppId'" -ErrorAction SilentlyContinue
if ($utcmSP) {
    Write-Host "UTCM service principal already exists (ObjectId: $($utcmSP.Id))" -ForegroundColor Yellow
}
else {
    if ($PSCmdlet.ShouldProcess('Tenant', "Provision UTCM service principal (AppId: $UTCMAppId)")) {
        Write-Host "Provisioning UTCM service principal..." -ForegroundColor White
        $utcmSP = New-MgServicePrincipal -AppId $UTCMAppId
        Write-Host "UTCM service principal created (ObjectId: $($utcmSP.Id))" -ForegroundColor Green
    }
}

# --- Step 2: Grant workload permissions to UTCM SP ---
Write-Host "`n--- Step 2: Grant workload permissions to UTCM service principal ---" -ForegroundColor Cyan

if (-not $utcmSP) {
    Write-Warning "UTCM service principal not available (WhatIf mode or provisioning failed). Skipping permission grants."
    return
}

$graphSP = Get-MgServicePrincipal -Filter "appId eq '$GraphAppId'"
if (-not $graphSP) {
    throw "Microsoft Graph service principal not found in tenant."
}

$availableRoles = $graphSP.AppRoles | Where-Object { $_.Value }
$roleMap = @{}
foreach ($r in $availableRoles) { $roleMap[$r.Value] = $r }

$existingUTCMAssignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $utcmSP.Id
$alreadyAssigned = [System.Collections.Generic.HashSet[guid]]::new()
foreach ($a in $existingUTCMAssignments) { [void]$alreadyAssigned.Add($a.AppRoleId) }

$utcmAssigned = @()
$utcmSkipped = @()

foreach ($permName in $UTCMWorkloadPermissions) {
    $role = $roleMap[$permName]
    if (-not $role) {
        Write-Warning "Permission '$permName' not found in Microsoft Graph app roles. Skipping."
        continue
    }

    if ($alreadyAssigned.Contains($role.Id)) {
        Write-Host "  $permName - already granted" -ForegroundColor Yellow
        $utcmSkipped += $permName
        continue
    }

    if ($PSCmdlet.ShouldProcess('UTCM service principal', "Grant $permName")) {
        try {
            New-MgServicePrincipalAppRoleAssignment `
                -ServicePrincipalId $utcmSP.Id `
                -PrincipalId $utcmSP.Id `
                -ResourceId $graphSP.Id `
                -AppRoleId $role.Id | Out-Null
            Write-Host "  $permName - granted" -ForegroundColor Green
            $utcmAssigned += $permName
        }
        catch {
            Write-Warning "  Failed to grant ${permName}: $($_.Exception.Message)"
        }
    }
}

# --- Verification ---
if (-not $SkipVerification) {
    Write-Host "`n--- Step 3: Verify UTCM access ---" -ForegroundColor Cyan
    Write-Host "Waiting 10 seconds for permission propagation..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10

    try {
        $verifyResult = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/beta/admin/configurationManagement/configurationMonitors' -ErrorAction Stop
        $monitorCount = 0
        if ($verifyResult.value) { $monitorCount = $verifyResult.value.Count }
        Write-Host "UTCM is active and accessible. Monitors found: $monitorCount" -ForegroundColor Green
    }
    catch {
        $errMsg = $_.Exception.Message
        if ($errMsg -match 'not provisioned|not been onboarded|unknown error') {
            Write-Host "`nUTCM provisioning may still be propagating." -ForegroundColor Yellow
            Write-Host "Wait a few minutes and retry verification, or check the Entra admin center:" -ForegroundColor White
            Write-Host "  https://entra.microsoft.com > Enterprise Apps > Change 'Application Type' to 'All Applications' > Search for 'Unified Tenant Configuration Management'" -ForegroundColor White
        }
        elseif ($errMsg -match 'insufficient privileges|authorization|forbidden|consent') {
            Write-Host "`nPermissions have not fully propagated yet." -ForegroundColor Yellow
            Write-Host "Wait a few minutes and try accessing UTCM in the dashboard." -ForegroundColor White
        }
        else {
            Write-Warning "Verification call failed: $errMsg"
            Write-Host "This may be transient. Wait a few minutes and try again." -ForegroundColor Yellow
        }
    }
}

# --- Summary ---
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "UTCM service principal: $(if ($utcmSP) { 'Provisioned' } else { 'Skipped (WhatIf)' })" -ForegroundColor Green
Write-Host "UTCM workload permissions - Granted: $($utcmAssigned.Count), Already present: $($utcmSkipped.Count)" -ForegroundColor Green

if ($utcmAssigned.Count -gt 0) {
    Write-Host "`nUTCM SP - newly granted:" -ForegroundColor Green
    foreach ($p in $utcmAssigned) { Write-Host "  - $p" -ForegroundColor Green }
}
if ($utcmSkipped.Count -gt 0) {
    Write-Host "`nUTCM SP - already present:" -ForegroundColor Yellow
    foreach ($p in $utcmSkipped) { Write-Host "  - $p" -ForegroundColor Yellow }
}

Write-Host "`nNext steps:" -ForegroundColor White
Write-Host "     (Optional) Grant Exchange RBAC roles to the UTCM service principal for Exchange Online monitoring." -ForegroundColor White
Write-Host "     Exchange resources require Exchange management roles, not Graph API permissions." -ForegroundColor White
Write-Host "     Connect to Exchange Online PowerShell and run:" -ForegroundColor White
Write-Host "       Connect-ExchangeOnline" -ForegroundColor Gray
Write-Host "       New-ManagementRoleAssignment -Role 'View-Only Configuration' -App '$($utcmSP.Id)'" -ForegroundColor Gray
Write-Host "       New-ManagementRoleAssignment -Role 'Security Reader' -App '$($utcmSP.Id)'" -ForegroundColor Gray
Write-Host "     See: https://learn.microsoft.com/en-us/graph/utcm-exchange-resources" -ForegroundColor Gray

Write-Host "`nReference: https://learn.microsoft.com/en-us/graph/utcm-authentication-setup" -ForegroundColor Cyan
Write-Host ""
