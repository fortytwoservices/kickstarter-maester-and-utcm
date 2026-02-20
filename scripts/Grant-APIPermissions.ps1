#Requires -Modules Microsoft.Graph.Applications
<#
.SYNOPSIS
    Grants required Microsoft Graph and other API permissions to a managed identity or app registration for Maester.

.DESCRIPTION
    This script assigns the required application permissions to a managed identity or app registration service principal
    hosting the Maester Dashboard. It supports permissions for Microsoft Graph, Exchange Online,
    SharePoint, and Teams testing.
    
    Works with both:
    - Managed Identity service principals (Azure Web App, Container Apps, etc.)
    - App Registration service principals (for local development with client secret)

.PARAMETER identityAccountName
    The display name of the managed identity or app registration service principal to grant permissions to.
    For managed identities: The name shown in Azure Portal (usually matches the resource name).
    For app registrations: The display name of the app registration.

.PARAMETER Tenant
    The Entra tenant ID (GUID).

.PARAMETER IncludeExchange
    If specified, grants Exchange Online API permissions (Exchange.ManageAsApp),
    assigns Exchange-related directory roles (Exchange Administrator, Compliance Administrator),
    registers the service principal in Exchange Online, and assigns RBAC management roles
    (Compliance Management). Requires the ExchangeOnlineManagement module.

.PARAMETER IncludeSharePoint
    If specified, also grants SharePoint API permissions for SharePoint tests.

.EXAMPLE
    # Grant permissions to a managed identity
    ./Grant-APIPermissions.ps1 -identityAccountName "my-maester-app" -Tenant "00000000-0000-0000-0000-000000000000"

.EXAMPLE
    # Grant permissions to an app registration for local development
    ./Grant-APIPermissions.ps1 -identityAccountName "maester-local-dev" -Tenant "00000000-0000-0000-0000-000000000000"

.EXAMPLE
    # Grant with Exchange and SharePoint permissions
    ./Grant-APIPermissions.ps1 -identityAccountName "my-maester-app" -Tenant "00000000-0000-0000-0000-000000000000" -IncludeExchange -IncludeSharePoint
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory)]
  [string]$identityAccountName,
  [Parameter(Mandatory)]
  [string]$Tenant,
  [switch]$IncludeExchange,
  [switch]$IncludeSharePoint
)

# Microsoft Graph App ID
$GraphAppId = '00000003-0000-0000-c000-000000000000'

# Exchange Online App ID
$ExchangeAppId = '00000002-0000-0ff1-ce00-000000000000'

# SharePoint Online App ID
$SharePointAppId = '00000003-0000-0ff1-ce00-000000000000'

# Required Microsoft Graph permissions for Maester (expanded for all workloads)
$GraphRequiredPermissions = @(
  # Entra ID / Directory
  'DeviceManagementConfiguration.Read.All',
  'DeviceManagementManagedDevices.Read.All',
  'DeviceManagementRBAC.Read.All',
  'DeviceManagementServiceConfig.Read.All',
  'Directory.Read.All',
  'DirectoryRecommendations.Read.All',
  'IdentityRiskEvent.Read.All',
  'Policy.Read.All',
  'Policy.Read.ConditionalAccess',
  'PrivilegedAccess.Read.AzureAD',
  'Reports.Read.All',
  'ReportSettings.Read.All',
  'RoleEligibilitySchedule.Read.Directory',
  'RoleEligibilitySchedule.ReadWrite.Directory',
  'RoleManagement.Read.All',
  'SecurityIdentitiesSensors.Read.All',
  'SecurityIdentitiesHealth.Read.All',
  'SharePointTenantSettings.Read.All',
  'UserAuthenticationMethod.Read.All',
  # UTCM (Unified Tenant Configuration Management)
  'ConfigurationMonitoring.ReadWrite.All',
  'ConfigurationMonitoring.Read.All',
  # Teams
  'Team.ReadBasic.All',
  'TeamSettings.Read.All',
  'Channel.ReadBasic.All',
  'ChannelSettings.Read.All',
  'TeamsAppInstallation.ReadForTeam.All',
  'TeamMember.Read.All',
  'Chat.Read.All',
  'OnlineMeetings.Read.All',
  'TeamsTab.Read.All',
  # Security & Compliance
  'SecurityEvents.Read.All',
  'ThreatIndicators.Read.All',
  'ThreatHunting.Read.All',
  'SecurityActions.Read.All',
  'SecurityAlert.Read.All',
  'AttackSimulation.Read.All',
  # Mail (for email alerts)
  'Mail.Send',
  # User and Group
  'User.Read.All',
  'Group.Read.All',
  'GroupMember.Read.All',
  # Application
  'Application.Read.All',
  # Audit Logs
  'AuditLog.Read.All'
)

