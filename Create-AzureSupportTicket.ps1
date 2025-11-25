<#!
.SYNOPSIS
Interactive script to create an Azure Support ticket via Azure CLI.

.DESCRIPTION
Lists Azure support services, lets the user select one, then lists problem classifications
for that service. Collects ticket details and creates the support ticket using `az support in-subscription tickets create`.

.REQUIREMENTS
- Azure CLI installed (`az --version`)
- Logged in (`az login`)
- Appropriate Azure Support plan and permissions.

.NOTES
If Azure CLI commands change, update parsing logic accordingly.

.PARAMETER SubscriptionId
(Optional) Azure subscription ID to associate with the ticket.

.PARAMETER WhatIf
If supplied, shows the az command that would be executed without creating the ticket.

.PARAMETER DefaultSeverity
Optional default severity (critical|severe|moderate|minimal). Prompts if not provided.

.PARAMETER NonInteractive
Skips interactive selection; expects ServiceId, ProblemClassificationId, Title, Description, Contact parameters pre-supplied.

#>
[CmdletBinding()]param(
    [string]$SubscriptionId,
    [switch]$WhatIf,
    [ValidateSet('critical','severe','moderate','minimal','A','B','C','1')][string]$DefaultSeverity,
    [switch]$NonInteractive,
    [string]$ServiceId,
    [string]$ProblemClassificationId,
    [string]$ServiceNamePattern,
    [string]$ProblemClassificationPattern,
    [switch]$AutoPickFirst,
    [string]$Title,
    [string]$Description,
    [string]$ContactFirstName,
    [string]$ContactLastName,
    [string]$ContactEmail,
    [string]$ContactPhoneNumber,
    [string]$ContactCountry,
    [string]$ContactTimeZone,
    [string]$ContactLanguage = 'en-US',
    [ValidateSet('email','phone')][string]$ContactMethod = 'email',
    [string]$OutputJsonFile
)

function Assert-AzCliInstalled {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        Write-Error 'Azure CLI (az) not found in PATH. Install from https://learn.microsoft.com/cli/azure/install-azure-cli and retry.'
        exit 1
    }
}

function Ensure-AzSupportExtension {
    try {
        az extension show --name support --only-show-errors | Out-Null
    } catch {
        Write-Host 'Installing Azure CLI support extension...' -ForegroundColor Yellow
        az extension add --name support --only-show-errors | Out-Null
    }
}

function Assert-AzLoggedIn {
    $acct = az account show --output json 2>$null | ConvertFrom-Json
    if (-not $acct) {
        Write-Warning 'Not logged in. Executing az login...'
        az login | Out-Null
        $acct = az account show --output json 2>$null | ConvertFrom-Json
        if (-not $acct) { Write-Error 'Login failed.'; exit 1 }
    }
}

function Get-AzSupportServices {
    Write-Verbose 'Fetching Azure support services...'
    $json = az support services list --output json
    if (-not $json) { throw 'Failed to retrieve services.' }
    $services = $json | ConvertFrom-Json
    # Normalize properties if necessary
    return $services
}

function Resolve-ServiceByPattern($Services, [string]$Pattern, [switch]$ErrorIfMultiple) {
    if (-not $Pattern) { return $null }
    $matches = $Services | Where-Object { $_.displayName -like "*$Pattern*" -or $_.name -like "*$Pattern*" }
    if ($matches.Count -eq 0) { throw "No service matches pattern: $Pattern" }
    if ($matches.Count -gt 1 -and $ErrorIfMultiple) {
        Write-Warning "Multiple services matched pattern '$Pattern':"
        $matches | ForEach-Object { Write-Warning " - $($_.displayName) ($($_.name))" }
        throw 'Ambiguous pattern; refine ServiceNamePattern.'
    }
    return $matches[0]
}

