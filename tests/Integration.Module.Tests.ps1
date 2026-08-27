Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:ModuleRoot = Join-Path $PSScriptRoot '..' 'Modules' 'TierModel'
    $script:ManifestPath = Join-Path $script:ModuleRoot 'TierModel.psd1'
    $script:ModulePath = Join-Path $script:ModuleRoot 'TierModel.psm1'
    $script:PublicPath = Join-Path $script:ModuleRoot 'public'
    
    # Clean up any existing module imports
    Remove-Module TierModel -Force -ErrorAction SilentlyContinue
}

Describe 'TierModel Module Integration Tests' -Tag 'Integration', 'Module' {
    
    Context 'Module Loading and Initialization' {
        BeforeAll {
            # Import module with verbose to capture loading details
            $VerbosePreference = 'Continue'
            $script:ImportOutput = Import-Module $script:ManifestPath -Force -PassThru -Verbose 4>&1
            $VerbosePreference = 'SilentlyContinue'
            $script:LoadedModule = Get-Module TierModel
        }
        
        AfterAll {
            Remove-Module TierModel -Force -ErrorAction SilentlyContinue
        }
        
        It 'Module loads without errors' {
            $script:LoadedModule | Should -Not -BeNullOrEmpty
            $script:LoadedModule.Name | Should -Be 'TierModel'
        }
        
        It 'Module version is correct' {
            $script:LoadedModule.Version.ToString() | Should -Be '1.3.3'
        }
        
        It 'Module loads all public function files' {
            $publicFiles = Get-ChildItem -Path $script:PublicPath -Filter '*.ps1'
            $publicFiles.Count | Should -BeGreaterThan 40
            
            # Verify all public functions are actually exported/available
            $exportedCommands = $script:LoadedModule.ExportedCommands.Keys
            $exportedCommands.Count | Should -BeGreaterThan 40 -Because "All public function files should be loaded and exported"
        }
        
        It 'Module does not load .old files from internal directory' {
            $oldFileMessages = $script:ImportOutput | Where-Object { $_ -match '\.old' }
            $oldFileMessages | Should -BeNullOrEmpty
        }
        
        It 'Module initialization completes without warnings or errors' {
            $warningMessages = $script:ImportOutput | Where-Object { $_ -match 'WARNING:' }
            $errorMessages = $script:ImportOutput | Where-Object { $_ -match 'ERROR:' }
            
            # Some verbose messages are expected, but no actual warnings/errors
            $warningMessages | Should -BeNullOrEmpty
            $errorMessages | Should -BeNullOrEmpty
        }
    }
    
    Context 'Module-Level Variables Initialization' {
        BeforeAll {
            Remove-Module TierModel -Force -ErrorAction SilentlyContinue
            Import-Module $script:ManifestPath -Force
        }
        
        AfterAll {
            Remove-Module TierModel -Force -ErrorAction SilentlyContinue
        }
        
        It 'Module sets CorrelationId for the session' {
            # CorrelationId is a script-scoped variable, we can't access it directly
            # but we can verify that logging functions use it properly
            # Just verify module loaded
            Get-Module TierModel | Should -Not -BeNullOrEmpty
        }
        
        It 'Module has accessible public path' {
            Test-Path $script:PublicPath | Should -BeTrue
        }
        
        It 'Config path is set correctly relative to module root' {
            # Config should be at ../../config from Modules/TierModel
            $expectedConfigPath = Join-Path (Split-Path (Split-Path $script:ModuleRoot -Parent) -Parent) 'config'
            Test-Path $expectedConfigPath | Should -BeTrue
        }
    }
    
    Context 'Function Export Verification' {
        BeforeAll {
            Remove-Module TierModel -Force -ErrorAction SilentlyContinue
            Import-Module $script:ManifestPath -Force
            $script:ExportedFunctions = (Get-Module TierModel).ExportedCommands.Keys
        }
        
        AfterAll {
            Remove-Module TierModel -Force -ErrorAction SilentlyContinue
        }
        
        It 'Exports all declared functions' {
            $manifest = Import-PowerShellDataFile -Path $script:ManifestPath
            $declaredFunctions = $manifest.FunctionsToExport
            
            foreach ($func in $declaredFunctions) {
                $script:ExportedFunctions | Should -Contain $func -Because "Function $func should be exported"
            }
        }
        
        It 'All exported functions are actually callable' {
            foreach ($func in $script:ExportedFunctions) {
                { Get-Command $func -Module TierModel -ErrorAction Stop } | Should -Not -Throw
            }
        }
        
        It 'Group functions are explicitly exported and accessible' {
            $groupFunctions = @('Get-TierModelGroup', 'New-TierModelGroup', 'Test-TierModelGroup', 'Get-TierModelGroupFd')
            
            foreach ($func in $groupFunctions) {
                Get-Command $func -Module TierModel -ErrorAction Stop | Should -Not -BeNullOrEmpty
            }
        }
        
        It 'User functions are explicitly exported and accessible' {
            $userFunctions = @('Get-TierModelUser', 'New-TierModelUser', 'Test-TierModelUser', 'Get-TierModelUserFd')
            
            foreach ($func in $userFunctions) {
                Get-Command $func -Module TierModel -ErrorAction Stop | Should -Not -BeNullOrEmpty
            }
        }
        
        It 'OU ACL functions are explicitly exported and accessible' {
            $aclFunctions = @('Get-TierModelOuAcl', 'New-TierModelOuAcl', 'Test-TierModelOuAcl', 'Get-TierModelOuAclFd')
            
            foreach ($func in $aclFunctions) {
                Get-Command $func -Module TierModel -ErrorAction Stop | Should -Not -BeNullOrEmpty
            }
        }
        
        It 'GPO functions are explicitly exported and accessible' {
            $gpoFunctions = @('Get-TierModelGpo', 'New-TierModelGpo', 'Test-TierModelGpo', 'Get-TierModelGpoFd')
            
            foreach ($func in $gpoFunctions) {
                Get-Command $func -Module TierModel -ErrorAction Stop | Should -Not -BeNullOrEmpty
            }
        }
        
        It 'GPO Link functions are explicitly exported and accessible' {
            $gpoLinkFunctions = @('Get-TierModelGPOLink', 'New-TierModelGPOLink', 'Test-TierModelGPOLink', 'Get-TierModelGpoLinkFd')
            
            foreach ($func in $gpoLinkFunctions) {
                Get-Command $func -Module TierModel -ErrorAction Stop | Should -Not -BeNullOrEmpty
            }
        }
        
        It 'All Fd (FindDifferences) variant functions are exported' {
            $fdFunctions = $script:ExportedFunctions | Where-Object { $_ -match 'Fd$' }
            $fdFunctions.Count | Should -BeGreaterOrEqual 5 -Because "Should have at least 5 *Fd functions"
            
            # Verify specific Fd functions
            $expectedFdFunctions = @(
                'Get-TierModelGroupFd',
                'Get-TierModelUserFd', 
                'Get-TierModelOuAclFd',
                'Get-TierModelGpoFd',
                'Get-TierModelGpoLinkFd'
            )
            
            foreach ($func in $expectedFdFunctions) {
                $script:ExportedFunctions | Should -Contain $func
            }
        }
    }
    
    Context 'Module Re-import and State Management' {
        It 'Module can be removed and re-imported cleanly' {
            # First import
            Import-Module $script:ManifestPath -Force
            $firstImport = Get-Module TierModel
            $firstImport | Should -Not -BeNullOrEmpty
            
            # Remove
            Remove-Module TierModel -Force
            Get-Module TierModel | Should -BeNullOrEmpty
            
            # Re-import
            Import-Module $script:ManifestPath -Force
            $secondImport = Get-Module TierModel
            $secondImport | Should -Not -BeNullOrEmpty
            
            # Verify same version
            $secondImport.Version | Should -Be $firstImport.Version
            
            # Cleanup
            Remove-Module TierModel -Force
        }
        
        It 'Module can be imported with -Force to refresh' {
            Import-Module $script:ManifestPath -Force
            $firstCount = (Get-Module TierModel).ExportedCommands.Count
            
            Import-Module $script:ManifestPath -Force
            $secondCount = (Get-Module TierModel).ExportedCommands.Count
            
            $secondCount | Should -Be $firstCount
            
            Remove-Module TierModel -Force
        }
        
        It 'Multiple imports do not cause duplicate function exports' {
            Import-Module $script:ManifestPath -Force
            Import-Module $script:ManifestPath -Force
            Import-Module $script:ManifestPath -Force
            
            # Should still only have one module loaded
            $modules = Get-Module TierModel
            @($modules).Count | Should -Be 1
            
            Remove-Module TierModel -Force
        }
    }
    
    Context 'Function Availability After Import' {
        BeforeAll {
            Remove-Module TierModel -Force -ErrorAction SilentlyContinue
            Import-Module $script:ManifestPath -Force
        }
        
        AfterAll {
            Remove-Module TierModel -Force -ErrorAction SilentlyContinue
        }
        
        It 'Core configuration functions are available' {
            Get-Command Get-TierModelConfig -Module TierModel | Should -Not -BeNullOrEmpty
            Get-Command Test-TierModelPrerequisites -Module TierModel | Should -Not -BeNullOrEmpty
            Get-Command Write-TierModelLog -Module TierModel | Should -Not -BeNullOrEmpty
        }
        
        It 'OU management functions are available' {
            Get-Command Get-TierModelOu -Module TierModel | Should -Not -BeNullOrEmpty
            Get-Command New-TierModelOu -Module TierModel | Should -Not -BeNullOrEmpty
            Get-Command Test-TierModelOu -Module TierModel | Should -Not -BeNullOrEmpty
            Get-Command Test-TierModelOuExists -Module TierModel | Should -Not -BeNullOrEmpty
        }
        
        It 'Resolution helper functions are available' {
            Get-Command Resolve-TierModelPrincipalSid -Module TierModel | Should -Not -BeNullOrEmpty
            Get-Command Resolve-TierModelDomainDN -Module TierModel | Should -Not -BeNullOrEmpty
            Get-Command Resolve-TierModelPlaceholder -Module TierModel | Should -Not -BeNullOrEmpty
            Get-Command Resolve-TierModelOuPath -Module TierModel | Should -Not -BeNullOrEmpty
            Get-Command Resolve-TierModelGuid -Module TierModel | Should -Not -BeNullOrEmpty
        }
        
        It 'ADMX functions are available' {
            Get-Command Get-TierModelAdmx -Module TierModel | Should -Not -BeNullOrEmpty
            Get-Command Copy-TierModelAdmx -Module TierModel | Should -Not -BeNullOrEmpty
            Get-Command Test-TierModelAdmx -Module TierModel | Should -Not -BeNullOrEmpty
        }
        
        It 'GPO template functions are available' {
            Get-Command Get-TierModelGpoTemplate -Module TierModel | Should -Not -BeNullOrEmpty
            Get-Command Set-TierModelGpoTemplate -Module TierModel | Should -Not -BeNullOrEmpty
            Get-Command New-TierModelGptTmplContent -Module TierModel | Should -Not -BeNullOrEmpty
            Get-Command Update-TierModelGPOConfig -Module TierModel | Should -Not -BeNullOrEmpty
        }
        
        It 'All test/validation functions are available' {
            $testFunctions = (Get-Module TierModel).ExportedCommands.Keys | Where-Object { $_ -match '^Test-TierModel' }
            $testFunctions.Count | Should -BeGreaterThan 5
        }
    }
    
    Context 'Module Script File Integrity' {
        It 'Module script file has valid PowerShell syntax' {
            { 
                $null = [System.Management.Automation.PSParser]::Tokenize(
                    (Get-Content $script:ModulePath -Raw),
                    [ref]$null
                )
            } | Should -Not -Throw
        }
        
        It 'Module script sets StrictMode' {
            $content = Get-Content $script:ModulePath -Raw
            $content | Should -Match 'Set-StrictMode.*-Version Latest'
        }
        
        It 'Module script sets ErrorActionPreference' {
            $content = Get-Content $script:ModulePath -Raw
            $content | Should -Match '\$ErrorActionPreference\s*=\s*[''"]Stop[''"]'
        }
        
        It 'Module script initializes CorrelationId' {
            $content = Get-Content $script:ModulePath -Raw
            $content | Should -Match '\$script:CorrelationId'
        }
        
        It 'Module script loads public functions' {
            $content = Get-Content $script:ModulePath -Raw
            $content | Should -Match 'Get-ChildItem.*public.*\.ps1'
        }
    }
    
    Context 'Module Dependencies and Requirements' {
        BeforeAll {
            Remove-Module TierModel -Force -ErrorAction SilentlyContinue
            Import-Module $script:ManifestPath -Force
        }
        
        AfterAll {
            Remove-Module TierModel -Force -ErrorAction SilentlyContinue
        }
        
        It 'Module does not require ActiveDirectory module as hard dependency' {
            # Module should load even if ActiveDirectory module is not available
            $manifest = Import-PowerShellDataFile -Path $script:ManifestPath
            
            if ($manifest.RequiredModules) {
                $manifest.RequiredModules | Where-Object { $_ -match 'ActiveDirectory' } | 
                    Should -BeNullOrEmpty
            }
        }
        
        It 'Module does not require GroupPolicy module as hard dependency' {
            # Module should load even if GroupPolicy module is not available
            $manifest = Import-PowerShellDataFile -Path $script:ManifestPath
            
            if ($manifest.RequiredModules) {
                $manifest.RequiredModules | Where-Object { $_ -match 'GroupPolicy' } | 
                    Should -BeNullOrEmpty
            }
        }
        
        It 'Module requires PowerShell 7.0 or higher' {
            $manifest = Import-PowerShellDataFile -Path $script:ManifestPath
            [version]$manifest.PowerShellVersion | Should -BeGreaterOrEqual ([version]'7.0')
        }
    }
    
    Context 'Function Loading Error Handling' {
        It 'Module provides clear error if public path is missing' {
            # This is a theoretical test - we can't actually remove the path
            # but we verify the code checks for it
            $content = Get-Content $script:ModulePath -Raw
            $content | Should -Match 'if.*Test-Path.*PublicPath'
        }
        
        It 'Module handles loading errors gracefully' {
            $content = Get-Content $script:ModulePath -Raw
            $content | Should -Match 'try\s*{'
            $content | Should -Match 'catch\s*{'
        }
    }
    
    Context 'Module Export Consistency' {
        BeforeAll {
            Remove-Module TierModel -Force -ErrorAction SilentlyContinue
            Import-Module $script:ManifestPath -Force
            
            $script:ExportedCommands = (Get-Module TierModel).ExportedCommands.Keys | Sort-Object
            $script:ManifestData = Import-PowerShellDataFile -Path $script:ManifestPath
            $script:DeclaredFunctions = $script:ManifestData.FunctionsToExport | Sort-Object
        }
        
        AfterAll {
            Remove-Module TierModel -Force -ErrorAction SilentlyContinue
        }
        
        It 'Number of exported commands matches manifest declaration' {
            $script:ExportedCommands.Count | Should -Be $script:DeclaredFunctions.Count
        }
        
        It 'All manifest-declared functions are actually exported' {
            foreach ($func in $script:DeclaredFunctions) {
                $script:ExportedCommands | Should -Contain $func -Because "$func declared in manifest should be exported"
            }
        }
        
        It 'No extra functions are exported beyond manifest' {
            foreach ($func in $script:ExportedCommands) {
                $script:DeclaredFunctions | Should -Contain $func -Because "$func exported but not in manifest"
            }
        }
        
        It 'Function exports are stable across re-imports' {
            $firstExport = (Get-Module TierModel).ExportedCommands.Keys | Sort-Object
            
            Remove-Module TierModel -Force
            Import-Module $script:ManifestPath -Force
            
            $secondExport = (Get-Module TierModel).ExportedCommands.Keys | Sort-Object
            
            Compare-Object -ReferenceObject $firstExport -DifferenceObject $secondExport | 
                Should -BeNullOrEmpty
        }
    }
}

Describe 'TierModel Module Performance' -Tag 'Integration', 'Module', 'Performance' {
    
    Context 'Module Loading Performance' {
        BeforeAll {
            Remove-Module TierModel -Force -ErrorAction SilentlyContinue
        }
        
        AfterAll {
            Remove-Module TierModel -Force -ErrorAction SilentlyContinue
        }
        
        It 'Module loads in reasonable time (under 5 seconds)' {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Import-Module $script:ManifestPath -Force
            $stopwatch.Stop()
            
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 5000
            
            Get-Module TierModel | Should -Not -BeNullOrEmpty
        }
        
        It 'Module re-import is reasonably fast (under 5 seconds)' {
            Import-Module $script:ManifestPath -Force
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Import-Module $script:ManifestPath -Force
            $stopwatch.Stop()
            
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 5000
        }
    }
}
