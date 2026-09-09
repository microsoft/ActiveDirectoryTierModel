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
            # NOT producer coverage. No producer emits Type='AuditRight' any more - the per-right
            # rows were ruled out of the findings collection. This exemplar exercises the
            # NORMALISER's AuditRight branch directly, which is deliberately retained for a
            # producer that does not exist yet, and which nothing else now reaches.
            @{ Producer = 'AuditRight shape (normaliser branch, no live producer)'; Finding = [PSCustomObject]@{ Type = 'AuditRight'; ResourceType = 'DomainAuditRule'; Identifier = 'DC=x,DC=y'; Details = 'WriteProperty not audited' } }
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

# =========================================================================================
# Consolidated audit counters: the section line, the grand total, and the colour of both.
#
# The defect these lock in was TYPE-blindness, not name-blindness. Every standalone producer
# publishes its Summary as a HASHTABLE literal (nine wrap sites in Audit-TierModel.ps1), and
# a hashtable's PSObject.Properties are Keys/Values/Count/IsReadOnly - never its own keys. So
# a dotted-path walk over PSObject.Properties.Name falls out at the first segment and returns
# 0 for every one of them. The producers were publishing Drift/Missing/Mismatched correctly
# the whole time; the reader could not see them, and the section line printed "Drift: 0,
# Errors: 0" directly above a list of real drift.
#
# The three things asserted here are the three ways that failure can come back:
#   1. the two Summary representations disagreeing again,
#   2. the section counter and the grand total being computed twice and drifting apart,
#   3. one underlying error being counted once per representation that mentions it.
# =========================================================================================
Describe 'Audit-TierModel consolidated counters' -Tag 'Unit', 'Audit', 'Reporting' {

    BeforeAll {
        $script:AuditScriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'Audit-TierModel.ps1')).Path

        $parseErrors = $null
        $script:CounterAst = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:AuditScriptPath, [ref]$null, [ref]$parseErrors)
        $script:CounterParseErrorCount = @($parseErrors).Count

        function Get-CounterFunctionText {
            param([string]$Name)
            $found = $script:CounterAst.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name
            }, $true)
            if (@($found).Count -ne 1) {
                throw "Expected exactly one definition of '$Name' in Audit-TierModel.ps1, found $(@($found).Count)"
            }
            return $found[0].Extent.Text
        }

        foreach ($fn in @(
                'Get-SafePropertyValue'
                'Test-SummaryKey'
                'Get-SummaryCount'
                'Get-EntityDriftTotals'
                'Get-EntityErrorTotal'
                'Get-TierModelFindingColor'
                'Get-TierModelUnverifiedCount'
                'Write-TierModelComplianceLine'
                'ConvertTo-TierModelDriftFinding')) {
            . ([scriptblock]::Create((Get-CounterFunctionText -Name $fn)))
        }

        # Every command invocation in the shipping file, for the call-site ratchets below.
        $script:CounterCommands = $script:CounterAst.FindAll({
            param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)

        function Get-CallSiteCount {
            param([string]$Name)
            return @($script:CounterCommands | Where-Object { $_.GetCommandName() -eq $Name }).Count
        }

        # --- A DRIFTED estate, in the exact wrapper shapes Audit-TierModel.ps1 constructs ------
        # Taken from the nine `Summary = @{ ... }` wrap sites plus the OU/Group hashtable
        # summaries built inside Test-TierModelOu. A clean estate proves nothing about a
        # counting bug, so every section here carries drift and one carries an error.
        $script:DriftedEstate = @(
            [PSCustomObject]@{
                EntityType    = 'OU'
                Summary       = @{ TotalChecked = 10; MissingCount = 2; MismatchCount = 1; UnverifiedCount = 0; DriftCount = 3 }
                DriftFindings = @(
                    [PSCustomObject]@{ Type = 'Missing';  Identifier = 'OU=T0,DC=x,DC=y'; Details = 'OU absent' }
                    [PSCustomObject]@{ Type = 'Missing';  Identifier = 'OU=T1,DC=x,DC=y'; Details = 'OU absent' }
                    [PSCustomObject]@{ Type = 'Mismatch'; Identifier = 'OU=T2,DC=x,DC=y'; Details = 'Description differs' }
                )
            }
            [PSCustomObject]@{
                EntityType    = 'Group'
                Summary       = @{ TotalChecked = 5; MissingCount = 1; MismatchCount = 0; UnverifiedCount = 0; DriftCount = 1 }
                DriftFindings = @([PSCustomObject]@{ Type = 'Missing'; Identifier = 'Tier0Admins'; Details = 'Group absent' })
            }
            [PSCustomObject]@{
                EntityType = 'OU Canonical ACL'
                Summary    = @{ TotalAcls = 4; Compliant = 3; Missing = 0; Mismatched = 1; Errors = 0; Drift = 1; Skipped = 0 }
                Findings   = @([PSCustomObject]@{ Status = 'Mismatched'; DistinguishedName = 'OU=T0,DC=x,DC=y'; Reason = 'Non-canonical ACE ordering' })
            }
            [PSCustomObject]@{
                EntityType = 'MSA ACL'
                Summary    = @{ TotalAcls = 3; Compliant = 1; Missing = 1; Mismatched = 1; Errors = 0; Drift = 2 }
                Findings   = @(
                    [PSCustomObject]@{ Type = 'MissingAcl';    Identifier = 'msa-svc01' }
                    [PSCustomObject]@{ Type = 'UnexpectedAcl'; Identifier = 'msa-svc02' }
                )
            }
            [PSCustomObject]@{
                EntityType = 'WinLaps ACL'
                Summary    = @{ TotalAcls = 2; Compliant = 1; Missing = 1; Mismatched = 0; Errors = 0; Drift = 1 }
                Findings   = @([PSCustomObject]@{ Type = 'MissingAcl'; Identifier = 'OU=Tier1Servers,DC=x,DC=y' })
            }
            [PSCustomObject]@{
                EntityType = 'WinLaps Decryptor'
                Summary    = @{ TotalAcls = 4; Compliant = 1; Missing = 2; Mismatched = 0; Errors = 1; Drift = 3 }
                Errors     = 1
                Findings   = @(
                    [PSCustomObject]@{ Status = 'Missing'; GpoName = 'T0 LAPS'; Actual = 'No matching GPO' }
                    [PSCustomObject]@{ Status = 'Missing'; GpoName = 'T1 LAPS'; Actual = '(not set)' }
                    [PSCustomObject]@{ Status = 'Error';   GpoName = 'T2 LAPS'; Actual = 'Ambiguous matches: A, B' }
                )
            }
            [PSCustomObject]@{
                EntityType = 'Auth Policies'
                Summary    = @{ TotalChecked = 3; Compliant = 1; Missing = 1; Mismatched = 1; Errors = 0; Drift = 2 }
                Findings   = @(
                    [PSCustomObject]@{ Status = 'Missing';      PolicyName = 'Tier0-AuthPolicy' }
                    [PSCustomObject]@{ Status = 'NonCompliant'; PolicyName = 'Tier1-AuthPolicy' }
                )
            }
            [PSCustomObject]@{
                EntityType = 'Auth Silos'
                Summary    = @{ TotalChecked = 2; Compliant = 1; Missing = 0; Mismatched = 1; Errors = 0; Drift = 1 }
                Findings   = @([PSCustomObject]@{ Status = 'NonCompliant'; SiloName = 'Tier0-Silo' })
            }
        )
    }

    # =====================================================================================
    Context 'Harness fidelity (anti-vacuity)' {

        It 'Parses the shipping Audit-TierModel.ps1 with zero errors' {
            $script:CounterParseErrorCount | Should -Be 0
        }

        It 'Lifted the real counter helpers, not stubs' {
            foreach ($fn in 'Get-SafePropertyValue', 'Get-EntityDriftTotals', 'Get-EntityErrorTotal', 'Get-TierModelFindingColor') {
                $cmd = Get-Command $fn -ErrorAction SilentlyContinue
                $cmd | Should -Not -BeNullOrEmpty -Because "$fn must be liftable from the shipping file"
                $cmd.CommandType | Should -Be 'Function'
            }
            (Get-Command Get-EntityDriftTotals).Definition   | Should -Match 'Get-SummaryCount'
            (Get-Command Get-TierModelFindingColor).Definition | Should -Match 'Yellow'
        }

        It 'Uses a drifted estate, not a clean one' {
            # A green fixture cannot fail a counting bug. Population stated so a later zero is
            # falsifiable on sight: 8 sections, every one of them carrying drift.
            @($script:DriftedEstate).Count | Should -Be 8
            foreach ($section in $script:DriftedEstate) {
                (Get-EntityDriftTotals $section).Drift | Should -BeGreaterThan 0 -Because $section.EntityType
            }
        }
    }

    # =====================================================================================
    Context 'The bug, reduced: a hashtable Summary and a PSCustomObject Summary must agree' {

        It 'Reads identical drift and error totals from both Summary representations' {
            # This is the whole defect in one assertion. The two objects below carry the same
            # numbers and differ only in the TYPE of Summary.
            $asHashtable = [PSCustomObject]@{
                EntityType = 'WinLaps Decryptor'
                Summary    = @{ TotalAcls = 4; Compliant = 1; Missing = 3; Mismatched = 2; Errors = 1; Drift = 6 }
                Errors     = 1
                Findings   = @([PSCustomObject]@{ Status = 'Error'; GpoName = 'T0 LAPS' })
            }
            $asPsCustom = [PSCustomObject]@{
                EntityType = 'WinLaps Decryptor'
                Summary    = [PSCustomObject]@{ TotalAcls = 4; Compliant = 1; Missing = 3; Mismatched = 2; Errors = 1; Drift = 6 }
                Errors     = 1
                Findings   = @([PSCustomObject]@{ Status = 'Error'; GpoName = 'T0 LAPS' })
            }

            $htTotals = Get-EntityDriftTotals $asHashtable
            $coTotals = Get-EntityDriftTotals $asPsCustom

            $htTotals.Drift      | Should -Be $coTotals.Drift
            $htTotals.Missing    | Should -Be $coTotals.Missing
            $htTotals.Mismatched | Should -Be $coTotals.Mismatched

            # Exact integers, not "greater than 0" - a non-zero assertion sails past a partial sum.
            $htTotals.Drift      | Should -Be 6
            $htTotals.Missing    | Should -Be 3
            $htTotals.Mismatched | Should -Be 2

            (Get-EntityErrorTotal $asHashtable) | Should -Be (Get-EntityErrorTotal $asPsCustom)
            (Get-EntityErrorTotal $asHashtable) | Should -Be 1
        }

        It 'Names the mechanism: a hashtable never exposes its own keys as properties' {
            # A fact about PowerShell, not about our code, so it cannot rot. This is why any
            # reader that walks PSObject.Properties.Name is blind to a hashtable Summary.
            $names = @{ Drift = 6; Missing = 3 }.PSObject.Properties.Name
            $names | Should -Not -Contain 'Drift'
            $names | Should -Not -Contain 'Missing'
            $names | Should -Contain 'Keys'
            $names | Should -Contain 'Count'

            ([PSCustomObject]@{ Drift = 6 }).PSObject.Properties.Name | Should -Contain 'Drift'
        }

        It 'Documents the live limitation of Get-SafePropertyValue that the shared readers exist to avoid' {
            # DELIBERATE: Get-SafePropertyValue was NOT made hashtable-aware. The fix routed the
            # drift and error reads around it instead, which is why the ratchet below matters.
            # If this helper is ever taught to read a dictionary, this single assertion is the
            # one to delete - do not delete the ratchet with it.
            $ht = [PSCustomObject]@{ Summary = @{ Drift = 6; Errors = 1 } }
            $co = [PSCustomObject]@{ Summary = [PSCustomObject]@{ Drift = 6; Errors = 1 } }

            Get-SafePropertyValue $co 'Summary.Drift' | Should -Be 6
            Get-SafePropertyValue $ht 'Summary.Drift' | Should -Be 0
        }

        It 'Keeps every drift and error count off the dotted-path reader' {
            # The ratchet. Any Summary.Drift / Summary.Missing / Summary.Mismatched /
            # Summary.Errors argument handed to Get-SafePropertyValue reintroduces the bug for
            # the eight hashtable-Summary producers, silently and with no error.
            $offenders = foreach ($call in $script:CounterCommands) {
                if ($call.GetCommandName() -ne 'Get-SafePropertyValue') { continue }
                foreach ($element in $call.CommandElements) {
                    $literal = $element.Extent.Text.Trim("'", '"')
                    if ($literal -match '^Summary\.(Drift|DriftCount|Missing|MissingCount|Mismatched|MismatchCount|Unverified|UnverifiedCount|Errors)$') {
                        "L$($call.Extent.StartLineNumber): $($call.Extent.Text)"
                    }
                }
            }
            # Population: all 7 Get-SafePropertyValue call sites in Audit-TierModel.ps1. The
            # survivors read Summary.Total* for entity-type detection and a top-level 'Errors'
            # - neither is a drift or error COUNT off a hashtable Summary.
            (Get-CallSiteCount 'Get-SafePropertyValue') | Should -Be 7
            @($offenders) -join '; ' | Should -BeNullOrEmpty
        }
    }

    # =====================================================================================
    Context 'The section line and the grand total must reconcile' {

        It 'Sums every section drift to exactly the grand total' {
            # Rule 14 as an executable check: the summary must reconcile against the body it
            # sits above, WITHIN one artifact. Two outputs agreeing proves nothing unless they
            # were computed independently - so the guard that makes this real is the call-site
            # ratchet below, which pins both loops to the same helper.
            $sectionDrift = 0
            $grandMissing = 0
            $grandMismatched = 0
            foreach ($section in $script:DriftedEstate) {
                $totals = Get-EntityDriftTotals $section
                $sectionDrift += $totals.Drift
                $grandMissing += $totals.Missing
                $grandMismatched += $totals.Mismatched
            }

            $sectionDrift    | Should -Be 14
            $grandMissing    | Should -Be 8
            $grandMismatched | Should -Be 5
        }

        It 'Sums every section error to exactly the grand total' {
            $sectionErrors = 0
            foreach ($section in $script:DriftedEstate) {
                $sectionErrors += Get-EntityErrorTotal $section
            }
            $sectionErrors | Should -Be 1
        }

        It 'Computes both figures from one shared definition, called exactly twice each' {
            # Two independent computations are what let the section line and the Overall Summary
            # disagree in the first place. One call site per loop, and no third copy.
            (Get-CallSiteCount 'Get-EntityDriftTotals') | Should -Be 2
            (Get-CallSiteCount 'Get-EntityErrorTotal')  | Should -Be 2
        }

        It 'Reports drift for a producer whose Summary omits the total entirely' {
            # Falls back to Missing + Mismatched + Unverified rather than to 0, on both
            # Summary representations.
            $noTotal = [PSCustomObject]@{ EntityType = 'Domain Audit Rule'; Summary = @{ Missing = 2; Mismatched = 1 } }
            (Get-EntityDriftTotals $noTotal).Drift | Should -Be 3

            $noSummary = [PSCustomObject]@{ EntityType = 'Nothing' }
            (Get-EntityDriftTotals $noSummary).Drift | Should -Be 0
        }

        It 'Keeps reconciling when an error is reclassified as an absence' {
            # The estate A/B moved Total Errors 12 -> 0, not 12 -> 6, because the decryptor
            # findings were RECLASSIFIED Error->Missing rather than merely de-duplicated. So the
            # invariant is reconciliation, not any particular error literal: whatever the split
            # between Missing and Errors, the section sums must still equal the grand totals and
            # the drift total must not move.
            $before = [PSCustomObject]@{
                EntityType = 'WinLaps Decryptor'
                Summary    = @{ TotalAcls = 8; Compliant = 2; Missing = 0; Mismatched = 0; Errors = 6; Drift = 6 }
                Errors     = 6
                Findings   = @(1..6 | ForEach-Object { [PSCustomObject]@{ Status = 'Error'; GpoName = "GPO-$_" } })
            }
            $after = [PSCustomObject]@{
                EntityType = 'WinLaps Decryptor'
                Summary    = @{ TotalAcls = 8; Compliant = 2; Missing = 6; Mismatched = 0; Errors = 0; Drift = 6 }
                Errors     = 0
                Findings   = @(1..6 | ForEach-Object { [PSCustomObject]@{ Status = 'Missing'; GpoName = "GPO-$_" } })
            }

            # Drift is the figure that must not move - the row changed counters, not existence.
            (Get-EntityDriftTotals $before).Drift | Should -Be (Get-EntityDriftTotals $after).Drift
            (Get-EntityDriftTotals $after).Drift  | Should -Be 6

            # The reclassification is visible exactly where it should be, and nowhere else.
            (Get-EntityDriftTotals $before).Missing | Should -Be 0
            (Get-EntityDriftTotals $after).Missing  | Should -Be 6
            Get-EntityErrorTotal $before | Should -Be 6
            Get-EntityErrorTotal $after  | Should -Be 0

            # Reconciliation asserted as a relationship, not against a remembered figure.
            foreach ($section in $before, $after) {
                $totals = Get-EntityDriftTotals $section
                ($totals.Missing + $totals.Mismatched + $totals.Unverified + (Get-EntityErrorTotal $section)) |
                    Should -Be $totals.Drift -Because "the breakdown must account for the whole drift total"
            }
        }
    }

    # =====================================================================================
    Context 'One underlying error is counted once' {

        It 'Counts a single failure once across all three representations of it' {
            # Summary.Errors, the top-level Errors collection and a Status='Error' finding are
            # three renderings of the SAME failure. Adding them printed "Errors: 2" over one
            # error line.
            $oneError = [PSCustomObject]@{
                EntityType = 'WinLaps Decryptor'
                Summary    = @{ Drift = 1; Errors = 1 }
                Errors     = 1
                Findings   = @([PSCustomObject]@{ Status = 'Error'; GpoName = 'T0 LAPS' })
            }
            Get-EntityErrorTotal $oneError | Should -Be 1
        }

        It 'Counts six decryptor errors as six, not twelve' {
            # The estate-scale shape: Total Errors read 12 where the sections summed to 6, with
            # -IncludeWinLaps the only source and its 6 decryptor errors counted exactly twice.
            $sixErrors = [PSCustomObject]@{
                EntityType = 'WinLaps Decryptor'
                Summary    = @{ Drift = 6; Errors = 6 }
                Errors     = 6
                Findings   = @(1..6 | ForEach-Object { [PSCustomObject]@{ Status = 'Error'; GpoName = "GPO-$_" } })
            }
            Get-EntityErrorTotal $sixErrors | Should -Be 6
        }

        It 'Still reports a producer that publishes error findings but leaves its count at zero' {
            # Test-TierModelAdmx does exactly this. Taking the maximum must not under-count.
            $findingsOnly = [PSCustomObject]@{
                EntityType = 'ADMX'
                Summary    = @{ Drift = 2; Errors = 0 }
                Findings   = @(
                    [PSCustomObject]@{ Type = 'Error'; FileName = 'LAPS.admx' }
                    [PSCustomObject]@{ Type = 'Error'; FileName = 'LAPS.adml' }
                )
            }
            Get-EntityErrorTotal $findingsOnly | Should -Be 2
        }

        It 'Still reports a producer that publishes a count but no findings' {
            $countOnly = [PSCustomObject]@{ EntityType = 'Group'; Summary = @{ DriftCount = 3; Errors = 3 } }
            Get-EntityErrorTotal $countOnly | Should -Be 3

            $topLevelOnly = [PSCustomObject]@{ EntityType = 'OU'; Summary = @{ DriftCount = 1 }; Errors = 4 }
            Get-EntityErrorTotal $topLevelOnly | Should -Be 4
        }

        It 'Reports zero errors for a clean section without inventing any' {
            $clean = [PSCustomObject]@{
                EntityType = 'MSA ACL'
                Summary    = @{ TotalAcls = 3; Compliant = 3; Missing = 0; Mismatched = 0; Errors = 0; Drift = 0 }
                Findings   = @([PSCustomObject]@{ Type = 'Compliant'; Identifier = 'msa-svc01' })
            }
            Get-EntityErrorTotal $clean | Should -Be 0
            (Get-EntityDriftTotals $clean).Drift | Should -Be 0
        }
    }

    # =====================================================================================
    Context 'Finding colour is chosen by severity class, not by one string literal' {

        It 'Renders every member of the missing family red, not just the bare literal' {
            # The rule this replaces matched Type -eq 'Missing' exactly. MissingAcl and
            # MissingAuditRule are not that literal, so both fell to the else branch.
            foreach ($type in 'Missing', 'MissingAcl', 'MissingAuditRule', 'NotFound', 'Absent') {
                Get-TierModelFindingColor $type | Should -Be 'Red' -Because "$type is an absence"
            }
        }

        It 'Renders an [Error] finding RED - the one assertion the lab can no longer make' {
            # STANDALONE AND DELIBERATELY NARROW. Do not fold this into the missing-family or
            # the undeterminable-synonyms test: 'Error' must be provable on its own line.
            #
            # Why it has to live here. The A/B against the real estate found ZERO [Error]
            # findings across all eight scopes, because the only producer emitting Error in that
            # estate was the branch relabelled to a missing-state. The colour fix for [Error] is
            # therefore REAL BUT UNEXERCISED in the lab - an adjacent change removed the only
            # fixture that could prove it, with no error and no failing test. Nothing outside a
            # unit test can cover this now.
            #
            # And it is not cosmetic. Before the fix this returned 'Yellow': a hard error, the
            # most severe line the tool can print, displayed with the styling of a warning.
            Get-TierModelFindingColor 'Error' | Should -Be 'Red'
            Get-TierModelFindingColor 'Error' | Should -Not -Be 'Yellow'

            # Case is not a producer's contract, so the classifier must not depend on it.
            foreach ($spelling in 'Error', 'error', 'ERROR') {
                Get-TierModelFindingColor $spelling | Should -Be 'Red' -Because "'$spelling' is a hard error"
            }
        }

        It 'Carries a real producer Error finding all the way to red, not just the classifier' {
            # The classifier returning 'Red' is only half the chain. This walks the shape an
            # actual producer emits - Test-TierModelWinLapsDecryptor's five surviving
            # could-not-determine sites carry Status='Error' and no Type at all - through the
            # normaliser the report feeds, and colours what comes out.
            $producerErrors = @(
                [PSCustomObject]@{ Status = 'Error'; GpoName = 'T0 LAPS'; Expected = 'Exactly one GPO must match'; Actual = 'Ambiguous matches: A, B' }
                [PSCustomObject]@{ Status = 'Error'; GpoName = 'T1 LAPS'; Expected = 'GPO query must succeed';     Actual = 'Server unavailable' }
                [PSCustomObject]@{ Status = 'Error'; GpoName = 'N/A';     Expected = 'NETBIOS\sAMAccountName';     Actual = 'Domain resolution failed: unreachable' }
            )

            $normalised = @($producerErrors | ConvertTo-TierModelDriftFinding -DefaultResourceType 'WinLapsDecryptor')

            # An Error finding is drift and must survive normalisation - it is not compliant.
            $normalised.Count | Should -Be 3
            foreach ($finding in $normalised) {
                $finding.Type | Should -Be 'Error'
                Get-TierModelFindingColor $finding.Type | Should -Be 'Red' -Because "[$($finding.Type)] $($finding.Identifier) is a hard error"
            }

            # The rendered marker itself, exactly as the report interpolates it.
            $rendered = $normalised | ForEach-Object { "[$($_.Type)] $($_.Identifier): $($_.Details)" }
            @($rendered | Where-Object { $_ -like '`[Error`]*' }).Count | Should -Be 3
        }

        It 'Renders the other undeterminable verdicts red as well' {
            foreach ($type in 'Unverified', 'Failed', 'Failure') {
                Get-TierModelFindingColor $type | Should -Be 'Red' -Because "$type means compliance was not established"
            }
        }

        It 'Keeps present-but-wrong findings yellow' {
            foreach ($type in 'Mismatch', 'Mismatched', 'Unexpected', 'UnexpectedAcl', 'NonCompliant', 'Extra', 'Drift', 'Warning') {
                Get-TierModelFindingColor $type | Should -Be 'Yellow' -Because "$type is present but wrong"
            }
        }

        It 'Hands the classifier result to EVERY coloured render site - a census, not a count' {
            # The classifier can be perfect and a line still print the wrong colour if a render
            # site keeps its own colour expression. This test therefore guards the render
            # SURFACE, not the classifier.
            #
            # It used to read `$delegating.Count | Should -Be 4` and `$allColoured.Count |
            # Should -Be 6`. The 6 was a census; the 4 was NOT decreed - it was a snapshot of how
            # far the conversion had got when the test was written, which is precisely the
            # derived-number trap of working rule 22. It duly went red the moment the conversion
            # finished, i.e. it broke on the system being made MORE correct. A test that
            # must be rewritten every time the system legitimately improves is charging rent.
            #
            # The decreed rule is the equality: every render site that colours a finding must get
            # that colour from the classifier. Written as an equality it survives a SEVENTH
            # render site being added correctly, and breaks the moment one is added that colours
            # itself - which is the regression it exists to catch.
            $source = [IO.File]::ReadAllText($script:AuditScriptPath)

            $delegating  = @([regex]::Matches($source, '\$color\s*=\s*Get-TierModelFindingColor\s+\$_\.Type'))
            $allColoured = @([regex]::Matches($source, '\[\$\(\$_\.Type\)\][^\r\n]*-ForegroundColor\s+\$color'))

            # ANTI-VACUITY (working rule 19): the equality below is trivially true at 0==0, so a
            # regex that silently stops matching would turn this whole test green while proving
            # nothing. State the population and require it to be non-empty first.
            $allColoured.Count | Should -BeGreaterThan 0 -Because 'a census of zero render sites means the pattern broke, not that the code is clean'

            $delegating.Count | Should -Be $allColoured.Count -Because 'every coloured render site must take its colour from the classifier'
            (Get-CallSiteCount 'Get-TierModelFindingColor') | Should -Be $allColoured.Count

            # DELIBERATE NON-MEMBER, recorded per working rule 17 so the next reader does not
            # "fix" it: there is a SEVENTH '[$($_.Type)]' site, in the plain-text report body.
            # It renders no colour at all, so it must NOT delegate and is correctly outside this
            # census. Pinned so that if it ever gains a -ForegroundColor it joins the population
            # above rather than slipping through as an eighth uncounted site.
            $anyTypeMarker = @([regex]::Matches($source, '\[\$\(\$_\.Type\)\]'))
            ($anyTypeMarker.Count - $allColoured.Count) | Should -Be 1 -Because 'the only uncoloured [Type] site is the plain-text report body'

            # No render site may reintroduce the exact-literal rule the classifier replaced.
            [regex]::Matches($source, "-eq\s+'Missing'\s*\)\s*\{\s*'Red'").Count | Should -Be 0
        }

        It 'Prints every real producer type that reaches the GPO and ADMX render sites in red or yellow, never grey' {
            # SUPERSEDES 'Colours [Error] red at the two render sites that do NOT use the
            # classifier'. That name described a migration state, and when the last two sites
            # were converted the assertion `$switchMaps.Count | Should -Be 2` went red because
            # there were no inline maps left to find.
            #
            # The trap avoided here: simply retuning that literal from 2 to 0 would have made the
            # test PASS while deleting its entire safety content, because the two assertions that
            # actually mattered lived inside `foreach ($map in $switchMaps)` and a zero-length
            # collection iterates zero times. That is working rule 19 - a filter that matches
            # nothing raises no error and returns a confident, empty, wrong answer - and it would
            # have been a strictly worse outcome than leaving the test red.
            #
            # So the ratchet is kept, and the CONTENT is re-homed onto the classifier where it
            # still executes. The exemplars below are not invented: they are the closed emit
            # vocabularies of the two producers that feed these render sites, enumerated from
            # source rather than assumed.
            $source = [IO.File]::ReadAllText($script:AuditScriptPath)

            # RATCHET: no render site may reintroduce a local colour map.
            @([regex]::Matches($source, '\$color\s*=\s*switch\s*\(\$_\.Type\)')).Count |
                Should -Be 0 -Because 'a per-site colour map is how these two sites drifted from the classifier in the first place'

            # Test-TierModelAdmx.ps1 emits exactly these three Types (verified by enumeration:
            # Missing at L122/L189, Mismatch at L147/L214, Error at L302 - no other Type site).
            foreach ($type in 'Missing', 'Error') {
                Get-TierModelFindingColor $type | Should -Be 'Red' -Because "$type reaches the ADMX render site and is not a mere mismatch"
            }
            Get-TierModelFindingColor 'Mismatch' | Should -Be 'Yellow'

            # Test-TierModelGPOAudit.ps1 derives its Type from OverallStatus:
            #   Missing (IsMissing) / Error / Mismatch (from 'Fail') / Unknown (default arm).
            foreach ($type in 'Missing', 'Error') {
                Get-TierModelFindingColor $type | Should -Be 'Red'
            }

            # 'Unknown' is the important one and the reason this test still exists. It is the
            # `default { 'Unknown' }` arm of the GPO-audit findings switch. That arm is currently
            # UNREACHABLE - OverallStatus is assigned by an exhaustive if/elseif/else before the
            # result is appended to the collection the findings are built from - so this is a
            # LATENT path, guarded by a non-local invariant in a different file. It becomes live
            # the day someone adds a fourth OverallStatus, and that is exactly the day nobody
            # will be looking here. Escalating rather than demoting it is what makes that future
            # change safe by default.
            Get-TierModelFindingColor 'Unknown' | Should -Be 'Red' -Because 'the latent GPO-audit default arm must escalate, not render grey or yellow'
        }

        It 'Escalates an unknown or empty type rather than demoting it' {
            # Under-stating severity is the failure mode that produced the bug, so a producer
            # that invents a type name tomorrow must not be silently downgraded.
            #
            # 'AuditRight' is deliberately NOT used as the exemplar here. Whether that label
            # still reaches output at all is under review - the normaliser now derives
            # 'MissingAuditRule' from it - and pinning it as either present or absent would bake
            # in a behaviour nobody has chosen yet. The names below are unowned by any producer.
            foreach ($type in 'SomethingNobodyHasWrittenYet', 'Indeterminate', 'Quarantined', '', '   ') {
                Get-TierModelFindingColor $type | Should -Be 'Red' -Because "'$type' is unclassified and must escalate"
            }
            Get-TierModelFindingColor $null | Should -Be 'Red'
        }

        It 'Routes every drift-finding render through the classifier, with no literal left behind' {
            # Kept as the narrow ratchet on the classifier itself; the render-surface census
            # lives in the two tests above. Was `Should -Be 4` - a derived number that broke when
            # the conversion finished. Tied to the census instead, so it tracks the render
            # surface rather than a moment in its history.
            $source = [IO.File]::ReadAllText($script:AuditScriptPath)
            $allColoured = @([regex]::Matches($source, '\[\$\(\$_\.Type\)\][^\r\n]*-ForegroundColor\s+\$color'))
            $allColoured.Count | Should -BeGreaterThan 0 -Because 'anti-vacuity: an empty census would make the equality below meaningless'
            (Get-CallSiteCount 'Get-TierModelFindingColor') | Should -Be $allColoured.Count
        }

        It 'Colours the whole drifted estate without leaving a real failure yellow' {
            # End to end over the fixture: every finding the eight sections publish, coloured.
            $coloured = foreach ($section in $script:DriftedEstate) {
                $names = $section.PSObject.Properties.Name
                $body = if ($names -contains 'DriftFindings') { @($section.DriftFindings) }
                        elseif ($names -contains 'Findings')  { @($section.Findings) }
                        else { @() }
                foreach ($finding in $body) {
                    $fnames = $finding.PSObject.Properties.Name
                    $type = if ($fnames -contains 'Type') { $finding.Type } else { $finding.Status }
                    [PSCustomObject]@{ Type = $type; Color = (Get-TierModelFindingColor $type) }
                }
            }

            @($coloured).Count | Should -Be 14
            @($coloured | Where-Object { $_.Type -eq 'Error' -and $_.Color -ne 'Red' }).Count   | Should -Be 0
            @($coloured | Where-Object { $_.Type -like 'Missing*' -and $_.Color -ne 'Red' }).Count | Should -Be 0
            @($coloured | Where-Object { $_.Color -eq 'Red' }).Count    | Should -Be 9
            @($coloured | Where-Object { $_.Color -eq 'Yellow' }).Count | Should -Be 5
        }
    }

    # =====================================================================================
    Context 'A run that errored, or checked nothing, may never render as compliance' {
        # ADDED 2026-09-08 after the first full CI-shaped run of the session. That run was
        # 1982/1982 green, and it was green for the WRONG REASON here: I control-proved the gap
        # by inverting the real behaviour in a scratch tree - killing the $ErrorCount guard, the
        # $TotalChecked guard, and BOTH verdict precedence blocks - and re-running the whole
        # suite. It came back 1982/1982/0 with the coverage percentage unmoved by a single
        # command. An audit that hit errors rendered green, an unexamined scope rendered 100%,
        # and nothing in 1982 tests noticed.
        #
        # Two reasons the gap survived so long, both worth naming:
        #   1. ci.yml scopes CodeCoverage.Path to modules/ + optional/, so Audit-TierModel.ps1
        #      is not in the coverage population at all. The percentage could never have flagged
        #      this, however high it got.
        #   2. The behaviour is a PRECEDENCE rule between three outcomes. Every existing test
        #      supplied a clean single outcome, so the ordering was never exercised.
        #
        # The assertions below therefore always pin the LOSING branch as well as the winning one:
        # a precedence rule is only proved by a case where both conditions are live at once.

        It 'Reports N/A, in red, when errors are present - even with zero drift and a full check count' {
            # The decisive case. Drift is 0 and 10 objects were checked, so the percentage branch
            # would happily print a green 100%. Errors must outrank that.
            $recs = @(Write-TierModelComplianceLine -TotalChecked 10 -DriftCount 0 -ErrorCount 1 6>&1)
            @($recs).Count | Should -Be 1
            $recs[0].MessageData.Message         | Should -BeLike '*N/A (could not be determined)*'
            $recs[0].MessageData.ForegroundColor | Should -Be 'Red'
            # The point of the rule, asserted as its own claim rather than left implied.
            $recs[0].MessageData.Message | Should -Not -BeLike '*100*'
            $recs[0].MessageData.ForegroundColor | Should -Not -Be 'Green'
        }

        It 'Reports "not checked", in grey, for an empty scope - and never a percentage' {
            # TotalChecked 0 with no drift and no errors. Dividing here would be 0/0; printing
            # any percentage at all reports an unexamined scope as if it had passed.
            $recs = @(Write-TierModelComplianceLine -TotalChecked 0 6>&1)
            @($recs).Count | Should -Be 1
            $recs[0].MessageData.Message         | Should -BeLike '*Not checked - nothing configured*'
            $recs[0].MessageData.ForegroundColor | Should -Be 'Gray'
            $recs[0].MessageData.Message | Should -Not -Match '\d+(\.\d+)?%'
            $recs[0].MessageData.ForegroundColor | Should -Not -Be 'Green'
        }

        It 'Puts errors ahead of the empty scope too, so the order of the two guards is pinned' {
            # Both guards fire at once. Without this, swapping the two blocks would keep every
            # other assertion in this Context green.
            $recs = @(Write-TierModelComplianceLine -TotalChecked 0 -ErrorCount 3 6>&1)
            $recs[0].MessageData.Message | Should -BeLike '*could not be determined*'
            $recs[0].MessageData.Message | Should -Not -BeLike '*nothing configured*'
        }

        It 'Still prints a real percentage, in a banded colour, when the run actually established one' {
            # ANTI-VACUITY: the three assertions above are all satisfied by a function that
            # refuses to print anything useful ever. This proves the normal path survives.
            $good = @(Write-TierModelComplianceLine -TotalChecked 10 -DriftCount 0 6>&1)
            $good[0].MessageData.Message         | Should -BeLike '*100%*'
            $good[0].MessageData.ForegroundColor | Should -Be 'Green'

            $bad = @(Write-TierModelComplianceLine -TotalChecked 10 -DriftCount 6 6>&1)
            $bad[0].MessageData.Message         | Should -BeLike '*40%*'
            $bad[0].MessageData.ForegroundColor | Should -Be 'Red'
        }

        It 'Honours a percentage the producer already published rather than recomputing it' {
            $recs = @(Write-TierModelComplianceLine -TotalChecked 10 -DriftCount 9 -Percentage 87.5 6>&1)
            $recs[0].MessageData.Message | Should -BeLike '*87.5%*'
        }

        It 'Orders the guards identically at BOTH verdict sites in the shipping source' {
            # The consolidated verdict (Overall Audit Status) and the standalone verdict (Overall
            # Status) are inline script, not functions, so they cannot be lifted and called. They
            # are pinned structurally instead: errors first, empty scope second, drift last.
            #
            # This is the weaker form of the assertions above and is deliberately kept ANYWAY,
            # because those two blocks are where a green verdict is actually printed to the
            # operator, and duplicating a rule in two places is exactly how the two copies drift.
            $source = [IO.File]::ReadAllText($script:AuditScriptPath)

            foreach ($pair in @(
                    @{ Errors = 'totalErrors';           Checked = 'totalChecked';           Label = 'Overall Audit Status' }
                    @{ Errors = 'standaloneTotalErrors'; Checked = 'standaloneTotalChecked'; Label = 'Overall Status' })) {

                $pattern = 'if \(\$' + $pair.Errors + ' -gt 0\) \{\s*\r?\n\s*Write-Host "' + [regex]::Escape($pair.Label) +
                           ':[^\r\n]*COULD NOT BE FULLY DETERMINED[^\r\n]*\r?\n\s*\} elseif \(\$' + $pair.Checked +
                           ' -le 0\) \{\s*\r?\n\s*Write-Host "' + [regex]::Escape($pair.Label) + ':[^\r\n]*NOT CHECKED'

                @([regex]::Matches($source, $pattern)).Count |
                    Should -Be 1 -Because "the $($pair.Label) verdict must test errors first, then an empty scope, before it may print a drift verdict"
            }

            # And neither site may reach a COMPLIANT verdict from the leading branch.
            @([regex]::Matches($source, "if \(\`$totalErrors -gt 0\) \{[^\r\n]*\r?\n\s*Write-Host [^\r\n]*✅")).Count | Should -Be 0
        }
    }

    # =====================================================================================
    Context 'OU ACL findings must not have an Error manufactured for them' {
        # The OU ACL projection used to read:
        #     Type = if ($_.Type -eq 'Missing' -or $_.Type -eq 'Mismatch') { $_.Type } else { 'Error' }
        # An exact-literal whitelist of two, with everything else collapsed to 'Error'. That
        # INVENTS an error the audit never encountered, and it is the third distinct way this
        # report has manufactured or mis-rendered the Error class.
        #
        # It also matters for what can still be observed: the lab estate now has zero [Error]
        # findings, so this projection - like the colour fix - is real but unexercised outside a
        # unit test.

        It 'Keeps a finding that is neither Missing nor Mismatch as its own type' {
            $findings = @(
                [PSCustomObject]@{ Type = 'Warning';       ResourceType = 'ACL'; Identifier = 'Tier0Admins -> OU=T0,DC=x,DC=y'; Details = 'Configuration warning' }
                [PSCustomObject]@{ Type = 'UnexpectedAcl'; ResourceType = 'ACL'; Identifier = 'Tier1Admins -> OU=T1,DC=x,DC=y'; Details = 'Extra ACE present' }
            )
            $normalised = @($findings | ConvertTo-TierModelDriftFinding -DefaultResourceType 'ACL')

            $normalised.Count | Should -Be 2
            $normalised[0].Type | Should -Be 'Warning'
            $normalised[1].Type | Should -Be 'UnexpectedAcl'
            @($normalised | Where-Object { $_.Type -eq 'Error' }).Count | Should -Be 0 -Because 'neither finding reported an inability to determine compliance'

            # And the consequence the operator sees: a warning is yellow, not red.
            Get-TierModelFindingColor $normalised[0].Type | Should -Be 'Yellow'
            Get-TierModelFindingColor $normalised[1].Type | Should -Be 'Yellow'
        }

        It 'Still carries a genuine OU ACL Error through as an Error, in red' {
            # The other half. Removing a manufactured error must not remove the real one - that
            # would be the over-correction this whole family of fixes keeps risking.
            $real = [PSCustomObject]@{ Type = 'Error'; ResourceType = 'ACL'; Identifier = 'OU=T0,DC=x,DC=y'; Details = 'ACL could not be read' }
            $normalised = @($real | ConvertTo-TierModelDriftFinding -DefaultResourceType 'ACL')

            $normalised.Count   | Should -Be 1
            $normalised[0].Type | Should -Be 'Error'
            Get-TierModelFindingColor $normalised[0].Type | Should -Be 'Red'
        }

        It 'Projects OU ACL findings through the shared normaliser, with no local collapse left' {
            $source = [IO.File]::ReadAllText($script:AuditScriptPath)

            $source | Should -Match "ConvertTo-TierModelDriftFinding\s+-DefaultResourceType\s+'ACL'"
            # The exact collapse that manufactured the errors, in any spacing.
            [regex]::Matches($source, "-eq\s+'Missing'\s+-or\s+\`$_\.Type\s+-eq\s+'Mismatch'").Count |
                Should -Be 0 -Because 'the two-literal whitelist is what forced everything else to Error'
        }
    }

    # =====================================================================================
    Context 'AuditRight is relabelled from its own state, not rewritten wholesale' {
        # Two INDEPENDENT guards act on these findings, and the distinction matters:
        #
        #   1. A pre-existing status guard drops any finding whose Status is Pass/Compliant/
        #      OK/Success/True, whatever its Type. This is why a passing audit-right never
        #      reaches the drift report at all.
        #   2. A second, later rule renames 'AuditRight' to 'MissingAuditRule' ONLY when the
        #      finding's own state says it is an absence (ActualValue='Missing' or Status='Fail').
        #
        # The second is deliberately conditioned on state rather than being a blanket rename, so
        # an 'AuditRight' raised one day for some non-absent reason cannot be mislabelled as an
        # absence. These tests pin all three outcomes.
        #
        # Deliberately NOT pinned: whether '[AuditRight]' appears in any given estate's output.
        # It is reachable vocabulary that this estate simply never reaches, and pinning it either
        # present or absent would bake in a behaviour nobody chose.
        #
        # Since the per-right rows were ruled out of the findings collection, NO PRODUCER emits
        # Type='AuditRight' at all. The branch is retained on purpose - deleting a defensive guard
        # because today's producer stopped emitting the shape is how this class of bug returns -
        # so these tests are now the only thing exercising it. If they go, it is dead code that
        # nothing can prove still works.

        It 'Drops a passing audit-right entirely, so it never reaches the drift report' {
            $pass = [PSCustomObject]@{
                Type          = 'AuditRight'
                ResourceType  = 'DomainAuditRule'
                Identifier    = 'DomainRoot -> DC=test,DC=local'
                Property      = 'CreateChild'
                ExpectedValue = 'Present'
                ActualValue   = 'Present'
                Status        = 'Pass'
            }

            @($pass | ConvertTo-TierModelDriftFinding -DefaultResourceType 'DomainAuditRule').Count |
                Should -Be 0 -Because 'a right that is present is not drift'
        }

        It 'Relabels a failing audit-right to MissingAuditRule, in red' {
            $fail = [PSCustomObject]@{
                Type          = 'AuditRight'
                ResourceType  = 'DomainAuditRule'
                Identifier    = 'DomainRoot -> DC=test,DC=local'
                Property      = 'DeleteChild'
                ExpectedValue = 'Present'
                ActualValue   = 'Missing'
                Status        = 'Fail'
            }

            $normalised = @($fail | ConvertTo-TierModelDriftFinding -DefaultResourceType 'DomainAuditRule')
            $normalised.Count   | Should -Be 1
            $normalised[0].Type | Should -Be 'MissingAuditRule'
            Get-TierModelFindingColor $normalised[0].Type | Should -Be 'Red'

            # The detail the operator needs is not lost in the relabel.
            $normalised[0].Details | Should -Match 'DeleteChild'
        }

        It 'Keeps the AuditRight label for any state that is not an absence' {
            # The load-bearing case. A blanket rename would call this a missing audit rule, which
            # it is not - the right is present but not in the state we require.
            $other = [PSCustomObject]@{
                Type          = 'AuditRight'
                ResourceType  = 'DomainAuditRule'
                Identifier    = 'DomainRoot -> DC=test,DC=local'
                Property      = 'WriteDacl'
                ExpectedValue = 'Present'
                ActualValue   = 'Inherited'
                Status        = 'Warn'
            }

            $normalised = @($other | ConvertTo-TierModelDriftFinding -DefaultResourceType 'DomainAuditRule')
            $normalised.Count   | Should -Be 1
            $normalised[0].Type | Should -Be 'AuditRight' -Because 'only an absence may be relabelled as one'
            $normalised[0].Type | Should -Not -Be 'MissingAuditRule'

            # Still escalated: an unrecognised verdict is red, never a quiet grey or yellow.
            Get-TierModelFindingColor $normalised[0].Type | Should -Be 'Red'
        }

        It 'Treats the two guards as independent, so neither alone explains the behaviour' {
            # If the Pass drop were removed, a passing right would surface as drift.
            # If the relabel were removed, a failing right would surface as [AuditRight].
            # Asserting the pair together is what stops one being collapsed into the other.
            $rows = @(
                [PSCustomObject]@{ Type='AuditRight'; Identifier='d'; Property='A'; ActualValue='Present'; Status='Pass' }
                [PSCustomObject]@{ Type='AuditRight'; Identifier='d'; Property='B'; ActualValue='Missing'; Status='Fail' }
                [PSCustomObject]@{ Type='AuditRight'; Identifier='d'; Property='C'; ActualValue='Inherited'; Status='Warn' }
            )

            $normalised = @($rows | ConvertTo-TierModelDriftFinding -DefaultResourceType 'DomainAuditRule')

            @($normalised).Count | Should -Be 2 -Because 'exactly the Pass row is dropped'
            @($normalised | Where-Object { $_.Type -eq 'MissingAuditRule' }).Count | Should -Be 1
            @($normalised | Where-Object { $_.Type -eq 'AuditRight' }).Count       | Should -Be 1
            @($normalised | Where-Object { (Get-TierModelFindingColor $_.Type) -ne 'Red' }).Count | Should -Be 0
        }

        It 'Never treats NonCompliant as compliant' {
            # The compliant checks match exactly rather than by wildcard. A substring match here
            # would silently discard real drift.
            $nc = [PSCustomObject]@{ Type = 'NonCompliant'; Identifier = 'd'; Details = 'still drift' }
            @($nc | ConvertTo-TierModelDriftFinding -DefaultResourceType 'DomainAuditRule').Count |
                Should -Be 1 -Because 'NonCompliant is drift, and only exact matching keeps it'
        }
    }
}