function Select-SupportService ($Services) {
    if ($Services.Count -eq 0) { throw 'No services returned.' }
    Write-Host "\nAvailable Support Services:" -ForegroundColor Cyan
    $indexed = $Services | Sort-Object displayName | ForEach-Object { $_ }
    $i = 1
    foreach ($s in $indexed) {
        Write-Host ("[{0}] {1}" -f $i, $s.displayName)
        $i++
    }
    while ($true) {
        $sel = Read-Host 'Enter service number'
        if ([int]::TryParse($sel, [ref]$null)) {
            $index = [int]$sel
            if ($index -ge 1 -and $index -le $indexed.Count) {
                return $indexed[$index-1]
            }
        }
        Write-Warning 'Invalid selection. Try again.'
    }
}

function Get-ProblemClassifications($Service) {
    # CLI expects the short service name (e.g. 'virtual-machines') for --service-name
    $svcName = if ($Service.name) { $Service.name } else { $Service.id }
    Write-Verbose "Fetching problem classifications for service name: $svcName"
    $json = az support services problem-classifications list --service-name $svcName --output json
    if (-not $json) { throw 'Failed to retrieve problem classifications.' }
    return ($json | ConvertFrom-Json)
}

function Resolve-ProblemClassificationByPattern($ProblemClassifications, [string]$Pattern, [switch]$ErrorIfMultiple) {
    if (-not $Pattern) { return $null }
    $matches = $ProblemClassifications | Where-Object { $_.displayName -like "*$Pattern*" }
    if ($matches.Count -eq 0) { throw "No problem classification matches pattern: $Pattern" }
    if ($matches.Count -gt 1 -and $ErrorIfMultiple) {
        Write-Warning "Multiple problem classifications matched pattern '$Pattern':"
        $matches | ForEach-Object { Write-Warning " - $($_.displayName)" }
        throw 'Ambiguous pattern; refine ProblemClassificationPattern.'
    }
    return $matches[0]
}

function Select-ProblemClassification($ProblemClassifications) {
    if ($ProblemClassifications.Count -eq 0) { throw 'No problem classifications returned.' }
    Write-Host "\nProblem Classifications:" -ForegroundColor Cyan
    $sorted = $ProblemClassifications | Sort-Object displayName
    $i = 1
    foreach ($pc in $sorted) {
        Write-Host ("[{0}] {1}" -f $i, $pc.displayName)
        $i++
    }
    while ($true) {
        $sel = Read-Host 'Enter problem classification number'
        if ([int]::TryParse($sel, [ref]$null)) {
            $index = [int]$sel
            if ($index -ge 1 -and $index -le $sorted.Count) { return $sorted[$index-1] }
        }
        Write-Warning 'Invalid selection. Try again.'
    }
}

function Read-IfEmpty([string]$Current,[string]$Prompt,[switch]$Secret,[string]$DefaultValue='') {
    if ($Current) { return $Current }
    if ($Secret) { return (Read-Host $Prompt -AsSecureString | ConvertFrom-SecureString) }
    $promptText = if ($DefaultValue) { "$Prompt (default: $DefaultValue)" } else { $Prompt }
    $userInput = Read-Host $promptText
    if ([string]::IsNullOrWhiteSpace($userInput)) {
        if ($DefaultValue) { return $DefaultValue }
        return ''
    }
    return $userInput
}

function Ensure-Value([string]$Value,[string]$Name) {
    if (-not $Value) { throw "Missing required value: $Name" }
}

function Normalize-TimeZone([string]$TimeZone) {
    # Map common timezone abbreviations and formats to Windows timezone names
    $tzMap = @{
        'PST' = 'Pacific Standard Time'
        'PDT' = 'Pacific Standard Time'
        'EST' = 'Eastern Standard Time'
        'EDT' = 'Eastern Standard Time'
        'CST' = 'Central Standard Time'
        'CDT' = 'Central Standard Time'
        'MST' = 'Mountain Standard Time'
        'MDT' = 'Mountain Standard Time'
        'UTC' = 'UTC'
        'GMT' = 'GMT Standard Time'
        'UTC-8' = 'Pacific Standard Time'
        'UTC-7' = 'Mountain Standard Time'
        'UTC-6' = 'Central Standard Time'
        'UTC-5' = 'Eastern Standard Time'
        'UTC+0' = 'UTC'
        'UTC+1' = 'W. Europe Standard Time'
        'UTC+8' = 'Singapore Standard Time'
    }
    
    $tzUpper = $TimeZone.Trim().ToUpper()
    if ($tzMap.ContainsKey($tzUpper)) {
        return $tzMap[$tzUpper]
    }
    # Return as-is if not found in map (assume it's already a Windows timezone name)
    return $TimeZone
}

