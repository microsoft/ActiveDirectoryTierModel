# Tier Model Event ID Schema

**Scope:** The Active Directory Tier Model toolset (multiple scripts over time), documented through `optional/Update-TierModelMembership.ps1`.

**Purpose:** Define a stable Windows Event ID schema so SIEM solutions, monitoring, and operational dashboards can:
- detect a script **started** and **completed** (heartbeat / dead-man's-switch),
- know **which tiers changed** in a successful run,
- know an **error** occurred (with a pointer to logs for debugging),

without brittle string matching on script output. Event logging is **opt-in** and **best-effort** — errors in event registration or writes do not block the script's AD work.

---

## 1. Purpose

Define a single, future-proof Windows **Event ID schema** for every Tier Model script so any SIEM can detect critical operational events using **stable, documented Event IDs** rather than brittle string matching.

The event log is an **operational heartbeat + classification signal** — NOT a change ledger. Per-object detail belongs in `-EnableLogging` (change log) and `-EnableDebug` (deep dump). The AD *changes themselves* are also audited by Windows in the **Security** log **when the relevant audit policies are enabled** (see note) — complementary, not a replacement.

> **Security-log audit is a prerequisite, not automatic.** Group-membership events (4728/4732/4756) require *Audit Security Group Management*; Authentication-Policy assignment/clear (`msDS-AssignedAuthNPolicy`) requires *Audit Directory Service Changes* + an applicable SACL (5136). The Tier Model's `-EnableAuditing` sets the domain-root SACL, which helps, but customers must confirm these audit subcategories are enabled. 4728/4732/4756 do **not** cover policy assignment/clear.

---

## 2. Foundational principles

1. **Event IDs are scoped to their Source/Provider** — no cross-provider collision. SIEM rules MUST filter on **`Source` + `EventID` together**. Our entire `0-65535` ID space under our own Source is available.
2. **Displayed ID is 16-bit (0-65535).** No Microsoft-reserved third-party range; uniqueness within our own Source is the only constraint. No "customer bit" needed.
3. **The Security log is off-limits to scripts** (LSASS-only since Windows XP SP2). Our events go to the **Application** log.
4. **PowerShell 7 has no `Write-EventLog`.** Use `[System.Diagnostics.EventLog]::WriteEntry(...)`.
5. **No commas or tabs in message text** (CSV/TSV export safety). Use `|`-separated `key=value`.

---

## 3. Log target & Source

| Item | Value | Why |
|---|---|---|
| **Log** | **Application** | Best practice for a classic source; monitoring rules forward only our Source/IDs. |
| **Source** | `TierModel` (single shared source) | One `Source == 'TierModel'` filter returns every Tier Model event; the **ID range** identifies which script wrote it. |
| **Write API (PS7)** | `[System.Diagnostics.EventLog]::WriteEntry(Source, Message, EntryType, EventId, Category)` | `Write-EventLog` does not exist in PS7. |
| **Registration** | **deploy-time**, per DC, with verification (see section 11) | Registering a Source is machine-local and has post-creation latency; first-run self-register is unreliable. |

**KQL filter (example):** `Application!*[System[Provider[@Name='TierModel'] and (EventID=1000 or EventID=1001 or EventID=1009)]]`.

---

## 4. Event ID allocation scheme (toolset-wide)

**Base 1000**, one **100-ID block per script/component**. Maintain a **central allocation registry** in this document (collisions matter within the shared `TierModel` source).

| Range | Component |
|---|---|
| **1000-1099** | `Update-TierModelMembership.ps1` (reconciliation) |
| 1100-1199 | *(reserved — next script)* |
| ... | ... |
| 1900-1999 | *(reserved — future expansion)* |

**Offset convention per block:** `+0` START (Info), `+1` COMPLETE (Info), `+9` ERROR (Error), `+2..8` reserved for milestones, `+10..99` reserved for verbose.

---

## 5. Events for `Update-TierModelMembership.ps1` (1000-1099)

| ID | Name | Level | When |
|---|---|---|---|
| **1000** | MembershipRunStart | Information | **Immediately after event-log initialization succeeds, before preflight** — so a preflight failure still yields START+ERROR |
| **1001** | MembershipRunComplete | Information | Script reaches the end **cleanly (no errors)** — **the heartbeat** |
| **1009** | MembershipRunError | **Error** | **Any catchable error** → written **before** exit, then exit 1 (**fail-fast**; **no 1001**) |

**Design rules (fail-fast error model):**
- **Healthy run** = **1000 then 1001**. **Failed run** = **1000 then 1009, no 1001**.
- The outer `catch` writes **1009 first**, via a **no-throw writer** (best-effort; never throws from the catch), then exits 1.
- **1001 is emitted only on a clean run**, so `Level == Error` (1009) unambiguously means "the run failed."
- **1009 carries no counts** — just the failure signal + remediation pointer. Partial changes made before the failure are reported by the next successful run's COMPLETE event (Create-Once is idempotent) and are independently in the Security log.

---

## 6. Event message format

`|`-separated `key=value` (no commas/tabs; dynamic values restricted to `[A-Za-z0-9._:;-]`, no `|`/CR/LF; parsers split on the **first** `=`; the fixed-text `Message=` is always last).

**1000 START:**
```
Schema=1.0 | Script=Update-TierModelMembership | ScriptVersion=<version> | Action=START | RunMode=Apply | JobId=Tier0-Daily | CorrelationId=<guid> | Host=DC01.contoso.com | Scope=Tier0;Tier1;Tier2
```

**1001 COMPLETE** (clean success):
```
Schema=1.0 | Script=Update-TierModelMembership | ScriptVersion=<version> | Action=COMPLETE | RunMode=Apply | JobId=Tier0-Daily | CorrelationId=<guid> | Host=DC01.contoso.com | Scope=Tier0;Tier1;Tier2 | TiersChanged=Tier1;Tier2 | Tier0Changed=0 | Tier1Changed=2 | Tier2Changed=5 | Duration=00:01:42
```

**1009 ERROR** (fail-fast, written from the catch before exit):
```
Schema=1.0 | Script=Update-TierModelMembership | ScriptVersion=<version> | Action=ERROR | RunMode=Apply | JobId=Tier0-Daily | CorrelationId=<guid> | Host=DC01.contoso.com | Message=The script encountered an error and stopped. Re-run with -EnableLogging or -EnableDebug to identify and resolve it.
```

**Field dictionary:**

| Field | Meaning |
|---|---|
| `Schema` | schema version (this document) — append-only evolution |
| `Script` / `ScriptVersion` | which script + its version |
| `Action` | START \| COMPLETE \| ERROR |
| `RunMode` | **Apply** \| **WhatIf** — production heartbeat and workbook filter on `Apply`; a `WhatIf` dry run reports zero committed changes and must not satisfy the heartbeat |
| `JobId` | customer-supplied stable job identifier (from `-JobId`); **also embedded in the log file name and the log header** for end-to-end traceability. Defaults to `Adhoc` when omitted. Grammar `[A-Za-z0-9._-]{1,64}`. |
| `CorrelationId` | per-run GUID — ties the event to the `-EnableLogging` / `-EnableDebug` files |
| `Host` | informational DC FQDN; the **authoritative host key for KQL is the auto-stamped `Computer`** field |
| `Scope` | tiers **targeted by the parameters** (`;`-separated) |
| `TiersChanged` | tiers that **actually changed** (`;`-separated) or `None` — **the workbook tag** (COMPLETE only) |
| `TierNChanged` | per-tier change **count** (0 = no change); stable, always-present on COMPLETE |
| `Duration` | run elapsed (COMPLETE only) |
| `Message` | ERROR only — fixed remediation pointer, never raw exception text |

---

## 7. Tier-change classification rules

A **change** = an actual AD write: **`GroupAdded + PolicyAssigned + PolicyCleared`** per phase. (`Scanned`, `Excluded`, `AlreadyCurrent` are NOT changes. `PolicyCleared` **does** count — it is a security-significant enforcement change.)

- **`TierNChanged`** = sum across that tier's executed switches. **Tier 2 rolls up** Operators/Eud/ServiceAcct/PawDevices/EudDevices.
- **`TiersChanged`** lists only tiers with count > 0 (else `None`).
- **`Scope`** = tiers whose switches ran (`-All` → all three; `-AllTier0` → Tier0; `-Tier1MemberServers` → Tier1).
- **Built-in exclusion caveat (`TiersChanged` may not be a subset of `Scope`):** the always-on Phase 1 built-in-exclusion enforcement can clear a policy on a built-in domain-join account regardless of `Scope` (`svc-pawdomainjoin`→Tier0, `svc-t1srvdomainjoin`→Tier1, `svc-t2euddomainjoin`→Tier2). Those clears **must** be counted toward the account's tier, so e.g. a `-Tier1MemberServers` run could legitimately report `TiersChanged=Tier0`. Consumers must not assume `TiersChanged ⊆ Scope`.

---

## 8. Error model & failure coverage

**Fail-fast: trap any error, write 1009 (no-throw), exit 1.** Be clear about coverage:

| Failure class | 1009 written? | Covered by |
|---|---|---|
| Any error caught by the outer `try` while the pre-registered source is writable | **Yes** (guaranteed) | 1009 event |
| Failure **before** START / before the `try` (parse, param-binding, `#requires`) | No | missing-COMPLETE heartbeat |
| Event subsystem itself unavailable (source unregistered/denied, log full/no-overwrite) | No | missing-COMPLETE heartbeat; deploy-time verification prevents most of this |
| Hard kill / DC reboot / power loss mid-run | No | missing-COMPLETE heartbeat + Task Scheduler last-run telemetry |

**Contract:** 1009 is guaranteed for any catchable error while the event source is writable; everything else is covered by the **absence of 1001** (plus Task Scheduler's own operational log as an independent signal).

**Event logging is opt-in and best-effort (NOT mandatory).** Labs may run without `-EnableEventLog`. If `-EnableEventLog` is set but the source cannot be initialized or a write fails, the script **warns and continues** (all event writes are wrapped no-throw); it never blocks the AD work.

---

## 9. Severity / Level mapping

START (1000) = Information (KQL Level 4) · COMPLETE (1001) = Information (4) · ERROR (1009) = Error (2).

---

## 10. SIEM / KQL usage

**Heartbeat (dead-man's-switch).** True absence detection needs an **expected inventory** (which servers/jobs should run) — the customer owns this, since only they know their cadence. Two customer patterns:

```kql
// (a) count threshold per server per day — customer sets ExpectedRuns
Event
| where Source == "TierModel" and EventID == 1001 and TimeGenerated > ago(1d)
| where RenderedDescription has "RunMode=Apply"
| summarize n = count() by Computer
| where n < ExpectedRuns      // ExpectedRuns known only to the customer
```

```kql
// (b) inventory left-join — a watchlist of expected (Computer[,JobId]) rows; rows with no match = missed
_GetWatchlist('TierModelExpectedJobs')
| join kind=leftouter (
    Event | where Source=="TierModel" and EventID==1001 and TimeGenerated > ago(25h)
          | where RenderedDescription has "RunMode=Apply"
          | distinct Computer
  ) on Computer
| where isempty(Computer1)     // expected but no COMPLETE = alert
```

*(A bare `where count == 0` over observed events cannot fire — a server that never logged produces no row. Absence detection requires the expected inventory above.)*

**Error alert:**
```kql
Event | where Source == "TierModel" and EventID == 1009
| extend CorrelationId = extract(@"CorrelationId=([0-9a-fA-F-]+)", 1, RenderedDescription)
```

**Workbook — tiers changed per successful run:**
```kql
Event | where Source == "TierModel" and EventID == 1001
| extend TiersChanged = trim(@"\s", extract(@"TiersChanged=([^|]+)", 1, RenderedDescription))
| extend Tier0=toint(extract(@"Tier0Changed=(\d+)",1,RenderedDescription)),
         Tier1=toint(extract(@"Tier1Changed=(\d+)",1,RenderedDescription)),
         Tier2=toint(extract(@"Tier2Changed=(\d+)",1,RenderedDescription))
| project TimeGenerated, Computer, TiersChanged, Tier0, Tier1, Tier2
```

**Granularity across schedules/DCs (no JobId field):** filter on `Computer` + `Scope` and threshold on an expected count. A customer running `-Tier1MemberServers` hourly + `-AllTier0` daily distinguishes them by `Scope` and by expected daily counts. (Trailing whitespace: pipe values are space-padded — `trim`/`split` in KQL; `Scope`/`TiersChanged` are safe `;`-lists of controlled enums.)

---

## 11. Registration & deployment (deploy-time, verified)

At deploy time, on **each** DC that will run a scheduled task:

```powershell
if (-not [System.Diagnostics.EventLog]::SourceExists('TierModel')) {
    [System.Diagnostics.EventLog]::CreateEventSource('TierModel','Application')
}
# Verify the source maps to Application (a source name is machine-wide; it may already exist under another log)
if ([System.Diagnostics.EventLog]::LogNameFromSourceName('TierModel','.') -ne 'Application') { throw '...' }
# Allow cache propagation, then write+read-back a one-off deployment PROBE event (not 1001) to prove it works.
```

- **Runtime self-registers the source idempotently** if it is missing (SYSTEM can), so labs work with just `-EnableEventLog`; **deploy-time registration is still recommended for production** (avoids .NET first-write latency). All event writes are **no-throw** — a registration/write failure warns and continues (not mandatory).
- **Deployment should also validate** Application-log size/retention/overwrite policy and note that "job failed" (1009 / missing 1001) is distinct from "event collection failed" (monitoring agent health) — the latter is covered by Task Scheduler telemetry as an independent source.

---

## 12. Schema versioning

`Schema=` carries this document's version. Add fields = minor (append-only; ignore unknown). Change/remove a field or an ID's meaning = major (documented in CHANGELOG). **IDs are never reused** for a new meaning.

---

## 13. Future — ETW manifest (possible direction)

Later (non-committal): an ETW instrumentation manifest → `TierModel/Operational` channel with typed EventData + Keyword bits (`0x1`=Tier0, `0x2`=Tier1, `0x4`=Tier2, `0x8`=Error) — removing message-string parsing. IDs and tier semantics would carry forward unchanged.

---

## Related Documentation

- **[Tier Model Logging](https://microsoft.github.io/ActiveDirectoryTierModel/tiermodel-logging/)** — Structured logging, diagnostics, and the `-EnableVerbose` and `-EnableDebug` switches for troubleshooting
- **[Sentinel Monitoring](https://microsoft.github.io/ActiveDirectoryTierModel/sentinel-monitoring/)** — Out-of-the-box Microsoft Sentinel monitoring for a deployed Tier Model, including Event ID filtering and KQL queries
