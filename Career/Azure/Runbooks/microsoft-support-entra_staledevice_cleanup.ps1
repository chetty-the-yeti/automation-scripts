# Send formatted HTML email to microsoftadmins@metservice.com (for human recipients)
function Send-FormattedEmail($bodyContent) {
    $emailPayload = @{
        message = @{
            subject = "Entra Stale-Device Clean Up Report"
            body = @{
                contentType = "HTML"
                content = $bodyContent
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

# Email body builder
function Build-EmailBody($devices) {
    if (-not $devices -or $devices.Count -eq 0) {
        return @"
<html>
<head>
<meta http-equiv='Content-Type' content='text/html; charset=us-ascii'>
</head>
<body>
<div style='background-color:#004080; color:white; padding:15px; font-size:18px; font-weight:bold; text-align:center;'>
Entra Stale-Device Clean Up Report
</div>
<p>
There are no Stale-Devices to remove.
</p>
<p style='margin-top:10px;'>
This is an automated message.
</p>
</body>
</html>
"@
    }
    $tableRows = ($devices | ForEach-Object {
        "<tr>
            <td>$($_.displayName)</td>
            <td>$($_.id)</td>
        </tr>"
    }) -join "`n"
    return @"
<html>
<head>
<meta http-equiv='Content-Type' content='text/html; charset=us-ascii'>
</head>
<body>
<div style='background-color:#004080; color:white; padding:15px; font-size:18px; font-weight:bold; text-align:center;'>
Entra Stale-Device Clean Up Report
</div>
<p>
The following Stale-Devices have been deleted:
</p>
<table border='1' cellpadding='6' cellspacing='0' style='border-collapse:collapse; width:100%;'>
<tbody>
<tr style='background-color: #d3d3d3;'>
<th>Display Name</th>
<th>Device ID</th>
</tr>
$tableRows
</tbody>
</table>
<br>
<p style='margin-top:10px;'>
This is an automated message.
</p>
</body>
</html>
"@
}

# Collect deleted devices for reporting
$deletedDevices = @()
<#
.SYNOPSIS
    This script performs automated cleanup of inactive devices in Microsoft Entra ID (formerly Azure AD).

.DESCRIPTION
    The script authenticates using app registration credentials stored as Azure Automation Variables.
    It retrieves a list of devices from Microsoft Graph API and filters those that have not signed in for over 90 days.
    It then deletes each inactive device and logs the results.

    Automation Variables used:
    - EntraDeviceCleanupAutomation-ClientID
    - EntraDeviceCleanupAutomation-ClientSecret
    - EntraDeviceCleanupAutomation-TenantID
#>

# Get values from Automation Variables
$tenantId     = Get-AutomationVariable -Name "microsoft-support-automations_app-TenantID"
$clientId     = Get-AutomationVariable -Name "microsoft-support-automations_app-ClientID"
$clientSecret = Get-AutomationVariable -Name "microsoft-support-automations_app-ClientSecret"

# Get an OAuth2 token using the app credentials
$body = @{
    grant_type    = "client_credentials"
    client_id     = $clientId
    client_secret = $clientSecret
    scope         = "https://graph.microsoft.com/.default"
}

$tokenResponse = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Body $body
$accessToken = $tokenResponse.access_token

# Create the authorization header
$headers = @{
    Authorization = "Bearer $accessToken"
    "Content-Type" = "application/json"
}

# Get devices inactive for more than 90 days
$cutoffDate = (Get-Date).AddDays(-90).ToString("o")
$uri = "https://graph.microsoft.com/v1.0/devices"
$response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
$inactiveDevices = $response.value | Where-Object {
    $_.approximateLastSignInDateTime -and ([datetime]$_.approximateLastSignInDateTime) -lt $cutoffDate
}

Write-Output "📋 Found $($inactiveDevices.Count) inactive devices."

foreach ($device in $inactiveDevices) {
    try {
        $deviceId = $device.id
        $displayName = $device.displayName

        Write-Output "🗑️ Deleting: $displayName | ID: $deviceId"

        Invoke-RestMethod -Method Delete -Uri "https://graph.microsoft.com/v1.0/devices/$deviceId" -Headers $headers

        $deletedDevices += [PSCustomObject]@{ displayName = $displayName; id = $deviceId }
    }
    catch {
        Write-Error "❌ Failed to delete device $($device.displayName): $_"
    }
}

# Only send the email if any stale-devices were removed
if ($deletedDevices.Count -gt 0) {
    $emailBody = Build-EmailBody -devices $deletedDevices
    Send-FormattedEmail -bodyContent $emailBody
}

Write-Output "✅ Device cleanup completed at $(Get-Date)."
