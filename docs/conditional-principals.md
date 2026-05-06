# Conditional Principals Configuration

## Overview

The enhanced tiermodel using json supports conditional assignment of principals (users, groups, services) based on domain environment characteristics. This enables a single configuration file to work across different scenarios:

- Forest root vs child domains
- Presence/absence of specific groups
- Different DNS configurations
- Various principal types requiring different resolution methods

## Principal Structure

### Bulk Array Approach (Recommended for Large Groups)

For scenarios with many principals, use the `principalGroups` or `memberGroups` structure:

```json
{
  "principalGroups": {
    "alwaysInclude": ["Group1", "Group2", "Group3", ...],
    "forestRootOnly": ["Enterprise Admins", "Schema Admins"],
    "conditionalGroups": [
      {
        "names": ["Group4", "Group5", "Group6", ...], 
        "conditions": [...],
        "comment": "Description"
      }
    ],
    "literalStrings": ["NT SERVICE\\Service1", "NT SERVICE\\Service2", ...]
  }
}
```

### Individual Object Approach (For Complex Conditions)

For complex individual conditions, use the detailed object structure:

```json
{
  "name": "GroupOrUserName",
  "type": "group|user|ntService|wellKnownSid", 
  "resolveSid": true|false,
  "required": true|false,
  "conditions": [...],
  "comment": "Description"
}
```

## Principal Types

### `group` and `user`
- **resolveSid**: `true` - Will be resolved to SID using Get-ADGroup/Get-ADUser
- **Usage**: Standard AD groups and users that exist in the domain

### `ntService` 
- **resolveSid**: `false` - Used as literal string, no AD resolution
- **Usage**: NT SERVICE accounts like "NT SERVICE\himds", "NT SERVICE\MSSQLSERVER"
- **Format**: Use exact string including "NT SERVICE\" prefix

### `wellKnownSid`
- **resolveSid**: `true` - Translated using well-known SID resolution
- **Usage**: Built-in accounts like "SYSTEM", "LOCAL SERVICE", etc.

## Condition Types

### Domain Type Detection
```json
{
  "type": "domainType",
  "value": "forestRoot|childDomain", 
  "operator": "equals|notEquals"
}
```

**Use Cases:**
- Include Schema Admins only in forest root domain
- Skip Enterprise Admins and Enterprise Key Admins in child domains
- Domain-specific service accounts

### Group Existence Check
```json
{
  "type": "groupExists",
  "value": "GroupName",
  "operator": "exists|notExists"
}
```

**Use Cases:**
- Include DnsAdmins only if it exists
- Skip groups that may not be present in all environments
- Optional security groups

### AD-Integrated DNS Detection
```json
{
  "type": "groupExists",
  "operator": "exists"
}
```

**Use Cases:**
- Include DnsAdmins/DnsUpdateProxy only if AD-Integrated DNS was configured
- Skip DNS groups when third-party DNS solutions are used
- Gracefully handle environments without AD-DNS integration

**Background:** During forest/domain setup, the wizard asks whether to configure AD-Integrated DNS. If "Yes" is selected, DnsAdmins and DnsUpdateProxy groups are created. If organizations use third-party DNS solutions (like BIND, Infoblox, etc.), these groups don't exist because there's no AD-DNS integration.

## Deployment Scenarios

### Scenario 1: AD-Integrated DNS Environment
- **Setup**: Domain wizard configured with AD-Integrated DNS
- **Groups Present**: DnsAdmins, DnsUpdateProxy exist in AD
- **Tier Model Behavior**: Groups are included in rights assignments
- **Use Case**: Traditional Windows-centric environments

### Scenario 2: Third-Party DNS Environment  
- **Setup**: Domain wizard configured without AD-Integrated DNS
- **Groups Present**: DnsAdmins, DnsUpdateProxy do NOT exist
- **Tier Model Behavior**: Groups are automatically skipped
- **Use Case**: Organizations using BIND, Infoblox, AWS Route 53, etc.

### Scenario 3: Mixed Environment
- **Setup**: Some domains have AD-DNS, others use third-party
- **Groups Present**: Varies by domain
- **Tier Model Behavior**: Adapts per domain during deployment
- **Use Case**: Large enterprises with diverse DNS strategies

## Example: SeLogonAsServiceRight Assignment (Bulk Array Approach)

```json
{
  "right": "SeLogonAsServiceRight",
  "principalGroups": {
    "alwaysInclude": [
      "Tier0-ServiceAccounts",
      "Tier0-BackupOperators", 
      "Tier0-NetworkOperators",
      "Custom-ServiceGroup1",
      "Custom-ServiceGroup2"
    ],
    "forestRootOnly": [
      "Schema Admins",
      "Enterprise Admins"
    ],
    "conditionalGroups": [
      {
        "names": ["DnsAdmins", "DnsUpdateProxy"],
        "conditions": [
          {
            "type": "groupExists",
            "operator": "exists"
          }
        ],
        "comment": "AD-Integrated DNS groups - only exist if AD-Integrated DNS was configured during domain setup"
      }
    ],
    "literalStrings": [
      "NT SERVICE\\himds",
      "NT SERVICE\\MSSQLSERVER",
      "NT SERVICE\\SQLWriter",
      "NT SERVICE\\SQLTELEMETRY"
    ]
  }
}
```

## Example: Restricted Groups (Bulk Array Approach)