function Normalize-CountryCode([string]$CountryCode) {
    # Map common 2-letter ISO 3166-1 alpha-2 codes to 3-letter alpha-3 codes (required by Azure)
    $countryMap = @{
        'US' = 'USA'; 'CA' = 'CAN'; 'GB' = 'GBR'; 'AU' = 'AUS'; 'NZ' = 'NZL'
        'FR' = 'FRA'; 'DE' = 'DEU'; 'IT' = 'ITA'; 'ES' = 'ESP'; 'PT' = 'PRT'
        'IN' = 'IND'; 'CN' = 'CHN'; 'JP' = 'JPN'; 'KR' = 'KOR'; 'SG' = 'SGP'
        'BR' = 'BRA'; 'MX' = 'MEX'; 'AR' = 'ARG'; 'CL' = 'CHL'; 'CO' = 'COL'
        'ZA' = 'ZAF'; 'NG' = 'NGA'; 'EG' = 'EGY'; 'KE' = 'KEN'
        'SE' = 'SWE'; 'NO' = 'NOR'; 'DK' = 'DNK'; 'FI' = 'FIN'; 'NL' = 'NLD'
        'BE' = 'BEL'; 'CH' = 'CHE'; 'AT' = 'AUT'; 'PL' = 'POL'; 'CZ' = 'CZE'
        'IE' = 'IRL'; 'GR' = 'GRC'; 'TR' = 'TUR'; 'RU' = 'RUS'; 'UA' = 'UKR'
        'IL' = 'ISR'; 'AE' = 'ARE'; 'SA' = 'SAU'; 'MY' = 'MYS'; 'TH' = 'THA'
        'ID' = 'IDN'; 'PH' = 'PHL'; 'VN' = 'VNM'; 'PK' = 'PAK'; 'BD' = 'BGD'
    }
    
    $codeUpper = $CountryCode.Trim().ToUpper()
    # If already 3 letters, return as-is
    if ($codeUpper.Length -eq 3) { return $codeUpper }
    # If 2 letters, map to 3
    if ($countryMap.ContainsKey($codeUpper)) {
        return $countryMap[$codeUpper]
    }
    # Return as-is if not found
    return $CountryCode
}

