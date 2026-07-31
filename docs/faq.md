# Frequently Asked Questions (FAQ)

## General

### What is the Tier Model?
- Brief explanation of Active Directory tiering (Tier 0, Tier 1, Tier 2)
- What problems it solves (credential theft, lateral movement, privilege escalation)
- Link to index.md for full documentation

### Who is this solution intended for?
- Organizations running Active Directory on-premises or in hybrid environments
- Recommended skill level (e.g., intermediate to experienced AD administrators)
- Not a substitute for a full security architecture review

### What version of the Tier Model is this?
- Current release is **v1.2.1** (released July 30, 2026)
- The initial automated release was **v1.0.0** (released February 27, 2026)
- See the `CHANGELOG.md` file in the repository root for full release history
- v1.2.1 is a **patch** release (UI and reliability bug fixes, BUG-001..011); v1.2.0 added Windows LAPS ACL delegation and GPO decryptor support; v1.1.0 added MSA/gMSA/dMSA ACL support; `2.x` is reserved for future breaking changes

---

## Upgrading from a Previous Version

### I deployed an earlier version of the Tier Model. What do I need to know before upgrading?
- This automated module was first released as **v1.0.0** — review the full CHANGELOG before proceeding
- The deployment script (`Deploy-TierModel.ps1`) is idempotent; existing objects in AD will be skipped, not overwritten
- New components added in v1.0.0 (e.g., structured logging, drift detection, ADMX management) will be created fresh
- Back up your Active Directory (System State or AD-specific backup) before running any upgrade

### What changed compared to a legacy, manually-maintained Tier Model?
- `Deploy-TierModel.ps1` was fully rewritten with component-specific switches (`-OuOnly`, `-GroupOnly`, `-GposOnly`, etc.)
- `Audit-TierModel.ps1` is a **new script** — it did not exist in legacy manual deployments
- Structured logging with correlation IDs and security redaction is new in v1.0.0
- GPO deployment modes expanded to three options: `create`, `createAndImport`, `createImportAndConfigure`
- ADMX hash verification added for template integrity
- A **Microsoft Sentinel monitoring pack** has been built against the new structure, enabling day-one SOC monitoring of your Tier Model immediately after deployment

### Will upgrading overwrite my existing OUs, Groups, or GPOs?
- **No** — the deployment engine tests for existence before acting (see [Deployment Methodology](deployment-methodology.md))
- If an OU, Group, or User already exists, it is **skipped** with an INFO log message
- GPOs are handled similarly: existing GPOs are not re-imported unless explicitly configured
- Exceptions and edge cases to be noted here

### Do I need to re-import my ADMX templates?
- If you previously imported ADMX templates manually, they may not match the v1.0.0 hash manifest
- Use the drift detection audit (`Audit-TierModel.ps1`) to identify hash mismatches before re-importing
- Re-import can be triggered with `-AdmxOnly` or as part of `-FullDeployment`

### I have been running a Tier Model for years with OU names like "Admin", "Devices", "Groups", "User Accounts", and "Tier 0 Servers" under the Admin OU. Do I need to change?

**No — you do not need to change anything.** The previous Tier Model structure is still secure and fully functional. If your environment uses the older OU naming conventions, it means you (or your team) have been manually maintaining your Tier Model — likely for the better part of a decade since the original Tier Model guidance was released. That discipline is exactly what makes a Tier Model effective, and the naming of the OUs does not diminish the security value of what you have built.

**You have two options:**

**Option 1: Stay with your current structure (recommended for most long-running environments)**
- Continue maintaining your existing Tier Model manually as you always have
- There is no security requirement to rename OUs or migrate to the new structure
- Your existing GPOs, groups, ACLs, and delegation model remain valid
- This is the right choice if your environment is stable and you have mature operational processes already in place

**Option 2: Migrate to the open-source, community-maintained version**
- This open-source release is the only version actively being invested in going forward — new features, bug fixes, and community contributions will happen here
- If you want to take advantage of automated deployment, drift detection, structured logging, and ongoing community improvements, migration is worthwhile
- **This is a significant undertaking and should not be rushed.** Migration from a long-running manually maintained environment into the new automated structure requires careful planning to avoid impact to production systems

#### Migrating from the Previous OU Structure

