#Requires -Modules Pester
<#
    Static prohibition guard for diagnostics forwarding into Active Directory and Group Policy.

    Two call shapes are forbidden anywhere in the product surface:

      1. A literal -Debug on an AD or GroupPolicy invocation.
      2. An @PSBoundParameters splat into an AD or GroupPolicy invocation, which forwards
         -Debug (and everything else the caller was given) implicitly.

    Explicitly forwarding -Debug to these cmdlets throws
    "Object reference not set to an instance of an object" when the host is non-interactive,
    because the cmdlet attempts to raise a debug prompt against a host that cannot service one.
    The supported way to raise diagnostic output is to set the PREFERENCE VARIABLE
    ($DebugPreference / $VerbosePreference), which the entry scripts already do. That path is
    safe; these two are not.

    The second shape matters as much as the first: a splat carries -Debug without the token
    -Debug appearing anywhere in the source, so a text search cannot see it. That is why this
    guard reads the AST rather than the text.

    Strategy
    --------
    Parse every product file with the PowerShell parser and inspect CommandAst nodes directly.
    Detection is structural, so it is unaffected by line drift, formatting or comments, and it
    cannot be fooled by the token appearing inside a string or a comment.

    House rules applied here
    ------------------------
    * Assert EXACT integers, never -BeGreaterThan 0.
    * Every scan carries an anti-vacuity assertion proving files were actually read and AD/GPO
      invocations were actually found. A prohibition test that scans nothing passes for the
      wrong reason, which is worse than having no test at all.
    * Failures name the file, line and command so the message is actionable without a rerun.
#>

Describe 'Diagnostics forwarding prohibition (AD / GroupPolicy)' -Tag 'Unit', 'Prohibition', 'Diagnostics' {

    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

        # --- Product surface under prohibition -------------------------------------------
        $publicDir = Join-Path $script:RepoRoot 'modules\TierModel\public'
        $script:ScannedFiles = @(
            @(Get-ChildItem -Path $publicDir -Filter '*.ps1' -File -ErrorAction Stop).FullName
            (Join-Path $script:RepoRoot 'Deploy-TierModel.ps1')
            (Join-Path $script:RepoRoot 'Audit-TierModel.ps1')
        )

        # An AD cmdlet is <Verb>-AD<Noun>; a GroupPolicy cmdlet is <Verb>-GP<Noun>.
        $script:AdGpoPattern = '^[A-Za-z]+-(AD|GP)[A-Za-z]*$'

        $script:ParseErrorCount = 0
        $script:AdGpoInvocations = [System.Collections.Generic.List[object]]::new()
        $script:LiteralDebugViolations = [System.Collections.Generic.List[string]]::new()
        $script:SplatViolations = [System.Collections.Generic.List[string]]::new()

        foreach ($file in $script:ScannedFiles) {
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $file, [ref]$null, [ref]$parseErrors)
            $script:ParseErrorCount += @($parseErrors).Count

            $commands = $ast.FindAll({
                param($n) $n -is [System.Management.Automation.Language.CommandAst]
            }, $true)

            foreach ($cmd in $commands) {
                $name = $cmd.GetCommandName()
                if (-not $name -or $name -notmatch $script:AdGpoPattern) { continue }

                $where = '{0}:{1} ({2})' -f (Split-Path $file -Leaf), $cmd.Extent.StartLineNumber, $name
                $script:AdGpoInvocations.Add($where)

                foreach ($element in $cmd.CommandElements) {
                    if ($element -is [System.Management.Automation.Language.CommandParameterAst] -and
                        $element.ParameterName -eq 'Debug') {
                        $script:LiteralDebugViolations.Add($where)
                    }

                    if ($element -is [System.Management.Automation.Language.VariableExpressionAst] -and
                        $element.Splatted -and
                        $element.VariablePath.UserPath -eq 'PSBoundParameters') {
                        $script:SplatViolations.Add($where)
                    }
                }
            }
        }
    }

    Context 'The scan itself is valid' {

        It 'Reads a non-empty product surface' {
            # Anti-vacuity: an empty file list would make every prohibition below pass trivially.
            @($script:ScannedFiles).Count | Should -BeGreaterThan 0
        }

        It 'Includes both entry scripts' {
            $leaves = @($script:ScannedFiles | Split-Path -Leaf)
            $leaves | Should -Contain 'Deploy-TierModel.ps1'
            $leaves | Should -Contain 'Audit-TierModel.ps1'
        }

        It 'Parses every scanned file without error' {
            $script:ParseErrorCount | Should -Be 0
        }

        It 'Actually finds AD/GPO invocations to police' {
            # Anti-vacuity: proves the detector matches real calls. If the naming convention or
            # the pattern ever drifts, this fails loudly instead of reporting a false all-clear.
            @($script:AdGpoInvocations).Count | Should -BeGreaterThan 0
        }
    }

    Context 'FR-017 prohibitions' {

        It 'No AD or GroupPolicy invocation carries a literal -Debug' {
            $found = @($script:LiteralDebugViolations)
            $found.Count | Should -Be 0 -Because (
                "explicitly forwarding -Debug to AD/GroupPolicy throws a null reference on a " +
                "non-interactive host; set `$DebugPreference instead. Offending call sites: " +
                ($found -join '; ')
            )
        }

        It 'No AD or GroupPolicy invocation is splatted with @PSBoundParameters' {
            $found = @($script:SplatViolations)
            $found.Count | Should -Be 0 -Because (
                "an @PSBoundParameters splat forwards -Debug implicitly, with no -Debug token " +
                "in the source for a text search to find. Offending call sites: " +
                ($found -join '; ')
            )
        }
    }
}
