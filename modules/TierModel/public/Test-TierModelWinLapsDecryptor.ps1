function Test-TierModelWinLapsDecryptor {
    <#
    .SYNOPSIS
    Audit Windows LAPS ADPasswordEncryptionPrincipal GPO settings against configuration.

    .DESCRIPTION
    Performs drift detection for the Windows LAPS decryptor (ADPasswordEncryptionPrincipal)
    GPO registry policy on each configured non-DC LAPS GPO. For each winLapsDelegations
    entry that has both decryptorGroup and decryptorGpoName, resolves the GPO by display
    name pattern (using Get-GPO -All | Where-Object DisplayName -like), reads the current
    ADPasswordEncryptionPrincipal value via Get-GPRegistryValue, computes the expected
    "NETBIOS\sAMAccountName" value from the config group, and compares them
    case-insensitively. Reports each result as Compliant, Missing, or Mismatched.
    DC OUs (isDomainControllerOu:true) and entries without decryptor fields are skipped.
    Read-only — never modifies GPO settings or rotates passwords.

    .PARAMETER Config
    TierModel configuration object containing winLapsDelegations definitions.

    .PARAMETER DomainController
    The domain controller to use for Active Directory operations.

    .PARAMETER Silent
    Suppress all host output (for consolidated reporting).

    .PARAMETER SuppressSummary
    Suppress the summary section while still showing per-GPO status.

    .OUTPUTS
    PSCustomObject with TotalChecked, Compliant, Missing, Mismatched, Errors, Drift,
    Findings (array of {GpoName,Expected,Actual,Status}), DurationMs, CorrelationId.
    Drift = Missing + Mismatched + Errors.

    .EXAMPLE
    $config = Get-TierModelConfig
    $result = Test-TierModelWinLapsDecryptor -Config $config -DomainController 'DC01'
    $result.Findings | Where-Object { $_.Status -ne 'Compliant' }

    .EXAMPLE
    Test-TierModelWinLapsDecryptor -Config $config -DomainController 'DC01' -Silent
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

    Write-TierModelLog -Level Info -Message "WinLapsDecryptorAuditStart" -Data @{
        DomainController = $DomainController
        Silent           = $Silent.IsPresent
        CorrelationId    = $CorrelationId
    } | Out-Null

    try {
        $totalChecked = 0
        $compliantCount = 0
        $missingCount = 0
        $mismatchCount = 0
        $errorCount = 0
        $findings = @()

        if (-not ($Config.PSObject.Properties.Name -contains 'winLapsDelegations') -or -not $Config.winLapsDelegations) {
            Write-TierModelLog -Level Warning -Message "No Windows LAPS delegations found in configuration" -Data @{
                CorrelationId = $CorrelationId
            } | Out-Null

            return [PSCustomObject]@{
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

        # Resolve NetBIOS domain name once for all expected value calculations
        $netBIOSDomain = $null
        try {
            $adDomain = Get-ADDomain -Server $DomainController -ErrorAction Stop
            $netBIOSDomain = $adDomain.NetBIOSName
        } catch {
            Write-TierModelLog -Level Error -Message "Cannot resolve NetBIOS domain name — decryptor audit cannot proceed" -Data @{
                Exception     = $_.Exception.Message
                CorrelationId = $CorrelationId
            } | Out-Null

            return [PSCustomObject]@{
                TotalChecked  = 0
                Compliant     = 0
                Missing       = 0
                Mismatched    = 0
                Errors        = 1
                Drift         = 1
                Findings      = @([PSCustomObject]@{
                    GpoName  = 'N/A'
                    Expected = 'NETBIOS\sAMAccountName'
                    Actual   = "Domain resolution failed: $($_.Exception.Message)"
                    Status   = 'Error'
                })
                DurationMs    = ((Get-Date) - $startTime).TotalMilliseconds
                CorrelationId = $CorrelationId
            }
        }

        if (-not $Silent) {
            Write-Host "Auditing Windows LAPS decryptor (ADPasswordEncryptionPrincipal) settings..." -ForegroundColor Cyan
        }

        foreach ($entry in @($Config.winLapsDelegations)) {
            # Skip DC OUs — DSRM always uses Domain Admins; no decryptor GPO
            if ($entry.PSObject.Properties.Name -contains 'isDomainControllerOu' -and $entry.isDomainControllerOu -eq $true) {
                continue
            }

            # Skip entries without decryptor fields
            $hasDecryptorGroup  = $entry.PSObject.Properties.Name -contains 'decryptorGroup' -and
                                   -not [string]::IsNullOrWhiteSpace($entry.decryptorGroup)
            $hasDecryptorGpoName = $entry.PSObject.Properties.Name -contains 'decryptorGpoName' -and
                                   -not [string]::IsNullOrWhiteSpace($entry.decryptorGpoName)
            if (-not $hasDecryptorGroup -or -not $hasDecryptorGpoName) {
                continue
            }

            $totalChecked++
            $gpoPattern       = $entry.decryptorGpoName
            $decryptorGroupName = $entry.decryptorGroup

            if (-not $Silent) {
                Write-Host "Checking decryptor for GPO pattern '$gpoPattern' (group: $decryptorGroupName)" -ForegroundColor Cyan
            }

            # Step 1: Resolve GPO by display name pattern — must match exactly one GPO
            $matchedGpo = $null
            try {
                $matchedGpos = @(Get-GPO -All -ErrorAction Stop | Where-Object { $_.DisplayName -like $gpoPattern })
                if ($matchedGpos.Count -eq 0) {
                    if (-not $Silent) {
                        Write-Host "    `u{274C} No GPO found matching pattern '$gpoPattern'" -ForegroundColor Red
                    }
                    $findings += [PSCustomObject]@{
                        GpoName  = $gpoPattern
                        Expected = 'GPO must exist'
                        Actual   = 'No matching GPO'
                        Status   = 'Error'
                    }
                    $errorCount++
                    continue
                } elseif ($matchedGpos.Count -gt 1) {
                    $nameList = ($matchedGpos | Select-Object -ExpandProperty DisplayName) -join ', '
                    if (-not $Silent) {
                        Write-Host "    `u{274C} Multiple GPOs match pattern '$gpoPattern': $nameList" -ForegroundColor Red
                    }
                    $findings += [PSCustomObject]@{
                        GpoName  = $gpoPattern
                        Expected = 'Exactly one GPO must match'
                        Actual   = "Ambiguous matches: $nameList"
                        Status   = 'Error'
                    }
                    $errorCount++
                    continue
                }
                $matchedGpo = $matchedGpos[0]
            } catch {
                if (-not $Silent) {
                    Write-Host "    `u{274C} Error enumerating GPOs: $($_.Exception.Message)" -ForegroundColor Red
                }
                $findings += [PSCustomObject]@{
                    GpoName  = $gpoPattern
                    Expected = 'GPO query must succeed'
                    Actual   = $_.Exception.Message
                    Status   = 'Error'
                }
                $errorCount++
                continue
            }

            $gpoDisplayName = $matchedGpo.DisplayName

            # Step 2: Compute expected value from config group — NETBIOS\sAMAccountName
            $expectedValue = $null
            try {
                $escapedName = $decryptorGroupName -replace "'", "''"
                $adGroup = Get-ADGroup -Filter "Name -eq '$escapedName'" -Server $DomainController `
                               -Properties sAMAccountName -ErrorAction Stop
                if (-not $adGroup) {
                    throw "Group '$decryptorGroupName' not found in Active Directory."
                }
                $expectedValue = "$netBIOSDomain\$($adGroup.sAMAccountName)"
            } catch {
                if (-not $Silent) {
                    Write-Host "    `u{274C} Cannot resolve group '$decryptorGroupName': $($_.Exception.Message)" -ForegroundColor Red
                }
                $findings += [PSCustomObject]@{
                    GpoName  = $gpoDisplayName
                    Expected = "$netBIOSDomain\<sAMAccountName of $decryptorGroupName>"
                    Actual   = "Group resolution failed: $($_.Exception.Message)"
                    Status   = 'Error'
                }
                $errorCount++
                continue
            }

            # Step 3: Read current ADPasswordEncryptionPrincipal value from the GPO registry policy
            $currentValue    = $null
            $isValueMissing  = $false
            try {
                $regEntry = Get-GPRegistryValue `
                    -Name        $gpoDisplayName `
                    -Key         'HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\LAPS' `
                    -ValueName   'ADPasswordEncryptionPrincipal' `
                    -ErrorAction Stop
                $currentValue = $regEntry.Value
            } catch {
                # Value not set or registry key absent — treat as Missing
                $isValueMissing = $true
            }

            # Step 4: Compare case-insensitively
            if ($isValueMissing -or [string]::IsNullOrWhiteSpace($currentValue)) {
                if (-not $Silent) {
                    Write-Host "    `u{274C} ADPasswordEncryptionPrincipal NOT SET on '$gpoDisplayName' (expected: $expectedValue)" -ForegroundColor Red
                }
                $findings += [PSCustomObject]@{
                    GpoName  = $gpoDisplayName
                    Expected = $expectedValue
                    Actual   = '(not set)'
                    Status   = 'Missing'
                }
                $missingCount++
            } elseif ($currentValue.Trim() -ieq $expectedValue) {
                if (-not $Silent) {
                    Write-Host "    `u{2705} ADPasswordEncryptionPrincipal COMPLIANT on '$gpoDisplayName' ($currentValue)" -ForegroundColor Green
                }
                $findings += [PSCustomObject]@{
                    GpoName  = $gpoDisplayName
                    Expected = $expectedValue
                    Actual   = $currentValue
                    Status   = 'Compliant'
                }
                $compliantCount++
            } else {
                if (-not $Silent) {
                    Write-Host "    `u{274C} ADPasswordEncryptionPrincipal MISMATCHED on '$gpoDisplayName'" -ForegroundColor Yellow
                    Write-Host "      Expected: $expectedValue" -ForegroundColor Yellow
                    Write-Host "      Actual:   $currentValue" -ForegroundColor Yellow
                }
                $findings += [PSCustomObject]@{
                    GpoName  = $gpoDisplayName
                    Expected = $expectedValue
                    Actual   = $currentValue
                    Status   = 'Mismatched'
                }
                $mismatchCount++
            }
        }

        $durationMs = ((Get-Date) - $startTime).TotalMilliseconds
        $drift = $missingCount + $mismatchCount + $errorCount

        if (-not $Silent -and -not $SuppressSummary) {
            Write-Host "`n=== Windows LAPS Decryptor Audit Summary ===" -ForegroundColor Blue
            Write-Host "Total Checked: $totalChecked" -ForegroundColor White
            Write-Host "Compliant:     $compliantCount" -ForegroundColor Green
            Write-Host "Missing:       $missingCount" -ForegroundColor Red
            Write-Host "Mismatched:    $mismatchCount" -ForegroundColor Yellow
            Write-Host "Errors:        $errorCount" -ForegroundColor Red
        }

        Write-TierModelLog -Level Info -Message "WinLapsDecryptorAuditComplete" -Data @{
            TotalChecked  = $totalChecked
            Compliant     = $compliantCount
            Missing       = $missingCount
            Mismatched    = $mismatchCount
            Errors        = $errorCount
            Drift         = $drift
            DurationMs    = $durationMs
            CorrelationId = $CorrelationId
        } | Out-Null

        return [PSCustomObject]@{
            TotalChecked  = $totalChecked
            Compliant     = $compliantCount
            Missing       = $missingCount
            Mismatched    = $mismatchCount
            Errors        = $errorCount
            Drift         = $drift
            Findings      = $findings
            DurationMs    = $durationMs
            CorrelationId = $CorrelationId
        }
    } catch {
        Write-TierModelLog -Level Error -Message "Windows LAPS Decryptor audit failed" -Data @{
            Exception     = $_.Exception.Message
            CorrelationId = $CorrelationId
        } | Out-Null

        return [PSCustomObject]@{
            TotalChecked  = 0
            Compliant     = 0
            Missing       = 0
            Mismatched    = 0
            Errors        = 1
            Drift         = 1
            Findings      = @([PSCustomObject]@{
                GpoName  = 'Windows LAPS Decryptor Audit'
                Expected = 'Audit should complete successfully'
                Actual   = $_.Exception.Message
                Status   = 'Error'
            })
            DurationMs    = ((Get-Date) - $startTime).TotalMilliseconds
            CorrelationId = $CorrelationId
        }
    }
}
