<#
.SYNOPSIS
    Expiring User Account Alert
.DESCRIPTION
    This runbook checks for on-prem Active Directory user accounts that are about to expire and sends an alert email.
    It is designed to run on the Hybrid Workers.
    Requirements:
      - PowerShell 7 installed and in PATH on Hybrid Worker.
      - RSAT: Active Directory module installed on Hybrid Worker.
      - Hybrid Worker service account has permission to query AD.
      - Select the Hybrid Worker group when running the runbook.
#>

$ErrorActionPreference = "Stop"

# Get stored Automation variables
$clientId     = Get-AutomationVariable -Name "microsoft-support-automations_app-ClientID"
$clientSecret = Get-AutomationVariable -Name "microsoft-support-automations_app-ClientSecret"
$tenantId     = Get-AutomationVariable -Name "microsoft-support-automations_app-TenantID"

# Get an access token using client credentials
$body = @{
    client_id     = $clientId
    scope         = "https://graph.microsoft.com/.default"
    client_secret = $clientSecret
    grant_type    = "client_credentials"
}
$tokenResponse = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Body $body
$accessToken = $tokenResponse.access_token

Function NZDateTime {
    Get-Date -Format "dd/MM/yyyy hh:mm:ss"
}

Write-Output "$(NZDateTime) [INFO] Script started"

$SmtpFrom = "alerts@example.com"
$SmtpTo = @("admins@example.com", "servicedesk@example.com")

Function Send-GraphMail($from, $to, $subject, $bodyHtml, $accessToken) {
    $toRecipients = @()
    foreach ($recipient in $to) {
        $toRecipients += @{
            emailAddress = @{
                address = $recipient
            }
        }
    }
    $mailPayload = @{
        message = @{
            subject = $subject
            body = @{
                contentType = "HTML"
                content     = $bodyHtml
            }
            toRecipients = $toRecipients
        }
        saveToSentItems = "false"
    }
    $mailUrl = "https://graph.microsoft.com/v1.0/users/$from/sendMail"
    Invoke-RestMethod -Uri $mailUrl -Headers @{ Authorization = "Bearer $accessToken" } -Method POST -Body ($mailPayload | ConvertTo-Json -Depth 10) -ContentType 'application/json'
}

$adModule = Get-Module -ListAvailable -Name ActiveDirectory
if ($adModule) {
    Import-Module ActiveDirectory
    Write-Output "$(NZDateTime) [INFO] Using on-prem Active Directory module for expiring account check"

    $ExpiredAccounts = Search-ADAccount -AccountExpiring -UsersOnly -TimeSpan 07.00:00:00 | Where-Object { $_.Enabled -eq $true } | Sort-Object AccountExpirationDate
    $AccountList = $null

    foreach ($Account in $ExpiredAccounts) {
        $GetUser = Get-ADUser $Account.SamAccountName -Properties Title, Department
        $AccountList += "<tr><td>$($Account.AccountExpirationDate.AddDays(-1).ToString('D'))</td><td>$($Account.Name)</td><td>$($GetUser.Title), $($GetUser.Department)</td></tr>"
    }

    if ($ExpiredAccounts.Count -gt 0) {
        Write-Output "$(NZDateTime) [INFO] Found $($ExpiredAccounts.Count) expiring on-prem account(s)"
        $SmtpSubject = "INFO - Active Directory Accounts Expiring Within the Next Seven Days"
        $tableRows = $AccountList

        $SmtpBody = @"
<html>
<head>
<meta http-equiv='Content-Type' content='text/html; charset=us-ascii'>
</head>
<body>
<div style='background-color:#004080; color:white; padding:15px; font-size:18px; font-weight:bold; text-align:center;'>
Active Directory Expiring Accounts Report
</div>
<p>
The following Active Directory accounts are due to expire within the next seven days.
</p>
<table border='1' cellpadding='6' cellspacing='0' style='border-collapse:collapse; width:100%;'>
<tbody>
<tr style='background-color: #d3d3d3;'>
<th>Expiring end of</th>
<th>Name</th>
<th>Title and Department</th>
</tr>
$tableRows
</tbody>
</table>
</body>
</html>
"@
        Write-Output "$(NZDateTime) [INFO] Sending email to $SmtpTo"
        Send-GraphMail -from $SmtpFrom -to $SmtpTo -subject $SmtpSubject -bodyHtml $SmtpBody -accessToken $accessToken
        Write-Output "$(NZDateTime) [INFO] Email sent"
    } else {
        Write-Output "$(NZDateTime) [INFO] No on-prem accounts are expiring in the next seven days"
    }
} else {
    Write-Output "$(NZDateTime) [ERROR] On-prem Active Directory module not available. Cannot check for expiring accounts."
}

Write-Output "$(NZDateTime) [INFO] Script finished"