<#
.SYNOPSIS
Unit tests for TierModel GPO Template and Configuration operations.

.DESCRIPTION
Tests GPO template parsing, content generation, template setting, and GPO configuration.
All tests use mocks to avoid AD/filesystem dependencies.

Functions Tested:
- Get-TierModelGpoTemplate.ps1 - Parse GptTmpl.inf files
- Set-TierModelGpoTemplate.ps1 - Write GptTmpl.inf files
- New-TierModelGptTmplContent.ps1 - Generate GptTmpl.inf content
- Update-TierModelGPOConfig.ps1 - Execute GPO configuration from plan

.NOTES
Created: February 25, 2026
Test Count: 45+ tests across 4 functions
Coverage: Mock-based testing (no AD/filesystem required)
#>

BeforeAll {
    # Import the TierModel module
    Import-Module "$PSScriptRoot\..\modules\TierModel\TierModel.psd1" -Force
    
    # Override Out-File in the TierModel module to handle PowerShell 7+ encoding parameter
    # This allows tests to work with production code that uses -Encoding Unicode (string)
    InModuleScope -ModuleName TierModel {
        function global:Out-File {
            [CmdletBinding()]
            param(
                [Parameter(ValueFromPipeline=$true)]
                $InputObject,
                [string]$FilePath,
                $Encoding,
                [switch]$Force,
                [switch]$Append
            )
            process {
                # This is a test stub that accepts string encoding values
                # In production, this would need to convert string to System.Text.Encoding
            }
        }
    }
    
    # Sample GptTmpl.inf content for testing
    $script:SampleGptTmplContent = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Privilege Rights]
SeNetworkLogonRight = *S-1-5-32-544,*S-1-5-11
SeInteractiveLogonRight = *S-1-5-32-544
[Group Membership]
*S-1-5-32-544__Members = *S-1-5-21-123456789-123456789-123456789-500
Administrators__Members = *S-1-5-21-123456789-123456789-123456789-512
"@
    
    # Sample GPO data for New-TierModelGptTmplContent
    $script:SampleGpoData = [PSCustomObject]@{
        name = 'Test-GPO'
        userRightsAssignments = @(
            [PSCustomObject]@{
                right = 'SeNetworkLogonRight'
                principals = [PSCustomObject]@{
                    resolvableGroups = @('Domain Admins')
                    literalStrings = @('*S-1-5-11')
                }
            }
            [PSCustomObject]@{
                right = 'SeInteractiveLogonRight'
                principals = [PSCustomObject]@{
                    resolvableGroups = @('Enterprise Admins')
                }
            }
        )
        restrictedGroups = [PSCustomObject]@{
            emptyGroups = @('Backup Operators')
            membershipGroups = @(
                [PSCustomObject]@{
                    groupSidOrName = 'Administrators'
                    memberGroups = @('Domain Admins', 'Enterprise Admins')
                }
            )
        }
    }
}

