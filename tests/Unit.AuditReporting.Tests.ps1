#Requires -Modules Pester
<#
    Unit tests for the Audit-TierModel.ps1 REPORTING path.

    These lock in six reporting-path defects that were fixed with lab evidence but no unit
    coverage. Every one of them was a silent failure: the audit reached the right verdict and
    then rendered it wrongly, so nothing in the suite moved. That is precisely the class of
    defect a regression test has to catch, because a human will not.

    Strategy
    --------
    The reporting logic lives INSIDE Audit-TierModel.ps1, which is invoked with '&'. Mock cannot
    bind to a script-internal function, so the helpers under test are lifted out of the SHIPPING
    file by AST (FunctionDefinitionAst, matched by NAME) and dot-sourced into test scope. That
    tests the real source, survives line drift, and needs no product change. The Text-report
    findings expression is not a function, so it is lifted by locating its own source line in the
    shipping file and evaluating that verbatim.

    House rules applied here
    ------------------------
    * Assert EXACT integers, never -BeGreaterThan 0. A "non-zero" assertion sails past
      partial-sum bugs.
    * Assert relationships and shapes, not exact English prose. Prose changes; the invariant
      does not.
    * Every extraction carries an anti-vacuity assertion proving the thing under test was
      actually loaded and actually ran.
#>

