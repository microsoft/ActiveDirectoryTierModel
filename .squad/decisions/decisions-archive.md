# Decisions Archive

Archived 2026-08-14T18:22:14.9449095+08:00

### 2026-05-29T17:50:00+08:00: Rights model decision — match existing delegation pattern
**By:** Joel (via Copilot)
**What:** For MSA/gMSA/dMSA ACL delegation, match the same delegation pattern already used for Tier 1/2 OUs (Accounts, PAW Devices, Groups, etc.):
- Tier 1/2: CreateChild/DeleteChild scoped to object class GUID on the OU + GenericAll on descendant objects of that class (existing pattern for credentials, SPNs, etc.)
- Tier 0: Already has full control at the parent OU — verify existing ACLs cover MSA/gMSA/dMSA creation in `Tier # Service Accounts` OUs. Add explicit ACEs only if needed.
- Tier 1 and Tier 2 restricted to their respective Service Accounts OUs only.
- No T000 lab validation task needed — decision is to follow established pattern.
**Why:** Consistency with existing Computer/User/Group delegation model. GenericAll on descendants is already the approved pattern across the tier model.


--- 

### 2026-05-29T17:51:00+08:00: dMSA GUID resolution — extend Resolve-DomainSpecificGuid
**By:** Joel (via Copilot)
**What:** Option A — Add `-SchemaObjectClass` parameter to `Resolve-DomainSpecificGuid.ps1` (default `attributeSchema`, pass `classSchema` for dMSA). This fixes the resolver for all future classSchema lookups.
**Why:** Cleaner, reusable fix. Avoids duplicating LDAP query logic in individual cmdlets.


--- 

### 2026-05-29T17:52:00+08:00: GUID guard — mandatory null/empty check in New-* cmdlets
**By:** Joel (via Copilot)
**What:** Every `New-TierModel*Acl` cmdlet must guard against GUID resolution failure: if resolved GUID is null, empty string, or `[Guid]::Empty`, throw a terminating error with a clear message rather than applying an over-scoped ACE. This is a security-critical requirement.
**Why:** Prevents silent privilege escalation where an unscoped ACE grants CreateChild/DeleteChild for ALL object types in the OU.


--- 

### 2026-05-29T17:53:00+08:00: Config loading — extend Get-TierModelConfig (existing pattern)
**By:** Joel (via Copilot)
**What:** New MSA/gMSA/dMSA JSON config files will be loaded via `Get-TierModelConfig` — add them to `$requiredFiles` array and merge into the config object. This matches the existing centralized loading pattern.
**Why:** Consistency — all other JSON configs are loaded centrally. Each cmdlet receives the merged config, not raw JSON.
**Note:** This means `Get-TierModelConfig.ps1` will need modification (existing file change task). The new JSON files should NOT be added to `$requiredFiles` unconditionally — they should be optional (only loaded when present) since MSA/gMSA/dMSA are add-on features. A domain without these files should still work.


--- 

### 2026-05-29T17:54:00+08:00: LDAP binding — new cmdlets use DC-qualified, track existing bug
**By:** Joel (via Copilot)
**What:** New MSA/gMSA/dMSA cmdlets must use `"LDAP://$DomainController/$targetOUPath"` (DC-qualified binding). The existing bug in `New-TierModelOuAcl.ps1` line 76 will NOT be fixed in this feature branch — tracked separately in a bug tracker file for a future branch.
**Why:** Don't mix bug fixes with new feature work. Fix forward in new code, track existing bugs for a dedicated fix branch.


--- 

### 2026-05-29T17:55:00+08:00: KDS root key check — invoke via PreferredDomainController
**By:** Joel (via Copilot)
**What:** Use `Invoke-Command -ComputerName $PreferredDomainController` to run `Get-KdsRootKey` on the target DC rather than locally. This avoids the RSAT availability issue since DCs always have the KDS cmdlets. Also ensure `dependencies.json` is updated if `Get-KdsRootKey` requires a module not already listed (e.g., `Kds` module or `ActiveDirectory` module dependency).
**Why:** The `-PreferredDomainController` parameter is mandatory. Most deployments run from a server OS or DC. By invoking on the DC, we guarantee cmdlet availability regardless of local RSAT state.


--- 

### 2026-05-29T17:56:00+08:00: KDS check — read-only, never deploy KDS
**By:** Joel (via Copilot)
**What:** The Tier Model will NEVER execute `Add-KdsRootKey`. The prereq check only validates:
1. KDS root key exists (query via PreferredDomainController)
2. KDS root key effective time is older than 10 hours

If either check fails, STOP deployment and inform the user:
- "KDS Root Key not found. A KDS Root Key must be created by a Domain Admin before gMSA/dMSA ACL delegation can be deployed. Run `Add-KdsRootKey` manually, wait 10 hours for replication, then re-run the Tier Model deployment."
- If key exists but effective time < 10 hours: "KDS Root Key found but effective time has not elapsed (10-hour replication window). Wait until [effective time + 10h] before deploying gMSA/dMSA ACLs."

The code is read-only — check and report, never modify.
**Why:** Security boundary. The Tier Model should not make domain-wide changes like deploying KDS keys. That's a manual Domain Admin decision.


--- 




--- 

# Beast: Windows LAPS — Complete Technical Findings
## Cmdlet Surface · Schema-Check · Pre-Reqs · Integration · Lab Verification

**Author:** Beast (Dr. Hank McCoy) — Core Developer, PowerShell/Active Directory
**Date:** 2026-07-13T18:21:02+08:00
**Branch:** feature/windows-laps
**Phase:** Technical Foundation Review — READ ONLY; no implementation, no AD changes
**Research consumed:** `.research/windowslaps/` (all files), `modules/TierModel/public/` conventions, `Deploy-TierModel.ps1`, `Test-TierModelPrerequisites.ps1`, `Get-TierModelConfig.ps1`, `config/tiermodel-gmsa.json`, `.specify/memory/constitution.md`

---

## 0. Hyper-V Lab Verification

**READ-ONLY. `Get-VM` + `Get-VMSnapshot` only. No VMs started, no AD changes.**

### VM inventory

| VM | State |
|---|---|
| `TierLab-DC01` | Off |
| `TierLab-Client` | Off |
| `Src2022-DC` | Off |

### Checkpoints on TierLab-DC01

| Name | Created | Parent | Type |
|---|---|---|---|
| `DC-Promoted-Clean` | 2026-07-13T18:11:49+08:00 | *(root)* | Standard |
| **`WinLapsSchema`** | **2026-07-13T18:19:38+08:00** | **`DC-Promoted-Clean`** | **Standard** |

**`WinLapsSchema` checkpoint CONFIRMED.** It exists and is a direct child of `DC-Promoted-Clean`. This gives the implementation squad a two-point test harness:
- Reset to `DC-Promoted-Clean` → schema absent → schema-check hard-stop behaviour can be validated
- Reset to `WinLapsSchema` → schema present → delegation flow can be validated end to end

### Other VMs

`TierLab-Client` has one checkpoint: `Client-WorkGroup` (2026-05-30). `Src2022-DC` has one checkpoint: `DC-Promoted-Clean` (2026-05-30). Neither has a WinLaps-specific checkpoint. Wolverine / the test squad should use `TierLab-DC01` exclusively for WinLaps testing.

> **Note on gMSA lab history:** Beast's history records that the `DC-Promoted-Clean` checkpoint previously contained a non-effective KDS root key that interfered with gMSA prereq checks. That issue does NOT apply to WinLaps — Windows LAPS has no KDS dependency. The new `WinLapsSchema` checkpoint on `TierLab-DC01` is a separate, dedicated baseline.

---

## 1. Windows LAPS — Deployment & Delegation Mechanics

### 1.1 Schema Attribute Family — Windows LAPS ONLY (ms-LAPS-*)

Six attributes are added to the forest schema by `Update-LapsADSchema`. All six live on **computer objects** in AD. These are the only attributes the implementation touches; do NOT check, touch, or reference legacy LAPS attributes.

| LDAP Display Name | OID | SearchFlags | AttributeSecurityGuid | Notes |
|---|---|---|---|---|
| `msLAPS-PasswordExpirationTime` | `1.2.840.113556.1.6.44.1.1` | `0` | *(not set)* | 64-bit UTC expiry timestamp |
| `msLAPS-Password` | `1.2.840.113556.1.6.44.1.2` | `904` | *(not set)* | Clear-text password JSON (when encryption disabled) |
| `msLAPS-EncryptedPassword` | `1.2.840.113556.1.6.44.1.3` | `904` | `f3531ec6-6330-4f8e-8d39-7a671fbac605` | Encrypted current password |
| `msLAPS-EncryptedPasswordHistory` | `1.2.840.113556.1.6.44.1.4` | `904` | `f3531ec6-6330-4f8e-8d39-7a671fbac605` | Multi-valued encrypted history |
| `msLAPS-EncryptedDSRMPassword` | `1.2.840.113556.1.6.44.1.5` | `904` | `f3531ec6-6330-4f8e-8d39-7a671fbac605` | Encrypted DSRM password — **Tier 0, out of scope** |
| `msLAPS-EncryptedDSRMPasswordHistory` | `1.2.840.113556.1.6.44.1.6` | `904` | `f3531ec6-6330-4f8e-8d39-7a671fbac605` | Encrypted DSRM history — **Tier 0, out of scope** |

The four encrypted attributes share extended right GUID **`f3531ec6-6330-4f8e-8d39-7a671fbac605`** (`ms-LAPS-Encrypted-Password-Attributes`), granting `RIGHT_DS_READ_PROPERTY | RIGHT_DS_WRITE_PROPERTY`.

**`msLAPS-CurrentPasswordVersion` is NOT a detection target.** Microsoft states it is only available with Windows Server 2025 forest schema and is NOT installed by `Update-LapsADSchema`. Do not require it for baseline schema readiness.

### 1.2 Explicit Windows LAPS vs. Legacy LAPS Distinction

| | Windows LAPS (implement this) | Legacy Microsoft LAPS (excluded — ADR-0001) |
|---|---|---|
| Schema family | `msLAPS-*` (6 attributes above) | `ms-Mcs-AdmPwd`, `ms-Mcs-AdmPwdExpirationTime` |
| AD encryption | Yes — AES-256 CNG DPAPI, DFL 2016+ required | No — clear-text only |
| DSRM backup | Yes (encrypted, DFL 2016+ required) | No |
| Product status | In-box, serviced with Windows | Deprecated; blocked on newer OS |
| PowerShell module | `LAPS` (in-box) | `AdmPwd.PS` (legacy MSI) |

**Hard rule:** Never check for `ms-Mcs-AdmPwd` or `ms-Mcs-AdmPwdExpirationTime` as proof of Windows LAPS.

### 1.3 Three DACL Operations per Target OU

| Op | Cmdlet | Principal | What it does |
|---|---|---|---|
| **A — SELF-store** | `Set-LapsADComputerSelfPermission -Identity <OU>` | SELF (inherited by computer objects) | Allows each managed computer to write its own LAPS password state to its own AD object |
| **B — Read (retrieve)** | `Set-LapsADReadPasswordPermission -Identity <OU> -AllowedPrincipals <readGroup>` | Per-tier read group | Grants permission to query stored password values |
| **C — Reset (force expiry)** | `Set-LapsADResetPasswordPermission -Identity <OU> -AllowedPrincipals <resetGroup>` | Per-tier reset group | Grants write of `msLAPS-PasswordExpirationTime`, triggering rotation on next policy cycle |

