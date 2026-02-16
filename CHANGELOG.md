# Changelog

All notable changes to the Maester & UTCM Dashboard will be documented in this file.

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
