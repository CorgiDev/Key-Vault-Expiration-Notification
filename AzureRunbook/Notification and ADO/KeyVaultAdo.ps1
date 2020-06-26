######################################
# Variables
# Please note that this script will 
# only work for items in the same 
# subscription as the automation 
# account.
######################################
# Key Vault being checked
$VaultName = "{Vault Name}" #Vault being searched. Must be on same subscription as Automation Account.
# Service Account Info
$ServiceAccountEmail = "{Service Account Email Sending Notifications}"
$ServiceAccountEmailPasswordLabel = "{Key Vault Label for Service Account Password}"
$ServiceAccountEmailLabel = "{Key Vault Label for Service Account Email Address}" # If stored separately from password
$ServiceAccountKeyVault = "{Name of Key Vault where Service Account Info stored}" #Vault where pulling service account
# Key Vault query info
$IncludeAllKeyVersions = $true
$IncludeAllSecretVersions = $true
$KeyvaultUri = "https://ms.portal.azure.com/{depends on your org}/asset/Microsoft_Azure_KeyVault/Secret/" # Navigate into a keyvault secret and you will see this portion of the url. Replace the bracketed area with whatever is in your URL.
# Email info
$RecipientEmail = "{Receiving Email or DL address}"
$To = $RecipientEmail
$From = $ServiceAccountEmail
$AlertRange = 40
$Port = 587
$SMTPServer = "smtp.office365.com"

# Misc variables
$today = (Get-Date).Date
$divider = "==========================================================================================================="

# ADO Info
$adoOrg = "{OrgName in ADO Url}"
$adoProj = "{Proj name in ADO Url}"
$adoTeam = "{Team Name}"
$adoApiVersion ="api-version=5.1"
$baseOrgUri = "https://dev.azure.com/$adoOrg/$adoProj" 
$adoWiki = "{Location of your asset update documentation}"
$wiqlUri = "$baseOrgUri/$adoTeam/_apis/wit/wiql?$adoApiVersion"
$workItemBaseUrl = "https://$adoOrg.visualstudio.com/$adoProj/_apis/wit/workitems/" # This could require this different formatting. Depends on your instance somewhat.
#$workItemBaseUrl = "$baseOrgUri/_apis/wit/workitems/"
$createWorkUri = (-join ($workItemBaseUrl,"`$","User%20Story?", $adoApiVersion)) # I fyou prefer to make "tasks" instead, swap it for "Tasks?"
$workItemViewUri = "$baseOrgUri/_workitems/edit/"
# ADO PAT
$encryptedPatVarName = "{ADO Personal Access Token variable name in Automation Account variables}"
$adoPat = Get-AutomationVariable -Name $encryptedPatVarName # Works for encrypted variable stored in Automation Account. Same method can be used to retrieve other variables if you would like.
$adoPatToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($adoPat)"))
$adoHeader = @{authorization = "Basic $adoPatToken"}

##################################
# Connecting with Run As Account
##################################
$connectionName = "AzureRunAsConnection"
try
{
	# Get the connection "AzureRunAsConnection "
	$servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         
	"Logging in to Azure..."
	Add-AzureRmAccount `
		-ServicePrincipal `
		-TenantId $servicePrincipalConnection.TenantId `
		-ApplicationId $servicePrincipalConnection.ApplicationId `
		-CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
    "Connected to Azure..."
}
catch {
	if (!$servicePrincipalConnection)
	{
		$ErrorMessage = "Connection $connectionName not found."
		throw $ErrorMessage
	} else{
		Write-Error -Message $_.Exception
		throw $_.Exception
	}
}

###############
# Functions
###############
Function New-KeyVaultObject {
	param
	(
		[string]$Id,
		[string]$Name,
		[string]$Version,
		[System.Nullable[DateTime]]$Expires
	)
	$server = New-Object -TypeName PSObject
	$server | Add-Member -MemberType NoteProperty -Name Id -Value $Id
	$server | Add-Member -MemberType NoteProperty -Name Name -Value $Name
	$server | Add-Member -MemberType NoteProperty -Name Version -Value $Version
	$server | Add-Member -MemberType NoteProperty -Name Expires -Value $Expires
		
	return $server
}

