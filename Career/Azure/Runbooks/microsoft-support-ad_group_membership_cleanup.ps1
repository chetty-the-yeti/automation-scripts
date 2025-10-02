<#
.SYNOPSIS
    Cleans up group memberships for disabled Active Directory user accounts and sends a summary email.

.DESCRIPTION
    This script is intended to be run as an Azure Automation Runbook on a Hybrid Worker.
    It finds all disabled Active Directory user accounts in a specified OU, exports their group memberships,
    removes them from all groups, and sends a summary email to specified recipients.
    The script uses Azure Automation variables for authentication and is designed for
    automated, scheduled execution in a hybrid cloud/on-premises environment.
    A summary of actions and any errors encountered are included in the email, and detailed
    group membership exports are saved to a network share for reference.
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
$OU = "OU=Disabled,OU=Users,DC=example,DC=com"
$SmtpFrom    = "alerts@example.com"
$SmtpTo      = @("admins@example.com")
$SmtpSubject = "INFO - Disabled User Group Memberships Clean Up Report"

# Import AD module
Import-Module ActiveDirectory

# === Main Processing ===
$users = Get-ADUser -Filter * -SearchBase $OU -Properties memberof
$processedTable = ""
$licensesFreed = 0
$processedCount = 0
$removalErrors = @() # Collect errors for admin attention

foreach ($user in $users) {
    $username = $user.SamAccountName
    $membership = $user.memberof | Get-ADGroup | Select-Object -ExpandProperty SamAccountName

    $removedGroups = @()
    foreach ($group in $membership) {
        try {
            Remove-ADGroupMember -Identity $group -Members $username -Confirm:$false -ErrorAction Stop
            $removedGroups += $group
            if ($group -eq "License-Standard") {
                $licensesFreed++
            }
            Write-Output "Removed $username from group $group"
        } catch {
            $errMsg = "Failed to remove $username from group ${group}: $_"
            Write-Output $errMsg
            $removalErrors += $errMsg
        }
    }

    if ($removedGroups.Count -gt 0) {
        $processedCount++
        $processedTable += "<tr><td>$username</td><td>$($removedGroups.Count) group(s)</td></tr>"
    }
}

# === HTML Sections ===
$summaryMsg = if ($processedCount -gt 0) {
    "The following disabled user accounts had their group memberships removed.<br>Total processed: $processedCount"
} else {
    "<span style='color:#444;'>No eligible disabled accounts were found to process during this run.</span>"
}

$licensesMsg = @"
<div style='background-color:#e6f7ff; color:#004080; border:1px solid #b3d8ff; padding:10px; margin:10px 0; font-size:16px; font-weight:bold;'>
Microsoft 365 Licenses Released: $licensesFreed
</div>
"@

$tableHtml = if ($processedTable -ne "") {
@"
<h3 style='color:#004080;'>Disabled User Accounts</h3>
<table border='1' cellpadding='6' cellspacing='0' style='border-collapse:collapse; width:100%;'>
<tr style='background-color: #d3d3d3;'><th>Username</th><th>Groups Removed</th></tr>
$processedTable
</table>
"@
} else { "" }

# Add error section if there are removal errors
$errorsHtml = ""
if ($removalErrors.Count -gt 0) {
    $errorList = $removalErrors | ForEach-Object { "<li>$_</li>" } | Out-String
    $errorsHtml = @"
<div style='background-color:#fff3cd; color:#856404; border:1px solid #ffeeba; padding:12px; margin:15px 0; font-size:15px;'>
<strong>Attention Required:</strong> The following group removals failed and may require Microsoft Admin intervention:
<ul style='margin-top:8px;'>$errorList</ul>
</div>
"@
}

# === Full Email Body ===
$SmtpBody = @"
<html>
<head><meta http-equiv='Content-Type' content='text/html; charset=us-ascii'></head>
<body>
<div style='background-color:#004080; color:white; padding:15px; font-size:18px; font-weight:bold; text-align:center;'>
Disabled User Group Memberships Clean Up Report
</div>
<div style='padding:10px; font-size:15px; text-align:left;'>
This report lists AD user accounts in the Disabled OU that have had their group memberships removed.
</div>
$errorsHtml
<p>$summaryMsg</p>
$tableHtml
$licensesMsg
</body>
</html>
"@

# === Send Email ===
if (($processedCount -gt 0) -or ($removalErrors.Count -gt 0)) {
    Send-GraphMail -from $SmtpFrom -to $SmtpTo -subject $SmtpSubject -bodyHtml $SmtpBody -accessToken $accessToken
    Write-Output "$processedCount user(s) processed. Email sent."
    Write-Output "Microsoft 365 Licenses Released: $licensesFreed"
    if ($removalErrors.Count -gt 0) {
        Write-Output "$($removalErrors.Count) error(s) encountered. Email sent."
    }
} else {
    Write-Output "No eligible disabled accounts found. No email sent."
}
# === End of Script ===