Describe "Get-TierModelGpoTemplate" -Tag 'Unit', 'GpoTemplates' {
    
    Context "GptTmpl.inf Parsing" {
        BeforeEach {
            # Mock Test-Path for file existence check
            Mock -CommandName Test-Path -MockWith { $true } -ModuleName TierModel
            
            # Mock Get-Content to return sample content
            Mock -CommandName Get-Content -MockWith { 
                $script:SampleGptTmplContent -split "`r?`n"
            } -ModuleName TierModel
            
            # Mock Write-TierModelLog
            Mock -CommandName Write-TierModelLog -MockWith { } -ModuleName TierModel
        }
        
        It "Should parse GptTmpl.inf file successfully" {
            $result = Get-TierModelGpoTemplate -Path "C:\Test\GptTmpl.inf"
            
            $result | Should -Not -BeNullOrEmpty
            $result.Sections | Should -Not -BeNullOrEmpty
            $result.FilePath | Should -Be "C:\Test\GptTmpl.inf"
            $result.Modified | Should -Be $false
        }
        
        It "Should parse section headers correctly" {
            $result = Get-TierModelGpoTemplate -Path "C:\Test\GptTmpl.inf"
            
            $result.Sections.Keys | Should -Contain 'Unicode'
            $result.Sections.Keys | Should -Contain 'Version'
            $result.Sections.Keys | Should -Contain 'Privilege Rights'
            $result.Sections.Keys | Should -Contain 'Group Membership'
        }
        
        It "Should parse properties in sections" {
            $result = Get-TierModelGpoTemplate -Path "C:\Test\GptTmpl.inf"
            
            $result.Sections['Unicode'].Lines['Unicode'] | Should -Be 'yes'
            $result.Sections['Version'].Lines['Revision'] | Should -Be '1'
        }
        
        It "Should parse User Rights Assignments" {
            $result = Get-TierModelGpoTemplate -Path "C:\Test\GptTmpl.inf"
            
            $result.Sections['Privilege Rights'].Lines['SeNetworkLogonRight'] | Should -Be '*S-1-5-32-544,*S-1-5-11'
            $result.Sections['Privilege Rights'].Lines['SeInteractiveLogonRight'] | Should -Be '*S-1-5-32-544'
        }
        
        It "Should parse Group Membership section" {
            $result = Get-TierModelGpoTemplate -Path "C:\Test\GptTmpl.inf"
            
            $result.Sections['Group Membership'].Lines.Count | Should -BeGreaterThan 0
        }
        
        It "Should store raw lines" {
            $result = Get-TierModelGpoTemplate -Path "C:\Test\GptTmpl.inf"
            
            $result.RawLines | Should -Not -BeNullOrEmpty
            $result.RawLines.Count | Should -BeGreaterThan 0
        }
        
        It "Should throw when file not found" {
            Mock -CommandName Test-Path -MockWith { $false } -ModuleName TierModel
            
            { Get-TierModelGpoTemplate -Path "C:\NotFound\GptTmpl.inf" } | Should -Throw "*not found*"
        }
        
        It "Should handle empty sections" {
            Mock -CommandName Get-Content -MockWith { 
                @('[Unicode]', 'Unicode=yes', '[EmptySection]', '[Version]', 'Revision=1')
            } -ModuleName TierModel
            
            $result = Get-TierModelGpoTemplate -Path "C:\Test\GptTmpl.inf"
            
            $result.Sections.Keys | Should -Contain 'EmptySection'
            $result.Sections['EmptySection'].Lines.Count | Should -Be 0
        }
        
        It "Should skip comments and empty lines" {
            Mock -CommandName Get-Content -MockWith { 
                @('[Unicode]', '; This is a comment', '', 'Unicode=yes', '[Version]')
            } -ModuleName TierModel
            
            $result = Get-TierModelGpoTemplate -Path "C:\Test\GptTmpl.inf"
            
            $result.Sections['Unicode'].Lines['Unicode'] | Should -Be 'yes'
        }
        
        It "Should use correlation ID when provided" {
            $correlationId = [guid]::NewGuid().ToString()
            
            Get-TierModelGpoTemplate -Path "C:\Test\GptTmpl.inf" -CorrelationId $correlationId
            
            Should -Invoke -CommandName Write-TierModelLog -ModuleName TierModel -Times 2
        }
    }
    
    Context "Error Handling" {
        BeforeEach {
            Mock -CommandName Write-TierModelLog -MockWith { } -ModuleName TierModel
        }
        
        It "Should handle malformed content gracefully" {
            Mock -CommandName Test-Path -MockWith { $true } -ModuleName TierModel
            Mock -CommandName Get-Content -MockWith { 
                throw "File encoding error"
            } -ModuleName TierModel
            
            { Get-TierModelGpoTemplate -Path "C:\Test\GptTmpl.inf" } | Should -Throw
        }
    }
}

