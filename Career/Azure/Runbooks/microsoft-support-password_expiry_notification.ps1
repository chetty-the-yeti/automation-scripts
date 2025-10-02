<#
.SYNOPSIS
    Sends email notifications to users whose Active Directory passwords are about to expire.

.DESCRIPTION
    This script is designed to run as an Azure Automation Runbook on a Hybrid Worker.
    It queries Active Directory for enabled user accounts whose passwords are due to expire within a specified period.
    For each user found, it sends a personalized email reminder using Microsoft Graph API.
    The script uses Azure Automation variables for authentication and logs all actions and errors for auditing purposes.
#>

# Define Constants
$NotifyPeriod = 8
$SmtpFrom = "no-reply@example.com"

# === Azure Graph Credentials ===
$clientId     = Get-AutomationVariable -Name "microsoft-support-automations_app-ClientID"
$clientSecret = Get-AutomationVariable -Name "microsoft-support-automations_app-ClientSecret"
$tenantId     = Get-AutomationVariable -Name "microsoft-support-automations_app-TenantID"

######## Functions ########
Function NZDateTime
{
    Get-Date -Format "dd/MM/yyyy hh:mm:ss"
}

Function Get-GraphToken {
    param (
        [string]$clientId,
        [string]$clientSecret,
        [string]$tenantId
    )
    $body = @{
        grant_type    = "client_credentials"
        scope         = "https://graph.microsoft.com/.default"
        client_id     = $clientId
        client_secret = $clientSecret
    }
    $response = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -ContentType "application/x-www-form-urlencoded" -Body $body
    return $response.access_token
}

Function Send-GraphMail {
    param (
        [string]$accessToken,
        [string]$from,
        [string]$to,
        [string]$subject,
        [string]$bodyHtml
    )
    $mailBody = @{
        message = @{
            subject = $subject
            body = @{
                contentType = "HTML"
                content     = $bodyHtml
            }
            toRecipients = @(@{emailAddress = @{address = $to}})
        }
        saveToSentItems = "false"
    }
    $uri = "https://graph.microsoft.com/v1.0/users/$from/sendMail"
    $headers = @{
        Authorization = "Bearer $accessToken"
        "Content-Type" = "application/json"
    }
    try {
        Write-Output "$(NZDateTime) [INFO] Attempting to send mail from $from to $to"
        $response = Invoke-RestMethod -Method POST -Uri $uri -Headers $headers -Body ($mailBody | ConvertTo-Json -Depth 4) -ErrorAction Stop
        Write-Output "$(NZDateTime) [INFO] Graph API sendMail response: $($response | ConvertTo-Json -Compress)"
        return $true
    } catch {
        Write-Error "$(NZDateTime) [ERROR] Graph API sendMail failed: $($_.Exception.Message)"
        if ($_.ErrorDetails) {
            Write-Error "$(NZDateTime) [ERROR] Graph API error details: $($_.ErrorDetails.Message)"
        }
        return $false
    }
}

# Create and write to log. Terminate if unable
Try{
    Write-Output "$(NZDateTime) [INFO] Script started"
}
Catch{
    Write-Error "$_"
    Exit
}

# Load Active Directory Module
Try{
    if(@(get-module | where-object {$_.Name -eq "ActiveDirectory"} ).count -eq 0) {import-module ActiveDirectory -ErrorAction Stop}
    Write-Output "$(NZDateTime) [INFO] Imported Active Directory module"
}
Catch{
    Write-Error "$(NZDateTime) [ERROR] Failed to imported Active Directory module. $_"
    Exit
}

