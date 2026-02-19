# Changelog

All notable changes to the Maester & UTCM Dashboard will be documented in this file.

---

## [1.15.0] - 2026-02-20

> [!WARNING]
> **Please rerun the Enable-UTCM.ps1 and Grant-APIPermissions.ps1 scripts to ensure all permissions are correctly configured for the latest UTCM and Maester features.**

Added the Enable-UTCM.ps1 script to automate the setup of the Unified Tenant Configuration Management (UTCM) solution. This script grants all necessary Microsoft Graph API permissions, assigns Entra ID directory roles, and optionally configures Exchange Online RBAC roles for comprehensive UTCM functionality. The help page now includes detailed parameter documentation and a preview of the script for easy access.

### Added

- **Enable-UTCM.ps1** completely rewritten with full permission automation for all 5 UTCM workloads — grants 22 Graph API permissions (Entra ID, Intune, SharePoint), `Exchange.ManageAsApp`, and assigns directory roles (Global Reader, Security Reader, Compliance Administrator)
- New `-IncludeExchangeRBAC` switch for Exchange Online RBAC role management (registers UTCM SP in Exchange, assigns View-Only Configuration and Security Reader roles)
- Resource budget tracking with per-run usage indicators
- Retry baseline functionality when snapshot jobs fail
- Failed snapshot job details displayed in the UI with error reasons
- Monitor health status indicators with severity-based risk labeling
- UTCM API error detection with guided setup link to the help page
- Script download and preview for Enable-UTCM.ps1 and Grant-APIPermissions.ps1 on the help page
- Changelog page with version history and update highlights
- Automated update checks on the homepage with notifications for new releases of the container image

### Changed

- Log page updated with time filters, and more responsive.
- Background refresh uses adaptive intervals (30s to 5m) with fast mode during active wizard flows
- Improved snapshot error messaging with failed resource details from the Graph API
- Help page updated with full parameter documentation for Enable-UTCM.ps1

### Fixed

- Log cleanup no longer fails on concurrent file access (idempotent dual-logging with mutex)
- Wizard button correctly disables when UTCM API is not consented
- Modals close on Escape key press

### Removed
- Deprecated the "Priviliged Roles Guard" monitor template as the resources monitored was excessive (more than the allotted quota). Existing monitors of this type will continue to function but cannot be edited or recreated.

---

## [1.14.0] - 2026-02-16

### Added (UTCM - BETA)

- Unified Tenant Configuration Management (UTCM) dashboard
- Configuration snapshot creation and artifact download
- Active monitoring with baseline drift detection
- Severity-scored drift alerts (High, Medium, Low)
- Workflow for detected configuration changes
- Monitoring Wizard for guided monitor creation
- Background Graph API refresh every 5 minutes
- SQLite-based local persistence for history
- Webhook notifications for change detection, report completion, and health changes

---

## [1.13.0] - 2026-02-06

### Added

- Homepage redesign with overview cards and quick-access links
- Calendar-based Maester report browsing with side-by-side comparison
- On-demand Maester test execution with selectable services (Graph, Exchange, Teams, Security & Compliance)
- Real-time job status tracking with global toast notifications
- Automatic container version checking against GHCR every 3 hours
- Disk usage monitoring with low-space warnings
- Storage cleanup tools with protection against running jobs
- Dark/light theme support with persistent preference
- Kanban board for tracking failed test remediation
- Log viewer with auto-refresh, severity highlighting, and color-coded levels
- Emergency access account exclusions for tests
- Configurable cron schedule with local-time picker and UTC conversion

### Added (Infrastructure)

- User-assigned managed identity for secure Graph API access
- Easy Auth SSO with Entra ID
- SSH support (port 2222) for Azure Web App troubleshooting
- Grant-APIPermissions.ps1 script for automated permission assignment
- Exchange Online and Security & Compliance role management

---

## [1.12.1] - 2025-10-01

### Fixed

- Minor bug fixes and stability improvements

---

## [1.12.0] - 2025-09-29

### Added

- Initial public release of Maester Dashboard
- Calendar-based date navigation for test results
- Full HTML report rendering via iframe
- Stacked layout with compact date selector
- Syntax-highlighted code viewer
- PowerShell runner with managed identity support
- Container image with cron scheduling
- Azure deployment support
