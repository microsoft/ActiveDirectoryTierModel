# Language Support

> **Status: English (`en-US`) only.** At this time the Active Directory Tier Model
> supports deploying and auditing only where **both** the domain controller's operating
> system **and** Active Directory are English. On a non-English domain controller OS or
> a localized Active Directory, `Deploy-TierModel` and `Audit-TierModel` **stop during
> prerequisite validation** with a clear message rather than partially applying an
> inconsistent configuration.

This page explains *why* only English is supported today, *how* that requirement is
enforced, the complete set of languages it affects, and what it would take for the
community to bring the Tier Model to the remaining languages in the future.

## Why English only?

Active Directory stores the **names** of its well-known security principals — for
example *Domain Admins*, *Server Operators*, and *Account Operators* — as real
directory attributes. Those names are **localized once, at domain creation**, from
the installation language of the first domain controller, and then replicated to
every domain controller in the domain/forest.

Two consequences matter here:

1. **The domain's language is fixed and independent of the machine you run from.**
   Opening *Active Directory Users and Computers* (`dsa.msc`) from an English
   Windows 11 client against a German domain still shows `Domänen-Admins`, not
   `Domain Admins` — the name comes from the directory, not the client. A domain
   controller later installed with an **English** OS and joined to that German
   domain still serves the **German** names, because they are replicated, not
   recreated.
2. **The Tier Model references well-known principals by their English names.** The
   configuration set refers to these names in hundreds of places — the
   restricted-groups and user-rights entries in `config/tiermodel-gpos.json` alone
   contain **389** such references. On a localized domain those lookups do not
   resolve, which would cause partial or failed deployments.

Detecting the **domain's** language must be done at the Active Directory level: the OS
or registry install language can disagree with the domain — for example, an English-OS
domain controller joined to a German domain still serves German names — so an OS check
alone cannot stand in for the directory check. In addition, the Tier Model requires the
domain controller's **operating system** to be installed in English, so that English is
guaranteed in *both* places: the OS **and** the directory.

## How the requirement is enforced

`Test-TierModelPrerequisites` performs **two unconditional, fail-fast language checks**
that both `Deploy-TierModel` and `Audit-TierModel` run up front — before any change is
made. Both must pass; if either fails, the run stops with a friendly, actionable error.
In the final code the checks run in this order:

### Check 1 — English operating system (domain controller)

The target domain controller's Windows **installation language** must be English
(`en-US` — install language `0409`). This is the static, authoritative signal for how
the operating system was installed, and it is read from the domain controller itself.
This check runs **first** because it is the broadest, cheapest signal.

### Check 2 — English Active Directory (well-known group names)

The domain's well-known group **names** must be English. The check resolves three
well-known groups **by SID** and compares each group's directory `Name` to its expected
English value:

| Canary group | SID / RID | Scope |
|--------------|-----------|-------|
| Domain Admins | `<DomainSID>-512` | Domain — exists in every domain |
| Server Operators | `S-1-5-32-549` | BUILTIN — exists in every domain |
| Account Operators | `S-1-5-32-548` | BUILTIN — exists in every domain |

Design notes:

- **All three must equal their English names to pass.** If **any** of the three
  differs, the domain is treated as non-English and the run stops with a friendly
  error that names the group and the localized value that was found.
- **Three groups, not one** — defense in depth against an administrator having
  renamed a single built-in group, or an unusual language that leaves one name
  coincidentally matching English.
- **Domain and BUILTIN groups only** (no *Enterprise Admins* / *Schema Admins*), so
  the check is correct when deploying into a **child domain**; forest-root-only
  groups are intentionally avoided.
- The name is read **from Active Directory** (`Get-ADGroup -Identity <SID>`), not via
  a client-side SID-to-name translation, because BUILTIN SID translation is localized
  by the *client* OS and would produce a false pass.

### Why both checks?

Neither check alone is sufficient:

- **OS check alone** would miss an English-OS domain controller joined to a localized
  domain — the directory names are still localized (Check 2 catches this).
