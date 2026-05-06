# Required Modules
Import-Module ActiveDirectory

# Get the CN and Name of the current domain
$Domain = Get-ADDomain
$DomainCN = $Domain.DistinguishedName

# Get the current ACL of the OU
$ACL = Get-Acl "AD:$DomainCN"

# Define Auditing Permissions Properly (Casting Each), excluding Full, List, Read all Properties, and Read Permissions to reduce event log noise
$AuditRights = [System.DirectoryServices.ActiveDirectoryRights]::CreateChild -bor `
               [System.DirectoryServices.ActiveDirectoryRights]::DeleteChild -bor `
               [System.DirectoryServices.ActiveDirectoryRights]::WriteProperty -bor `
               [System.DirectoryServices.ActiveDirectoryRights]::Self -bor `
               [System.DirectoryServices.ActiveDirectoryRights]::Delete -bor `
               [System.DirectoryServices.ActiveDirectoryRights]::DeleteTree -bor `
               [System.DirectoryServices.ActiveDirectoryRights]::WriteDacl -bor `
               [System.DirectoryServices.ActiveDirectoryRights]::WriteOwner -bor `
               [System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight

# Define the Audit Rule
$AuditRule = New-Object System.DirectoryServices.ActiveDirectoryAuditRule(
    [System.Security.Principal.NTAccount]("Everyone"),
    $AuditRights,
    [System.DirectoryServices.ActiveDirectorySecurityInheritance] "All",
    [System.Security.AccessControl.AuditFlags]::Success
)

# Apply Audit Rule to the OU
$ACL.AddAuditRule($AuditRule)

# Set the new ACL to the OU
Set-Acl -Path "AD:$DomainCN" -AclObject $ACL