# beast -- History (Archived Summary)

## 2026-08-29 -- Milestone 7: -EnableDebug Deep Troubleshooting Dump (Update-TierModelMembership.ps1)

**Status:** CODE AUTHORED -- awaiting lab validation by coordinator

### Deliverables
- `optional/Update-TierModelMembership.ps1` -- -EnableDebug fully implemented (version 1.6.0)

### Key Changes

#### Per-run CorrelationId
- `$script:CorrelationId = [guid]::NewGuid()` generated once per run, before any logging or debug init.
- Embedded in the debug filename, the debug log header, every Write-DebugLog line, and both the run-start and run-end Write-Log messages.
- Allows cross-referencing the change log (-EnableLogging) and the debug dump for the same run.

#### Write-DebugLog function
- Writes timestamped, CorrelationId-tagged, structured lines (key=value pairs via -Data hashtable).
- No-op when -EnableDebug is off (`if (-not $script:DebugFilePath) { return }` -- zero overhead, zero output).
- NOT Start-Transcript (too noisy, per plan section 16.2).

#### Initialize-Debug function (hardening from plan section 17 medium findings)
- Dir: `%ProgramData%\TierModel\Debug` (SEPARATE from Logs dir; created if missing).
- File: `Update-TierModelMembership.debug.<yyyyMMdd-HHmmss>.<CorrelationId>.log`
- **FREE-SPACE precheck**: if target volume has <50 MB free, throws fail-fast before any AD change.
- **PRE-OPEN**: creates/opens the debug file BEFORE any AD write. If file creation fails, throws fail-fast with clear message -- no silent fallback.
- **BOUNDED RETENTION** (triple-cap pruning at init):
  - Age: deletes files older than 7 days.
  - Count: keeps at most 30 most-recent files.
  - Size: caps total directory size at 200 MB, deleting oldest beyond the cap.

#### Instrumentation points (26 Write-DebugLog calls)
- **Run lifecycle**: run-started (with DC/domain/PS-version/switches/exclusion config), switches-resolved, run-completed (with total elapsed ms), fatal-error (with stack trace).
- **Config resolution**: Resolve-OuDn, Resolve-GroupSam, Resolve-PolicyName each log the resolved value.
- **Built-in exclusions**: each exclusion account logged during init; each account checked in Phase 1 with result (not-found / has-policy+clear / no-policy+correct).
- **Per-phase timing**: Stopwatch start/stop with elapsed ms logged for Phase 1 and every reconciliation function.
- **Per-object in Invoke-TierReconciliation**: sAMAccountName, DN, BuiltInExcluded, CustomerExcluded, ExclAttrValue, CurrentPolicy vs DesiredPolicy, PolicyAction (assign/clear/excluded-no-policy/already-current/no-policy-configured), GroupAction (add/skip-excluded/already-member).
- **Per-object in Invoke-Tier2Operators**: adds IsOp/IsLDO/Role classification; logs skip-eud with reason; operator decisions with full exclusion + policy + group tracking.
- **Per-object in Invoke-Tier2Eud**: adds IsOp/IsLDO/Role classification; logs skip-operator with reason; EUD decisions with policy tracking (GroupAction=N/A since LDO is customer-managed).

#### -WhatIf compatibility
- Debug tracking variables are set BEFORE ShouldProcess, recording the DECISION (not whether it executed). With -WhatIf, the debug file documents what WOULD have changed.

#### -EnableLogging verification
- Initialize-Logging and Write-Log are UNCHANGED (no regression).
- Run-start and run-end Write-Log messages now include CorrelationId for cross-referencing with debug.
- Change log entries (policy assigned/cleared, group added) are all preserved.

### Design decisions
- Debug and Logging use SEPARATE dirs (`%ProgramData%\TierModel\Debug` vs `\Logs`) -- both can be on simultaneously.
- Tracking variables ($debugPolicyAction, $debugGroupAction) are simple string assignments added at each decision branch; one Write-DebugLog per object at the end captures the full decision summary. Overhead when -EnableDebug is off is negligible (a few string assignments, no I/O).
- Initialize-Debug is called AFTER Assert-Preflight (needs validated DC) but BEFORE Phase 1 (first AD write). A debug-file failure aborts the entire run.

---

## 2026-08-29 -- Milestone 6: Tier 2 Operators/EUD Account Pair (Update-TierModelMembership.ps1)

**Status:** CODE AUTHORED -- awaiting lab validation by coordinator

### Deliverables
- `optional/Update-TierModelMembership.ps1` -- Invoke-Tier2Operators + Invoke-Tier2Eud implemented (version 1.5.0, all 15 switches complete)
- `.research/auth-silos/lab/Setup-Tier2AccountsLab.ps1` -- idempotent lab-data setup for the Tier 2 Operators/EUD account pair

### Key Changes

#### Invoke-Tier2Operators (dedicated function, not Invoke-TierReconciliation)
- Enumerates ALL user objects in `Tier 2 Accounts` OU (Subtree).
- Builds two DN HashSets from current Tier2Operators and Tier2LocalDeviceOperators group members.
- Classification per user:
  - EUD (isLDO AND NOT isOp): SKIP (handled by -Tier2Eud)
  - OPERATOR (all others, including both-groups and no-group): process
- Policy: assigns `*- Tier 2 Authentication Policy` via Set-TmObjectAuthPolicy. Exclusion APPLIES (skip excluded; clear policy from excluded operator that has one).
- Group: adds to Tier2Operators if not already a member. Exclusion does NOT apply (all tier users are operators, matching Tier 0/1 behavior).
- Fail-closed: policy FIRST, then group.

#### Invoke-Tier2Eud (dedicated function)
- Enumerates ALL user objects in `Tier 2 Accounts` OU (same OU as Operators).
- Same two DN HashSets for classification.
- Only processes pure-LDO users (isLDO AND NOT isOp). All others skipped.
- Policy: assigns `*- Tier 2 EUD Authentication Policy`. Exclusion APPLIES.
- NO group add ever -- the script never writes to Tier2LocalDeviceOperators (LDO membership is customer-managed).
- Single-valued msDS-AssignedAuthNPolicy interaction: a user transitioning from pure-LDO to both-groups will have their EUD policy overwritten by the Tier 2 operator policy on the next -Tier2Operators run. Correct: operator wins.

#### Why NOT Invoke-TierReconciliation
The existing reusable function assumes one-OU-to-one-group-plus-policy. The Tier 2 Operators/EUD pair breaks this:
- SAME OU, TWO policies, TWO target groups, user-level classification by a THIRD group (LDO).
- -Tier2Eud does NO group add at all.
- Exclusion semantics differ per step (policy vs group) and per function.
- Forcing this into Invoke-TierReconciliation would require many special-case parameters, defeating its simplicity. Dedicated functions reuse the same helpers (Set-TmObjectAuthPolicy, Clear-TmObjectAuthPolicy, Test-IsBuiltInExcluded, Test-IsCustomerExcluded, Write-Log, -Server $script:PreferredDc) for consistency.