# Get AD max password age policy
$MaxPassAge = (Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge.days
Write-Output "$(NZDateTime) [INFO] Maximum password age is $MaxPassAge"

# Get Graph API token
$accessToken = Get-GraphToken -clientId $clientId -clientSecret $clientSecret -tenantId $tenantId
if (-not $accessToken) {
    Write-Error "$(NZDateTime) [ERROR] Failed to obtain Graph API access token."
    Exit 1
}

# Query all enabled users with an email address whose password expires within the notify period in the specified OU
$Users = Get-ADUser -SearchBase "OU=Users,OU=MetInfo,DC=met,DC=co,DC=nz" -Filter {Enabled -eq $true -and mail -like "*"} -Properties *,GivenName,PasswordLastSet |
    Select-Object SamAccountName,Mail,DistinguishedName,GivenName,@{Name="Expires";Expression={ 
        if ($_.PasswordLastSet) {
            $MaxPassAge - ((Get-Date) - ($_.PasswordLastSet)).days
        } else {
            $null
        }
    }}

if (!$Users) {
    Write-Output "$(NZDateTime) [WARN] No users found for notification."
}

ForEach($User in $Users){
    $DaysToExpiry = $User.Expires
    $SmtpTo = $User.Mail
    $FirstName = $User.GivenName

    # Handle missing PasswordLastSet
    if ($DaysToExpiry -eq $null) {
        Write-Output "$(NZDateTime) [WARN] User $($User.SamAccountName) has no PasswordLastSet property. Skipping."
        continue
    }

    # Only notify users whose password expires in <= NotifyPeriod days and > 0 days
    if (($DaysToExpiry -le $NotifyPeriod) -and ($DaysToExpiry -gt 0)) {
        if ([string]::IsNullOrWhiteSpace($SmtpTo)) {
            Write-Output "$(NZDateTime) [WARN] User $($User.SamAccountName) has no email address. Skipping."
            continue
        }

        if ([string]::IsNullOrWhiteSpace($SmtpFrom)) {
            Write-Error "$(NZDateTime) [ERROR] SmtpFrom is not set. Cannot send email."
            continue
        }

        # Log which user is being notified
        Write-Output "$(NZDateTime) [INFO] Sending password expiry notification to $($User.SamAccountName) <$SmtpTo>, expires in $DaysToExpiry day(s)"

        $SmtpSubject = "🔐 Password Expiry Notice: Your password expires in $DaysToExpiry day(s)"
        $SmtpBody = @"
<html>
<head>
<meta http-equiv='Content-Type' content='text/html; charset=us-ascii'>
</head>
<body style='font-family:Segoe UI,Arial,sans-serif; font-size:15px; color:#222;'>
<div style='background-color:#004080; color:white; padding:15px; font-size:18px; font-weight:bold; text-align:center; margin-bottom:18px;'>
Password Expiry Notification
</div>
<p>Hi $FirstName,</p>
<p><b>Your password will expire in $DaysToExpiry day(s).</b></p>
<p>
<p>To avoid disruptions to services, please update your password.
<p>Click the button below, enter your email address, complete the security CAPTCHA then select “I forgot my password” to proceed with the reset.
<br>
<br>
<a href="https://passwordreset.microsoftonline.com" style="display:inline-block; padding:10px 20px; background-color:#004080; color:#fff; text-decoration:none; border-radius:5px; font-weight:bold;">
    Change Password
</a>
</p>
<p><b>Password Requirements:</b>
<ul>
    <li>Minimum 14 characters</li>
    <li>Include uppercase letters and numbers</li>
    <li>Symbols are allowed and encouraged for stronger security</li>
</ul>
</p>
<p style='font-size:13px; color:#555;'>
Note: Changing your password will not affect your ability to log in using Windows Hello methods such as PIN, fingerprint, or facial recognition on your existing devices.
</p>
<p>
Need help?<br>
Contact: servicedesk@example.com
</p>
</body>
</html>
"@
        Try{
            $mailSent = $false
            try {
                $mailSent = Send-GraphMail -accessToken $accessToken -from $SmtpFrom -to $SmtpTo -subject $SmtpSubject -bodyHtml $SmtpBody
            } catch {
                Write-Error "$(NZDateTime) [ERROR] Exception in Send-GraphMail: $($_.Exception.Message)"
                if ($_.Exception.Response) {
                    $reader = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())
                    $responseBody = $reader.ReadToEnd()
                    Write-Error "$(NZDateTime) [ERROR] Graph API HTTP response: $responseBody"
                }
            }
            if (-not $mailSent) {
                Write-Error "$(NZDateTime) [ERROR] Unable to send email to $SmtpTo via Graph API."   
            }
        }
        Catch{
            Write-Error "$(NZDateTime) [ERROR] Exception in processing $($User.SamAccountName): $($_.Exception.Message)"
        }
    }
}

Write-Output "$(NZDateTime) [INFO] Script completed"