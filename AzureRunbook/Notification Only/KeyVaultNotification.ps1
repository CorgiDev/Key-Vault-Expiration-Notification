#####################
# Variables
#####################
# Key Vault being checked
$VaultName = "{Name of Vault being checked}" # Must be within the same subscription as the automation account
# Service Account Info
$ServiceAccountEmail = "{Email of Service Account}"
$ServiceAccountEmailLabel = "{Label of Service Account Email in KeyVault}" # Only needed if you plan to pull that from key vault too, but have to make other changes if doing that too
$ServiceAccountPasswordLabel = "{Label for service account password in KeyVault}"
$ServiceAccountKeyVault = "{Name of Vault where Service Account info is stored}"

# Key Vault query info
$IncludeAllKeyVersions = $true
$IncludeAllSecretVersions = $true
$KeyvaultUri = "https://ms.portal.azure.com/{depends on your org}/asset/Microsoft_Azure_KeyVault/Secret/" # Navigate into a keyvault secret and you will see this portion of the url. Replace the bracketed area with whatever is in your URL.

# Email Info
$RecipientEmail = "{Email or DL that notifications need to go to}"
$From = $ServiceAccountEmail
$Port = 587
$SMTPServer = "smtp.office365.com"

# ADO Info
$adoWiki = "{URL where documentation is stored relating to various assets}"
$adoOrg = "{Org Name in ADO URL}"
$adoProj = "{Proj Name in ADO URL}"
$ADO_PAT_Variable = Get-AutomationVariable -Name "{ADO PAT Variable name in Azure Automation Account}" # This version works with encrypted variables so you can store it encrypted rather than unencrypted
$PAT = $ADO_PAT_Variable.value

# Misc Variables
$divider = "==========================================================================================================="
$AlertRange = 40
$today = (Get-Date).Date

#######################
# Script Starts Here
#######################
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

$allKeyVaultObjects = [System.Collections.ArrayList]@()
$allKeyVaultObjects.AddRange((Get-AzureKeyVaultObjectKeys -VaultName $VaultName -IncludeAllVersions $IncludeAllKeyVersions))
$allKeyVaultObjects.AddRange((Get-AzureKeyVaultObjectSecrets -VaultName $VaultName -IncludeAllVersions $IncludeAllSecretVersions))
try {
  # Email and password for service account sending notification emails
  # $ServiceUsername = (Get-AzureKeyVaultSecret -vaultName $ServiceAccountKeyVault -name $ServiceAccountEmailLabel).SecretValueText
  # $ServiceUsername = (Get-AzureKeyVaultSecret -vaultName $ServiceAccountKeyVault -name $ServiceAccountPasswordLabel).ContentType # Use this if the email is the COntent Type of the Password entry instead of a separate Key Vault object.
  $ServicePassword = (Get-AzureKeyVaultSecret -vaultName $ServiceAccountKeyVault -name $ServiceAccountPasswordLabel).SecretValueText
  $Password = ConvertTo-SecureString $ServicePassword -AsPlainText -Force
}
catch {
  Write-Error -Message $_.Exception
  throw $_.Exception
}
$Creds = New-Object System.Management.Automation.PSCredential($ServiceAccountEmail, $Password)

# Get expired Objects
$expiredCount = 0
$expiredKeyVaultObjects = [System.Collections.ArrayList]@()
foreach($vaultObject in $allKeyVaultObjects) {
  # Send SRE Alert if within the number of days set by SREAlert days
  if ($vaultObject.Expires -and $vaultObject.Expires.AddDays(-$AlertRange).Date -lt $today) {
    # Add to expiry list
    $expiredKeyVaultObjects.Add($vaultObject) | Out-Null
    Write-Output "Expiring" $vaultObject.Id
    $secretName = $vaultObject.Name
    $To = $RecipientEmail
    $Subject = "$secretName in Key Vaults expiring in next $AlertRange days"
    $Body = Write-Output "The " $secretName " secret in the Key Vault is expiring on " $vaultObject.Expires " : " (-join ($KeyvaultUri, $vaultObject.Id)) ". <br/><br/> This credential may have multiple parts, and be located in multiple Key Vaults. See $adoWiki for more details."
    
    Send-MailMessage -to $To -From $From -Subject $Subject -BodyAsHtml ($Body | Out-String) -SmtpServer $SMTPServer -Port $Port -UseSsl -Credential $Creds
    $expiredCount += 1
  }
}
$expiredCount

if($expiredCount -eq 0){
  $Subject = "No assets expiring this sprint"
  $Body = "Good news everybody! No assets are expiring in the next $AlertRange days. This email appears so you know the job is still running. If you were expecting something to be expiring soon, then this also serves as a reminder that you might want to go check Key Vault."
  Send-MailMessage -to $To -From $From -Subject $Subject -BodyAsHtml ($Body | Out-String) -SmtpServer $SMTPServer -Port $Port -UseSsl -Credential $Creds
}
elseif($expiredCount -ge 1){
  Write-Output "There are $expiredCount assets expiring soon."
  Write-Output "The following assets are expiring sometime within the next $AlertRange days:"
  $expiredKeyVaultObjects
}