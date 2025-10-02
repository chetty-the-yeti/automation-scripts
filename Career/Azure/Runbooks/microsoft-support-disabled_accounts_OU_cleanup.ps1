<#
.SYNOPSIS
    This runbook moves expired standard AD users to Disabled OU and lists expired admin users for manual review.
.DESCRIPTION
    Sends an HTML report using Microsoft Graph from Azure Automation.
#>

$ErrorActionPreference = "Stop"

# === Azure Graph Credentials ===
$clientId     = Get-AutomationVariable -Name "microsoft-support-automations_app-ClientID"
$clientSecret = Get-AutomationVariable -Name "microsoft-support-automations_app-ClientSecret"
$tenantId     = Get-AutomationVariable -Name "microsoft-support-automations_app-TenantID"

# === Acquire Access Token ===
$body = @{
    client_id     = $clientId
    scope         = "https://graph.microsoft.com/.default"
    client_secret = $clientSecret
    grant_type    = "client_credentials"
}
$tokenResponse = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Body $body
$accessToken = $tokenResponse.access_token

Function Send-GraphMail($from, $to, $subject, $bodyHtml, $accessToken) {
    $toRecipients = @()
    foreach ($recipient in $to) {
        $toRecipients += @{ emailAddress = @{ address = $recipient } }
    }
    $mailPayload = @{
        message = @{
            subject = $subject
            body = @{ contentType = "HTML"; content = $bodyHtml }
            toRecipients = $toRecipients
        }
        saveToSentItems = $false
    }
    $mailUrl = "https://graph.microsoft.com/v1.0/users/$from/sendMail"
    Invoke-RestMethod -Uri $mailUrl -Headers @{ Authorization = "Bearer $accessToken" } -Method POST -Body ($mailPayload | ConvertTo-Json -Depth 10) -ContentType 'application/json'
}

# === Configuration ===
$SourceOU        = "OU=Users,DC=example,DC=com"
$TargetOU        = "OU=Disabled,OU=Users,DC=example,DC=com"
$AdminOU         = "OU=Admin,OU=Users,DC=example,DC=com"
$AdminDisabledOU = "OU=Disabled,OU=Admin,OU=Users,DC=example,DC=com"

$SmtpFrom       = "alerts@example.com"
$SmtpTo         = @("admins@example.com")
$SmtpSubject    = "INFO - Disabled AD Accounts Clean Up Report"
$thresholdDate  = (Get-Date).AddDays(-90)

# === Import Active Directory ===
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    throw "Active Directory module not found on Hybrid Worker."
}
Import-Module ActiveDirectory

# === Helper: Shorten OU Path ===
function Get-ShortOUPath($dn) {
    if ($dn -match "OU=Users,DC=example,DC=com") {
        $pattern = "(OU=.*?),OU=Users,DC=example,DC=com"
        return [regex]::Match($dn, $pattern).Groups[1].Value
    }
    return ""
}

# === Get Standard Users to Move ===
$StandardUsers = Get-ADUser -SearchBase $SourceOU -SearchScope Subtree `
    -Filter {Enabled -eq $false -and accountExpires -ne 0} `
    -Properties accountExpires, DistinguishedName |
    Where-Object {
        $_.DistinguishedName -notlike "*OU=Admin,OU=Users,*" -and
        $_.DistinguishedName -notlike "*OU=Disabled,OU=Users,*"
    }

# === Get Admin Users for Reporting Only (OneLevel, exclude Admin Disabled OU) ===
$AdminUsers = Get-ADUser -SearchBase $AdminOU -SearchScope OneLevel `
    -Filter {Enabled -eq $false -and accountExpires -ne 0} `
    -Properties accountExpires, DistinguishedName |
    Where-Object {
        $_.DistinguishedName -notlike "*OU=Disabled,OU=Admin,OU=Users,*"
    }

# === Initialize ===
$MovedCount      = 0
$standardTable   = ""
$adminTable      = ""