If you decide to migrate, the **recommended first step is to engage Microsoft** — a specialist can help you plan and execute the migration in a way that minimizes risk to production. Alternatively, engage a **Microsoft Partner with deep Tier Model expertise** who can guide the process end-to-end.

The high-level migration path is:

1. **Audit first** — Run `Audit-TierModel.ps1` against your environment to establish a baseline of differences between your current state and the target configuration. This gives you a clear picture of what needs to change before touching anything.
2. **OU structure** — Start with OUs. Rename existing OUs to align with the new naming convention where possible, rather than creating parallel structures. Work through the OU hierarchy top-down so that child paths resolve correctly.
3. **Groups** — Run `Deploy-TierModel.ps1 -GroupOnly` to create any missing groups defined in `tiermodel-groups.json`. Review existing groups and consolidate where appropriate.
4. **Users** — Use `-UserOnly` to create Tier Model service/admin accounts. Existing accounts tied to the old structure should be reviewed and migrated or decommissioned.
5. **OU ACLs** — Use `-OuAclsOnly` after the OU and group work is complete to apply delegation in the new structure.
6. **GPOs — the most complex step** — Custom GPO settings from your previous deployment (User Rights Assignments, Restricted Groups, audit policies, etc.) should be **consolidated into the SOE or SHF GPOs** rather than preserved as standalone custom GPOs. Previous custom GPOs should be removed once their settings are validated in the new GPO structure. This is where an expert can provide the most value — mapping legacy policy intent to the new GPO organization is not a mechanical process.
7. **Audit to completion** — Continuously re-run `Audit-TierModel.ps1` throughout the migration. The goal is for all audit checks to pass before considering the migration complete.

> **Important:** Take your time. A Tier Model that has been in place for a decade has a lot of history embedded in it — GPO settings, delegation entries, group memberships. Migrating carefully and methodically is far safer than migrating quickly.

### My previous deployment used a different OU structure. What happens?
- The Tier Model will create any OUs defined in `tiermodel-ous.json` that do not already exist
- OUs that exist in your environment but are **not** in the config will be left untouched
- If your existing OU paths differ from the v1.0.0 defaults, update `tiermodel-ous.json` accordingly before deploying

### Can I roll back to a previous manual configuration if something goes wrong?
- The Tier Model does not provide an automated rollback mechanism
- Because all objects created by the Tier Model are **new objects not in production use**, the recommended remediation for any deployment failure is to **delete the affected object(s) and redeploy** using the appropriate component-specific switch
  - Example: if a GPO fails to import, delete the GPO in GPMC or via PowerShell, resolve the underlying issue, then re-run `Deploy-TierModel.ps1 -GposOnly` until all GPOs import successfully
  - The same approach applies to OUs, Groups, Users, and ACL delegations — delete the partially created object and let the deployment script recreate it cleanly
- This delete-and-redeploy pattern is safe precisely because none of these objects are yet linked to users, computers, or production workflows
- Recommendation: test in a lab environment before deploying to production
- If you need to fully undo a deployment, remove all Tier Model OUs (which will cascade-delete child objects), GPOs, and groups, then start fresh with `-FullDeployment`

---

## Prerequisites & Requirements

### What PowerShell version is required?
- **PowerShell 7.0 or later** is required
- PowerShell 5.1 is explicitly **not supported**
- Verify with `$PSVersionTable.PSVersion`

### What AD permissions are required?
- **Domain Admin** membership is required for full deployment
- Scoped deployments (e.g., `-OuAclsOnly`) may work with delegated permissions — to be confirmed per use case

### What language or locale is supported?
- **English (`en-US`) only, at this time.** Both the **host** you run the scripts from (your workstation or the domain controller) and **Active Directory** must be English.
- The tool runs **two fail-fast prerequisite checks** — one for the host OS install language, one for the well-known Active Directory group names — and stops with a clear message on a non-English environment **before making any change**.
- Only 18 languages fully localize Windows Server (including AD group names); English is supported and the other 17 are detected and stopped. Language Interface Packs (e.g. Hindi, Bengali) and non-bold language packs (e.g. Arabic) keep English AD names and are unaffected.
- See [Language Support](language-support.md) for the full language list and the future localization roadmap.

### What PowerShell modules must be installed?
- `ActiveDirectory` (v1.0.1.0 or later)
- `GroupPolicy` (v1.0 or later)
- `Pester` (any 5.x release; Pester 6.x is not yet supported) — install from PowerShell Gallery
- Notes on air-gapped environments and offline module installation

