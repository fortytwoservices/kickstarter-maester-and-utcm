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

.PARAMETER IncludeExchangeOnline
    If specified, also grants Exchange Online API permissions for EXO tests.

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
    ./Grant-APIPermissions.ps1 -identityAccountName "my-maester-app" -Tenant "00000000-0000-0000-0000-000000000000" -IncludeExchangeOnline -IncludeSharePoint
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory)]
  [string]$identityAccountName,
  [Parameter(Mandatory)]
  [string]$Tenant,
  [switch]$IncludeExchangeOnline,
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

if (Get-Module -ListAvailable Microsoft.Graph) { 
  Write-Host 'Module is installed' 
}
else { 
  Write-Host 'Module is NOT installed'
  Install-Module Microsoft.Graph -Scope CurrentUser
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
$exoRoleAssigned = $false
if ($IncludeExchangeOnline) {
  $exoResult = Grant-AppRoleAssignments -ResourceAppId $ExchangeAppId -ResourceName 'Exchange Online' -Permissions $ExchangeRequiredPermissions -TargetSP $WebAppMSI
  
  # Also assign Exchange Administrator directory role (required for EXO PowerShell)
  Write-Host "`n=== Processing Exchange Administrator Role ===" -ForegroundColor Cyan
  try {
    $exoAdminRole = Get-MgDirectoryRole -Filter "displayName eq 'Exchange Administrator'" -ErrorAction SilentlyContinue
    if (-not $exoAdminRole) {
      # Role not yet activated, activate it from template
      Write-Host "Activating Exchange Administrator role..." -ForegroundColor Yellow
      $allTemplates = Get-MgDirectoryRoleTemplate -All
      $roleTemplate = $allTemplates | Where-Object { $_.DisplayName -eq 'Exchange Administrator' }
      if ($roleTemplate) {
        $exoAdminRole = New-MgDirectoryRole -RoleTemplateId $roleTemplate.Id
      }
    }
    
    if ($exoAdminRole) {
      if ($PSCmdlet.ShouldProcess($WebAppMSI.DisplayName, "Assign Exchange Administrator directory role")) {
        try {
          $memberBody = @{ "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($WebAppMSI.Id)" }
          New-MgDirectoryRoleMemberByRef -DirectoryRoleId $exoAdminRole.Id -BodyParameter $memberBody -ErrorAction Stop
          Write-Host "Exchange Administrator role: Assigned" -ForegroundColor Green
          $exoRoleAssigned = $true
        }
        catch {
          if ($_.Exception.Message -match 'already exist') {
            Write-Host "Exchange Administrator role: Already assigned" -ForegroundColor Yellow
          } else {
            throw
          }
        }
      }
    } else {
      Write-Warning "Could not find or activate Exchange Administrator role"
    }
  }
  catch {
    Write-Warning "Failed to assign Exchange Administrator role: $($_.Exception.Message)"
  }

  # Also assign Compliance Administrator role (required for Security & Compliance PowerShell)
  Write-Host "`n=== Processing Compliance Administrator Role ===" -ForegroundColor Cyan
  try {
    $complianceAdminRole = Get-MgDirectoryRole -Filter "displayName eq 'Compliance Administrator'" -ErrorAction SilentlyContinue
    if (-not $complianceAdminRole) {
      # Role not yet activated, activate it from template
      Write-Host "Activating Compliance Administrator role..." -ForegroundColor Yellow
      $allTemplates = Get-MgDirectoryRoleTemplate -All
      $roleTemplate = $allTemplates | Where-Object { $_.DisplayName -eq 'Compliance Administrator' }
      if ($roleTemplate) {
        $complianceAdminRole = New-MgDirectoryRole -RoleTemplateId $roleTemplate.Id
      }
    }
    
    if ($complianceAdminRole) {
      if ($PSCmdlet.ShouldProcess($WebAppMSI.DisplayName, "Assign Compliance Administrator directory role")) {
        try {
          $memberBody = @{ "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($WebAppMSI.Id)" }
          New-MgDirectoryRoleMemberByRef -DirectoryRoleId $complianceAdminRole.Id -BodyParameter $memberBody -ErrorAction Stop
          Write-Host "Compliance Administrator role: Assigned" -ForegroundColor Green
        }
        catch {
          if ($_.Exception.Message -match 'already exist') {
            Write-Host "Compliance Administrator role: Already assigned" -ForegroundColor Yellow
          } else {
            throw
          }
        }
      }
    } else {
      Write-Warning "Could not find or activate Compliance Administrator role"
    }
  }
  catch {
    Write-Warning "Failed to assign Compliance Administrator role: $($_.Exception.Message)"
  }
  
  # Exchange Management Roles (required for Security & Compliance PowerShell)
  Write-Host "`n=== Exchange Management Roles ===" -ForegroundColor Cyan
  Write-Host "Exchange admin roles require the service principal to sync to Exchange Online." -ForegroundColor Yellow
  Write-Host ""
  Write-Host "Steps to assign Exchange roles:" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "1. Wait 10-15 minutes for Azure AD sync to Exchange Online" -ForegroundColor White
  Write-Host ""
  Write-Host "2. Connect to Exchange Online:" -ForegroundColor White
  Write-Host "   Connect-ExchangeOnline" -ForegroundColor Gray
  Write-Host ""
  Write-Host "3. Verify service principal is visible:" -ForegroundColor White
  Write-Host "   Get-ServicePrincipal -Identity '$($WebAppMSI.AppId)'" -ForegroundColor Gray
  Write-Host ""
  Write-Host "4. If not found, trigger sync by accessing Exchange with the identity:" -ForegroundColor White
  Write-Host "   Get-Mailbox -ResultSize 1 -ErrorAction SilentlyContinue" -ForegroundColor Gray
  Write-Host "   (This may fail but helps trigger registration)" -ForegroundColor Gray
  Write-Host ""
  Write-Host "5. Once visible, assign the role:" -ForegroundColor White
  Write-Host "   New-ManagementRoleAssignment -Role 'Compliance Management' -App '$($WebAppMSI.AppId)' -Name 'ComplianceManagement-$($WebAppMSI.DisplayName)'" -ForegroundColor Gray
  Write-Host ""
  Write-Host "6. Verify the assignment:" -ForegroundColor White
  Write-Host "   Get-ManagementRoleAssignment -RoleAssignee '$($WebAppMSI.AppId)'" -ForegroundColor Gray
  Write-Host ""
  Write-Host "App ID: $($WebAppMSI.AppId)" -ForegroundColor Green
  Write-Host "Display Name: $($WebAppMSI.DisplayName)" -ForegroundColor Green
}

# Assign Teams Reader role (required for Teams tests)
# This is always assigned since Teams Graph permissions are in the default set
$teamsRoleAssigned = $false
Write-Host "`n=== Processing Teams Reader Role ===" -ForegroundColor Cyan
try {
  $teamsReaderRole = Get-MgDirectoryRole -Filter "displayName eq 'Teams Reader'" -ErrorAction SilentlyContinue
  if (-not $teamsReaderRole) {
    # Role not yet activated, activate it from template
    Write-Host "Activating Teams Reader role..." -ForegroundColor Yellow
    $allTemplates = Get-MgDirectoryRoleTemplate -All
    $roleTemplate = $allTemplates | Where-Object { $_.DisplayName -eq 'Teams Reader' }
    if ($roleTemplate) {
      $teamsReaderRole = New-MgDirectoryRole -RoleTemplateId $roleTemplate.Id
    }
  }
  
  if ($teamsReaderRole) {
    if ($PSCmdlet.ShouldProcess($WebAppMSI.DisplayName, "Assign Teams Reader directory role")) {
      try {
        $memberBody = @{ "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($WebAppMSI.Id)" }
        New-MgDirectoryRoleMemberByRef -DirectoryRoleId $teamsReaderRole.Id -BodyParameter $memberBody -ErrorAction Stop
        Write-Host "Teams Reader role: Assigned" -ForegroundColor Green
        $teamsRoleAssigned = $true
      }
      catch {
        if ($_.Exception.Message -match 'already exist') {
          Write-Host "Teams Reader role: Already assigned" -ForegroundColor Yellow
        } else {
          throw
        }
      }
    }
  } else {
    Write-Warning "Could not find or activate Teams Reader role"
  }
}
catch {
  Write-Warning "Failed to assign Teams Reader role: $($_.Exception.Message)"
}

# Process SharePoint permissions if requested
$spoResult = @{ Assigned = @(); Skipped = @() }
if ($IncludeSharePoint) {
  $spoResult = Grant-AppRoleAssignments -ResourceAppId $SharePointAppId -ResourceName 'SharePoint Online' -Permissions $SharePointRequiredPermissions -TargetSP $WebAppMSI
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Microsoft Graph - Assigned: $($graphResult.Assigned.Count), Already present: $($graphResult.Skipped.Count)" -ForegroundColor Green
Write-Host "Teams Reader Role - $(if ($teamsRoleAssigned) { 'Assigned' } else { 'Already present or skipped' })" -ForegroundColor Green
if ($IncludeExchangeOnline) {
  Write-Host "Exchange Online - Assigned: $($exoResult.Assigned.Count), Already present: $($exoResult.Skipped.Count)" -ForegroundColor Green
  Write-Host "Exchange Administrator Role - $(if ($exoRoleAssigned) { 'Assigned' } else { 'Already present or skipped' })" -ForegroundColor Green
}
if ($IncludeSharePoint) {
  Write-Host "SharePoint Online - Assigned: $($spoResult.Assigned.Count), Already present: $($spoResult.Skipped.Count)" -ForegroundColor Green
}

Write-Host "`nDetailed assignments:" -ForegroundColor Yellow
Write-Host ("Graph Assigned: {0}" -f ($graphResult.Assigned -join ', ')) -ForegroundColor Green
Write-Host ("Graph Already present: {0}" -f ($graphResult.Skipped -join ', ')) -ForegroundColor Yellow
if ($IncludeExchangeOnline) {
  Write-Host ("EXO Assigned: {0}" -f ($exoResult.Assigned -join ', ')) -ForegroundColor Green
  Write-Host ("EXO Already present: {0}" -f ($exoResult.Skipped -join ', ')) -ForegroundColor Yellow
}
if ($IncludeSharePoint) {
  Write-Host ("SPO Assigned: {0}" -f ($spoResult.Assigned -join ', ')) -ForegroundColor Green
  Write-Host ("SPO Already present: {0}" -f ($spoResult.Skipped -join ', ')) -ForegroundColor Yellow
}