<#
.SYNOPSIS
    Inactive User Account Alert
.DESCRIPTION
    This runbook checks for on-prem Active Directory user accounts that have been inactive for more than 90 days and sends an alert email.
    It is designed to run on the Hybrid Worker.
    Requirements:
      - PowerShell 7 installed.
      - RSAT: Active Directory module installed on Hybrid Worker.
      - Hybrid Worker service account has permission to query AD.
      - Select the Hybrid Worker group when running the runbook.
#>

# Get stored Automation variables for Microsoft Graph authentication
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
#$LogFile = "$PSScriptRoot\InactiveUserAlert.log"
$Date = Get-Date
$SmtpFrom = "alerts@example.com"
$SmtpTo = @("admins@example.com")


# Set Variables
$InactiveDays = 90
$Days = (Get-Date).Adddays(-($InactiveDays))
$SmtpSubject = $null
$SmtpBody = $null
$AccountList = $null

#OUs
$AdminOU = 'OU=Admin,OU=Users,DC=example,DC=com'
$StandardOU = 'OU=Standard,OU=Users,DC=example,DC=com'
$RoamingOU = 'OU=Roaming,OU=Users,DC=example,DC=com'
$SharedOU = 'OU=Shared,OU=Users,DC=example,DC=com'
$ExternalOU = 'OU=External,OU=Users,DC=example,DC=com'


#Remove-Variable -Name LogFile -ErrorAction SilentlyContinue
#Remove-Variable -Name transcript0 -ErrorAction SilentlyContinue

######## Functions ########
Function NZDateTime
{
Get-Date -Format "dd/MM/yyyy hh:mm:ss"
}


# Check log file is available and create if neccessary
Try{
    # If (!(Test-Path $LogFile)){
    #     "$(NZDateTime) [INFO] Inactive User Alert script log created" | Out-File $LogFile -ErrorAction Stop
    # }
    Write-Output "$(NZDateTime) [INFO] Script started"
}
Catch{
    Write-Output "$(NZDateTime) [ERROR] Unable to start script. $($_.Exception.Message)"
    Exit
}

# Load Active Directory Module
Try{
    if(@(get-module | where-object {$_.Name -eq "ActiveDirectory"} ).count -eq 0) {import-module ActiveDirectory -ErrorAction Stop}
    Write-Output "$(NZDateTime) [INFO] Imported Active Directory module"
}
Catch{
    Write-Output "$(NZDateTime) [ERROR] Failed to import Active Directory module. $_"
    Exit
}

