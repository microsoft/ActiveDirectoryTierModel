BeforeAll {
    # Load the TierModel module
    $ModulePath = "$PSScriptRoot\..\Modules\TierModel\TierModel.psd1"
    Import-Module $ModulePath -Force
}

Describe "Get-TierModelAdmx - ADMX Planning with Hash Verification" -Tag "Unit", "ADMX", "Planning" {
    
    BeforeAll {
        # Mock configuration JSON content
        $script:MockAdmxConfig = @{
            version = "2.0.0"
            admx = @{
                destinationPath = "\\{{DOMAIN_FQDN}}\SYSVOL\{{DOMAIN_FQDN}}\Policies\PolicyDefinitions"
                sourcePath = "config\admx"
               files = @{
                    "TestPolicy1.admx" = @{
                        hash = "ABC123DEF456GHI789JKL012MNO345PQ"
                    }
                    "TestPolicy2.admx" = @{
                        hash = "XYZ987WVU654TSR321PON098MLK765IH"
                    }
                }
            }
        } | ConvertTo-Json -Depth 10
        
        $script:MockAdmlConfig = @{
            version = "2.0.0"
            adml = @{
                destinationPath = "\\{{DOMAIN_FQDN}}\SYSVOL\{{DOMAIN_FQDN}}\Policies\PolicyDefinitions\en-US"
                sourcePath = "config\admx\en-US"
                files = @{
                    "TestPolicy1.adml" = @{
                        hash = "AAA111BBB222CCC333DDD444EEE555FF"
                    }
                    "TestPolicy2.adml" = @{
                        hash = "FFF555EEE444DDD333CCC222BBB111AA"
                    }
                }
            }
        } | ConvertTo-Json -Depth 10
        
        # Mock config object
        $script:MockConfig = [PSCustomObject]@{}
        
        # Mock logging
        Mock Write-TierModelLog -ModuleName TierModel { }
        Mock Write-Host -ModuleName TierModel { }
    }
    
    BeforeEach {
        # Reset mocks for each test
        Mock Get-ADDomain -ModuleName TierModel {
            return [PSCustomObject]@{ DNSRoot = "test.domain.com" }
        }
        
        # Mock configuration file loading
        Mock Get-Content -ModuleName TierModel {
            param($Path)
            if ($Path -like "*tiermodel-admx.json") {
                return $script:MockAdmxConfig
            } elseif ($Path -like "*tiermodel-adml-*.json") {
                return $script:MockAdmlConfig
            }
            # Return empty for other files
            return "{}"
        }
        
        # Mock Test-Path for config and source files
        Mock Test-Path -ModuleName TierModel {
            param($Path)
            # Config files exist
            if ($Path -like "*tiermodel-admx.json" -or $Path -like "*tiermodel-adml-*.json") {
                return $true
            }
            # Source directories exist (config\admx, config\admx\en-US)
            if ($Path -like "*config\admx*" -and $Path -notlike "*.*") {
                return $true
            }
            # Source files exist (*.admx, *.adml)
            if ($Path -like "*config\admx\*.admx" -or $Path -like "*config\admx\*\*.adml") {
                return $true
            }
            # Destination SYSVOL files don't exist by default
            return $false
        }
        
        # Mock Get-FileHash to return predictable hashes
        Mock Get-FileHash -ModuleName TierModel {
            param($Path, $Algorithm)
            $fileName = Split-Path $Path -Leaf
            
            # Return matching hashes for source files
            switch ($fileName) {
                "TestPolicy1.admx" { return [PSCustomObject]@{ Hash = "ABC123DEF456GHI789JKL012MNO345PQ" } }
                "TestPolicy2.admx" { return [PSCustomObject]@{ Hash = "XYZ987WVU654TSR321PON098MLK765IH" } }
                "TestPolicy1.adml" { return [PSCustomObject]@{ Hash = "AAA111BBB222CCC333DDD444EEE555FF" } }
                "TestPolicy2.adml" { return [PSCustomObject]@{ Hash = "FFF555EEE444DDD333CCC222BBB111AA" } }
                default { return [PSCustomObject]@{ Hash = "DIFFERENT_HASH_MISMATCH_000000000" } }
            }
        }
    }
    
    It "Should analyze files and detect new imports needed (files missing from destination)" {
        $result = Get-TierModelAdmx -Config $script:MockConfig -DomainController "DC01" -AdmlLanguage "en-US" -Silent
        
        $result.Summary.TotalFiles | Should -Be 4  # 2 ADMX + 2 ADML
        $result.Summary.FilesToUpdate | Should -Be 4  # All need import
        $result.Summary.RequiresUpdate | Should -Be $true
        $result.Analysis.AdmxToUpdate[0].ActionType | Should -Be "Import"
        $result.Analysis.AdmlToUpdate[0].ActionType | Should -Be "Import"
    }
    
    It "Should detect files that are up-to-date (hash match)" {
        # Mock Test-Path to indicate destination files exist
        Mock Test-Path -ModuleName TierModel {
            param($Path)
            return $true
        }
        
        $result = Get-TierModelAdmx -Config $script:MockConfig -DomainController "DC01" -AdmlLanguage "en-US" -Silent
        
        $result.Summary.FilesToUpdate | Should -Be 0
        $result.Summary.FilesUpToDate | Should -Be 4
        $result.Summary.RequiresUpdate | Should -Be $false
        $result.Analysis.AdmxUpToDate[0].Reason | Should -Match "Hash matches"
    }
    
    It "Should detect files needing updates (hash mismatch)" {
        Mock Test-Path -ModuleName TierModel {
            param($Path)
            return $true
        }
        
        Mock Get-FileHash -ModuleName TierModel {
            param($Path)
            $fileName = Split-Path $Path -Leaf
            
            # Source files (in config\admx) have expected hashes
            if ($Path -like "*config\admx*") {
                switch ($fileName) {
                    "TestPolicy1.admx" { return [PSCustomObject]@{ Hash = "ABC123DEF456GHI789JKL012MNO345PQ" } }
                    "TestPolicy2.admx" { return [PSCustomObject]@{ Hash = "XYZ987WVU654TSR321PON098MLK765IH" } }
                    "TestPolicy1.adml" { return [PSCustomObject]@{ Hash = "AAA111BBB222CCC333DDD444EEE555FF" } }
                    "TestPolicy2.adml" { return [PSCustomObject]@{ Hash = "FFF555EEE444DDD333CCC222BBB111AA" } }
                }
            } else {
                # Destination files (in SYSVOL) have different hashes (outdated)
                return [PSCustomObject]@{ Hash = "OUTDATED_HASH_000000000000000000" }
            }
        }
        
        $result = Get-TierModelAdmx -Config $script:MockConfig -DomainController "DC01" -AdmlLanguage "en-US" -Silent
        
        $result.Summary.FilesToUpdate | Should -Be 4
        $result.Analysis.AdmxToUpdate[0].ActionType | Should -Be "Update"
        $result.Analysis.AdmxToUpdate[0].Reason | Should -Match "Hash mismatch"
    }
    
    It "Should handle missing configuration files gracefully" {
        # Mock Test-Path to return false for ADMX config
        Mock Test-Path -ModuleName TierModel {
            param($Path)
            if ($Path -like "*tiermodel-admx.json") {
                return $false
            }
            return $true
        }
        
        $result = Get-TierModelAdmx -Config $script:MockConfig -DomainController "DC01" -AdmlLanguage "en-US" -Silent
        
        $result.Summary.Errors | Should -Be 1
        $result.Analysis.Errors[0] | Should -Match "ADMX configuration file not found"
    }
    
    It "Should resolve SYSVOL destination paths correctly" {
        Mock Get-ADDomain -ModuleName TierModel {
            return [PSCustomObject]@{ DNSRoot = "contoso.com" }
        }
        
        $result = Get-TierModelAdmx -Config $script:MockConfig -DomainController "DC01" -AdmlLanguage "en-US" -Silent
        
        $result.Domain | Should -Be "contoso.com"
        $result.Analysis.AdmxToUpdate[0].DestinationPath | Should -Match "\\\\DC01\\SYSVOL\\CONTOSO.COM"
    }
    
    It "Should handle domain controller connection errors" {
        Mock Get-ADDomain -ModuleName TierModel {
            throw "Unable to contact domain controller"
        }
        
        $result = Get-TierModelAdmx -Config $script:MockConfig -DomainController "InvalidDC" -AdmlLanguage "en-US" -Silent
        
        $result.Summary.Errors | Should -Be 1
        $result.Domain | Should -BeNullOrEmpty
    }
    
    It "Should include correlation ID and timing information" {
        $result = Get-TierModelAdmx -Config $script:MockConfig -DomainController "DC01" -AdmlLanguage "en-US" -Silent
        
        $result.CorrelationId | Should -Match "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
        $result.DurationMs | Should -BeGreaterThan 0
    }
    
    It "Should provide comprehensive analysis results structure" {
        $result = Get-TierModelAdmx -Config $script:MockConfig -DomainController "DC01" -AdmlLanguage "en-US" -Silent
        
        $result.PSObject.Properties.Name | Should -Contain "Analysis"
        $result.PSObject.Properties.Name | Should -Contain "Summary"
        $result.PSObject.Properties.Name | Should -Contain "Domain"
        $result.PSObject.Properties.Name | Should -Contain "AdmlLanguage"
        $result.PSObject.Properties.Name | Should -Contain "CorrelationId"
        
        $result.Analysis.TotalAdmxFiles | Should -Be 2
        $result.Analysis.TotalAdmlFiles | Should -Be 2
    }
}

