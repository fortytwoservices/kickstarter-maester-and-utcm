<#
.SYNOPSIS
    Onboards UTCM (Unified Tenant Configuration Management) in a Microsoft Entra tenant.

.DESCRIPTION
    This script provisions the UTCM first-party service principal and grants all permissions
    required for monitoring Microsoft 365 workload configurations:

    - Microsoft Graph API application permissions (Entra ID, Intune, SharePoint)
    - Exchange Online application permission (Exchange.ManageAsApp)
    - Microsoft Entra ID directory roles (Global Reader, Security Reader, Compliance Administrator)
    - Exchange RBAC management roles (optional, requires ExchangeOnlineManagement module)

    Steps:
    1. Provisions the UTCM service principal (AppId 03b07b79-c5bc-4b5e-9bfa-13acf4a99998).
    2. Grants Microsoft Graph API read permissions for Entra ID, Intune, and SharePoint resources.
    3. Grants Exchange Online app permission (Exchange.ManageAsApp) for Exchange and Security & Compliance resources.
    4. Assigns Entra ID directory roles for workload-specific read access.
    5. (Optional) Grants Exchange RBAC management roles for Exchange resource monitoring.
    6. Verifies UTCM access by calling the configurationMonitors endpoint.

    References:
    - https://learn.microsoft.com/en-us/graph/utcm-authentication-setup
    - https://learn.microsoft.com/en-us/graph/utcm-entra-resources
    - https://learn.microsoft.com/en-us/graph/utcm-exchange-resources
    - https://learn.microsoft.com/en-us/graph/utcm-intune-resources
    - https://learn.microsoft.com/en-us/graph/utcm-securityandcompliance-resources
    - https://learn.microsoft.com/en-us/graph/utcm-teams-resources

.PARAMETER TenantId
    The Entra tenant ID (GUID).

.PARAMETER SkipVerification
    If specified, skips the post-grant verification call to the configurationMonitors endpoint.

.PARAMETER IncludeExchangeRBAC
    Grant Exchange RBAC management roles (View-Only Configuration, Security Reader)
    via Exchange Online Management. Requires the ExchangeOnlineManagement module and
    will establish a separate Exchange Online connection.

.EXAMPLE
    # Full onboarding (SP + Graph permissions + Exchange.ManageAsApp + directory roles)
    ./Enable-UTCM.ps1 -TenantId "00000000-0000-0000-0000-000000000000"

.EXAMPLE
    # Include Exchange RBAC roles for Exchange Online resource monitoring
    ./Enable-UTCM.ps1 -TenantId "00000000-0000-0000-0000-000000000000" -IncludeExchangeRBAC

.EXAMPLE
    # Onboard without verification
    ./Enable-UTCM.ps1 -TenantId "00000000-0000-0000-0000-000000000000" -SkipVerification
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$TenantId,

    [switch]$SkipVerification,

    [switch]$IncludeExchangeRBAC
)

$ErrorActionPreference = 'Stop'

$GraphAppId = '00000003-0000-0000-c000-000000000000'
$ExchangeOnlineAppId = '00000002-0000-0ff1-ce00-000000000000'
$UTCMAppId = '03b07b79-c5bc-4b5e-9bfa-13acf4a99998'

# Microsoft Graph API permissions for reading workload configurations
$GraphPermissions = @(
    # Entra ID resources
    'Directory.Read.All',
    'Policy.Read.All',
    'Policy.Read.ConditionalAccess',
    'Policy.Read.AuthenticationMethod',
    'User.Read.All',
    'Application.Read.All',
    'Group.Read.All',
    'RoleManagement.Read.Directory',
    'Organization.Read.All',
    'AdministrativeUnit.Read.All',
    'EntitlementManagement.Read.All',
    'IdentityProvider.Read.All',
    'RoleEligibilitySchedule.Read.Directory',
    'RoleManagementPolicy.Read.Directory',
    'Agreement.Read.All',
    'Device.Read.All',

    # Intune resources
    'DeviceManagementConfiguration.Read.All',
    'DeviceManagementApps.Read.All',
    'DeviceManagementManagedDevices.Read.All',
    'DeviceManagementServiceConfig.Read.All',
    'DeviceManagementRBAC.Read.All',

    # SharePoint
    'SharePointTenantSettings.Read.All'
)