#### Aggregate Wiring
- -AllTier2 resolves to: Tier2Operators, Tier2Eud, Tier2ServiceActt, Tier2PawDevices, Tier2EudDevices.
- -All resolves to AllTier0 + AllTier1 + AllTier2 (all 15 switches).
- Tier2Operators is before Tier2Eud in both $allGranular and $tier2Granular arrays (mandatory Operators-first order).
- Classification uses group-membership snapshot, so candidate sets are disjoint and order-independent in practice, but Operators-first is maintained for safety.

#### Truth Table Verification
| isOp | isLDO | -Tier2Operators does                      | -Tier2Eud does          |
|------|-------|-------------------------------------------|-------------------------|
| No   | No    | Assigns T2 policy + adds to Tier2Operators | Skips (not LDO)         |
| Yes  | No    | Assigns T2 policy (already in group)       | Skips (not LDO)         |
| No   | Yes   | Skips (pure LDO)                           | Assigns T2 EUD policy   |
| Yes  | Yes   | Assigns T2 policy (already in group)       | Skips (isOp=true)       |
With exclusion (No/No + excluded): NO policy, but STILL added to Tier2Operators group.

#### Lab Script (Setup-Tier2AccountsLab.ps1)
- 10 users t2op01..10 in Tier2Operators (expect T2 policy)
- 10 users t2ldo01..10 in Tier2LocalDeviceOperators ONLY (expect T2 EUD policy)
- 10 users t2new01..10 with NO group; t2new09/10 excluded (expect default->operator T2 policy + added to Tier2Operators; excluded pair -> no policy but still added to group)
- 2 users t2both01..02 in BOTH groups (expect operator wins -> T2 policy)
- -Reset: clears msDS-AssignedAuthNPolicy from all test users, removes t2new* from Tier2Operators (script-added); leaves pre-staged fixture memberships intact
- -Remove: deletes all test users
- Uses trailing-digit index extraction: [int]([regex]::Match($name, '\d+$').Value)
- Expected counts: 20 operator policy, 10 EUD policy, 2 no-policy, 10 new Tier2Operators members

### Learnings
- The LDO classification approach (two HashSets, per-user predicate) was the cleanest way to disambiguate Operator vs EUD from a single OU.
- Operator-wins semantics for single-valued msDS-AssignedAuthNPolicy are naturally enforced by the Operators-first execution order and the classification predicate (both-groups -> operator, not EUD).
- A dedicated function per complex switch (rather than stretching Invoke-TierReconciliation) keeps the code simple and auditable. The reusable helpers (Set-TmObjectAuthPolicy, exclusion tests, Write-Log, -Server pattern) provide consistency without the complexity of a heavily parameterized generic function.
- New no-group users defaulting to OPERATOR is the fail-secure choice (OQ-1 resolution): they get the restrictive Tier 2 operator policy immediately. Customer must explicitly add to LDO to make a user EUD.
- The script NEVER adds to Tier2LocalDeviceOperators. LDO membership is a customer decision that determines the user's role.
- All 15 granular switches are now implemented. The script is feature-complete for v1.

---

## 2026-08-29 -- Milestone 5: Tier 2 Simple (Update-TierModelMembership.ps1)

**Status:** CODE AUTHORED -- awaiting lab validation by coordinator

### Deliverables
- `optional/Update-TierModelMembership.ps1` -- 3 simple Tier 2 functions implemented (version 1.4.0)
- `.research/auth-silos/lab/Setup-Tier2SimpleLab.ps1` -- idempotent lab-data setup for all 3 simple Tier 2 switches

### Key Changes

#### Three Simple Tier 2 Functions Implemented (mechanical swap from Tier 0/1)
Each mirrors its Tier 0/1 counterpart exactly, changing only the tier-specific config values:

- **Invoke-Tier2PawDevices**: source `Tier 2 PAW Devices` OU (OU=Tier 2 PAW Devices,OU=Tier 2,OU=Tier Model Administration,<domainDN>), target `Tier2PAWDevices` group, no policy, filter `(objectClass=computer)`. Same as Tier 0/1 PAW Devices.
- **Invoke-Tier2ServiceActt**: source `Tier 2 Service Accounts` OU (OU=Tier 2 Service Accounts,OU=Tier 2,OU=Tier Model Administration,<domainDN>), target `Tier2ServiceAccounts` group, policy `*- Tier 2 Authentication Policy`, LDAP filter for user+gMSA+dMSA+sMSA, `ApplyExclusionToGroup=$true`. Same as Tier 0/1 ServiceActt.
- **Invoke-Tier2EudDevices**: source `Tier 2 End-User Devices` OU (OU=Tier 2 End-User Devices,<domainDN>), target `Tier2EUDDevices` group, no policy, filter `(objectClass=computer)`, `ExcludeChildOuDn` = `Disabled End-User Devices` DN. Same child-OU exclusion pattern as MemberServers.

#### Remaining Stubs
- `Invoke-Tier2Operators` and `Invoke-Tier2Eud` remain stubbed -- deferred to next milestone (complex Tier 2 Operators/EUD account pair with Tier2LocalDeviceOperators disambiguation).

#### OU DN Resolution Verification (Tier 2)
- `Tier 2 PAW Devices`: config path=`OU=Tier 2,OU=Tier Model Administration` -> resolves to `OU=Tier 2 PAW Devices,OU=Tier 2,OU=Tier Model Administration,<domainDN>`. Correct.
- `Tier 2 Service Accounts`: config path=`OU=Tier 2,OU=Tier Model Administration` -> resolves to `OU=Tier 2 Service Accounts,OU=Tier 2,OU=Tier Model Administration,<domainDN>`. Correct.
- `Tier 2 End-User Devices`: config path=`{{DOMAIN_DN}}` -> resolves to `OU=Tier 2 End-User Devices,<domainDN>` (domain root). Correct.
- `Disabled End-User Devices`: config path=`OU=Tier 2 End-User Devices` -> resolves to `OU=Disabled End-User Devices,OU=Tier 2 End-User Devices,<domainDN>` (child). Correct.
- All 4 OU entries exist in tiermodel-ous.json. All 3 group entries exist in tiermodel-groups.json. Policy `*- Tier 2 Authentication Policy` exists in tiermodel-authsilos.json.
- Built-in exclusion: `svc-t2euddomainjoin` is in tiermodel-users.json built-in exclusion list (lives in Tier 2 Service Accounts OU). Confirmed.