# Retrieve list of users accounts in specific OUs who are enabled and who have a LastLogonTimeStamp of more than 90 days
Try{
    $InactiveUsers = Get-ADUser -Properties * -SearchBase $KbStandardOU -Filter {LastLogonTimeStamp -lt $Days -and PasswordLastSet -lt $Days -and enabled -eq $true}
    $InactiveUsers += Get-ADUser -Properties * -SearchBase $KbRoamingOU -Filter {LastLogonTimeStamp -lt $Days -and PasswordLastSet -lt $Days -and enabled -eq $true}
    $InactiveUsers += Get-ADUser -Properties * -SearchBase $AkStandardOU -Filter {LastLogonTimeStamp -lt $Days -and PasswordLastSet -lt $Days -and enabled -eq $true}
    $InactiveUsers += Get-ADUser -Properties * -SearchBase $AkRoamingOU -Filter {LastLogonTimeStamp -lt $Days -and PasswordLastSet -lt $Days -and enabled -eq $true}
    $InactiveUsers += Get-ADUser -Properties * -SearchBase $BkStandardOU -Filter {LastLogonTimeStamp -lt $Days -and PasswordLastSet -lt $Days -and enabled -eq $true}
    $InactiveUsers += Get-ADUser -Properties * -SearchBase $BkRoamingOU -Filter {LastLogonTimeStamp -lt $Days -and PasswordLastSet -lt $Days -and enabled -eq $true}
    $InactiveUsers += Get-ADUser -Properties * -SearchBase $ChStandardOU -Filter {LastLogonTimeStamp -lt $Days -and PasswordLastSet -lt $Days -and enabled -eq $true}
    $InactiveUsers += Get-ADUser -Properties * -SearchBase $ChRoamingOU -Filter {LastLogonTimeStamp -lt $Days -and PasswordLastSet -lt $Days -and enabled -eq $true}
    $InactiveUsers += Get-ADUser -Properties * -SearchBase $PaStandardOU -Filter {LastLogonTimeStamp -lt $Days -and PasswordLastSet -lt $Days -and enabled -eq $true}
    $InactiveUsers += Get-ADUser -Properties * -SearchBase $PaSharedOU -Filter {LastLogonTimeStamp -lt $Days -and PasswordLastSet -lt $Days -and enabled -eq $true}
    $InactiveUsers += Get-ADUser -Properties * -SearchBase $PaRoamingOU -Filter {LastLogonTimeStamp -lt $Days -and PasswordLastSet -lt $Days -and enabled -eq $true}
    $InactiveUsers += Get-ADUser -Properties * -SearchBase $RaStandardOU -Filter {LastLogonTimeStamp -lt $Days -and PasswordLastSet -lt $Days -and enabled -eq $true}
    $InactiveUsers += Get-ADUser -Properties * -SearchBase $ReStandardOU -Filter {LastLogonTimeStamp -lt $Days -and PasswordLastSet -lt $Days -and enabled -eq $true}
    $InactiveUsers += Get-ADUser -Properties * -SearchBase $ReRoamingOU -Filter {LastLogonTimeStamp -lt $Days -and PasswordLastSet -lt $Days -and enabled -eq $true}
    $InactiveUsers += Get-ADUser -Properties * -SearchBase $SydStandardOU -Filter {LastLogonTimeStamp -lt $Days -and PasswordLastSet -lt $Days -and enabled -eq $true}
    $InactiveUsers += Get-ADUser -Properties * -SearchBase $SydRoamingOU -Filter {LastLogonTimeStamp -lt $Days -and PasswordLastSet -lt $Days -and enabled -eq $true}
    $InactiveUsers += Get-ADUser -Properties * -SearchBase $ExternalOU -Filter {LastLogonTimeStamp -lt $Days -and PasswordLastSet -lt $Days -and enabled -eq $true}

    $InactiveUsers = $InactiveUsers | Sort-Object -Property LastLogonDate -Descending

    ForEach ($InactiveUser in $InactiveUsers) {
        $GetUser = Get-ADUser $InactiveUser.SamAccountName -Properties *
        if ($GetUser -ne $null) {
            $LastLogOnDate = if ($InactiveUser.LastLogOnDate -ne $null) { $InactiveUser.LastLogOnDate.ToString('dd-MMM-yyyy') } else { "N/A" }
            $PasswordLastSet = if ($InactiveUser.PasswordLastSet -ne $null) { $InactiveUser.PasswordLastSet.ToString('dd-MMM-yyyy') } else { "N/A" }
            $DaysInactive = if ($InactiveUser.LastLogOnDate -ne $null) { New-TimeSpan -Start $InactiveUser.LastLogOnDate -End $Date } else { "N/A" }
            $DaysSincePwdLastSet = if ($InactiveUser.PasswordLastSet -ne $null) { New-TimeSpan -Start $InactiveUser.PasswordLastSet -End $Date } else { "N/A" }
            $PwdExpired = $InactiveUser.PasswordExpired
            $OrgUnit = ($InactiveUser.DistinguishedName -split ',OU=')[1..4] -join '/' -replace '(,DC=.*$)', ''
            $AccountList += "<tr><td>$($InactiveUser.Name)</td><td>$LastLogOnDate ($($DaysInactive.Days))</td><td>$PasswordLastSet ($($DaysSincePwdLastSet.Days))</td><td>$PwdExpired</td><td>$OrgUnit</td></tr>"
        }
    }

    If ($InactiveUsers) {
        $SmtpSubject = "INFO - Potentially Inactive Active Directory Users"
        $tableRows = $AccountList

        $SmtpBody = @"
<html>
<head>
<meta http-equiv='Content-Type' content='text/html; charset=us-ascii'>
</head>
<body>
<div style='background-color:#004080; color:white; padding:15px; font-size:18px; font-weight:bold; text-align:center;'>
Potentially Inactive Active Directory Users
</div>
<p>
The following Active Directory accounts have not logged in to AD DS for more than 90 days and/or have an expired AD DS password.
</p>
<table border='1' cellpadding='6' cellspacing='0' style='border-collapse:collapse; width:100%;'>
<tbody>
<tr style='background-color: #d3d3d3;'>
<th>Name</th>
<th>Last Logon Date (days)</th>
<th>Pwd Last Set (days)</th>
<th>PwdExpired</th>
<th>Org Unit</th>
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
        Exit
    }
    Else {
        Write-Output "$(NZDateTime) [INFO] No Potentially Inactive Accounts Exists"
    }
    Write-Output "$(NZDateTime) [INFO] Inactive Accounts have been exported"
}
Catch{
    Write-Output "$(NZDateTime) [ERROR] Unable to retrieve account information from the directory. $_"
    Exit
}

Write-Output "$(NZDateTime) [INFO] Script finished"