# Exchange Online permissions (for EXO tests)
$ExchangeRequiredPermissions = @(
  'Exchange.ManageAsApp',
  'full_access_as_app'
)

# SharePoint permissions
$SharePointRequiredPermissions = @(
  'Sites.Read.All',
  'Sites.FullControl.All'
)

# Directory roles (always assigned)
$DirectoryRolesAlways = @(
    'Teams Reader'
)

# Directory roles for Exchange Online
$DirectoryRolesExchange = @(
    'Exchange Administrator',
    'Compliance Administrator'
)

# Exchange RBAC management roles for Maester
$ExchangeRBACRoles = @(
    'View-Only Configuration',
    'Security Reader',
    'View-Only Recipients'
)

if (Get-Module -ListAvailable Microsoft.Graph) { 
  Write-Host 'Module is installed' 
}
else { 
  Write-Host 'Module is NOT installed'
  Install-Module Microsoft.Graph -Scope CurrentUser
}

if ($IncludeExchange) {
    if (Get-Module -ListAvailable ExchangeOnlineManagement) {
        Write-Host "ExchangeOnlineManagement module: installed" -ForegroundColor Green
    }
    else {
        Write-Host "Installing ExchangeOnlineManagement module..." -ForegroundColor Yellow
        Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force
    }
}

Write-Host "Connecting to Microsoft Graph (Tenant: $Tenant) ..." -ForegroundColor Cyan
Connect-MgGraph -TenantId $Tenant -Scopes 'AppRoleAssignment.ReadWrite.All', 'Application.Read.All', 'RoleManagement.ReadWrite.Directory' -NoWelcome | Out-Null

$ctx = Get-MgContext
Write-Host "Tenant: $($ctx.TenantId)" -ForegroundColor Green

# Lookup target service principal (works for both managed identity and app registration)
$webAppMatches = Get-MgServicePrincipal -Filter "displayName eq '$identityAccountName'"
$WebAppMSI = $webAppMatches

if (-not $webAppMatches) {
  throw "No service principal found with displayName '$identityAccountName'"
}
if ($webAppMatches.Count -gt 1) {
  Write-Warning "Multiple service principals matched. Using the first. Consider disambiguating by AppId/ObjectId."
  $WebAppMSI = $webAppMatches[0]
}

$spType = if ($WebAppMSI.ServicePrincipalType -eq 'ManagedIdentity') { 'Managed Identity' } else { 'App Registration' }
Write-Host "Target SP: $($WebAppMSI.DisplayName)  ObjectId: $($WebAppMSI.Id)  Type: $spType" -ForegroundColor Yellow

# Function to assign app roles for a given resource
function Grant-AppRoleAssignments {
  param(
    [Parameter(Mandatory)][string]$ResourceAppId,
    [Parameter(Mandatory)][string]$ResourceName,
    [Parameter(Mandatory)][string[]]$Permissions,
    [Parameter(Mandatory)][object]$TargetSP
  )
  
  Write-Host "`n=== Processing $ResourceName permissions ===" -ForegroundColor Cyan
  
  $resourceSp = Get-MgServicePrincipal -Filter "appId eq '$ResourceAppId'"
  if (-not $resourceSp) {
    Write-Warning "$ResourceName service principal not found in tenant. Skipping."
    return @{ Assigned = @(); Skipped = @() }
  }
  
  # Roles exposed by the resource
  $availableRoles = $resourceSp.AppRoles | Where-Object { $_.Value }
  
  # Map required permissions to app role objects
  $roleMap = @{}
  foreach ($r in $availableRoles) { $roleMap[$r.Value] = $r }
  
  $missing = $Permissions | Where-Object { -not $roleMap.ContainsKey($_) }
  if ($missing) {
    Write-Warning "The following $ResourceName permissions were not found: $($missing -join ', ')"
  }
  
  $targetRoles = $Permissions | ForEach-Object { $roleMap[$_] } | Where-Object { $_ }
  
  # Existing assignments
  $existingAssignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $TargetSP.Id
  $alreadyAssigned = [System.Collections.Generic.HashSet[guid]]::new()
  foreach ($a in $existingAssignments) { [void]$alreadyAssigned.Add($a.AppRoleId) }
  
  $assigned = @()
  $skipped = @()
  
  foreach ($role in $targetRoles) {
    if ($alreadyAssigned.Contains($role.Id)) {
      $skipped += $role.Value
      continue
    }
    if ($PSCmdlet.ShouldProcess($TargetSP.DisplayName, "Assign $ResourceName role $($role.Value)")) {
      try {
        New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $TargetSP.Id -PrincipalId $TargetSP.Id -ResourceId $resourceSp.Id -AppRoleId $role.Id | Out-Null
        Write-Host "Assigned: $($role.Value)" -ForegroundColor Green
        $assigned += $role.Value
      }
      catch {
        Write-Warning "Failed assigning $($role.Value): $($_.Exception.Message)"
      }
    }
  }
  
  return @{ Assigned = $assigned; Skipped = $skipped }
}