Describe 'Audit-TierModel reporting path' -Tag 'Unit', 'Audit', 'Reporting' {

    BeforeAll {
        $script:AuditScriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'Audit-TierModel.ps1')).Path

        $parseErrors = $null
        $script:AuditAst = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:AuditScriptPath, [ref]$null, [ref]$parseErrors)
        $script:AuditParseErrorCount = @($parseErrors).Count

        # --- Lift the script-internal helpers out of the shipping file, by name -------------
        function Get-AuditFunctionText {
            param([string]$Name)
            $found = $script:AuditAst.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name
            }, $true)
            if (@($found).Count -ne 1) {
                throw "Expected exactly one definition of '$Name' in Audit-TierModel.ps1, found $(@($found).Count)"
            }
            return $found[0].Extent.Text
        }

        . ([scriptblock]::Create((Get-AuditFunctionText -Name 'ConvertTo-TierModelDriftFinding')))
        . ([scriptblock]::Create((Get-AuditFunctionText -Name 'Test-SummaryKey')))
        . ([scriptblock]::Create((Get-AuditFunctionText -Name 'Get-SummaryCount')))

        # --- Lift the Text report's FINDINGS expression, verbatim, from the shipping file ---
        # It is a $(...) subexpression inside an expandable here-string, so it cannot be reached
        # by AST function lookup. Located by its own source text and evaluated as written.
        $auditLines = Get-Content -LiteralPath $script:AuditScriptPath
        $findingsLines = @($auditLines | Where-Object { $_ -match '\$driftFindings\.Count\s+-eq\s+0' })
        $script:FindingsExprSourceCount = $findingsLines.Count
        if ($findingsLines.Count -eq 1) {
            $raw = $findingsLines[0].Trim()
            # strip the outer '$(' ... ')' so the inner if-expression can be invoked directly
            $inner = $raw.Substring(2, $raw.Length - 3)
            $script:RenderFindings = [scriptblock]::Create("param(`$driftFindings) $inner")
        }

        # --- Realistic finding shapes, taken from the actual producers -----------------------
        # Verified against modules\TierModel\public\*.ps1 rather than assumed. Each entry is
        # (label, finding, isDrift).
        $script:ProducerDriftShapes = @(
            @{ Producer = 'Test-TierModelOuAcl (Missing)';   Finding = [PSCustomObject]@{ Type = 'Missing'; ResourceType = 'ACL'; Identifier = 'Tier0Admins -> OU=T0,DC=x,DC=y'; Property = 'TargetOU'; ExpectedValue = 'OU=T0,DC=x,DC=y'; ActualValue = 'Missing'; Details = "Target OU does not exist" } }
            @{ Producer = 'Test-TierModelOuAcl (Mismatch)';  Finding = [PSCustomObject]@{ Type = 'Mismatch'; ResourceType = 'ACL'; Identifier = 'Tier0Admins -> OU=T0,DC=x,DC=y'; Property = 'ACEProperties'; ExpectedValue = 'Deny'; ActualValue = 'Allow'; Details = "ACL delegation properties don't match configuration" } }
            @{ Producer = 'Test-TierModelGPOAudit';          Finding = [PSCustomObject]@{ Type = 'Mismatch'; GpoName = 'Tier0-Baseline'; Message = 'Settings drift detected' } }
            @{ Producer = 'Test-TierModelGPOAudit (Error)';  Finding = [PSCustomObject]@{ Type = 'Error'; GpoName = 'Tier1-Baseline'; Message = 'GPO audit failed' } }
            @{ Producer = 'Test-TierModelAdmx (ADMX)';       Finding = [PSCustomObject]@{ Type = 'ADMX'; ResourceType = 'ADMX'; FileName = 'LAPS.admx'; Message = 'ADMX file missing from Central Store' } }
            @{ Producer = 'Test-TierModelAdmx (ADML)';       Finding = [PSCustomObject]@{ Type = 'ADML'; ResourceType = 'ADML'; FileName = 'LAPS.adml'; Message = 'ADML file hash mismatch' } }
            @{ Producer = 'Test-TierModelMsaAcl';            Finding = [PSCustomObject]@{ Type = 'MissingAcl'; ResourceType = 'ACL'; Identifier = 'msa-svc01'; Property = 'PrincipalsAllowed'; ExpectedValue = 'Tier0Admins'; ActualValue = '' } }
            @{ Producer = 'Test-TierModelGmsaAcl';           Finding = [PSCustomObject]@{ Type = 'UnexpectedAcl'; ResourceType = 'ACL'; Identifier = 'gmsa-svc01'; Property = 'PrincipalsAllowed'; ExpectedValue = ''; ActualValue = 'DOMAIN\Everyone' } }
            @{ Producer = 'Test-TierModelDmsaAcl';           Finding = [PSCustomObject]@{ Type = 'MissingAcl'; ResourceType = 'ACL'; Identifier = 'dmsa-svc01'; Property = 'PrincipalsAllowed'; ExpectedValue = 'Tier0Admins'; ActualValue = '' } }
            @{ Producer = 'Test-TierModelWinLapsAcl';        Finding = [PSCustomObject]@{ Type = 'MissingAcl'; Identifier = 'OU=Tier1Servers,DC=x,DC=y'; Property = 'LapsPermission'; ExpectedValue = 'ReadLapsPassword'; ActualValue = '' } }
            @{ Producer = 'Test-TierModelAuditRule';         Finding = [PSCustomObject]@{ Type = 'MissingAuditRule'; ResourceType = 'DomainAuditRule'; Identifier = 'DC=x,DC=y'; Details = 'Audit rule not present on domain root' } }
            @{ Producer = 'Test-TierModelAuditRule (Right)'; Finding = [PSCustomObject]@{ Type = 'AuditRight'; ResourceType = 'DomainAuditRule'; Identifier = 'DC=x,DC=y'; Details = 'WriteProperty not audited' } }
            @{ Producer = 'Test-TierModelWinLapsDecryptor';  Finding = [PSCustomObject]@{ Status = 'Mismatched'; Name = 'OU=Tier0,DC=x,DC=y'; Reason = 'Decryptor principal differs from configuration' } }
            @{ Producer = 'Test-TierModelAuthPolicy';        Finding = [PSCustomObject]@{ Status = 'Missing'; PolicyName = 'Tier0-AuthPolicy'; Issues = @('Policy does not exist') } }
            @{ Producer = 'Test-TierModelAuthSilo';          Finding = [PSCustomObject]@{ Status = 'NonCompliant'; SiloName = 'Tier0-Silo'; Issues = @('Member list differs', 'Policy not linked') } }
            @{ Producer = 'Test-TierModelCanonicalAcl';      Finding = [PSCustomObject]@{ Status = 'Mismatched'; ResourceType = 'CanonicalAcl'; DistinguishedName = 'OU=Tier0,DC=x,DC=y'; Reason = 'Non-canonical ACE ordering' } }
        )

        # The compliant counterparts of the SAME producers. A fully compliant estate must
        # render an EMPTY body -- the fix must under-report rather than manufacture drift.
        $script:ProducerCompliantShapes = @(
            @{ Producer = 'Test-TierModelMsaAcl';           Finding = [PSCustomObject]@{ Type = 'Compliant'; ResourceType = 'ACL'; Identifier = 'msa-svc01' } }
            @{ Producer = 'Test-TierModelGmsaAcl';          Finding = [PSCustomObject]@{ Type = 'Compliant'; ResourceType = 'ACL'; Identifier = 'gmsa-svc01' } }
            @{ Producer = 'Test-TierModelDmsaAcl';          Finding = [PSCustomObject]@{ Type = 'Compliant'; ResourceType = 'ACL'; Identifier = 'dmsa-svc01' } }
            @{ Producer = 'Test-TierModelWinLapsAcl';       Finding = [PSCustomObject]@{ Type = 'Compliant'; Identifier = 'OU=Tier1Servers,DC=x,DC=y' } }
            @{ Producer = 'Test-TierModelAuditRule';        Finding = [PSCustomObject]@{ Type = 'Compliant'; ResourceType = 'DomainAuditRule'; Identifier = 'DC=x,DC=y' } }
            @{ Producer = 'Test-TierModelWinLapsDecryptor'; Finding = [PSCustomObject]@{ Status = 'Compliant'; Name = 'OU=Tier0,DC=x,DC=y' } }
            @{ Producer = 'Test-TierModelAuthPolicy';       Finding = [PSCustomObject]@{ Status = 'Compliant'; PolicyName = 'Tier0-AuthPolicy'; Issues = @() } }
            @{ Producer = 'Test-TierModelAuthSilo';         Finding = [PSCustomObject]@{ Status = 'Compliant'; SiloName = 'Tier0-Silo'; Issues = @() } }
            @{ Producer = 'Test-TierModelAdmx';             Finding = [PSCustomObject]@{ Status = 'Pass'; ResourceType = 'ADMX'; FileName = 'LAPS.admx' } }
        )
    }

    # =====================================================================================
    Context 'Harness fidelity (anti-vacuity)' {
        # Learning: a probe needs its own fail-for-the-right-reason check, exactly like a test.
        # These assert the extraction worked BEFORE anything below trusts it.

        It 'Parses the shipping Audit-TierModel.ps1 with zero errors' {
            $script:AuditParseErrorCount | Should -Be 0
        }

        It 'Lifted ConvertTo-TierModelDriftFinding out of the shipping file, not a stub' {
            $cmd = Get-Command ConvertTo-TierModelDriftFinding -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.CommandType | Should -Be 'Function'
            # it must be the real body, not an accidentally-empty scriptblock
            $cmd.Definition | Should -Match 'DefaultResourceType'
        }

        It 'Located exactly one FINDINGS rendering expression in the shipping file' {
            # If this ever finds 0 or 2, every rendering test below is measuring the wrong thing.
            $script:FindingsExprSourceCount | Should -Be 1
            $script:RenderFindings | Should -Not -BeNullOrEmpty
        }
    }

    # =====================================================================================
    Context 'BUG-039 - findings render one per line, not flattened onto one line' {
        # An array inside a $(...) subexpression in an expandable string flattens using $OFS,
        # which defaults to a single space. Eleven findings became one 2,267-character line that
        # no line-based tool could parse. Asserting NEWLINE COUNT rather than prose, because the
        # prose is allowed to change and the line structure is not.

        It 'Returns a single string, not an array, so string interpolation cannot flatten it' {
            $findings = 1..5 | ForEach-Object {
                [PSCustomObject]@{ Type = 'Missing'; ResourceType = 'ACL'; Identifier = "id$_"; Details = "detail $_" }
            }
            $rendered = & $script:RenderFindings @($findings)
            # Asserted on the OBJECT, never through the pipeline. `$rendered | Should -BeOfType
            # ([string])` passes against the BUG because piping an array tests each ELEMENT, and
            # every element is a string. Verified against a reverted control: the pipeline form
            # was green with the defect fully restored.
            ($rendered -is [string]) | Should -BeTrue -Because 'an array here is flattened by $OFS at interpolation time'
        }

        It 'Emits exactly one line per finding once interpolated the way the report interpolates it' {
            # This is the real mechanism. The report embeds the expression in an expandable
            # here-string, so an array is joined with $OFS (default: a single space) and eleven
            # findings collapse onto one physical line. Interpolating here reproduces that
            # faithfully instead of testing the expression's raw return value.
            foreach ($n in 1, 2, 5, 11) {
                $findings = 1..$n | ForEach-Object {
                    [PSCustomObject]@{ Type = 'Missing'; ResourceType = 'ACL'; Identifier = "id$_"; Details = "detail $_" }
                }
                $body = "$(& $script:RenderFindings @($findings))"
                $lines = @($body -split "`r`n|`n|`r")
                $lines.Count | Should -Be $n -Because "$n findings must render as $n lines"
            }
        }

        It 'Starts every rendered line with the finding type marker' {
            $findings = 1..4 | ForEach-Object {
                [PSCustomObject]@{ Type = 'Mismatch'; ResourceType = 'GPO'; Identifier = "gpo$_"; Details = "drift $_" }
            }
            $body = "$(& $script:RenderFindings @($findings))"
            $lines = @($body -split "`r`n|`n|`r")
            @($lines | Where-Object { $_ -match '^\[' }).Count | Should -Be 4
        }

        It 'Does not run findings together with a space separator' {
            # The observed symptom: eleven findings became one 2,267-character line in which
            # consecutive findings were separated by ' [' rather than a newline.
            $findings = 1..3 | ForEach-Object {
                [PSCustomObject]@{ Type = 'Missing'; ResourceType = 'ACL'; Identifier = "id$_"; Details = "detail $_" }
            }
            $body = "$(& $script:RenderFindings @($findings))"
            $firstLine = @($body -split "`r`n|`n|`r")[0]
            $firstLine | Should -Not -Match '\] .*\['
        }

        It 'Keeps the join in the shipping source' {
            # Static backstop. The comment above the here-string says "do not simplify the -join
            # away"; this is that instruction with teeth.
            $source = Get-Content -LiteralPath $script:AuditScriptPath -Raw
            $source | Should -Match '-join\s+\[Environment\]::NewLine'
        }
    }

    # =====================================================================================
    Context 'BUG-044 - consolidated body must not silently deny-all its producers' {
        # THE most valuable regression test here. The consolidated body used to filter on
        # Type -eq 'Drift'. When the last producer emitting the literal 'Drift' stopped emitting
        # it, that whitelist became a deny-all: ADMX, MSA/gMSA/dMSA, WinLaps, AuditRule and
        # GPOContent findings vanished from the report while still reaching the counters.
        # NOTHING IN THE SUITE FAILED. Counts are unaffected by the body, so only a test that
        # asserts the BODY can catch it.

        It 'Normalises every real producer drift shape into a renderable finding' {
            foreach ($case in $script:ProducerDriftShapes) {
                $out = @($case.Finding | ConvertTo-TierModelDriftFinding -DefaultResourceType 'Unknown')
                $out.Count | Should -Be 1 -Because "$($case.Producer) drift must survive normalisation"
            }
        }

        It 'Guarantees all four report fields on every producer shape' {
            # The report interpolates Type/ResourceType/Identifier/Details. Under
            # Set-StrictMode -Version Latest a missing property is a terminating error at report
            # time -- i.e. a drifted run producing no report at all.
            foreach ($case in $script:ProducerDriftShapes) {
                $out = @($case.Finding | ConvertTo-TierModelDriftFinding -DefaultResourceType 'Unknown')[0]
                foreach ($field in 'Type', 'ResourceType', 'Identifier', 'Details') {
                    $out.PSObject.Properties.Name | Should -Contain $field -Because "$($case.Producer) -> $field"
                    [string]$out.$field | Should -Not -BeNullOrEmpty -Because "$($case.Producer) -> $field"
                }
            }
        }

        It 'Never invents the identifier Unknown for a producer that supplies one' {
            foreach ($case in $script:ProducerDriftShapes) {
                $out = @($case.Finding | ConvertTo-TierModelDriftFinding -DefaultResourceType 'Unknown')[0]
                $out.Identifier | Should -Not -Be 'Unknown' -Because "$($case.Producer) supplies an identifier"
            }
        }

        It 'Preserves the producer class rather than relabelling everything Drift' {
            # The generic label is what made downstream code guess by substring-matching prose.
            foreach ($case in $script:ProducerDriftShapes) {
                $out = @($case.Finding | ConvertTo-TierModelDriftFinding -DefaultResourceType 'Unknown')[0]
                $expected = if ($case.Finding.PSObject.Properties.Name -contains 'Type') {
                    [string]$case.Finding.Type
                } else {
                    [string]$case.Finding.Status
                }
                $out.Type | Should -Be $expected -Because "$($case.Producer) label must survive"
            }
        }

        It 'Would be emptied by a Type -eq Drift whitelist - proving the old filter was deny-all' {
            # This is the assertion that makes the bug visible instead of theoretical. If someone
            # reintroduces the whitelist, this number tells them exactly what it costs.
            $normalised = @($script:ProducerDriftShapes.Finding | ConvertTo-TierModelDriftFinding -DefaultResourceType 'Unknown')
            $normalised.Count | Should -Be $script:ProducerDriftShapes.Count
            @($normalised | Where-Object { $_.Type -eq 'Drift' }).Count | Should -Be 0
        }

        It 'Applies DefaultResourceType only where the producer supplies none' {
            $withOwn = [PSCustomObject]@{ Type = 'Missing'; ResourceType = 'ADMX'; FileName = 'a.admx'; Message = 'm' }
            $withNone = [PSCustomObject]@{ Type = 'Missing'; GpoName = 'g'; Message = 'm' }
            (@($withOwn | ConvertTo-TierModelDriftFinding -DefaultResourceType 'GPO')[0]).ResourceType | Should -Be 'ADMX'
            (@($withNone | ConvertTo-TierModelDriftFinding -DefaultResourceType 'GPO')[0]).ResourceType | Should -Be 'GPO'
        }

        It 'Routes the consolidated per-entity findings through the normaliser, not a Type literal' {
            # Static guard on the shipping file. The defect was a whitelist of one string; if it
            # ever comes back, this catches it before the lab does.
            $source = Get-Content -LiteralPath $script:AuditScriptPath -Raw
            $source | Should -Match 'ConvertTo-TierModelDriftFinding\s+-DefaultResourceType'
            $source | Should -Not -Match "\`$_\.Type\s+-eq\s+'Drift'"
        }
    }

    # =====================================================================================
    Context 'PRIMARY GUARD - a fully compliant estate reports nothing' {
        # Proven in the lab, never asserted. Made permanent here. The danger with every fix in
        # this family is over-correction: widening a filter until compliant rows are itemised
        # as drift.

        It 'Drops every compliant producer shape' {
            foreach ($case in $script:ProducerCompliantShapes) {
                $out = @($case.Finding | ConvertTo-TierModelDriftFinding -DefaultResourceType 'Unknown')
                $out.Count | Should -Be 0 -Because "$($case.Producer) compliant row is not drift"
            }
        }

        It 'Produces zero findings for a whole compliant estate' {
            $all = @($script:ProducerCompliantShapes.Finding | ConvertTo-TierModelDriftFinding -DefaultResourceType 'Unknown')
            $all.Count | Should -Be 0
        }

        It 'Renders the empty body, not a blank line or a stray marker' {
            $rendered = & $script:RenderFindings @()
            ($rendered -is [string]) | Should -BeTrue
            $rendered | Should -Not -Match '^\['
            $rendered.Trim() | Should -Not -BeNullOrEmpty
        }

        It 'Treats NonCompliant as drift and never as compliant' {
            # Matched exactly, never by wildcard: 'NonCompliant' contains 'Compliant'.
            $f = [PSCustomObject]@{ Status = 'NonCompliant'; SiloName = 'Tier0-Silo'; Issues = @('x') }
            @($f | ConvertTo-TierModelDriftFinding -DefaultResourceType 'AuthSilo').Count | Should -Be 1
        }
    }

    # =====================================================================================
    Context 'BUG-032 - a breakdown must never be able to take the report down' {
        # Under Set-StrictMode -Version Latest an unguarded read of an absent Summary key aborts
        # the whole branch, so a DRIFTED run produced no report at all. Both Summary conventions
        # (hashtable and PSCustomObject) reach these helpers.

        It 'Reports key presence for both hashtable and PSCustomObject summaries' {
            Test-SummaryKey @{ Missing = 1 } 'Missing' | Should -BeTrue
            Test-SummaryKey ([PSCustomObject]@{ Missing = 1 }) 'Missing' | Should -BeTrue
            Test-SummaryKey @{ Missing = 1 } 'MissingGpos' | Should -BeFalse
            Test-SummaryKey ([PSCustomObject]@{ Missing = 1 }) 'MissingGpos' | Should -BeFalse
        }

        It 'Returns 0 rather than throwing for an absent key' {
            Get-SummaryCount @{ Missing = 3 } 'MissingGpos' | Should -Be 0
            Get-SummaryCount ([PSCustomObject]@{ Missing = 3 }) 'MissingGpos' | Should -Be 0
        }

        It 'Returns 0 rather than throwing for a null summary' {
            Test-SummaryKey $null 'Missing' | Should -BeFalse
            Get-SummaryCount $null 'Missing' | Should -Be 0
        }

        It 'Reads the real value when the key is present, in both conventions' {
            Get-SummaryCount @{ Missing = 7 } 'Missing' | Should -Be 7
            Get-SummaryCount ([PSCustomObject]@{ Missing = 7 }) 'Missing' | Should -Be 7
        }

        It 'Counts collections and coerces strings without throwing' {
            Get-SummaryCount @{ Missing = @('a', 'b', 'c') } 'Missing' | Should -Be 3
            Get-SummaryCount @{ Missing = '4' } 'Missing' | Should -Be 4
            Get-SummaryCount @{ Missing = 'not-a-number' } 'Missing' | Should -Be 0
            Get-SummaryCount @{ Missing = $null } 'Missing' | Should -Be 0
        }
    }

    # =====================================================================================
    Context 'BUG-043 - every scope branch publishes its drift breakdown' {
        # Three scope branches published DriftCount but never MissingCount/MismatchCount, so a
        # report read "Missing: 0" directly above real Missing findings. Enforced as an AST
        # ratchet over the shipping file rather than by output-scraping, so a NEW scope branch
        # added later cannot quietly omit the breakdown.

        BeforeAll {
            $script:DriftAssignments = $script:AuditAst.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $n.Left.Extent.Text -match '^\$auditSummary\.DriftCount$'
            }, $true)

            # Nearest enclosing if-statement, NOT outermost: the whole single-entity region is
            # wrapped in one giant `if ($FullDeployment) {} else {}`, so an outermost walk
            # collapses all nine sites into one block and the guard becomes vacuous.
            $script:DriftSites = foreach ($a in $script:DriftAssignments) {
                $node = $a; $near = $null
                while ($node.Parent) {
                    if ($node.Parent -is [System.Management.Automation.Language.IfStatementAst]) { $near = $node.Parent; break }
                    $node = $node.Parent
                }
                [PSCustomObject]@{
                    Line        = $a.Extent.StartLineNumber
                    Condition   = if ($near) { $near.Clauses[0].Item1.Extent.Text } else { '<none>' }
                    BranchText  = if ($near) { $near.Extent.Text } else { '' }
                }
            }

            # Documented exceptions, identified by CONDITION not by line number so they survive
            # line drift. Both are genuine: neither producer has a Missing bucket at all.
            #   * Canonical ACL  - an OU is canonical or it is not; nothing can be "missing".
            #   * ADMX           - the console reports ADMX drift as Mismatched with Missing
            #                      pinned at 0, and $auditSummary.MissingCount is initialised
            #                      to 0, so the published figure is correct by construction.
            $script:MissingCountExempt = @(
                '$canonicalResult.Drift -gt 0'
                '$admxAudit -and ($admxAudit.PSObject.Properties.Name -contains ''Summary'')'
            )
        }

        It 'Finds the expected population of DriftCount publication sites' {
            # A moved count is evidence against the diagnosis, not a fixture to tune. If this
            # number changes, a scope branch was added or removed and the two lists below need
            # a human decision, not a nudge.
            @($script:DriftAssignments).Count | Should -Be 9
        }

        It 'Publishes MismatchCount at every single DriftCount site' {
            foreach ($site in $script:DriftSites) {
                $site.BranchText | Should -Match '\$auditSummary\.MismatchCount' -Because "L$($site.Line): $($site.Condition)"
            }
        }

        It 'Publishes MissingCount at every DriftCount site except the two documented exceptions' {
            foreach ($site in $script:DriftSites) {
                $exempt = $false
                foreach ($e in $script:MissingCountExempt) {
                    if ($site.Condition.Contains($e)) { $exempt = $true; break }
                }
                if ($exempt) { continue }
                $site.BranchText | Should -Match '\$auditSummary\.MissingCount' -Because "L$($site.Line): $($site.Condition)"
            }
        }

        It 'Keeps the exception list honest - exactly two sites are exempt' {
            $exemptCount = 0
            foreach ($site in $script:DriftSites) {
                foreach ($e in $script:MissingCountExempt) {
                    if ($site.Condition.Contains($e)) { $exemptCount++; break }
                }
            }
            # If an exemption stops matching, this fails rather than silently widening the rule.
            $exemptCount | Should -Be 2
        }

        It 'Renders the summary breakdown lines the branches feed' {
            $source = Get-Content -LiteralPath $script:AuditScriptPath -Raw
            $source | Should -Match '-\s+Missing:\s+\$\(\$auditSummary\.MissingCount\)'
            $source | Should -Match '-\s+Mismatch:\s+\$\(\$auditSummary\.MismatchCount\)'
        }
    }

    # =====================================================================================
    Context 'BUG-041 - the summary must not contradict the body' {
        # Observed: "Drift 8 / Missing 8 / Mismatch 0" printed above 1 Missing, 2 Mismatch and
        # 8 Drift findings, because a global override discarded one family's numbers whichever
        # way it ran.
        #
        # KNOWN GENUINE EXCEPTION, ruled documented-by-design by Joel: Test-TierModelGPOAudit
        # and Test-TierModelWinLapsDecryptor define Drift to INCLUDE an error component that the
        # Missing/Mismatch breakdown does not name. So Missing + Mismatch can legitimately be
        # LESS than the drift total. The rule below is therefore an inequality plus an explicit
        # error allowance -- NOT an equality. Do not "tighten" it.

        It 'Reconciles Missing + Mismatch against the drift total, allowing the error component' {
            $cases = @(
                @{ Name = 'clean estate';        Drift = 0;  Missing = 0; Mismatch = 0; Errors = 0 }
                @{ Name = 'pure missing';        Drift = 5;  Missing = 5; Mismatch = 0; Errors = 0 }
                @{ Name = 'mixed';               Drift = 9;  Missing = 5; Mismatch = 4; Errors = 0 }
                @{ Name = 'gpo with error';      Drift = 11; Missing = 6; Mismatch = 4; Errors = 1 }
                @{ Name = 'decryptor w/ errors'; Drift = 7;  Missing = 2; Mismatch = 2; Errors = 3 }
            )
            foreach ($c in $cases) {
                $breakdown = $c.Missing + $c.Mismatch
                $breakdown | Should -BeLessOrEqual $c.Drift -Because "$($c.Name): the breakdown can never exceed the total"
                ($c.Drift - $breakdown) | Should -BeLessOrEqual $c.Errors -Because "$($c.Name): any shortfall is the documented error component and nothing else"
            }
        }

        It 'Rejects a summary that claims more Missing than there are findings' {
            # The exact shape of the observed contradiction: 8/8/0 over a 1/2 body.
            $body = @(
                [PSCustomObject]@{ Type = 'Missing';  ResourceType = 'ACL'; Identifier = 'a'; Details = 'd' }
                [PSCustomObject]@{ Type = 'Mismatch'; ResourceType = 'ACL'; Identifier = 'b'; Details = 'd' }
                [PSCustomObject]@{ Type = 'Mismatch'; ResourceType = 'GPO'; Identifier = 'c'; Details = 'd' }
            )
            $normalised = @($body | ConvertTo-TierModelDriftFinding -DefaultResourceType 'Unknown')
            @($normalised | Where-Object { $_.Type -eq 'Missing' }).Count  | Should -Be 1
            @($normalised | Where-Object { $_.Type -eq 'Mismatch' }).Count | Should -Be 2
            $normalised.Count | Should -Be 3
        }
    }
}

