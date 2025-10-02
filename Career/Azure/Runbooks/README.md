# Azure Automation Runbooks

This repository contains a collection of PowerShell runbooks designed for use with Azure Automation Accounts and Hybrid Workers.  
**Note:** These scripts were originally developed as standalone PowerShell scripts running on a dedicated VM. They have since been migrated and modernized to run as Azure Automation Runbooks, utilizing Microsoft Graph API and Automation Account variables for secure, scalable, and cloud-native automation of traditional IT operations.

Some scripts utilize **Hybrid Workers**, which allow Azure Automation to execute runbooks on machines in your own datacenter or network. This enables automation of tasks that require access to on-premises resources, such as Active Directory, file shares, or other internal systems.

These scripts automate common IT operations tasks for Active Directory and Microsoft Entra ID (Azure AD), including user account lifecycle management, group membership cleanup, device cleanup, and credential expiry monitoring.

## Overview

Azure Automation enables organizations to automate repetitive tasks, orchestrate workflows, and improve operational efficiency. The scripts in this repository demonstrate practical automation for identity and access management in hybrid environments.

## Runbooks Included

- **ad_group_membership_cleanup.ps1**  
  Removes disabled Active Directory user accounts from all groups and sends a summary report via email.

- **potential_inactive_users.ps1**  
  Identifies enabled AD user accounts that have been inactive for a configurable period (e.g., 90 days) and sends an alert email with details.

- **password_expiry_notification.ps1**  
  Notifies users whose AD passwords are about to expire, sending personalized email reminders using Microsoft Graph.

- **expiring_users.ps1**  
  Reports on AD user accounts that are scheduled to expire within the next seven days and sends a summary email.

- **entra_staledevice_cleanup.ps1**  
  Finds and deletes inactive devices in Microsoft Entra ID (Azure AD) that have not signed in for a specified period, then emails a cleanup report.

- **disabled_accounts_OU_cleanup.ps1**  
  Moves expired standard AD users to a designated "Disabled" OU and lists expired admin users for manual review, with reporting via email.

- **disable_expired_users.ps1**  
  Automatically disables expired AD user accounts, updates their descriptions, and sends a summary notification email.

- **app_registration_expiry_checker.ps1**  
  Checks Azure AD application registrations for expiring secrets and certificates, sending formatted expiry reports and notifications.

## Usage

- These scripts are intended for use in Azure Automation Accounts and may require Hybrid Worker configuration for on-premises Active Directory access.
- Hybrid Workers allow runbooks to interact with resources inside your network that are not directly accessible from Azure.
- Authentication is handled via Azure Automation variables and Microsoft Graph API.
- All email notifications are sent using Microsoft Graph, with recipient addresses configurable in each script.

## Notes

- All scripts have been sanitized to remove company-specific and sensitive information.
- Example domain names and email addresses are used throughout.
- For demonstration purposes only; adapt and configure for your own environment as needed.

---