function Get-AzureKeyVaultObjectKeys {
	param
	(
		[string]$VaultName,
		[bool]$IncludeAllVersions
	)
	$vaultObjects = [System.Collections.ArrayList]@()
	$allKeys = Get-AzureKeyVaultKey -VaultName $VaultName
	foreach ($key in $allKeys) {
		if($IncludeAllVersions){
			$allSecretVersion = Get-AzureKeyVaultKey -VaultName $VaultName -IncludeVersions -Name $key.Name
			foreach($key in $allSecretVersion){
			$vaultObject = New-KeyVaultObject -Id $key.Id -Name $key.Name -Version $key.Version -Expires $key.Expires
			$vaultObjects.Add($vaultObject)
		}
		} else {
			$vaultObject = New-KeyVaultObject -Id $key.Id -Name $key.Name -Version $key.Version -Expires $key.Expires
			$vaultObjects.Add($vaultObject)
		}
	}
	return $vaultObjects
}

function Get-AzureKeyVaultObjectSecrets {
	param
	(
		[string]$VaultName,
		[bool]$IncludeAllVersions
	)

	$vaultObjects = [System.Collections.ArrayList]@()
	$allSecrets = Get-AzureKeyVaultSecret -VaultName $VaultName
	foreach ($secret in $allSecrets) {
		if($IncludeAllVersions){
			$allSecretVersion = Get-AzureKeyVaultSecret -VaultName $VaultName -IncludeVersions -Name $secret.Name
			foreach($secret in $allSecretVersion){
			$vaultObject = New-KeyVaultObject -Id $secret.Id -Name $secret.Name -Version $secret.Version -Expires $secret.Expires
			$vaultObjects.Add($vaultObject)
		}
		} else {
			$vaultObject = New-KeyVaultObject -Id $secret.Id -Name $secret.Name -Version $secret.Version -Expires $secret.Expires
			$vaultObjects.Add($vaultObject)
		}
	}
	return $vaultObjects
}

#Checks if open work item already exists for the asset expiring
function Search-AzureDevOpsWorkItems {
	param
	(
		[string]$SearchTitle,
		[string]$SearchUri
	)
	# The Query (Can be altered for your needs. Searching for work items with a title matching the email subject that are not in a closed, resolved, or removed state)
	$searchQuery = "SELECT [System.Title],[System.State],[System.ChangedDate] FROM workitems WHERE [System.Title] CONTAINS WORDS '"+ $SearchTitle + "' AND [System.State]<>'Removed' AND [System.State]<>'Closed' AND [System.State]<>'Resolved' ORDER BY [System.ChangedDate] DESC"
	$searchBody = ConvertTo-Json @{query = $searchQuery} # Converts query to JSON format for WIQL API call
	#The search itself
	$searchResults = Invoke-RestMethod -Uri $wiqlUri -Method Post -ContentType "application/json" -Headers $adoHeader -Body $searchBody
	return $searchResults
}