# =========================================================================================
Describe 'BUG-040 - resolved identifiers on OU ACL findings' -Tag 'Unit', 'Audit', 'Reporting' {
    <#
        Eight identifiers shipped a literal {{DOMAIN_DN}} to the customer because five producer
        sites re-read the raw $acl.targetOUPath instead of the resolved local.

        DELIBERATELY NOT ASSERTED GLOBALLY. Four sites were left on the raw path on purpose: in a
        resolution-failure catch the resolved local holds the PREVIOUS iteration's value, so a
        silently-wrong identifier is worse than a visible placeholder. A test that forbade the
        placeholder everywhere would pin the wrong invariant and would be "fixed" by breaking the
        product. These tests cover the SUCCESS paths only, where resolution demonstrably ran.
    #>

    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..' 'modules' 'TierModel' 'TierModel.psd1') -Force

        $script:DDN = 'DC=test,DC=local'
        $script:DC  = 'dc01.test.local'

        # Config paths carry the REAL placeholder token and the REAL Resolve-TierModelPlaceholder
        # is left unmocked, so this exercises resolution rather than a fixture that pre-resolves.
        $script:CfgPlaceholder = [PSCustomObject]@{
            aclDelegations = @(
                [PSCustomObject]@{
                    identityreference                  = 'Tier0Admins'
                    targetOUPath                       = 'OU=Tier0,{{DOMAIN_DN}}'
                    accesscontroltype                  = 'Allow'
                    activedirectoryrights              = @('GenericAll')
                    activeDirectorysecurityinheritance = 'All'
                    objecttype                         = ''
                }
            )
            guidMappings = [PSCustomObject]@{ staticMappings = @{}; dynamicMappings = @{}; friendlyNameMappings = @{} }
        }
    }

    BeforeEach {
        Mock Resolve-TierModelDomainDN -ModuleName TierModel { return $script:DDN }
        Mock Write-TierModelLog -ModuleName TierModel { }
        Mock Get-ADGroup -ModuleName TierModel { param($Identity, $Server) [PSCustomObject]@{ SamAccountName = $Identity } }
        Mock Get-ADUser -ModuleName TierModel { throw 'User not found' }
    }

    It 'Resolves the placeholder in the identifier of a target-OU-missing finding' {
        Mock Get-ADOrganizationalUnit -ModuleName TierModel { throw 'OU not found' }
        $result = Test-TierModelOuAcl -Config $script:CfgPlaceholder -DomainController $script:DC -Silent

        # anti-vacuity: the run must actually have produced the finding under test
        $f = @($result.Findings | Where-Object { $_.Property -eq 'TargetOU' })
        $f.Count | Should -Be 1
        $f[0].Identifier | Should -Not -Match '\{\{'
        $f[0].Identifier | Should -BeLike "*$script:DDN"
    }

    It 'Resolves the placeholder in the identifier of a missing-ACE finding' {
        Mock Get-ADOrganizationalUnit -ModuleName TierModel { param($Identity, $Server) [PSCustomObject]@{ DistinguishedName = $Identity } }
        Mock Get-Acl -ModuleName TierModel {
            param($Path)
            $rule = [PSCustomObject]@{
                IdentityReference     = [PSCustomObject]@{ Value = 'TEST\SomeoneElse' }
                AccessControlType     = [System.Security.AccessControl.AccessControlType]::Allow
                ActiveDirectoryRights = [System.DirectoryServices.ActiveDirectoryRights]::GenericAll
                InheritanceType       = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All
                ObjectType            = [Guid]::Empty
                InheritedObjectType   = [Guid]::Empty
            }
            [PSCustomObject]@{ Path = $Path; Access = @($rule) }
        }
        $result = Test-TierModelOuAcl -Config $script:CfgPlaceholder -DomainController $script:DC -Silent

        $f = @($result.Findings | Where-Object { $_.Property -eq 'ACE' })
        $f.Count | Should -Be 1
        $f[0].Identifier | Should -Not -Match '\{\{'
        $f[0].Details    | Should -Not -Match '\{\{'
    }

    It 'Resolves the placeholder in the identifier of an unreadable-ACL finding' {
        Mock Get-ADOrganizationalUnit -ModuleName TierModel { param($Identity, $Server) [PSCustomObject]@{ DistinguishedName = $Identity } }
        Mock Get-Acl -ModuleName TierModel { throw 'Access denied' }
        $result = Test-TierModelOuAcl -Config $script:CfgPlaceholder -DomainController $script:DC -Silent

        $f = @($result.Findings | Where-Object { $_.Property -eq 'ACLAccess' })
        $f.Count | Should -Be 1
        $f[0].Identifier | Should -Not -Match '\{\{'
    }

    It 'Keeps the four deliberate raw-path sites out of scope - documented, not asserted' {
        # This test exists to STOP a future reader from adding a global "no {{ anywhere" rule.
        # The outer catch of Test-TierModelOuAcl intentionally reports the RAW configured path,
        # because the resolved local is stale at that point. Asserting the intent as a comment
        # is not enough; asserting it here makes the exception discoverable from a failing run.
        $source = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..' 'modules' 'TierModel' 'public' 'Test-TierModelOuAcl.ps1') -Raw
        $source | Should -Match '\$\(\$acl\.identityreference\) → \$\(\$acl\.targetOUPath\)'
    }
}
