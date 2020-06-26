# KeyVaultExpirationNotification
This Powershell script can be adjusted to check a Key Vault for expiring objects, send email notifications, and create User Stories in Azure Devops.

## About the Script
### A Tale of 2 folders
You will notice that there are 2 main folders:
1. **AzureRunbook**: Versions of the script meant to be used in Azure Runbooks
   1. Requires the following Azure Modules to run:
      1. Az
      2. Azure.DevOps
      3. Az.KeyVault
      4. Az.Profile
      5. There may be others that were just already installed in the environment I was testing with.
      6. Also may work with AzureRM variants of these, but some commands would need to be changed to their AzureRM equivalents.
      7. Also you are better off sticking with Az because it is meant to replace AzureRM.
2. **LocalRun**: Versions of the script meant to be able to use locally, or possibly outside Azure. 
   1. **Important:** These ones are not set up yet.

### What does it do?
There are 2 main versions of the script in each of the main folders listed previously. I will describe each version below.
1) **Notification Only**
   1) Checks for expiring assets in a KeyVault based on a number of days you set.
   2) It then shoots off an email to a designated recipient email address using a service account whose credentials you provide if any assets are expiring within that number of days from the current date. These emails will include a clear subject and a body with some details on where to find documentation. Can be customized to your needs.
2) **Notification & ADO Work Item Creation**
   1) Checks for expiring assets in a KeyVault based on a number of days you set.
   2) **If anything is expiring,** it then checks if a work item exists for it based on the notification subject, which includes the secret label and expiration date
      1) **If the work item exists**, it sends out the notification still, but lists the matching work item(s).
      2) **If the work item does not exist**, it creates the work item.
      3) Then sends the notification, and lets you know it created a work item.
   3) **If nothing is expiring**, it still sends a notification so you know it is still working, but lets you know nothing was found to be expiring. 
      1) This can also be a warning for you if you were expecting something to be expiring but it says nothing is expiring.

## Additional Notes
- Uses a WIQL query for the Work Item search and a different API call for the work item creation.
- In my experience the Azure Runbook must be in an Automation Account on the same subscription as the KeyVault being checked.
- Runbook variant requires an Azure DevOps Personal Access Token to access the ADO portions. This is meant to be stored in an encrypted variable within the Automation Account itself. Though you could alter it to pull from a KeyVault instead.
  - Looking into ways to use something not linked to a specific user account in the future.

## External Documentation Referenced
-  [Expiry Notification for Azure Key Vault Keys and Secrets](https://www.rahulpnath.com/blog/expiry-notification-for-azure-key-vault-keys-and-secrets/)
   -  By Rahul Nath on his official page
   -  Honestly this page was the one that got me started on this journey and thinking about what all I could do with Key Vault, which led to thinking about making ADO work items.
-  [Get Azure Key Vault expired secrets](https://www.powershellbros.com/get-azure-key-vault-expired-secrets/)
   -  By Artur Brodziński on PowerShell Bros.
   -  Probably the # major influence in me putting together this script.
- [Azure DevOps Rest API Reference v 5.1](https://docs.microsoft.com/en-us/rest/api/azure/devops/?view=azure-devops-rest-5.1)
- [Azure DevOps - Work items quick reference](https://docs.microsoft.com/en-us/azure/devops/boards/work-items/quick-ref?view=azure-devops)
- [Azure DevOps - Work item field index](https://docs.microsoft.com/en-us/azure/devops/boards/work-items/guidance/work-item-field?view=azure-devops)
- [Azure DevOps - Work item fields and attributes](https://docs.microsoft.com/en-us/azure/devops/boards/work-items/work-item-fields?view=azure-devops)
- [Azure DevOps - Wiql](https://docs.microsoft.com/en-us/rest/api/azure/devops/wit/wiql?view=azure-devops-rest-5.1)
- [Azure DevOps - Work Items](https://docs.microsoft.com/en-us/rest/api/azure/devops/wit/work%20items?view=azure-devops-rest-5.1)
- [Visual Studio Marketplace - Azure DevOps Wiql Editor](https://marketplace.visualstudio.com/items?itemName=ottostreifel.wiql-editor)
  - This is an addon you can add to your Azure DevOps environment to help with creating Wiql queries.
- [How to Query and Parse a REST API with PowerShell](https://mcpmag.com/articles/2019/04/02/parse-a-rest-api-with-powershell.aspx)
  -  By Adam Bertram on MCP Mag
-  [Getting started with Azure DevOps API with PowerShell](https://dev.to/omiossec/getting-started-with-azure-devops-api-with-powershell-59nn)
   -  By Olivier Miossec on DEV
-  [How to use the Azure DevOps Rest API with PowerShell](https://www.imaginet.com/2019/how-use-azure-devops-rest-api-with-powershell/)
   -  By Etinne Tremblay on Imaginet
   -  Demo is located in a GitHub repo called [AzureDevOpsRestAPIPowerShell](https://github.com/tegaaasolutions/AzureDevOpsRestAPIPowerShell/blob/master/Demos.ps1)
-  [Create vsts work item with Azure DevOps REST API](https://medium.com/@sandeepsinh/create-work-item-with-rest-api-in-azure-devops-28f979a12f37)
   -  By Sandeep Singh on Medium
-  [Controlling Azure DevOps from PowerShell](https://veegens.wordpress.com/2019/09/06/controlling-azure-devops-from-powershell/)
   -  By Fokko Veegens on his WordPress site
-  [Create Azure DevOps User Story using Powershell](https://arindamhazra.com/create-azure-devops-user-story-using-powershell/)
   -  By Arindam Hazra on Tech Automation Blog
-  [Create Azure DevOps Task using Powershell](https://arindamhazra.com/create-azure-devops-task-using-powershell/)
   -  By Arindam Hazra on Tech Automation Blog

## Additional Thanks
I want to thank some of my wonderful friends, coworkers, and my boyfriend who helped me troubleshoot this script and get it working. It started as a fun personal project I was playing with outside work, which then turned into something helpful at work and in my personal play areas. While functional, I am going to be looking at ways to refactor it soon to clean it up and improve its quality. However, I hope that it can serve as a helpful tool to people in the mean time.