# Process Microsoft Graph permissions
$graphResult = Grant-AppRoleAssignments -ResourceAppId $GraphAppId -ResourceName 'Microsoft Graph' -Permissions $GraphRequiredPermissions -TargetSP $WebAppMSI

# Process Exchange Online permissions if requested
$exoResult = @{ Assigned = @(); Skipped = @() }
if ($IncludeExchange) {
  $exoResult = Grant-AppRoleAssignments -ResourceAppId $ExchangeAppId -ResourceName 'Exchange Online' -Permissions $ExchangeRequiredPermissions -TargetSP $WebAppMSI
}

# --- Assign Entra ID directory roles ---
$allDirectoryRoles = [System.Collections.Generic.List[string]]::new()
foreach ($r in $DirectoryRolesAlways) { $allDirectoryRoles.Add($r) }
if ($IncludeExchange) {
    foreach ($r in $DirectoryRolesExchange) { $allDirectoryRoles.Add($r) }
}

$rolesAssigned = @()
$rolesSkipped = @()

Write-Host "`n=== Processing Directory Roles ===" -ForegroundColor Cyan

foreach ($roleName in $allDirectoryRoles) {
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
            -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?`$filter=principalId eq '$($WebAppMSI.Id)' and roleDefinitionId eq '$roleDefId'" `
            -ErrorAction Stop

        if ($existingRoleAssignment.value -and $existingRoleAssignment.value.Count -gt 0) {
            Write-Host "  $roleName - already assigned" -ForegroundColor Yellow
            $rolesSkipped += $roleName
            continue
        }

        if ($PSCmdlet.ShouldProcess($WebAppMSI.DisplayName, "Assign directory role: $roleName")) {
            $body = @{
                roleDefinitionId = $roleDefId
                principalId      = $WebAppMSI.Id
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

# --- (Optional) Grant Exchange RBAC management roles ---
$exoRBACAssigned = @()
$exoRBACSkipped = @()
$exoSPRegistered = $false

if ($IncludeExchange) {
    Write-Host "`n=== Processing Exchange RBAC Roles ===" -ForegroundColor Cyan
    Write-Host "Connecting to Exchange Online..." -ForegroundColor Cyan

    try {
        Import-Module ExchangeOnlineManagement -ErrorAction Stop
        Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop

        $existingExoSP = Get-ServicePrincipal -Identity $WebAppMSI.Id -ErrorAction SilentlyContinue
        if ($existingExoSP) {
            Write-Host "  Service principal already registered in Exchange Online" -ForegroundColor Yellow
            $exoSPRegistered = $true
        }
        else {
            if ($PSCmdlet.ShouldProcess('Exchange Online', "Register service principal (ObjectId: $($WebAppMSI.Id))")) {
                Write-Host "  Registering service principal in Exchange Online..." -ForegroundColor White
                try {
                    New-ServicePrincipal -AppId $WebAppMSI.AppId -ObjectId $WebAppMSI.Id -DisplayName $WebAppMSI.DisplayName -ErrorAction Stop | Out-Null
                    Write-Host "  Service principal registered in Exchange Online" -ForegroundColor Green
                    $exoSPRegistered = $true
                }
                catch {
                    if ($_.Exception.Message -match 'already exists|already registered|duplicate') {
                        Write-Host "  Service principal already registered in Exchange Online" -ForegroundColor Yellow
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
                    New-ManagementRoleAssignment -Role $roleName -App $WebAppMSI.Id -ErrorAction Stop | Out-Null
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
        Write-Host "    New-ServicePrincipal -AppId '$($WebAppMSI.AppId)' -ObjectId '$($WebAppMSI.Id)' -DisplayName '$($WebAppMSI.DisplayName)'" -ForegroundColor Gray
        foreach ($roleName in $ExchangeRBACRoles) {
            Write-Host "    New-ManagementRoleAssignment -Role '$roleName' -App '$($WebAppMSI.Id)'" -ForegroundColor Gray
        }
    }
}

# Process SharePoint permissions if requested
$spoResult = @{ Assigned = @(); Skipped = @() }
if ($IncludeSharePoint) {
  $spoResult = Grant-AppRoleAssignments -ResourceAppId $SharePointAppId -ResourceName 'SharePoint Online' -Permissions $SharePointRequiredPermissions -TargetSP $WebAppMSI
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Microsoft Graph - Assigned: $($graphResult.Assigned.Count), Already present: $($graphResult.Skipped.Count)" -ForegroundColor Green
if ($IncludeExchange) {
  Write-Host "Exchange Online - Assigned: $($exoResult.Assigned.Count), Already present: $($exoResult.Skipped.Count)" -ForegroundColor Green
}

Write-Host "`nDirectory roles - Assigned: $($rolesAssigned.Count), Already present: $($rolesSkipped.Count)" -ForegroundColor Green
if ($rolesAssigned.Count -gt 0) {
    Write-Host "  Newly assigned:" -ForegroundColor Green
    foreach ($r in $rolesAssigned) { Write-Host "    - $r" -ForegroundColor Green }
}

if ($IncludeExchange) {
    Write-Host "`nExchange RBAC roles - Assigned: $($exoRBACAssigned.Count), Already present: $($exoRBACSkipped.Count)" -ForegroundColor Green
    if ($exoRBACAssigned.Count -gt 0) {
        Write-Host "  Newly assigned:" -ForegroundColor Green
        foreach ($r in $exoRBACAssigned) { Write-Host "    - $r" -ForegroundColor Green }
    }
}
else {
    Write-Host "`nExchange RBAC roles: Skipped (use -IncludeExchange to grant)" -ForegroundColor Yellow
    Write-Host "  Exchange and Security & Compliance tests require RBAC roles." -ForegroundColor White
    Write-Host "  Run again with -IncludeExchange, or manually run:" -ForegroundColor White
    Write-Host "    Connect-ExchangeOnline" -ForegroundColor Gray
    Write-Host "    New-ServicePrincipal -AppId '$($WebAppMSI.AppId)' -ObjectId '$($WebAppMSI.Id)' -DisplayName '$($WebAppMSI.DisplayName)'" -ForegroundColor Gray
    foreach ($roleName in $ExchangeRBACRoles) {
        Write-Host "    New-ManagementRoleAssignment -Role '$roleName' -App '$($WebAppMSI.Id)'" -ForegroundColor Gray
    }
}

if ($IncludeSharePoint) {
  Write-Host "`nSharePoint Online - Assigned: $($spoResult.Assigned.Count), Already present: $($spoResult.Skipped.Count)" -ForegroundColor Green
}

Write-Host "`nDetailed assignments:" -ForegroundColor Yellow
Write-Host ("Graph Assigned: {0}" -f ($graphResult.Assigned -join ', ')) -ForegroundColor Green
Write-Host ("Graph Already present: {0}" -f ($graphResult.Skipped -join ', ')) -ForegroundColor Yellow
if ($IncludeExchange) {
  Write-Host ("EXO Assigned: {0}" -f ($exoResult.Assigned -join ', ')) -ForegroundColor Green
  Write-Host ("EXO Already present: {0}" -f ($exoResult.Skipped -join ', ')) -ForegroundColor Yellow
}
if ($IncludeSharePoint) {
  Write-Host ("SPO Assigned: {0}" -f ($spoResult.Assigned -join ', ')) -ForegroundColor Green
  Write-Host ("SPO Already present: {0}" -f ($spoResult.Skipped -join ', ')) -ForegroundColor Yellow
}