### Do I need to run this from a Domain Controller?
- No — the scripts connect to a DC specified via `-PreferredDc`
- Recommended to run from a Tier 0 PAW (Privileged Access Workstation)
- Ensure network connectivity to the specified DC before running

---

## Deployment

### What does a dry-run (planning mode) do?
- Running without `-WhatIf` or with default settings shows what *would* be changed
- No objects are created, modified, or deleted during a dry-run
- Review the output carefully before committing to a full deployment

### What is the difference between `-FullDeployment` and component-specific switches?
- `-FullDeployment` deploys all core components in the correct order of precedence
- Component switches (`-OuOnly`, `-GroupOnly`, `-GposOnly`, etc.) deploy only that component
- **Optional features** (`-IncludeMsa`, `-IncludeGmsa`, `-IncludeDmsa`, `-IncludeWinLaps`) must be explicitly added to either `-FullDeployment` or a standalone run — they are never deployed automatically
- Use component switches for targeted remediation or phased rollouts

### How long does a full deployment take?
- Varies based on environment size, DC responsiveness, and number of GPOs
- GPO import is typically the longest step
- Logging output will show per-component timing

### Can I deploy to multiple domains?
- Not natively in a single script run — each run targets one domain/DC
- Multi-domain environments require separate runs per domain, adjusting config files accordingly

### Can I deploy only Tier 0 and skip Tier 1 and Tier 2?

**This is not supported, and it is strongly recommended against.** Here is why:

Unless you are operating a highly specialized Active Directory with fewer than ten domain-joined servers serving a single purpose, your environment almost certainly has Tier 1 servers (member servers, application servers, file servers) and Tier 2 endpoints (workstations, user devices) that would directly benefit from being brought into the Tier Model. In practice, 99.999% of Active Directory environments require more than one tier to be meaningful.

**The GPO complexity problem:**
The Tier Model GPOs that include User Rights Assignments (URAs) and Restricted Groups are built around the full set of Tier 0, Tier 1, and Tier 2 security groups. If you deploy only Tier 0 and exclude the Tier 1 and Tier 2 groups, those GPOs will be incomplete from day one. When you later want to extend the deployment to cover additional tiers, you face two bad options:
- **Re-deploy and retest the GPOs** in production — introducing change risk to apply settings that should have been there from the start
- **Manually edit the GPOs** to add the missing groups — introducing human error risk in security-critical policy

Deploying the full structure up front eliminates both problems entirely.

**The practical reality:**
In the vast majority of organizations, the people who would be affected by the presence of extra OUs, GPOs, and groups in Active Directory are essentially zero — almost no one has ADUC or GPMC open day-to-day, and a handful of additional objects in AD has no operational impact on anything. It is genuinely not worth debating.

The time and energy spent trying to minimize the Tier Model footprint would be far better invested in addressing real, known threats in your environment — patching, credential hygiene, attack path reduction, lateral movement controls. A few extra Tier Model OUs and GPOs sitting unused for a quarter until Tier 1 rollout begins are not a risk. An incomplete security boundary is.

**Deploy the full structure. Use the tiers as you are ready for them.**

---

## Drift Detection & Auditing

### What is drift detection?
- Compares the current state of your AD environment against the desired state defined in the config files
- Reports missing objects, configuration mismatches, extra protections, and hash mismatches
- See [Drift Detection Details](drift-detection-details.md) for full documentation

### How do I run an audit?
- Example: `.\Audit-TierModel.ps1 -PreferredDc DC01.contoso.com -OutputFormat Html`
- Supported output formats: `Text`, `Json`, `Html`, `NUnitXml`
- NUnit XML format integrates with CI/CD pipelines (Azure DevOps, GitHub Actions)

### What severity levels are reported?
- **High** — Missing critical objects (Tier 0 OUs, admin groups, etc.)
- **Medium** — Configuration mismatches (wrong ACLs, GPO link targets, etc.)
- **Low** — Informational drift (extra protections, unexpected objects)

### How often should I run an audit?
- Best practice: run on a scheduled basis (monthly or quarter)
- Always run before and after any change window
- Integrate with CI/CD for continuous compliance validation

---

## Group Policy (GPO) Management

