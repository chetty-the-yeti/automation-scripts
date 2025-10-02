<#
.SYNOPSIS
    Disables expired Active Directory user accounts and sends notification emails.

.DESCRIPTION
    This script is intended to be run as an Azure Automation Runbook on a Hybrid Worker.
    It finds all enabled Active Directory user accounts that have expired, disables them,
    updates their description, and sends a summary email to specified recipients.
    The script uses Azure Automation variables for authentication and is designed for
    automated, scheduled execution in a hybrid cloud/on-premises environment.
#>
# Azure Automation Variables
$clientId     = Get-AutomationVariable -Name "microsoft-support-automations_app-ClientID"
$clientSecret = Get-AutomationVariable -Name "microsoft-support-automations_app-ClientSecret"
$tenantId     = Get-AutomationVariable -Name "microsoft-support-automations_app-TenantID"

# Get an access token using client credentials for Microsoft Graph
$body = @{
    client_id     = $clientId
    scope         = "https://graph.microsoft.com/.default"
    client_secret = $clientSecret
    grant_type    = "client_credentials"
}
$tokenResponse = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Body $body
$accessToken = $tokenResponse.access_token

# Function to send mail via Microsoft Graph
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

# Define Constants
$Date = Get-Date -Format dd/MM/yyyy
$SmtpServer = "example-com.mail.protection.outlook.com"
$SmtpFrom = "alerts@example.com"
$SmtpTo = @("admins@example.com", "servicedesk@example.com")
$DisableThreshold = 10

# Add at the top for consistent error handling and output
$ErrorActionPreference = "Stop"

# Import Active Directory module (for Hybrid Worker)
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] ERROR: Active Directory module not found on Hybrid Worker."
    throw "Active Directory module not found on Hybrid Worker."
}
Import-Module ActiveDirectory
Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Active Directory module imported"

# Main logic
Try {
    Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Starting disable expired users script"
    # Retrieve list of expired user accounts that are enabled
    [Array]$ExpiredAccounts = Search-ADAccount -AccountExpired -UsersOnly -ErrorAction Stop | Where-Object Enabled -EQ $true

    Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Found $($ExpiredAccounts.Count) expired accounts"

    if ($ExpiredAccounts.Count -eq 0) {
        Write-Output "No expired accounts found."
        return
    }

    if ($ExpiredAccounts.Count -gt $DisableThreshold) {
        Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] WARNING: Threshold exceeded, no action taken"
        # Build table rows for warning email
        $tableRows = ""
        foreach ($Account in $ExpiredAccounts) {
            $tableRows += "<tr><td>$($Account.Name)</td></tr>"
        }
        $SmtpSubject = "INFO - Active Directory Expired Accounts Report"
        $SmtpBody = @"
<html>
<head>
<meta http-equiv='Content-Type' content='text/html; charset=us-ascii'>
</head>
<body>
<div style='background-color:#004080; color:white; padding:15px; font-size:18px; font-weight:bold; text-align:center;'>
Active Directory Expired Accounts Report
</div>
<p>
The following Active Directory accounts are due to expire within the next seven days.<br>
<b>WARNING:</b> $($ExpiredAccounts.Count) accounts found, which exceeds the safety threshold of $DisableThreshold.<br>
No action has been taken as a precaution.<br>
</p>
<table border='1' cellpadding='6' cellspacing='0' style='border-collapse:collapse; width:100%;'>
<tbody>
<tr style='background-color: #d3d3d3;'>
<th>Name</th>
</tr>
$tableRows
</tbody>
</table>
</body>
</html>
"@
        Send-GraphMail -from $SmtpFrom -to $SmtpTo -subject $SmtpSubject -bodyHtml $SmtpBody -accessToken $accessToken
        return
    }

    Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Disabling expired accounts..."
    # Otherwise, process and disable expired accounts
    $tableRowsBuilder = New-Object System.Text.StringBuilder
    foreach ($Account in $ExpiredAccounts) {
        $GetUser = Get-ADUser $Account.SamAccountName -Properties *
        try {
            $User = Get-ADUser $Account -Properties Description -ErrorAction Stop
            Disable-ADAccount $User -ErrorAction Stop
            Set-ADUser $User -Description "[AutoDisabled Expired Account $Date] $($User.Description)"
            Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Disabled account: $($Account.SamAccountName) ($($Account.Name))"
            [void]$tableRowsBuilder.Append("<tr><td>$Date</td><td>$($Account.Name)</td><td>$($GetUser.Title), $($GetUser.Department)</td></tr>")
        }
        catch {
            [void]$tableRowsBuilder.Append("<tr><td>$Date</td><td>$($Account.Name)</td><td>ERROR: $($_.Exception.Message)</td></tr>")
            continue
        }
    }
    $tableRows = $tableRowsBuilder.ToString()

    if ($tableRows) {
        $SmtpSubject = "INFO - Expired Active Directory Accounts were Automatically Disabled"
        $SmtpBody = @"
<html>
<head>
<meta http-equiv='Content-Type' content='text/html; charset=us-ascii'>
</head>
<body>
<div style='background-color:#004080; color:white; padding:15px; font-size:18px; font-weight:bold; text-align:center;'>
Active Directory Expired Accounts Report
</div>
<p>
The following Active Directory accounts have been automatically disabled after reaching their expiry date.
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
        try {
            Send-GraphMail -from $SmtpFrom -to $SmtpTo -subject $SmtpSubject -bodyHtml $SmtpBody -accessToken $accessToken
        }
        catch {
            Write-Error "Failed to send summary email: $($_.Exception.Message)"
        }
    }
}
catch {
    $SmtpSubject = "ERROR - Account Disable Script"
    $SmtpBody = "There was an error retrieving account information from the directory.`r`n`nThe script has terminated with error:`r`n`n`t$_"
    try {
        Send-GraphMail -from $SmtpFrom -to $SmtpTo -subject $SmtpSubject -bodyHtml $SmtpBody -accessToken $accessToken
    }
    catch {
        Write-Error "Failed to send error notification email: $($_.Exception.Message)"
    }
    throw $_
}