**Separation of duties is mandatory by default.** Op B and Op C use separate groups. A combined group requires explicit ADR-recorded risk acceptance (OQ-RT-04 design intent, Joel's per-Tier delegation model).

**Op D — Auditing** (`Set-LapsADAuditing`) is NOT in scope for this deployment phase. The executor must emit a visible plan notice that auditing configuration is required and is a follow-up step. It must NOT silently skip auditing.

### 1.4 Two-Layer Encryption Security Model

Windows LAPS enforces two independent authorization layers when encryption is enabled (mandatory by default per Joel OQ-RT-03):

1. **Directory read permission** — `Set-LapsADReadPasswordPermission` grants the read group the right to retrieve the encrypted blob from AD. This alone does NOT enable decryption.
2. **Cryptographic decrypt authorization** — controlled by Group Policy `ADPasswordEncryptionPrincipal`. Default: Domain Admins only. Non-DA principals can be authorized, but only ONE encryption principal is supported per password; use a wrapper group if multiple principals need decrypt.

The implementation MUST NOT conflate read permission with decrypt authorization. These are separate controls with separate groups (OQ-RT-04).

### 1.5 DC/DSRM Scope — Hard Exclude by Default (Joel OQ-RT-01)

`OU=Domain Controllers` and any OU containing DC computer objects **must be detected before any DACL mutation and cause an immediate hard fail.**

**Rationale:** Microsoft documents `Get-LapsADPassword` as retrieving credentials from "AD computer **or domain controller** objects." A generic OU sweep can accidentally apply LAPS read/reset delegation to a Tier 0 DC/DSRM credential path. This is the biggest implementation foot-gun in the research package.

**DC detection — do NOT use OU name alone.** Enumerate all computer objects in the target OU subtree. Reject if any object matches:
- `primaryGroupID = 516` (Domain Controllers group)
- `userAccountControl` bitwise AND `0x00002000` (SERVER_TRUST_ACCOUNT)
- `serverReferenceBL` attribute present (NTDS Settings back-link — DC objects have this)

Error code: `TargetOUContainsDCObjects`. No LAPS cmdlets run. No partial application.

**DC/DSRM support:** future `–IncludeDomainControllers` mode with its own threat model, DACL contract, approval workflow, and Tier 0 governance. Not a parameter flag on `-IncludeWinLaps`.

---

## 2. Schema-Present Detection — Exact Method

### 2.1 Two-Tier Check

Both checks run in the planner before any actions are emitted. Both use read-only `Get-ADObject` calls. No writes to AD.

#### Tier 1 — Quick Attribute-Presence Check

Query the schema naming context (from `Get-ADRootDSE`) for all six required `attributeSchema` objects by `lDAPDisplayName`. This is fast and produces an intelligible error when the schema is simply absent. It cannot detect a partially botched extension.

```powershell
$schemaNamingContext = (Get-ADRootDSE -Server $DomainController -ErrorAction Stop).schemaNamingContext
$requiredAttributes = @(
    'msLAPS-PasswordExpirationTime',
    'msLAPS-Password',
    'msLAPS-EncryptedPassword',
    'msLAPS-EncryptedPasswordHistory',
    'msLAPS-EncryptedDSRMPassword',
    'msLAPS-EncryptedDSRMPasswordHistory'
)
$found = foreach ($attr in $requiredAttributes) {
    Get-ADObject -SearchBase $schemaNamingContext `
        -LDAPFilter "(&(objectClass=attributeSchema)(lDAPDisplayName=$attr))" `
        -Properties lDAPDisplayName -Server $DomainController -ErrorAction Stop |
        Select-Object -ExpandProperty lDAPDisplayName
}
$missing = $requiredAttributes | Where-Object { $_ -notin $found }
```

Label result `WindowsLapsAttributePresence = ($missing.Count -eq 0)`. If missing, emit `WINLAPS_SCHEMA_MISSING` immediately (see §2.3).

#### Tier 2 — Hardened Schema-Readiness Check (REQUIRED for production gate)

Additionally verifies:
1. Each attribute's `attributeID` matches the expected OID (`1.2.840.113556.1.6.44.1.1` through `1.2.840.113556.1.6.44.1.6`)
2. Each encrypted attribute's `attributeSecurityGUID` matches `f3531ec6-6330-4f8e-8d39-7a671fbac605`
3. The `computer` classSchema `mayContain` list includes all six LDAP display names

```powershell
$computerClass = Get-ADObject -SearchBase $schemaNamingContext `
    -LDAPFilter '(&(objectClass=classSchema)(lDAPDisplayName=computer))' `
    -Properties mayContain -Server $DomainController -ErrorAction Stop

$mayContainMissing = $requiredAttributes | Where-Object { $_ -notin @($computerClass.mayContain) }
```

Label result `WindowsLapsSchemaReady = ($failures.Count -eq 0 -and $mayContainMissing.Count -eq 0)`. The implementation must gate on `WindowsLapsSchemaReady`, not `WindowsLapsAttributePresence`.

**OQ-RT-05 (Needs Research — still open):** Schema replication convergence across all DCs the tool targets is not checked by either tier. For production, the implementation squad should run the hardened check against the specific `$DomainController` parameter value. The handoff document recommends also checking against all writable DCs the deployment will use, or requiring evidence of convergence. This remains an open research item.

### 2.2 LAPS PowerShell Module Check (alongside schema check)

Run immediately after the schema check, also in the planner, before emitting any actions:

```powershell
$lapsModule = Get-Module -ListAvailable -Name LAPS | Sort-Object Version -Descending | Select-Object -First 1
if (-not $lapsModule) {
    # Hard stop: WINLAPS_MODULE_MISSING
}
# Bind to the specific module path — do not rely on Get-Command -Module LAPS
$loaded = Import-Module -Name $lapsModule.Path -Force -PassThru -ErrorAction Stop
$requiredCmdlets = @(
    'Set-LapsADComputerSelfPermission',
    'Set-LapsADReadPasswordPermission',
    'Set-LapsADResetPasswordPermission',
    'Find-LapsADExtendedRights'
)
$missingCmdlets = $requiredCmdlets | Where-Object { $_ -notin @($loaded.ExportedCommands.Keys) }
if ($missingCmdlets.Count -gt 0) {
    # Hard stop: WINLAPS_MODULE_CMDLETS_MISSING; log missing cmdlet names
}
```

Log `ModuleName`, `ModuleVersion`, `ModulePath` for diagnostics. Do NOT hard-code a minimum version number — gate on cmdlet inventory. Management host must be Windows Server 2019/2022 (April 2023 update or later) or Server 2025+. Windows Server 2016 does NOT ship the in-box `LAPS` module.

### 2.3 Hard-Stop Behavior — WINLAPS_SCHEMA_MISSING (Joel OQ-RT-02 — locked)

When the schema check fails (either tier):

1. **Emit stable error code `WINLAPS_SCHEMA_MISSING`** — machine-readable, suitable for SIEM/log parsing
2. **Log via `Write-TierModelLog -Level Error`**: forest name, schema NC DN, which attributes/checks failed, timestamp, CorrelationId
3. **Surface a quiet, non-prescriptive console alert** — see approved wording proposal below
4. **Return immediately** with empty Actions array — no LAPS delegation actions emitted, no AD changes

**Absolute prohibitions (Joel's exact words):**
- Do NOT print `Update-LapsADSchema` in any console output or user-facing message
- Do NOT provide numbered remediation steps
- Do NOT implement any `-AutoUpdateSchema` or similar auto-mutation parameter
- Do NOT proceed with partial configuration

**Proposed console message (flagged for Professor X approval):**
> `Windows LAPS AD schema readiness check failed (WINLAPS_SCHEMA_MISSING). Schema extension is a forest-wide, high-privilege change. Engage your AD/schema change-control process before retrying.`

This is intentionally brief. It does not name any cmdlet, does not suggest blog steps, and directs the operator to their own controlled process. **Professor X must review and approve the final wording.**

Residual risk acknowledged by research team: an operator who receives only this message may improvise an unofficial schema extension (LDIF, ADSI, blog posts). Mitigations that do NOT violate Joel's decision:
- Emit `WINLAPS_SCHEMA_MISSING` as a structured log field (SIEM can alert on it)
- Log the forest/domain name and schema NC in the log, not the console
- Add a statement: "Do not use LDIF, ADSI, or unofficial scripts" — this warns against improvisation without naming the official cmdlet

---

## 3. OU/Group Pre-Req Dependencies

### 3.1 Required Objects Before Any LAPS Delegation

**Per configured delegation entry:**

| Object | Why required | Absence error code |
|---|---|---|
| Target OU (computer objects OU) | LAPS cmdlets require a valid OU DN for `-Identity` | `TargetOUNotFound` |
| Read group | `Set-LapsADReadPasswordPermission -AllowedPrincipals` | `SecurityPrincipalNotFound` |
| Reset group | `Set-LapsADResetPasswordPermission -AllowedPrincipals` | `SecurityPrincipalNotFound` |

**Additional forest/domain pre-reqs:**

| Check | Failure error code |
|---|---|
| Windows LAPS schema — hardened | `WINLAPS_SCHEMA_MISSING` |
| LAPS module + required cmdlets present | `WINLAPS_MODULE_MISSING` / `WINLAPS_MODULE_CMDLETS_MISSING` |
| DFL ≥ Windows2016Domain (for encryption, mandatory by default) | `WINLAPS_DFL_INSUFFICIENT` |
| No DC objects in target OU subtree | `TargetOUContainsDCObjects` |

### 3.2 Green-Before-Changes — Exact Ordering in the Planner

The planner (`Get-TierModelWinLapsAcl`) collects ALL errors before returning. No partial application. If `$planErrors.Count -gt 0` after all checks, return the error list with an empty `Actions = @()`.

**Check sequence:**
1. Schema hardened check — hard stop if fail (emit `WINLAPS_SCHEMA_MISSING`, return immediately; do not continue to module check)
2. LAPS module + cmdlet check — hard stop if fail
3. DFL + encryption check — fail if below DFL 2016 with no risk-acceptance mode
4. Load `$Config.winLapsDelegations` — if null or empty, return empty plan with a warning (not an error — winlaps.json may simply not be present yet)
5. Resolve `{{DOMAIN_DN}}` placeholders via `Resolve-TierModelPlaceholder` for all delegation entries
6. For each unique target OU: `Get-ADOrganizationalUnit -Identity <dn>` — collect `TargetOUNotFound` errors
7. For each unique target OU: enumerate computer objects, check DC semantics — collect `TargetOUContainsDCObjects` errors
8. For each unique read group + reset group: `Get-ADGroup -Identity <name>` — collect `SecurityPrincipalNotFound` errors
9. If any errors from steps 4–8: return plan with errors, empty Actions (green-before-changes)
10. For each delegation: idempotency check (see §4.6)
11. Emit `CreateAcl` actions for missing permissions

**Error messages matching gMSA convention:**
- `"Target OU not found: '<DN>'. Use -OuOnly to deploy the OUs, or use -FullDeployment -IncludeWinLaps."`
- `"Delegation group '<name>' not found. Use -GroupOnly to deploy the Groups, or use -FullDeployment -IncludeWinLaps."`

### 3.3 Standalone Mode Failure Behaviour

Running `-IncludeWinLaps` without `-FullDeployment` on a fresh environment (no OUs, no groups) must produce a clear, actionable error list:

```
❌ TargetOUNotFound: 'OU=Tier 0 Computers,...'
   Use -OuOnly to deploy the OUs, or use -FullDeployment -IncludeWinLaps.
❌ TargetOUNotFound: 'OU=Tier 1 Computers,...'
   Use -OuOnly to deploy the OUs, or use -FullDeployment -IncludeWinLaps.
❌ SecurityPrincipalNotFound: 'Tier0LapsReaders' not found.
   Use -GroupOnly to deploy the Groups, or use -FullDeployment -IncludeWinLaps.
❌ SecurityPrincipalNotFound: 'Tier0LapsReset' not found.
   ...
```

No LAPS cmdlets are ever called. Zero AD changes. Same behaviour as `Get-TierModelGmsaAcl` when OUs/groups are absent.

---

## 4. Cmdlet Surface Proposal — Full Detail

### 4.1 Naming Convention

The codebase establishes a strict three-cmdlet pattern per optional ACL feature:

| Role | gMSA example | WinLaps equivalent |
|---|---|---|
| Standalone planner | `Get-TierModelGmsaAcl` | **`Get-TierModelWinLapsAcl`** |
| Full-Deployment planner | `Get-TierModelGmsaAclFd` | **`Get-TierModelWinLapsAclFd`** |
| Executor | `New-TierModelGmsaAcl` | **`New-TierModelWinLapsAcl`** |

All three are NEW files under `modules/TierModel/public/`. No existing file is touched.

### 4.2 `Get-TierModelWinLapsAcl` — Standalone Planner

```powershell
function Get-TierModelWinLapsAcl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$Config,
        [Parameter(Mandatory)] [string]$DomainController,
        [switch]$IncludeDetails
    )
```

Full pre-req validation (§3.2 ordering). Returns plan object:

```powershell
[PSCustomObject]@{
    Actions       = $actions          # array of action objects
    Errors        = $planErrors       # array of @{Timestamp;Category;Code;Message;Context}
    Summary       = @{
        TotalActions   = $actions.Count
        CreateActions  = $createActions
        RiskAssessment = @{ LowRisk = $lowRiskActions; MediumRisk = 0; HighRisk = 0 }
    }
    Analysis      = @{
        ConfiguredDelegations = $delegations.Count
        ExistingPermissions   = $existingCount
        ValidationErrors      = $planErrors.Count
    }
    Warnings      = $warnings
    DurationMs    = $durationMs
    CorrelationId = $CorrelationId
}
```

### 4.3 `Get-TierModelWinLapsAclFd` — Full-Deployment Planner

```powershell
function Get-TierModelWinLapsAclFd {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$Config,
        [Parameter(Mandatory)] [string]$DomainController,
        [switch]$IncludeDetails,
        [switch]$Silent
    )
```

Differences from standalone planner:
- Inherits `$script:CorrelationId` if set (shared with the full-deployment run's CorrelationId)
- Schema and LAPS module checks: still hard gates — cannot skip
- OU + group checks: lighter — missing objects are flagged in the action's `Validation` property (`TargetOUExists = $false`) but do NOT abort the plan. OUs/groups are expected to exist from earlier FullDeployment phases.
- `-Silent` suppresses `Write-Host` lines (used during apply phase to avoid duplicate output)
- Summary includes `ExistingCount` — used for "✅ already up to date" display

### 4.4 `New-TierModelWinLapsAcl` — Executor

```powershell
function New-TierModelWinLapsAcl {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [object]$Plan,
        [Parameter(Mandatory)] [string]$DomainController,
        [Parameter(Mandatory)] [object]$Config
    )
```

**Critical structural difference from gMSA/MSA/dMSA executors:** Does NOT use `System.DirectoryServices.DirectoryEntry` or `System.DirectoryServices.ActiveDirectoryAccessRule`. Instead, calls the `LAPS` module cmdlets:

```powershell
switch ($action.Data.lapsOperation) {
    'SelfPermission' {
        if ($PSCmdlet.ShouldProcess("OU: $targetOUPath", "Apply Windows LAPS SelfPermission")) {
            Set-LapsADComputerSelfPermission -Identity $targetOUPath
        }
    }
    'ReadPermission' {
        if ($PSCmdlet.ShouldProcess("OU: $targetOUPath", "Apply Windows LAPS ReadPermission for $group")) {
            Set-LapsADReadPasswordPermission -Identity $targetOUPath -AllowedPrincipals $group
        }
    }
    'ResetPermission' {
        if ($PSCmdlet.ShouldProcess("OU: $targetOUPath", "Apply Windows LAPS ResetPermission for $group")) {
            Set-LapsADResetPasswordPermission -Identity $targetOUPath -AllowedPrincipals $group
        }
    }
}
```

**WhatIf:** `$PSCmdlet.ShouldProcess()` returns `$false` — LAPS cmdlet call is skipped, action goes to `$skipped` with `Reason = 'WhatIf'`. Console: `[WhatIf] Would apply Windows LAPS ReadPermission: Tier1LapsReaders on OU=Tier1 Computers,...`

**Logging:** `Write-TierModelLog -Level Info` at start, each applied action, and completion. Error actions: `Write-TierModelLog -Level Error`. All calls include `CorrelationId`.

**Return shape (mirrors gMSA executor):**
```powershell
[PSCustomObject]@{
    Applied       = $applied          # array of applied action summaries
    Executed      = $applied.Count
    Failed        = $errors.Count
    Skipped       = $skipped
    Errors        = $errors
    DurationMs    = $durationMs
    Converged     = $converged
    CorrelationId = $CorrelationId
}
```

### 4.5 Action Type and Shape — Three Actions per Delegation Entry

Each `winLapsDelegations` config entry generates **three** `CreateAcl` action objects. The action type `CreateAcl` is used for compatibility with the existing `Add-IncludeAclPhaseToDeploymentPlan` and `Write-IncludeAclPlanActions` helper functions in `Deploy-TierModel.ps1` — both check `$_.Action -eq 'CreateAcl'` for totals counting and plan display. `ResourceType = 'LapsPermission'` distinguishes these from raw ACE delegations.

```powershell
# Action A — SelfPermission
[PSCustomObject]@{
    Action        = 'CreateAcl'
    ResourceType  = 'LapsPermission'
    Name          = "LAPS SelfPermission on $ouShortName"
    Path          = $targetOUPath
    Data          = [PSCustomObject]@{
        lapsOperation     = 'SelfPermission'
        identityreference = 'SELF'
        targetOUPath      = $targetOUPath
        tier              = $delegation.tier
    }
    Dependencies  = @()
    RiskLevel     = 'Low'
    Validation    = @{ TargetOUExists = $true; PrincipalResolvable = $true }
}

# Action B — ReadPermission
[PSCustomObject]@{
    Action        = 'CreateAcl'
    ResourceType  = 'LapsPermission'
    Name          = "LAPS ReadPermission: $($delegation.readPasswordGroup) on $ouShortName"
    Path          = $targetOUPath
    Data          = [PSCustomObject]@{
        lapsOperation     = 'ReadPermission'
        identityreference = $delegation.readPasswordGroup
        targetOUPath      = $targetOUPath
        tier              = $delegation.tier
    }
    Dependencies  = @()
    RiskLevel     = 'Low'
    Validation    = @{ TargetOUExists = $true; PrincipalResolvable = $true }
}

# Action C — ResetPermission
[PSCustomObject]@{
    Action        = 'CreateAcl'
    ResourceType  = 'LapsPermission'
    Name          = "LAPS ResetPermission: $($delegation.resetPasswordGroup) on $ouShortName"
    Path          = $targetOUPath
    Data          = [PSCustomObject]@{
        lapsOperation     = 'ResetPermission'
        identityreference = $delegation.resetPasswordGroup
        targetOUPath      = $targetOUPath
        tier              = $delegation.tier
    }
    Dependencies  = @()
    RiskLevel     = 'Low'
    Validation    = @{ TargetOUExists = $true; PrincipalResolvable = $true }
}
```

**Totals arithmetic:** N configured delegation entries × 3 actions = N × 3 `CreateAcl` actions contributed to `$deploymentPlan.CreateCount` and `$deploymentPlan.TotalActions`. For a 3-tier config: +9 to total. **Point 8 — "totals must go UP" — satisfied.**

### 4.6 Idempotency Design — v1 Contract and Known Gap

The constitution (Section III) mandates "Only create/update when drift detected; never assume prior state — always query & compare."

**Challenge:** Microsoft Learn does NOT publish the exact ACE/SDDL emitted by any of the three LAPS permission cmdlets. This is the central unresolved implementation risk (OQ-RT-06 in the research handoff).

**Per-operation approach:**

| Operation | Idempotency method | Confidence |
|---|---|---|
| ReadPermission | `Find-LapsADExtendedRights -Identity <OU>` returns principals with LAPS read rights on the OU. Check if read group is already present. | **High** — this cmdlet exists for exactly this purpose |
| SelfPermission | `Get-Acl -Path "AD:\$targetOUPath"` + inspect for SELF write ACE on LAPS attributes. Exact ACE shape unknown without lab. | **Low until lab-validated** |
| ResetPermission | `Get-Acl` + inspect for write ACE on `msLAPS-PasswordExpirationTime`. Exact ACE shape unknown without lab. | **Low until lab-validated** |

**v1 guardrail (research handoff OQ-RT-06):** "v1 uses Microsoft `Set-LapsAD*Permission` cmdlets only. If idempotence, removal, or manual ACL comparison is required, lab-captured before/after DACL fixtures must be produced and cited before that code is written."

**Practical v1 stance:**
- Use `Find-LapsADExtendedRights` for ReadPermission idempotency — mark as `Existing` if already present
- For SelfPermission and ResetPermission: attempt `Get-Acl` inspection with best-effort matching. If uncertain, plan as `NeedsLabValidation = $true` in the action and flag it yellow in plan output
- Document this explicitly: "LAPS SELF/Reset idempotency requires lab-captured ACE fixtures from `WinLapsSchema` checkpoint. Using `TierLab-DC01` → `WinLapsSchema` restore, apply each cmdlet, export ACL before/after, record exact ACE properties."

The `WinLapsSchema` checkpoint now available on `TierLab-DC01` provides exactly the right starting state for this lab work.

### 4.7 Config Shape — `config/tiermodel-winlaps.json`

Different from `tiermodel-gmsa.json` because LAPS uses named cmdlet operations, not raw ACE object arrays.

```json
{
  "version": "1.0.0",
  "comment": "Windows LAPS ACL delegations. Optional add-on — loaded only when -IncludeWinLaps is specified.",
  "winLapsDelegations": [
    {
      "targetOUPath": "OU=Tier 0 Computers,OU=Tier 0,OU=Tier Model Administration,{{DOMAIN_DN}}",
      "tier": 0,
      "selfPermission": true,
      "readPasswordGroup": "Tier0LapsReaders",
      "resetPasswordGroup": "Tier0LapsReset",
      "comment": "Windows LAPS delegation for Tier 0 managed computer OUs"
    },
    {
      "targetOUPath": "OU=Tier 1 Computers,OU=Tier 1,OU=Tier Model Administration,{{DOMAIN_DN}}",
      "tier": 1,
      "selfPermission": true,
      "readPasswordGroup": "Tier1LapsReaders",
      "resetPasswordGroup": "Tier1LapsReset",
      "comment": "Windows LAPS delegation for Tier 1 managed computer OUs"
    }
  ]
}
```

**Group names and OU paths above are structural PLACEHOLDERS.** Joel supplies the actual values (OQ-001 deferred to implementation squad). The JSON schema establishes the shape, not the values.

**Config property in merged config object:** `$config.winLapsDelegations` (array; null if file absent).

---

## 5. Integration Points in Deploy-TierModel.ps1

`Deploy-TierModel.ps1` is a script (not a module cmdlet file) and is modifiable.

### 5.1 New Switch — `[switch]$IncludeWinLaps`

Add alongside `$IncludeMsa`, `$IncludeGmsa`, `$IncludeDmsa` in the `param()` block.

Update include-parameter validation array:
```powershell
$includeParameters = @($IncludeMsa, $IncludeGmsa, $IncludeDmsa, $IncludeWinLaps)
$activeIncludeCount = @($includeParameters | Where-Object { $_ }).Count
```

Existing validation logic ("must specify one scope or one or more `-Include*`" and "cannot combine with `–*Only`") requires no changes beyond this array update.

### 5.2 Phase 10 — FullDeployment Planning Block

Insert after the existing Phase 9 (`$IncludeDmsa`) block, inside the `if ($activeIncludeCount -gt 0)` section:

```powershell
if ($IncludeWinLaps) {
    if (-not $ConfirmApply) {
        Write-Host "Phase 10: Windows LAPS ACL Delegations" -ForegroundColor Cyan
    }
    $winLapsFdPlanParams = @{ Config = $config; DomainController = $PreferredDc; IncludeDetails = $true }
    if ($ConfirmApply) { $winLapsFdPlanParams['Silent'] = $true }
    $winLapsFdPlan = Get-TierModelWinLapsAclFd @winLapsFdPlanParams

    if ($winLapsFdPlan.Errors -and $winLapsFdPlan.Errors.Count -gt 0) {
        if (-not $ConfirmApply) {
            Write-Host "  ❌ Windows LAPS planning errors:" -ForegroundColor Red
            $winLapsFdPlan.Errors | ForEach-Object { Write-Host "    - $($_.Message)" -ForegroundColor Red }
        }
    } else {
        Add-IncludeAclPhaseToDeploymentPlan -DeploymentPlan $deploymentPlan `
            -PhaseNumber 10 -PhaseName 'Windows LAPS ACL Delegations' -Plan $winLapsFdPlan
        if (-not $ConfirmApply) {
            if ($winLapsFdPlan.Summary.TotalActions -gt 0) {
                Write-Host "  Actions planned: $($winLapsFdPlan.Summary.TotalActions)" -ForegroundColor Yellow
                Write-IncludeAclPlanActions -Actions $winLapsFdPlan.Actions
            } else {
                Write-Host "  ✅ Windows LAPS ACL delegations already up to date" -ForegroundColor Green
            }
        }
    }
}
```

### 5.3 Phase 10 — FullDeployment Execution Block

Inside the `if ($activeIncludeCount -gt 0 -and -not $standardDeployHadErrors)` apply section:

```powershell
if ($IncludeWinLaps) {
    Write-Host "  Deploying Windows LAPS ACL delegations..." -ForegroundColor Cyan
    $winLapsPlan = if (Get-Variable winLapsFdPlan -ErrorAction SilentlyContinue) {
        $winLapsFdPlan
    } else {
        Get-TierModelWinLapsAclFd -Config $config -DomainController $PreferredDc -IncludeDetails -Silent
    }
    if ($winLapsPlan.Errors -and $winLapsPlan.Errors.Count -gt 0) {
        Write-Host "  ❌ Windows LAPS planning errors:" -ForegroundColor Red
        $winLapsPlan.Errors | ForEach-Object { Write-Host "    - $($_.Message)" -ForegroundColor Red }
    } elseif (@($winLapsPlan.Actions).Count -gt 0) {
        $winLapsExecResult = New-TierModelWinLapsAcl -Plan $winLapsPlan -DomainController $PreferredDc -Config $config
    } else {
        Write-Host "  ✅ Windows LAPS ACL delegations already up to date" -ForegroundColor Green
    }
}
```

Add `$winLapsExecResult` to the `$allResults` array for the consolidated totals display.

### 5.4 Prerequisite Check Update

The existing `$msaPrereqs` splat in the optional-features execution section must include WinLaps:
```powershell
if ($IncludeWinLaps) { $prereqSplat['IncludeWinLaps'] = $true }
```

This requires `Test-TierModelPrerequisites.ps1` to accept `[switch]$IncludeWinLaps` — see §6 exception decision.

### 5.5 `Write-IncludeAclPlanActions` Display

The existing function iterates `$_.Action -eq 'CreateAcl'` and prints `"Create ACL: $($_.Data.identityreference) on $ouName"`. For the SELF operation, `identityreference = 'SELF'` and the display reads `"Create ACL: SELF on <OU>"` — which is correct and clear. No change needed for minimum viable display. If a richer label is desired (e.g. `"Apply LAPS SelfPermission on OU=..."` using `$_.Name`), the function can be extended in `Deploy-TierModel.ps1` to check `$_.ResourceType -eq 'LapsPermission'` first.

---

## 6. Config Loading — Constraint Analysis and Options

### The Problem

`Get-TierModelConfig.ps1` under `modules/TierModel/public/` is off-limits per the active "no-modify existing cmdlets" directive. But to surface `$config.winLapsDelegations` through the standard path, `'tiermodel-winlaps.json'` must be added to its `$optionalFiles` list (same pattern used when `tiermodel-msa.json`, `tiermodel-gmsa.json`, and `tiermodel-dmsa.json` were added during gMSA feature work).

### Option A — Narrow exception to Get-TierModelConfig.ps1 (RECOMMENDED)

Add one entry to `$optionalFiles` array and one property to the `$config` object:
```powershell
# In $optionalFiles:
'tiermodel-winlaps.json'

# In config object construction:
winLapsDelegations = if ($optionalSegments['tiermodel-winlaps.json'] -and
    $optionalSegments['tiermodel-winlaps.json'].PSObject.Properties['winLapsDelegations']) {
    $optionalSegments['tiermodel-winlaps.json'].winLapsDelegations
} else { $null }
```

This is purely additive. Existing behavior is unchanged. It matches the exact precedent from gMSA/dMSA/MSA feature addition. The "off-limits" rule was enforced during Phase 16 testing; WinLaps is a new feature.

### Option B — Self-loading in WinLaps planners (no exception needed)

`Get-TierModelWinLapsAcl` and `Get-TierModelWinLapsAclFd` load `tiermodel-winlaps.json` internally if `$Config.winLapsDelegations` is null. Uses `$script:ConfigPath` (same module-level path).

**Downside:** Creates a secondary config-loading code path outside the established convention. Breaks the invariant that `Get-TierModelConfig` is the single source of truth for all config. Not recommended.

### Decision required (Professor X / Cyclops)

**Recommend Option A with a narrow scope exception.** The modification is two lines, purely additive, follows exact precedent, and does not affect any existing test or behavior.

---

## 7. Test-TierModelPrerequisites.ps1 — Same Constraint

The same off-limits constraint applies. Adding LAPS schema + module prereq checks requires `[switch]$IncludeWinLaps`.

**Option A (exception):** Add `[switch]$IncludeWinLaps` block to `Test-TierModelPrerequisites.ps1` with LAPS schema hardened check + module check. Mirrors the `$IncludeMsa / $IncludeGmsa / $IncludeDmsa` blocks exactly.

**Option B (no exception):** Embed all LAPS prereq checks in `Get-TierModelWinLapsAcl` and `Get-TierModelWinLapsAclFd` as part of their planning logic. The planner is then fully self-validating. The `$prereqSplat` in `Deploy-TierModel.ps1` simply does not pass `-IncludeWinLaps` to `Test-TierModelPrerequisites`, and WinLaps prereqs are handled inside the planner.

**Option B is viable** and arguably cleaner architecturally — WinLaps has unique prereq checks (schema, module) that are unlike the MSA/gMSA/dMSA schema-version checks. Self-containment means the planner is fully self-sufficient.

**Decision required (Professor X / Cyclops).**

---

## 8. Open Questions Routed to Decision Owners

### For Professor X / Cyclops — exception decisions

| # | Decision | Recommendation |
|---|---|---|
| **P-1** | `Get-TierModelConfig.ps1` narrow exception — Option A | **Approve.** Two additive lines, exact gMSA precedent. |
| **P-2** | `Test-TierModelPrerequisites.ps1` narrow exception — or Option B self-contained | **Option B preferred.** WinLaps prereqs differ in kind from MSA/gMSA/dMSA; self-containment is clean. |
| **P-3** | Schema error message wording for `WINLAPS_SCHEMA_MISSING` | Approve proposed wording in §2.3, or revise before spec authoring. |

### For Joel Platek — values and design

| # | Decision | Notes |
|---|---|---|
| **J-1** | Concrete OU paths per tier for `tiermodel-winlaps.json` | OQ-001 deferred. Cannot finalize config without these. |
| **J-2** | Group names per tier (read group, reset group) | OQ-001 deferred. One read group + one reset group per tier recommended as minimum. |
| **J-3** | OQ-RT-04: Is a separate decrypt-principal group required at deployment time? | Separate by default. If combined read+decrypt is acceptable, needs ADR. |
| **J-4** | Auditing notice in v1 plan output | Tool will NOT configure auditing in this phase. What visible notice is required? Suggested: a yellow `Write-Host` line in the plan output: "⚠️ Windows LAPS auditing is not configured by this tool. Configure `Set-LapsADAuditing` separately." |

### For implementation squad (Beast) — lab work required before production

| # | Work item | Notes |
|---|---|---|
| **B-1** | Lab-capture idempotency ACE fixtures | Restore `TierLab-DC01` to `WinLapsSchema` checkpoint, apply each of the three LAPS cmdlets to a test OU, export `Get-Acl "AD:\<OU>"` before and after. Record exact `ObjectType`, `InheritanceType`, `ActiveDirectoryRights`, `IdentityReference`. Required before writing SelfPermission and ResetPermission idempotency logic. |
| **B-2** | DC object detection lab validation | Verify `primaryGroupID=516`, `userAccountControl` flags, and `serverReferenceBL` correctly identify DCs in renamed OU scenarios on `TierLab-DC01`. |
| **B-3** | Schema replication convergence approach | OQ-RT-05: decide whether to check against all writable DCs or only `$DomainController`. Document assumption in code. |

---

## 9. Files Required — Complete List

### New files (no existing file impact)

| File | Created by |
|---|---|
| `modules/TierModel/public/Get-TierModelWinLapsAcl.ps1` | Beast |
| `modules/TierModel/public/Get-TierModelWinLapsAclFd.ps1` | Beast |
| `modules/TierModel/public/New-TierModelWinLapsAcl.ps1` | Beast |
| `config/tiermodel-winlaps.json` | Beast (shape); Joel (values) |
| `tests/Unit.WinLapsAclOperations.Tests.ps1` | Wolverine |

### Existing files requiring modification

| File | Change | Exception needed? |
|---|---|---|
| `Deploy-TierModel.ps1` | `[switch]$IncludeWinLaps`, Phase 10 block, execution block, prereq splat | **No** — script, not module cmdlet |
| `modules/TierModel/public/Get-TierModelConfig.ps1` | Add `tiermodel-winlaps.json` optional file + `winLapsDelegations` property | **Yes** — Professor X/Cyclops approval |
| `modules/TierModel/public/Test-TierModelPrerequisites.ps1` | Add `[switch]$IncludeWinLaps` + LAPS checks | **Yes** (Option A) or **skip entirely** (Option B) |

---

## 10. Key Reference Facts

| Fact | Value |
|---|---|
| Windows LAPS schema update cmdlet | `Update-LapsADSchema` — DO NOT invoke from this tool (Joel OQ-RT-02) |
| LAPS PowerShell module name | `LAPS` (in-box Windows feature) |
| Encrypted attributes extended right GUID | `f3531ec6-6330-4f8e-8d39-7a671fbac605` |
| Required attributes: count | 6 (`msLAPS-PasswordExpirationTime` through `msLAPS-EncryptedDSRMPasswordHistory`) |
| Do NOT check | `msLAPS-CurrentPasswordVersion` (Server 2025 forest schema only) |
| Do NOT check | `ms-Mcs-AdmPwd` / `ms-Mcs-AdmPwdExpirationTime` (Legacy LAPS) |
| Min DFL for encryption (mandatory default) | `Windows2016Domain` |
| Min management host OS | Windows Server 2019/2022 (April 2023 update) or Server 2025+. NOT Server 2016. |
| Actions per delegation entry | 3: SelfPermission + ReadPermission + ResetPermission |
| Action type for totals compatibility | `CreateAcl` |
| Action ResourceType | `LapsPermission` |
| Phase number in FullDeployment | Phase 10 (after MSA=7, gMSA=8, dMSA=9) |
| Config file | `config/tiermodel-winlaps.json` |
| Config property | `$config.winLapsDelegations` |
| Error code: schema missing | `WINLAPS_SCHEMA_MISSING` |
| Error code: module missing | `WINLAPS_MODULE_MISSING` |
| Error code: OU missing | `TargetOUNotFound` |
| Error code: group missing | `SecurityPrincipalNotFound` |
| Error code: DC objects in OU | `TargetOUContainsDCObjects` |
| Lab checkpoint: schema absent | `TierLab-DC01` → `DC-Promoted-Clean` |
| Lab checkpoint: schema present | `TierLab-DC01` → `WinLapsSchema` (created 2026-07-13T18:19:38+08:00) |
| Auditing | NOT in scope for this phase; visible plan notice required |
| DC/DSRM support | Hard-excluded from `-IncludeWinLaps`; future `-IncludeDomainControllers` only |


--- 

# Decision Note: Windows LAPS Architecture & Cmdlet Surface

**Author:** Cyclops — Architect & Reviewer  
**Date:** 2026-07-13  
**Branch:** `feature/windows-laps`  
**Status:** ACTIVE — backbone for plan.md authoring in Wave 2  
**Governing Documents:** `.specify/memory/constitution.md` v1.3.0, ADR-0001  
**Research Package:** `.research/windowslaps/`

---

## 1. Pre-Requisite Gating Architecture

### Design Principle

All-green-before-any-change. The deploy validates ALL pre-requisites UP FRONT and refuses to make ANY change (no OU, group, or ACL writes) unless every check passes. This extends the existing `Test-TierModelPrerequisites` pattern (Deploy-TierModel.ps1 lines 225–250).

### Gating Sequence (ordered, fail-fast)

When `-IncludeWinLaps` is active (standalone or within `-FullDeployment`):

```
GATE 1: Windows LAPS Schema Present (HARD STOP — see §2)
  ├─ Check msLAPS-* attributeSchema objects exist in schema NC
  ├─ Verify computer class mayContain linkage
  └─ FAIL → Emit WINLAPS_SCHEMA_MISSING, halt entire deploy

GATE 2: LAPS PowerShell Module Available
  ├─ Import-Module LAPS -ErrorAction Stop
  ├─ Verify required cmdlets present in ExportedCommands:
  │   Set-LapsADComputerSelfPermission
  │   Set-LapsADReadPasswordPermission
  │   Set-LapsADResetPasswordPermission
  └─ FAIL → Emit WINLAPS_MODULE_MISSING

GATE 3: Domain Functional Level ≥ 2016 (encryption gate)
  ├─ Query DFL via Get-ADDomain
  └─ FAIL → Emit WINLAPS_DFL_INSUFFICIENT

GATE 4: Required OUs Present
  ├─ For each target OU in WinLaps config segment:
  │   Resolve OU DN, confirm exists via Get-ADOrganizationalUnit
  ├─ Domain Controller OU exclusion check (DC-object detection)
  └─ FAIL → Emit WINLAPS_OU_MISSING per missing OU

GATE 5: Required Groups Present
  ├─ For each AllowedPrincipal group in config:
  │   Resolve via Get-ADGroup
  └─ FAIL → Emit WINLAPS_GROUP_MISSING per missing group

ALL GATES PASS → Proceed to planning/execution
```

### Fail-Fast Contract Details

- **Accumulate, then fail.** Gates 1–3 are sequential hard-stops (no point checking OUs if schema is missing). Gates 4–5 accumulate all errors, then emit a combined failure report. This gives the operator a single remediation pass.
- **No partial deployment.** If ANY gate fails, ZERO changes are written. This applies equally to standalone `-IncludeWinLaps` and to `-FullDeployment -IncludeWinLaps`.
- **FullDeployment integration.** Windows LAPS gates run within `Test-TierModelPrerequisites` when `-IncludeWinLaps` is passed. The existing phases (OUs → Groups → Users → OU ACLs → GPOs → ADMX) execute normally; Windows LAPS phases execute AFTER standard phases complete, same as the MSA/gMSA/dMSA pattern. If WinLaps prereqs fail, the entire deploy is blocked — not just the WinLaps phase — because the contract is "deploy plan as a unit."
- **Standalone mode.** When `-IncludeWinLaps` is the only switch (no `-FullDeployment`, no `-*Only`), WinLaps prereqs run first; if they pass, config is loaded, planning proceeds, and execution occurs on `-ConfirmApply`.

### Domain Controller OU Exclusion (Safety Rail)

Per Joel's approved decision (OQ-RT-01), the tool must default-exclude:
- `OU=Domain Controllers,<domainDN>`
- Any target OU that contains objects with `primaryGroupID=516` (Domain Controllers) or `userAccountControl` bit `0x2000` (SERVER_TRUST_ACCOUNT)

Detection must NOT rely on OU name alone. Implementation queries objects within candidate OUs and rejects scope containing DC objects BEFORE any DACL mutation.

Violation emits: `WINLAPS_DC_SCOPE_REJECTED` — a distinct error from missing-OU.

---

## 2. Hard-Stop on Missing Schema

### Architectural Contract

The Windows LAPS schema extension (`Update-LapsADSchema`) is a forest-wide, irreversible, Schema-Admin-privileged operation. The deploy tool:

1. **NEVER mutates schema.** No auto-run of `Update-LapsADSchema`. No offer to do so. No step-by-step instructions.
2. **Detects missing schema** by querying for the six `msLAPS-*` attributeSchema objects AND the `computer` class `mayContain` linkage.
3. **Emits a structured error** with stable error ID `WINLAPS_SCHEMA_MISSING`.
4. **Directs the user** to their organization's approved AD schema-change runbook/change-control process. Points to Microsoft public documentation URL (`https://learn.microsoft.com/en-us/windows-server/identity/laps/laps-technical-reference`) without step-by-step instructions.
5. **Explicitly warns** against ad-hoc schema edits, LDIF, ADSI, and unsupported scripts.

### Distinction from Soft Pre-Req Failures

| Category | Nature | Operator Self-Remediate? | Tool Behavior |
|---|---|---|---|
| Schema missing (HARD STOP) | Forest-level, requires Schema Admin, irreversible | No — requires change-control process | Halt, emit `WINLAPS_SCHEMA_MISSING`, reference MS docs |
| OU missing (soft pre-req) | Domain-level, operator can create OU or run `-OuOnly` first | Yes | Halt, list missing OUs, suggest running earlier phases |
| Group missing (soft pre-req) | Domain-level, operator can create group or run `-GroupOnly` first | Yes | Halt, list missing groups, suggest running earlier phases |
| DFL insufficient | Domain-level, requires domain admin planning | Partially | Halt, emit `WINLAPS_DFL_INSUFFICIENT`, reference MS docs |

### Error Output Shape

```powershell
[PSCustomObject]@{
    ErrorId       = 'WINLAPS_SCHEMA_MISSING'
    Severity      = 'Fatal'
    Message       = 'Windows LAPS AD schema attributes are not present in this forest.'
    Guidance      = 'Extend the forest schema through your organization''s approved AD schema-change runbook.'
    Reference     = 'https://learn.microsoft.com/en-us/windows-server/identity/laps/laps-technical-reference'
    Warning       = 'Do not use ad-hoc LDIF, ADSI edits, or unsupported scripts for schema extension.'
    Forest        = $forestDN
    SchemaDN      = $schemaNamingContext
    MissingAttrs  = $missingAttributes
    Timestamp     = (Get-Date -Format 'o')
    CorrelationId = $correlationId
}
```

---

## 3. Cmdlet Surface Architecture

### Placement & Module Pattern

All new cmdlets reside under `modules/TierModel/public/` — dot-sourced by `TierModel.psm1` automatically (lines 37–53). This is the established pattern for MSA/gMSA/dMSA. New cmdlets need only: (a) a `.ps1` file in `public/`, (b) an entry in `FunctionsToExport` in `TierModel.psd1`.

### Cmdlet Inventory (Approved Names)

Following the established `{Verb}-TierModel{Feature}{Fd}` naming convention:

| Cmdlet | Responsibility | Mode |
|---|---|---|
| `Get-TierModelWinLapsAcl` | Generate DACL delegation plan (standalone) — validates target OUs, resolves principals, produces action list | Standalone |
| `Get-TierModelWinLapsAclFd` | Generate DACL delegation plan (FullDeployment variant) — lighter validation, assumes earlier phases created OUs/groups | FullDeployment |
| `New-TierModelWinLapsAcl` | Execute the plan — applies DACL changes via Microsoft `Set-LapsAD*Permission` cmdlets | Both |

### Standalone vs Fd Split (Constitution VIII)

Consistent with `Get-TierModelMsaAcl` / `Get-TierModelMsaAclFd` (same files, same contract):

- **Standalone (`Get-TierModelWinLapsAcl`):** Full pre-req validation of OUs and groups. Used when operator runs `-IncludeWinLaps` without `-FullDeployment`. Fails fast if target OUs or groups don't exist.
- **Fd variant (`Get-TierModelWinLapsAclFd`):** Assumes OUs and groups were created by earlier phases (Phase 1 OUs, Phase 2 Groups). Uses lighter validation. Used in `-FullDeployment -IncludeWinLaps` orchestration.
- **Shared executor (`New-TierModelWinLapsAcl`):** Single apply cmdlet accepts plan from either variant. Contains the Microsoft cmdlet invocation logic (`Set-LapsADComputerSelfPermission`, `Set-LapsADReadPasswordPermission`, `Set-LapsADResetPasswordPermission`).

### Naming Verdict

`WinLapsAcl` is APPROVED because:
- Distinct from any legacy LAPS naming (`LapsAcl` could be confused with legacy `ms-Mcs-AdmPwd*`)
- Consistent with `MsaAcl`, `GmsaAcl`, `DmsaAcl` convention (abbreviated feature + `Acl` suffix)
- Single clear responsibility per cmdlet (Constitution VIII)

### Audit Cmdlet (Future — NOT in scope now)

`Test-TierModelWinLapsAcl` will be designed in the auditing wave. Placeholder reserved; NOT implemented in deployment wave.

### Export Surface Addition

Add to `TierModel.psd1` `FunctionsToExport`:
```
'Get-TierModelWinLapsAcl',
'Get-TierModelWinLapsAclFd',
'New-TierModelWinLapsAcl',
```

---

## 4. Windows-LAPS-Only Invariant (ADR-0001 Enforcement)

### Architectural Enforcement at Three Layers

The system must NEVER deploy, assume, or reference Legacy Microsoft LAPS (`ms-Mcs-AdmPwd*`):

1. **Schema Detection Layer:** Only query for `msLAPS-*` attributes (the six Windows LAPS attributes). Never query for `ms-Mcs-AdmPwd` or `ms-Mcs-AdmPwdExpirationTime`.
2. **Cmdlet Invocation Layer:** Only invoke Microsoft `Set-LapsAD*Permission` cmdlets from the `LAPS` module. Never invoke `Set-AdmPwdComputerSelfPermission` (legacy) or reference `AdmPwd.PS` module.
3. **Configuration Schema Layer:** The JSON config segment uses key names referencing `winLaps` / `msLAPS-*` only. No `legacyLaps` or `admPwd` keys exist in the schema.

### Validation Rule

If the tool detects `ms-Mcs-AdmPwd` attributes in the target OU's DACL during planning (future drift-detection scope), it MUST NOT assume those are managed by this tool. Legacy LAPS state is treated as "foreign" — logged as informational, never modified, never relied upon.

### Config Key Naming

```json
{
  "winLapsAclDelegations": [
    {
      "targetOu": "{{TierX_Computers_OU}}",
      "selfPermission": true,
      "readPasswordPrincipals": ["{{TierX_LapsRead_Group}}"],
      "resetPasswordPrincipals": ["{{TierX_LapsReset_Group}}"]
    }
  ]
}
```

Placeholder syntax `{{...}}` is consistent with existing `Resolve-TierModelPlaceholder` mechanism.

---

## 5. Constitution Compliance Map

| Principle | How Satisfied |
|---|---|
| **III. Idempotent Deployments** | v1 uses Microsoft `Set-LapsAD*Permission` cmdlets which are additive/convergent. Re-running produces same state. Planning phase detects existing ACEs before proposing actions. Second run yields 0 changes → converged. |
| **IV. Zero-Unintended-Impact / -WhatIf** | Default mode is PLANNING only. No changes without `-ConfirmApply`. Plan output includes summary counts, per-OU action list, and risk classification. Fail-fast gating prevents partial deployment. |
| **VI. Structured Logging (Write-TierModelLog)** | All gating decisions, plan generation, and execution steps emit structured logs with CorrelationId, Level, Message, Data. Sensitive data (group SIDs, OU DNs) logged; passwords NEVER logged. |
| **VII. Simplicity & Explicitness** | `-IncludeWinLaps` switch is explicit. No hidden side effects. DC exclusion is visible in plan output. No dynamic global state. |
| **VIII. Modular Decomposition** | Three cmdlets (Get-standalone, Get-Fd, New-apply) each < 300 lines target. Single responsibility: plan vs execute. No modification to existing cmdlets. Separate .ps1 files in `public/`. |
| **IX. JSON Schema/Version Governance** | New `winLapsAclDelegations` config segment added to config schema. Schema version bump (minor) with migration notes. SHA-256 hash of config logged at run start. |

Additional touchpoints:
- **I. Code Quality:** New cmdlets require comment-based help, examples, `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'`.
- **II. Test-First:** Pester tests deferred to UAT phase per Joel's workflow (same deviation as 002-gmsa-support).
- **V. Drift Detection:** Reserved for audit wave. Planning output captures current state for future drift comparison.

---

## 6. Risk Register

Distilled from `.research/windowslaps/research/red-team-findings.md` and `compliance-credential-custody.md`.

| # | Risk | Severity | Source | Mitigation |
|---|---|---|---|---|
| **R1** | Over-broad read delegation exposes local Administrator passwords across entire OU subtrees | **Critical** | compliance-credential-custody §2.1, red-team (info-disclosure) | Scope DACL to narrowest member-computer OU; per-Tier groups; `Find-LapsADExtendedRights` validation in plan output |
| **R2** | Accidental DC/DSRM scope creates Tier 0 credential-custody path | **Critical** | red-team finding #1, dacl-design §2 | Default-exclude DC OU; detect DC objects in target OUs; `WINLAPS_DC_SCOPE_REJECTED` hard stop; separate future mode required |
| **R3** | Collapsed read+reset+decrypt into one group defeats separation of duties | **High** | red-team finding #5, compliance §2.2 | Config schema separates `readPasswordPrincipals` and `resetPasswordPrincipals` as distinct arrays; combined requires explicit acknowledgment |
| **R4** | Clear-text AD storage (DFL < 2016) exposes passwords to any read-ACL holder | **High** | red-team finding #4, compliance §3 | DFL 2016+ gating in Gate 3; encrypted storage mandatory by default (Joel decision OQ-RT-03) |
| **R5** | Partial/botched schema extension passes naive attribute-presence check | **High** | red-team finding #2 | Hardened schema check verifies `mayContain` linkage on `computer` class, not just attribute names |
| **R6** | Reset-group abuse forces repeated password rotation, creating DoS or timing attacks | **Medium** | red-team STRIDE (DoS), dacl-design §4 | Separate reset principals from read principals; structured logging of reset operations; alerting recommendation |
| **R7** | Stale or orphaned DACL entries if OUs/groups are later deleted | **Medium** | Architecture concern | Audit wave drift detection will identify orphaned ACEs; deployment is additive-only — no deletion logic in v1 |
| **R8** | Management host with multiple LAPS module copies produces inconsistent behavior | **Low** | red-team finding #6 | Gate 2 uses `Import-Module LAPS -ErrorAction Stop` and validates via `ExportedCommands` on loaded instance |

---

## 7. FullDeployment Composition

### Phase Ordering

`-IncludeWinLaps` composes into `-FullDeployment` as a new optional phase AFTER all existing phases:

```
Phase 1:  OUs              (Invoke-OuDeployment)
Phase 2:  Groups           (Invoke-GroupDeployment)
Phase 3:  Users            (Invoke-UserDeployment)
Phase 4:  OU ACLs          (Invoke-OuAclDeployment)
Phase 5:  GPOs             (Invoke-GpoDeployment)
Phase 6:  ADMX             (Invoke-AdmxDeployment)
Phase 7:  MSA ACLs         (if -IncludeMsa)
Phase 8:  gMSA ACLs        (if -IncludeGmsa)
Phase 9:  dMSA ACLs        (if -IncludeDmsa)
Phase 10: WinLaps ACLs     (if -IncludeWinLaps)   ← NEW
```

### Independence from MSA/gMSA/dMSA

Windows LAPS operates on a completely different schema family (`msLAPS-*`) and different Microsoft cmdlets (`Set-LapsAD*Permission`). It has NO dependency on MSA, gMSA, or dMSA phases:
- `-IncludeWinLaps` can run with or without any combination of `-IncludeMsa`, `-IncludeGmsa`, `-IncludeDmsa`.
- Phase 10 executes AFTER any enabled MSA/gMSA/dMSA phases, but does not depend on their success.
- It depends only on Phase 1 OUs and Phase 2 Groups having created required objects.

### FullDeployment Pre-computation

Following Beast's archived decision "Precompute Optional MSA/gMSA/dMSA ACL Plans During Full-Deployment":
1. **Planning phase:** When `-FullDeployment -IncludeWinLaps` is specified, pre-compute `$winLapsFdPlan = Get-TierModelWinLapsAclFd` BEFORE the aggregate Deployment Plan summary is printed.
2. **Summary integration:** WinLaps phase action counts appear in aggregate summary totals and phase listing.
3. **Execution phase:** Reuse the stored `$winLapsFdPlan` — no second planning pass.

### Parameter Validation Rules

```
-IncludeWinLaps + -FullDeployment        → VALID (Phase 10 in full sequence)
-IncludeWinLaps (standalone, no scope)   → VALID (standalone WinLaps ACL deploy)
-IncludeWinLaps + -OuOnly                → INVALID (rejected at param validation)
-IncludeWinLaps + -GroupOnly             → INVALID
-IncludeWinLaps + -OuAclsOnly            → INVALID
-IncludeWinLaps + -IncludeMsa            → VALID (both run independently)
-IncludeWinLaps + -IncludeGmsa + -FD     → VALID (phases 8 + 10 in full sequence)
```

### No Modification to Existing Cmdlets

Per active decision "Cmdlet Files Are Off-Limits" — existing cmdlets are NOT modified. The feature is entirely additive: new cmdlet files, new config segment, expanded `Test-TierModelPrerequisites`, and expanded `Deploy-TierModel.ps1` orchestration.

---

## 8. Configuration Schema Design (Shape Only — Values Deferred)

### New Config Segment

```json
{
  "$schema": "./tiermodel-winlaps-acl-schema.json",
  "schemaVersion": "1.0.0",
  "winLapsAclDelegations": [
    {
      "targetOu": "{{Tier1_Servers_OU}}",
      "selfPermission": true,
      "readPasswordPrincipals": ["{{Tier1_LapsRead_Group}}"],
      "resetPasswordPrincipals": ["{{Tier1_LapsReset_Group}}"],
      "tier": 1,
      "description": "Tier 1 server computer LAPS delegation"
    }
  ]
}
```

### Schema Versioning
- Semantic versioned: `1.0.0` initial.
- JSON Schema file validates structure.
- Schema changes require minor/major version bump + migration notes (Constitution IX).
- SHA-256 hash of config file logged at deploy start.

### Placeholder Resolution
All `{{...}}` placeholders resolved via existing `Resolve-TierModelPlaceholder` — no new resolution mechanism needed.

---

## 9. Open Architecture Questions (For Plan.md Resolution in Wave 2)

| ID | Question | Blocks |
|---|---|---|
| AQ-1 | Should `New-TierModelWinLapsAcl` invoke `Set-LapsAD*Permission` directly or wrap for additional idempotency checking? (OQ-RT-06) | Implementation |
| AQ-2 | Does auditing (`Set-LapsADAuditing`) belong in `-IncludeWinLaps` or is it a separate switch? (OQ-RT-07) | Scope |
| AQ-3 | Should the Fd variant skip DC-object detection (relying on config correctness) or perform it defensively? | Safety vs performance |
| AQ-4 | Config segment: separate JSON file or new key in existing segmented config structure? | Config architecture |

---

## 10. Data Flow Diagram

```
User invokes:
  Deploy-TierModel.ps1 -PreferredDc DC01 -FullDeployment -IncludeWinLaps -ConfirmApply

  ┌───────────────────────────────────────────────────────────────┐
  │ Test-TierModelPrerequisites -IncludeWinLaps                   │
  │   → Gates 1-5 (§1)                                           │
  │   → ALL PASS or HALT                                          │
  └───────────────────────────┬───────────────────────────────────┘
                              │ pass
  ┌───────────────────────────▼───────────────────────────────────┐
  │ Get-TierModelConfig → loads winLapsAclDelegations segment     │
  └───────────────────────────┬───────────────────────────────────┘
                              │
  ┌───────────────────────────▼───────────────────────────────────┐
  │ Phases 1-9 execute (standard + MSA/gMSA/dMSA)                │
  └───────────────────────────┬───────────────────────────────────┘
                              │
  ┌───────────────────────────▼───────────────────────────────────┐
  │ Phase 10: Get-TierModelWinLapsAclFd                           │
  │   → Resolve target OUs, principals                            │
  │   → DC-object exclusion check                                 │
  │   → Generate action plan (self + read + reset per OU)         │
  └───────────────────────────┬───────────────────────────────────┘
                              │
  ┌───────────────────────────▼───────────────────────────────────┐
  │ New-TierModelWinLapsAcl -Plan $plan                           │
  │   → Set-LapsADComputerSelfPermission per OU                   │
  │   → Set-LapsADReadPasswordPermission per OU + principals      │
  │   → Set-LapsADResetPasswordPermission per OU + principals     │
  │   → Structured logging for each operation                     │
  │   → Return result (Applied/Skipped/Errors/DurationMs)         │
  └───────────────────────────────────────────────────────────────┘
```

---

## 11. Key Research References

- DACL Design: `.research/windowslaps/architecture/dacl-design.md`
- Dependencies & Preflight: `.research/windowslaps/research/dependencies-and-preflight.md`
- Red-Team Findings: `.research/windowslaps/research/red-team-findings.md`
- Compliance & Custody: `.research/windowslaps/research/compliance-credential-custody.md`
- ADR-0001: `.research/windowslaps/decisions/0001-windows-laps-only.md`
- Joel Decisions: `.research/windowslaps/open-questions.md` (OQ-RT-01, OQ-RT-02, OQ-RT-03 — closed)
- Precedent Fd cmdlet: `modules/TierModel/public/Get-TierModelMsaAclFd.ps1`
- Precedent standalone: `modules/TierModel/public/Get-TierModelMsaAcl.ps1`

---

## Rationale

- Follows constitution v1.3.0 principles (idempotency III, zero-impact IV, structured logging VI, modular decomposition VIII, version governance IX)
- Consistent with `specs/002-gmsa-support/plan.md` patterns
- Respects all Joel pre-start decisions (OQ-RT-01 DC exclusion, OQ-RT-02 schema detect-only, OQ-RT-03 encryption mandatory)
- Preserves "cmdlet files off-limits" active decision


--- 

# Decision Note: DC OU Gating — Per-Entry isDomainControllerOu Flag

**Author:** Cyclops | **Date:** 2026-07-13 | **Status:** Applied to spec.md, plan.md, tasks.md

## Decision

Joel resolved the Domain Controllers OU gating conflict (OQ-RT-01 refinement) with a per-entry opt-in flag:

- **Config**: Optional `isDomainControllerOu` (boolean, default `false`) added to each `winLapsDelegations` entry. Only the Domain Controllers OU entry sets it `true`.
- **Gating**: DC-object hard-stop (`WINLAPS_DC_SCOPE_REJECTED`) REMAINS the default for every entry. When `isDomainControllerOu: true`, the planner/prereq intentionally allows DC objects in that OU — DC targeting is deliberate and visible in config.
- **Locked decision OQ-RT-01 refined**: default protection retained + explicit per-entry opt-in added. No blanket DC exclusion bypass.

## Context

Beast confirmed 7 LAPS-linked computer OUs: Domain Controllers; Tier 0/1 Member Servers; Tier 0/1/2 PAW Devices; Tier 2 End-User Devices. Two GPO templates used (DC template for DCs+PAWs; Common template for member servers+EUDs). Read/reset groups may differ across groupings.

## Files Changed

- spec.md: FR-003, FR-007, FR-013, Key Entities, edge cases, risk mitigation
- plan.md: Gate 4 logic, config schema example, risk R2, 7-OU deployment note
- tasks.md: T001 (config), T002 (schema), T004 (prereqs), T005 (planner)


--- 

# Decision Note: OQ-WL-01–06 Resolved — Integrated Design Adopted

**Author:** Cyclops | **Date:** 2026-07-13 | **Status:** Applied to spec.md, plan.md, tasks.md

## Summary

Joel resolved all 6 open questions. The INTEGRATED design (consistent with msa/gmsa/dmsa) is now the chosen baseline. Self-contained fallback dropped.

## Resolutions Applied

| OQ | Resolution |
|---|---|
| OQ-WL-01 | Config shape: exactly 4 fields per entry — `ouDn`, `computerSelfPermission`, `readGroup`, `resetGroup`. No tier/description metadata. |
| OQ-WL-02 | Read/reset kept as SEPARATE fields (secure-by-design: reset/expire ≠ read/decrypt). Operators MAY equalize. No decrypt-principal group needed. |
| OQ-WL-03 | Schema-missing message approved (KDS-key pattern in Test-TierModelPrerequisites.ps1). Exact wording pending Joel final sign-off. Tool never mutates schema. |
| OQ-WL-04 | "Auditing not configured" runtime notice REMOVED. Completeness tracked by STOP gate + Future Wave section boundary. |
| OQ-WL-05 | APPROVED: Test-TierModelPrerequisites.ps1 gets `-IncludeWinLaps` switch. Must NOT run/affect non-WinLaps deployments. |
| OQ-WL-06 | APPROVED: Get-TierModelConfig.ps1 gets `tiermodel-winlaps.json` in `$optionalFiles` + `winLapsDelegations` property + SHA-256 hash inclusion. |

## Key Design Changes

1. **Integrated = primary baseline**: cmdlets receive config via `-Config` param (loaded by Get-TierModelConfig); prereqs via Test-TierModelPrerequisites.
2. **T031/T032 moved to Phase 2b** (main flow, not conditional). Old Phase 8 removed.
3. **FR-014 redefined**: now means "integrated infrastructure" (was "audit notice").
4. **Risk R3 mitigation updated**: separation enforced at schema level; equalizing is operator choice.

## Remaining Inputs from Joel

- Concrete OU paths and group names for `config/tiermodel-winlaps.json`
- Final sign-off on exact WINLAPS_SCHEMA_MISSING message text


--- 

# Decision Note: Spec-Kit Polish (Professor X Review)

**Author:** Cyclops | **Date:** 2026-07-13 | **Status:** Applied

Professor X approved specs/003-win-laps/ with 2 minor non-blocking items, now applied: (1) tasks.md T033 documentation task assigned to Storm; (2) plan.md "Files to Modify (Existing)" table added for at-a-glance readability, explicitly stating no other existing module cmdlet is modified.


--- 

# Decision Note: Spec-Kit Documents Authored for specs/003-win-laps/

**Author:** Cyclops — Architect & Reviewer  
**Date:** 2026-07-13  
**Branch:** `feature/windows-laps`  
**Status:** PENDING Professor X review

---

## What Was Done

Authored the four canonical Spec-Kit documents for `specs/003-win-laps/`:

| File | Lines | Content |
|---|---|---|
| `spec.md` | ~300 | Feature specification: 3 user stories, 15 functional requirements, 7 success criteria, 8 edge cases, invariant statement, open questions |
| `plan.md` | ~330 | Implementation plan: prereq gating architecture, deployment flow, cmdlet contracts, config schema, risk register, parameter validation, self-contained vs integrated design |
| `tasks.md` | ~217 | 32 tasks (T001–T032) across 8 phases with 🛑 STOP GATE after T030. Test-first (T001–T019), config (T020–T021), implementation (T022–T025), integration (T026), lab validation (T027–T030), STOP, conditional (T031–T032). Future Wave (auditing) clearly marked OUT OF SCOPE. |
| `checklists/requirements.md` | ~70 | Quality checklist with all gates evaluated |

## Consolidated Inputs

Three Wave-1 findings notes consolidated:
1. `.squad/decisions/inbox/cyclops-winlaps-architecture.md` — 11-section gating design, cmdlet surface, composition, risk register
2. `.squad/decisions/inbox/wolverine-winlaps-lab-and-tests.md` — 19-test Pester plan, lab access verification (WinLapsSchema checkpoint confirmed), totals measurement strategy
3. Research package (`.research/windowslaps/`) — DACL design, red-team findings, compliance/custody, ADR-0001

## Open Decisions Routed to Joel (6)

| ID | Question | Blocks |
|---|---|---|
| OQ-WL-01 | Concrete OU paths and group names for config values | T20, T27–T30 |
| OQ-WL-02 | Read/reset group-separation model + decrypt principal | T20 |
| OQ-WL-03 | WINLAPS_SCHEMA_MISSING console message wording | T22 |
| OQ-WL-04 | "Auditing not yet configured" notice wording | T26 |
| OQ-WL-05 | Permission to modify Test-TierModelPrerequisites.ps1 | T32 |
| OQ-WL-06 | Permission to modify Get-TierModelConfig.ps1 | T31 |

## Key Decisions Baked In

- **Cmdlet names**: `Get-TierModelWinLapsAcl`, `Get-TierModelWinLapsAclFd`, `New-TierModelWinLapsAcl` (approved)
- **Phase 10**: WinLaps is last optional phase, after dMSA (Phase 9)
- **Self-contained baseline**: works without modifying existing cmdlets (OQ-WL-05/06 are optional enhancements)
- **3 actions per delegation**: Self + Read + Reset = totals increase by 3N
- **Test-first**: 19 tests authored before implementation (Constitution II, non-negotiable)
- **ADR-0001 enforced**: all three layers (schema/cmdlet/config) — legacy LAPS never referenced

## Next Steps

1. Professor X reviews and approves Spec-Kit docs
2. Joel resolves 6 open questions
3. Wolverine authors T01–T19 (Phase 1 — test stubs)
4. Beast implements T20–T26 (Phases 2–6)
5. Joel performs lab validation T27–T30 (Phase 7)


--- 

# Professor X — Spec Review Verdict: 003-win-laps

**Reviewer:** Professor X (Charles Xavier) — Lead  
**Date:** 2026-07-13  
**Branch:** `feature/windows-laps`  
**Documents Reviewed:** `specs/003-win-laps/spec.md`, `plan.md`, `tasks.md`, `checklists/requirements.md`  
**Baseline:** `specs/002-gmsa-support/` (structure parity reference)  
**Source Findings:** Beast, Cyclops, Wolverine inbox documents (faithful capture verified)

---

## Overall Verdict: ✅ APPROVED — with 2 minor action items (non-blocking)

---

## A. Constitution Scorecard (9 Principles)

| # | Principle | Verdict | Evidence |
|---|-----------|---------|----------|
| I | Code Quality / Traceability | **PASS** | Feature branch declared, input documented, FR→SC→Task traceability table in tasks.md |
| II | Test-First with Pester | **PASS** | Phase 1 (T001–T019) = 19 tests authored BEFORE implementation; red→green stated. Correctly follows constitution (improvement over 002's deviation). |
| III | Idempotent Deployments | **PASS** | FR-005, SC-001; T007/T010/T018/T029; Microsoft cmdlets are convergent; second run = 0 changes documented |
| IV | Zero-Unintended-Impact / -WhatIf | **PASS** | FR-006; planning-only default; -ConfirmApply required; fail-fast 5-gate architecture; T008 |
| V | Drift Detection | **PASS (deferred)** | Explicitly out-of-scope with visible "auditing not yet configured" notice (FR-014). Future wave section in tasks.md. Acceptable documented deferral. |
| VI | Structured Logging / Write-TierModelLog | **PASS** | FR-009; cmdlet contracts specify Write-TierModelLog + CorrelationId; passwords never logged |
| VII | Simplicity & Explicitness | **PASS** | Switch params, no hidden behavior, DC exclusion visible in plan output |
| VIII | Modular Decomposition | **PASS** | 3 cmdlets (Get-standalone, Get-Fd, New-apply), single-responsibility, <300 lines each, separate .ps1 files |
| IX | Dependency/JSON Schema+Version Governance | **PASS** | schemaVersion "1.0.0", JSON Schema file (T021), SHA-256 hash logged, version bump on change |

---

## B. Structure Parity with 002-gmsa-support

| Dimension | 002 | 003 | Assessment |
|-----------|-----|-----|------------|
| spec.md | 4 user stories, 14 FRs, 7 SCs | 3 user stories, 15 FRs, 7 SCs | ✅ Proportional (003 is single-feature vs 002's 3-type matrix) |
| plan.md | ~27KB, 12 cmdlets | ~15KB, 3 cmdlets | ✅ Scope-proportional; all key sections present |
| tasks.md | ~24KB, 37 tasks, 16 phases | ~17KB, 32 tasks, 8 phases | ✅ Proportional to feature complexity |
| checklists | Simple pass/fail | Enhanced with constitution + security | ✅ Improvement over 002 |

**Key sections verified present in 003:** Technical Context, Constitution Check, Prerequisites Architecture, Deployment Flow (standalone + FD), Plan Output Contract, Totals Integration, New Files, Parameter Validation, Cmdlet Contracts, Risk Register, Dependencies, Open Questions.

**003 is NOT unjustifiably thin.** The size difference (~60%) is proportional: 002 delivers 12 cmdlets across 3 account types; 003 delivers 3 cmdlets for 1 feature. Substance is complete.

---

## C. Requirements Scorecard (Points 1–10 + D/E/F)

| # | Requirement | Verdict | Evidence |
|---|-------------|---------|----------|
| 1 | `-IncludeWinLaps` named option | **PASS** | FR-001; plan.md param block; T026 |
| 2 | Schema missing = HARD STOP, quiet, non-prescriptive, WINLAPS_SCHEMA_MISSING, MS docs ref | **PASS** | FR-004; plan.md Schema Hard-Stop Contract; T001; Cyclops arch §2 confirms no cmdlet name, no step-by-step |
| 3 | Standalone FAILS if OUs/groups missing; all pre-reqs green before ANY change | **PASS** | FR-003 ("validate ALL...UP FRONT"); plan.md Gate 4–5; T003/T004 |
| 4 | FullDeployment composes after MSA/gMSA/dMSA; existing phases not reordered | **PASS** | FR-012 (Phase 10 after Phase 9); plan.md full deployment flow; T014/T019 |
| 5 | Deployment ONLY; auditing OUT OF SCOPE; visible notice | **PASS** | FR-014; Assumptions; tasks.md Future Wave section; "auditing not yet configured" in plan output |
| 6 | STOP gate for Joel manual testing | **PASS** | tasks.md "🛑 STOP — MANUAL TEST GATE (Joel)" after T030, before Phase 8 |
| 7 | NO existing cmdlet modified without permission; self-contained new cmdlets | **PASS** | plan.md §Self-Contained Design; OQ-WL-05/06 flagged; T031/T032 gated by Joel decision |
| 8 | Totals strictly INCREASE (N×3 CreateAcl); measurement documented; verification task | **PASS** | FR-008; SC-002; plan.md §Totals Integration (3N formula); T016/T017/T028 |
| 9 | JSON config shape defined, schema-versioned; values marked [NEEDS INPUT: Joel] | **PASS** | plan.md §Configuration Schema; T020/T021; schemaVersion "1.0.0" |
| 10 | WINDOWS LAPS ONLY (ms-LAPS-*), never legacy | **PASS** | FR-010; ADR-0001 §Invariant (3-layer enforcement); T006 |
| D | tasks.md usability (IDs, granularity, STOP gate, OUT-OF-SCOPE section) | **PASS** | T001–T032 sequential; 🛑 gate after T030; "Future Wave — OUT OF SCOPE" at end |
| E | Open decisions OQ-WL-01..06 present, correctly scoped, non-blocking | **PASS** | All 6 in spec.md Open Questions; implementation unblocked via self-contained baseline |
| F | Risks captured (credential-custody, DC-scope, over-delegation, ACE-lab-gap) | **PASS** | R1–R8 in plan.md + spec.md; H-1 ACE fixture gap addressed by T030 |

---

## D. Source Findings — Faithful Capture Verification

| Source | Key Content | Captured? |
|--------|-------------|-----------|
| Beast technical findings | 6 ms-LAPS-* attributes, 2-tier schema check, 3 DACL ops per OU, DC exclusion by attribute, LAPS module check, encryption model, no legacy LAPS | ✅ All reflected in spec FR-003/004/007/010, plan Gates 1–5 |
| Cyclops architecture | 5-gate gating sequence, cmdlet naming (WinLapsAcl), ADR-0001 3-layer enforcement, Phase 10 composition, config schema shape, risk register | ✅ Directly adopted into plan.md architecture |
| Wolverine lab+tests | 19-test strategy (15 unit + 4 integration), lab access (TierLab-DC01, WinLapsSchema checkpoint), Phase 16 Pester conventions, totals capture method | ✅ tasks.md Phase 1 mirrors exactly; lab procedure in Phase 7 |

---

## E. Minor Action Items (Non-Blocking)

These should be addressed before implementation begins but do NOT block the spec review:

### Item 1: Missing documentation task in tasks.md

**File:** `specs/003-win-laps/tasks.md`  
**Section:** After Phase 7 (or within Phase 6)  
**Change needed:** Add a documentation task (e.g., T033) to update `docs/` and `README.md` with `-IncludeWinLaps` switch documentation, following the pattern of 002's T037. Should cover: parameter documentation, deployment examples (standalone + FD), test-tag-matrix update.

### Item 2: Explicit "Files to Modify" summary table in plan.md

**File:** `specs/003-win-laps/plan.md`  
**Section:** After "New Files to Create" section  
**Change needed:** Add a consolidated "Files to Modify (Existing)" table matching 002's format, listing: `Deploy-TierModel.ps1` (moderate), `modules/TierModel/TierModel.psd1` (minor), and optionally `Get-TierModelConfig.ps1` / `Test-TierModelPrerequisites.ps1` (if OQ-WL-05/06 approved). This improves at-a-glance readability for Joel's review.

---

## Ready for Joel?

**Yes.** The Spec-Kit documents are substantively complete, faithfully capture the research findings, align with all 9 constitution principles, and meet all 10 of Joel's requirements. The 2 action items above are presentation/completeness polish — they can be addressed in < 15 minutes by Cyclops and do not change architecture or scope.

Joel can confidently review these documents for the OQ-WL-01..06 decisions and approve implementation start.


--- 

# Wolverine — WinLaps Lab Access Verification + Pester Test Strategy

**Author:** Wolverine (Logan)
**Date:** 2026-07-13T18:21:02+08:00
**Branch:** feature/windows-laps
**Requested by:** Joel Platek
**Feeds:** Wave-2 spec.md / plan.md / tasks.md authoring for specs/003-win-laps/
**Scope:** Deployment only (auditing deferred). Read-only lab verification + test strategy.

---

## PART 1 — LAB ACCESS VERIFICATION

### Hyper-V Verification Commands Run (Read-Only)

```powershell
# Confirm VM exists
Get-VM -Name 'TierLab-DC01' | Select-Object Name, State, Status, Generation, ProcessorCount
# Result: Name=TierLab-DC01  State=Off  Status=Operating normally  Generation=2  ProcessorCount=16

# Confirm checkpoints
Get-VMCheckpoint -VMName 'TierLab-DC01' |
    Select-Object Name, SnapshotType, CreationTime, ParentSnapshotName |
    Sort-Object CreationTime
```

### Results

| Field | Value |
|---|---|
| VM Name | `TierLab-DC01` |
| VM State | Off |
| VM Status | Operating normally |
| Generation | 2 |
| Access method | PowerShell Direct via Hyper-V VMBus (elevation required) |

**Checkpoints present:**

| Name | Type | CreationTime | Parent |
|---|---|---|---|
| `DC-Promoted-Clean` | Standard | 2026-07-13 18:11:49 | (none — root) |
| `WinLapsSchema` | Standard | 2026-07-13 18:19:38 | `DC-Promoted-Clean` |

**✅ VM `TierLab-DC01` confirmed present and healthy.**
**✅ Checkpoint `WinLapsSchema` confirmed present** (child of `DC-Promoted-Clean`, created 8 minutes after parent on same date).

### What WinLapsSchema Represents

Joel extended the Windows LAPS AD schema on the guest DC and immediately shut down the VM and created the `WinLapsSchema` checkpoint. This gives us a clean, stable base where:
- The base Tier Model is NOT deployed (no Tier OUs, no Tier groups, no ACLs).
- The Windows LAPS schema IS already extended (ms-LAPS-* attributes exist in schema).
- The DC is in a healthy state with AD functional.

This is the **preferred rollback target** for all WinLaps deployment test iterations. We restore to `WinLapsSchema` rather than `DC-Promoted-Clean` so that we are not required to re-extend the schema on every cycle (schema extension is a one-way, irreversible AD operation that the team does not own).

### Lab Identity — Single Source of Truth

All values from `.research\copilot-cli-hyperv-ad-lab\lab-config.json` (ADR-0011):

| Parameter | Value |
|---|---|
| Hyper-V host | Workgroup Windows desktop (not domain-joined), same machine as Copilot CLI |
| VM name (Hyper-V) | `TierLab-DC01` |
| Guest hostname | `DC01` |
| Domain FQDN | `tierlab.internal` |
| Domain NetBIOS | `TIERLAB` |
| Admin credential | `TIERLAB\Administrator` / `LabPass123!` |
| Internal vSwitch | `vInternalSwitch` |
| DC IP | `192.168.100.10` |
| Guest deploy root | `C:\TierModel` |
| Deploy entry point | `C:\TierModel\Deploy-TierModel.ps1` |
| Guest PowerShell 7 | `C:\Program Files\PowerShell\7\pwsh.exe` |
| Baseline checkpoint | `DC-Promoted-Clean` |
| WinLaps checkpoint | `WinLapsSchema` |

### Access Requirements

Confirmed (from ADR-0011, OQ-07 resolved 2026-05-29):
- **Elevation required**: Copilot CLI must run in an elevated (Administrator) PowerShell session.
- **PowerShell 7+ required on guest**: TierModel module manifest specifies `PowerShellVersion = '7.0'`. PS Direct connects to the guest's default Windows PowerShell 5.1; all deploy invocations must explicitly call `C:\Program Files\PowerShell\7\pwsh.exe`.
- **NTDS StartPending workaround**: Both checkpoints are Standard type. After restore, NTDS may hang in StartPending for extended periods. `Reset-Lab.ps1` and `Start-LabAndDeploy.ps1` automatically detect and resolve this by stopping and restarting the NTDS service via PS Direct.

### Exact Commands: Lab Workflow for WinLaps Testing

#### Restore to WinLapsSchema (standard WinLaps retest cycle)

```powershell
# Must run in elevated PowerShell on Hyper-V host
Stop-VM -Name 'TierLab-DC01' -TurnOff -Force
Restore-VMCheckpoint -VMName 'TierLab-DC01' -Name 'WinLapsSchema' -Confirm:$false
Start-VM -Name 'TierLab-DC01'
# Wait for AD readiness — NTDS workaround runs automatically in Start-LabAndDeploy.ps1
```

#### Restore to DC-Promoted-Clean (full clean — no schema extension)

```powershell
# Use only when a schema-free base is explicitly required
& '.research\copilot-cli-hyperv-ad-lab\scripts\Reset-Lab.ps1'
```

`Reset-Lab.ps1` uses `lab-config.json` for the baseline checkpoint name and handles the NTDS workaround automatically.

#### Deploy without WinLaps (baseline totals capture)

```powershell
& '.research\copilot-cli-hyperv-ad-lab\scripts\Start-LabAndDeploy.ps1'
# Start-LabAndDeploy.ps1 always appends -FullDeployment -ConfirmApply
# Captures: output lines matching "Applied: N" and "Action count: N"
```

#### Deploy with -IncludeWinLaps

```powershell
& '.research\copilot-cli-hyperv-ad-lab\scripts\Start-LabAndDeploy.ps1' `
    -AdditionalParams @('-IncludeWinLaps')
# -AdditionalParams is appended verbatim to the Deploy-TierModel.ps1 invocation string
# built inside Start-LabAndDeploy.ps1 (Step 4, run-deploy.ps1 wrapper)
```

#### Verify Windows LAPS schema on guest (ad hoc check)

```powershell
$config = Get-Content -Raw '.research\copilot-cli-hyperv-ad-lab\lab-config.json' | ConvertFrom-Json
$cred = [pscredential]::new(
    $config.credentials.username,
    (ConvertTo-SecureString $config.credentials.admin_password -AsPlainText -Force)
)
Invoke-Command -VMName 'TierLab-DC01' -Credential $cred -ScriptBlock {
    Import-Module ActiveDirectory
    # ms-LAPS-Password is the canary — present iff Windows LAPS schema was extended
    Get-ADObject -SearchBase (Get-ADRootDSE).schemaNamingContext `
        -LDAPFilter '(lDAPDisplayName=ms-LAPS-Password)' `
        -ErrorAction SilentlyContinue |
        Select-Object Name, lDAPDisplayName
}
# Expected on WinLapsSchema: returns ms-LAPS-Password object
# Expected on DC-Promoted-Clean: returns nothing
```

#### Measure lab totals before/after WinLaps (manual comparison procedure)

```powershell
# Step 1 — Baseline (no WinLaps)
Stop-VM -Name 'TierLab-DC01' -TurnOff -Force
Restore-VMCheckpoint -VMName 'TierLab-DC01' -Name 'WinLapsSchema' -Confirm:$false
Start-VM -Name 'TierLab-DC01'
$baseOutput = & '.research\copilot-cli-hyperv-ad-lab\scripts\Start-LabAndDeploy.ps1' 2>&1 |
    ForEach-Object { $_.ToString() }
$baseApplied = [int](($baseOutput | Select-String '^  Applied: (\d+)').Matches[0].Groups[1].Value)

# Step 2 — With WinLaps (restore first for clean comparison)
Stop-VM -Name 'TierLab-DC01' -TurnOff -Force
Restore-VMCheckpoint -VMName 'TierLab-DC01' -Name 'WinLapsSchema' -Confirm:$false
Start-VM -Name 'TierLab-DC01'
$lapsOutput = & '.research\copilot-cli-hyperv-ad-lab\scripts\Start-LabAndDeploy.ps1' `
    -AdditionalParams @('-IncludeWinLaps') 2>&1 |
    ForEach-Object { $_.ToString() }
$lapsApplied = [int](($lapsOutput | Select-String '^  Applied: (\d+)').Matches[0].Groups[1].Value)

Write-Host "Baseline Applied : $baseApplied"
Write-Host "WinLaps Applied  : $lapsApplied"
Write-Host "Delta            : $($lapsApplied - $baseApplied)"
# Expected: Delta > 0
```

#### Least-privilege cleanup

Close all PS Direct sessions immediately after use. `Start-LabAndDeploy.ps1` and `Reset-Lab.ps1` already call `Remove-PSSession` in their `finally` blocks. For ad-hoc sessions, always wrap in `try/finally { Remove-PSSession $session }`.

---

## PART 2 — PESTER TEST STRATEGY

### Governing Principles

- **Constitution Principle II (Test-First — NON-NEGOTIABLE)**: All 19 tests authored before Beast writes a single line of implementation. Tests must be red-failing against stubs, then green after implementation.
- **Constitution Principle III (Idempotency)**: Second run from identical state must yield `Converged: True`, `Applied: 0`.
- **Constitution Principle IV (WhatIf pre-flight)**: Planning mode must emit plan with counts and make zero AD writes.
- **Phase 16 Pester patterns (from .squad/decisions.md)**: These are mandatory conventions established during MSA/gMSA/dMSA work and must be followed exactly.

### Phase 16 Pester Conventions (Mandatory)

1. **Never `Mock` inside `It` blocks for error-path tests** — Pester 5.7.1 treats such mocks as Context-scoped and they bleed to subsequent tests. Use dedicated `BeforeAll` with config-driven conditional behavior instead.
2. **`Should -Invoke -Times N`** (omit `-Exactly`) for "at least N" semantics. `-AtLeastTimes` is NOT valid in Pester 5.7.1.
3. **Hashtable vs PSCustomObject**: Module cmdlets return `Summary` and `Validation` as `@{...}` hashtables. Use `.Keys | Should -Contain`, not `.PSObject.Properties.Name`.
4. **`InheritedObjectType`** in ACE mock rules: expected to be `[Guid]::Empty` for GenericAll/Descendents ACE entries.
5. **Describe-level `BeforeAll`** for all AD mocks: conditional returns based on `Identity` value to handle both positive and negative paths.

### Precedent Pattern (MSA/gMSA/dMSA — Phase 16)

WinLaps tests must follow the exact structure of `tests/Unit.MsaAclOperations.Tests.ps1`. The new cmdlets will follow the naming pattern:
- `Get-TierModelWinLapsAcl` — plan generator (standalone)
- `New-TierModelWinLapsAcl` — applier (standalone)
- `Test-TierModelWinLapsAcl` — drift/test checker
- `Get-TierModelWinLapsAclFd` — plan generator for FullDeployment integration

Config key: `winLapsAclDelegations` (array of delegation objects matching the MSA/gMSA/dMSA shape).
GUID mappings: ms-LAPS-* attribute GUIDs in `config\dependencies.json` `staticMappings.objectClasses` section.

### How Deploy-TierModel.ps1 Reports Totals (Read-Only Inspection)

**Planning mode** (no `-ConfirmApply`), output block `=== Deployment Plan ===`:
```
Action count: N       ←  $deploymentPlan.TotalActions  (all planned actions, all phases)
Create count: N       ←  $deploymentPlan.CreateCount
Update count: N       ←  $deploymentPlan.UpdateCount
Link count: N         ←  $deploymentPlan.LinkCount
Configure count: N    ←  $deploymentPlan.ConfigureCount
Already exist: N      ←  $deploymentPlan.AlreadyExistCount
```
`$deploymentPlan` is a hashtable initialized at start of `if ($FullDeployment)` block. Each phase adds to `TotalActions` and `CreateCount`. The optional phases (MSA=7, gMSA=8, dMSA=9) are added via `Add-IncludeAclPhaseToDeploymentPlan`. WinLaps will be Phase 10 (TBD by Beast/Cyclops — just ≥ 10).

**Apply mode** (`-ConfirmApply`), output block `=== Deployment Results ===`:
```
Applied: N            ←  $totalApplied  (sum of .Applied.Count + .Executed across all result objects)
Skipped: N            ←  $totalSkipped
Errors: N             ←  $totalErrors
Duration: Nms
Converged: True/False
```
`$totalApplied` is computed by iterating `$allResults` (which includes `$msaExecResult`, `$gmsaExecResult`, `$dmsaExecResult` — WinLaps will add `$winLapsExecResult` to this array). The loop adds `.Applied.Count` (for OU/Group/OuAcl-type results) OR `.Executed` (for GPO/ADMX-type results) OR `.Summary.Successful` (for ADMX).

**For unit tests**: assert directly on `$plan.Summary.TotalActions` / `$plan.Summary.CreateActions` / `$plan.Summary.ExistingCount` returned by `Get-TierModelWinLapsAclFd`.

**For integration totals tests**: capture `Deploy-TierModel.ps1` stdout via `2>&1`, then:
```powershell
# Planning mode line
$actionCount = [int](($output | Select-String '^Action count: (\d+)').Matches[0].Groups[1].Value)
# Apply mode line  
$applied = [int](($output | Select-String '^Applied: (\d+)').Matches[0].Groups[1].Value)
$convergedLine = $output | Where-Object { $_ -match '^Converged:' }
```
Note: `Start-LabAndDeploy.ps1` prepends `"  "` (two spaces) to each output line via `Write-Host "  $_"`. In lab-run output, match `^  Applied: (\d+)` instead.

### Test File Map

| File | Tags | Count |
|---|---|---|
| `tests/Unit.WinLapsDeployment.Tests.ps1` | Unit, WinLaps | 15 |
| `tests/Integration.WinLapsDeployment.Tests.ps1` | Integration, WinLaps | 4 |
| **Total** | | **19** |

---

### UNIT TESTS — `tests/Unit.WinLapsDeployment.Tests.ps1`

Top-level: `Describe "WinLaps ACL Operations" -Tag "Unit", "WinLaps"`

---

#### T01 — Schema hard stop: ms-LAPS-Password attribute absent → throw, zero writes

**Context:** `Get-TierModelWinLapsAcl` must check for the Windows LAPS schema attribute `ms-LAPS-Password` in the AD schema partition BEFORE generating any plan. If absent, it must throw immediately with a message that identifies "schema" and "Windows LAPS". Zero AD-write calls (no `Set-Acl`, no `New-TierModelWinLapsAcl`) must fire.

**Mock setup (BeforeAll in Describe or dedicated Context):**
- `Mock Get-ADObject` — when called with an LDAP filter matching `ms-LAPS-Password` against the schema partition, return `$null` (not found).
- `Mock Set-Acl` as no-op (to detect any write call).

**Assertions:**
```powershell
{ Get-TierModelWinLapsAcl -Config $cfg -DomainController $dc } |
    Should -Throw -ExceptionMessage '*schema*'
Should -Invoke 'Set-Acl' -Times 0 -Scope It
```

**Why this matters:** Schema extension is irreversible and must be present before any LAPS-related delegation is possible. If schema is absent, every ACE write will fail with cryptic GUID resolution errors. Failing fast with a clear message prevents partial-state corruption and guides the operator to extend the schema first.

---

#### T02 — Schema present: no throw, plan proceeds

**Context:** When `Get-ADObject` returns a valid schema object for `ms-LAPS-Password`, the prerequisite check passes and plan generation proceeds without throwing.

**Mock setup:** `Mock Get-ADObject` to return a synthetic schema object (`[PSCustomObject]@{ lDAPDisplayName = 'ms-LAPS-Password'; Name = 'ms-LAPS-Password' }`) when queried against the schema partition.

**Assertions:**
```powershell
{ Get-TierModelWinLapsAcl -Config $cfg -DomainController $dc } | Should -Not -Throw
```

---

#### T03 — Pre-req gating: required OUs absent → plan errors, zero ACL actions

**Context:** Even with schema present, if the target OUs (the Tier X Computers OUs, or whichever OUs LAPS will delegate read/write access on) are absent, the plan must record a pre-req error and produce exactly zero `CreateAcl` actions. No writes must occur.

**Mock setup:** Schema mock passes. `Mock Get-ADOrganizationalUnit` to throw `[Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]` when called with the target OU distinguished name.

**Assertions:**
```powershell
$plan = Get-TierModelWinLapsAcl -Config $cfg -DomainController $dc
$plan.Errors.Count | Should -BeGreaterThan 0
$plan.Errors[0].Message | Should -BeLike '*required*OU*'
($plan.Actions | Where-Object { $_.Action -eq 'CreateAcl' }).Count | Should -Be 0
Should -Invoke 'Set-Acl' -Times 0 -Scope It
```

---

#### T04 — Pre-req gating: required groups absent → plan errors, zero ACL actions

**Context:** With schema and OUs present but the required groups (e.g., the Tier X Admins groups that will be granted read/write on LAPS attributes) absent, the plan records a pre-req error and produces zero actions.

**Mock setup:** Schema and OU mocks pass. `Mock Get-ADGroup` to throw `[Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]` for the required group identity.

**Assertions:**
```powershell
$plan = Get-TierModelWinLapsAcl -Config $cfg -DomainController $dc
$plan.Errors.Count | Should -BeGreaterThan 0
$plan.Errors[0].Message | Should -BeLike '*required*group*'
($plan.Actions | Where-Object { $_.Action -eq 'CreateAcl' }).Count | Should -Be 0
```

---

#### T05 — All pre-reqs green: valid plan generated with CreateAcl actions

**Context:** Schema, OUs, and groups all mocked as present. `Get-TierModelWinLapsAcl` must return a plan with `Errors = @()`, at least one `CreateAcl` action, and a `Summary` hashtable containing `TotalActions` and `CreateActions`.

**Mock setup:** All AD mocks return valid objects.

**Assertions:**
```powershell
$plan = Get-TierModelWinLapsAcl -Config $cfg -DomainController $dc
$plan.Errors.Count | Should -Be 0
($plan.Actions | Where-Object { $_.Action -eq 'CreateAcl' }).Count | Should -BeGreaterThan 0
$plan.Summary.Keys | Should -Contain 'TotalActions'
$plan.Summary.Keys | Should -Contain 'CreateActions'
$plan.Summary.TotalActions | Should -BeGreaterThan 0
```

---

#### T06 — Windows LAPS-only namespace: no ms-Mcs-AdmPwd* anywhere in plan

**Context:** This is the hard "no legacy LAPS" test. Every `objectType` field in every ACL action in the plan must reference an `ms-LAPS-*` attribute name or GUID. No `ms-Mcs-AdmPwd*` attribute (legacy LAPS) may appear in any action, data field, or GUID mapping used by WinLaps cmdlets.

**Mock setup:** All pre-req mocks pass; plan generated from the standard test config.

**Assertions:**
```powershell
$plan = Get-TierModelWinLapsAcl -Config $cfg -DomainController $dc
foreach ($action in $plan.Actions) {
    $action.Data.objecttype | Should -Not -BeLike 'ms-Mcs-*'
    $action.Data.objecttype | Should -Not -BeLike '*AdmPwd*'
    if ($action.Data.inheritedObjectType -and $action.Data.inheritedObjectType -ne [Guid]::Empty) {
        # If a GUID is used, verify it does not resolve to a legacy LAPS attribute
        # (implementation note: Beast must ensure no legacy GUID is ever in winLapsAclDelegations config)
        $action.Data.inheritedObjectType | Should -Not -Be '<guid-for-ms-Mcs-AdmPwd>'
    }
}
```
Note to Beast: the `winLapsAclDelegations` config block must exclusively reference `ms-LAPS-*` attribute names/GUIDs. No legacy LAPS attribute should ever be present in `staticMappings` under a WinLaps key.

---

#### T07 — Idempotency (plan): converged state → TotalActions = 0, Converged = true

**Context:** When all expected ACEs are already present on the target OUs (mock `Get-Acl` returns ACLs containing the full expected ACE set), a fresh plan generation must return `TotalActions = 0` and `Converged = $true`. No actions should be emitted.

**Mock setup:** `Mock Get-Acl` to return an `[System.DirectoryServices.ActiveDirectorySecurity]` object whose `Access` property already includes all expected WinLaps ACE entries.

**Assertions:**
```powershell
$plan = Get-TierModelWinLapsAcl -Config $cfg -DomainController $dc
$plan.Summary.TotalActions | Should -Be 0
$plan.Actions.Count | Should -Be 0
$plan.Converged | Should -BeTrue
```

---

#### T08 — WhatIf/planning: plan emitted, Set-Acl never called, Applied = 0

**Context:** Calling `New-TierModelWinLapsAcl` without `-ConfirmApply` (planning/WhatIf mode) must emit the plan structure but must not call `Set-Acl` or any ACL-writing cmdlet. This implements Constitution Principle IV.

**Mock setup:** `Mock Set-Acl` as no-op. Plan has N > 0 actions. Invoke `New-TierModelWinLapsAcl -Plan $plan -DomainController $dc -WhatIf` (or without `-ConfirmApply`, per how Beast designs the parameter).

**Assertions:**
```powershell
$result = New-TierModelWinLapsAcl -Plan $plan -DomainController $dc -WhatIf
Should -Invoke 'Set-Acl' -Times 0 -Scope It
$result.Applied | Should -Be 0
```

---

#### T09 — Apply: all expected ACE entries created, Applied = plan.Actions.Count

**Context:** When pre-reqs are green and the plan has N actions, `New-TierModelWinLapsAcl` with apply mode must call `Set-Acl` (or equivalent) exactly N times and return `Applied = N`, `Errors.Count = 0`, `Converged = $true`.

**Mock setup:** `Mock Set-Acl` as no-op. `Mock Get-Acl` returning empty ACL. Plan has N > 0 `CreateAcl` actions.

**Assertions:**
```powershell
$result = New-TierModelWinLapsAcl -Plan $plan -DomainController $dc -Config $cfg
$result.Applied | Should -Be $plan.Actions.Count
$result.Errors.Count | Should -Be 0
$result.Converged | Should -BeTrue
Should -Invoke 'Set-Acl' -Times $plan.Actions.Count -Scope It
```

---

#### T10 — Apply idempotency: already-converged state → Applied = 0, Skipped ≥ 0

**Context:** When all expected ACEs are already present, `New-TierModelWinLapsAcl` must skip every entry, report `Applied = 0`, and set `Converged = $true`. `Set-Acl` must never be called.

**Mock setup:** `Mock Get-Acl` returning ACL already containing all expected ACE entries. Pass an empty plan (zero `CreateAcl` actions) or a plan whose actions are all marked as already-satisfied.

**Assertions:**
```powershell
$result = New-TierModelWinLapsAcl -Plan $emptyOrConvergedPlan -DomainController $dc -Config $cfg
$result.Applied | Should -Be 0
$result.Converged | Should -BeTrue
Should -Invoke 'Set-Acl' -Times 0 -Scope It
```

---

#### T11 — Parameter guard: -IncludeWinLaps cannot combine with -OuOnly / *Only parameters

**Context:** Consistent with existing behavior for `-IncludeMsa`/`-IncludeGmsa`/`-IncludeDmsa`, the `-IncludeWinLaps` switch must not be combinable with any `-*Only` scope switch (`-OuOnly`, `-GroupOnly`, `-UserOnly`, `-GposOnly`, `-OuAclsOnly`, `-AdmxOnly`). The script must terminate with a parameter validation error and zero AD operations.

**Reference code:** `Deploy-TierModel.ps1` lines checking `$activeIncludeCount -gt 0 -and $activeScopeCount -eq 1 -and -not $FullDeployment` → `Write-Error "... cannot be used with -OuOnly..."`.

**Mock setup:** Mock `Get-TierModelConfig` and all prereq functions to return valid objects (to ensure the error is the parameter validation, not something upstream).

**Assertions:**
```powershell
{ & $deployScript -PreferredDc 'dummy' -IncludeWinLaps -OuOnly } |
    Should -Throw
# OR: capture exit code, assert non-zero and message contains prohibition text
```

---

#### T12 — Standalone -IncludeWinLaps (no -FullDeployment): plan contains only WinLaps actions

**Context:** `-IncludeWinLaps` without `-FullDeployment` must be valid and must produce a plan covering ONLY WinLaps ACL delegations — no OU creation, no group creation, no GPO actions.

**Mock setup:** All pre-req mocks green. Invoke `Get-TierModelWinLapsAcl` in planning mode.

**Assertions:**
```powershell
$plan = Get-TierModelWinLapsAcl -Config $cfg -DomainController $dc
$plan.Errors.Count | Should -Be 0
$plan.Summary.TotalActions | Should -BeGreaterThan 0
# No bleeding from other entity types
($plan.Actions | Where-Object { $_.Action -eq 'CreateOU' }).Count | Should -Be 0
($plan.Actions | Where-Object { $_.Action -eq 'CreateGroup' }).Count | Should -Be 0
($plan.Actions | Where-Object { $_.Action -eq 'CreateGPO' }).Count | Should -Be 0
```

---

#### T13 — FullDeployment integration: Get-TierModelWinLapsAclFd contributes to deployment plan totals

**Context:** `Get-TierModelWinLapsAclFd` (the FullDeployment variant, matching the MSA/gMSA/dMSA `*Fd` pattern) must return a plan object with `Summary.TotalActions > 0` and a phase number ≥ 10 (Beast/Cyclops assign exact number — WinLaps must come after dMSA=9). When `Add-IncludeAclPhaseToDeploymentPlan` processes it, `$deploymentPlan.TotalActions` must increase.

**Mock setup:** Schema, OUs, groups mocked as present. Invoke `Get-TierModelWinLapsAclFd -Config $cfg -DomainController $dc -IncludeDetails`.

**Assertions:**
```powershell
$winLapsPlan = Get-TierModelWinLapsAclFd -Config $cfg -DomainController $dc -IncludeDetails
$winLapsPlan.Errors.Count | Should -Be 0
$winLapsPlan.Summary.TotalActions | Should -BeGreaterThan 0
$winLapsPlan.Summary.CreateActions | Should -BeGreaterThan 0

# Verify Add-IncludeAclPhaseToDeploymentPlan integration:
$dp = @{ TotalActions = 0; CreateCount = 0; AlreadyExistCount = 0; Actions = @(); Phases = @() }
Add-IncludeAclPhaseToDeploymentPlan -DeploymentPlan $dp -PhaseNumber 10 `
    -PhaseName 'Windows LAPS ACL Delegations' -Plan $winLapsPlan
$dp.TotalActions | Should -BeGreaterThan 0
$dp.CreateCount | Should -BeGreaterThan 0
```

---

#### T14 — FullDeployment composition: WinLaps executes after MSA, gMSA, dMSA in call order

**Context:** When `-FullDeployment -IncludeMsa -IncludeGmsa -IncludeDmsa -IncludeWinLaps` is requested, the four `*AclFd` plan functions must be called in order: MSA, gMSA, dMSA, WinLaps. WinLaps must be last among the optional phases.

**Mock setup:** Mock all four `Get-TierModel*AclFd` functions to append to a `$callOrder` array and return minimal valid plan objects.

**Assertions:**
```powershell
$callOrder.IndexOf('WinLaps') | Should -BeGreaterThan ($callOrder.IndexOf('dMSA'))
$callOrder.IndexOf('WinLaps') | Should -BeGreaterThan ($callOrder.IndexOf('gMSA'))
$callOrder.IndexOf('WinLaps') | Should -BeGreaterThan ($callOrder.IndexOf('MSA'))
$callOrder.Count | Should -Be 4  # All four phases called
```

---

#### T15 — FullDeployment: WinLaps skipped when standard phases 1–6 fail

**Context:** The existing `$standardDeployHadErrors` gate in `Deploy-TierModel.ps1` prevents optional Include phases from executing if any of phases 1–6 produced errors. WinLaps must respect this gate identically to MSA/gMSA/dMSA.

**Mock setup:** Mock `Get-TierModelOuAclFd` (or any phase 1–6 function) to return a result object with `Errors.Count > 0`. Mock `Get-TierModelWinLapsAclFd` and `New-TierModelWinLapsAcl` as no-ops (to detect calls).

**Assertions:**
```powershell
Should -Invoke 'Get-TierModelWinLapsAclFd' -Times 0 -Scope It
Should -Invoke 'New-TierModelWinLapsAcl' -Times 0 -Scope It
```

---

### INTEGRATION TESTS — `tests/Integration.WinLapsDeployment.Tests.ps1`

Top-level: `Describe "WinLaps FullDeployment Integration" -Tag "Integration", "WinLaps"`

All AD cmdlets mocked at the integration boundary (same approach as `Integration.Deploy.Tests.ps1`). These tests exercise the full `Deploy-TierModel.ps1` orchestration with a realistic but mocked AD layer, focusing on the text output that operators and CI will observe.

---

#### T16 — TOTALS (planning): Action count strictly greater with -IncludeWinLaps

**Intent:** Confirms that `$deploymentPlan.TotalActions` is larger when `-IncludeWinLaps` is added. Tests the contribution of the WinLaps phase to the aggregate plan summary line in stdout.

**Capture method:**
```powershell
# Run baseline (no WinLaps)
$baseOutput = & $deployScript -PreferredDc $testDC -FullDeployment 2>&1 |
    ForEach-Object { $_.ToString() }
$baseActionCount = [int](($baseOutput |
    Where-Object { $_ -match '^Action count: (\d+)' } |
    ForEach-Object { [regex]::Match($_, '(\d+)').Value }
) | Select-Object -Last 1)

# Run with WinLaps
$lapsOutput = & $deployScript -PreferredDc $testDC -FullDeployment -IncludeWinLaps 2>&1 |
    ForEach-Object { $_.ToString() }
$lapsActionCount = [int](($lapsOutput |
    Where-Object { $_ -match '^Action count: (\d+)' } |
    ForEach-Object { [regex]::Match($_, '(\d+)').Value }
) | Select-Object -Last 1)
```

**Assertion:**
```powershell
$lapsActionCount | Should -BeGreaterThan $baseActionCount
```

---

#### T17 — TOTALS (apply): Applied count strictly greater with -IncludeWinLaps

**Intent:** Confirms that `$totalApplied` (the `Applied: N` line from `=== Deployment Results ===`) is strictly greater when `-IncludeWinLaps -ConfirmApply` is used, compared to `-ConfirmApply` alone — both runs from the same fresh mock state.

**Capture method:**
```powershell
# Baseline apply
$baseApplied = [int](($baseConfirmOutput |
    Where-Object { $_ -match '^Applied: (\d+)' } |
    ForEach-Object { [regex]::Match($_, '(\d+)').Value }
) | Select-Object -Last 1)

# WinLaps apply
$lapsApplied = [int](($lapsConfirmOutput |
    Where-Object { $_ -match '^Applied: (\d+)' } |
    ForEach-Object { [regex]::Match($_, '(\d+)').Value }
) | Select-Object -Last 1)
```

**Assertion:**
```powershell
$lapsApplied | Should -BeGreaterThan $baseApplied
```

---

#### T18 — TOTALS (apply idempotency): second run → Applied = 0, Converged: True

**Intent:** After a successful `-IncludeWinLaps -ConfirmApply` run, a second run on the same (now fully applied) mocked state must report `Applied: 0` and `Converged: True`. Validates Constitution Principle III end-to-end through the orchestration script.

**Capture method:** After first apply run, re-run same deploy command without resetting mocks (mocks now simulate all ACEs present).

```powershell
$secondApplied = [int](($secondRunOutput |
    Where-Object { $_ -match '^Applied: (\d+)' } |
    ForEach-Object { [regex]::Match($_, '(\d+)').Value }
) | Select-Object -Last 1)
$convergedLine = $secondRunOutput | Where-Object { $_ -match '^Converged:' }
```

**Assertions:**
```powershell
$secondApplied | Should -Be 0
$convergedLine | Should -BeLike '*True*'
```

---

#### T19 — FullDeployment composition (plan output): all four Include* phases present, WinLaps last

**Intent:** When `-FullDeployment -IncludeMsa -IncludeGmsa -IncludeDmsa -IncludeWinLaps` is run in planning mode, the stdout must contain phase-label lines for all four optional phases, and the WinLaps phase label must appear after the dMSA phase label in output order.

**Capture method:**
```powershell
$planOutput = & $deployScript -PreferredDc $testDC `
    -FullDeployment -IncludeMsa -IncludeGmsa -IncludeDmsa -IncludeWinLaps 2>&1 |
    ForEach-Object { $_.ToString() }

$msaIdx    = ($planOutput | Select-String 'Phase.*MSA ACL|MSA ACL Delegations').LineNumber   | Select-Object -First 1
$gmsaIdx   = ($planOutput | Select-String 'Phase.*gMSA ACL|gMSA ACL Delegations').LineNumber | Select-Object -First 1
$dmsaIdx   = ($planOutput | Select-String 'Phase.*dMSA ACL|dMSA ACL Delegations').LineNumber | Select-Object -First 1
$lapsIdx   = ($planOutput | Select-String 'Phase.*WinLaps|Windows LAPS').LineNumber           | Select-Object -First 1
```

**Assertions:**
```powershell
$msaIdx  | Should -Not -BeNullOrEmpty
$gmsaIdx | Should -Not -BeNullOrEmpty
$dmsaIdx | Should -Not -BeNullOrEmpty
$lapsIdx | Should -Not -BeNullOrEmpty
$lapsIdx | Should -BeGreaterThan $dmsaIdx
$lapsIdx | Should -BeGreaterThan $gmsaIdx
$lapsIdx | Should -BeGreaterThan $msaIdx
```

---

## MASTER TEST TABLE

| ID | File | Describe Context | Intent (one line) | Key Assertion |
|---|---|---|---|---|
| T01 | Unit | Schema absent | Schema missing → throw, zero writes | `Should -Throw -ExceptionMessage '*schema*'`; `Set-Acl -Times 0` |
| T02 | Unit | Schema present | Schema present → no throw | `Should -Not -Throw` |
| T03 | Unit | OUs missing | OUs absent → plan errors, 0 CreateAcl | `Errors.Count > 0`; `Actions.Count = 0` |
| T04 | Unit | Groups missing | Groups absent → plan errors, 0 CreateAcl | `Errors.Count > 0`; `Actions.Count = 0` |
| T05 | Unit | All green | All pre-reqs pass → valid plan | `Errors = 0`; `TotalActions > 0` |
| T06 | Unit | Namespace | All ACL objectType = ms-LAPS-*, none ms-Mcs-* | `Should -Not -BeLike 'ms-Mcs-*'` on every action |
| T07 | Unit | Idempotency plan | Converged state → 0 actions, Converged=$true | `TotalActions = 0`; `Converged = $true` |
| T08 | Unit | WhatIf | Planning mode → Set-Acl never called, Applied=0 | `Set-Acl -Times 0`; `result.Applied = 0` |
| T09 | Unit | Apply | Apply → Applied=N, Errors=0, Converged | `Applied = plan.Actions.Count`; `Converged = $true` |
| T10 | Unit | Apply idempotency | Apply on converged → Applied=0, Set-Acl never | `Applied = 0`; `Set-Acl -Times 0` |
| T11 | Unit | Param guard | -IncludeWinLaps +-OuOnly → error | `Should -Throw` |
| T12 | Unit | Standalone | No -FullDeployment → WinLaps-only plan | `0 CreateOU/Group/GPO actions` in plan |
| T13 | Unit | FD integration | Get-TierModelWinLapsAclFd contributes to deploymentPlan | `dp.TotalActions > 0` after `Add-IncludeAclPhaseToDeploymentPlan` |
| T14 | Unit | Call order | WinLaps executes after MSA/gMSA/dMSA | `callOrder.IndexOf('WinLaps') > indexOf('dMSA')` |
| T15 | Unit | Error gate | Standard phase fail → WinLaps not invoked | `Get-TierModelWinLapsAclFd -Times 0` |
| T16 | Integration | TOTALS plan | Action count with WinLaps > without | `$lapsActionCount > $baseActionCount` |
| T17 | Integration | TOTALS apply | Applied with WinLaps > without | `$lapsApplied > $baseApplied` |
| T18 | Integration | TOTALS converge | Second apply → Applied=0, Converged:True | `Applied = 0`; output `'Converged: True'` |
| T19 | Integration | FD plan output | All 4 Include* phase labels in output, WinLaps last | `$lapsIdx > $dmsaIdx > $gmsaIdx > $msaIdx` |

---

## CONSTRAINTS AND DECISIONS FOR WAVE-2 AUTHORS

### For Beast (Implementation)

1. **Cmdlet names**: `Get-TierModelWinLapsAcl`, `New-TierModelWinLapsAcl`, `Test-TierModelWinLapsAcl`, `Get-TierModelWinLapsAclFd` — follow MSA/gMSA/dMSA naming exactly.
2. **Schema check first**: `Get-TierModelWinLapsAcl` must query `(Get-ADRootDSE).schemaNamingContext` for `ms-LAPS-Password` as the very first operation, before any plan building. Hard throw if absent.
3. **Windows LAPS only**: Config section `winLapsAclDelegations` must reference ONLY `ms-LAPS-*` attribute names/GUIDs. The GUID mapping entries in `staticMappings.objectClasses` for WinLaps must all have `ms-LAPS-` prefix. Never add `ms-Mcs-AdmPwd*` mappings to the WinLaps config block.
4. **Phase number**: WinLaps is Phase 10 in FullDeployment (after dMSA=9). Adjust if a phase is inserted earlier — WinLaps must remain the last optional phase.
5. **`$winLapsExecResult` variable**: Must be added to the `$allResults` array in the `=== Deployment Results ===` section so `$totalApplied` includes WinLaps ACE applications.
6. **Error gate**: The `$standardDeployHadErrors` block that gates all `$activeIncludeCount > 0` optional phases must also gate WinLaps. No separate gating logic needed — just add WinLaps to the same `if ($activeIncludeCount -gt 0 -and -not $standardDeployHadErrors)` block.

### For Cyclops (Architecture)

The WinLaps phase follows the exact same `Add-IncludeAclPhaseToDeploymentPlan` pattern as MSA/gMSA/dMSA. The function signature and call pattern are already established. No new architectural pattern required.

### For Storm (Documentation)

`-IncludeWinLaps` should be documented alongside `-IncludeMsa`, `-IncludeGmsa`, `-IncludeDmsa` in the deployment guide, with an explicit note that Windows LAPS schema extension must be performed separately before this switch can be used.

### For Wolverine (Test Implementation — Wave 2)

- Author T01–T19 before Beast implements. Stubs must fail all 19 before implementation begins.
- Follow Phase 16 Pester conventions strictly (see section above).
- T06 is a belt-and-suspenders test: even if Beast's config is correct, this test is a regression guard against future edits that accidentally introduce legacy LAPS GUIDs.
- T14 call-order test: record call order in a `$script:callOrder = @()` variable initialized in `BeforeAll`, appended in each mock body, asserted in `It`.

---

## LAB OPERATING PROCEDURE SUMMARY

For reference during Wave-2 manual validation by Joel:

```
1. RESTORE WinLapsSchema:
   Stop-VM 'TierLab-DC01' -TurnOff -Force
   Restore-VMCheckpoint -VMName 'TierLab-DC01' -Name 'WinLapsSchema' -Confirm:$false
   Start-VM 'TierLab-DC01'
   # Wait ~60-90s for AD readiness (NTDS workaround automatic)

2. BASELINE TOTALS (no WinLaps):
   & '.research\copilot-cli-hyperv-ad-lab\scripts\Start-LabAndDeploy.ps1'
   # Note "Applied: N" from "=== Deployment Results ===" section

3. RESTORE WinLapsSchema again (clean state for WinLaps run)

4. WINLAPS TOTALS:
   & '.research\copilot-cli-hyperv-ad-lab\scripts\Start-LabAndDeploy.ps1' -AdditionalParams @('-IncludeWinLaps')
   # Note "Applied: M" — M must be > N

5. IDEMPOTENCY CHECK (do NOT restore — rerun on deployed state):
   & '.research\copilot-cli-hyperv-ad-lab\scripts\Start-LabAndDeploy.ps1' -AdditionalParams @('-IncludeWinLaps')
   # Expect: "Applied: 0" and "Converged: True"

6. CLEANUP: sessions closed automatically by Start-LabAndDeploy.ps1 (Remove-PSSession in finally block)
```