### How does the Tier Model manage GPOs?
- GPOs are defined in `tiermodel-gpos.json`
- Three deployment modes: `create`, `createAndImport`, `createImportAndConfigure`
- See [GPO Management Strategy](gpo-management-strategy.md) for full details

### What is the difference between `ImportOnlyGpo` and `PostConfigureGpo`?
- `ImportOnlyGpo` — imports GPO settings from a backup; no post-configuration applied
- `PostConfigureGpo` — imports and then applies User Rights Assignments and Restricted Groups settings
- Use `PostConfigureGpo` for security-sensitive baseline GPOs

### Will the Tier Model overwrite my existing GPO settings?
- Only if the GPO is configured with `createImportAndConfigure` mode
- Existing GPOs in `create` mode are skipped if they already exist
- Review `tiermodel-gpos.json` to confirm the mode for each GPO before deploying

### Can I add custom GPOs to the Tier Model config?
- We advise against this as the SHF and SOE GPOs have been provided to add any additional settings
- else, add entries to `tiermodel-gpos.json` following the existing schema
- Backup files for `createAndImport` GPOs must be placed in the `config/gpo/` directory
- Validate changes against `tiermodel.schema.json` before deploying
- However, 

---

## Windows LAPS (Optional Feature)

### What does `-IncludeWinLaps` do?
- Deploys 7 Windows LAPS ACL delegations (Self-permission, Read-permission, Reset-permission) to the configured target OUs using `Set-LapsADComputerSelfPermission`, `Set-LapsADReadPasswordPermission`, and `Set-LapsADResetPasswordPermission`
- Configures the `ADPasswordEncryptionPrincipal` registry value on 6 non-DC Windows LAPS GPOs so the correct tier group can decrypt managed passwords
- Domain Controllers OU receives Self + Read + Reset delegations but **no** decryptor configuration (DSRM always uses Domain Admins per Microsoft specification)
- Deployment is idempotent — re-runs skip already-configured entries

### Does this support legacy Microsoft LAPS (ms-Mcs-AdmPwd)?
- **No.** This feature is **Windows LAPS only** (`ms-LAPS-*` attributes). Legacy Microsoft LAPS (`ms-Mcs-AdmPwd*`, `AdmPwd.PS`) is never referenced, modified, or documented.

### What are the prerequisites for `-IncludeWinLaps`?
- **Windows LAPS schema extension** must already be present (`ms-LAPS-Password` attribute class). If absent, the tool stops with a friendly error message and **never** extends the schema itself
- All Tier Model OUs must exist (required for ACL delegation targets)
- All Tier Model Groups must exist (required for Read/Reset permission principals)
- All 7 Windows LAPS GPOs must exist (GPO existence only — links are not required)

### What happens if the Windows LAPS schema is not extended?
- The planner (`Get-TierModelWinLapsAcl`) immediately returns a plan error: `WinLapsSchemaNotPresent`
- Deployment stops at the plan phase — no ACL or GPO changes are applied
- The tool never extends the schema; this is a manual prerequisite that must be satisfied before deployment

### Why can't Tier 0 Admins decrypt Tier 1 and Tier 2 PAW passwords?
- `ADPasswordEncryptionPrincipal` accepts a single principal per GPO. The Tier Model assigns each tier's LAPS GPO to that tier's specific admin/operator group.
- CNG-DPAPI decryption requires the **exact** encryption principal — having `GenericAll` on a lower-tier PAW OU does **not** grant decryption rights. This is an intentional security design: per-tier isolation ensures each tier's admins can only decrypt passwords in their own tier.
- This is the strongest security posture and is confirmed as the design intent (see architecture decisions).

### Can `-IncludeWinLaps` be used standalone (without `-FullDeployment`)?
- Yes. Run `.\Deploy-TierModel.ps1 -IncludeWinLaps -PreferredDc DC01.contoso.com` for a standalone plan, and add `-ConfirmApply` to execute.
- The three prerequisites (OUs, Groups, GPOs) must already exist when running standalone. The planner validates all three and reports a dependency errors list if anything is missing.

