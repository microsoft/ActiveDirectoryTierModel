Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:ModuleRoot = Join-Path $PSScriptRoot '..' 'Modules' 'TierModel'
    $script:ManifestPath = Join-Path $script:ModuleRoot 'TierModel.psd1'
    $script:ModulePath = Join-Path $script:ModuleRoot 'TierModel.psm1'
    $script:PublicPath = Join-Path $script:ModuleRoot 'public'
}

Describe 'TierModel Module Manifest' -Tag 'Unit', 'Manifest' {
    
    Context 'Manifest File Structure' {
        It 'Manifest file exists' {
            Test-Path $script:ManifestPath | Should -BeTrue
        }
        
        It 'Module script file exists' {
            Test-Path $script:ModulePath | Should -BeTrue
        }
        
        It 'Public functions directory exists' {
            Test-Path $script:PublicPath | Should -BeTrue
        }
        
        It 'Manifest is valid PowerShell data file' {
            { Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop } | Should -Not -Throw
        }
    }
    
    Context 'Manifest Metadata' {
        BeforeAll {
            $script:Manifest = Import-PowerShellDataFile -Path $script:ManifestPath
        }
        
        It 'Has valid module version' {
            $script:Manifest.ModuleVersion | Should -Not -BeNullOrEmpty
            $script:Manifest.ModuleVersion | Should -Match '^\d+\.\d+\.\d+$'
        }
        
        It 'Has current version 1.2.2' {
            $script:Manifest.ModuleVersion | Should -Be '1.2.2'
        }
        
        It 'Has valid GUID' {
            $script:Manifest.GUID | Should -Not -BeNullOrEmpty
            { [System.Guid]::Parse($script:Manifest.GUID) } | Should -Not -Throw
        }
        
        It 'Has consistent GUID' {
            $script:Manifest.GUID | Should -Be 'b6a7c9f8-5e5d-4c7a-9b9e-2e2e9a4f6d10'
        }
        
        It 'Has root module specified' {
            $script:Manifest.RootModule | Should -Be 'TierModel.psm1'
        }
        
        It 'Has author specified' {
            $script:Manifest.Author | Should -Not -BeNullOrEmpty
        }
        
        It 'Has description' {
            $script:Manifest.Description | Should -Not -BeNullOrEmpty
            $script:Manifest.Description.Length | Should -BeGreaterThan 20
        }
        
        It 'Has PowerShell version requirement' {
            $script:Manifest.PowerShellVersion | Should -Not -BeNullOrEmpty
        }
        
        It 'Requires PowerShell 7.0 or higher' {
            [version]$script:Manifest.PowerShellVersion | Should -BeGreaterOrEqual ([version]'7.0')
        }
    }
    
    Context 'Function Exports Declaration' {
        BeforeAll {
            $script:Manifest = Import-PowerShellDataFile -Path $script:ManifestPath
            $script:DeclaredFunctions = $script:Manifest.FunctionsToExport
        }
        
        It 'Has functions to export declared' {
            $script:DeclaredFunctions | Should -Not -BeNullOrEmpty
        }
        
        It 'Exports meaningful number of functions' {
            $script:DeclaredFunctions.Count | Should -BeGreaterThan 30
        }
        
        It 'All declared functions follow naming convention' {
            $invalidNames = $script:DeclaredFunctions | Where-Object { 
                $_ -notmatch '^(Get|Set|New|Test|Copy|Import|Resolve|Clear|Update|Write)-(TierModel|DomainSpecificGuid)' 
            }
            $invalidNames | Should -BeNullOrEmpty
        }
        
        It 'Contains core prerequisite function' {
            $script:DeclaredFunctions | Should -Contain 'Test-TierModelPrerequisites'
        }
        
        It 'Contains core configuration function' {
            $script:DeclaredFunctions | Should -Contain 'Get-TierModelConfig'
        }
        
        It 'Contains OU functions' {
            $script:DeclaredFunctions | Should -Contain 'Get-TierModelOu'
            $script:DeclaredFunctions | Should -Contain 'New-TierModelOu'
            $script:DeclaredFunctions | Should -Contain 'Test-TierModelOu'
        }
        
        It 'Contains Group functions including Fd variant' {
            $script:DeclaredFunctions | Should -Contain 'Get-TierModelGroup'
            $script:DeclaredFunctions | Should -Contain 'Get-TierModelGroupFd'
            $script:DeclaredFunctions | Should -Contain 'New-TierModelGroup'
            $script:DeclaredFunctions | Should -Contain 'Test-TierModelGroup'
        }
        
        It 'Contains User functions including Fd variant' {
            $script:DeclaredFunctions | Should -Contain 'Get-TierModelUser'
            $script:DeclaredFunctions | Should -Contain 'Get-TierModelUserFd'
            $script:DeclaredFunctions | Should -Contain 'New-TierModelUser'
            $script:DeclaredFunctions | Should -Contain 'Test-TierModelUser'
        }
        
        It 'Contains OU ACL functions including Fd variant' {
            $script:DeclaredFunctions | Should -Contain 'Get-TierModelOuAcl'
            $script:DeclaredFunctions | Should -Contain 'Get-TierModelOuAclFd'
            $script:DeclaredFunctions | Should -Contain 'New-TierModelOuAcl'
            $script:DeclaredFunctions | Should -Contain 'Test-TierModelOuAcl'
        }
        
        It 'Contains MSA ACL functions including Fd variant' {
            $script:DeclaredFunctions | Should -Contain 'Get-TierModelMsaAcl'
            $script:DeclaredFunctions | Should -Contain 'Get-TierModelMsaAclFd'
            $script:DeclaredFunctions | Should -Contain 'New-TierModelMsaAcl'
            $script:DeclaredFunctions | Should -Contain 'Test-TierModelMsaAcl'
        }
        
        It 'Contains gMSA ACL functions including Fd variant' {
            $script:DeclaredFunctions | Should -Contain 'Get-TierModelGmsaAcl'
            $script:DeclaredFunctions | Should -Contain 'Get-TierModelGmsaAclFd'
            $script:DeclaredFunctions | Should -Contain 'New-TierModelGmsaAcl'
            $script:DeclaredFunctions | Should -Contain 'Test-TierModelGmsaAcl'
        }
        
        It 'Contains dMSA ACL functions including Fd variant' {
            $script:DeclaredFunctions | Should -Contain 'Get-TierModelDmsaAcl'
            $script:DeclaredFunctions | Should -Contain 'Get-TierModelDmsaAclFd'
            $script:DeclaredFunctions | Should -Contain 'New-TierModelDmsaAcl'
            $script:DeclaredFunctions | Should -Contain 'Test-TierModelDmsaAcl'
        }
        
        It 'Contains GPO functions including Fd variant' {
            $script:DeclaredFunctions | Should -Contain 'Get-TierModelGpo'
            $script:DeclaredFunctions | Should -Contain 'Get-TierModelGpoFd'
            $script:DeclaredFunctions | Should -Contain 'New-TierModelGpo'
            $script:DeclaredFunctions | Should -Contain 'Import-TierModelGpo'
        }
        
        It 'Contains GPO Link functions including Fd variant' {
            $script:DeclaredFunctions | Should -Contain 'Get-TierModelGPOLink'
            $script:DeclaredFunctions | Should -Contain 'Get-TierModelGpoLinkFd'
            $script:DeclaredFunctions | Should -Contain 'New-TierModelGPOLink'
        }
        
        It 'Contains ADMX functions' {
            $script:DeclaredFunctions | Should -Contain 'Get-TierModelAdmx'
            $script:DeclaredFunctions | Should -Contain 'Copy-TierModelAdmx'
            $script:DeclaredFunctions | Should -Contain 'Test-TierModelAdmx'
        }
        
        It 'Contains resolution helper functions' {
            $script:DeclaredFunctions | Should -Contain 'Resolve-TierModelPrincipalSid'
            $script:DeclaredFunctions | Should -Contain 'Resolve-TierModelDomainDN'
            $script:DeclaredFunctions | Should -Contain 'Resolve-TierModelPlaceholder'
            $script:DeclaredFunctions | Should -Contain 'Resolve-TierModelOuPath'
            $script:DeclaredFunctions | Should -Contain 'Resolve-TierModelGuid'
        }
        
        It 'Contains logging function' {
            $script:DeclaredFunctions | Should -Contain 'Write-TierModelLog'
        }
    }
    
    Context 'Actual Public Functions vs Manifest' {
        BeforeAll {
            $script:Manifest = Import-PowerShellDataFile -Path $script:ManifestPath
            $script:DeclaredFunctions = $script:Manifest.FunctionsToExport | Sort-Object
            
            # Get actual function files from public folder
            $script:PublicFiles = Get-ChildItem -Path $script:PublicPath -Filter '*.ps1' | 
                Where-Object { $_.Name -notlike '*.old' }
            
            # Extract function names from filenames (remove .ps1 extension)
            $script:ActualFunctions = $script:PublicFiles | 
                ForEach-Object { $_.BaseName }
            
            # Add functions defined inline in TierModel.psm1 (not in separate files)
            $psmPath = Join-Path (Split-Path $script:ManifestPath) 'TierModel.psm1'
            $psmContent = Get-Content $psmPath -Raw
            $inlineFunctions = @()
            if ($psmContent -match 'function Get-TierModel[\s\{]') { $inlineFunctions += 'Get-TierModel' }
            if ($psmContent -match 'function Get-TierModelPlan[\s\{]') { $inlineFunctions += 'Get-TierModelPlan' }
            if ($psmContent -match 'function Test-TierModelConfig[\s\{]') { $inlineFunctions += 'Test-TierModelConfig' }
            
            # Combine public files and inline functions
            $script:ActualFunctions = ($script:ActualFunctions + $inlineFunctions) | Sort-Object
        }
        
        It 'Public folder contains function files' {
            $script:PublicFiles.Count | Should -BeGreaterThan 30
        }
        
        It 'Number of declared functions matches number of public function files' {
            $script:DeclaredFunctions.Count | Should -Be $script:ActualFunctions.Count `
                -Because "Every public function (in public/ or inline in .psm1) should be declared in FunctionsToExport"
        }
        
        It 'All public function files are declared in manifest' {
            $undeclared = $script:ActualFunctions | Where-Object { $script:DeclaredFunctions -notcontains $_ }
            
            if ($undeclared) {
                $undeclaredList = $undeclared -join ', '
                $undeclared | Should -BeNullOrEmpty `
                    -Because "These functions exist in public/ or .psm1 but are not in FunctionsToExport: $undeclaredList"
            }
        }
        
        It 'All declared functions have corresponding files' {
            $missingFiles = $script:DeclaredFunctions | Where-Object { $script:ActualFunctions -notcontains $_ }
            
            if ($missingFiles) {
                $missingList = $missingFiles -join ', '
                $missingFiles | Should -BeNullOrEmpty `
                    -Because "These functions are declared in FunctionsToExport but missing from public/ and .psm1: $missingList"
            }
        }
        
        It 'Declared functions list matches actual functions list exactly' {
            Compare-Object -ReferenceObject $script:DeclaredFunctions -DifferenceObject $script:ActualFunctions |
                Should -BeNullOrEmpty
        }
    }
    
    Context 'Module Import and Export' {
        BeforeAll {
            # Remove module if already loaded
            Remove-Module TierModel -Force -ErrorAction SilentlyContinue
            
            # Import the module
            Import-Module $script:ManifestPath -Force -ErrorAction Stop
            
            $script:ExportedCommands = (Get-Module TierModel).ExportedCommands.Keys | Sort-Object
        }
        
        AfterAll {
            Remove-Module TierModel -Force -ErrorAction SilentlyContinue
        }
        
        It 'Module imports successfully' {
            Get-Module TierModel | Should -Not -BeNullOrEmpty
        }
        
        It 'Module exports functions' {
            $script:ExportedCommands.Count | Should -BeGreaterThan 0
        }
        
        It 'All declared functions are actually exported' {
            $script:Manifest = Import-PowerShellDataFile -Path $script:ManifestPath
            $notExported = $script:Manifest.FunctionsToExport | 
                Where-Object { $script:ExportedCommands -notcontains $_ }
            
            if ($notExported) {
                $notExportedList = $notExported -join ', '
                $notExported | Should -BeNullOrEmpty `
                    -Because "These functions are declared but not actually exported: $notExportedList"
            }
        }
        
        It 'Core functions are accessible after import' {
            Get-Command -Module TierModel -Name 'Test-TierModelPrerequisites' -ErrorAction Stop | 
                Should -Not -BeNullOrEmpty
            Get-Command -Module TierModel -Name 'Get-TierModelConfig' -ErrorAction Stop | 
                Should -Not -BeNullOrEmpty
            Get-Command -Module TierModel -Name 'Write-TierModelLog' -ErrorAction Stop | 
                Should -Not -BeNullOrEmpty
        }
        
        It 'OU functions are accessible' {
            Get-Command -Module TierModel -Name 'Get-TierModelOu' | Should -Not -BeNullOrEmpty
            Get-Command -Module TierModel -Name 'New-TierModelOu' | Should -Not -BeNullOrEmpty
        }
        
        It 'Group Fd function is accessible' {
            Get-Command -Module TierModel -Name 'Get-TierModelGroupFd' | Should -Not -BeNullOrEmpty
        }
        
        It 'User Fd function is accessible' {
            Get-Command -Module TierModel -Name 'Get-TierModelUserFd' | Should -Not -BeNullOrEmpty
        }
        
        It 'OU ACL Fd function is accessible' {
            Get-Command -Module TierModel -Name 'Get-TierModelOuAclFd' | Should -Not -BeNullOrEmpty
        }
        
        It 'MSA ACL functions are accessible' {
            Get-Command -Module TierModel -Name 'Get-TierModelMsaAcl'   | Should -Not -BeNullOrEmpty
            Get-Command -Module TierModel -Name 'Get-TierModelMsaAclFd' | Should -Not -BeNullOrEmpty
            Get-Command -Module TierModel -Name 'New-TierModelMsaAcl'   | Should -Not -BeNullOrEmpty
            Get-Command -Module TierModel -Name 'Test-TierModelMsaAcl'  | Should -Not -BeNullOrEmpty
        }
        
        It 'gMSA ACL functions are accessible' {
            Get-Command -Module TierModel -Name 'Get-TierModelGmsaAcl'   | Should -Not -BeNullOrEmpty
            Get-Command -Module TierModel -Name 'Get-TierModelGmsaAclFd' | Should -Not -BeNullOrEmpty
            Get-Command -Module TierModel -Name 'New-TierModelGmsaAcl'   | Should -Not -BeNullOrEmpty
            Get-Command -Module TierModel -Name 'Test-TierModelGmsaAcl'  | Should -Not -BeNullOrEmpty
        }
        
        It 'dMSA ACL functions are accessible' {
            Get-Command -Module TierModel -Name 'Get-TierModelDmsaAcl'   | Should -Not -BeNullOrEmpty
            Get-Command -Module TierModel -Name 'Get-TierModelDmsaAclFd' | Should -Not -BeNullOrEmpty
            Get-Command -Module TierModel -Name 'New-TierModelDmsaAcl'   | Should -Not -BeNullOrEmpty
            Get-Command -Module TierModel -Name 'Test-TierModelDmsaAcl'  | Should -Not -BeNullOrEmpty
        }
        
        It 'GPO Fd function is accessible' {
            Get-Command -Module TierModel -Name 'Get-TierModelGpoFd' | Should -Not -BeNullOrEmpty
        }
        
        It 'GPO Link Fd function is accessible' {
            Get-Command -Module TierModel -Name 'Get-TierModelGpoLinkFd' | Should -Not -BeNullOrEmpty
        }
    }
    
    Context 'Module Dependencies' {
        BeforeAll {
            $script:Manifest = Import-PowerShellDataFile -Path $script:ManifestPath
        }
        
        It 'Has RequiredModules property defined' {
            $script:Manifest.ContainsKey('RequiredModules') | Should -BeTrue
        }
        
        It 'ActiveDirectory module is loaded dynamically (not required)' {
            # Module should NOT require ActiveDirectory as hard dependency
            # This allows testing without RSAT installed
            if ($script:Manifest.RequiredModules) {
                $script:Manifest.RequiredModules | 
                    Where-Object { $_ -match 'ActiveDirectory' } | 
                    Should -BeNullOrEmpty -Because "ActiveDirectory should be loaded dynamically when needed"
            }
        }
        
        It 'GroupPolicy module is loaded dynamically (not required)' {
            # Module should NOT require GroupPolicy as hard dependency
            if ($script:Manifest.RequiredModules) {
                $script:Manifest.RequiredModules | 
                    Where-Object { $_ -match 'GroupPolicy' } | 
                    Should -BeNullOrEmpty -Because "GroupPolicy should be loaded dynamically when needed"
            }
        }
    }
    
    Context 'Module Metadata and Tags' {
        BeforeAll {
            $script:Manifest = Import-PowerShellDataFile -Path $script:ManifestPath
        }
        
        It 'Has PrivateData section' {
            $script:Manifest.PrivateData | Should -Not -BeNullOrEmpty
        }
        
        It 'Has PSData section' {
            $script:Manifest.PrivateData.PSData | Should -Not -BeNullOrEmpty
        }
        
        It 'Has descriptive tags' {
            $script:Manifest.PrivateData.PSData.Tags | Should -Not -BeNullOrEmpty
            $script:Manifest.PrivateData.PSData.Tags.Count | Should -BeGreaterThan 3
        }
        
        It 'Contains ActiveDirectory tag' {
            $script:Manifest.PrivateData.PSData.Tags | Should -Contain 'ActiveDirectory'
        }
        
        It 'Contains TierModel tag' {
            $script:Manifest.PrivateData.PSData.Tags | Should -Contain 'TierModel'
        }
        
        It 'Has release notes' {
            $script:Manifest.PrivateData.PSData.ReleaseNotes | Should -Not -BeNullOrEmpty
        }
        
        It 'Release notes mention current version' {
            $script:Manifest.PrivateData.PSData.ReleaseNotes | Should -Match '1\.1\.0'
        }
    }
}