#### Lab Script
- Single script `Setup-Tier2SimpleLab.ps1` covers all 3 simple Tier 2 switches
- Tier 2 Service Accounts OU: 10 users (svc-t2-u01..10) + 10 gMSAs (svc-t2-g01..10) + dMSA attempt (svc-t2-d01..10), excluded indices 9/10 each
- Tier 2 PAW Devices OU: 5 computers (t2paw01..05)
- Tier 2 End-User Devices OU (domain root): 5 computers (t2eud01..05), OU created if missing
- Disabled End-User Devices OU (child): 3 computers (t2eudx01..03), OU created if missing
- Uses TRAILING-DIGIT index extraction: `[int]([regex]::Match($name, '\d+$').Value)` to avoid the Tier 1 lab bug where `[int]($sam -replace '[^0-9]','')` strips ALL digits (including tier digit)
- Reset mode: clears all group membership + policy for all test objects
- Remove mode: deletes all test objects
- KDS root key: reuses if present, creates with past effective time if absent
- Expected-state summary and verification commands for all 3 switches

### Learnings
- Tier 2 simple switches are a true mechanical swap from Tier 0/1 -- identical `Invoke-TierReconciliation` calls with different config names. No logic changes required.
- `Tier 2 End-User Devices` OU is at the domain root (path=`{{DOMAIN_DN}}`), matching the Member Servers pattern.
- `Disabled End-User Devices` child OU exclusion uses the same `ExcludeChildOuDn` mechanism as Staging OU exclusion in MemberServers.
- Lab index extraction bug: the old pattern `[int]($sam -replace '[^0-9]','')` strips ALL digits including the tier digit (e.g., `svc-t2-u09` -> `209`, not `9`). Fixed pattern: `[int]([regex]::Match($name, '\d+$').Value)` extracts only trailing digits.
- Script now targets PowerShell 7.0+ (pwsh.exe). Windows PowerShell 5.1 is blocked via `#requires -Version 7.0` (first line) plus a belt-and-suspenders version guard in Assert-Preflight. The TierModel deployment already requires PS7. Scheduled task action must use pwsh.exe, not powershell.exe.

---

## 2026-08-29 -- Milestone 4: Tier 1 (Update-TierModelMembership.ps1)

**Status:** CODE AUTHORED -- awaiting lab validation by coordinator

### Deliverables
- `optional/Update-TierModelMembership.ps1` -- All 5 Tier 1 functions implemented (version 1.3.0)
- `.research/auth-silos/lab/Setup-Tier1MembershipLab.ps1` -- combined idempotent lab-data setup for all Tier 1 switches

### Key Changes

#### Five Tier 1 Functions Implemented (mechanical swap from Tier 0)
Each mirrors its Tier 0 counterpart exactly, changing only the tier-specific config values:

- **Invoke-Tier1Operators**: source `Tier 1 Accounts` OU (OU=Tier 1 Accounts,OU=Tier 1,OU=Tier Model Administration,<domainDN>), target `Tier1Operators` group, policy `*- Tier 1 Authentication Policy`, filter `(objectClass=user)`, `ApplyExclusionToGroup=$false`.
- **Invoke-Tier1ServiceActt**: source `Tier 1 Service Accounts` OU (OU=Tier 1 Service Accounts,OU=Tier 1,OU=Tier Model Administration,<domainDN>), target `Tier1ServiceAccounts` group, policy `*- Tier 1 Authentication Policy`, LDAP filter for user+gMSA+dMSA+sMSA, `ApplyExclusionToGroup=$true`.
- **Invoke-Tier1PawDevices**: source `Tier 1 PAW Devices` OU (OU=Tier 1 PAW Devices,OU=Tier 1,OU=Tier Model Administration,<domainDN>), target `Tier1PAWDevices` group, no policy, filter `(objectClass=computer)`.
- **Invoke-Tier1MemberServers**: source `Tier 1 Member Servers` OU (OU=Tier 1 Member Servers,<domainDN>), target `Tier1MemberServers` group, no policy, filter `(objectClass=computer)`, `ExcludeChildOuDn` = `Tier 1 Server Staging` DN.
- **Invoke-Tier1Staging**: source `Tier 1 Server Staging` OU (OU=Tier 1 Server Staging,OU=Tier 1 Member Servers,<domainDN>), target `Tier1MemberServers` group (same as MemberServers), no policy, filter `(objectClass=computer)`.

#### OU DN Resolution Verification (Tier 1)
- `Tier 1 Accounts`: config path=`OU=Tier 1,OU=Tier Model Administration` -> resolves to `OU=Tier 1 Accounts,OU=Tier 1,OU=Tier Model Administration,<domainDN>`. Correct.
- `Tier 1 Service Accounts`: config path=`OU=Tier 1,OU=Tier Model Administration` -> resolves to `OU=Tier 1 Service Accounts,OU=Tier 1,OU=Tier Model Administration,<domainDN>`. Correct.
- `Tier 1 PAW Devices`: config path=`OU=Tier 1,OU=Tier Model Administration` -> resolves to `OU=Tier 1 PAW Devices,OU=Tier 1,OU=Tier Model Administration,<domainDN>`. Correct.
- `Tier 1 Member Servers`: config path=`{{DOMAIN_DN}}` -> resolves to `OU=Tier 1 Member Servers,<domainDN>` (domain root). Correct. Mirrors Tier 0.
- `Tier 1 Server Staging`: config path=`OU=Tier 1 Member Servers` -> resolves to `OU=Tier 1 Server Staging,OU=Tier 1 Member Servers,<domainDN>`. Correct. Mirrors Tier 0.
- All 5 OU entries exist in tiermodel-ous.json. All 4 group entries exist in tiermodel-groups.json. Policy `*- Tier 1 Authentication Policy` exists in tiermodel-authsilos.json.
- Built-in exclusion: `svc-t1srvdomainjoin` is in tiermodel-users.json built-in exclusion list (lives in Tier 1 Service Accounts OU). Confirmed.

#### Lab Script (Combined)
- Single script `Setup-Tier1MembershipLab.ps1` covers all 5 Tier 1 switches
- Tier 1 Accounts OU: 10 users (t1-user01..10, 09/10 excluded)
- Tier 1 Service Accounts OU: 10 users (svc-t1-u01..10) + 10 gMSAs (svc-t1-g01..10) + dMSA attempt (svc-t1-d01..10), excluded indices 9/10 each
- Tier 1 PAW Devices OU: 5 computers (t1paw01..05)
- Tier 1 Member Servers OU (domain root): 5 computers (t1srv01..05), OU created if missing
- Tier 1 Server Staging OU (child of Member Servers): 5 computers (t1stg01..05), OU created if missing
- Reset mode: clears all group membership + policy for all test objects
- Remove mode: deletes all test objects
- KDS root key: reuses if present, creates with past effective time if absent
- Expected-state summary and verification commands for all 5 switches

