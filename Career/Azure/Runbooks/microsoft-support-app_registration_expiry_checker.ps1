<#
.SYNOPSIS
    Azure App Registration Expiry Report Script

.DESCRIPTION
    This script queries Entra ID for application registrations tagged with "Team=microsoft-support".
    It checks for client secrets and certificates that are expiring within the next 30 days.
    If any credentials are found, it sends a formatted HTML expiry report to a specified mailbox.
    If any credentials are expiring within the next 30 days, it also sends a plain text notification to a Jira/Atlassian mailbox to trigger ticket creation.
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

# Prepare authorization header
$headers = @{
    Authorization = "Bearer $accessToken"
    "Content-Type" = "application/json"
}

# Graph query to find app registrations with tag "Team=microsoft-support"
$appUrl = 'https://graph.microsoft.com/beta/applications?$filter=tags/any(t:t eq ''Team=microsoft-support'')'

$response = Invoke-RestMethod -Method Get -Uri $appUrl -Headers $headers

if (-not $response.value) {
    return "No applications found with the tag 'Team=microsoft-support'."
}

# Collect all tagged registrations for reporting, not just expiring ones
$allTaggedApps = @()
foreach ($app in $response.value) {
    # Add all secrets
    if ($app.passwordCredentials) {
        foreach ($secret in $app.passwordCredentials) {
            $allTaggedApps += [PSCustomObject]@{
                DisplayName = $app.displayName
                Type        = "Secret"
                KeyId       = $secret.keyId
                Expires     = (Get-Date $secret.endDateTime).ToString("MM/dd/yyyy HH:mm:ss")
            }
        }
    }
    # Add all certificates
    if ($app.keyCredentials) {
        foreach ($cert in $app.keyCredentials) {
            $allTaggedApps += [PSCustomObject]@{
                DisplayName = $app.displayName
                Type        = "Certificate"
                KeyId       = $cert.keyId
                Expires     = (Get-Date $cert.endDateTime).ToString("MM/dd/yyyy HH:mm:ss")
            }
        }
    }
}

# Send formatted HTML expiry email to microsoftadmins@metservice.com (for human recipients)
function Send-FormattedExpiryEmail($bodyContent) {
    $emailPayload = @{
        message = @{
            subject = "Azure App Registration Expiry Report"
            body = @{
                contentType = "HTML"
                content     = $bodyContent
            }
            from = @{
                emailAddress = @{
                    address = "alerts@example.com"
                }
            }
            toRecipients = @(
                @{
                    emailAddress = @{
                        address = "admins@example.com"
                    }
                }
            )
        }
        saveToSentItems = "false"
    }
    $sendMailUrl = "https://graph.microsoft.com/v1.0/users/alerts@example.com/sendMail"
    Invoke-RestMethod -Uri $sendMailUrl -Headers $headers -Method POST -Body ($emailPayload | ConvertTo-Json -Depth 10)
}

# Send plain text expiry notification to Jira/Atlassian mailbox
function Send-JiraNotification($plainTextBody) {
    $emailPayload = @{
        message = @{
            subject = "Azure App Registration Expiry Report"
            body = @{
                contentType = "Text"
                content     = $plainTextBody
            }
            from = @{
                emailAddress = @{
                    address = "alerts@example.com"
                }
            }
            toRecipients = @(
                @{
                    emailAddress = @{
                        address = "jira@example.com"
                    }
                }
            )
        }
        saveToSentItems = "false"
    }
    $sendMailUrl = "https://graph.microsoft.com/v1.0/users/alerts@example.com/sendMail"
    Invoke-RestMethod -Uri $sendMailUrl -Headers $headers -Method POST -Body ($emailPayload | ConvertTo-Json -Depth 10)
}

# Build plain text report for Jira
function Build-PlainTextReport($apps) {
    $lines = @("The following App Registrations have secrets or certificates expiring soon:`n")
    foreach ($app in $apps) {
        $lines += "App: $($app.DisplayName), Type: $($app.Type), Key ID: $($app.KeyId), Expires: $($app.Expires)"
    }
    return $lines -join "`n"
}

# Email body builder
function Build-ExpiryEmailBody($apps, $jiraInfo) {
    $jiraSection = ""
    if ($jiraInfo) {
        $jiraSection = @"
<p><strong>Notice: Assign to Microsoft Team</strong><br>
This JIRA ticket has been automatically created for expiring items.<br/>
<a href='https://metservice.atlassian.net/browse/$($jiraInfo.Key)'>$($jiraInfo.Key)</a></p>
"@
    } else {
        $jiraSection = "<p>No JIRA ticket was created as no items are expiring within the next 30 days.</p>"
    }

    $soonThreshold = (Get-Date).AddDays(30)
    $tableRows = ($apps | ForEach-Object {
        $expiresDate = [datetime]$_.Expires
        if ($expiresDate -le $soonThreshold) {
            $expiringSoon = "<b><span style='color:red;'>Yes</span></b>"
        } else {
            $expiringSoon = "No"
        }
        "<tr>
<td>$($_.DisplayName)</td>
<td>$($_.Type)</td>
<td>$($_.KeyId)</td>
<td>$($_.Expires)</td>
<td style='text-align:center;'>$expiringSoon</td>
</tr>"
    }) -join "`n"

    return @"
<html>
<head>
<meta http-equiv='Content-Type' content='text/html; charset=us-ascii'>
</head>
<body>
<div style='background-color:#004080; color:white; padding:15px; font-size:18px; font-weight:bold; text-align:center;'>
Azure App Registration Expiry Report
</div>
<p>
These app registrations are managed by the Microsoft Team.<br>
</p>
<p>
If any expiring credentials are detected, a JIRA ticket will be automatically created.
</p>
<table border='1' cellpadding='6' cellspacing='0' style='border-collapse:collapse; width:100%;'>
<tbody>
<tr style='background-color: #d3d3d3;'>
<th>Display Name</th>
<th>Type</th>
<th>Key ID</th>
<th>Expires</th>
<th>Expiring Soon</th>
</tr>
$tableRows
</tbody>
</table>
<br>
$jiraSection
<p style='margin-top:10px;'>
<a href='https://metservice.atlassian.net/wiki/spaces/IT/pages/874381499/Azure+App+Registration+Tagging'>
Follow these instructions to add an App Registration to this report
</a>
</p>
</body>
</html>
"@
}

# Use all tagged apps for the main report, but only expiring soon for JIRA
$jiraTicketInfo = $null
$expiringSoonApps = $allTaggedApps | Where-Object { [datetime]$_.Expires -le (Get-Date).AddDays(30) }

if ($expiringSoonApps.Count -gt 0) {
    $jiraBody  = Build-PlainTextReport -apps $expiringSoonApps
    $jiraTicketInfo = Send-JiraNotification -plainTextBody $jiraBody

    $emailBody = Build-ExpiryEmailBody -apps $allTaggedApps -jiraInfo $jiraTicketInfo
    Send-FormattedExpiryEmail -bodyContent $emailBody
}