# Exchange Online app permission (required for Exchange and Security & Compliance resources)
$ExchangePermissions = @(
    'Exchange.ManageAsApp'
)

# Entra ID directory roles required for workload read access
$DirectoryRoles = @(
    'Global Reader',
    'Security Reader',
    'Compliance Administrator'
)

# Exchange RBAC management roles for Exchange resource monitoring
$ExchangeRBACRoles = @(
    'View-Only Configuration',
    'Security Reader'
)

Write-Host "`n=== UTCM Onboarding ===" -ForegroundColor Cyan
Write-Host "Tenant: $TenantId"
Write-Host ""

# --- Module checks ---
if (Get-Module -ListAvailable Microsoft.Graph.Applications) {
    Write-Host "Microsoft.Graph.Applications module: installed" -ForegroundColor Green
}
else {
    Write-Host "Installing Microsoft.Graph.Applications module..." -ForegroundColor Yellow
    Install-Module Microsoft.Graph.Applications -Scope CurrentUser -Force
}

if ($IncludeExchangeRBAC) {
    if (Get-Module -ListAvailable ExchangeOnlineManagement) {
        Write-Host "ExchangeOnlineManagement module: installed" -ForegroundColor Green
    }
    else {
        Write-Host "Installing ExchangeOnlineManagement module..." -ForegroundColor Yellow
        Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force
    }
}

# --- Connect to Microsoft Graph ---
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
$graphScopes = @(
    'AppRoleAssignment.ReadWrite.All',
    'Application.ReadWrite.All',
    'RoleManagement.ReadWrite.Directory'
)
Connect-MgGraph -TenantId $TenantId -Scopes $graphScopes -NoWelcome | Out-Null

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

if (-not $utcmSP) {
    Write-Warning "UTCM service principal not available (WhatIf mode or provisioning failed). Cannot continue."
    return
}

# --- Step 2: Grant Microsoft Graph API permissions ---
Write-Host "`n--- Step 2: Grant Microsoft Graph API permissions ---" -ForegroundColor Cyan

$graphSP = Get-MgServicePrincipal -Filter "appId eq '$GraphAppId'"
if (-not $graphSP) {
    throw "Microsoft Graph service principal not found in tenant."
}

$availableRoles = $graphSP.AppRoles | Where-Object { $_.Value }
$roleMap = @{}
foreach ($r in $availableRoles) { $roleMap[$r.Value] = $r }

$allExistingAssignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $utcmSP.Id
$graphAlreadyAssigned = [System.Collections.Generic.HashSet[guid]]::new()
foreach ($a in ($allExistingAssignments | Where-Object { $_.ResourceId -eq $graphSP.Id })) {
    [void]$graphAlreadyAssigned.Add($a.AppRoleId)
}

$graphAssigned = @()
$graphSkipped = @()

foreach ($permName in $GraphPermissions) {
    $role = $roleMap[$permName]
    if (-not $role) {
        Write-Warning "Permission '$permName' not found in Microsoft Graph app roles. Skipping."
        continue
    }

    if ($graphAlreadyAssigned.Contains($role.Id)) {
        Write-Host "  $permName - already granted" -ForegroundColor Yellow
        $graphSkipped += $permName
        continue
    }

    if ($PSCmdlet.ShouldProcess('UTCM service principal', "Grant Graph permission: $permName")) {
        try {
            New-MgServicePrincipalAppRoleAssignment `
                -ServicePrincipalId $utcmSP.Id `
                -PrincipalId $utcmSP.Id `
                -ResourceId $graphSP.Id `
                -AppRoleId $role.Id | Out-Null
            Write-Host "  $permName - granted" -ForegroundColor Green
            $graphAssigned += $permName
        }
        catch {
            Write-Warning "  Failed to grant ${permName}: $($_.Exception.Message)"
        }
    }
}