# === Process Standard Users ===
foreach ($user in $StandardUsers) {
    $expires = $user.accountExpires
    if ($expires -ne $null -and $expires -ne 0 -and $expires -ne 9223372036854775807) {
        $expiresDate = [datetime]::FromFileTime([int64]$expires)
        if ($expiresDate -lt $thresholdDate) {
            $shortOU = Get-ShortOUPath($user.DistinguishedName)
            try {
                Move-ADObject -Identity $user.DistinguishedName -TargetPath $TargetOU -ErrorAction Stop
                $MovedCount++
                Write-Output "Moved account: $($user.Name)"
                $standardTable += "<tr><td>$($user.Name)</td><td><span style='font-size:smaller;'>$shortOU</span></td><td><span style='font-size:smaller;'>$(Get-ShortOUPath($TargetOU))</span></td></tr>"
            } catch {
                $standardTable += "<tr><td>$($user.Name) (ERROR: $($_.Exception.Message))</td><td><span style='font-size:smaller;'>$shortOU</span></td><td><span style='font-size:smaller;'>$(Get-ShortOUPath($TargetOU))</span></td></tr>"
            }
        }
    }
}

# === Process Admin Users for Reporting ===
foreach ($admin in $AdminUsers) {
    $expires = $admin.accountExpires
    if ($expires -ne $null -and $expires -ne 0 -and $expires -ne 9223372036854775807) {
        $expiresDate = [datetime]::FromFileTime([int64]$expires)
        if ($expiresDate -lt $thresholdDate) {
            $shortOU = Get-ShortOUPath($admin.DistinguishedName)
            $adminTable += "<tr><td>$($admin.Name)</td><td><span style='font-size:smaller;'>$shortOU</span></td></tr>"
        }
    }
}

# === HTML Sections ===
$summaryMsg = if ($MovedCount -gt 0) {
    "The following Active Directory accounts have been moved to the Disabled OU.<br>Total moved: $MovedCount"
} else {
    "<span style='color:#444;'>No eligible standard accounts were found to move during this run.</span>"
}

$tableHtml = if ($standardTable -ne "") {
@"
<h3 style='color:#004080;'>Standard User Accounts</h3>
<table border='1' cellpadding='6' cellspacing='0' style='border-collapse:collapse; width:100%;'>
<tr style='background-color: #d3d3d3;'><th>Name</th><th>Original OU</th><th>Destination OU</th></tr>
$standardTable
</table>
"@
} else { "" }

$adminHtml = if ($adminTable -ne "") {
@"
<h3 style='color:#b22222;'>Admin Accounts in Active OU (Manual Review)</h3>
<p style='font-size:small; font-style:italic; color:#555;'>
These accounts are in the Admin OU and have been disabled for more than 90 days.<br>
If confirmed, please move them manually to:<br>
<b>$AdminDisabledOU</b>
</p>
<table border='1' cellpadding='6' cellspacing='0' style='border-collapse:collapse; width:100%;'>
<tr style='background-color: #ffe0e0;'><th>Name</th><th>Current OU</th></tr>
$adminTable
</table>
"@
} else { "" }

# === Full Email Body ===
$SmtpBody = @"
<html>
<head><meta http-equiv='Content-Type' content='text/html; charset=us-ascii'></head>
<body>
<div style='background-color:#004080; color:white; padding:15px; font-size:18px; font-weight:bold; text-align:center;'>
Disabled AD Accounts Clean Up Report
</div>
<div style='padding:10px; font-size:15px;'>
This report lists AD user accounts that have been disabled for 90+ days.
</div>
<p>$summaryMsg</p>
$tableHtml
$adminHtml
</body>
</html>
"@

# === Conditional Email Delivery ===
if ($MovedCount -gt 0 -or $adminTable -ne "") {
    Send-GraphMail -from $SmtpFrom -to $SmtpTo -subject $SmtpSubject -bodyHtml $SmtpBody -accessToken $accessToken
    Write-Output "$MovedCount standard account(s) moved or admin accounts flagged. Email sent."
} else {
    Write-Output "No standard or admin accounts met the 90-day threshold. No email sent."
}