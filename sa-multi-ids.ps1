# Quick script to manually change or alter specific azure resources according to our defaults

param(
   $resourceIDs,
   $command = "none",
   $public_access = "deny",
   [switch]$set,
   [switch]$categories
)

foreach ($resourceID in $resourceIDs) {

 
   # Function to show/set public access information
   function set_public_access() {
      # Only set the rules if we have the set flag
      if ($set) {
         Write-Host "Nothing here yet. You can only list network rules for keyvaults"
      }
      else {
         az keyvault network-rule list --name $name --resource-group $rg --subscription $sub
      }
      return
   }

   # Keyvault section - functions and commands for keyvaults
   function set_keyvault() {
      param(
         $resourceID,
         $command
      )


      # Function to show/set keyvault purge protection information
      function set_purge_protect() {
         # Only set purge protection if we have the set flag
         if ($set) {
            az keyvault update --name $name --resource-group $rg --subscription $sub --enable-purge-protection
         }
         else {
            az keyvault show --name $name --resource-group $rg --subscription $sub --query "{Name:name, Purge:properties.enablePurgeProtection, SoftDelete:properties.enableSoftDelete}" --output json
         }
         return
      }
   
      # Function to set default Barings audit diag settings
      function set_audit_diag() {
         param(
            $diagName = "evhns-baringsauditlog-pr-diag",
            $eventRule = "/subscriptions/ed5fa5ae-d7eb-4e95-94d0-b4589b057b3c/resourceGroups/rg-eventhub-pr/providers/Microsoft.EventHub/namespaces/evhns-baringsauditlog-pr/authorizationRules/evhns-baringsauditlog-pr-diag",
            $eventHubName = "auditlogging"
         )
   
         # Defaults
         $temp_json = "./temp_kv_diag.json"
      
         # If set switch is not on, just list the current diag settings and exit
         if (!($set)) {
            az monitor diagnostic-settings list --resource $resourceID
            return
         }
      
         # JSON for the logs data
         $logs_json = @"
[
  {
    "category": "AuditEvent",
    "enabled": true,
    "retentionPolicy": {
      "enabled": true,
      "days": 7
    }
  }
]
"@

         # Write our temp json file
         $logs_json | Out-File $temp_json
      
         # Now write our new diag settings from the json output file
         Get-Content -Path $temp_json | az monitor diagnostic-settings create --subscription $sub --resource "$resourceID" -n $diagName --event-hub-rule $eventRule --event-hub $eventHubName --logs "@-"
      
         # Cleanup
         Remove-Item $temp_json -Force | Out-Null
      }

      # If our command is audit, just do the audit part
      switch ($command) {
         "audit" { set_audit_diag }
         "public" { set_public_access }
         "purge" { set_purge_protect }
         default {
            Write-Host "You must supply a valid command to use : -command audit|public|purge"
            exit 1
         }
      }
   }

   # Storage section - functions and commands for storage
   function set_storage() {
      param(
         $resourceID,
         $command
      )

      # Function to show/set public access information
      function set_public_access() {
         # Only set the public access if our set flag is on
         if ($set) {
            # Depending on if we are allowing or denying access
            if ($public_access -eq "deny") {
               az storage account update --ids $resourceID --default-action Deny --bypass Logging Metrics AzureServices
            }
            elseif ($public_access -eq "allow") {
               az storage account update --ids $resourceID --default-action Allow
            }
            else {
               Write-Host "ERROR: Public access can only be allow or deny"
            }
         }
         else {
            az storage account show --ids $resourceID --query networkRuleSet
         }
         return
      }
   
      # Function to set default Barings audit diag settings
      function set_audit_diag() {
         param(
            $diagName = "evhns-baringsauditlog-pr-diag",
            $eventRule = "/subscriptions/ed5fa5ae-d7eb-4e95-94d0-b4589b057b3c/resourceGroups/rg-eventhub-pr/providers/Microsoft.EventHub/namespaces/evhns-baringsauditlog-pr/authorizationRules/evhns-baringsauditlog-pr-diag",
            $eventHubName = "auditlogging"
         )
   
         # Defaults
         $temp_json = "./temp_stor_diag.json"
      
         # If the set flag is not set, just list the categories and exit
         if (!($set)) {
            az monitor diagnostic-settings list --resource $resourceID
            return
         }
      
         # JSON for the logs data
         $logs_json = @"
[
  {
    "category": "StorageWrite",
    "categoryGroup": null,
    "enabled": true,
    "retentionPolicy": {
      "days": 7,
      "enabled": true
    }
  },
  {
    "category": "StorageRead",
    "categoryGroup": null,
    "enabled": true,
    "retentionPolicy": {
      "days": 7,
      "enabled": true
    }
  },
  {
    "category": "StorageDelete",
    "categoryGroup": null,
    "enabled": true,
    "retentionPolicy": {
      "days": 7,
      "enabled": true
    }
  }
]
"@
   
         # Write our temp json file
         $logs_json | Out-File $temp_json
      
         # Create an array of storage services
         $storage_types = "blobServices", "tableServices", "queueServices", "fileServices"
      
         # Only useful for storage accounts
         foreach ($type in $storage_types) {
            Get-Content -Path $temp_json | az monitor diagnostic-settings create --subscription $sub --resource "$resourceID/$type/default" -n $diagName --event-hub-rule $eventRule --event-hub $eventHubName --logs "@-"
         }
      
         # Cleanup
         Remove-Item $temp_json -Force | Out-Null
      }

      # If our command is audit, just do the audit part
      switch ($command) {
         "audit" { set_audit_diag }
         "public" { set_public_access }
         default {
            Write-Host "You must supply a valid command to use : -command audit|public"
            exit 1
         }
      }
   }

   # They must supply a resourceID, so exit if not
   if (!($resourceID)) {
      Write-Host "ERROR: You must supply a valid resourceID of the resource to use!"
      exit 1
   }
   else {
      $sub = ($resourceID.Split("/"))[2]
      $rg = ($resourceID.Split("/"))[4]
      $name = ($resourceID.Split("/"))[8]
      $type = ($resourceID.Split("/"))[6]
   }

   # If categories switch is on, just list categories available and exit      
   if ($categories) {
      az monitor diagnostic-settings categories list --resource $resourceID
   }

   # Depending on the type of resource ID, handle appropriately
   switch ($type) {
      "Microsoft.Storage" { 
         set_storage -resourceID $resourceID -command $command
      }
      "Microsoft.KeyVault" {
         set_keyvault -resourceID $resourceID $subscription -command $command
      }
   }
}