### How do I audit Windows LAPS compliance?
- `.\Audit-TierModel.ps1 -IncludeWinLaps -PreferredDc DC01.contoso.com`
- This runs both `Test-TierModelWinLapsAcl` (ACL delegation drift) and `Test-TierModelWinLapsDecryptor` (GPO decryptor drift)
- Adding `-IncludeWinLaps` to a `-FullDeployment` audit also includes Windows LAPS. A plain `-FullDeployment` without `-IncludeWinLaps` does **not** audit Windows LAPS.

---

## ADMX Templates

### What ADMX templates are included?
- A full list of bundled `.admx` files is available in `config/admx/`
- Includes templates for Microsoft Edge, LAPS, Kerberos, LanMan, SecGuide, and others

### How does ADMX hash verification work?
- Each ADMX file has an expected MD5 hash stored in the config
- The deployment/audit process compares actual vs. expected hashes
- A mismatch indicates the file was modified or replaced — resolve before importing

### Can I add my own ADMX templates?
- Yes — place the `.admx` (and corresponding `.adml`) files in `config/admx/`
- Add hash entries to the appropriate config file
- Test in a non-production environment first

---

## Logging

### How do I enable deployment logging?
- Add the `-Logging` switch to `Deploy-TierModel.ps1`
- Logs are written with structured JSON format and include a correlation ID
- See [Tier Model Logging](tiermodel-logging.md) for full configuration details

### Are passwords or credentials logged?
- No — sensitive values (passwords, tokens, secrets, credentials) are automatically redacted
- The `Write-TierModelLog` function applies redaction patterns before writing any output

---

## Microsoft Sentinel Integration

### Is there a Microsoft Sentinel solution for the Tier Model?
- Yes — a **Microsoft Sentinel content pack** is being released alongside the Tier Model to provide near-real-time (NRT) security monitoring for environments using this solution
- The pack is designed to give your SOC visibility into Tier Model-relevant security events without requiring custom query authoring from scratch

### What does the Sentinel pack include?
- **Analytic Rules** — Pre-built detection rules that alert on suspicious activity relevant to the Tier Model, including tier-crossing violations (e.g., Tier 0 accounts authenticating to Tier 1 or Tier 2 systems) and unauthorized changes to Tier Model OUs, groups, and GPOs
- **Automation Rules** — Response automation to triage and enrich Sentinel incidents generated by the Analytic Rules, reducing manual SOC workload for common Tier Model alert patterns
- **Workbook** — A dedicated monitoring dashboard providing SOC analysts with an at-a-glance view of Tier Model health, recent violations, and trend data across tiers

### What are "tier-crossing violations"?
- A tier-crossing violation occurs when a privileged account from one tier authenticates to or interacts with a system in a lower or higher tier in a way that violates the Tier Model isolation boundaries
- Example: a Tier 0 domain admin account being used to log into a Tier 1 member server, or a Tier 1 service account accessing a Tier 0 domain controller
- These events are high-fidelity indicators of either policy non-compliance or active credential misuse and should be investigated promptly

### Do I need Microsoft Sentinel to use the Tier Model?
- No — Microsoft Sentinel is **not a prerequisite** for deploying or operating the Tier Model
- The Tier Model is fully functional as a standalone AD hardening solution
- The Sentinel pack is an optional add-on for organizations that want automated SOC-level monitoring on top of their Tier Model deployment

### Where can I find the Sentinel pack?
- The pack will be available from the project repository alongside the Tier Model release
- Link to be added once the pack is published

### What if my organization uses a third-party SIEM instead of Microsoft Sentinel?
- If you are not using Microsoft Sentinel, it is assumed you already have a third-party SIEM in place (e.g., Splunk, QRadar, Elastic, Chronicle, etc.) with an established SOC practice
- The Analytic Rules in the Sentinel pack are written in **KQL (Kusto Query Language)** — your SIEM team can convert these queries into the equivalent language for your platform to achieve comparable detection coverage
- Most modern SIEMs have well-documented query languages, and the detection logic itself (what events to look for, what field correlations matter) translates directly regardless of syntax
- **Generative AI tools can assist significantly with this conversion** — providing a KQL query and the target SIEM's query language to a tool like GitHub Copilot or similar will generally produce a high-quality starting point that your team can validate and refine
- The Workbook visualizations can similarly be recreated in your SIEM's dashboard tooling using the same underlying event logic

---

## Troubleshooting