Describe "Set-TierModelGpoTemplate" -Tag 'Unit', 'GpoTemplates' {
    
    Context "Template Writing" {
        BeforeEach {
            # Create a template content object
            $script:TemplateContent = [PSCustomObject]@{
                Sections = @{
                    'Unicode' = @{
                        Name = 'Unicode'
                        Lines = @{ 'Unicode' = 'yes' }
                        RawLines = @('Unicode=yes')
                        StartLine = 1
                    }
                    'Version' = @{
                        Name = 'Version'
                        Lines = @{ 
                            'signature' = '"`$CHICAGO`$"'
                            'Revision' = '2'
                        }
                        RawLines = @('signature="`$CHICAGO`$"', 'Revision=2')
                        StartLine = 3
                    }
                }
                RawLines = @('[Unicode]', 'Unicode=yes', '[Version]', 'signature="`$CHICAGO`$"', 'Revision=1')
                FilePath = 'C:\Test\GptTmpl.inf'
                Encoding = 'Unicode'
                Modified = $true
            }
            
            # Mock filesystem operations  
            Mock -CommandName Copy-Item -MockWith { } -ModuleName TierModel
            Mock -CommandName Out-File -MockWith { } -ModuleName TierModel
            Mock -CommandName Move-Item -MockWith { } -ModuleName TierModel
            Mock -CommandName Test-Path -MockWith { $false } -ModuleName TierModel
            Mock -CommandName Remove-Item -MockWith { } -ModuleName TierModel
            Mock -CommandName Write-TierModelLog -MockWith { } -ModuleName TierModel
        }
        
        It "Should write modified template content" {
            Set-TierModelGpoTemplate -TemplateContent $script:TemplateContent -Confirm:$false
            
            Should -Invoke -CommandName Out-File -ModuleName TierModel -Times 1
            Should -Invoke -CommandName Move-Item -ModuleName TierModel -Times 1
        }
        
        It "Should create backup when BackupPath specified" {
            Set-TierModelGpoTemplate -TemplateContent $script:TemplateContent -BackupPath "C:\Backup\GptTmpl.inf.bak" -Confirm:$false
            
            Should -Invoke -CommandName Copy-Item -ModuleName TierModel -Times 1
        }
        
        It "Should skip write when template not modified" {
            $unmodifiedTemplate = $script:TemplateContent.PSObject.Copy()
            $unmodifiedTemplate.Modified = $false
            
            Set-TierModelGpoTemplate -TemplateContent $unmodifiedTemplate -Confirm:$false
            
            Should -Invoke -CommandName Out-File -ModuleName TierModel -Times 0
        }
        
        It "Should support WhatIf" {
            Set-TierModelGpoTemplate -TemplateContent $script:TemplateContent -WhatIf
            
            Should -Invoke -CommandName Out-File -ModuleName TierModel -Times 0
            Should -Invoke -CommandName Move-Item -ModuleName TierModel -Times 0
        }
        
        It "Should use correlation ID when provided" {
            $correlationId = [guid]::NewGuid().ToString()
            
            Set-TierModelGpoTemplate -TemplateContent $script:TemplateContent -CorrelationId $correlationId -Confirm:$false
            
            Should -Invoke -CommandName Write-TierModelLog -ModuleName TierModel -Times 2
        }
        
        It "Should use Unicode encoding for output" {
            Set-TierModelGpoTemplate -TemplateContent $script:TemplateContent -Confirm:$false
            
            Should -Invoke -CommandName Out-File -ModuleName TierModel -ParameterFilter {
                $Encoding -eq 'Unicode'
            }
        }
        
        It "Should clean up temp file on error" {
            Mock -CommandName Move-Item -MockWith { throw "File locked" } -ModuleName TierModel
            Mock -CommandName Test-Path -MockWith { $true } -ModuleName TierModel
            
            { Set-TierModelGpoTemplate -TemplateContent $script:TemplateContent -Confirm:$false -ErrorAction Stop } | Should -Throw
            
            Should -Invoke -CommandName Remove-Item -ModuleName TierModel
        }
    }
}

