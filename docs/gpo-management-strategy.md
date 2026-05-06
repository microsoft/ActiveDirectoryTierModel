# GPO Management Strategy

## Overview

The Tier Model uses a two-tiered GPO management approach to handle different types of Group Policy Objects based on their maintenance requirements and lifecycle.

## GPO Structure

### GPO Organization by OU

GPOs are organized in the JSON configuration by target OU path. Each OU contains two arrays:

**1. ImportOnlyGpo Array**

Contains GPOs that are created and optionally imported from templates without post-configuration:
- **Mode: `create`** - Create empty GPO (placeholder for manual configuration)
- **Mode: `createAndImport`** - Create and import from Microsoft SCT baselines or other templates

**2. PostConfigureGpo Array**

Contains GPOs that require post-import configuration of User Rights Assignments (URA) and Restricted Groups (RG):
- **Mode: `createImportAndConfigure`** - Create, import template, then configure URA/RG

### JSON Structure Examples

**ImportOnlyGpo with Import:**
```json
{
  "OU=Domain Controllers,{{DOMAIN_DN}}": {
    "ImportOnlyGpo": [
      {
        "name": "*- Tier 0 DCs Authentication Silo - Computer",
        "mode": "createAndImport",
        "importPath": "config\\gpo\\domain_controller\\Authentication Silo\\{GUID}",
        "gpoStatus": "UserSettingsDisabled",
        "linkOrder": 1,
        "linkEnabled": false,
        "gpoComment": "Authentication Silo configuration for Tier 0"
      }
    ]
  }
}
```

**ImportOnlyGpo Placeholder (Manual Config):**
```json
{
  "name": "*- Tier 0 DCs SOE - Computer",
  "mode": "create",
  "gpoStatus": "UserSettingsDisabled",
  "linkOrder": 2,
  "linkEnabled": false,
  "comment": "Placeholder for Standard Operating Environment settings"
}
```

**PostConfigureGpo with URA/RG:**
```json
{
  "OU=Domain Controllers,{{DOMAIN_DN}}": {
    "PostConfigureGpo": [
      {
        "name": "*- Tier 0 DCs Account Restrictions",
        "mode": "createImportAndConfigure",
        "importPath": "config\\gpo\\common\\Account Restrictions\\{GUID}",
        "gpoStatus": "UserSettingsDisabled",
        "linkOrder": 1,
        "linkEnabled": false,
        "denyApplyGroupPolicy": ["Domain Controllers"],
        "userRightsAssignments": [
          {
            "right": "SeDenyBatchLogonRight",
            "principals": {
              "resolvableGroups": ["Domain Admins", "Guests"],
              "forestRootOnly": ["Enterprise Admins", "Schema Admins"],
              "conditionalGroups": [
                {
                  "names": ["DnsAdmins", "DnsUpdateProxy"],
                  "conditions": [{"type": "groupExists", "operator": "exists"}],
                  "comment": "Only if AD-Integrated DNS configured"
                }
              ],
              "literalStrings": ["NT SERVICE\\himds"]
            }
          }
        ],
        "restrictedGroups": {
          "emptyGroups": [
            "*S-1-5-32-544__Memberof",
            "*S-1-5-32-578__Memberof",
            "*S-1-5-32-578__Members"
          ],
          "membershipGroups": [
            {
              "groupSidOrName": "*S-1-5-32-544__Members",
              "memberGroups": ["Domain Admins", "Tier0ServerOperators"]
            }
          ]
        }
      }
    ]
  }
}
```

## GPO Properties Explained

### Core Properties

#### `mode`
- **`create`**: Create empty GPO without import (placeholder for manual configuration)
- **`createAndImport`**: Create GPO, import from path, link (no post-configuration)
- **`createImportAndConfigure`**: Create GPO, import from path, configure URA/RG, link

#### `importPath`
- Relative path to exported GPO folder (contains GUID-named folder)
- Path structure: `config\\gpos\\{category}\\{guid}`