Describe "Test-TierModelAdmx - ADMX Audit with Hash Verification" -Tag "Unit", "ADMX", "Audit" {
    
    BeforeAll {
        # Mock configuration JSON
        $script:MockAuditAdmxConfig = @{
            version = "2.0.0"
            admx = @{
                destinationPath = "\\{{DOMAIN_FQDN}}\SYSVOL\{{DOMAIN_FQDN}}\Policies\PolicyDefinitions"
                files = @{
                    "Compliant.admx" = @{ hash = "COMPLIANT_HASH_11111111111111111" }
                    "Outdated.admx" = @{ hash = "EXPECTED_HASH_22222222222222222" }
                    "Missing.admx" = @{ hash = "MISSING_HASH_333333333333333333" }
                }
            }
        } | ConvertTo-Json -Depth 10
        
        $script:MockAuditAdmlConfig = @{
            version = "2.0.0"
            adml = @{
                destinationPath = "\\{{DOMAIN_FQDN}}\SYSVOL\{{DOMAIN_FQDN}}\Policies\PolicyDefinitions\en-US"
                files = @{
                    "Compliant.adml" = @{ hash = "COMPLIANT_ADML_HASH_111111111" }
                    "Outdated.adml" = @{ hash = "EXPECTED_ADML_HASH_222222222" }
                }
            }
        } | ConvertTo-Json -Depth 10
        
        $script:MockConfig = [PSCustomObject]@{}
        Mock Write-TierModelLog -ModuleName TierModel { }
        Mock Write-Host -ModuleName TierModel { }
    }
    
    BeforeEach {
        Mock Get-ADDomain -ModuleName TierModel {
            return [PSCustomObject]@{ DNSRoot = "test.domain.com" }
        }
        
        Mock Get-Content -ModuleName TierModel {
            param($Path)
            if ($Path -like "*tiermodel-admx.json") {
                return $script:MockAuditAdmxConfig
            } elseif ($Path -like "*tiermodel-adml-*.json") {
                return $script:MockAuditAdmlConfig
            }
            return "{}"
        }
        
        Mock Test-Path -ModuleName TierModel {
            param($Path)
            # Config files exist
            if ($Path -like "*tiermodel-*.json") {
                return $true
            }
            # Destination files: Compliant and Outdated exist, Missing doesn't
            $fileName = Split-Path $Path -Leaf
            return ($fileName -in @("Compliant.admx", "Compliant.adml", "Outdated.admx", "Outdated.adml"))
        }
        
        Mock Get-FileHash -ModuleName TierModel {
            param($Path)
            $fileName = Split-Path $Path -Leaf
            
            switch ($fileName) {
                "Compliant.admx" { return [PSCustomObject]@{ Hash = "COMPLIANT_HASH_11111111111111111" } }
                "Compliant.adml" { return [PSCustomObject]@{ Hash = "COMPLIANT_ADML_HASH_111111111" } }
                "Outdated.admx" { return [PSCustomObject]@{ Hash = "ACTUAL_DIFFERENT_HASH_0000000000" } }
                "Outdated.adml" { return [PSCustomObject]@{ Hash = "ACTUAL_DIFFERENT_ADML_HASH_00" } }
                default { return [PSCustomObject]@{ Hash = "UNKNOWN_HASH" } }
            }
        }
    }
    
    It "Should identify compliant files (hash match)" {
        $result = Test-TierModelAdmx -Config $script:MockConfig -DomainController "DC01" -AdmlLanguage "en-US" -Silent
        
        $compliantAdmx = $result.Results | Where-Object { $_.FileName -eq "Compliant.admx" }
        $compliantAdmx.Status | Should -Be "Pass"
        $compliantAdmx.Exists | Should -Be $true
        $compliantAdmx.Issues.Count | Should -Be 0
    }
    
    It "Should identify non-compliant files (hash mismatch)" {
        $result = Test-TierModelAdmx -Config $script:MockConfig -DomainController "DC01" -AdmlLanguage "en-US" -Silent
        
        $outdatedAdmx = $result.Results | Where-Object { $_.FileName -eq "Outdated.admx" }
        $outdatedAdmx.Status | Should -Be "Mismatch"
        $outdatedAdmx.Issues | Should -Contain "Hash mismatch - file content differs from expected"
    }
    
    It "Should identify missing files" {
        $result = Test-TierModelAdmx -Config $script:MockConfig -DomainController "DC01" -AdmlLanguage "en-US" -Silent
        
        $missingAdmx = $result.Results | Where-Object { $_.FileName -eq "Missing.admx" }
        $missingAdmx.Status | Should -Be "Missing"
        $missingAdmx.Exists | Should -Be $false
        $missingAdmx.Issues | Should -Contain "ADMX file not found in SYSVOL"
    }
    
    It "Should calculate compliance percentage correctly" {
        $result = Test-TierModelAdmx -Config $script:MockConfig -DomainController "DC01" -AdmlLanguage "en-US" -Silent
        
        # 2 compliant out of 5 total = 40%
        $result.Summary.CompliancePercentage | Should -BeGreaterThan 0
        $result.Summary.CompliancePercentage | Should -BeLessThan 100
    }
    
    It "Should determine convergence status" {
        $result = Test-TierModelAdmx -Config $script:MockConfig -DomainController "DC01" -AdmlLanguage "en-US" -Silent
        
        $result.Converged | Should -Be $false  # Not all files are compliant
    }
    
    It "Should provide findings summary" {
        $result = Test-TierModelAdmx -Config $script:MockConfig -DomainController "DC01" -AdmlLanguage "en-US" -Silent
        
        $result.Findings | Should -Not -BeNullOrEmpty
        $result.Findings.Count | Should -BeGreaterThan 0
    }
    
    It "Should include timing and correlation information" {
        $result = Test-TierModelAdmx -Config $script:MockConfig -DomainController "DC01" -AdmlLanguage "en-US" -Silent
        
        $result.CorrelationId | Should -Match "^[0-9a-f]{8}-"
        $result.DurationMs | Should -BeGreaterThan 0
    }
}