```json
{
  "groupName": "Administrators",
  "memberGroups": {
    "alwaysInclude": [
      "Domain Admins",
      "Tier0-Admins",
      "Tier0-LocalAdmins",
      "DC-LocalAdmins"
    ],
    "forestRootOnly": [
      "Enterprise Admins",
      "Schema Admins"
    ],
    "conditionalGroups": [
      {
        "names": ["Custom-Tier0-Group1", "Custom-Tier0-Group2", "Emergency-Admins"],
        "conditions": [
          {
            "type": "groupExists",
            "operator": "exists"
          }
        ],
        "comment": "Optional Tier 0 administrative groups"
      }
    ],
    "literalStrings": [
      "BUILTIN\\Administrators"
    ]
  }
}
```

## GPO Link Target Resolution

### Default GPO Scoping
All GPOs use the default scoping of **"Authenticated Users"**. No explicit scope configuration is needed as this is the Windows default behavior.

### Domain Root Linking
For GPOs that need to be linked at the domain level, use the special token:

```json
{
  "links": [
    {
      "target": "{{DOMAIN_DN}}",
      "linkEnabled": true,
      "comment": "Link to domain root - resolved dynamically"
    }
  ]
}
```

### OU Linking  
For OU-specific GPO links, use relative OU paths:

```json
{
  "links": [
    {
      "target": "OU=Tier0",
      "linkEnabled": true,
      "comment": "Link to Tier0 OU - path constructed with domain DN"
    }
  ]
}
```

### Multiple Link Targets
GPOs can be linked to multiple locations:

```json
{
  "links": [
    {
      "target": "{{DOMAIN_DN}}",
      "linkEnabled": true,
      "comment": "Apply to entire domain"
    },
    {
      "target": "OU=Tier0",
      "linkEnabled": true,
      "comment": "Also apply specifically to Tier0 OU"
    }
  ]
}
```

## Implementation Logic

The deployment engine will:

1. **Resolve Link Targets**: 
   - `{{DOMAIN_DN}}` → Resolve to current domain DN using Get-ADDomain
   - `OU=Path` → Construct full DN by combining with domain DN
2. **Evaluate Conditions**: Check each condition against current environment
3. **Filter Principals**: Include only principals where all conditions are met
4. **Handle Resolution**: 
   - `resolveSid: true` → Resolve to SID using appropriate AD cmdlet
   - `resolveSid: false` → Use literal string value
5. **Apply Assignments**: Configure GPO with resolved principal list
6. **Create Links**: Use New-GPLink with resolved target DNs

## Error Handling

- **Required Principals**: If `required: true` and conditions fail, deployment fails
- **Optional Principals**: If `required: false` and conditions fail, principal is skipped
- **Missing Groups**: If group doesn't exist and `required: true`, deployment fails
- **Resolution Errors**: Failed SID resolution for required principals causes deployment failure

## Bulk Array Categories

### `alwaysInclude`
- **Behavior**: Groups that are always assigned (required: true)
- **Resolution**: All groups resolved to SIDs via Get-ADGroup
- **Use Case**: Core groups that must exist in all environments

### `forestRootOnly` 
- **Behavior**: Groups only included in forest root domains
- **Resolution**: All groups resolved to SIDs via Get-ADGroup
- **Use Case**: Enterprise-level groups like "Enterprise Admins", "Schema Admins"

### `conditionalGroups`
- **Behavior**: Arrays of groups with shared conditions
- **Resolution**: All groups resolved to SIDs via Get-ADGroup  
- **Use Case**: Feature-specific groups that may not exist in all environments

### `literalStrings`
- **Behavior**: Strings used as-is without SID resolution
- **Resolution**: No AD lookup performed
- **Use Case**: NT SERVICE accounts, built-in principals, special identifiers

## Bulk User Rights Assignment

### Multiple Rights with Same Principals
For scenarios where multiple User Rights Assignments need the same groups, use the `rights` array:

```json
{
  "rights": [
    "SeLogonAsServiceRight",
    "SeBatchLogonRight", 
    "SeServiceLogonRight",
    "SeInteractiveLogonRight",
    "SeNetworkLogonRight"
  ],
  "principalGroups": {
    "alwaysInclude": ["ServiceGroup1", "ServiceGroup2", ...]
  },
  "comment": "Apply same principals to multiple rights"
}
```

### Individual Rights Assignment
For rights with unique principal requirements, use single `right`:

```json
{
  "rights": ["SeDenyNetworkLogonRight"],
  "principalGroups": {
    "alwaysInclude": ["Tier0-Admins"]
  },
  "comment": "Specific denial for security isolation"
}
```

## Benefits

### Bulk Array Advantages:
1. **Concise Configuration**: 22 groups in 1 array instead of 22 objects
2. **Shared Logic**: Common conditions applied to multiple groups
3. **Maintainable**: Easy to add/remove groups from categories
4. **Performance**: Batch processing of similar principals
5. **Clear Categorization**: Explicit grouping by deployment behavior

### Overall Benefits:
1. **Single Configuration**: One file works across forest root and child domains
2. **Environment Adaptation**: Automatically adapts to DNS configuration and group availability  
3. **Flexible Principal Types**: Supports AD objects, NT services, and well-known accounts
4. **Defensive Deployment**: Gracefully handles missing optional components
5. **Clear Intent**: Explicit conditions document deployment behavior
6. **Scalable**: Handles large numbers of principals efficiently

This approach eliminates the need for multiple configuration files or complex conditional logic in deployment scripts while maintaining excellent readability and performance.

## Related Documentation

For additional documentation, see:
- [GPO Management Strategy](gpo-management-strategy.md)
- [Detailed Deployment Guide](detailed-deployment-guide.md)
- [Drift Detection Details](drift-detection-details.md)