### Learnings
- Tier 1 is a true mechanical swap from Tier 0 -- identical `Invoke-TierReconciliation` calls with different config names. No logic changes required.
- OU nesting pattern is identical: Accounts/ServiceAccounts/PAWDevices under `OU=Tier 1,OU=Tier Model Administration`, Member Servers at domain root, Server Staging as child of Member Servers.
- Combined lab script is more efficient than 3 separate scripts (Tier 0 used 3). Single -Reset/-Remove handles all object types.
- PowerShell `$var:` in double-quoted strings is parsed as a scope-qualified variable reference. Use `${var}:` to delimit the variable name when followed by a colon.

---

## 2026-08-29 -- Milestone 3: Tier 0 Computers (Update-TierModelMembership.ps1)

**Status:** CODE AUTHORED -- awaiting lab validation by coordinator

### Deliverables
- `optional/Update-TierModelMembership.ps1` -- Invoke-Tier0PawDevices, Invoke-Tier0MemberServers, Invoke-Tier0Staging implemented (version 1.2.0)
- `.research/auth-silos/lab/Setup-Tier0ComputersLab.ps1` -- idempotent lab-data setup for computers

### Key Changes

#### Three Computer Functions Implemented
- All three use `Invoke-TierReconciliation` with `PolicyName=$null`, `ObjectFilter='(objectClass=computer)'`, `ApplyExclusionToGroup=$false`
- **Invoke-Tier0PawDevices**: source `Tier 0 PAW Devices` OU (under Tier Model Administration), target `Tier0PAWDevices` group. Subtree search, no child-OU exclusion.
- **Invoke-Tier0MemberServers**: source `Tier 0 Member Servers` OU (domain root), target `Tier0MemberServers` group. Subtree search with `ExcludeChildOuDn` set to the resolved `Tier 0 Server Staging` DN. Post-filter in `Invoke-TierReconciliation` excludes objects whose DN ends with the Staging OU suffix.
- **Invoke-Tier0Staging**: source `Tier 0 Server Staging` OU (child of Member Servers at domain root), target `Tier0MemberServers` group (same group as MemberServers). Subtree search.

#### OU DN Resolution Verification
- `Tier 0 Member Servers`: config path=`{{DOMAIN_DN}}` -> resolves to `OU=Tier 0 Member Servers,DC=tierlab,DC=internal` (domain root). Correct.
- `Tier 0 Server Staging`: config path=`OU=Tier 0 Member Servers` (relative) -> resolves to `OU=Tier 0 Server Staging,OU=Tier 0 Member Servers,DC=tierlab,DC=internal`. Correct.
- `Tier 0 PAW Devices`: config path=`OU=Tier 0,OU=Tier Model Administration` (relative) -> resolves to `OU=Tier 0 PAW Devices,OU=Tier 0,OU=Tier Model Administration,DC=tierlab,DC=internal`. Correct.
- No config gaps found. All three OU entries exist in tiermodel-ous.json. Both group entries (Tier0PAWDevices, Tier0MemberServers) exist in tiermodel-groups.json.

#### Lab Script
- Creates 15 computer objects: 5 in PAW Devices (t0paw01..05), 5 in Member Servers (t0srv01..05), 5 in Server Staging (t0stg01..05)
- Ensures Member Servers and Server Staging OUs exist at domain root (creates if missing)
- Reset mode: removes test computers from both groups
- Remove mode: deletes test computer objects
- Expected-state summary and verification commands printed

### Learnings
- OU DN resolution for root-level OUs: config uses `{{DOMAIN_DN}}` as path for root-level OUs (Member Servers, End-User Devices), while nested OUs use relative OU chains. Resolve-OuDn handles both by checking if path starts with `DC=`.
- Child-OU exclusion mechanics: the `ExcludeChildOuDn` parameter in `Invoke-TierReconciliation` works via DN suffix matching. A computer in `OU=Tier 0 Server Staging,OU=Tier 0 Member Servers,DC=...` has a DN that ends with the Staging OU DN, so it is post-filtered out when enumerating from the parent Member Servers OU with Subtree scope.
- Computer objects have no auth policy assignment -- the device GROUP membership is what feeds the silo SDDL. Exclusions never apply to computers.
- Computer sAMAccountNames have a `$` suffix (auto-appended by AD). New-ADComputer -SamAccountName should include the `$`.
- Tier 0 Member Servers and Tier 0 Server Staging OUs may not exist from the base Deploy-TierModel.ps1 run -- they are in the config but the deploy script may not create root-level OUs. The lab script ensures they exist.

---

## 2026-08-29 -- Milestone 2: Tier 0 Service Accounts (Update-TierModelMembership.ps1)

**Status:** CODE AUTHORED -- awaiting lab validation by coordinator

### Deliverables
- `optional/Update-TierModelMembership.ps1` -- Invoke-Tier0ServiceActt implemented + type-agnostic policy refactor
- `.research/auth-silos/lab/Setup-Tier0ServiceAcctLab.ps1` -- idempotent lab-data setup for service accounts

### Key Changes

#### Type-Agnostic Policy Refactor (affects Operators path too)
- Replaced `Set-ADUser -AuthenticationPolicy $name` with `Set-ADObject -Replace @{ 'msDS-AssignedAuthNPolicy' = $dn }` for policy assignment
- Replaced `Set-ADUser -Clear 'msDS-AssignedAuthNPolicy'` with `Set-ADObject -Clear 'msDS-AssignedAuthNPolicy'` for policy removal
- Extracted two helpers: `Set-TmObjectAuthPolicy` and `Clear-TmObjectAuthPolicy` (use Set-ADObject internally)
- Helpers used in both `Invoke-TierReconciliation` loop AND `Invoke-BuiltInExclusionEnforcement`
- `Invoke-TierReconciliation` now resolves the policy DN at validation time (not just name) and passes the DN to the helper
- **Operators path preserved:** same LDAP filter `(objectClass=user)`, same `ApplyExclusionToGroup=$false`, same idempotency check (CN extraction from DN for comparison). Set-ADObject works identically to Set-ADUser for user objects.

#### Service Accounts Implementation
- LDAP filter: `(|(&(objectClass=user)(objectCategory=person))(objectClass=msDS-GroupManagedServiceAccount)(objectClass=msDS-DelegatedManagedServiceAccount)(objectClass=msDS-ManagedServiceAccount))`
- objectCategory=person in the user clause excludes computer objects from matching
- gMSA/dMSA/sMSA classes absent from schema simply return zero results (safe; no error)
- `ApplyExclusionToGroup = $true` -- both group and policy respect exclusions
- Same policy (*- Tier 0 Authentication Policy) shared with Operators

