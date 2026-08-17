function Test-TierModelAuditRule {
    <#
    .SYNOPSIS
    Audit the domain-root SACL audit rule against configuration (drift detection).

    .DESCRIPTION
    Reads the current SACL on the domain root DN and compares it against the configured
    canonical audit ACE (Everyone/Success/All/9-rights). Reports Compliant or Drift.

    Managed scope: ACEs with SID=S-1-1-0, AuditFlags=Success, InheritanceType=All,
    non-inherited. All other ACEs are ignored (no false positives for Failure-flag ACEs,
    other SIDs, or inherited ACEs).

    Requires SeSecurityPrivilege to read the SACL.

    .PARAMETER Config
    TierModel configuration object. Must contain a domainAuditRule segment.

    .PARAMETER DomainController
    The domain controller to use for Active Directory operations.

    .PARAMETER Silent
    Suppress all host output (for consolidated reporting).

    .PARAMETER SuppressSummary
    Suppress the summary section while still showing per-item status.

    .OUTPUTS
    PSCustomObject with TotalChecked, Compliant, Missing, Mismatched, Errors, Drift, Findings.

    .EXAMPLE
    $config = Get-TierModelConfig
    $audit = Test-TierModelAuditRule -Config $config -DomainController 'DC01'

    .EXAMPLE
    Test-TierModelAuditRule -Config $config -DomainController 'DC01' -Silent
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter(Mandatory)]
        [string]$DomainController,

        [switch]$Silent,

        [switch]$SuppressSummary
    )

    $CorrelationId = [System.Guid]::NewGuid().ToString()
    $startTime = Get-Date

    Write-TierModelLog -Level Info -Message "AuditRuleAuditStart" -Data @{
        DomainController = $DomainController
        Silent           = $Silent.IsPresent
        CorrelationId    = $CorrelationId
    } | Out-Null

    $emptyResult = {
        [PSCustomObject]@{
            TotalChecked  = 0
            Compliant     = 0
            Missing       = 0
            Mismatched    = 0
            Errors        = 0
            Drift         = 0
            Findings      = @()
            DurationMs    = ((Get-Date) - $startTime).TotalMilliseconds
            CorrelationId = $CorrelationId
        }
    }

    try {
        if (-not ($Config.PSObject.Properties.Name -contains 'domainAuditRule') -or
            -not $Config.domainAuditRule) {
            Write-TierModelLog -Level Warning -Message "No domainAuditRule found in configuration" -Data @{
                CorrelationId = $CorrelationId
            } | Out-Null
            return & $emptyResult
        }

        $ruleConfig = $Config.domainAuditRule
        $domainDN   = Resolve-TierModelDomainDN -DomainController $DomainController
        $targetDn   = $ruleConfig.targetDn -replace [regex]::Escape('{{DOMAIN_DN}}'), $domainDN
        $canonicalSid = 'S-1-1-0'

        # Build canonical target rights bitmask
        $targetRightsInt = 0
        foreach ($right in $ruleConfig.rights) {
            $targetRightsInt = $targetRightsInt -bor [int][System.DirectoryServices.ActiveDirectoryRights]$right
        }

        $totalChecked  = 1
        $compliantCount = 0
        $missingCount   = 0
        $errorCount     = 0
        $findings       = @()

        if (-not $Silent) {
            Write-Host "Auditing domain-root SACL audit rule..." -ForegroundColor Cyan
            Write-Host "Checking: $targetDn" -ForegroundColor Cyan
        }

        # Ensure AD provider is available
        Import-Module ActiveDirectory -ErrorAction SilentlyContinue

        # Read the SACL
        $acl = $null
        try {
            $acl = Get-Acl -Path "AD:$targetDn" -Audit -ErrorAction Stop
        } catch {
            $errorCount++
            $errMsg = if ($_.Exception.Message -match 'Privilege') {
                "Cannot read the domain-root SACL. SeSecurityPrivilege is required. Run as Domain Admin. Detail: $($_.Exception.Message)"
            } else {
                "Failed to read SACL on '$targetDn': $($_.Exception.Message)"
            }
            if (-not $Silent) {
                Write-Host "  ❌ $errMsg" -ForegroundColor Red
            }
            $findings += [PSCustomObject]@{
                Type          = 'Error'
                ResourceType  = 'DomainAuditRule'
                Identifier    = "DomainRoot → $targetDn"
                Property      = 'SaclRead'
                ExpectedValue = 'SACL readable'
                ActualValue   = 'Failed'
                Details       = $errMsg
            }
            return [PSCustomObject]@{
                TotalChecked  = $totalChecked
                Compliant     = 0
                Missing       = 0
                Mismatched    = 0
                Errors        = $errorCount
                Drift         = 0
                Findings      = $findings
                DurationMs    = ((Get-Date) - $startTime).TotalMilliseconds
                CorrelationId = $CorrelationId
            }
        }

        # Enumerate managed ACEs
        $managedAces = [System.Collections.Generic.List[object]]::new()
        foreach ($rule in $acl.GetAuditRules($true, $false, [System.Security.Principal.SecurityIdentifier])) {
            if ($rule.IdentityReference.Value -eq $canonicalSid -and
                $rule.AuditFlags -eq [System.Security.AccessControl.AuditFlags]::Success -and
                $rule.InheritanceType -eq [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All -and
                -not $rule.IsInherited) {
                $managedAces.Add($rule)
            }
        }

        $presentInt = 0
        foreach ($ace in $managedAces) {
            $presentInt = $presentInt -bor [int]$ace.ActiveDirectoryRights
        }
        $missingInt = $targetRightsInt -band (-bnot $presentInt)

        $isCompliant = ($managedAces.Count -eq 1) -and ($missingInt -eq 0)

        # Per-right granular output — model: Test-TierModelGPOContent URA validation
        # Always compute; emit to host only when not -Silent
        foreach ($right in $ruleConfig.rights) {
            $rightBit     = [int][System.DirectoryServices.ActiveDirectoryRights]$right
            $rightPresent = ($rightBit -band $presentInt) -ne 0

            if (-not $Silent) {
                if ($rightPresent) {
                    Write-Host "        ✅ Right '$right' - present" -ForegroundColor Green
                } else {
                    Write-Host "        ❌ Right '$right' - missing" -ForegroundColor Red
                }
            }

            $findings += [PSCustomObject]@{
                Type          = 'AuditRight'
                ResourceType  = 'DomainAuditRule'
                Identifier    = "DomainRoot → $targetDn"
                Property      = $right
                ExpectedValue = 'Present'
                ActualValue   = if ($rightPresent) { 'Present' } else { 'Missing' }
                Status        = if ($rightPresent) { 'Pass' } else { 'Fail' }
            }
        }

        if ($isCompliant) {
            if (-not $Silent) {
                Write-Host "  ✅ Domain-root audit rule COMPLIANT" -ForegroundColor Green
            }
            $findings += [PSCustomObject]@{
                Type          = 'Compliant'
                ResourceType  = 'DomainAuditRule'
                Identifier    = "DomainRoot → $targetDn"
                Property      = 'AuditRule'
                ExpectedValue = 'Canonical 9-right ACE present (Everyone/Success/All)'
                ActualValue   = 'Matched'
                Details       = 'Domain-root SACL audit rule matches canonical configuration.'
            }
            $compliantCount++
        } else {
            $status = if ($managedAces.Count -eq 0) { 'ABSENT' } elseif ($missingInt -ne 0) { 'PARTIAL' } else { 'MULTI-ACE' }
            $missingRightsStr = if ($missingInt -ne 0) { ([System.DirectoryServices.ActiveDirectoryRights]$missingInt).ToString() } else { 'None' }
            $detail = "Status: $status. ManagedAceCount: $($managedAces.Count). Missing rights: $missingRightsStr."

            if (-not $Silent) {
                Write-Host "  ❌ Domain-root audit rule DRIFT detected ($status)" -ForegroundColor Red
            }
            $findings += [PSCustomObject]@{
                Type          = 'MissingAuditRule'
                ResourceType  = 'DomainAuditRule'
                Identifier    = "DomainRoot → $targetDn"
                Property      = 'AuditRule'
                ExpectedValue = 'Canonical 9-right ACE present (Everyone/Success/All)'
                ActualValue   = $status
                Details       = $detail
            }
            $missingCount++
        }

        $durationMs = ((Get-Date) - $startTime).TotalMilliseconds

        if (-not $Silent -and -not $SuppressSummary) {
            Write-Host "`n=== Domain Audit Rule Audit Summary ===" -ForegroundColor Blue
            Write-Host "Total Checked: $totalChecked" -ForegroundColor White
            Write-Host "Compliant: $compliantCount" -ForegroundColor Green
            Write-Host "Missing/Drift: $missingCount" -ForegroundColor Red
            Write-Host "Errors: $errorCount" -ForegroundColor Red
        }

        Write-TierModelLog -Level Info -Message "AuditRuleAuditComplete" -Data @{
            TotalChecked  = $totalChecked
            Compliant     = $compliantCount
            Missing       = $missingCount
            Errors        = $errorCount
            DurationMs    = $durationMs
            CorrelationId = $CorrelationId
        } | Out-Null

        return [PSCustomObject]@{
            TotalChecked  = $totalChecked
            Compliant     = $compliantCount
            Missing       = $missingCount
            Mismatched    = 0
            Errors        = $errorCount
            Drift         = $missingCount
            Findings      = $findings
            DurationMs    = $durationMs
            CorrelationId = $CorrelationId
        }

    } catch {
        Write-TierModelLog -Level Error -Message "Audit rule drift check failed" -Data @{
            Exception = $_.Exception.Message; CorrelationId = $CorrelationId
        } | Out-Null

        return [PSCustomObject]@{
            TotalChecked  = 0
            Compliant     = 0
            Missing       = 0
            Mismatched    = 0
            Errors        = 1
            Drift         = 0
            Findings      = @([PSCustomObject]@{
                Type          = 'Error'
                ResourceType  = 'DomainAuditRule'
                Identifier    = 'Domain Audit Rule Audit'
                Property      = 'Execution'
                ExpectedValue = 'Audit should complete successfully'
                ActualValue   = 'Failed'
                Details       = $_.Exception.Message
            })
            DurationMs    = ((Get-Date) - $startTime).TotalMilliseconds
            CorrelationId = $CorrelationId
        }
    }
}