Describe "New-TierModelGptTmplContent" -Tag 'Unit', 'GpoTemplates' {
    
    Context "Content Generation" {
        BeforeEach {
            # Mock SID resolution
            Mock -CommandName Resolve-TierModelPrincipalSid -MockWith {
                param($Principal)
                
                $sidMap = @{
                    'Domain Admins' = 'S-1-5-21-123456789-123456789-123456789-512'
                    'Enterprise Admins' = 'S-1-5-21-123456789-123456789-123456789-519'
                    'Backup Operators' = 'S-1-5-32-551'
                }
                
                [PSCustomObject]@{
                    Success = $true
                    Sid = $sidMap[$Principal]
                    Principal = $Principal
                }
            } -ModuleName TierModel
            
            Mock -CommandName Write-TierModelLog -MockWith { } -ModuleName TierModel
        }
        
        It "Should generate valid GptTmpl.inf content" {
            $result = New-TierModelGptTmplContent -GPOData $script:SampleGpoData -DomainController 'DC01'
            
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match '\[Unicode\]'
            $result | Should -Match 'Unicode=yes'
            $result | Should -Match '\[Version\]'
            $result | Should -Match '\[Privilege Rights\]'
        }
        
        It "Should include User Rights Assignments" {
            $result = New-TierModelGptTmplContent -GPOData $script:SampleGpoData -DomainController 'DC01'
            
            $result | Should -Match 'SeNetworkLogonRight'
            $result | Should -Match 'SeInteractiveLogonRight'
        }
        
        It "Should resolve group names to SIDs" {
            $result = New-TierModelGptTmplContent -GPOData $script:SampleGpoData -DomainController 'DC01'
            
            $result | Should -Match '\*S-1-5-21-123456789-123456789-123456789-512'  # Domain Admins
            $result | Should -Match '\*S-1-5-21-123456789-123456789-123456789-519'  # Enterprise Admins
        }
        
        It "Should preserve literal SID strings" {
            $result = New-TierModelGptTmplContent -GPOData $script:SampleGpoData -DomainController 'DC01'
            
            $result | Should -Match '\*S-1-5-11'  # Literal SID
        }
        
        It "Should include Group Membership section" {
            $result = New-TierModelGptTmplContent -GPOData $script:SampleGpoData -DomainController 'DC01'
            
            $result | Should -Match '\[Group Membership\]'
        }
        
        It "Should handle empty groups in Restricted Groups" {
            $result = New-TierModelGptTmplContent -GPOData $script:SampleGpoData -DomainController 'DC01'
            
            $result | Should -Match 'Backup Operators='
        }
        
        It "Should handle membership groups in Restricted Groups" {
            $result = New-TierModelGptTmplContent -GPOData $script:SampleGpoData -DomainController 'DC01'
            
            $result | Should -Match 'Administrators=.*\*S-1-5-21'
        }
        
        It "Should handle GPO data without restrictedGroups" {
            $gpoDataNoRG = [PSCustomObject]@{
                name = 'Test-GPO-NoRG'
                userRightsAssignments = $script:SampleGpoData.userRightsAssignments
            }
            
            $result = New-TierModelGptTmplContent -GPOData $gpoDataNoRG -DomainController 'DC01'
            
            $result | Should -Match '\[Group Membership\]'
            $result | Should -Not -Match 'Backup Operators'
        }
        
        It "Should handle GPO data without userRightsAssignments" {
            $gpoDataNoURA = [PSCustomObject]@{
                name = 'Test-GPO-NoURA'
                restrictedGroups = $script:SampleGpoData.restrictedGroups
            }
            
            $result = New-TierModelGptTmplContent -GPOData $gpoDataNoURA -DomainController 'DC01'
            
            $result | Should -Match '\[Privilege Rights\]'
            $result | Should -Match 'Backup Operators='
        }
        
        It "Should warn on SID resolution failure (non-strict mode)" {
            Mock -CommandName Resolve-TierModelPrincipalSid -MockWith {
                [PSCustomObject]@{
                    Success = $false
                    Error = "Principal not found"
                }
            } -ModuleName TierModel
            
            { New-TierModelGptTmplContent -GPOData $script:SampleGpoData -DomainController 'DC01' } | Should -Not -Throw
        }
        
        It "Should throw on SID resolution failure in StrictMode" {
            Mock -CommandName Resolve-TierModelPrincipalSid -MockWith {
                [PSCustomObject]@{
                    Success = $false
                    Error = "Principal not found"
                }
            } -ModuleName TierModel
            
            { New-TierModelGptTmplContent -GPOData $script:SampleGpoData -DomainController 'DC01' -StrictMode } | Should -Throw "*Could not resolve SID*"
        }
        
        It "Should handle old URA format (rights array)" {
            $oldFormatGpo = [PSCustomObject]@{
                name = 'Test-GPO-OldFormat'
                userRightsAssignments = @(
                    [PSCustomObject]@{
                        rights = @('SeNetworkLogonRight', 'SeInteractiveLogonRight')
                        principalGroups = [PSCustomObject]@{
                            alwaysInclude = @('Domain Admins')
                            literalStrings = @('*S-1-5-11')
                        }
                    }
                )
            }
            
            $result = New-TierModelGptTmplContent -GPOData $oldFormatGpo -DomainController 'DC01'
            
            $result | Should -Match 'SeNetworkLogonRight'
            $result | Should -Match 'SeInteractiveLogonRight'
        }
    }

    Context "Conditional Groups" {
        BeforeEach {
            Mock -CommandName Resolve-TierModelPrincipalSid -MockWith {
                param($Principal)
                [PSCustomObject]@{
                    Success = $true
                    Sid     = 'S-1-5-21-123456789-123456789-123456789-1101'
                    Principal = $Principal
                }
            } -ModuleName TierModel

            Mock -CommandName Write-TierModelLog -MockWith { } -ModuleName TierModel
        }

        It "Should include conditional group SID when AD group exists" {
            Mock -CommandName Get-ADGroup -MockWith {
                [PSCustomObject]@{ Name = 'DnsAdmins' }
            } -ModuleName TierModel

            $gpoData = [PSCustomObject]@{
                name = 'Test-GPO-Conditional'
                userRightsAssignments = @(
                    [PSCustomObject]@{
                        right = 'SeDenyBatchLogonRight'
                        principals = [PSCustomObject]@{
                            resolvableGroups  = @()
                            conditionalGroups = @(
                                [PSCustomObject]@{
                                    names      = @('DnsAdmins')
                                    conditions = @([PSCustomObject]@{ type = 'groupExists'; operator = 'exists' })
                                }
                            )
                            literalStrings = @()
                        }
                    }
                )
            }

            $result = New-TierModelGptTmplContent -GPOData $gpoData -DomainController 'DC01'

            $result | Should -Match 'SeDenyBatchLogonRight'
            $result | Should -Match '\*S-1-5-21'
            # $Identity is not bound when AD module is absent; assert call count only
            Should -Invoke Get-ADGroup -ModuleName TierModel -Times 1
        }

        It "Should exclude conditional group and not throw when AD group does not exist" {
            Mock -CommandName Get-ADGroup -MockWith { throw "Cannot find an object" } -ModuleName TierModel

            $gpoData = [PSCustomObject]@{
                name = 'Test-GPO-MissingGroup'
                userRightsAssignments = @(
                    [PSCustomObject]@{
                        right = 'SeDenyBatchLogonRight'
                        principals = [PSCustomObject]@{
                            resolvableGroups  = @()
                            conditionalGroups = @(
                                [PSCustomObject]@{
                                    names      = @('DnsAdmins', 'DnsUpdateProxy')
                                    conditions = @([PSCustomObject]@{ type = 'groupExists'; operator = 'exists' })
                                }
                            )
                            literalStrings = @()
                        }
                    }
                )
            }

            { New-TierModelGptTmplContent -GPOData $gpoData -DomainController 'DC01' -StrictMode } | Should -Not -Throw
            Should -Invoke Get-ADGroup -ModuleName TierModel -Times 2
            Should -Invoke Resolve-TierModelPrincipalSid -ModuleName TierModel -Times 0
        }

        It "Should include only found groups when names have mixed AD existence" {
            # Mock Get-TierModelConditionalGroupNames directly (one level up from Get-ADGroup)
            # so we avoid the $Identity binding problem with external AD cmdlets entirely.
            # This is the correct unit-test boundary for New-TierModelGptTmplContent.
            Mock -CommandName Get-TierModelConditionalGroupNames -MockWith {
                return @('DnsAdmins')
            } -ModuleName TierModel

            $gpoData = [PSCustomObject]@{
                name = 'Test-GPO-MixedGroups'
                userRightsAssignments = @(
                    [PSCustomObject]@{
                        right = 'SeDenyBatchLogonRight'
                        principals = [PSCustomObject]@{
                            resolvableGroups  = @()
                            conditionalGroups = @(
                                [PSCustomObject]@{
                                    names      = @('DnsAdmins', 'DnsUpdateProxy')
                                    conditions = @([PSCustomObject]@{ type = 'groupExists'; operator = 'exists' })
                                }
                            )
                            literalStrings = @()
                        }
                    }
                )
            }

            New-TierModelGptTmplContent -GPOData $gpoData -DomainController 'DC01'

            # DnsAdmins found -> resolved once; DnsUpdateProxy not found -> never resolved
            Should -Invoke Resolve-TierModelPrincipalSid -ModuleName TierModel -Times 1 -ParameterFilter { $Principal -eq 'DnsAdmins' }
            Should -Invoke Resolve-TierModelPrincipalSid -ModuleName TierModel -Times 0 -ParameterFilter { $Principal -eq 'DnsUpdateProxy' }
        }

        It "Should include all names unconditionally when no conditions defined" {
            # Get-ADGroup should NOT be called when there are no conditions
            Mock -CommandName Get-ADGroup -MockWith { throw "Should not be called" } -ModuleName TierModel

            $gpoData = [PSCustomObject]@{
                name = 'Test-GPO-NoConditions'
                userRightsAssignments = @(
                    [PSCustomObject]@{
                        right = 'SeDenyBatchLogonRight'
                        principals = [PSCustomObject]@{
                            resolvableGroups  = @()
                            conditionalGroups = @(
                                [PSCustomObject]@{
                                    names = @('DnsAdmins')
                                    # no conditions property
                                }
                            )
                            literalStrings = @()
                        }
                    }
                )
            }

            { New-TierModelGptTmplContent -GPOData $gpoData -DomainController 'DC01' } | Should -Not -Throw
            Should -Invoke Get-ADGroup -ModuleName TierModel -Times 0
            Should -Invoke Resolve-TierModelPrincipalSid -ModuleName TierModel -Times 1 -ParameterFilter { $Principal -eq 'DnsAdmins' }
        }
    }
}