# --- Step 3: Grant Exchange Online app permission ---
Write-Host "`n--- Step 3: Grant Exchange Online app permission ---" -ForegroundColor Cyan

$exoSP = Get-MgServicePrincipal -Filter "appId eq '$ExchangeOnlineAppId'" -ErrorAction SilentlyContinue
$exoAssigned = @()
$exoSkipped = @()

if (-not $exoSP) {
    Write-Warning "Exchange Online service principal not found. Skipping Exchange.ManageAsApp grant."
    Write-Warning "Exchange Online and Security & Compliance monitoring will not be available."
}
else {
    $exoRoleMap = @{}
    foreach ($r in ($exoSP.AppRoles | Where-Object { $_.Value })) { $exoRoleMap[$r.Value] = $r }

    $exoAlreadyAssigned = [System.Collections.Generic.HashSet[guid]]::new()
    foreach ($a in ($allExistingAssignments | Where-Object { $_.ResourceId -eq $exoSP.Id })) {
        [void]$exoAlreadyAssigned.Add($a.AppRoleId)
    }

    foreach ($permName in $ExchangePermissions) {
        $role = $exoRoleMap[$permName]
        if (-not $role) {
            Write-Warning "Permission '$permName' not found in Exchange Online app roles. Skipping."
            continue
        }

        if ($exoAlreadyAssigned.Contains($role.Id)) {
            Write-Host "  $permName - already granted" -ForegroundColor Yellow
            $exoSkipped += $permName
            continue
        }

        if ($PSCmdlet.ShouldProcess('UTCM service principal', "Grant Exchange Online permission: $permName")) {
            try {
                New-MgServicePrincipalAppRoleAssignment `
                    -ServicePrincipalId $utcmSP.Id `
                    -PrincipalId $utcmSP.Id `
                    -ResourceId $exoSP.Id `
                    -AppRoleId $role.Id | Out-Null
                Write-Host "  $permName - granted" -ForegroundColor Green
                $exoAssigned += $permName
            }
            catch {
                Write-Warning "  Failed to grant ${permName}: $($_.Exception.Message)"
            }
        }
    }
}

# --- Step 4: Assign Entra ID directory roles ---
Write-Host "`n--- Step 4: Assign Entra ID directory roles ---" -ForegroundColor Cyan

$rolesAssigned = @()
$rolesSkipped = @()