# Creates new work item with provided criteria. You can remove some parameters and hard code them if they will be the same every time.
# Area path must have double-backslashes to work
function New-AzureDevOpsWorkItem {
	param
	(
		[string]$workItemTitle,
		[string]$workItemDescription,
        [DateTime]$workItemDueDate,
        [String]$TaskState,
        [String]$TaskStateReason,
        [String]$AreaPathString,
        [String]$WorkRequestType,
        [String]$AcceptanceCriteriaString,
        [Int]$WorkItemPriority
	)
	$workItemBody = @"
[
	{
		“op”: “add”,
		“path”: “/fields/System.Title”,
		“from”: null,
		“value”: “$workItemTitle"
	},
	{
		“op”: “add”,
		“path”: “/fields/System.Description”,
		“from”: null,
		“value”: “$workItemDescription"
	},
	{
		“op”: “add”,
		“path”: “/fields/Microsoft.VSTS.Common.Priority”,
		“from”: null,
		“value”: $WorkItemPriority
	},
	{
		“op”: “add”,
		“path”: “/fields/System.State”,
		“from”: null,
		“value”: “$TaskState”
	},
	{
		“op”: “add”,
		“path”: “/fields/System.Reason”,
		“from”: null,
		“value”: “$TaskStateReason"
	},
	{
		“op”: “add”,
		“path”: “/fields/System.AreaPath”,
		“from”: null,
		“value”: “$AreaPathString”
	},
	{
		“op”: “add”,
		“path”: “/fields/Custom.WorkRequestType”,
		“from”: null,
		“value”: "$WorkRequestType"
	},
	{
		“op”: “add”,
		“path”: “/fields/Microsoft.VSTS.Scheduling.DueDate”,
		“from”: null,
		“value”: "$workItemDueDate"
	},
	{
		“op”: “add”,
		“path”: “/fields/Microsoft.VSTS.Common.AcceptanceCriteria”,
		“from”: null,
		“value”: “$AcceptanceCriteriaString”
	}
]
"@
	$createWorkItemResult = Invoke-RestMethod -Uri $createWorkUri -Method Post -ContentType "application/json-patch+json" -Headers $adoHeader -Body $workItemBody
	return $createWorkItemResult
}

#######################
# Script Starts Here
#######################
$allKeyVaultObjects = [System.Collections.ArrayList]@()
$allKeyVaultObjects.AddRange((Get-AzureKeyVaultObjectKeys -VaultName $VaultName -IncludeAllVersions $IncludeAllKeyVersions))
$allKeyVaultObjects.AddRange((Get-AzureKeyVaultObjectSecrets -VaultName $VaultName -IncludeAllVersions $IncludeAllSecretVersions))

# Gather service account password for notifications
try {
	$ServicePassword = (Get-AzureKeyVaultSecret -vaultName $ServiceAccountKeyVault -name $ServiceAccountEmailPasswordLabel).SecretValueText
	$Password = ConvertTo-SecureString $ServicePassword -AsPlainText -Force
}
catch {
	Write-Error -Message $_.Exception
	throw $_.Exception
}
$Creds = New-Object System.Management.Automation.PSCredential($ServiceAccountEmail, $Password) #email hard-coded

