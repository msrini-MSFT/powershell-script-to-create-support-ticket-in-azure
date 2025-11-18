<#
Wrapper script: prompts for user inputs, then invokes
Create-AzureSupportTicket.ps1 non-interactively with pattern-based selection.
#>

# --- Script Defaults ---
$DefaultTimezone = "Pacific Standard Time"
$DefaultCountry  = "US"
$DefaultLanguage = "en-US"
$PreferredContact = "email"  # used by the underlying script via defaults

function Get-Input {
    param(
        [string]$PromptText,
        [string]$DefaultValue = "",
        [bool]$IsMandatory = $true,
        [string[]]$ValidOptions = $null
    )
    $InputPrompt = $PromptText
    if (-not [string]::IsNullOrEmpty($DefaultValue)) { $InputPrompt += " (Default: $DefaultValue)" }
    do {
        if ($ValidOptions) { Write-Host "Valid Options: $($ValidOptions -join ', ')" -ForegroundColor Cyan }
        $Input = Read-Host -Prompt $InputPrompt
        if ([string]::IsNullOrEmpty($Input)) {
            if ($DefaultValue) { $Input = $DefaultValue }
            elseif ($IsMandatory) { Write-Host "This field is mandatory. Please provide a value." -ForegroundColor Yellow }
        }
        if ($ValidOptions -and $Input) {
            if ($ValidOptions -notcontains $Input.ToUpper().Trim()) {
                Write-Host "Invalid input. Please choose from the valid options." -ForegroundColor Red
                $Input = $null
            } else { $Input = $Input.Trim() }
        }
    } while ($IsMandatory -and [string]::IsNullOrEmpty($Input))
    return $Input
}

Write-Host "--- Azure Support Ticket Creation (Guided) ---" -ForegroundColor Green
Write-Host "This collects inputs and calls the non-interactive creator." -ForegroundColor Cyan

# 1. Subscription
Write-Host ">> STEP 1: Subscription Details" -ForegroundColor Yellow
$SubscriptionID = Get-Input -Prompt "Enter the Subscription ID associated with the issue" -IsMandatory $true

# 2. Title & Description
Write-Host "`n>> STEP 2: Problem Summary" -ForegroundColor Yellow
$Title = Get-Input -Prompt "Enter a concise Title for the support ticket" -IsMandatory $true
$Description = Get-Input -Prompt "Enter a detailed Description of the issue" -IsMandatory $true

# 3. Severity
Write-Host "`n>> STEP 3: Severity Level" -ForegroundColor Yellow
$SeverityOptions = @("A","B","C")
Write-Host "A - Critical (critical)"
Write-Host "B - Moderate (moderate)"
Write-Host "C - Minimal (minimal)"
$SeverityLetter = Get-Input -Prompt "Select Severity (A, B, or C)" -ValidOptions $SeverityOptions -DefaultValue "C"
switch ($SeverityLetter.ToUpper()) {
    "A" { $SeverityLabel = "critical" }
    "B" { $SeverityLabel = "moderate" }
    "C" { $SeverityLabel = "minimal" }
    default { $SeverityLabel = "minimal" }
}

# 4. Contact details
Write-Host "`n>> STEP 4: Contact Details" -ForegroundColor Yellow
$ContactEmail      = Get-Input -Prompt "Enter your contact Email Address" -IsMandatory $true
$ContactFirstName  = Get-Input -Prompt "Enter your First Name" -IsMandatory $true
$ContactLastName   = Get-Input -Prompt "Enter your Last Name" -IsMandatory $true
$ContactPhone      = Get-Input -Prompt "Enter your Phone Number (with country code)" -IsMandatory $true
$Timezone          = Get-Input -Prompt "Enter your Time Zone (e.g., Pacific Standard Time)" -DefaultValue $DefaultTimezone
$Country           = Get-Input -Prompt "Enter your Country Code (e.g., US, CA)" -DefaultValue $DefaultCountry

# 5. Invoke interactive creator (you will select Service & Problem Classification next)
Write-Host "`n--- Creating Support Ticket (interactive service/classification selection) ---" -ForegroundColor Magenta

$creator = Join-Path $PSScriptRoot 'Create-AzureSupportTicket.ps1'
if (-not (Test-Path $creator)) {
    Write-Error "Cannot find Create-AzureSupportTicket.ps1 in $PSScriptRoot"
    exit 1
}

& $creator `
    -SubscriptionId $SubscriptionID `
    -DefaultSeverity $SeverityLabel `
    -Title $Title `
    -Description $Description `
    -ContactFirstName $ContactFirstName `
    -ContactLastName $ContactLastName `
    -ContactEmail $ContactEmail `
    -ContactPhoneNumber $ContactPhone `
    -ContactCountry $Country `
    -ContactTimeZone $Timezone `
    -ContactLanguage $DefaultLanguage `
    -ContactMethod $PreferredContact

if ($LASTEXITCODE -ne 0) {
    Write-Host "`n❌ ERROR: Creating the support ticket failed. Check inputs and subscription access." -ForegroundColor Red
}