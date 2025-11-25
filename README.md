# PowerShell script to create Support ticket in Azure

## Overview
`Create-AzureSupportTicket.ps1` creates Azure Support tickets using the Azure CLI. You can run it interactively or supply patterns/IDs for fully automated (non-interactive) execution.

This script is especially useful during Azure Portal outages or when the Portal is unavailable, because it relies only on PowerShell and the Azure CLI (no Portal dependency).

Flow:
1. Fetch support services (`az support services list`).
2. Select service (interactive menu or pattern match).
3. Fetch problem classifications for the selected service.
4. Select classification (interactive or pattern match).
5. Collect ticket details & contact info (or pass as parameters).
6. Execute `az support in-subscription tickets create`.

## Prerequisites
- PowerShell 5.1+ or PowerShell 7+.
- Azure CLI installed: https://learn.microsoft.com/cli/azure/install-azure-cli
- Logged in: `az login`
- Appropriate Azure Support plan and permissions.
- Azure CLI support extension: the script auto-installs it (`az extension add -n support`).

### Pre-Requisites (copy/paste)
Run these once before using the script:

```powershell
# 1) Install Azure CLI (if not installed)
# https://learn.microsoft.com/cli/azure/install-azure-cli

# 2) Sign in and pick the right subscription
az login
az account list -o table
az account set -s <subscription-guid-or-name>

# 3) Ensure the Support extension is available
az extension add -n support --upgrade
az extension show -n support -o table

# 4) (Recommended) Update Azure CLI to latest
az upgrade --yes
```

Required access: You must have permissions to create Support tickets for the selected subscription and an active Azure support plan appropriate for your chosen severity.

## Usage

### Interactive
```powershell
pwsh -File .\Create-AzureSupportTicket.ps1
```

### Interactive with explicit subscription
```powershell
pwsh -File .\Create-AzureSupportTicket.ps1 -SubscriptionId "<subscription-guid>"
```

### Dry run (no ticket created)
```powershell
pwsh -File .\Create-AzureSupportTicket.ps1 -WhatIf `
    -ServiceNamePattern "virtual-machines" `
    -ProblemClassificationPattern "Cannot start"
```

### Pattern-based non-interactive (auto pick first match)
```powershell
pwsh -File .\Create-AzureSupportTicket.ps1 -NonInteractive -AutoPickFirst `
    -ServiceNamePattern "virtual-machines" `
    -ProblemClassificationPattern "start" `
    -DefaultSeverity moderate `
    -Title "VM start failures" `
    -Description "Multiple VMs failing to start after scheduled maintenance." `
    -ContactFirstName "Jane" `
    -ContactLastName "Doe" `
    -ContactEmail "jane@example.com" `
    -ContactPhoneNumber "+1-555-0100" `
    -ContactCountry "US" `
    -ContactTimeZone "Pacific Standard Time" `
    -SubscriptionId "<subscription-guid>" `
    -OutputJsonFile ticket.json
```

### Fully ID driven (skip pattern logic)
If you already know the `ServiceId` and `ProblemClassificationId`:
```powershell
pwsh -File .\Create-AzureSupportTicket.ps1 -NonInteractive `
    -ServiceId "/providers/Microsoft.Support/services/virtual-machines" `
    -ProblemClassificationId "/providers/Microsoft.Support/services/virtual-machines/problemClassifications/compute-vm-start" `
    -DefaultSeverity severe `
    -Title "VM start issue" `
    -Description "Start operation repeatedly failing with InternalError." `
    -ContactFirstName "John" `
    -ContactLastName "Smith" `
    -ContactEmail "john@example.com" `
    -ContactPhoneNumber "+1-555-0123" `
    -ContactCountry "US" `
    -ContactTimeZone "Pacific Standard Time"
```

## Parameters

- `-SubscriptionId`: Azure subscription GUID. If omitted, uses current `az account show` context.
- `-WhatIf`: Prints the exact `az` command; does not create a ticket.
- `-DefaultSeverity`: Accepts `1 | A | B | C | highestcriticalimpact | critical | moderate | minimal`. The interactive prompt allows one-character input:
    - `1` → `highestcriticalimpact` (Premium support only; will fail if plan not eligible)
    - `A` → `critical`
    - `B` → `moderate`
    - `C` → `minimal` (default)
    If an ineligible highest impact is chosen, Azure will return an error indicating plan restrictions.
- `-NonInteractive`: Skips interactive menus; provide IDs or patterns for service/classification and all contact details.
- `-ServiceId`: Full service resource ID from `az support services list` (e.g., `/providers/Microsoft.Support/services/virtual-machines`).
- `-ProblemClassificationId`: Full problem classification ID under the selected service.
- `-ServiceNamePattern`: Case-insensitive substring matched against service `displayName` or `name` (e.g., `virtual-machines`).
- `-ProblemClassificationPattern`: Case-insensitive substring matched against classification `displayName` (e.g., `start`).
- `-AutoPickFirst`: When patterns match multiple results, pick the first match instead of erroring.
- `-Title`: Ticket title/summary. Required.
- `-Description`: Detailed problem description. Required.
- `-ContactFirstName`, `-ContactLastName`, `-ContactEmail`, `-ContactPhoneNumber`: Required contact details.
- `-ContactCountry`: ISO 3166-1 alpha-3 code (e.g., `USA`, `CAN`). The script accepts alpha-2 (`US`) and maps to alpha-3 automatically.
- `-ContactTimeZone`: Windows timezone name (e.g., `Pacific Standard Time`). The script normalizes common inputs like `PST`, `UTC-8`, `EST`.
- `-ContactLanguage`: Preferred language tag (default `en-US`).
- `-ContactMethod`: `email` (default) or `phone`.
- `-OutputJsonFile`: If provided, writes the created ticket JSON to this file.

## Input Normalization

- **Severity mapping**: `1`→`highestcriticalimpact` (Premium-only), `A`→`critical`, `B`→`moderate`, `C`→`minimal`; full names also accepted. If `1` fails due to plan limits, re-run selecting `A`, `B`, or `C`.
- **Timezone mapping**: Accepts common forms like `PST`, `EST`, `UTC-8`, `UTC+0` and converts to Windows timezone names.
 - **Timezone mapping**: Accepts common forms like `PST`, `EST`, `UTC-8`, `UTC+0`, `IST` (mapped to `India Standard Time`), and converts them to Windows timezone names.
- **Country code mapping**: Accepts alpha-2 codes (`US`, `GB`, `DE`, etc.) and converts to alpha-3 (`USA`, `GBR`, `DEU`).

## Notes

- Service short `name` is used for listing problem classifications; ticket creation requires the full problem classification `id`.
- The script ensures the Azure CLI support extension is installed; you can manually run `az extension add -n support`.
- Patterns are matched with PowerShell `-like` using wildcards around your input.

## Troubleshooting

- **No services returned**: Ensure you are logged in (`az login`) and have required permissions.
- **Unrecognized arguments or command**: Update Azure CLI (`az upgrade`) and ensure the support extension is installed (`az extension add -n support`).
- **Invalid country code**: Use ISO alpha-3 (e.g., `USA`). Alpha-2 inputs are auto-mapped when possible.
- **Invalid timezone**: Provide a Windows timezone name or a supported shorthand (e.g., `PST`).
- **Inspect CLI call**: Use `-WhatIf` to see the exact `az` command the script would run.