#### Lab Script
- KDS root key: checks `Get-KdsRootKey`; if absent, creates with `Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10))` for immediate lab use. This is domain-persistent -- logged clearly.
- Creates 10 users (svc-t0-u01..u10), 10 gMSAs (svc-t0-g01..g10), attempts 10 dMSAs (svc-t0-d01..d10, skips if DFL < 2025)
- 2 of each type marked excluded (indices 9, 10) via adminDescription=TierModelExclude
- Reset/Remove modes use Get-ADObject/Set-ADObject/Remove-ADObject (type-agnostic)
- Expected-state summary accounts for svc-pawdomainjoin (built-in excluded, lives in this OU)

### Learnings
- `Set-ADUser -AuthenticationPolicy` only works on user objects -- gMSA/dMSA/sMSA need `Set-ADObject -Replace @{ 'msDS-AssignedAuthNPolicy' = <policyDN> }` instead
- `Set-ADObject` with `-Replace`/`-Clear` on msDS-AssignedAuthNPolicy works uniformly for all security principal types
- The LDAP filter for mixed account types must use `(objectCategory=person)` with `(objectClass=user)` to exclude computers, since sMSA inherits from computer which inherits from user
- gMSA creation needs a KDS root key; `Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10))` makes it immediately usable in a lab (normally requires 10-hour propagation delay)
- dMSA (msDS-DelegatedManagedServiceAccount) requires Windows Server 2025 DFL; schema queries return zero results on older DFLs (safe, not an error)
- gMSA sAMAccountNames have a `$` suffix (auto-appended); built-in exclusion matching is by sAMAccountName so these never collide with the plain-user built-in exclusion list
- CRITICAL: Windows PowerShell 5.1 without BOM reads .ps1 as ANSI. ANY non-ASCII byte (> 0x7F) causes ParserError. Always verify with a byte-scan.

---

## 2026-08-29 -- Milestone 1: Tier 0 Operators (Update-TierModelMembership.ps1)

**Status:** LAB-VALIDATED -- working

### Deliverables
- `optional/Update-TierModelMembership.ps1` — shared scaffold + Tier 0 Operators implemented
- `.research/auth-silos/lab/Setup-Tier0OperatorsLab.ps1` — idempotent lab-data setup

### Scaffold Shape
- Full param block: 4 aggregates (All/AllTier0/AllTier1/AllTier2) + 15 granular switches + ExclusionAttribute/ExclusionValue + EnableLogging + reserved EnableDebug/LogEventID
- Switch resolution: no-switch → All → AllTierX → granular. Ordered list preserves mandatory Tier2Operators-before-Tier2Eud sequence
- Preflight: AD module import → writable non-RODC DC → dNSHostName identity → GC check → ADWS probe
- Config loading: standalone JSON reader (4 files), `{{DOMAIN_DN}}` resolved via Get-ADDomain
- Built-in exclusions: HashSet from tiermodel-users.json (3 svc accounts), always enforced
- Customer exclusions: parameterized attribute/value, validated at startup
- Logging: %ProgramData%\TierModel\Logs, one file per run, 7-day retention

### Reusable Per-Tier Function Signature
```powershell
Invoke-TierReconciliation
    -SwitchName        [string]      # Display name for logging
    -SourceOuDn        [string]      # Source OU distinguished name
    -TargetGroupSam    [string]      # Target group sAMAccountName
    -PolicyName        [string]      # Auth policy name ($null if no policy)
    -ObjectFilter      [string]      # LDAP filter (default: (objectClass=user))
    -SearchScope       [string]      # Subtree/OneLevel (default: Subtree)
    -ApplyExclusionToGroup [bool]    # $true for ServiceAccounts, $false for Operators
    -ExcludeChildOuDn  [string]      # Child OU to post-filter exclude
```

### Key Implementation Decisions
- **Fail-closed ordering:** policy assigned FIRST, then group add. Error stops the run with account NOT in group
- **Policy assignment:** `Set-ADUser -AuthenticationPolicy` (clear: `Set-ADUser -Clear 'msDS-AssignedAuthNPolicy'`)
- **Policy idempotency:** AD stores `msDS-AssignedAuthNPolicy` as a DN; script extracts CN via regex `'^CN=(.+?),'` for comparison
- **DC targeting:** `$script:PreferredDc` set once from `Get-ADDomainController` .HostName; passed to every AD cmdlet via `-Server`
- **Group membership cache:** `HashSet<string>` (DN, OrdinalIgnoreCase) per switch for O(1) membership checks
- **Exclusion predicate:** universal `Test-IsExcludedFromPolicy` combines built-in + customer checks; built-in also has Step 0 enforcement
- **Stub architecture:** each future tier/switch has a named `Invoke-TierXYZ` function stub; dispatch hashtable preserves execution order
- **Config resolution:** `Resolve-OuDn`, `Resolve-GroupSam`, `Resolve-PolicyName` look up by display name in JSON

### Learnings
- `Set-ADUser -AuthenticationPolicy` accepts the policy CN (name), not the DN — works on WS2012R2+ AD module
- AD returns `msDS-AssignedAuthNPolicy` as a full DN (`CN=*- Tier 0...,CN=AuthN Policies,...`); must normalize for comparison
- `Get-ADDomainController -Identity $env:COMPUTERNAME` resolves the local DC; `.HostName` gives the FQDN (safe for disjoint namespaces)
- Config `path` field in tiermodel-ous.json is the PARENT path, not the full DN; construct DN as `OU=<name>,<path>`
- Lab script uses `adminDescription` = `TierModelExclude` per Joel's §18 decision

---

## 2026-08-27 — Design Plan: Update-TierModelMembership.ps1

**Status:** 📋 DESIGN PLAN WRITTEN — awaiting Joel review, no code written

### Scope
Unified reconciliation script (`optional/Update-TierModelMembership.ps1`) replacing 6 legacy per-tier scripts. Two mechanisms: group membership (additive) + auth policy assignment (enforcing). 15 granular switches with tier-level aggregates. Config-driven (no hardcoded DNs/names).

### Key Design Decisions
- **Never edits SDDL** — group membership is what keeps the create-once SDDL current
- **msDS-AssignedAuthNPolicy is single-valued** — drives the Tier 2 Operator-vs-EUD truth table (operator wins conflicts)
- **Built-in exclusions** for 3 domain-join svc accounts (always active, policy removed if found)
- **Customer exclusions** via configurable AD attribute/value pair
- **Group membership additive-only in v1** (no removal); policy assignment enforced (assign + remove)
- **Target PS 5.1** — no PS7 syntax; Get-ADObject with LDAP filter for MSA/gMSA/dMSA (avoid Get-ADServiceAccount dependency)
- **Tier2Operators runs before Tier2Eud** — mandatory execution order for single-valued policy resolution

### Open Questions (6)
1. **OQ-1:** Tier 2 new-user default — operator or LDO? Script can't guess intent; recommended default-to-operator
2. **OQ-2:** Stamp exclusion marker on built-in accounts? Recommended: no
3. **OQ-3:** Group membership additive-only vs enforce? Recommended: additive-only v1
4. **OQ-4:** Staging OU SearchScope — recommended Subtree
5. **OQ-5:** Protected Users group — recommended out of scope v1
6. **OQ-6:** Multi-domain forest — recommended single-domain v1