#### `gpoStatus`
- **`UserSettingsDisabled`**: Disable user configuration processing (computer-only GPO)
- **`ComputerSettingsDisabled`**: Disable computer configuration processing (user-only GPO)
- **`AllSettingsEnabled`**: Enable both user and computer processing (default)

### Configuration Properties (PostConfigureGpo Only)

#### `userRightsAssignments`
- Array of user rights with principal assignment
- Each assignment has `right` (e.g., "SeDenyBatchLogonRight") and `principals` object
- Supports conditional principal inclusion based on domain type and group existence
- See [Conditional Principals](conditional-principals.md) for detailed syntax

#### `restrictedGroups`
- Object (or empty array []) containing restricted group configurations
- **`emptyGroups`**: Array of group SID entries to clear (both __Memberof and __Members)
- **`membershipGroups`**: Array of membership definitions, each with:
  - `groupSidOrName`: SID or name of the local group (e.g., "*S-1-5-32-544__Members" for Administrators)
  - `memberGroups`: Array of AD group names to include as members
- Used to lock down local group memberships on endpoints

#### `denyApplyGroupPolicy`
- Array of group names that should be denied GPO application
- Used for security filtering and tier isolation
- Groups listed here get explicit Deny permission for "Apply Group Policy"

#### `principals` Object Structure
Used in `userRightsAssignments` to define which AD principals receive specific rights:
```json
"principals": {
  "resolvableGroups": ["Group1", "Group2"],     // Always included, resolved to SIDs
  "forestRootOnly": ["Enterprise Admins"],       // Only in forest root domain
  "conditionalGroups": [                          // Conditionally included
    {
      "names": ["DnsAdmins"],
      "conditions": [{"type": "groupExists", "operator": "exists"}]
    }
  ],
  "literalStrings": ["NT SERVICE\\service"]     // Used as-is, not resolved
}
```

#### Notes
1. The template `gpttmpl-template.inf` guarantees creation of the SecEdit file by providing blank placeholder URA lines (e.g. `SeDenyInteractiveLogonRight =`). These are fully replaced; no blank rights remain in the final file.
2. SID entries are prefixed with `*` in the INF format; literal service accounts remain unprefixed.
3. If a referenced group/user cannot be resolved and is marked mandatory, the process fails fast prior to file write.
4. Duplicate SIDs are removed before block generation; ordering follows JSON definition for determinism.
5. Restricted Groups entries produce paired lines (`<SID>__Memberof =` blank and `<SID>__Members = *SID1,*SID2`).
6. Replication delays to SYSVOL are handled via retry logic (configurable attempts/delay).
7. Integrity assertion validates expected rights count and presence of both headers before continuing.
8. Security filtering uses a helper to apply deny scopes without overwriting existing permissions unexpectedly.

## Benefits

### Separation of Concerns
- **ImportOnlyGpo**: Baselines and templates imported as-is, or placeholders for manual config
- **PostConfigureGpo**: Custom business rules with URA/RG dynamically configured

### Performance Optimization
- **GPO Status**: Disable unused sections (User/Computer) for faster processing
- **Security Filtering**: Precise targeting with `denyApplyGroupPolicy` reduces unnecessary processing

### Maintenance Efficiency
- **Template Updates**: Simple replacement of imported GPOs when baselines update
- **Custom Changes**: Isolated to PostConfigureGpo with JSON-driven configuration
- **Placeholder GPOs**: Mode "create" allows empty GPO creation for manual population

### Environment Flexibility
- **Conditional Logic**: Adapts to domain type (forest root vs child) and group availability
- **Bulk Operations**: Efficient management of multiple rights/groups via `principals` structure
- **Domain-Specific**: Conditional principals like DnsAdmins only included when appropriate

This approach provides a clean separation between imported baselines, placeholder GPOs, and custom Tier Model logic while maximizing deployment efficiency and maintainability.

## Related Documentation

For additional documentation, see:
- [Conditional Principals](conditional-principals.md)
- [Deployment Methodology](deployment-methodology.md)
- [Drift Detection Details](drift-detection-details.md)