foreach ($roleName in $DirectoryRoles) {
    try {
        $roleDefResponse = Invoke-MgGraphRequest -Method GET `
            -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions?`$filter=displayName eq '$roleName'" `
            -ErrorAction Stop

        if (-not $roleDefResponse.value -or $roleDefResponse.value.Count -eq 0) {
            Write-Warning "Directory role '$roleName' not found. Skipping."
            continue
        }

        $roleDefId = $roleDefResponse.value[0].id

        $existingRoleAssignment = Invoke-MgGraphRequest -Method GET `
            -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?`$filter=principalId eq '$($utcmSP.Id)' and roleDefinitionId eq '$roleDefId'" `
            -ErrorAction Stop

        if ($existingRoleAssignment.value -and $existingRoleAssignment.value.Count -gt 0) {
            Write-Host "  $roleName - already assigned" -ForegroundColor Yellow
            $rolesSkipped += $roleName
            continue
        }

        if ($PSCmdlet.ShouldProcess('UTCM service principal', "Assign directory role: $roleName")) {
            $body = @{
                roleDefinitionId = $roleDefId
                principalId      = $utcmSP.Id
                directoryScopeId = '/'
            }
            Invoke-MgGraphRequest -Method POST `
                -Uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments' `
                -Body $body `
                -ErrorAction Stop | Out-Null
            Write-Host "  $roleName - assigned" -ForegroundColor Green
            $rolesAssigned += $roleName
        }
    }
    catch {
        Write-Warning "  Failed to assign role '${roleName}': $($_.Exception.Message)"
    }
}

# --- Step 5: (Optional) Grant Exchange RBAC management roles ---
$exoRBACAssigned = @()
$exoRBACSkipped = @()
$exoSPRegistered = $false

if ($IncludeExchangeRBAC) {
    Write-Host "`n--- Step 5: Grant Exchange RBAC management roles ---" -ForegroundColor Cyan
    Write-Host "Connecting to Exchange Online..." -ForegroundColor Cyan

    try {
        Import-Module ExchangeOnlineManagement -ErrorAction Stop
        Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop

        # Exchange Online has its own SP registry. Register the UTCM SP before assigning roles.
        $existingExoSP = Get-ServicePrincipal -Identity $utcmSP.Id -ErrorAction SilentlyContinue
        if ($existingExoSP) {
            Write-Host "  UTCM service principal already registered in Exchange Online" -ForegroundColor Yellow
            $exoSPRegistered = $true
        }
        else {
            if ($PSCmdlet.ShouldProcess('Exchange Online', "Register UTCM service principal (AppId: $UTCMAppId)")) {
                Write-Host "  Registering UTCM service principal in Exchange Online..." -ForegroundColor White
                try {
                    New-ServicePrincipal -AppId $UTCMAppId -ObjectId $utcmSP.Id -DisplayName 'Unified Tenant Configuration Management' -ErrorAction Stop | Out-Null
                    Write-Host "  UTCM service principal registered in Exchange Online" -ForegroundColor Green
                    $exoSPRegistered = $true
                }
                catch {
                    if ($_.Exception.Message -match 'already exists|already registered|duplicate') {
                        Write-Host "  UTCM service principal already registered in Exchange Online" -ForegroundColor Yellow
                        $exoSPRegistered = $true
                    }
                    else {
                        Write-Warning "  Failed to register SP in Exchange Online: $($_.Exception.Message)"
                    }
                }
            }
        }

        if ($exoSPRegistered) {
            foreach ($roleName in $ExchangeRBACRoles) {
                try {
                    New-ManagementRoleAssignment -Role $roleName -App $utcmSP.Id -ErrorAction Stop | Out-Null
                    Write-Host "  $roleName - assigned" -ForegroundColor Green
                    $exoRBACAssigned += $roleName
                }
                catch {
                    if ($_.Exception.Message -match 'is already assigned|already exists|duplicate') {
                        Write-Host "  $roleName - already assigned" -ForegroundColor Yellow
                        $exoRBACSkipped += $roleName
                    }
                    else {
                        Write-Warning "  Failed to assign Exchange role '${roleName}': $($_.Exception.Message)"
                    }
                }
            }
        }
        else {
            Write-Warning "Skipping Exchange RBAC role assignments (SP not registered in Exchange Online)."
        }

        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    }
    catch {
        Write-Warning "Failed to connect to Exchange Online: $($_.Exception.Message)"
        Write-Host "  You can manually connect and run:" -ForegroundColor White
        Write-Host "    Connect-ExchangeOnline" -ForegroundColor Gray
        Write-Host "    New-ServicePrincipal -AppId '$UTCMAppId' -ObjectId '$($utcmSP.Id)' -DisplayName 'Unified Tenant Configuration Management'" -ForegroundColor Gray
        foreach ($roleName in $ExchangeRBACRoles) {
            Write-Host "    New-ManagementRoleAssignment -Role '$roleName' -App '$($utcmSP.Id)'" -ForegroundColor Gray
        }
    }
}

# --- Verification ---
if (-not $SkipVerification) {
    $stepNum = if ($IncludeExchangeRBAC) { '6' } else { '5' }
    Write-Host "`n--- Step $stepNum`: Verify UTCM access ---" -ForegroundColor Cyan
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
            Write-Host "Wait a few minutes and retry, or check the Entra admin center:" -ForegroundColor White
            Write-Host "  https://entra.microsoft.com > Enterprise Apps > Search for 'Unified Tenant Configuration Management'" -ForegroundColor White
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
Write-Host "UTCM service principal: Provisioned (ObjectId: $($utcmSP.Id))" -ForegroundColor Green

Write-Host "`nGraph API permissions - Granted: $($graphAssigned.Count), Already present: $($graphSkipped.Count)" -ForegroundColor Green
if ($graphAssigned.Count -gt 0) {
    Write-Host "  Newly granted:" -ForegroundColor Green
    foreach ($p in $graphAssigned) { Write-Host "    - $p" -ForegroundColor Green }
}

if ($exoSP) {
    Write-Host "`nExchange Online permissions - Granted: $($exoAssigned.Count), Already present: $($exoSkipped.Count)" -ForegroundColor Green
    if ($exoAssigned.Count -gt 0) {
        Write-Host "  Newly granted:" -ForegroundColor Green
        foreach ($p in $exoAssigned) { Write-Host "    - $p" -ForegroundColor Green }
    }
}

Write-Host "`nEntra ID directory roles - Assigned: $($rolesAssigned.Count), Already present: $($rolesSkipped.Count)" -ForegroundColor Green
if ($rolesAssigned.Count -gt 0) {
    Write-Host "  Newly assigned:" -ForegroundColor Green
    foreach ($r in $rolesAssigned) { Write-Host "    - $r" -ForegroundColor Green }
}

if ($IncludeExchangeRBAC) {
    Write-Host "`nExchange RBAC roles - Assigned: $($exoRBACAssigned.Count), Already present: $($exoRBACSkipped.Count)" -ForegroundColor Green
    if ($exoRBACAssigned.Count -gt 0) {
        Write-Host "  Newly assigned:" -ForegroundColor Green
        foreach ($r in $exoRBACAssigned) { Write-Host "    - $r" -ForegroundColor Green }
    }
}
else {
    Write-Host "`nExchange RBAC roles: Skipped (use -IncludeExchangeRBAC to grant)" -ForegroundColor Yellow
    Write-Host "  Exchange resources require RBAC roles in addition to Exchange.ManageAsApp." -ForegroundColor White
    Write-Host "  Run again with -IncludeExchangeRBAC, or manually run:" -ForegroundColor White
    Write-Host "    Connect-ExchangeOnline" -ForegroundColor Gray
    Write-Host "    New-ServicePrincipal -AppId '$UTCMAppId' -ObjectId '$($utcmSP.Id)' -DisplayName 'Unified Tenant Configuration Management'" -ForegroundColor Gray
    foreach ($roleName in $ExchangeRBACRoles) {
        Write-Host "    New-ManagementRoleAssignment -Role '$roleName' -App '$($utcmSP.Id)'" -ForegroundColor Gray
    }
}

Write-Host "`nReferences:" -ForegroundColor Cyan
Write-Host "  https://learn.microsoft.com/en-us/graph/utcm-authentication-setup" -ForegroundColor Gray
Write-Host "  https://learn.microsoft.com/en-us/graph/utcm-entra-resources" -ForegroundColor Gray
Write-Host "  https://learn.microsoft.com/en-us/graph/utcm-exchange-resources" -ForegroundColor Gray
Write-Host "  https://learn.microsoft.com/en-us/graph/utcm-intune-resources" -ForegroundColor Gray
Write-Host "  https://learn.microsoft.com/en-us/graph/utcm-securityandcompliance-resources" -ForegroundColor Gray
Write-Host "  https://learn.microsoft.com/en-us/graph/utcm-teams-resources" -ForegroundColor Gray
Write-Host ""