Describe "Update-TierModelGPOConfig" -Tag 'Unit', 'GpoTemplates' {
    
    Context "Configuration Execution" {
        BeforeEach {
            # Create a deployment plan
            $script:DeploymentPlan = [PSCustomObject]@{
                Actions = @(
                    [PSCustomObject]@{
                        Action = 'ConfigureGPO'
                        Path = 'OU=Tier0,DC=contoso,DC=com'
                        Data = $script:SampleGpoData
                    }
                    [PSCustomObject]@{
                        Action = 'LinkGPO'
                        Path = 'OU=Tier0,DC=contoso,DC=com'
                        Data = [PSCustomObject]@{ name = 'Other-GPO' }
                    }
                )
            }
            
            # Mock AD cmdlets
            Mock -CommandName Get-GPO -MockWith {
                [PSCustomObject]@{
                    DisplayName = 'Test-GPO'
                    Id = [guid]::NewGuid()
                }
            } -ModuleName TierModel
            
            Mock -CommandName Get-ADDomain -MockWith {
                [PSCustomObject]@{
                    DNSRoot = 'contoso.com'
                    PDCEmulator = 'DC01.contoso.com'
                }
            } -ModuleName TierModel
            
            # Mock filesystem operations
            Mock -CommandName Test-Path -MockWith { 
                param($Path, $LiteralPath)
                $pathToCheck = if ($PSBoundParameters.ContainsKey('LiteralPath')) { $LiteralPath } 
                               elseif ($PSBoundParameters.ContainsKey('Path')) { $Path } 
                               else { $Path }
                # Return $false for SecEdit folder to trigger creation
                # Return $true for GptTmpl.inf file to pass validation
                if ($pathToCheck -like '*SecEdit*' -and $pathToCheck -notlike '*GptTmpl.inf') {
                    return $false
                } elseif ($pathToCheck -like '*GptTmpl.inf*') {
                    return $true
                } else {
                    return $false
                }
            } -ModuleName TierModel
            Mock -CommandName New-Item -MockWith { 
                [PSCustomObject]@{ FullName = $Path }
            } -ModuleName TierModel
            Mock -CommandName Out-File -MockWith { } -ModuleName TierModel
            Mock -CommandName Get-Item -MockWith {
                [PSCustomObject]@{ Length = 1024 }
            } -ModuleName TierModel
            
            # Mock content generation
            Mock -CommandName New-TierModelGptTmplContent -MockWith {
                return $script:SampleGptTmplContent
            } -ModuleName TierModel
            
            Mock -CommandName Write-TierModelLog -MockWith { } -ModuleName TierModel
            Mock -CommandName Write-Host -MockWith { } -ModuleName TierModel
        }
        
        It "Should filter and execute only ConfigureGPO actions" {
            $result = Update-TierModelGPOConfig -Plan $script:DeploymentPlan -DomainController 'DC01' -Confirm:$false
            
            $result.Executed | Should -Be 1
            Should -Invoke -CommandName New-TierModelGptTmplContent -ModuleName TierModel -Times 1
        }
        
        It "Should get GPO object from AD" {
            Update-TierModelGPOConfig -Plan $script:DeploymentPlan -DomainController 'DC01' -Confirm:$false
            
            Should -Invoke -CommandName Get-GPO -ModuleName TierModel -Times 1
        }
        
        It "Should create Machine folder if not exists" {
            Mock -CommandName Test-Path -MockWith { $false } -ModuleName TierModel
            
            Update-TierModelGPOConfig -Plan $script:DeploymentPlan -DomainController 'DC01' -Confirm:$false
            
            Should -Invoke -CommandName New-Item -ModuleName TierModel -ParameterFilter {
                $ItemType -eq 'Directory'
            }
        }
        
        It "Should create SecEdit folder structure" {
            Update-TierModelGPOConfig -Plan $script:DeploymentPlan -DomainController 'DC01' -Confirm:$false
            
            Should -Invoke -CommandName New-Item -ModuleName TierModel -Times 2
        }
        
        It "Should write GptTmpl.inf with Unicode encoding" {
            Update-TierModelGPOConfig -Plan $script:DeploymentPlan -DomainController 'DC01' -Confirm:$false
            
            Should -Invoke -CommandName Out-File -ModuleName TierModel -ParameterFilter {
                $Encoding -eq 'Unicode'
            }
        }
        
        It "Should validate GptTmpl.inf file creation" {
            Mock -CommandName Test-Path -MockWith { 
                param($Path, $LiteralPath)
                $pathToCheck = if ($LiteralPath) { $LiteralPath } else { $Path }
                # Return false for SecEdit folder, true for GptTmpl.inf file
                if ($pathToCheck -like '*SecEdit') {
                    return $false
                } elseif ($pathToCheck -match 'GptTmpl\.inf$') {
                    return $true
                } else {
                    return $false
                }
            } -ModuleName TierModel
            
            $result = Update-TierModelGPOConfig -Plan $script:DeploymentPlan -DomainController 'DC01' -Confirm:$false
            
            $result.Executed | Should -Be 1
            $result.Failed | Should -Be 0
        }
        
        It "Should support WhatIf mode" {
            $result = Update-TierModelGPOConfig -Plan $script:DeploymentPlan -DomainController 'DC01' -WhatIf
            
            $result.Skipped | Should -Be 1
            $result.Executed | Should -Be 0
            Should -Invoke -CommandName Out-File -ModuleName TierModel -Times 0
        }
        
        It "Should write mock file when MockFilePath specified" {
            $mockPath = "C:\Temp\MockGptTmpl.inf"
            
            Update-TierModelGPOConfig -Plan $script:DeploymentPlan -DomainController 'DC01' -MockFilePath $mockPath -Confirm:$false
            
            Should -Invoke -CommandName Out-File -ModuleName TierModel -Times 2  # Mock + actual
        }
        
        It "Should handle GPO not found error" {
            Mock -CommandName Get-GPO -MockWith { $null } -ModuleName TierModel
            
            $result = Update-TierModelGPOConfig -Plan $script:DeploymentPlan -DomainController 'DC01' -Confirm:$false
            
            $result.Failed | Should -Be 1
            $result.Errors.Count | Should -Be 1
        }
        
        It "Should handle file write errors" {
            Mock -CommandName Out-File -MockWith { throw "Access denied" } -ModuleName TierModel
            
            $result = Update-TierModelGPOConfig -Plan $script:DeploymentPlan -DomainController 'DC01' -Confirm:$false
            
            $result.Failed | Should -Be 1
            $result.Converged | Should -Be $false
        }
        
        It "Should return execution summary" {
            $result = Update-TierModelGPOConfig -Plan $script:DeploymentPlan -DomainController 'DC01' -Confirm:$false
            
            $result.Executed | Should -BeGreaterOrEqual 0
            $result.Failed | Should -BeGreaterOrEqual 0
            $result.Skipped | Should -BeGreaterOrEqual 0
            $result.Converged | Should -BeOfType [bool]
            $result.CorrelationId | Should -Not -BeNullOrEmpty
        }
        
        It "Should handle empty plan" {
            $emptyPlan = [PSCustomObject]@{ Actions = @() }
            
            $result = Update-TierModelGPOConfig -Plan $emptyPlan -DomainController 'DC01' -Confirm:$false
            
            $result.Executed | Should -Be 0
            $result.Failed | Should -Be 0
        }
        
        It "Should track duration in milliseconds" {
            $result = Update-TierModelGPOConfig -Plan $script:DeploymentPlan -DomainController 'DC01' -Confirm:$false
            
            $result.DurationMs | Should -BeGreaterThan 0
        }
    }
}