### Decided
- **Execution model:** DC + local scheduled task + SYSTEM context (recommended). GPO/SYSVOL hijack risk does NOT apply to local scheduled tasks. Script-integrity hardening = ACL-locked local path + Authenticode code signing. gMSA-on-management-host is an optional alternative for orgs that want automation off-DC, but NOT the primary recommendation.

### Learnings
- OU structure is non-uniform: Accounts/SvcAccounts/PAW under `OU=Tier Model Administration`; Member Servers and End-User Devices at domain root
- `Tier2LocalDeviceOperators` membership is customer-curated, not managed by this script — EUD status is by group membership, not OU
- Legacy scripts (`Update-Tier0MemberServers.ps1` etc.) DO remove non-OU members from groups — new script deliberately does NOT in v1 for safety
- `msDS-DelegatedManagedServiceAccount` (dMSA) requires Windows Server 2025 DFL — LDAP filter includes it but must handle zero results gracefully
- Existing `ScheduleTask-GPO/` and `ScheduleTask-Local/` directories contain XML task definitions — new script's scheduling model should align

### Plan Location
`optional/Update-TierModelMembership.PLAN.md` (uncommitted draft)

---

## 2026-08-27 — Amendment: Computer-Membership-Only + Remove exemptAccounts

**Status:** ✅ COMPLETE — 6 files changed; ready for lab validation

### Scope Reduction: Silos govern computers, not accounts

Tier admin account groups are always empty on a TM deploy. Auditing/assigning user silo membership is a no-op and adds complexity for no operational benefit. Removed entirely.

**Config (`tiermodel-authsilos.json`):**
- Removed top-level `exemptAccounts` block (3 domain-join service accounts + RID-500 well-known-account entry)
- Removed `memberAccountGroups` array from ALL 4 silos
- Updated `comment` fields to remove VPN-exclusion/account rationale text
- Updated top-level comment to state computer-only scope

**Deploy (`Set-TierModelAuthSiloMembership`, `Get-TierModelAuthSiloMembershipFd`):**
- Removed entire exemption setup (configuredExempts, RID-500 resolution, exemptSet HashSet, ExemptAccounts log)
- Removed account-group expansion loop (`foreach memberAccountGroups`)
- Removed exemptSet.Contains check from computer-group expansion
- `$allPrincipals = @($accountsToAssign) + @($computersToAssign)` → `@($computersToAssign)`
- Membership summary: removed "N exempt-skipped" → just "N assigned, N already-assigned"
- `TotalExempt` removed from MembershipFd Summary

**Audit (`Test-TierModelAuthSilo`, `Test-TierModelAuthSiloPrerequisite`):**
- Removed exemption setup block from Test-TierModelAuthSilo (no exemptSet)
- Removed memberAccountGroups expansion loop; computer-only membership subset check retained
- Check 5 comment: "Computer membership (subset check — computer groups only)"
- Test-TierModelAuthSiloPrerequisite: removed `foreach ($silo.memberAccountGroups)` section

**Config loading (`Get-TierModelConfig`):**
- Removed `authSilosExemptAccounts` property from config object

### Final per-silo config shape
```json
{
  "name": "*- Tier 0 Admins Authentication Silo",
  "description": "...",
  "policy": "*- Tier 0 Admins Authentication Policy",
  "memberComputerGroups": ["Domain Controllers", "Read-only Domain Controllers", "Tier0MemberServers", "Tier0PAWDevices"],
  "enforce": false,
  "protectedFromAccidentalDeletion": true,
  "comment": "..."
}
```

No `memberAccountGroups`. No `exemptAccounts`.

---



**Status:** ✅ COMPLETE — 9 files changed; ready for lab validation

### Create-Once / Never-Modify Deploy Model

**Rule**: Authentication Policies and Silos are created ONCE by deploy. If an object already exists in AD, deploy leaves it completely untouched regardless of any property difference. No drift detection, no update actions, ever. Modifications to existing objects are an out-of-band operation.

**Changes:**
- `Get-TierModelAuthPolicyFd`: removed all drift detection (SID resolution, SDDL comparison, PFAD check, TGT check, Enforce check). Now: exists in AD → AlreadyExists; not in AD → resolve SIDs + build SDDL → CreateAuthPolicy.
- `Get-TierModelAuthSiloFd`: same. Removed UpdateAuthSilo. Now: exists → AlreadyExists; not in AD → CreateAuthSilo.
- `New-TierModelAuthPolicy`: removed all UpdateAuthPolicy handling. Create-only. Returns `CreatedNames [string[]]`.
- `New-TierModelAuthSilo`: removed all UpdateAuthSilo handling. Create-only. Returns `CreatedSiloNames [string[]]`.

### Create-Once Membership Model

Silo membership is assigned ONLY for silos created in this run. Silos that already existed are never touched by membership assignment.

**Changes:**
- `New-TierModelAuthSilo`: returns `CreatedSiloNames` — the names of silos actually created.
- `Set-TierModelAuthSiloMembership`: added `[string[]]$OnlyForSilos` — when bound, only processes silos in the list (empty list = process nothing; unbound = process all for backwards compat).
- `Get-TierModelAuthSiloMembershipFd`: same `-OnlyForSilos` parameter for plan-mode pending count.
- Deploy wiring: pass `$authSiloResult.CreatedSiloNames` to `-OnlyForSilos`; fully converged runs show 0 membership pending.

### Green-Only Deploy Output (`-ConfirmApply`)
- `✅ Created Authentication Policy: *- Tier 0 Admins Authentication Policy`
- `✅ Created Authentication Policy Silo: *- Tier 0 Admins Authentication Silo`
- `✅ Assigned DC01$ (computer) to silo: *- Tier 0 Admins Authentication Silo`
- `✅ Already deployed — nothing to create` (when all objects already exist)
- Yellow/Red = real problem only. No "X to create, Y to update, Z converged" yellow lines.

### Plan Mode Output (no `-ConfirmApply`)
- `  Auth Policies: all 4 already deployed` (Green) OR `  Auth Policies: 2 to create` (Cyan)
- `  Auth Silos:    all 4 already deployed` (Green) OR `  Auth Silos:    3 to create` (Cyan)
- `  Membership:    0 pending (all silos already deployed)` (Gray) OR `  Membership:    will assign for N new silo(s)` (Cyan)