function Create-SupportTicket($Params) {
    # Generate unique ticket name using timestamp
    $ticketName = "ticket-$(Get-Date -Format 'yyyyMMddHHmmss')"
    
    # Build the az support in-subscription tickets create command
    $cmd = @('support','in-subscription','tickets','create',
        '--ticket-name', $ticketName,
        '--title', $Params.Title,
        '--description', $Params.Description,
        '--problem-classification', $Params.ProblemClassificationId,
        '--severity', $Params.Severity,
        '--contact-first-name', $Params.ContactFirstName,
        '--contact-last-name', $Params.ContactLastName,
        '--contact-email', $Params.ContactEmail,
        '--contact-phone-number', $Params.ContactPhoneNumber,
        '--contact-country', $Params.ContactCountry,
        '--contact-timezone', $Params.ContactTimeZone,
        '--contact-method', $Params.ContactMethod,
        '--contact-language', $Params.ContactLanguage,
        '--advanced-diagnostic-consent', 'Yes',
        '--output','json'
    )
    if ($Params.SubscriptionId) { $cmd += @('--subscription',$Params.SubscriptionId) }

    $displayCmd = 'az ' + ($cmd -join ' ')
    Write-Host "\nExecuting: $displayCmd" -ForegroundColor Yellow

    if ($WhatIf) {
        Write-Host 'WhatIf specified. Ticket not created.' -ForegroundColor Magenta
        return
    }
    $json = az @cmd 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $joined = ($json -join ' ')
        if ($joined -match 'highestcriticalimpact' -or $joined -match 'highestcriticalseverity') {
            Write-Warning 'Request for highest critical impact severity appears to be restricted. Your support plan may not allow Sev 1. Please retry with A, B or C.'
        }
        Write-Error "Azure CLI command failed with exit code $exitCode. Output: $joined"
        throw 'Ticket creation failed.'
    }
    if (-not $json) { throw 'Ticket creation returned no output.' }
    $ticket = $json | ConvertFrom-Json
    Write-Host "\nTicket Created Successfully!" -ForegroundColor Green
    Write-Host "Ticket Name: $ticketName" -ForegroundColor Cyan
    if ($ticket.properties) {
        Write-Host "Title: $($ticket.properties.title)" -ForegroundColor Cyan
        Write-Host "Status: $($ticket.properties.status)" -ForegroundColor Cyan
        Write-Host "Severity: $($ticket.properties.severity)" -ForegroundColor Cyan
        if ($ticket.properties.supportTicketId) {
            Write-Host "Support Ticket ID: $($ticket.properties.supportTicketId)" -ForegroundColor Cyan
        }
    } else {
        Write-Host "Ticket ID: $($ticket.id)" -ForegroundColor Cyan
    }
    return $ticket
}