### The deployment fails with a prerequisite error. What do I check?
- Verify PowerShell version is 7.0 or later
- Confirm you are running as Domain Admin
- Confirm network connectivity to the `-PreferredDc` specified
- Check that all required modules are installed at the correct versions
- Confirm the **host OS** (where you run the scripts) and **Active Directory** are English (`en-US`) — non-English environments are not supported (see [Language Support](language-support.md))

### An OU was not created. Why?
- The OU may already exist (check the log for "OU already exists" INFO messages)
- The parent OU path may not exist yet — OUs must be deployed in hierarchy order (handled automatically by `-FullDeployment`)
- Check for typos in `tiermodel-ous.json`

### A GPO failed to import. What should I do?
- GPO import failures are typically caused by a corrupt or missing backup, insufficient permissions, or a DC-replication issue
- **Recommended remediation:**
  1. Identify the failed GPO in the deployment log output
  2. Delete the GPO using GPMC or `Remove-GPO -Name "<GPOName>" -Domain <domain>`
  3. Investigate and resolve the underlying cause (check the backup files in `config/gpo/`, verify DC connectivity, confirm Domain Admin rights)
  4. Re-run `Deploy-TierModel.ps1 -GposOnly -PreferredDc DC01.contoso.com` to retry only GPO deployment
  5. Repeat until all GPOs show as successfully created and imported
- Because GPOs created by the Tier Model are new and not yet in use, deleting and redeploying is the safest and cleanest approach
- Do **not** attempt to partially repair a GPO in-place — delete and let the script recreate it from the backup

### A GPO was not linked. Why?
- GPO linking depends on the OU existing — ensure OUs were deployed first
- GPO link order corrections may require manual intervention (see deployment methodology)
- Check `tiermodel-gpos.json` for the expected link target and verify the OU DN

### I see "hash mismatch" warnings for ADMX files. What do I do?
- Compare the installed ADMX file against the bundled version in `config/admx/`
- If the file was intentionally customized, update the expected hash in the config
- If the file was unintentionally modified, replace it with the bundled version and re-run ADMX import

### How do I get support or report a bug?
- Open an issue on the project repository
- Include the deployment log output (with sensitive data redacted) and the relevant config file section
- Specify the version of TierModel, PowerShell version, and AD forest/domain functional level

---

## Microsoft Engagement Guidelines

### I am a Microsoft employee deploying the Tier Model for a customer. What are the rules around customization?

**Microsoft employees must deploy the Tier Model as released — no modifications to the JSON configuration files are permitted during a Microsoft-led engagement.**

The scope of a Microsoft-led deployment is to deploy, test, and validate that the Tier Model is functioning correctly as designed. The deliverable is a verified, working Tier Model that matches the released configuration. Any deviation from that introduces variability that moves outside the bounds of what has been tested and validated.

**Why no modifications during the engagement?**
- Customizing a brand-new security framework before you have operational experience with it is counterproductive — you cannot make informed decisions about what to change until you understand how it behaves in practice
- Changes made without deep knowledge of the Tier Model's internal design can expose security gaps or break the model entirely — the interdependencies between OUs, groups, GPO URAs, Restricted Groups, and ACL delegations are not always obvious
- The Tier Model has already accounted for a wide range of compliance and security framework requirements through the **SHF (Secure Host Foundation) GPOs**, and for environment-specific settings through the **SOE (Standard Operating Environment) GPOs** — in most cases, the need to customize the base configuration reflects a misunderstanding of how these GPOs are intended to be used

**Additional services available:**
Microsoft also offers the **Tier Model Integration Services (TMIS)** to assist with migrating servers currently outside the Tier Model into their correct tiers (Tier 0 or Tier 1). This service covers data collection, analysis, migration planning, and the migration itself. Contact your Microsoft representative for more information.

### What happens after the Microsoft engagement closes?

Once the project has closed — meaning Microsoft has completed deployment, testing, and validation, and the Tier Model has been signed off as functioning correctly — **the partner or customer takes full ownership and may make any changes they choose.** Accountability for any modifications made after project closure rests entirely with those who approved and implemented them.

If Microsoft is engaged in the future to assess the environment, the **`Audit-TierModel.ps1`** script will be used to identify any configuration drift from the state at project closure. The audit reports produced at sign-off serve as the baseline — any findings that did not exist at closure represent post-engagement changes made outside of Microsoft's scope. These reports are part of the project closure documentation for exactly this reason.

