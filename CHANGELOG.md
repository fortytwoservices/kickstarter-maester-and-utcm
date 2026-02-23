# Changelog

All notable changes to the Maester & UTCM Dashboard will be documented in this file.

---

## [1.15.0] - 2026-02-24

> [!WARNING]
> Please rerun the Enable-UTCM.ps1 and Grant-APIPermissions.ps1 scripts to ensure all permissions are correctly configured for the latest UTCM and Maester features.
>
> We also recommend that you remove existing monitors and recreate them to take advantage of the new and improved set of resources included in the monitor templates. Existing monitors will continue to function.

Added the Enable-UTCM.ps1 script to automate the setup of the Unified Tenant Configuration Management (UTCM) solution. This script grants all necessary Microsoft Graph API permissions, assigns Entra ID directory roles, and optionally configures Exchange Online RBAC roles for comprehensive UTCM functionality. The help page now includes detailed parameter documentation and a preview of the script for easy access.

### Added

- Enable-UTCM.ps1 script to automate UTCM setup with Graph API permissions, Entra ID roles, and optional Exchange Online RBAC role assignment [Issue #4](https://github.com/fortytwoservices/kickstarter-maester-and-utcm/issues/4)
- Resource budget tracking with per-run usage indicators
- Retry baseline functionality when snapshot jobs fail, failed snapshot job details displayed in the UI with error reasons
- Monitor health status indicators with severity-based risk labeling
- UTCM API error detection with guided setup link to the help page
- Script download and preview for Enable-UTCM.ps1 and Grant-APIPermissions.ps1 on the help page
- Changelog page with version history and update highlights
- Automated update checks on the homepage with notifications for new releases of the container image
- Possibility to add custom monitors, where you can specify which resources to include in a monitor
- Possibility to add emergency access accounts both by UPN and object ID [Issue #2](https://github.com/fortytwoservices/kickstarter-maester-and-utcm/issues/2)

### Changed

- Reworked the monitor presets
- The "Test Results Trend" chart is now sorted in chronological order (oldest to newest) for better trend visualization [Issue #5](https://github.com/fortytwoservices/kickstarter-maester-and-utcm/issues/5)
- Log page updated with time filters, and more responsive. [Issue #3](https://github.com/fortytwoservices/kickstarter-maester-and-utcm/issues/3)
- Background refresh uses adaptive intervals (30s to 5m) with fast mode during active wizard flows
- Improved snapshot error messaging with failed resource details from the Graph API
- Help page updated with full parameter documentation for Enable-UTCM.ps1
- Changed the parameters and RBAC permissions/roles of the Grant-APIPermissions.ps1 script to align with the new Enable-UTCM.ps1 script, which now includes an option to assign Exchange Online RBAC roles in addition to Graph API permissions and Entra ID directory roles

### Fixed

- Log cleanup no longer fails on concurrent file access
- Wizard button correctly disabled when UTCM API is not consented
- Modals close on Escape key press
- Improved logging and error handling all over the application, especially around baseline creation and snapshot job monitoring

### Removed

- Deprecated the "Priviliged Roles Guard" monitor template as the resources monitored was excessive (more than the allotted quota). Existing monitors of this type will continue to work

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