# Main Flow
try {
    Assert-AzCliInstalled
    Ensure-AzSupportExtension
    Assert-AzLoggedIn

    $services = Get-AzSupportServices
    if ($NonInteractive -or $ServiceNamePattern) {
        if (-not $ServiceId) {
            $selectedService = Resolve-ServiceByPattern -Services $services -Pattern $ServiceNamePattern -ErrorIfMultiple:$(-not $AutoPickFirst)
            $ServiceId = $selectedService.id
            Write-Host "Resolved Service (pattern '$ServiceNamePattern'): $($selectedService.displayName)" -ForegroundColor Cyan
        }
    } else {
        $selectedService = Select-SupportService -Services $services
        $ServiceId = $selectedService.id
        Write-Host "Selected Service: $($selectedService.displayName)" -ForegroundColor Cyan
    }

    Ensure-Value $ServiceId 'ServiceId'
    if (-not $selectedService) { $selectedService = ($services | Where-Object { $_.id -eq $ServiceId }) }

    $problemClassifications = Get-ProblemClassifications -Service $selectedService
    if ($NonInteractive -or $ProblemClassificationPattern) {
        if (-not $ProblemClassificationId) {
            $selectedPC = Resolve-ProblemClassificationByPattern -ProblemClassifications $problemClassifications -Pattern $ProblemClassificationPattern -ErrorIfMultiple:$(-not $AutoPickFirst)
            $ProblemClassificationId = $selectedPC.id
            Write-Host "Resolved Problem Classification (pattern '$ProblemClassificationPattern'): $($selectedPC.displayName)" -ForegroundColor Cyan
        }
    } else {
        $selectedPC = Select-ProblemClassification -ProblemClassifications $problemClassifications
        $ProblemClassificationId = $selectedPC.id
        Write-Host "Selected Problem Classification: $($selectedPC.displayName)" -ForegroundColor Cyan
    }
    Ensure-Value $ProblemClassificationId 'ProblemClassificationId'

    # Normalize provided default severity if user passed letter or 1
    if ($DefaultSeverity) {
        $inputNorm = $DefaultSeverity.ToUpper().Trim()
        switch ($inputNorm) {
            "1" { $DefaultSeverity = "critical" }
            "A" { $DefaultSeverity = "critical" }
            "B" { $DefaultSeverity = "moderate" }
            "C" { $DefaultSeverity = "minimal" }
        }
    }

    if (-not $DefaultSeverity) {
        Write-Host '\nSeverity choices:' -ForegroundColor Cyan
        Write-Host '  1 : Highest critical impact (Premium support only; may fail if plan not eligible)' -ForegroundColor Yellow
        Write-Host '  A : Critical' -ForegroundColor Yellow
        Write-Host '  B : Moderate' -ForegroundColor Yellow
        Write-Host '  C : Minimal (default)' -ForegroundColor Yellow
        $severityInput = Read-Host 'Enter severity (1/A/B/C) [default: C]'
        if ([string]::IsNullOrWhiteSpace($severityInput)) {
            $DefaultSeverity = "minimal"
        } else {
            switch ($severityInput.ToUpper().Trim()) {
                "1" { $DefaultSeverity = "critical" }
                "A" { $DefaultSeverity = "critical" }
                "B" { $DefaultSeverity = "moderate" }
                "C" { $DefaultSeverity = "minimal" }
                "CRITICAL" { $DefaultSeverity = "critical" }
                "SEVERE" { $DefaultSeverity = "severe" }
                "MODERATE" { $DefaultSeverity = "moderate" }
                "MINIMAL" { $DefaultSeverity = "minimal" }
                default { $DefaultSeverity = "minimal"; Write-Warning 'Unrecognized input; defaulting to minimal.' }
            }
        }
    }
    Ensure-Value $DefaultSeverity 'Severity'

    $Title = Read-IfEmpty $Title 'Ticket Title'
    $Description = Read-IfEmpty $Description 'Problem Description'
    $ContactFirstName = Read-IfEmpty $ContactFirstName 'Contact First Name'
    $ContactLastName = Read-IfEmpty $ContactLastName 'Contact Last Name'
    $ContactEmail = Read-IfEmpty $ContactEmail 'Contact Email'
    $ContactPhoneNumber = Read-IfEmpty $ContactPhoneNumber 'Contact Phone Number' -DefaultValue '+1-555-0000'
    $ContactCountry = Read-IfEmpty $ContactCountry 'Contact Country (2 or 3 letter code, e.g. US, USA)' -DefaultValue 'USA'
    $ContactTimeZone = Read-IfEmpty $ContactTimeZone 'Contact Time Zone (e.g. PST, UTC-8, Pacific Standard Time)' -DefaultValue 'Pacific Standard Time'
    # Normalize timezone and country to required formats
    $ContactTimeZone = Normalize-TimeZone $ContactTimeZone
    $ContactCountry = Normalize-CountryCode $ContactCountry

    $requiredFields = @{
        'Title' = $Title
        'Description' = $Description
        'ContactFirstName' = $ContactFirstName
        'ContactLastName' = $ContactLastName
        'ContactEmail' = $ContactEmail
        'ContactPhoneNumber' = $ContactPhoneNumber
        'ContactCountry' = $ContactCountry
        'ContactTimeZone' = $ContactTimeZone
    }
    foreach ($field in $requiredFields.GetEnumerator()) {
        if ([string]::IsNullOrWhiteSpace($field.Value)) {
            throw "Missing required field: $($field.Key)"
        }
    }

    $params = [pscustomobject]@{
        ServiceId              = $ServiceId
        ProblemClassificationId= $ProblemClassificationId
        Severity               = $DefaultSeverity
        Title                  = $Title
        Description            = $Description
        ContactFirstName       = $ContactFirstName
        ContactLastName        = $ContactLastName
        ContactEmail           = $ContactEmail
        ContactPhoneNumber     = $ContactPhoneNumber
        ContactCountry         = $ContactCountry
        ContactTimeZone        = $ContactTimeZone
        ContactLanguage        = $ContactLanguage
        ContactMethod          = $ContactMethod
        SubscriptionId         = $SubscriptionId
    }

    $ticket = Create-SupportTicket -Params $params
    if ($OutputJsonFile -and $ticket) {
        try {
            $ticket | ConvertTo-Json -Depth 6 | Out-File -FilePath $OutputJsonFile -Encoding UTF8
            Write-Host "Ticket JSON saved to $OutputJsonFile" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to write ticket JSON to $OutputJsonFile : $_"
        }
    }
}
catch {
    Write-Error $_
    exit 1
}