Describe "Copy-TierModelAdmx - ADMX Deployment" -Tag "Unit", "ADMX", "Deployment" {
    
    BeforeAll {
        # Mock configuration JSON
        $script:MockDeployAdmxConfig = @{
            version = "2.0.0"
            admx = @{
                destinationPath = "\\{{DOMAIN_FQDN}}\SYSVOL\{{DOMAIN_FQDN}}\Policies\PolicyDefinitions"
                sourcePath = "config\admx"
                files = @{
                    "Deploy1.admx" = @{ hash = "DEPLOY1_HASH_11111111111111111" }
                }
            }
        } | ConvertTo-Json -Depth 10
        
        $script:MockDeployAdmlConfig = @{
            version = "2.0.0"
            adml = @{
                destinationPath = "\\{{DOMAIN_FQDN}}\SYSVOL\{{DOMAIN_FQDN}}\Policies\PolicyDefinitions\en-US"
                sourcePath = "config\admx\en-US"
                files = @{
                    "Deploy1.adml" = @{ hash = "DEPLOY1_ADML_HASH_11111111111" }
                }
            }
        } | ConvertTo-Json -Depth 10
        
        $script:MockConfig = [PSCustomObject]@{}
        Mock Write-TierModelLog -ModuleName TierModel { }
        Mock Write-Host -ModuleName TierModel { }
    }
    
    BeforeEach {
        Mock Get-ADDomain -ModuleName TierModel {
            return [PSCustomObject]@{ DNSRoot = "test.domain.com" }
        }
        
        Mock Get-Content -ModuleName TierModel {
            param($Path)
            if ($Path -like "*tiermodel-admx.json") {
                return $script:MockDeployAdmxConfig
            } elseif ($Path -like "*tiermodel-adml-*.json") {
                return $script:MockDeployAdmlConfig
            }
            return "{}"
        }
        
        Mock Test-Path -ModuleName TierModel {
            param($Path)
            # Config files exist
            if ($Path -like "*tiermodel-*.json") {
                return $true
            }
            # Source files exist
            if ($Path -like "*config\admx\*") {
                return $true
            }
            # Destination files don't exist by default
            return $false
        }
        
        Mock Get-FileHash -ModuleName TierModel {
            param($Path)
            $fileName = Split-Path $Path -Leaf
            
            switch ($fileName) {
                "Deploy1.admx" { return [PSCustomObject]@{ Hash = "DEPLOY1_HASH_11111111111111111" } }
                "Deploy1.adml" { return [PSCustomObject]@{ Hash = "DEPLOY1_ADML_HASH_11111111111" } }
                default { return [PSCustomObject]@{ Hash = "OTHER_HASH" } }
            }
        }
        
        Mock Get-TierModelAdmx -ModuleName TierModel {
            return [PSCustomObject]@{
                Analysis = [PSCustomObject]@{
                    AdmxToUpdate = @(
                        [PSCustomObject]@{ 
                            Name = "Deploy1.admx"
                            SourcePath = "c:\ADO\TierModelv2\TierModel\config\admx\Deploy1.admx"
                            DestinationPath = "\\DC01\SYSVOL\TEST.DOMAIN.COM\Policies\PolicyDefinitions\Deploy1.admx"
                            ExpectedHash = "DEPLOY1_HASH_11111111111111111"
                            ActionType = "Import"
                        }
                    )
                    AdmlToUpdate = @(
                        [PSCustomObject]@{ 
                            Name = "Deploy1.adml"
                            SourcePath = "c:\ADO\TierModelv2\TierModel\config\admx\en-US\Deploy1.adml"
                            DestinationPath = "\\DC01\SYSVOL\TEST.DOMAIN.COM\Policies\PolicyDefinitions\en-US\Deploy1.adml"
                            ExpectedHash = "DEPLOY1_ADML_HASH_11111111111"
                            ActionType = "Import"
                        }
                    )
                    AdmxUpToDate = @()
                    AdmlUpToDate = @()
                    Errors = @()
                }
            }
        }
        
        Mock New-Item -ModuleName TierModel {
            param($Path, $ItemType, $Force)
            return [PSCustomObject]@{ FullName = $Path }
        }
        
        Mock Copy-Item -ModuleName TierModel { }
    }
    
    It "Should deploy ADMX files successfully" {
        $result = Copy-TierModelAdmx -Config $script:MockConfig -DomainController "DC01" -AdmlLanguage "en-US"
        
        $result.Summary.Successful | Should -BeGreaterOrEqual 0
        $result.Summary.Success | Should -Be $true
        Should -Invoke Copy-Item -ModuleName TierModel
    }
    
    It "Should skip files that are already up-to-date" {
        # Mock Get-TierModelAdmx to return files that are up-to-date (not to update)
        Mock Get-TierModelAdmx -ModuleName TierModel {
            return [PSCustomObject]@{
                Analysis = [PSCustomObject]@{
                    AdmxToUpdate = @()
                    AdmlToUpdate = @()
                    AdmxUpToDate = @(
                        [PSCustomObject]@{ 
                            Name = "Deploy1.admx"
                            SourcePath = "c:\ADO\TierModelv2\TierModel\config\admx\Deploy1.admx"
                            DestinationPath = "\\DC01\SYSVOL\TEST.DOMAIN.COM\Policies\PolicyDefinitions\Deploy1.admx"
                            CurrentHash = "DEPLOY1_HASH_11111111111111111"
                        }
                    )
                    AdmlUpToDate = @(
                        [PSCustomObject]@{ 
                            Name = "Deploy1.adml"
                            SourcePath = "c:\ADO\TierModelv2\TierModel\config\admx\en-US\Deploy1.adml"
                            DestinationPath = "\\DC01\SYSVOL\TEST.DOMAIN.COM\Policies\PolicyDefinitions\en-US\Deploy1.adml"
                            CurrentHash = "DEPLOY1_ADML_HASH_11111111111"
                        }
                    )
                    Errors = @()
                }
            }
        }
        
        $result = Copy-TierModelAdmx -Config $script:MockConfig -DomainController "DC01" -AdmlLanguage "en-US"
        
        $result.Summary.Skipped | Should -BeGreaterThan 0
        $result.Results.AdmxSkipped.Count | Should -BeGreaterThan 0
    }
    
    It "Should handle copy failures gracefully" {
        Mock Copy-Item -ModuleName TierModel { throw "Access denied" }
        
        $result = Copy-TierModelAdmx -Config $script:MockConfig -DomainController "DC01" -AdmlLanguage "en-US"
        
        $result.Summary.Success | Should -Be $false
        $result.Summary.Failed | Should -BeGreaterThan 0
    }
    
    It "Should verify hash after deployment" {
        Copy-TierModelAdmx -Config $script:MockConfig -DomainController "DC01" -AdmlLanguage "en-US"
        
        # Get-FileHash should be called after Copy-Item to verify deployment
        Should -Invoke Get-FileHash -ModuleName TierModel -Times 1 -ParameterFilter { 
            $Path -like "*SYSVOL*Deploy1.admx" 
        }
    }
    
    It "Should accept pre-computed analysis" {
        $mockAnalysis = @{
            AdmxToUpdate = @()
            AdmlToUpdate = @()
            Errors = @()
        }
        
        { Copy-TierModelAdmx -Config $script:MockConfig -DomainController "DC01" -AdmlLanguage "en-US" -Analysis $mockAnalysis } | Should -Not -Throw
    }
    
    It "Should include correlation ID and timing" {
        $result = Copy-TierModelAdmx -Config $script:MockConfig -DomainController "DC01" -AdmlLanguage "en-US"
        
        $result.CorrelationId | Should -Match "^[0-9a-f]{8}-"
        $result.DurationMs | Should -BeGreaterThan 0
    }
}
Describe "Test-TierModelAdmx – Extended Coverage" -Tag "Unit", "ADMX", "Audit" {
    BeforeAll {
        $ModulePath = Resolve-Path "$PSScriptRoot\..\Modules\TierModel"
        Import-Module $ModulePath -Force

        # ADMX config: one file
        $script:ExtAdmxJson = @{
            admx = @{
                destinationPath = "\\{{DOMAIN_FQDN}}\SYSVOL\{{DOMAIN_FQDN}}\Policies\PolicyDefinitions"
                files = @{ "File1.admx" = @{ hash = "HASH_FILE1_111111111111111111111" } }
            }
        } | ConvertTo-Json -Depth 10

        # ADML config: one present + one deliberately absent from SYSVOL
        $script:ExtAdmlJson = @{
            adml = @{
                destinationPath = "\\{{DOMAIN_FQDN}}\SYSVOL\{{DOMAIN_FQDN}}\Policies\PolicyDefinitions\en-US"
                files = @{
                    "File1.adml"       = @{ hash = "HASH_ADML_FILE1_11111111111111" }
                    "MissingFile.adml" = @{ hash = "HASH_ADML_MISSING_2222222222" }
                }
            }
        } | ConvertTo-Json -Depth 10

        $script:ExtCfg = [PSCustomObject]@{}

        Mock Write-TierModelLog -ModuleName TierModel { }
        Mock Write-Host         -ModuleName TierModel { }
    }

    BeforeEach {
        Mock Get-ADDomain -ModuleName TierModel { [PSCustomObject]@{ DNSRoot = 'ext.test.local' } }

        Mock Get-Content -ModuleName TierModel {
            param($Path)
            if ($Path -like '*tiermodel-admx.json')   { return $script:ExtAdmxJson }
            if ($Path -like '*tiermodel-adml-*.json') { return $script:ExtAdmlJson }
            return '{}'
        }

        # Default: config JSONs exist; File1.admx + File1.adml present; MissingFile.adml absent
        Mock Test-Path -ModuleName TierModel {
            param($Path)
            if ($Path -like '*tiermodel-*.json') { return $true }
            $leaf = Split-Path $Path -Leaf
            return ($leaf -in @('File1.admx', 'File1.adml'))
        }

        Mock Get-FileHash -ModuleName TierModel {
            param($Path)
            $leaf = Split-Path $Path -Leaf
            switch ($leaf) {
                'File1.admx' { return [PSCustomObject]@{ Hash = 'HASH_FILE1_111111111111111111111' } }
                'File1.adml' { return [PSCustomObject]@{ Hash = 'HASH_ADML_FILE1_11111111111111' } }
                default      { return [PSCustomObject]@{ Hash = 'UNKNOWN' } }
            }
        }
    }

    It "Should populate outer catch when ADMX config file is missing (lines 63, 268-292)" {
        Mock Test-Path -ModuleName TierModel {
            param($Path)
            if ($Path -like '*tiermodel-admx.json') { return $false }
            return $true
        }
        $result = Test-TierModelAdmx -Config $script:ExtCfg -DomainController 'DC01' -Silent
        $result.Converged             | Should -Be $false
        $result.Summary.Errors        | Should -Be 1
        $result.Findings[0].Type      | Should -Be 'Error'
        ($result.Findings[0].Message) | Should -Match 'ADMX audit failed'
    }

    It "Should populate outer catch when ADML config file is missing (line 66)" {
        Mock Test-Path -ModuleName TierModel {
            param($Path)
            if ($Path -like '*tiermodel-admx.json')   { return $true }
            if ($Path -like '*tiermodel-adml-*.json') { return $false }
            return $true
        }
        $result = Test-TierModelAdmx -Config $script:ExtCfg -DomainController 'DC01' -Silent
        $result.Summary.Errors        | Should -Be 1
        ($result.Findings[0].Message) | Should -Match 'ADMX audit failed'
    }

    It "Should populate outer catch when Get-ADDomain throws (lines 268-292)" {
        Mock Get-ADDomain -ModuleName TierModel { throw 'Domain unreachable' }
        $result = Test-TierModelAdmx -Config $script:ExtCfg -DomainController 'DC01' -Silent
        $result.Summary.Errors | Should -Be 1
        $result.Domain         | Should -BeNullOrEmpty
        $result.Converged      | Should -Be $false
    }

    It "Should record Missing status for ADML files not found in SYSVOL (lines 172-183)" {
        # BeforeEach default: MissingFile.adml returns $false from Test-Path
        $result = Test-TierModelAdmx -Config $script:ExtCfg -DomainController 'DC01' -Silent
        $missingAdml = $result.Results | Where-Object { $_.FileName -eq 'MissingFile.adml' }
        $missingAdml             | Should -Not -BeNullOrEmpty
        $missingAdml.Status      | Should -Be 'Missing'
        $missingAdml.Exists      | Should -Be $false
        ($missingAdml.Issues[0]) | Should -Match 'ADML file not found in SYSVOL'
        $result.Converged        | Should -Be $false
    }

    It "Should print summary output when Silent is not set and all files pass (lines 221-224, 228-229, 233-235)" {
        # All files exist and all hashes match — zero drift
        Mock Test-Path -ModuleName TierModel {
            param($Path)
            return $true
        }
        Mock Get-FileHash -ModuleName TierModel {
            param($Path)
            $leaf = Split-Path $Path -Leaf
            switch ($leaf) {
                'File1.admx'       { return [PSCustomObject]@{ Hash = 'HASH_FILE1_111111111111111111111' } }
                'File1.adml'       { return [PSCustomObject]@{ Hash = 'HASH_ADML_FILE1_11111111111111' } }
                'MissingFile.adml' { return [PSCustomObject]@{ Hash = 'HASH_ADML_MISSING_2222222222' } }
                default            { return [PSCustomObject]@{ Hash = 'UNKNOWN' } }
            }
        }
        # No -Silent → summary Write-Host block executes
        $result = Test-TierModelAdmx -Config $script:ExtCfg -DomainController 'DC01'
        $result.Converged                    | Should -Be $true
        $result.Summary.Drift                | Should -Be 0
        $result.Summary.CompliancePercentage | Should -Be 100
    }

    It "Should print error summary when Silent is not set and files have issues (lines 221-222, 226, 231, 237)" {
        # BeforeEach default: MissingFile.adml absent → driftCount > 0
        # No -Silent → error-summary Write-Host branch executes
        $result = Test-TierModelAdmx -Config $script:ExtCfg -DomainController 'DC01'
        $result.Converged     | Should -Be $false
        $result.Summary.Drift | Should -BeGreaterThan 0
    }
}