Describe 'TierModel Module Loading Behavior' -Tag 'Unit', 'Manifest' {
    
    Context 'Module Re-import' {
        It 'Can be removed and re-imported multiple times' {
            # First import
            Import-Module $script:ManifestPath -Force
            Get-Module TierModel | Should -Not -BeNullOrEmpty
            
            # Remove
            Remove-Module TierModel -Force
            Get-Module TierModel | Should -BeNullOrEmpty
            
            # Re-import
            Import-Module $script:ManifestPath -Force
            Get-Module TierModel | Should -Not -BeNullOrEmpty
            
            # Cleanup
            Remove-Module TierModel -Force
        }
    }
    
    Context 'Module Version Consistency' {
        BeforeAll {
            Import-Module $script:ManifestPath -Force
            $script:LoadedModule = Get-Module TierModel
            $script:ManifestData = Import-PowerShellDataFile -Path $script:ManifestPath
        }
        
        AfterAll {
            Remove-Module TierModel -Force -ErrorAction SilentlyContinue
        }
        
        It 'Loaded module version matches manifest version' {
            $script:LoadedModule.Version.ToString() | Should -Be $script:ManifestData.ModuleVersion
        }
        
        It 'Loaded module GUID matches manifest GUID' {
            $script:LoadedModule.Guid.ToString() | Should -Be $script:ManifestData.GUID
        }
        
        It 'Loaded module name is correct' {
            $script:LoadedModule.Name | Should -Be 'TierModel'
        }
    }
}