- **AD check alone** would allow a non-English domain controller OS, which the Tier
  Model does not support and which can affect locale-sensitive OS-level operations even
  when the directory names happen to be English.

Requiring **both** guarantees English end-to-end — in the operating system and in the
directory. Each check has its own dedicated fail-fast test.

## Supported vs. unsupported languages

Microsoft fully localizes the Windows **Server** user interface — including Active
Directory built-in group names — for **only 18 languages**. As the
[Available Language Packs for Windows](https://learn.microsoft.com/windows-hardware/manufacture/desktop/available-language-packs-for-windows)
reference states: *"In Windows Server 2012 and later the user interface (UI) is
localized only for the 18 languages listed in bold."*

English is one of those 18. The **other 17 are therefore the complete set of
languages that would trip the gate** — there is no fully-localized Windows Server
language outside this list, so the matrix below is exhaustive.

| #  | Language (`locale`)              | Domain Admins               | Server Operators        | Account Operators             | Result       |
|----|----------------------------------|-----------------------------|-------------------------|-------------------------------|--------------|
| 1  | English (`en-US`)                | Domain Admins               | Server Operators        | Account Operators             | ✅ Supported |
| 2  | Chinese – Simplified (`zh-CN`)   | 域管理员                    | 服务器操作员            | 帐户操作员                    | 🛑 Stops     |
| 3  | Chinese – Traditional (`zh-TW`)  | 網域系統管理員              | 伺服器操作員            | 帳戶操作員                    | 🛑 Stops     |
| 4  | Czech (`cs-CZ`)                  | Správci domény              | Operátoři serveru       | Operátoři účtů                | 🛑 Stops     |
| 5  | Dutch (`nl-NL`)                  | Domeinadmins                | Serveroperators         | Accountoperators              | 🛑 Stops     |
| 6  | French (`fr-FR`)                 | Admins du domaine           | Opérateurs de serveur   | Opérateurs de compte          | 🛑 Stops     |
| 7  | German (`de-DE`)                 | Domänen-Admins              | Server-Operatoren       | Konten-Operatoren             | 🛑 Stops     |
| 8  | Hungarian (`hu-HU`)              | Tartománygazdák             | Kiszolgálókezelők       | Fiókkezelők                   | 🛑 Stops     |
| 9  | Italian (`it-IT`)                | Amministratori di dominio   | Operatori server        | Operatori account             | 🛑 Stops     |
| 10 | Japanese (`ja-JP`)               | ドメイン管理者              | サーバー オペレーター   | アカウント オペレーター       | 🛑 Stops     |
| 11 | Korean (`ko-KR`)                 | 도메인 관리자               | 서버 운영자             | 계정 운영자                   | 🛑 Stops     |
| 12 | Polish (`pl-PL`)                 | Administratorzy domeny      | Operatorzy serwera      | Operatorzy kont               | 🛑 Stops     |
| 13 | Portuguese – Brazil (`pt-BR`)    | Administradores de domínio  | Operadores de servidor  | Operadores de contas          | 🛑 Stops     |
| 14 | Portuguese – Portugal (`pt-PT`)  | Administradores de Domínio  | Operadores de Servidor  | Operadores de Conta           | 🛑 Stops     |
| 15 | Russian (`ru-RU`)                | Администраторы домена       | Операторы сервера       | Операторы учетных записей     | 🛑 Stops     |
| 16 | Spanish (`es-ES`)                | Administradores de dominio  | Operadores de servidor  | Operadores de cuentas         | 🛑 Stops     |
| 17 | Swedish (`sv-SE`)                | Domänadministratörer        | Serveroperatörer        | Kontooperatörer               | 🛑 Stops     |
| 18 | Turkish (`tr-TR`)                | Etki Alanı Yöneticileri     | Sunucu İşletmenleri     | Hesap İşletmenleri            | 🛑 Stops     |

> The non-English names above are illustrative, drawn from localized Windows
> references (German is confirmed against Microsoft Learn). Exact spelling is
> irrelevant to enforcement: the gate only ever compares against the **English**
> names, and every fully-localized language localizes these built-in names as a set,
> so any of the 17 will differ from English and stop.

### What about other languages?

Any language **not** in the 18 above keeps **English** Active Directory names and is
therefore **supported today**:

- **Language Interface Packs (LIPs)** — e.g. Hindi, Bengali, Urdu, Indonesian — are
  partial translations layered on an English base. They do **not** localize AD
  built-in group names, so those installs remain effectively English.
- **Non-bold full Language Packs** — e.g. Arabic, Greek, Hebrew, Danish, Finnish,
  Norwegian, Thai — ship a language pack, but the Windows **Server** UI (and the AD
  names) is not fully localized, so those names also remain English.

In other words, the gate's pass/stop boundary lines up exactly with the set of
domains that would actually break — no more, no less.

## What it would take to support another language

Adding a language is not a code change; it is a **content and validation** effort:

- **Localized configuration files** for every config that names a principal or
  object — for example `config/tiermodel-groups.json`, `config/tiermodel-gpos.json`
  (hundreds of references), `config/tiermodel-acls.json`, `config/tiermodel-users.json`,
  and `config/tiermodel-winlaps.json`.
- **Correct localized names** for every well-known principal the model touches, plus
  any localized container or OU path.
- **Full functional and integration regression** for that language, on a domain
  actually installed in it.

## A possible future model: community language packs

A natural future design is a `-Language <locale>` parameter that selects a
language-specific configuration set:

- The **English** configuration remains the canonical, reference implementation.
- The community **contributes and maintains** the configuration files for each
  additional language.
- Each contributed language requires the contributor to complete **full manual
  regression** using the manual integration workbook (`manual.integration.tests.xlsx`)
  against a domain installed in that language, in addition to the automated tests.

## Challenges and trade-offs

Broad language support has a real, ongoing cost that grows with the project:

- **Release velocity.** Every new feature would have to be implemented **and
  regression-tested across all supported languages** before it could ship. A single
  change becomes an *N*-language change — lots of moving parts, and a much larger
  test matrix on every release.
- **Maintenance burden.** Localized config drifts as features evolve; keeping 17
  additional language sets correct is a continuous commitment, not a one-time port.
- **Contributor coordination.** Each language needs an owner willing to run and
  re-run the manual regression as the product changes.

For these reasons, the pragmatic sequencing is to pursue localization **only once the
Tier Model is a near-complete solution** — i.e. no major features still need to be
added. At that point the per-feature multiplier no longer applies to a moving target,
and the effort becomes a bounded, community-drivable project rather than a permanent
tax on every release.

## Historical context and opportunity

The internal, **closed-source** Microsoft Tier Model tooling — used for roughly a
decade — also supported **English only**. Language coverage has therefore never been
part of the Tier Model, even in its private form.

Now that an **official, open-source** Microsoft Tier Model exists, the community has,
for the first time, a realistic path to collaboratively extend the model to the
remaining 17 fully-localized languages. This document captures the groundwork — the
exhaustive language list and the detection design — so that effort can start from a
known, verified baseline whenever the project is ready.

## References

- [Available Language Packs for Windows](https://learn.microsoft.com/windows-hardware/manufacture/desktop/available-language-packs-for-windows)
  — the statement that Windows Server localizes its UI for only the 18 bold languages.
- [Understand security groups (Active Directory)](https://learn.microsoft.com/windows-server/identity/ad-ds/manage/understand-security-groups)
  — the default/built-in groups and their well-known RIDs.
- [Security identifiers (well-known SIDs)](https://learn.microsoft.com/windows-server/identity/ad-ds/manage/understand-security-identifiers)
  — why SID/RID resolution is language-independent.
- [Issue #23 — Language DC Error](https://github.com/microsoft/ActiveDirectoryTierModel/issues/23)
  — the original report that motivated this requirement.