### Audit Console Cleanup
- `Write-TierModelLog -Level Warning` → `Write-TierModelLog -Level Info` for audit NonCompliant events. Structured log still written to file; `Write-Warning` no longer called → no "WARNING: [timestamp]..." console spam.
- Per-issue display: `❌ NonCompliant — {concise reason}` (one line per issue, Red) instead of `❌ NonCompliant` + multi-line yellow dump.
- SDDL issues name the group, not the SID: `AllowedToAuthenticateFrom: missing required device group: Tier0PAWDevices`
- Silo policy link: `UserAuthenticationPolicy not linked to config policy '...' (not linked)` 
- Added `ℹ️  Enforce state: {state}` below ❌ lines (informational, DarkGray).
- Added `sidToGroupName` map in Test-TierModelAuthPolicy so missing SIDs show as group names.

---



**Status:** ✅ FIXED — 3 files changed + 1 new cmdlet; ready for lab validation

### New Cmdlet: `Get-TierModelAuthSiloMembershipFd`

Read-only membership planner. Builds the exemption set, expands member groups, then for each
expected principal reads:
1. `grantedDns` (silo Members list via `msDS-AuthNPolicySiloMembers`) — Grant step done?
2. `msDS-AssignedAuthNPolicySilo` on the account — Set step done?

A principal is `ALREADY-ASSIGNED` only if BOTH are satisfied; otherwise it is `PENDING`.

Returns `{ Actions (pending only), Summary { TotalPending, TotalAlreadyAssigned, TotalExempt, TotalActions, ExistingCount }, Warnings, Errors, DurationMs }`.

### Fixed: `Set-TierModelAuthSiloMembership` — ShouldProcess ordering

The read-only already-assigned pre-check (`$alreadyGranted` + `$preCheckSiloName` → `$alreadyAssigned`) now runs BEFORE `$PSCmdlet.ShouldProcess()`. Effect:
- **WhatIf mode**: converged principals skip entirely (`continue`); only truly pending principals print `[WhatIf] Would assign`, so WhatIf output is accurate
- **Execution mode**: converged principals skip with `continue` (no ShouldProcess overhead); pending principals go to ShouldProcess → Grant → Set as before
- **Eliminates the redundant inner AD read** in step 2 — `$preCheckSiloName` is reused from the pre-check, saving one `Get-ADUser/Computer` per already-assigned principal

### Fixed: Deploy-TierModel.ps1 plan-mode membership line

Both plan-mode blocks (FullDeployment planning, standalone planning) now call `Get-TierModelAuthSiloMembershipFd` instead of printing a static silo count:
```
# Converged:
  Membership:    0 pending (all assigned)          ← Gray

# Work pending:
  Membership:    3 pending assignment(s)            ← Yellow
```
The pending count is also added to `$deploymentPlan.TotalActions` / `$standaloneDeploymentPlan.TotalActions`, making `Action count: N` in the plan summary consistent: a fully converged re-run shows `Action count: 0`.

### `$alreadyAssigned` logic (matches both cmdlets)
```
$alreadyGranted  = silo's Members list contains account DN
$currentSiloName = msDS-AssignedAuthNPolicySilo → normalize DN to name
$alreadyAssigned = $alreadyGranted AND ($currentSiloName -eq $siloName)
```

---



**Status:** ✅ FIXED — 3 files changed; ready for lab re-validation

### Rule 1: Enforce State — Always Informational, Never Pass/Fail

Both `Test-TierModelAuthPolicy` and `Test-TierModelAuthSilo` now:
- READ the Enforce attribute and expose it as `EnforceState` in every Findings entry: `'audit mode'`, `'ENFORCED'`, or `'unknown'`
- NEVER add it to `$issues` (the array that drives NonCompliant)
- A policy/silo with `Enforce=$true` is **Compliant exactly like** `Enforce=$false`
- The per-object display line now shows `(enforce: <state>)` regardless of pass/fail

### Rule 2: Mandatory-Subset Check (configured ⊆ actual)

**SDDL device groups** (`Test-TierModelAuthPolicy`):
- Uses `Compare-TierModelAuthSddl -RequireSubset` instead of exact-match
- Every CONFIGURED device-group SID must be present → NonCompliant if any are missing
- Extra SIDs in AD beyond config (customer-added custom groups) → allowed, `ExtraDeviceGroups` in Findings (informational display with ℹ️)
- Deploy planner (`Get-TierModelAuthPolicyFd`) still uses exact-match (no `-RequireSubset`) — deploy behavior UNCHANGED

**Silo membership** (`Test-TierModelAuthSilo`):
- Every CONFIGURED member (from group expansion minus exempts) must be in silo Members → NonCompliant if absent (`"Missing from silo Members: <sam> (<dn>)"`)
- Extra members in silo beyond config → allowed, `ExtraMembers` in Findings (informational display with ℹ️), NEVER counted as NonCompliant
- Removed: `$issues += "Unexpected member in silo (not in config groups): ..."` — this exact failure is gone

### `Compare-TierModelAuthSddl` API Change

Added `[switch]$RequireSubset` parameter. All return paths now include `ExtraSids [string[]]`:
- **Default (exact mode)**: sets must be identical; `ExtraSids = @()`
- **RequireSubset mode**: desired ⊆ existing; `ExtraSids = [string[]]` of extras in existing-but-not-desired (informational)

Callers that omit `-RequireSubset` (including `Get-TierModelAuthPolicyFd`) are **unaffected** — exact-match behavior preserved.

### Findings Shape After Refinements

**Test-TierModelAuthPolicy Findings entry:**
```
{ PolicyName, Status, Issues, EnforceState, ExtraDeviceGroups }
```

**Test-TierModelAuthSilo Findings entry:**
```
{ SiloName, Status, Issues, EnforceState, ExtraMembers }
```

### Definitive Compliant / NonCompliant Criteria

**Test-TierModelAuthPolicy** — NonCompliant when:
- Policy absent from AD → `Missing`
- Description differs
- UserTGTLifetimeMins differs (when config is non-null)
- Any CONFIGURED device-group SID absent from AllowedToAuthenticateFrom (`-RequireSubset`)
- ProtectedFromAccidentalDeletion ≠ true

Informational only (never NonCompliant): Enforce state; extra device groups beyond config.

**Test-TierModelAuthSilo** — NonCompliant when:
- Silo absent from AD → `Missing`
- Description differs
- Any of User/Computer/ServiceAuthenticationPolicy link differs
- ProtectedFromAccidentalDeletion ≠ true
- Any CONFIGURED member (account or computer, minus exempts) absent from silo Members

Informational only (never NonCompliant): Enforce state; extra silo members beyond config.

---



**Status:** ✅ IMPLEMENTATION COMPLETE — Deploy + Audit cmdlet sets, 8 public functions, config, lab-ready

### Auth Silos Deployment (2026-08-27)

