function Test-TierModelGPOContent {
    <#
    .SYNOPSIS
    Test TierModel GPO security template content against expected configuration.
    
    .DESCRIPTION
    Validates GPO GptTmpl.inf content by generating a mock file from configuration
    and comparing User Rights Assignments and Restricted Groups against the actual
    GPO content. Uses exact logic from original audit script.
    
    .PARAMETER GPOName
    Name of the GPO to test content for.
    
    .PARAMETER GPOConfig
    GPO configuration object containing expected userRightsAssignments and restrictedGroups.
    
    .PARAMETER DomainController
    The domain controller to use for Active Directory operations.
    
    .PARAMETER KeepMockFiles
    Whether to keep mock files for debugging when validation fails (default: true).
    
    .EXAMPLE
    Test-TierModelGPOContent -GPOName "Tier0-Security" -GPOConfig $gpoConfig -DomainController "DC01"
    
    .OUTPUTS
    PSCustomObject with content validation results including URA and RG validation details.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GPOName,
        
        [Parameter(Mandatory)]
        [object]$GPOConfig,
        
        [switch]$Silent,
        
        [Parameter(Mandatory)]
        [string]$DomainController,
        
        [bool]$KeepMockFiles = $true
    )
    
    $CorrelationId = [System.Guid]::NewGuid().ToString()
    $startTime = Get-Date
    
    Write-TierModelLog -Level Info -Message "GPO content validation start" -Data @{
        GPOName = $GPOName
        DomainController = $DomainController
        CorrelationId = $CorrelationId
    } | Out-Null
    
    try {
        $testResult = [PSCustomObject]@{
            GPOName = $GPOName
            MockFilePath = $null
            ActualFilePath = $null
            ValidationResults = @()
            Status = 'Unknown'
            Issues = @()
            Recommendations = @()
        }
        
        # Get GPO object
        try {
            $gpo = Get-GPO -Name $GPOName -Server $DomainController -ErrorAction Stop
        } catch {
            $testResult.Status = 'Error'
            $testResult.Issues += "GPO '$GPOName' not found"
            $testResult.Recommendations += "Create GPO using New-TierModelGpo"
            return $testResult
        }
        
        # Ensure temp directory exists for mock file generation
        $basePath = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent  # Up to TierModel parent folder
        $tempDir = Join-Path $basePath 'Temp'
        if (-not (Test-Path $tempDir)) {
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
            Write-Host "    Created temp directory: $tempDir" -ForegroundColor Gray
        }
        
        # Generate mock GptTmpl.inf content using the same function as deployment
        try {
            $mockContent = New-TierModelGptTmplContent -GPOData $GPOConfig -DomainController $DomainController
            $mockFilePath = Join-Path $tempDir "$($GPOName.Replace('*', 'STAR').Replace(':', '_'))_Mock.inf"
            $mockContent | Out-File -FilePath $mockFilePath -Encoding unicode -Force
            $testResult.MockFilePath = $mockFilePath
            
            # Get actual GPO GptTmpl.inf path
            $domain = Get-ADDomain -Server $DomainController
            $domainName = $domain.DNSRoot
            $sysvol = "\\$DomainController\SYSVOL"
            $actualGptTmplPath = "$sysvol\$domainName\Policies\{$($gpo.Id)}\Machine\Microsoft\Windows NT\SecEdit\GptTmpl.inf"
            $testResult.ActualFilePath = $actualGptTmplPath
            
            if (Test-Path $actualGptTmplPath) {
                $actualContent = Get-Content $actualGptTmplPath -Raw
                
                # Parse mock content for expected URA and RG entries
                $mockLines = $mockContent -split "`n"
                $actualLines = $actualContent -split "`n"
                
                $uraSection = $false
                $rgSection = $false
                $uraValidationFailed = $false
                $rgValidationFailed = $false
                
                foreach ($mockLine in $mockLines) {
                    $mockLine = $mockLine.Trim()
                    if ([string]::IsNullOrEmpty($mockLine)) { continue }
                    
                    if ($mockLine -eq '[Privilege Rights]') {
                        $uraSection = $true
                        $rgSection = $false
                        continue
                    } elseif ($mockLine -eq '[Group Membership]') {
                        $uraSection = $false
                        $rgSection = $true
                        continue
                    } elseif ($mockLine -match '^\[.*\]$') {
                        $uraSection = $false
                        $rgSection = $false
                        continue
                    }
                    
                    # Validate URA entries
                    if ($uraSection -and $mockLine -match '^(\w+)\s*=\s*(.*)$') {
                        $uraName = $matches[1]
                        $expectedSids = $matches[2] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
                        
                        # Find corresponding line in actual GPO
                        $actualUraLine = $actualLines | Where-Object { $_.Trim() -match "^$uraName\s*=\s*(.*)$" } | Select-Object -First 1
                        if ($actualUraLine) {
                            $actualSids = $actualUraLine.Trim() -replace "^$uraName\s*=\s*", '' -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
                            
                            # Check if all expected SIDs are present (allow additional SIDs)
                            $missingSids = @()
                            foreach ($expectedSid in $expectedSids) {
                                if ($expectedSid -notin $actualSids) {
                                    $missingSids += $expectedSid
                                }
                            }
                            
                            if ($missingSids.Count -eq 0) {
                                # Individual URA success messages removed for cleaner output
                                $testResult.ValidationResults += [PSCustomObject]@{
                                    Type = 'URA'
                                    Name = $uraName
                                    Status = 'Pass'
                                    Expected = $expectedSids -join ', '
                                    Actual = $actualSids -join ', '
                                    Message = 'All required SIDs present'
                                }
                            } else {
                                Write-Host "        ❌ URA '$uraName' - missing SIDs: $($missingSids -join ', ')" -ForegroundColor Red
                                $testResult.ValidationResults += [PSCustomObject]@{
                                    Type = 'URA'
                                    Name = $uraName
                                    Status = 'Fail'
                                    Expected = $expectedSids -join ', '
                                    Actual = "Missing: $($missingSids -join ', ')"
                                    Message = "Missing required SIDs: $($missingSids -join ', ')"
                                }
                                $testResult.Issues += "URA '$uraName' in GPO '$GPOName' is missing required SIDs: $($missingSids -join ', ')"
                                $testResult.Recommendations += "Update GPO security settings for User Rights Assignment '$uraName'"
                                $uraValidationFailed = $true
                            }
                        } else {
                            Write-Host "        ❌ URA '$uraName' - not found in actual GPO" -ForegroundColor Red
                            $testResult.ValidationResults += [PSCustomObject]@{
                                Type = 'URA'
                                Name = $uraName
                                Status = 'Fail'
                                Expected = $expectedSids -join ', '
                                Actual = 'Not Found'
                                Message = 'URA not found in GPO'
                            }
                            $testResult.Issues += "URA '$uraName' is missing from GPO '$GPOName'"
                            $testResult.Recommendations += "Add User Rights Assignment '$uraName' to GPO security settings"
                            $uraValidationFailed = $true
                        }
                    }
                    
                    # Validate RG entries
                    if ($rgSection -and $mockLine -match '^([^=]+)=(.*)$') {
                        $rgName = $matches[1].Trim()
                        $expectedMembers = if ($matches[2]) { $matches[2] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } } else { @() }
                        
                        # Find corresponding line in actual GPO
                        $escapedRgName = [regex]::Escape($rgName)
                        $actualRgLine = $actualLines | Where-Object { $_.Trim() -match "^$escapedRgName\s*=\s*(.*)$" } | Select-Object -First 1
                        if ($actualRgLine) {
                            $actualMembers = if ($actualRgLine -match '=(.*)$' -and $matches[1]) { $matches[1] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } } else { @() }
                            
                            # Check if all expected members are present (allow additional members)
                            $missingMembers = @()
                            foreach ($expectedMember in $expectedMembers) {
                                if ($expectedMember -notin $actualMembers) {
                                    $missingMembers += $expectedMember
                                }
                            }
                            
                            if ($missingMembers.Count -eq 0) {
                                # Individual RG success messages removed for cleaner output
                                $testResult.ValidationResults += [PSCustomObject]@{
                                    Type = 'RG'
                                    Name = $rgName
                                    Status = 'Pass'
                                    Expected = $expectedMembers -join ', '
                                    Actual = $actualMembers -join ', '
                                    Message = 'All required members present'
                                }
                            } else {
                                Write-Host "        ❌ RG '$rgName' - missing members: $($missingMembers -join ', ')" -ForegroundColor Red
                                $testResult.ValidationResults += [PSCustomObject]@{
                                    Type = 'RG'
                                    Name = $rgName
                                    Status = 'Fail'
                                    Expected = $expectedMembers -join ', '
                                    Actual = "Missing: $($missingMembers -join ', ')"
                                    Message = "Missing required members: $($missingMembers -join ', ')"
                                }
                                $testResult.Issues += "RG '$rgName' in GPO '$GPOName' is missing required members: $($missingMembers -join ', ')"
                                $testResult.Recommendations += "Update GPO security settings for Restricted Group '$rgName'"
                                $rgValidationFailed = $true
                            }
                        } else {
                            Write-Host "        ❌ RG '$rgName' - not found in actual GPO" -ForegroundColor Red
                            $testResult.ValidationResults += [PSCustomObject]@{
                                Type = 'RG'
                                Name = $rgName
                                Status = 'Fail'
                                Expected = $expectedMembers -join ', '
                                Actual = 'Not Found'
                                Message = 'RG not found in GPO'
                            }
                            $testResult.Issues += "RG '$rgName' is missing from GPO '$GPOName'"
                            $testResult.Recommendations += "Add Restricted Group '$rgName' to GPO security settings"
                            $rgValidationFailed = $true
                        }
                    }
                }
                
                # Determine overall validation status
                if (-not $uraValidationFailed -and -not $rgValidationFailed) {
                    Write-Host "      ✅ URA and RG validation passed" -ForegroundColor Green
                    $testResult.Status = 'Pass'
                    # Delete mock file when validation passes (no errors to debug)
                    if ((Test-Path $mockFilePath)) {
                        Remove-Item $mockFilePath -Force -ErrorAction SilentlyContinue
                        $testResult.MockFilePath = "$mockFilePath (deleted - no errors)"
                    }
                } else {
                    $testResult.Status = 'Fail'
                    # Keep mock file for debugging when validation fails
                    if ((Test-Path $mockFilePath)) {
                        Write-Host "      📁 Mock file kept for debugging: $mockFilePath" -ForegroundColor Yellow
                    }
                }
                
            } else {
                Write-Host "      ❌ GptTmpl.inf file not found in GPO" -ForegroundColor Red
                $testResult.Status = 'Fail'
                $testResult.Issues += "GptTmpl.inf file is missing from GPO '$GPOName'"
                $testResult.Recommendations += "Generate security template using Update-TierModelGPOConfig"
                # Keep mock file for debugging when GPO is missing (error case)
                if ((Test-Path $mockFilePath)) {
                    Write-Host "      📁 Mock file kept for debugging: $mockFilePath" -ForegroundColor Yellow
                }
            }
            
        } catch {
            Write-Host "      ⚠️  Could not validate URA/RG content: $($_.Exception.Message)" -ForegroundColor Yellow
            $testResult.Status = 'Error'
            $testResult.Issues += "Content validation failed: $($_.Exception.Message)"
            $testResult.Recommendations += "Check GPO accessibility and file permissions"
            # Keep mock file for debugging when error occurs
            if ($mockFilePath -and (Test-Path $mockFilePath)) {
                Write-Host "      📁 Mock file kept for debugging: $mockFilePath" -ForegroundColor Yellow
            }
        }
        
        $durationMs = ((Get-Date) - $startTime).TotalMilliseconds
        
        Write-TierModelLog -Level Info -Message "GPO content validation complete" -Data @{
            GPOName = $GPOName
            Status = $testResult.Status
            ValidationCount = $testResult.ValidationResults.Count
            DurationMs = $durationMs
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return $testResult
        
    } catch {
        Write-TierModelLog -Level Error -Message "GPO content validation failed" -Data @{
            GPOName = $GPOName
            Exception = $_.Exception.Message
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return [PSCustomObject]@{
            GPOName = $GPOName
            MockFilePath = $null
            ActualFilePath = $null
            ValidationResults = @()
            Status = 'Error'
            Issues = @("Content validation failed: $($_.Exception.Message)")
            Recommendations = @('Check GPO name and domain controller connectivity')
        }
    }
}