#################################################
# URLs and some other info useful for debugging
#################################################
$divider
Write-Output "The following are URLs used throughout this Runbook."
Write-Output "The parsed work item creation URL is $createWorkUri"
Write-Output "The parsed URL for WIQL queries used to search Work Items is: $wiqlUri"
Write-Output "The url for viewing work items based on their ID is: $workItemViewUri + id#"
Write-Output "The Org's ADO wiki is located at: $adoWiki"
Write-Output "The base url for the Org's ADO used in many of the API calls here is: $baseOrgUri"
Write-Output "The API calls here use the following ADO Rest API version: $adoApiVersion"
$divider
#################################
# Get expired objects and notify
#################################
$expiredCount = 0
$expiredKeyVaultObjects = [System.Collections.ArrayList]@()
foreach($vaultObject in $allKeyVaultObjects) {
    $assetBody = ""
    $ticketbody = ""
	#Send alert if within the number of days set by $AlertRange
	if ($vaultObject.Expires -and $vaultObject.Expires.AddDays(-$AlertRange).Date -lt $today) {
		# add to expiry list
		$expiredKeyVaultObjects.Add($vaultObject) | Out-Null
		$secretName = $vaultObject.Name
		$secretExpire = $vaultObject.Expires
		$secretUri = (-join ($KeyvaultUri, $vaultObject.Id))
		Write-Output "The following secret is expiring soon: $secretName!"
		$searchSubject = "$secretName in Key Vault expiring on $secretExpire"
        $ticketBody = Write-Output "The $secretName secret in the Key Vaults is expiring on $secretExpire :<br/><br/> $secretUri <br/><br/>This credential may have multiple parts, and be located in multiple Key Vaults. See $adoWiki for more details."
		$expiredCount += 1 # Increases the expired count for end summary / email
		$divider
		Write-Output "Searching to see if work item needs to be created."
		#############################
		# Start ADO Work Item search
		#############################
		$searchResults = Search-AzureDevOpsWorkItems -SearchTitle $searchSubject
		$workItemsList = $searchResults.workItems
		$workItemCount = $workItemsList.Length
		if($workItemCount -ge 0){
            # Confirms search worked
			Write-Output "Search successful."
			# If no matching workitems ----> "workItems: {}"
			Write-Output "The following is a summary of the search results:"
			$searchResults
			$divider
			if($workItemCount -ge 1)
			{
                # Indicates matching work items already exist so new one is not needed.
				$workItemListString = ""
                Write-Output "Search returned $workItemCount matching work items. You should check ADO to ensure none of these need to be deleted. The matching work items include:"
				foreach($item in $workItemsList){
					$itemUri = (-join ($workItemViewUri, $item.id))
					$itemUri
                    $workItemListString = $workItemListString + "- $itemUri</br></br>"
				}
                $assetBody = Write-Output "The $secretName secret in the Key Vault is expiring on $secretExpire : $secretUri. <br/><br/> It appears that work item(s) may have already been created for this expiring asset. See the list below for details.<br/><br/>$workItemListString This credential may have multiple parts, and be located in multiple Key Vaults. See $adoWiki for more details."
				$divider
			}
			elseif($workItemCount -eq 0){
				################################
				# Start ADO Work Item Creation
				################################
				Write-Output "No matching work items found. Beginning work item creation."
                $createWorkItemResult = New-AzureDevOpsWorkItem -workItemTitle $searchSubject -workItemDescription $ticketBody -workItemDueDate $secretExpire -TaskState "New" -TaskStateReason "New" -AreaPathString "Area\\Path\\For\\Item" -WorkRequestType "{WorkRequestTypeHere}" -AcceptanceCriteriaString "Put whatever you want for acceptance criteria, including some HTML." -WorkItemPriority 1
				$newWorkItemId = $createWorkItemResult.Id
				$newWorkItemUri = (-join ($workItemViewUri, $newWorkItemId))
				Write-Output "Work item created successfully. To view it, navigate to $newWorkItemUri"
                $assetBody = Write-Output "The $secretName secret in the Key Vault is expiring on $secretExpire : $secretUri. <br/><br/>No exisiting work item was found for this asset expiration event. A new one was created at $newWorkItemUri.<br/><br/>This credential may have multiple parts, and be located in multiple Key Vaults. See $adoWiki for more details."
				$divider
			}
		}
        Write-Output "Sending notification email for $secretName."
        # Sends the message
		Send-MailMessage -to $To -From $From -Subject $searchSubject -BodyAsHtml ($assetBody | Out-String) -SmtpServer $SMTPServer -Port $Port -UseSsl -Credential $Creds
        Write-Output "Email notification for $secretName sent."
        $divider
	}
}

######################################################
# Sends special notification if nothing is expiring,
# and provide end summary.
######################################################
Write-Output "RUNBOOK END SUMMARY"
if($expiredCount -eq 0){
	$verifySubject = "No assets expiring this sprint"
	$verifyBody = "Good news everybody! No assets are expiring this sprint. This email appears so you know the job is still running. If you were expecting something to be expiring soon, then this also serves as a reminder that you might want to go check Key Vault."
	Send-MailMessage -to $To -From $From -Subject $verifySubject -BodyAsHtml ($verifyBody | Out-String) -SmtpServer $SMTPServer -Port $Port -UseSsl -Credential $Creds
	$verifySubject
	$divider
}
elseif($expiredCount -ge 1){
	Write-Output "There are $expiredCount assets expiring soon."
	Write-Output "The following assets are expiring sometime within the next $AlertRange days:"
	$expiredKeyVaultObjects.Id
    Write-Output "Emails should have been created by this runbook, and work items created as needed."
	$divider
}