**8 Public Cmdlets:**
- Get-TierModelAuthPolicy / Get-TierModelAuthPolicyFd — Load and plan auth policies
- Get-TierModelAuthSilo / Get-TierModelAuthSiloFd — Load and plan auth silos
- New-TierModelAuthPolicy — Idempotent create/update (Enforce=$false, PFAD=$true)
- New-TierModelAuthSilo — Idempotent create/update (1:1 policy per silo; all 3 classes same policy)
- Set-TierModelAuthSiloMembership — Idempotent membership (recursive expansion, exemptions, pre-checks)
- Test-TierModelAuthSiloPrerequisite — Dependency gate (group existence)

**Public Helper:**
- Build-TierModelAuthSddl — Constructs Member_of_any (OR-logic) SDDL; never AND-logic

**Key Invariants:**
- SDDL OR-logic: Member_of_any prevents lockout; AND-logic is documented failure mode
- Policies before silos (execution order enforced in Deploy-TierModel)
- Grant then Set for membership (both idempotent via pre-checks)
- RID-500 exemption resolved at runtime for renamed administrator accounts

**Deploy-TierModel Integration:**
- Param: -IncludeAuthSilos (after -IncludeWinLaps)
- Standalone: 3-step execution (policies → silos → membership)
- FullDeployment: Phase 12 planning; policies → silos → membership after audit
- Module v1.3.3, FunctionsToExport updated

**Config:** config/tiermodel-authsilos.json — 4 policies + 4 silos (1:1 mapping), group names resolved at runtime

### Auth Silos Audit (2026-08-27)

**2 Public Audit Cmdlets:**
- Test-TierModelAuthPolicy — Verify policy compliance (existence, Description, TGT lifetime, SDDL via Compare-TierModelAuthSddl, PFAD)
- Test-TierModelAuthSilo — Verify silo compliance (existence, policy links, PFAD, membership validation)

**Return Shape:** TotalChecked / Compliant / Missing / NonCompliant / Errors / Drift / Findings array (consistent with Test-TierModelWinLapsAcl)

**Hard Rule:** Enforce is intentionally NOT checked — audit mode is default; enforcement is a separate lifecycle step

**Audit-TierModel Integration:**
- -IncludeAuthSilos param after -IncludeWinLaps
- Standalone block + FullDeployment results (EntityType: 'Auth Policies' / 'Auth Silos')
- Membership comparison: config-expected vs silo's msDS-AuthNPolicySiloMembers (recursive expansion minus exempts + RID-500)

### SDDL Alias Fix (2026-08-26)

**Bug:** Domain Controllers group (RID 516) stored as SID, read back as SID(DD) alias → false drift on every re-run (Tier 0 only)

**Fix:** New public cmdlet Compare-TierModelAuthSddl
- Extracts domain SID from desired SDDL
- Expands DA/DU/DG/DC/DD aliases to full SIDs in both SDDLs
- Set-based comparison (order-insensitive, case-insensitive)
- Returns { Equal: bool, Reason: string }

**Applied to:** Get-TierModelAuthPolicyFd drift detection

### Silo Policy Dependency Fix (2026-08-25)

**Bug:** First deploy errored on silo planning (policies not yet in AD) → deployment blocked

**Fix:**
1. Get-TierModelAuthSiloFd now validates policy reference against **config**, not AD
2. Deploy-TierModel.ps1 restructured: policies created first (AD), then silos planned+created
3. Error handling: policy not in config = real error; policy pending creation = proceeds

**Invariant:** Policies must exist in AD before silos are created (non-negotiable)

### Config Finalization (2026-08-27)

**Naming Convention:** All 8 objects use *-  prefix (mirrors GPO convention)
- Tier 0/1/2 Admins: policies + silos
- Tier 2 EUD: policy + silo

**TGT Lifetimes:** Tier 0 (120m), Tier 1 (240m), Tier 2 Admin (360m), Tier 2 EUD (null/domain default)

**Group Scope:** Admins + Operators + ServiceAccounts per tier; Tier 2 EUD = LocalDeviceOperators only

**Open Items:** VPN account group inclusion (pending confirmation)

---

## 2026-08-24 — Format-TierModelDuration Implementation

**Status:** ✅ COMPLETE — Public function, 9 Write-Host sites updated, 12/12 smoke tests pass

**Function:** Format-TierModelDuration.ps1
- 4-tier format: <1ms / Xms / Xs / Xm Ys
- Floor-based arithmetic (no banker's rounding: 90000→1m 30s, not 2m 30s)
- Accepts both [int] and [double] DurationMs

**Integration:** Updated 9 Write-Host console sites in Deploy-TierModel.ps1; left 2 log sites raw

**Module v1.3.0, added to FunctionsToExport**

**Regression Guards:** 90000/119999/120000 boundary values locked

---

## 2026-08-14 — -EnableAuditing Implementation

**Status:** ✅ DELIVERED — 4 audit cmdlets, config/schema, deploy integration, lab-validated

**Cmdlets:** Get-TierModelAuditRule, New-TierModelAuditRule, Test-TierModelAuditRule, Get-TierModelAuditRuleFd

**Config:** tiermodel-audit.json — 9-right SACL list, domain DN templating

**SACL Pattern (Validated):**
- Get-Acl -Path "AD:<dn>" -Audit (requires SeSecurityPrivilege)
- UNION converge: remove managed ACEs, add canonical 9-right ACE, Set-Acl
- Idempotency: already-converged = zero writes
- No-clobber: non-Success AuditFlags left untouched

---

## 2026-08-11 — BUG-006 Canonical ACL Pre-flight Gate

**Status:** ✅ COMPLETE — Test-TierModelCanonicalAcl, 18 tests, lab-validated

**Technique:** System.DirectoryServices.Protocols + CommonSecurityDescriptor parsing
- Check .DiscretionaryAcl.IsCanonical (CommonAcl only)
- Two parameter sets: ByServer (live AD), ByBytes (Pester-friendly)

**Integration:** Pre-flight gate in Test-TierModelPrerequisites (WinLaps block); both Deploy/Audit hard-stop on non-canonical state

---

## Essential Technical Patterns

**SDDL Semantics:** Member_of_any (OR) prevents lockout; Member_of_each (AND) = documented failure

**Idempotency:** Always check-before-act; .Count wrapping for empty sets (@() prevents StrictMode errors)

**Type Handling:** Mixed int/double require explicit casting

**SACL Converge:** Remove managed → add canonical → write same object; zero writes when converged

**Exemptions:** RID-500 resolved at runtime; configured accounts in HashSet (case-insensitive skip)

**CLR Conflicts:** Process-lifetime persistence; spawn clean child process to resolve

**Hashtable vs PSObject:** .ContainsKey() for hashtables; .Properties.Name for objects

**Two-Step Binding:** Grant-ADAuthenticationPolicySiloAccess + Set-ADAccountAuthenticationPolicySilo (both idempotent)

---

**Latest Decision:** Beast-AuthSilos-Deploy (2026-08-27) — 8-object model, SDDL design, key implementation decisions documented

**Next:** Lab validation of 8 open items; config review (Joel); module code deployment to test environment
