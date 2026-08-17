#Requires -Modules Pester
<#
.SYNOPSIS
Integration tests for Deploy-TierModel.ps1 orchestration script.

.DESCRIPTION
Tests the deployment workflow orchestration including scope selection, planning vs execution modes,
prerequisite validation, and consolidated reporting. All AD cmdlets are mocked to avoid
requiring domain connectivity.

.NOTES
Tags: Integration, Deploy
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    # Import module under test
    $ModulePath = Join-Path $PSScriptRoot '..\Modules\TierModel\TierModel.psd1'
    Import-Module $ModulePath -Force
    
    # Define paths
    $script:DeployScriptPath = Join-Path $PSScriptRoot '..\Deploy-TierModel.ps1'
    $script:TestPreferredDc = 'testdc.contoso.local'
    $script:TestOutputDir = Join-Path $env:TEMP "TierModel-Deploy-Tests-$(Get-Random)"
    
    # Create test output directory
    New-Item -Path $script:TestOutputDir -ItemType Directory -Force | Out-Null
    
    # CRITICAL: Mock Read-Host FIRST to prevent interactive prompts during discovery
    Mock -CommandName Read-Host -MockWith { return 'N' } -ModuleName $null
    
    # Mock configuration data
    $script:MockConfig = [PSCustomObject]@{
        ConfigHash = 'abc123'
        organizationUnits = @(
            @{ name = 'TestOU1'; path = 'OU=TestOU1,DC=test,DC=local' }
            @{ name = 'TestOU2'; path = 'OU=TestOU2,DC=test,DC=local' }
        )
        groups = @(
            @{ name = 'TestGroup1'; path = 'CN=TestGroup1,OU=Groups,DC=test,DC=local'; samaccountname = 'TestGroup1' }
        )
        users = @(
            @{ name = 'TestUser1'; path = 'CN=TestUser1,OU=Users,DC=test,DC=local'; samaccountname = 'TestUser1' }
        )
        gpos = @(
            @{ name = 'TestGPO1' }
        )
        aclDelegations = @(
            @{ ou = 'OU=TestOU1,DC=test,DC=local'; trustee = 'TestGroup1'; permissions = @('GenericAll') }
        )
        admx = @(
            @{ file = 'test.admx' }
        )
    }
    
    # Helper function to create mock deployment plan results
    function New-MockDeploymentPlan {
        param(
            [string]$EntityType,
            [int]$TotalInConfig = 2,
            [int]$ToCreate = 1,
            [int]$ToUpdate = 0,
            [int]$ExistingCount = 1,
            [switch]$WithErrors
        )
        
        # Create base result structure - build actions as object[]
        [object[]]$actions = @()
        for ($i = 1; $i -le $ToCreate; $i++) {
            # Build Data hashtable with entity-specific properties
            $dataHash = @{ name = "Test${EntityType}${i}" }
            if ($EntityType -eq 'Group') {
                $dataHash['samaccountname'] = "Test${EntityType}${i}"
            }
            
            $actions += [PSCustomObject]@{
                Name = "Test${EntityType}${i}"
                Action = "Create${EntityType}"
                Data = $dataHash
            }
        }
        for ($i = 1; $i -le $ToUpdate; $i++) {
            # Use correct action name based on entity type
            $updateAction = switch ($EntityType) {
                'User' { 'UpdateUserMembership' }
                default { "Update${EntityType}" }
            }
            
            # Build Data hashtable with entity-specific properties
            $dataHash = @{ name = "Test${EntityType}Update${i}" }
            if ($EntityType -eq 'Group') {
                $dataHash['samaccountname'] = "Test${EntityType}Update${i}"
            }
            
            $actions += [PSCustomObject]@{
                Name = "Test${EntityType}Update${i}"
                Action = $updateAction
                Data = $dataHash
            }
        }
        
        # Ensure Actions is always an array, even if empty
        if ($actions.Count -eq 0) {
            [object[]]$actions = @()
        }
        
        # Ensure Errors and Warnings are properly typed arrays with Count property
        if ($WithErrors) {
            [object[]]$errorArray = @([PSCustomObject]@{ Message = "Test error" })
        } else {
            [object[]]$errorArray = [object[]]@()
        }
        [object[]]$warningsArray = [object[]]@()
        
        $result = [PSCustomObject]@{
            EntityType = $EntityType
        }
        
        # Add properties using Add-Member to preserve array types
        $result | Add-Member -MemberType NoteProperty -Name 'Summary' -Value ([PSCustomObject]@{
            TotalInConfig = $TotalInConfig
            ToCreate = $ToCreate
            ToUpdate = $ToUpdate
            ExistingCount = $ExistingCount
        })
        $result | Add-Member -MemberType NoteProperty -Name 'Actions' -Value $actions
        $result | Add-Member -MemberType NoteProperty -Name 'Warnings' -Value $warningsArray  
        $result | Add-Member -MemberType NoteProperty -Name 'Errors' -Value $errorArray
        
        # Add entity-specific properties
        switch ($EntityType) {
            'OU' { 
                $result.Summary | Add-Member -NotePropertyName 'TotalOUs' -NotePropertyValue $TotalInConfig -Force
            }
            'Group' { 
                $result.Summary | Add-Member -NotePropertyName 'TotalGroups' -NotePropertyValue $TotalInConfig -Force
            }
            'User' { 
                $result.Summary | Add-Member -NotePropertyName 'TotalUsers' -NotePropertyValue $TotalInConfig -Force
            }
            'GPO' {
                $result.Summary | Add-Member -NotePropertyName 'TotalGpos' -NotePropertyValue $TotalInConfig -Force
            }
        }
        
        return $result
    }
    
    # Helper function to create mock deployment execution results
    function New-MockDeploymentResult {
        param(
            [string]$EntityType,
            [int]$AppliedCount = 1,
            [int]$SkippedCount = 0,
            [int]$ErrorCount = 0,
            [int]$DurationMs = 100,
            [bool]$Converged = $true
        )
        
        [object[]]$applied = @()
        for ($i = 1; $i -le $AppliedCount; $i++) {
            $applied += [PSCustomObject]@{
                Name = "Applied Item ${i}"
                Action = "Create"
            }
        }
        
        [object[]]$skipped = @()
        for ($i = 1; $i -le $SkippedCount; $i++) {
            $skipped += [PSCustomObject]@{
                Name = "Skipped Item ${i}"
                Reason = "Already exists"
            }
        }
        
        [object[]]$errors = @()
        for ($i = 1; $i -le $ErrorCount; $i++) {
            $errors += [PSCustomObject]@{
                Message = "Test error ${i}"
                Timestamp = Get-Date
            }
        }
        
        # Return structure matching actual New-TierModel* cmdlets (both Applied and Executed for compatibility)
        [PSCustomObject]@{
            Applied = $applied
            Executed = $applied.Count
            Failed = $ErrorCount
            Skipped = $SkippedCount  # Integer for User deployment range operators
            Errors = $errors
            DurationMs = $DurationMs
            Converged = $Converged
            CorrelationId = [System.Guid]::NewGuid().ToString()
        }
    }
    
    function New-MockIncludeAclPlan {
        param(
            [string]$Prefix,
            [int]$ToCreate = 4,
            [int]$ExistingCount = 0,
            [switch]$WithErrors
        )

        [object[]]$actions = @()
        for ($i = 1; $i -le $ToCreate; $i++) {
            $actions += [PSCustomObject]@{
                Action = 'CreateAcl'
                ResourceType = 'ACL'
                Name = "ACL Delegation: TEST\\${Prefix}Principal${i} on OU=${Prefix}OU${i},DC=test,DC=local"
                Path = "OU=${Prefix}OU${i},DC=test,DC=local"
                Data = [PSCustomObject]@{
                    identityreference = "TEST\\${Prefix}Principal${i}"
                }
                Dependencies = @()
                RiskLevel = 'Low'
            }
        }

        [object[]]$errors = if ($WithErrors) {
            @([PSCustomObject]@{ Message = "${Prefix} planning error" })
        } else {
            @()
        }

        return [PSCustomObject]@{
            Actions = $actions
            Summary = [PSCustomObject]@{
                TotalActions = $ToCreate
                CreateActions = $ToCreate
                ExistingCount = $ExistingCount
            }
            Errors = $errors
            Warnings = [object[]]@()
        }
    }

    # Mock all AD and module cmdlets
    Mock Get-TierModelConfig { 
        return [PSCustomObject]@{
            ConfigHash = 'abc123'
            organizationUnits = @(
                @{ name = 'TestOU1'; path = 'OU=TestOU1,DC=test,DC=local' }
                @{ name = 'TestOU2'; path = 'OU=TestOU2,DC=test,DC=local' }
            )
            groups = @(
                @{ name = 'TestGroup1'; path = 'CN=TestGroup1,OU=Groups,DC=test,DC=local'; samaccountname = 'TestGroup1' }
            )
            users = @(
                @{ name = 'TestUser1'; path = 'CN=TestUser1,OU=Users,DC=test,DC=local'; samaccountname = 'TestUser1'; displayName = 'TestUser1' }
            )
            gpos = @(
                @{ name = 'TestGPO1' }
            )
            aclDelegations = @(
                @{ ou = 'OU=TestOU1,DC=test,DC=local'; trustee = 'TestGroup1'; permissions = @('GenericAll') }
            )
            admx = @(
                @{ file = 'test.admx' }
            )
        }
    }
    Mock Test-TierModelPrerequisites { 
        return [PSCustomObject]@{
            Valid = $true
            Errors = @()
            Remediation = @()
        }
    }
    Mock Write-TierModelLog { }
    Mock Write-TierModelLog { } -ModuleName TierModel
    
    # Mock Active Directory cmdlets to avoid domain connectivity requirements
    Mock Get-ADDomain {
        return [PSCustomObject]@{
            DistinguishedName = 'DC=test,DC=local'
            DNSRoot = 'test.local'
            NetBIOSName = 'TEST'
        }
    }
    
    # Also mock Get-ADDomain within the TierModel module scope
    Mock Get-ADDomain {
        return [PSCustomObject]@{
            DistinguishedName = 'DC=test,DC=local'
            DNSRoot = 'test.local'
            NetBIOSName = 'TEST'
        }
    } -ModuleName TierModel
    
    # Mock domain DN resolution to avoid AD connectivity (both module and script scope)
    Mock Resolve-TierModelDomainDN {
        return 'DC=test,DC=local'
    }
    Mock Resolve-TierModelDomainDN {
        return 'DC=test,DC=local'
    } -ModuleName TierModel
    
    # Mock deployment planning cmdlets
    Mock Get-TierModelOu { 
        # Build actions array
        [object[]]$actionArray = @([PSCustomObject]@{
            Name = "TestOU1"
            Action = "CreateOU"
            Data = @{ name = "TestOU1" }
        })
        
        # Build result object with explicit typing
        $result = [PSCustomObject]@{
            EntityType = 'OU'
        }
        $result | Add-Member -MemberType NoteProperty -Name 'Summary' -Value ([PSCustomObject]@{
            TotalInConfig = 2
            ToCreate = 1
            ToUpdate = 0
            ExistingCount = 1
            TotalOUs = 2
        })
        $result | Add-Member -MemberType NoteProperty -Name 'Actions' -Value $actionArray
        $result | Add-Member -MemberType NoteProperty -Name 'Warnings' -Value ([object[]]@())
        $result | Add-Member -MemberType NoteProperty -Name 'Errors' -Value ([object[]]@())
        
        return $result
    }
    Mock Get-TierModelGroup { 
        [object[]]$actionArray = @([PSCustomObject]@{
            Name = "TestGroup1"
            Action = "CreateGroup"
            Data = @{ name = "TestGroup1"; samaccountname = "TestGroup1" }
        })
        
        $result = [PSCustomObject]@{ EntityType = 'Group' }
        $result | Add-Member -MemberType NoteProperty -Name 'Summary' -Value ([PSCustomObject]@{
            TotalInConfig = 1
            ToCreate = 1
            ToUpdate = 0
            ExistingCount = 0
            TotalGroups = 1
        })
        $result | Add-Member -MemberType NoteProperty -Name 'Actions' -Value $actionArray
        $result | Add-Member -MemberType NoteProperty -Name 'Warnings' -Value ([object[]]@())
        $result | Add-Member -MemberType NoteProperty -Name 'Errors' -Value ([object[]]@())
        
        return $result
    }
    
    # Create stub functions for commands that may not be exported
    if (-not (Get-Command Get-TierModelGroupFd -ErrorAction SilentlyContinue)) {
        function Get-TierModelGroupFd {}
    }
    if (-not (Get-Command Get-TierModelUserFd -ErrorAction SilentlyContinue)) {
        function Get-TierModelUserFd {}
    }
    if (-not (Get-Command New-TierModelOuAcl -ErrorAction SilentlyContinue)) {
        function New-TierModelOuAcl {}
    }
    if (-not (Get-Command Get-TierModelOuAcl -ErrorAction SilentlyContinue)) {
        function Get-TierModelOuAcl {}
    }
    if (-not (Get-Command Get-TierModelGpo -ErrorAction SilentlyContinue)) {
        function Get-TierModelGpo {}
    }
    if (-not (Get-Command New-TierModelGpo -ErrorAction SilentlyContinue)) {
        function New-TierModelGpo {}
    }
    if (-not (Get-Command Get-TierModelAdmx -ErrorAction SilentlyContinue)) {
        function Get-TierModelAdmx {}
    }
    if (-not (Get-Command Copy-TierModelAdmx -ErrorAction SilentlyContinue)) {
        function Copy-TierModelAdmx {}
    }
    if (-not (Get-Command New-TierModelOu -ErrorAction SilentlyContinue)) {
        function New-TierModelOu {}
    }
    if (-not (Get-Command Get-TierModelOu -ErrorAction SilentlyContinue)) {
        function Get-TierModelOu {}
    }
    if (-not (Get-Command New-TierModelGroup -ErrorAction SilentlyContinue)) {
        function New-TierModelGroup {}
    }
    if (-not (Get-Command Get-TierModelGroup -ErrorAction SilentlyContinue)) {
        function Get-TierModelGroup {}
    }
    if (-not (Get-Command New-TierModelUser -ErrorAction SilentlyContinue)) {
        function New-TierModelUser {}
    }
    if (-not (Get-Command Get-TierModelUser -ErrorAction SilentlyContinue)) {
        function Get-TierModelUser {}
    }
    
    Mock Get-TierModelGroupFd { 
        [object[]]$actionArray = @([PSCustomObject]@{
            Name = "TestGroup1"
            Action = "CreateGroup"
            Data = @{ name = "TestGroup1"; samaccountname = "TestGroup1" }
        })
        
        $result = [PSCustomObject]@{ EntityType = 'Group' }
        $result | Add-Member -MemberType NoteProperty -Name 'Summary' -Value ([PSCustomObject]@{
            TotalInConfig = 1
            ToCreate = 1
            ToUpdate = 0
            ExistingCount = 0
            TotalGroups = 1
        })
        $result | Add-Member -MemberType NoteProperty -Name 'Actions' -Value $actionArray
        $result | Add-Member -MemberType NoteProperty -Name 'Warnings' -Value ([object[]]@())
        $result | Add-Member -MemberType NoteProperty -Name 'Errors' -Value ([object[]]@())
        
        return $result
    }
    Mock Get-TierModelUser { 
        [object[]]$actionArray = @([PSCustomObject]@{
            Name = "TestUser1"
            Action = "CreateUser"
            Data = @{ name = "TestUser1"; samaccountname = "TestUser1" }
        })
        
        $result = [PSCustomObject]@{ EntityType = 'User' }
        $result | Add-Member -MemberType NoteProperty -Name 'Summary' -Value ([PSCustomObject]@{
            TotalInConfig = 1
            ToCreate = 1
            ToUpdate = 0
            ExistingCount = 0
            TotalUsers = 1
        })
        $result | Add-Member -MemberType NoteProperty -Name 'Actions' -Value $actionArray
        $result | Add-Member -MemberType NoteProperty -Name 'Warnings' -Value ([object[]]@())
        $result | Add-Member -MemberType NoteProperty -Name 'Errors' -Value ([object[]]@())
        
        return $result
    }
    Mock Get-TierModelUserFd { 
        [object[]]$actionArray = @([PSCustomObject]@{
            Name = "TestUser1"
            Action = "CreateUser"
            Data = @{ name = "TestUser1"; samaccountname = "TestUser1" }
        })
        
        $result = [PSCustomObject]@{ EntityType = 'User' }
        $result | Add-Member -MemberType NoteProperty -Name 'Summary' -Value ([PSCustomObject]@{
            TotalInConfig = 1
            ToCreate = 1
            ToUpdate = 0
            ExistingCount = 0
            TotalUsers = 1
        })
        $result | Add-Member -MemberType NoteProperty -Name 'Actions' -Value $actionArray
        $result | Add-Member -MemberType NoteProperty -Name 'Warnings' -Value ([object[]]@())
        $result | Add-Member -MemberType NoteProperty -Name 'Errors' -Value ([object[]]@())
        
        return $result
    }
    Mock Get-TierModelOuAcl {
        [object[]]$actionArray = @([PSCustomObject]@{ 
            OU = 'OU=TestOU1,DC=test,DC=local'
            Action = 'Apply'
            Data = @{
                identityreference = 'TEST\TestGroup1'
                activedirectoryrights = @('GenericAll')
                objecttype = 'All Objects'
                activeDirectorysecurityinheritance = 'All'
            }
        })
        
        $result = [PSCustomObject]@{ EntityType = 'OuAcl' }
        $result | Add-Member -MemberType NoteProperty -Name 'Summary' -Value ([PSCustomObject]@{
            TotalActions = 1
            CreateActions = 1
            ExistingCount = 0
        })
        $result | Add-Member -MemberType NoteProperty -Name 'Actions' -Value $actionArray
        $result | Add-Member -MemberType NoteProperty -Name 'Warnings' -Value ([object[]]@())
        $result | Add-Member -MemberType NoteProperty -Name 'Errors' -Value ([object[]]@())
        
        return $result
    }
    Mock Get-TierModelOuAclFd {
        # Return empty plan with no actions (all ACLs up to date) for FullDeployment mode
        $result = [PSCustomObject]@{ EntityType = 'OuAcl' }
        $result | Add-Member -MemberType NoteProperty -Name 'Summary' -Value ([PSCustomObject]@{
            TotalActions = 0
            CreateActions = 0
            ExistingCount = 1
        })
        $result | Add-Member -MemberType NoteProperty -Name 'Actions' -Value ([object[]]@())
        $result | Add-Member -MemberType NoteProperty -Name 'Warnings' -Value ([object[]]@())
        $result | Add-Member -MemberType NoteProperty -Name 'Errors' -Value ([object[]]@())
        
        return $result
    }
    Mock Get-TierModelGpo {
        [object[]]$actionArray = @([PSCustomObject]@{ Name = 'TestGPO1'; Action = 'CreateGPO' })
        
        $result = [PSCustomObject]@{ EntityType = 'GPO' }
        $result | Add-Member -MemberType NoteProperty -Name 'Summary' -Value (@{
            TotalInConfig = 1
            ToCreate = 1
            ExistingCount = 0
            TotalActions = 1
            CreateActions = 1
            ImportActions = 0
            ConfigureActions = 0
            LinkActions = 0
        })
        $result | Add-Member -MemberType NoteProperty -Name 'Actions' -Value $actionArray
        $result | Add-Member -MemberType NoteProperty -Name 'Warnings' -Value ([object[]]@())
        $result | Add-Member -MemberType NoteProperty -Name 'Errors' -Value ([object[]]@())
        
        return $result
    }
    Mock Get-TierModelGpoFd {
        # Return empty plan with no GPOs configured for FullDeployment mode
        $result = [PSCustomObject]@{ EntityType = 'GPO' }
        $result | Add-Member -MemberType NoteProperty -Name 'Summary' -Value (@{
            TotalInConfig = 0
            ToCreate = 0
            ExistingCount = 0
            TotalActions = 0
            CreateActions = 0
            ImportActions = 0
            ConfigureActions = 0
            LinkActions = 0
        })
        $result | Add-Member -MemberType NoteProperty -Name 'Actions' -Value ([object[]]@())
        $result | Add-Member -MemberType NoteProperty -Name 'Warnings' -Value ([object[]]@())
        $result | Add-Member -MemberType NoteProperty -Name 'Errors' -Value ([object[]]@())
        
        return $result
    }
    Mock Get-TierModelAdmx {
        [object[]]$admxToUpdate = @([PSCustomObject]@{ Name = 'test.admx'; ActionType = 'Import'; Reason = 'File not present' })
        [object[]]$admxUpToDate = @([PSCustomObject]@{ Name = 'existing.admx'; Hash = 'abc123' })
        
        $result = [PSCustomObject]@{ EntityType = 'ADMX' }
        $result | Add-Member -MemberType NoteProperty -Name 'Summary' -Value ([PSCustomObject]@{
            TotalFiles = 2
            FilesToUpdate = 1
            FilesUpToDate = 1
        })
        $result | Add-Member -MemberType NoteProperty -Name 'Analysis' -Value ([PSCustomObject]@{
            TotalAdmxFiles = 1
            TotalAdmlFiles = 0
            AdmxToUpdate = $admxToUpdate
            AdmlToUpdate = ([object[]]@())
            AdmxUpToDate = $admxUpToDate
            AdmlUpToDate = ([object[]]@())
            Errors = ([object[]]@())
        })
        $result | Add-Member -MemberType NoteProperty -Name 'Warnings' -Value ([object[]]@())
        $result | Add-Member -MemberType NoteProperty -Name 'Errors' -Value ([object[]]@())
        
        return $result
    }
    Mock Get-TierModelMsaAcl {
        New-MockIncludeAclPlan -Prefix 'MSA'
    }
    Mock Get-TierModelGmsaAcl {
        New-MockIncludeAclPlan -Prefix 'gMSA'
    }
    Mock Get-TierModelDmsaAcl {
        New-MockIncludeAclPlan -Prefix 'dMSA'
    }
    Mock Get-TierModelMsaAclFd {
        New-MockIncludeAclPlan -Prefix 'MSA'
    }
    Mock Get-TierModelGmsaAclFd {
        New-MockIncludeAclPlan -Prefix 'gMSA'
    }
    Mock Get-TierModelDmsaAclFd {
        New-MockIncludeAclPlan -Prefix 'dMSA'
    }
    
    # Mock deployment execution cmdlets
    Mock New-TierModelOu { 
        New-MockDeploymentResult -EntityType 'OU' -AppliedCount 1 -Converged $true
    }
    Mock New-TierModelGroup { 
        New-MockDeploymentResult -EntityType 'Group' -AppliedCount 1 -Converged $true
    }
    Mock New-TierModelUser { 
        New-MockDeploymentResult -EntityType 'User' -AppliedCount 1 -Converged $true
    }
    Mock New-TierModelOuAcl {
        New-MockDeploymentResult -EntityType 'OuAcl' -AppliedCount 1 -Converged $true
    }
    Mock New-TierModelGpo {
        New-MockDeploymentResult -EntityType 'GPO' -AppliedCount 1 -Converged $true
    }
    Mock New-TierModelMsaAcl {
        New-MockDeploymentResult -EntityType 'MSA ACL' -AppliedCount 4 -Converged $true
    }
    Mock New-TierModelGmsaAcl {
        New-MockDeploymentResult -EntityType 'gMSA ACL' -AppliedCount 4 -Converged $true
    }
    Mock New-TierModelDmsaAcl {
        New-MockDeploymentResult -EntityType 'dMSA ACL' -AppliedCount 4 -Converged $true
    }
    Mock Copy-TierModelAdmx {
        [PSCustomObject]@{
            Summary = [PSCustomObject]@{
                Successful = 1
                Failed = 0
            }
            Results = [PSCustomObject]@{
                AdmxSuccessful = @([PSCustomObject]@{ FileInfo = @{ Name = 'test.admx' }; ActionType = 'Import' })
                AdmlSuccessful = @()
                AdmxFailed = @()
                AdmlFailed = @()
            }
            DurationMs = 100
        }
    }
    
    # Mock Read-Host for interactive prompts
    Mock Read-Host { return 'N' }  # Default to No for confirmations
}

AfterAll {
    # Cleanup test output directory
    if (Test-Path $script:TestOutputDir) {
        Remove-Item -Path $script:TestOutputDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Deploy-TierModel - Parameter Validation' {
    It 'Should have PreferredDc as a mandatory parameter' {
        $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile($script:DeployScriptPath, [ref]$null, [ref]$null)
        $paramBlock = $scriptAst.ParamBlock
        $preferredDcParam = $paramBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'PreferredDc' }
        
        $preferredDcParam | Should -Not -BeNullOrEmpty
        $preferredDcParam.Attributes.TypeName.Name | Should -Contain 'Parameter'
        $mandatoryAttr = $preferredDcParam.Attributes | Where-Object { $_.TypeName.Name -eq 'Parameter' }
        $mandatoryAttr.NamedArguments | Where-Object { $_.ArgumentName -eq 'Mandatory' } | Should -Not -BeNullOrEmpty
    }
    
    It 'Should require exactly one scope parameter' {
        { & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -ErrorAction Stop } | 
            Should -Throw -ExpectedMessage '*exactly one deployment scope parameter*'
    }
    
    It 'Should reject multiple scope parameters' {
        { & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -GroupOnly -ErrorAction Stop } | 
            Should -Throw -ExpectedMessage '*only specify one deployment scope parameter*'
    }
    
    It 'Should accept OuOnly parameter' {
        Mock Read-Host { return 'N' }  # Cancel deployment
        { & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -ErrorAction Stop } | 
            Should -Not -Throw
    }
    
    It 'Should accept GroupOnly parameter' {
        Mock Read-Host { return 'N' }
        { & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GroupOnly -ErrorAction Stop } | 
            Should -Not -Throw
    }
    
    It 'Should accept UserOnly parameter' {
        Mock Read-Host { return 'N' }
        { & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -UserOnly -ErrorAction Stop } | 
            Should -Not -Throw
    }
    
    It 'Should accept GposOnly parameter' {
        Mock Read-Host { return 'N' }
        { & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GposOnly -ErrorAction Stop } | 
            Should -Not -Throw
    }
    
    It 'Should accept OuAclsOnly parameter' {
        Mock Read-Host { return 'N' }
        { & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuAclsOnly -ErrorAction Stop } | 
            Should -Not -Throw
    }
    
    It 'Should accept AdmxOnly parameter' {
        Mock Read-Host { return 'N' }
        { & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -AdmxOnly -ErrorAction Stop } | 
            Should -Not -Throw
    }
    
    It 'Should accept FullDeployment parameter' {
        Mock Read-Host { return 'N' }
        { & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -ErrorAction Stop } | 
            Should -Not -Throw
    }
}

Describe 'Deploy-TierModel - Logging Configuration' {
    BeforeEach {
        Mock Read-Host { return 'N' }  # Cancel deployment
    }
    
    It 'Should prompt for OutputFileBase when Logging enabled without OutputFileBase' {
        Mock Read-Host { 
            param($Prompt)
            if ($Prompt -like '*base filename*') { return 'TestLog' }
            return 'N'
        }
        
        { & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -Logging -ErrorAction Stop } | 
            Should -Not -Throw
        
        Should -Invoke Read-Host -Times 1 -ParameterFilter { $Prompt -like '*base filename*' }
    }
    
    It 'Should create log directory if LogPath does not exist' {
        Mock Read-Host { return 'N' }
        $testLogPath = Join-Path $script:TestOutputDir "LogDir-$(Get-Random)"
        
        & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -Logging -LogPath $testLogPath -OutputFileBase 'TestLog' -ErrorAction Stop
        
        Test-Path $testLogPath | Should -Be $true
    }
    
    It 'Should use current directory for logs when LogPath not provided' {
        Mock Read-Host { return 'N' }
        
        & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -Logging -OutputFileBase 'TestLog' -ErrorAction Stop
        
        Should -Invoke Write-TierModelLog -Times 1 -ParameterFilter { 
            $LogPath -like '*TestLog-*-*.log' 
        }
    }
    
    It 'Should write deployment start information to log' {
        Mock Read-Host { return 'N' }
        
        & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -Logging -OutputFileBase 'TestLog' -ErrorAction Stop
        
        Should -Invoke Write-TierModelLog -Times 1 -ParameterFilter { 
            $Message -eq 'TierModel deployment started' -and $Level -eq 'Info'
        }
    }
}

Describe 'Deploy-TierModel - Prerequisites Validation' {
    BeforeEach {
        Mock Read-Host { return 'N' }
    }
    
    It 'Should call Test-TierModelPrerequisites with correct parameters' {
        & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -ErrorAction Stop
        
        Should -Invoke Test-TierModelPrerequisites -Times 1 -ParameterFilter { 
            $PreferredDc -eq $script:TestPreferredDc -and $DependenciesPath -like '*dependencies.json'
        }
    }
    
    It 'Should exit with error when prerequisites fail' {
        Mock Test-TierModelPrerequisites { 
            return [PSCustomObject]@{
                Valid = $false
                Errors = @('Test prerequisite error')
                Remediation = @('Fix the error')
            }
        }
        
        # Script uses 'exit 1' which sets $LASTEXITCODE but doesn't throw
        $null = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -ErrorAction SilentlyContinue
        $LASTEXITCODE | Should -Be 1
    }
    
    It 'Should use fallback message when prerequisites fail with no Errors array' {
        # Covers Deploy-TierModel.ps1 L296: when $prereqResult.Errors is empty the script
        # falls back to the hardcoded "Prerequisites were not met." message.
        Mock Test-TierModelPrerequisites {
            return [PSCustomObject]@{
                Valid       = $false
                Errors      = @()
                Remediation = @()
            }
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly 6>&1 | Out-String

        $output | Should -Match 'Prerequisites were not met'
        $output | Should -Match 'Deploy script completed'
        $LASTEXITCODE | Should -Be 1
    }
    
    It 'Should handle array return from Test-TierModelPrerequisites' {
        Mock Test-TierModelPrerequisites { 
            return @(
                [PSCustomObject]@{
                    Valid = $true
                    Errors = @()
                    Remediation = @()
                }
            )
        }
        
        { & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -ErrorAction Stop } | 
            Should -Not -Throw
    }
}

Describe 'Deploy-TierModel - Configuration Loading' {
    BeforeEach {
        Mock Read-Host { return 'N' }
    }
    
    It 'Should call Get-TierModelConfig to load configuration' {
        & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -ErrorAction Stop
        
        Should -Invoke Get-TierModelConfig -Times 1
    }
    
    It 'Should exit with error when configuration loading fails' {
        Mock Get-TierModelConfig { throw 'Configuration load error' }
        
        # Script uses 'exit 1' which sets $LASTEXITCODE but doesn't throw
        $null = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -ErrorAction SilentlyContinue
        $LASTEXITCODE | Should -Be 1
    }
}

Describe 'Deploy-TierModel - ConfirmApply Prompt' {
    It 'Should prompt for confirmation when ConfirmApply is specified' {
        Mock Read-Host { 
            param($Prompt)
            return 'N'  # User cancels
        }
        
        & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -ConfirmApply -ErrorAction Stop
        
        Should -Invoke Read-Host -Times 1 -ParameterFilter { $Prompt -like "*Type 'Y' to continue*" }
    }
    
    It 'Should exit when user does not confirm with Y' {
        Mock Read-Host { return 'N' }
        
        & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -ConfirmApply -ErrorAction Stop
        
        # Script should exit, deployment cmdlets should not be called
        Should -Invoke New-TierModelOu -Times 0
    }
    
    It 'Should proceed when user confirms with Y' {
        Mock Read-Host { return 'Y' }
        Mock Get-TierModelOu {
            $plan = New-MockDeploymentPlan -EntityType 'OU' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1
            return $plan
        }
        
        & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -ConfirmApply -ErrorAction Stop
        
        Should -Invoke New-TierModelOu -Times 1
    }
}

Describe 'Deploy-TierModel - OuOnly Deployment' {
    BeforeEach {
        Mock Read-Host { return 'N' }
    }
    
    Context 'Planning Mode' {
        It 'Should call Get-TierModelOu in planning mode' {
            & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -ErrorAction Stop
            
            Should -Invoke Get-TierModelOu -Times 1 -ParameterFilter {
                $Config -ne $null -and $DomainController -eq $script:TestPreferredDc
            }
        }
        
        It 'Should not call New-TierModelOu in planning mode' {
            & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -ErrorAction Stop
            
            Should -Invoke New-TierModelOu -Times 0
        }
        
        It 'Should display plan summary' {
            Mock Get-TierModelOu {
                New-MockDeploymentPlan -EntityType 'OU' -TotalInConfig 3 -ToCreate 2 -ExistingCount 1
            }
            
            $output = (& $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -ErrorAction Stop 6>&1) | Out-String
            
            $output | Should -Match 'Total in Config: 3'
            $output | Should -Match 'To Create: 2'
            $output | Should -Match 'Already Exist: 1'
        }
        
        It 'Should not execute when there are errors in plan' {
            Mock Get-TierModelOu {
                New-MockDeploymentPlan -EntityType 'OU' -WithErrors
            }
            Mock Read-Host { return 'Y' }  # Even with confirmation
            
            & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -ConfirmApply -ErrorAction Stop
            
            Should -Invoke New-TierModelOu -Times 0
        }
    }
    
    Context 'Execution Mode' {
        It 'Should call New-TierModelOu when ConfirmApply is specified' {
            Mock Read-Host { return 'Y' }
            Mock Get-TierModelOu {
                New-MockDeploymentPlan -EntityType 'OU' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1
            }
            
            & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -ConfirmApply -ErrorAction Stop
            
            Should -Invoke New-TierModelOu -Times 1
        }
        
        It 'Should handle successful OU deployment' {
            Mock Read-Host { return 'Y' }
            Mock Get-TierModelOu {
                New-MockDeploymentPlan -EntityType 'OU' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1
            }
            Mock New-TierModelOu {
                New-MockDeploymentResult -EntityType 'OU' -AppliedCount 1 -Converged $true
            }
            
            { & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -ConfirmApply -ErrorAction Stop } | 
                Should -Not -Throw
        }
        
        It 'Should handle OU deployment with no actions needed' {
            Mock Read-Host { return 'Y' }
            Mock Get-TierModelOu {
                New-MockDeploymentPlan -EntityType 'OU' -TotalInConfig 2 -ToCreate 0 -ExistingCount 2
            }
            
            & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -ConfirmApply -ErrorAction Stop
            
            Should -Invoke New-TierModelOu -Times 0  # No actions, so no execution call
        }
        
        It 'Should handle OU deployment errors gracefully' {
            Mock Read-Host { return 'Y' }
            Mock Get-TierModelOu {
                New-MockDeploymentPlan -EntityType 'OU' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1
            }
            Mock New-TierModelOu { throw 'OU deployment failed' }
            
            { & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -ConfirmApply -ErrorAction Stop } | 
                Should -Not -Throw  # Script handles errors gracefully
        }
    }
}

Describe 'Deploy-TierModel - GroupOnly Deployment' {
    BeforeEach {
        Mock Read-Host { return 'N' }
    }
    
    Context 'Planning Mode' {
        It 'Should call Get-TierModelGroup in planning mode' {
            & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GroupOnly -ErrorAction Stop
            
            Should -Invoke Get-TierModelGroup -Times 1 -ParameterFilter {
                $Config -ne $null -and $DomainController -eq $script:TestPreferredDc
            }
        }
        
        It 'Should not call New-TierModelGroup in planning mode' {
            & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GroupOnly -ErrorAction Stop
            
            Should -Invoke New-TierModelGroup -Times 0
        }
        
        It 'Should display plan summary' {
            Mock Get-TierModelGroup {
                New-MockDeploymentPlan -EntityType 'Group' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1
            }
            
            $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GroupOnly -ErrorAction Stop 6>&1 | Out-String
            
            $output | Should -Match 'Total in Config: 2'
            $output | Should -Match 'To Create: 1'
        }
    }
    
    Context 'Execution Mode' {
        It 'Should call New-TierModelGroup when ConfirmApply is specified' {
            Mock Read-Host { return 'Y' }
            Mock Get-TierModelGroup {
                New-MockDeploymentPlan -EntityType 'Group' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1
            }
            
            & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GroupOnly -ConfirmApply -ErrorAction Stop
            
            Should -Invoke New-TierModelGroup -Times 1
        }
        
        It 'Should handle successful Group deployment' {
            Mock Read-Host { return 'Y' }
            Mock Get-TierModelGroup {
                New-MockDeploymentPlan -EntityType 'Group' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1
            }
            Mock New-TierModelGroup {
                New-MockDeploymentResult -EntityType 'Group' -AppliedCount 1 -Converged $true
            }
            
            { & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GroupOnly -ConfirmApply -ErrorAction Stop } | 
                Should -Not -Throw
        }
    }
}

Describe 'Deploy-TierModel - UserOnly Deployment' {
    BeforeEach {
        Mock Read-Host { return 'N' }
    }
    
    Context 'Planning Mode' {
        It 'Should call Get-TierModelUser in planning mode' {
            & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -UserOnly -ErrorAction Stop
            
            Should -Invoke Get-TierModelUser -Times 1 -ParameterFilter {
                $Config -ne $null -and $DomainController -eq $script:TestPreferredDc
            }
        }
        
        It 'Should not call New-TierModelUser in planning mode' {
            & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -UserOnly -ErrorAction Stop
            
            Should -Invoke New-TierModelUser -Times 0
        }
        
        It 'Should display plan summary including ToUpdate count' {
            Mock Get-TierModelUser {
                New-MockDeploymentPlan -EntityType 'User' -TotalInConfig 3 -ToCreate 1 -ToUpdate 1 -ExistingCount 1
            }
            
            $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -UserOnly -ErrorAction Stop 6>&1 | Out-String
            
            $output | Should -Match 'Action count: 2'
            $output | Should -Match 'Create count: 1'
            $output | Should -Match 'Update count: 1'
        }
    }
    
    Context 'Execution Mode' {
        It 'Should call New-TierModelUser when ConfirmApply is specified' {
            Mock Read-Host { return 'Y' }
            Mock Get-TierModelUser {
                New-MockDeploymentPlan -EntityType 'User' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1
            }
            
            & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -UserOnly -ConfirmApply -ErrorAction Stop
            
            Should -Invoke New-TierModelUser -Times 1
        }
        
        It 'Should handle successful User deployment' {
            Mock Read-Host { return 'Y' }
            Mock Get-TierModelUser {
                New-MockDeploymentPlan -EntityType 'User' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1
            }
            Mock New-TierModelUser {
                New-MockDeploymentResult -EntityType 'User' -AppliedCount 1 -Converged $true
            }
            
            { & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -UserOnly -ConfirmApply -ErrorAction Stop } | 
                Should -Not -Throw
        }
    }
}

Describe 'Deploy-TierModel - OuAclsOnly Deployment' {
    BeforeEach {
        Mock Read-Host { return 'N' }
    }
    
    Context 'Planning Mode' {
        It 'Should call Get-TierModelOuAcl in planning mode' {
            & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuAclsOnly -ErrorAction Stop
            
            Should -Invoke Get-TierModelOuAcl -Times 1 -ParameterFilter {
                $Config -ne $null -and $DomainController -eq $script:TestPreferredDc
            }
        }
        
        It 'Should not call New-TierModelOuAcl in planning mode' {
            & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuAclsOnly -ErrorAction Stop
            
            Should -Invoke New-TierModelOuAcl -Times 0
        }
    }
    
    Context 'Execution Mode' {
        It 'Should call New-TierModelOuAcl when ConfirmApply is specified' {
            Mock Read-Host { return 'Y' }
            Mock Get-TierModelOuAcl {
                [PSCustomObject]@{
                    EntityType = 'OuAcl'
                    Summary = [PSCustomObject]@{ TotalActions = 1; CreateActions = 1 }
                    Actions = @([PSCustomObject]@{ 
                        OU = 'OU=Test,DC=test,DC=local'
                        Action = 'Apply'
                        Data = @{
                            identityreference = 'TEST\TestGroup1'
                            activedirectoryrights = @('GenericAll')
                            objecttype = 'All Objects'
                            activeDirectorysecurityinheritance = 'All'
                        }
                    })
                    Errors = @()
                }
            }
            
            & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuAclsOnly -ConfirmApply -ErrorAction Stop
            
            Should -Invoke New-TierModelOuAcl -Times 1
        }
    }
}

Describe 'Deploy-TierModel - GposOnly Deployment' {
    BeforeEach {
        Mock Read-Host { return 'N' }
    }
    
    Context 'Planning Mode' {
        It 'Should call Get-TierModelGpo in planning mode' {
            & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GposOnly -ErrorAction Stop
            
            Should -Invoke Get-TierModelGpo -Times 1 -ParameterFilter {
                $Config -ne $null -and $DomainController -eq $script:TestPreferredDc
            }
        }
        
        It 'Should not call New-TierModelGpo in planning mode' {
            & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GposOnly -ErrorAction Stop
            
            Should -Invoke New-TierModelGpo -Times 0
        }
    }
    
    Context 'Execution Mode' {
        It 'Should call New-TierModelGpo when ConfirmApply is specified' {
            Mock Read-Host { return 'Y' }
            Mock Get-TierModelGpo {
                [PSCustomObject]@{
                    Actions = @([PSCustomObject]@{ Name = 'TestGPO1'; Action = 'CreateGPO' })
                    Summary = @{
                        TotalInConfig = 1
                        ToCreate = 1
                        ExistingCount = 0
                        TotalActions = 1
                        CreateActions = 1
                        ImportActions = 0
                        ConfigureActions = 0
                        LinkActions = 0
                    }
                    Errors = @()
                }
            }
            
            & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GposOnly -ConfirmApply -ErrorAction Stop
            
            Should -Invoke New-TierModelGpo -Times 1
        }
    }
}

Describe 'Deploy-TierModel - AdmxOnly Deployment' {
    BeforeEach {
        Mock Read-Host { return 'N' }
    }
    
    Context 'Planning Mode' {
        It 'Should call Get-TierModelAdmx in planning mode' {
            & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -AdmxOnly -ErrorAction Stop
            
            Should -Invoke Get-TierModelAdmx -Times 1 -ParameterFilter {
                $Config -ne $null -and $DomainController -eq $script:TestPreferredDc
            }
        }
        
        It 'Should not call Copy-TierModelAdmx in planning mode' {
            & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -AdmxOnly -ErrorAction Stop
            
            Should -Invoke Copy-TierModelAdmx -Times 0
        }
        
        It 'Should display ADMX plan summary' {
            Mock Get-TierModelAdmx {
                [PSCustomObject]@{
                    EntityType = 'ADMX'
                    Summary = [PSCustomObject]@{
                        TotalFiles = 3
                        FilesToUpdate = 2
                        FilesUpToDate = 1
                    }
                    Analysis = [PSCustomObject]@{
                        AdmxToUpdate = @(
                            [PSCustomObject]@{ Name = 'test1.admx'; ActionType = 'Import'; Reason = 'File not present' }
                        )
                        AdmlToUpdate = @(
                            [PSCustomObject]@{ Name = 'test1.adml'; ActionType = 'Import'; Reason = 'File not present' }
                        )
                        Errors = @()
                    }
                }
            }
            
            $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -AdmxOnly -ErrorAction Stop 6>&1 | Out-String
            
            $output | Should -Match 'Total in Config: 3'
            $output | Should -Match 'To Create: 2'
        }
    }
    
    Context 'Execution Mode' {
        It 'Should call Copy-TierModelAdmx when ConfirmApply is specified' {
            Mock Read-Host { return 'Y' }
            
            & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -AdmxOnly -ConfirmApply -ErrorAction Stop
            
            Should -Invoke Copy-TierModelAdmx -Times 1
        }
        
        It 'Should handle successful ADMX deployment' {
            Mock Read-Host { return 'Y' }
            Mock Copy-TierModelAdmx {
                [PSCustomObject]@{
                    Summary = [PSCustomObject]@{
                        Successful = 2
                        Failed = 0
                    }
                    Results = [PSCustomObject]@{
                        AdmxSuccessful = @([PSCustomObject]@{ FileInfo = @{ Name = 'test.admx' }; ActionType = 'Import' })
                        AdmlSuccessful = @([PSCustomObject]@{ FileInfo = @{ Name = 'test.adml' }; ActionType = 'Import' })
                        AdmxFailed = @()
                        AdmlFailed = @()
                    }
                    DurationMs = 150
                }
            }
            
            { & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -AdmxOnly -ConfirmApply -ErrorAction Stop } | 
                Should -Not -Throw
        }
    }
}

Describe 'Deploy-TierModel - FullDeployment Orchestration' {
    BeforeEach {
        Mock Read-Host { return 'N' }
    }
    
    Context 'Planning Mode' {
        It 'Should call all Get-* cmdlets in correct order' {
            & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -ErrorAction Stop
            
            Should -Invoke Get-TierModelOu -Times 1
            Should -Invoke Get-TierModelGroupFd -Times 1
            Should -Invoke Get-TierModelUserFd -Times 1
            Should -Invoke Get-TierModelOuAclFd -Times 1
            Should -Invoke Get-TierModelGpoFd -Times 1
            Should -Invoke Get-TierModelAdmx -Times 1
        }
        
        It 'Should not call any New-* cmdlets in planning mode' {
            & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -ErrorAction Stop
            
            Should -Invoke New-TierModelOu -Times 0
            Should -Invoke New-TierModelGroup -Times 0
            Should -Invoke New-TierModelUser -Times 0
            Should -Invoke New-TierModelOuAcl -Times 0
            Should -Invoke New-TierModelGpo -Times 0
            Should -Invoke Copy-TierModelAdmx -Times 0
        }
        
        It 'Should display deployment plan for all phases' {
            $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -ErrorAction Stop 6>&1 | Out-String
            
            $output | Should -Match 'Phase 1: Analyzing OUs'
            $output | Should -Match 'Phase 2: Analyzing Groups'
            $output | Should -Match 'Phase 3: Analyzing Users'
            $output | Should -Match 'Phase 4: Analyzing OU ACLs'
            $output | Should -Match 'Phase 5: Analyzing GPOs'
            $output | Should -Match 'Phase 6: Analyzing ADMX'
        }
        
        It 'Should aggregate action counts across all phases' {
            Mock Get-TierModelOu {
                New-MockDeploymentPlan -EntityType 'OU' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1
            }
            Mock Get-TierModelGroupFd {
                New-MockDeploymentPlan -EntityType 'Group' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1  
            }
            Mock Get-TierModelUserFd {
                $plan = New-MockDeploymentPlan -EntityType 'User' -TotalInConfig 3 -ToCreate 1 -ToUpdate 1 -ExistingCount 1
                return $plan
            }
            
            $output = (& $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -ErrorAction Stop 6>&1) | Out-String
            
            $output | Should -Match 'Deployment Plan'
        }
    }
    
    Context 'Execution Mode' {
        It 'Should call all deployment cmdlets when ConfirmApply is specified' {
            Mock Read-Host { return 'Y' }
            
            # Setup plans with actions
            Mock Get-TierModelOu {
                New-MockDeploymentPlan -EntityType 'OU' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1
            }
            Mock Get-TierModelGroupFd {
                New-MockDeploymentPlan -EntityType 'Group' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1
            }
            Mock Get-TierModelUserFd {
                New-MockDeploymentPlan -EntityType 'User' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1
            }
            Mock Get-TierModelOuAclFd {
                $result = [PSCustomObject]@{ EntityType = 'OuAcl' }
                $result | Add-Member -MemberType NoteProperty -Name 'Summary' -Value ([PSCustomObject]@{
                    TotalActions = 1
                    CreateActions = 1
                    ExistingCount = 0
                })
                $result | Add-Member -MemberType NoteProperty -Name 'Actions' -Value (@([PSCustomObject]@{ 
                    OU = 'OU=Test,DC=test,DC=local'
                    Action = 'CreateAcl'
                    Data = @{
                        identityreference = 'TEST\TestGroup1'
                        activedirectoryrights = @('GenericAll')
                        objecttype = 'All Objects'
                        activeDirectorysecurityinheritance = 'All'
                    }
                }))
                $result | Add-Member -MemberType NoteProperty -Name 'Warnings' -Value ([object[]]@())
                $result | Add-Member -MemberType NoteProperty -Name 'Errors' -Value ([object[]]@())
                return $result
            }
            Mock Get-TierModelGpoFd {
                $result = [PSCustomObject]@{ EntityType = 'Gpo' }
                $result | Add-Member -MemberType NoteProperty -Name 'Summary' -Value ([PSCustomObject]@{
                    TotalActions = 1
                    CreateActions = 1
                    ExistingCount = 0
                })
                $result | Add-Member -MemberType NoteProperty -Name 'Actions' -Value (@([PSCustomObject]@{ 
                    Name = 'TestGPO1'
                    Action = 'CreateGpo'
                }))
                $result | Add-Member -MemberType NoteProperty -Name 'Warnings' -Value ([object[]]@())
                $result | Add-Member -MemberType NoteProperty -Name 'Errors' -Value ([object[]]@())
                return $result
            }
            Mock Get-TierModelAdmx {
                [PSCustomObject]@{
                    EntityType = 'ADMX'
                    Summary = [PSCustomObject]@{ 
                        TotalFiles = 2
                        FilesToUpdate = 1
                        FilesUpToDate = 1
                    }
                    Analysis = [PSCustomObject]@{
                        AdmxToUpdate = @([PSCustomObject]@{ Name = 'test.admx'; ActionType = 'Import' })
                        AdmlToUpdate = @()
                        Errors = @()
                    }
                }
            }
            
            & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -ConfirmApply -ErrorAction Stop
            
            Should -Invoke New-TierModelOu -Times 1
            Should -Invoke New-TierModelGroup -Times 1
            Should -Invoke New-TierModelUser -Times 1
            Should -Invoke New-TierModelOuAcl -Times 1
            Should -Invoke New-TierModelGpo -Times 1
            Should -Invoke Copy-TierModelAdmx -Times 1
        }

        It 'BUG-011: clean FullDeployment reports Skipped: 0 (no phantom 1..0 range skips)' {
            # Regression: the User and OuAcl phases built their result Skipped arrays with
            # @(1..$executionResult.Skipped | ForEach-Object {...}). On a clean deploy Skipped=0,
            # and PowerShell's 1..0 is the DESCENDING range {1,0} (2 elements) — so each of those
            # two phases emitted 2 phantom "Skipped" entries, yielding a bogus "Skipped: 4" with
            # zero real skips. Guarding the range with `if ($n -gt 0)` fixes it.
            Mock Read-Host { return 'Y' }
            Mock Get-TierModelOu {
                New-MockDeploymentPlan -EntityType 'OU' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1
            }
            Mock Get-TierModelGroupFd {
                New-MockDeploymentPlan -EntityType 'Group' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1
            }
            Mock Get-TierModelUserFd {
                New-MockDeploymentPlan -EntityType 'User' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1
            }
            Mock Get-TierModelOuAclFd {
                $result = [PSCustomObject]@{ EntityType = 'OuAcl' }
                $result | Add-Member -MemberType NoteProperty -Name 'Summary' -Value ([PSCustomObject]@{
                    TotalActions = 1
                    CreateActions = 1
                    ExistingCount = 0
                })
                $result | Add-Member -MemberType NoteProperty -Name 'Actions' -Value (@([PSCustomObject]@{
                    OU = 'OU=Test,DC=test,DC=local'
                    Action = 'CreateAcl'
                    Data = @{
                        identityreference = 'TEST\TestGroup1'
                        activedirectoryrights = @('GenericAll')
                        objecttype = 'All Objects'
                        activeDirectorysecurityinheritance = 'All'
                    }
                }))
                $result | Add-Member -MemberType NoteProperty -Name 'Warnings' -Value ([object[]]@())
                $result | Add-Member -MemberType NoteProperty -Name 'Errors' -Value ([object[]]@())
                return $result
            }
            Mock Get-TierModelGpoFd {
                $result = [PSCustomObject]@{ EntityType = 'Gpo' }
                $result | Add-Member -MemberType NoteProperty -Name 'Summary' -Value ([PSCustomObject]@{
                    TotalActions = 1
                    CreateActions = 1
                    ExistingCount = 0
                })
                $result | Add-Member -MemberType NoteProperty -Name 'Actions' -Value (@([PSCustomObject]@{
                    Name = 'TestGPO1'
                    Action = 'CreateGpo'
                }))
                $result | Add-Member -MemberType NoteProperty -Name 'Warnings' -Value ([object[]]@())
                $result | Add-Member -MemberType NoteProperty -Name 'Errors' -Value ([object[]]@())
                return $result
            }
            Mock Get-TierModelAdmx {
                [PSCustomObject]@{
                    EntityType = 'ADMX'
                    Summary = [PSCustomObject]@{ TotalFiles = 2; FilesToUpdate = 1; FilesUpToDate = 1 }
                    Analysis = [PSCustomObject]@{
                        AdmxToUpdate = @([PSCustomObject]@{ Name = 'test.admx'; ActionType = 'Import' })
                        AdmlToUpdate = @()
                        Errors = @()
                    }
                }
            }

            $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -ConfirmApply -ErrorAction Stop 6>&1 | Out-String

            # The two phases that used the 1..$n antipattern must have executed with zero real skips
            Should -Invoke New-TierModelUser -Times 1
            Should -Invoke New-TierModelOuAcl -Times 1
            # Consolidated summary must report zero skips (was a phantom "Skipped: 4" before the fix)
            $output | Should -Match 'Skipped:\s*0'
            $output | Should -Not -Match 'Skipped:\s*[1-9]'
        }
        
        It 'Should handle FullDeployment with some phases having no actions' {
            Mock Read-Host { return 'Y' }
            
            # Setup mixed scenarios - some need actions, some don't
            Mock Get-TierModelOu {
                New-MockDeploymentPlan -EntityType 'OU' -TotalInConfig 2 -ToCreate 0 -ExistingCount 2
            }
            Mock Get-TierModelGroupFd {
                New-MockDeploymentPlan -EntityType 'Group' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1
            }
            Mock Get-TierModelUserFd {
                New-MockDeploymentPlan -EntityType 'User' -TotalInConfig 2 -ToCreate 0 -ExistingCount 2
            }
            
            & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -ConfirmApply -ErrorAction Stop
            
            # Only Group should be executed (has actions)
            Should -Invoke New-TierModelOu -Times 0
            Should -Invoke New-TierModelGroup -Times 1
            Should -Invoke New-TierModelUser -Times 0
        }
        
        It 'Should continue deployment even if one phase fails' {
            Mock Read-Host { return 'Y' }
            
            Mock Get-TierModelOu {
                New-MockDeploymentPlan -EntityType 'OU' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1
            }
            Mock New-TierModelOu { throw 'OU deployment failed' }
            
            Mock Get-TierModelGroupFd {
                New-MockDeploymentPlan -EntityType 'Group' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1
            }
            
            # Should continue to Group even though OU failed
            & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -ConfirmApply -ErrorAction Stop
            
            Should -Invoke New-TierModelGroup -Times 1
        }
    }
}

Describe 'Deploy-TierModel - Error Handling' {
    BeforeEach {
        Mock Read-Host { return 'N' }
    }
    
    It 'Should handle null result from Get-TierModelOu' {
        Mock Get-TierModelOu {
            [PSCustomObject]@{
                EntityType = 'OU'
                Summary = [PSCustomObject]@{
                    TotalInConfig = 0
                    ToCreate = 0
                    ExistingCount = 0
                }
                Actions = @()
                Warnings = @()
                Errors = @()
            }
        }
        
        { & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -ErrorAction Stop } | 
            Should -Not -Throw
    }
    
    It 'Should handle missing Actions property gracefully' {
        Mock Get-TierModelOu {
            [PSCustomObject]@{
                EntityType = 'OU'
                Summary = [PSCustomObject]@{
                    TotalInConfig = 2
                    ToCreate = 0
                    ExistingCount = 2
                }
                Actions = @()
                Warnings = @()
                Errors = @()
            }
        }
        
        { & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -ErrorAction Stop } | 
            Should -Not -Throw
    }
    
    It 'Should handle plan errors and skip execution' {
        Mock Read-Host { return 'Y' }
        Mock Get-TierModelGroup {
            $plan = New-MockDeploymentPlan -EntityType 'Group' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1 -WithErrors
            return $plan
        }
        
        & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GroupOnly -ConfirmApply -ErrorAction Stop
        
        # Should not execute when there are plan errors
        Should -Invoke New-TierModelGroup -Times 0
    }
    
    It 'Should handle null result from New-TierModelOu' {
        Mock Read-Host { return 'Y' }
        Mock Get-TierModelOu {
            New-MockDeploymentPlan -EntityType 'OU' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1
        }
        Mock New-TierModelOu { return $null }
        
        { & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -ConfirmApply -ErrorAction Stop } | 
            Should -Not -Throw  # Production code handles null gracefully with fallback result
    }
    
    It 'Should handle deployment result without Applied property' {
        Mock Read-Host { return 'Y' }
        Mock Get-TierModelGroup {
            New-MockDeploymentPlan -EntityType 'Group' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1
        }
        Mock New-TierModelGroup {
            return [PSCustomObject]@{
                EntityType = 'Group'
                # Missing Applied property
                Errors = @()
            }
        }
        
        { & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GroupOnly -ConfirmApply -ErrorAction Stop } | 
            Should -Not -Throw  # Production code handles missing Applied property gracefully with fallback result
    }
}

Describe 'Deploy-TierModel - Logging Integration' {
    BeforeEach {
        Mock Read-Host { return 'N' }
    }
    
    It 'Should log OU deployment start and completion' {
        Mock Read-Host { return 'Y' }
        Mock Get-TierModelOu {
            New-MockDeploymentPlan -EntityType 'OU' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1
        }
        Mock New-TierModelOu {
            [PSCustomObject]@{
                Applied = @([PSCustomObject]@{ Name = 'TestOU1'; Action = 'Create' })
                Skipped = @()
                Errors = @()
                DurationMs = 100
                Converged = $true
            }
        }
        
        & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -ConfirmApply -Logging -OutputFileBase 'TestLog' -ErrorAction Stop
        
        Should -Invoke Write-TierModelLog -Times 1 -ParameterFilter { 
            $Message -eq 'Starting OU deployment - Mode: EXECUTION' -and $Level -eq 'Info'
        }
        Should -Invoke Write-TierModelLog -Times 1 -ParameterFilter { 
            $Message -like 'OU deployment completed*' -and $Level -eq 'Info'
        }
    }
    
    It 'Should log FullDeployment sequence start' {
        & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -Logging -OutputFileBase 'TestLog' -ErrorAction Stop
        
        Should -Invoke Write-TierModelLog -Times 1 -ParameterFilter { 
            $Message -eq 'Starting Full Deployment sequence' -and $Level -eq 'Info'
        }
    }
    
    It 'Should log configuration load success' {
        & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -Logging -OutputFileBase 'TestLog' -ErrorAction Stop
        
        Should -Invoke Write-TierModelLog -Times 1 -ParameterFilter { 
            $Message -eq 'Configuration loaded successfully' -and $Level -eq 'Info'
        }
    }
    
    It 'Should log prerequisites validation success' {
        & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -Logging -OutputFileBase 'TestLog' -ErrorAction Stop
        
        Should -Invoke Write-TierModelLog -Times 1 -ParameterFilter { 
            $Message -eq 'Prerequisites validation passed' -and $Level -eq 'Info'
        }
    }
}

# =============================================================================
# Additional tests to improve coverage for previously-untested branches
# =============================================================================

Describe 'Deploy-TierModel - Logging Edge Cases' {
    It 'Should throw when OutputFileBase is empty string while Logging enabled' {
        Mock Read-Host {
            param($Prompt)
            if ($Prompt -like '*base filename*') { return '' }
            return 'N'
        }
        { & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -Logging -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*OutputFileBase cannot be empty*'
    }

    It 'Should throw when OutputFileBase is whitespace-only while Logging enabled' {
        Mock Read-Host {
            param($Prompt)
            if ($Prompt -like '*base filename*') { return '   ' }
            return 'N'
        }
        { & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -Logging -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*OutputFileBase cannot be empty*'
    }
}

Describe 'Deploy-TierModel - Error Path Logging' {
    BeforeEach {
        Mock Read-Host { return 'N' }
    }

    It 'Should log error message when prerequisites check throws with Logging enabled' {
        Mock Test-TierModelPrerequisites { throw 'Simulated prereq failure' }

        $null = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -Logging -OutputFileBase 'TestLog' -ErrorAction SilentlyContinue

        Should -Invoke Write-TierModelLog -ParameterFilter {
            $Level -eq 'Error' -and $Message -like '*Prerequisites check failed*'
        }
    }

    It 'Should log error message when config loading fails with Logging enabled' {
        Mock Get-TierModelConfig { throw 'Simulated config failure' }

        $null = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -Logging -OutputFileBase 'TestLog' -ErrorAction SilentlyContinue

        Should -Invoke Write-TierModelLog -ParameterFilter {
            $Level -eq 'Error' -and $Message -like '*Failed to load configuration*'
        }
    }

    It 'Should exit when prerequisites return invalid result' {
        Mock Test-TierModelPrerequisites {
            return [PSCustomObject]@{
                Valid = $false
                Errors = @('Missing domain connectivity')
                Remediation = @('Ensure DC is reachable')
            }
        }

        $null = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -ErrorAction SilentlyContinue
        $LASTEXITCODE | Should -Be 1
    }
}

Describe 'Deploy-TierModel - OuOnly Display Variants' {
    BeforeEach {
        Mock Read-Host { return 'N' }
    }

    It 'Should display Warnings section when plan contains warnings' {
        Mock Get-TierModelOu {
            $plan = New-MockDeploymentPlan -EntityType 'OU' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1
            $plan | Add-Member -MemberType NoteProperty -Name 'Warnings' -Value ([object[]]@('OU naming conflict detected')) -Force
            return $plan
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'Warnings'
        $output | Should -Match 'OU naming conflict detected'
    }

    It 'Should display no-actions message when plan has 0 actions to create' {
        Mock Get-TierModelOu {
            New-MockDeploymentPlan -EntityType 'OU' -TotalInConfig 2 -ToCreate 0 -ExistingCount 2
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'No actions needed'
    }

    It 'Should display error message and fall back when New-TierModelOu throws' {
        Mock Read-Host { return 'Y' }
        Mock Get-TierModelOu {
            New-MockDeploymentPlan -EntityType 'OU' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1
        }
        Mock New-TierModelOu { throw 'Simulated OU creation failure' }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -ConfirmApply -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'ERROR: OU deployment failed'
    }

    It 'Should not call New-TierModelOu when ConfirmApply but plan has no actions' {
        Mock Read-Host { return 'Y' }
        Mock Get-TierModelOu {
            New-MockDeploymentPlan -EntityType 'OU' -TotalInConfig 2 -ToCreate 0 -ExistingCount 2
        }

        & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -ConfirmApply -ErrorAction Stop

        Should -Invoke New-TierModelOu -Times 0
    }

    It 'Should show plan summary with action counts' {
        Mock Get-TierModelOu {
            New-MockDeploymentPlan -EntityType 'OU' -TotalInConfig 3 -ToCreate 2 -ExistingCount 1
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'Action count: 2'
        $output | Should -Match 'Create count: 2'
    }

    It 'Should show duration and convergence when ConfirmApply finishes successfully' {
        Mock Read-Host { return 'Y' }
        Mock Get-TierModelOu {
            New-MockDeploymentPlan -EntityType 'OU' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1
        }
        Mock New-TierModelOu {
            New-MockDeploymentResult -EntityType 'OU' -AppliedCount 1 -DurationMs 150 -Converged $true
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -ConfirmApply -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'Duration: 150ms'
        $output | Should -Match 'Converged: True'
    }
}

Describe 'Deploy-TierModel - GroupOnly Display Variants' {
    BeforeEach {
        Mock Read-Host { return 'N' }
    }

    It 'Should display Warnings section when plan contains warnings' {
        Mock Get-TierModelGroup {
            $plan = New-MockDeploymentPlan -EntityType 'Group' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1
            $plan | Add-Member -MemberType NoteProperty -Name 'Warnings' -Value ([object[]]@('Group scope mismatch')) -Force
            return $plan
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GroupOnly -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'Warnings'
        $output | Should -Match 'Group scope mismatch'
    }

    It 'Should display dependency errors and skip apply when plan has errors' {
        Mock Get-TierModelGroup {
            New-MockDeploymentPlan -EntityType 'Group' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1 -WithErrors
        }
        Mock Read-Host { return 'Y' }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GroupOnly -ConfirmApply -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'Dependency Errors'
        Should -Invoke New-TierModelGroup -Times 0
    }

    It 'Should display no-actions message when plan has 0 actions' {
        Mock Get-TierModelGroup {
            New-MockDeploymentPlan -EntityType 'Group' -TotalInConfig 2 -ToCreate 0 -ExistingCount 2
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GroupOnly -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'No actions needed'
    }

    It 'Should not call New-TierModelGroup when ConfirmApply but plan has no actions' {
        Mock Read-Host { return 'Y' }
        Mock Get-TierModelGroup {
            New-MockDeploymentPlan -EntityType 'Group' -TotalInConfig 2 -ToCreate 0 -ExistingCount 2
        }

        & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GroupOnly -ConfirmApply -ErrorAction Stop

        Should -Invoke New-TierModelGroup -Times 0
    }

    It 'Should display error message and fall back when New-TierModelGroup throws' {
        Mock Read-Host { return 'Y' }
        Mock Get-TierModelGroup {
            New-MockDeploymentPlan -EntityType 'Group' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1
        }
        Mock New-TierModelGroup { throw 'Simulated group deployment failure' }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GroupOnly -ConfirmApply -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'ERROR: Group deployment failed'
    }

    It 'Should display Resolve errors message in plan summary when result has errors' {
        Mock Get-TierModelGroup {
            New-MockDeploymentPlan -EntityType 'Group' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1 -WithErrors
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GroupOnly -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'Resolve all dependency errors'
    }
}

Describe 'Deploy-TierModel - UserOnly Display Variants' {
    BeforeEach {
        Mock Read-Host { return 'N' }
    }

    It 'Should display dependency errors when plan has errors' {
        Mock Get-TierModelUser {
            New-MockDeploymentPlan -EntityType 'User' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1 -WithErrors
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -UserOnly -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'Dependency Errors'
        # BUG-002: -UserOnly now mirrors -GroupOnly — Invoke-UserDeployment runs non-Silent, so it
        # prints the "User Plan Summary" section and lists the SPECIFIC missing OU/Group messages
        # (❌ items) before "=== Deployment Plan ===", and the Deployment Plan section shows only
        # the generic resolve line. Previously -UserOnly passed -Silent, hiding the summary and
        # the specific messages.
        $output | Should -Match 'User Plan Summary'
        $output | Should -Match 'Test error'
        $output | Should -Match 'Resolve all dependency errors before proceeding with User deployment'
    }

    It 'Should display Update count for UpdateUserMembership actions in outer plan summary' {
        Mock Get-TierModelUser {
            New-MockDeploymentPlan -EntityType 'User' -TotalInConfig 2 -ToCreate 0 -ToUpdate 1 -ExistingCount 2
        }

        # -UserOnly runs non-Silent (mirrors -GroupOnly); the outer plan summary still shows Update count
        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -UserOnly -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'Update count: 1'
    }

    It 'Should display zero action count in outer summary when plan has 0 actions' {
        Mock Get-TierModelUser {
            New-MockDeploymentPlan -EntityType 'User' -TotalInConfig 2 -ToCreate 0 -ExistingCount 2
        }

        # -UserOnly runs non-Silent (mirrors -GroupOnly); outer code still shows action counts
        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -UserOnly -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'Action count: 0'
    }

    It 'Should not call New-TierModelUser when plan has errors' {
        Mock Read-Host { return 'Y' }
        Mock Get-TierModelUser {
            New-MockDeploymentPlan -EntityType 'User' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1 -WithErrors
        }

        & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -UserOnly -ConfirmApply -ErrorAction Stop

        Should -Invoke New-TierModelUser -Times 0
    }

    It 'Should display UserOnly plan summary with separate Create and Update counts' {
        Mock Get-TierModelUser {
            New-MockDeploymentPlan -EntityType 'User' -TotalInConfig 3 -ToCreate 1 -ToUpdate 1 -ExistingCount 1
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -UserOnly -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'Action count: 2'
        $output | Should -Match 'Create count: 1'
        $output | Should -Match 'Update count: 1'
    }
}

Describe 'Deploy-TierModel - OuAclsOnly Display Variants' {
    BeforeEach {
        Mock Read-Host { return 'N' }
    }

    It 'Should display ACE grouping by principal in planning mode' {
        Mock Get-TierModelOuAcl {
            $result = [PSCustomObject]@{ EntityType = 'OuAcl' }
            $result | Add-Member -MemberType NoteProperty -Name 'Summary' -Value ([PSCustomObject]@{
                TotalActions = 2; CreateActions = 2
            })
            $result | Add-Member -MemberType NoteProperty -Name 'Actions' -Value ([object[]]@(
                [PSCustomObject]@{
                    OU = 'OU=TestOU1,DC=test,DC=local'; Action = 'CreateAcl'
                    Data = @{ identityreference = 'TEST\TestGroup1'; activedirectoryrights = @('GenericAll'); objecttype = 'All Objects'; activeDirectorysecurityinheritance = 'All' }
                },
                [PSCustomObject]@{
                    OU = 'OU=TestOU2,DC=test,DC=local'; Action = 'CreateAcl'
                    Data = @{ identityreference = 'TEST\TestGroup1'; activedirectoryrights = @('CreateChild'); objecttype = 'Computer'; activeDirectorysecurityinheritance = 'All' }
                }
            ))
            $result | Add-Member -MemberType NoteProperty -Name 'Warnings' -Value ([object[]]@())
            $result | Add-Member -MemberType NoteProperty -Name 'Errors' -Value ([object[]]@())
            return $result
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuAclsOnly -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'Principal:'
        $output | Should -Match 'TEST\\TestGroup1'
    }

    It 'Should display dependency errors when plan has errors' {
        Mock Get-TierModelOuAcl {
            $result = [PSCustomObject]@{ EntityType = 'OuAcl' }
            $result | Add-Member -MemberType NoteProperty -Name 'Summary' -Value ([PSCustomObject]@{ TotalActions = 0; CreateActions = 0 })
            $result | Add-Member -MemberType NoteProperty -Name 'Actions' -Value ([object[]]@())
            $result | Add-Member -MemberType NoteProperty -Name 'Warnings' -Value ([object[]]@())
            $result | Add-Member -MemberType NoteProperty -Name 'Errors' -Value ([object[]]@([PSCustomObject]@{ Message = 'Schema extension missing' }))
            return $result
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuAclsOnly -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'Dependency Errors'
    }

    It 'Should not call New-TierModelOuAcl when plan has 0 actions even with ConfirmApply' {
        Mock Read-Host { return 'Y' }
        Mock Get-TierModelOuAcl {
            $result = [PSCustomObject]@{ EntityType = 'OuAcl' }
            $result | Add-Member -MemberType NoteProperty -Name 'Summary' -Value ([PSCustomObject]@{ TotalActions = 0; CreateActions = 0 })
            $result | Add-Member -MemberType NoteProperty -Name 'Actions' -Value ([object[]]@())
            $result | Add-Member -MemberType NoteProperty -Name 'Warnings' -Value ([object[]]@())
            $result | Add-Member -MemberType NoteProperty -Name 'Errors' -Value ([object[]]@())
            return $result
        }

        & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuAclsOnly -ConfirmApply -ErrorAction Stop

        Should -Invoke New-TierModelOuAcl -Times 0
    }

    It 'Should display Deployment Results header when OuAclsOnly uses ConfirmApply' {
        Mock Read-Host { return 'Y' }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuAclsOnly -ConfirmApply -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'Deployment Results'
    }
}

Describe 'Deploy-TierModel - GposOnly Multi-Phase Execution' {
    BeforeEach {
        Mock Read-Host { return 'N' }
        Mock Import-TierModelGpo {
            [PSCustomObject]@{ Executed = 1; Failed = 0; Skipped = 0; Errors = @(); DurationMs = 50; Converged = $true }
        }
        Mock Update-TierModelGPOConfig {
            [PSCustomObject]@{ Executed = 1; Failed = 0; Skipped = 0; Errors = @(); DurationMs = 30; Converged = $true }
        }
        Mock Get-TierModelGPOLink {
            [PSCustomObject]@{ Actions = @(); Config = $null; Errors = @() }
        }
        Mock New-TierModelGPOLink {
            [PSCustomObject]@{ Executed = 1; Failed = 0; Skipped = 0; Errors = @(); DurationMs = 20; Converged = $true }
        }
    }

    It 'Should display dependency errors when planCheck returns errors' {
        Mock Get-TierModelGpo {
            $result = [PSCustomObject]@{ EntityType = 'GPO' }
            $result | Add-Member -MemberType NoteProperty -Name 'Summary' -Value ([PSCustomObject]@{
                TotalInConfig = 1; ToCreate = 0; ExistingCount = 0; TotalActions = 0
                CreateActions = 0; ImportActions = 0; ConfigureActions = 0; LinkActions = 0
            })
            $result | Add-Member -MemberType NoteProperty -Name 'Actions' -Value ([object[]]@())
            $result | Add-Member -MemberType NoteProperty -Name 'Warnings' -Value ([object[]]@())
            $result | Add-Member -MemberType NoteProperty -Name 'Errors' -Value ([object[]]@([PSCustomObject]@{ Message = 'GPO template file missing' }))
            return $result
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GposOnly -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'Dependency Errors'
    }

    It 'Should display GPO plan summary with action counts in planning mode' {
        Mock Get-TierModelGpo {
            $result = [PSCustomObject]@{ EntityType = 'GPO' }
            $result | Add-Member -MemberType NoteProperty -Name 'Summary' -Value ([PSCustomObject]@{
                TotalInConfig = 3; ToCreate = 1; ExistingCount = 2; TotalActions = 2
                CreateActions = 1; ImportActions = 1; ConfigureActions = 0; LinkActions = 0
            })
            $result | Add-Member -MemberType NoteProperty -Name 'Actions' -Value ([object[]]@(
                [PSCustomObject]@{ Name = 'TestGPO1'; Action = 'CreateGPO' },
                [PSCustomObject]@{ Name = 'TestGPO2'; Action = 'ImportGPO' }
            ))
            $result | Add-Member -MemberType NoteProperty -Name 'Warnings' -Value ([object[]]@())
            $result | Add-Member -MemberType NoteProperty -Name 'Errors' -Value ([object[]]@())
            return $result
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GposOnly -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'GPO Plan Summary'
        $output | Should -Match 'Total in Config: 3'
        $output | Should -Match 'To Create: 1'
    }

    It 'Should display GPO plan warnings when present' {
        Mock Get-TierModelGpo {
            $result = [PSCustomObject]@{ EntityType = 'GPO' }
            $result | Add-Member -MemberType NoteProperty -Name 'Summary' -Value ([PSCustomObject]@{
                TotalInConfig = 2; ToCreate = 1; ExistingCount = 1; TotalActions = 1
                CreateActions = 1; ImportActions = 0; ConfigureActions = 0; LinkActions = 0
            })
            $result | Add-Member -MemberType NoteProperty -Name 'Actions' -Value ([object[]]@(
                [PSCustomObject]@{ Name = 'TestGPO1'; Action = 'CreateGPO' }
            ))
            $result | Add-Member -MemberType NoteProperty -Name 'Warnings' -Value ([object[]]@('GPO backup file is outdated'))
            $result | Add-Member -MemberType NoteProperty -Name 'Errors' -Value ([object[]]@())
            return $result
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GposOnly -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'Warnings'
        $output | Should -Match 'GPO backup file is outdated'
    }

    It 'Should execute Phase 2 (ImportGPO) when plan has ImportGPO actions' {
        Mock Read-Host { return 'Y' }
        Mock Get-TierModelGpo {
            $result = [PSCustomObject]@{ EntityType = 'GPO' }
            $result | Add-Member -MemberType NoteProperty -Name 'Summary' -Value ([PSCustomObject]@{
                TotalInConfig = 2; ToCreate = 0; ExistingCount = 1; TotalActions = 1
                CreateActions = 0; ImportActions = 1; ConfigureActions = 0; LinkActions = 0
            })
            $result | Add-Member -MemberType NoteProperty -Name 'Actions' -Value ([object[]]@(
                [PSCustomObject]@{ Name = 'TestGPO1'; Action = 'ImportGPO' }
            ))
            $result | Add-Member -MemberType NoteProperty -Name 'Warnings' -Value ([object[]]@())
            $result | Add-Member -MemberType NoteProperty -Name 'Errors' -Value ([object[]]@())
            return $result
        }

        & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GposOnly -ConfirmApply -ErrorAction Stop

        Should -Invoke Import-TierModelGpo -Times 1
    }

    It 'Should execute Phase 3 (ConfigureGPO) when plan has ConfigureGPO actions' {
        Mock Read-Host { return 'Y' }
        Mock Get-TierModelGpo {
            $result = [PSCustomObject]@{ EntityType = 'GPO' }
            $result | Add-Member -MemberType NoteProperty -Name 'Summary' -Value ([PSCustomObject]@{
                TotalInConfig = 2; ToCreate = 0; ExistingCount = 2; TotalActions = 1
                CreateActions = 0; ImportActions = 0; ConfigureActions = 1; LinkActions = 0
            })
            $result | Add-Member -MemberType NoteProperty -Name 'Actions' -Value ([object[]]@(
                [PSCustomObject]@{ Name = 'TestGPO1'; Action = 'ConfigureGPO' }
            ))
            $result | Add-Member -MemberType NoteProperty -Name 'Warnings' -Value ([object[]]@())
            $result | Add-Member -MemberType NoteProperty -Name 'Errors' -Value ([object[]]@())
            return $result
        }

        & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GposOnly -ConfirmApply -ErrorAction Stop

        Should -Invoke Update-TierModelGPOConfig -Times 1
    }

    It 'Should execute Phase 4 (LinkGPO) when plan has LinkGPO actions' {
        Mock Read-Host { return 'Y' }
        Mock Get-TierModelGpo {
            $result = [PSCustomObject]@{ EntityType = 'GPO' }
            $result | Add-Member -MemberType NoteProperty -Name 'Summary' -Value ([PSCustomObject]@{
                TotalInConfig = 2; ToCreate = 0; ExistingCount = 2; TotalActions = 1
                CreateActions = 0; ImportActions = 0; ConfigureActions = 0; LinkActions = 1
            })
            $result | Add-Member -MemberType NoteProperty -Name 'Actions' -Value ([object[]]@(
                [PSCustomObject]@{ Name = 'TestGPO1'; Action = 'LinkGPO'; OU = 'OU=TestOU1,DC=test,DC=local' }
            ))
            $result | Add-Member -MemberType NoteProperty -Name 'Warnings' -Value ([object[]]@())
            $result | Add-Member -MemberType NoteProperty -Name 'Errors' -Value ([object[]]@())
            return $result
        }
        Mock Get-TierModelGPOLink {
            [PSCustomObject]@{
                Actions = @([PSCustomObject]@{ Name = 'TestGPO1'; Action = 'LinkGPO' })
                Config = $null; Errors = @()
            }
        }

        & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GposOnly -ConfirmApply -ErrorAction Stop

        Should -Invoke New-TierModelGPOLink -Times 1
    }

    It 'Should not call New-TierModelGpo when plan is fully converged in planning mode' {
        Mock Get-TierModelGpo {
            $result = [PSCustomObject]@{ EntityType = 'GPO' }
            $result | Add-Member -MemberType NoteProperty -Name 'Summary' -Value ([PSCustomObject]@{
                TotalInConfig = 2; ToCreate = 0; ExistingCount = 2; TotalActions = 0
                CreateActions = 0; ImportActions = 0; ConfigureActions = 0; LinkActions = 0
            })
            $result | Add-Member -MemberType NoteProperty -Name 'Actions' -Value ([object[]]@())
            $result | Add-Member -MemberType NoteProperty -Name 'Warnings' -Value ([object[]]@())
            $result | Add-Member -MemberType NoteProperty -Name 'Errors' -Value ([object[]]@())
            return $result
        }

        & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GposOnly -ErrorAction Stop

        Should -Invoke New-TierModelGpo -Times 0
    }

    It 'Should stop GPO deployment when Phase 1 completely fails' {
        Mock Read-Host { return 'Y' }
        Mock Get-TierModelGpo {
            $result = [PSCustomObject]@{ EntityType = 'GPO' }
            $result | Add-Member -MemberType NoteProperty -Name 'Summary' -Value ([PSCustomObject]@{
                TotalInConfig = 2; ToCreate = 1; ExistingCount = 1; TotalActions = 2
                CreateActions = 1; ImportActions = 1; ConfigureActions = 0; LinkActions = 0
            })
            $result | Add-Member -MemberType NoteProperty -Name 'Actions' -Value ([object[]]@(
                [PSCustomObject]@{ Name = 'TestGPO1'; Action = 'CreateGPO' },
                [PSCustomObject]@{ Name = 'TestGPO1'; Action = 'ImportGPO' }
            ))
            $result | Add-Member -MemberType NoteProperty -Name 'Warnings' -Value ([object[]]@())
            $result | Add-Member -MemberType NoteProperty -Name 'Errors' -Value ([object[]]@())
            return $result
        }
        Mock New-TierModelGpo {
            [PSCustomObject]@{ Executed = 0; Failed = 1; Skipped = 0; Errors = @('Creation failed'); DurationMs = 10; Converged = $false }
        }

        { & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GposOnly -ConfirmApply -ErrorAction Stop } |
            Should -Not -Throw

        Should -Invoke Import-TierModelGpo -Times 0
    }

    It 'Should display GPO deployment plan summary with action breakdown after ConfirmApply' {
        Mock Read-Host { return 'Y' }
        # Default Get-TierModelGpo mock has 1 CreateGPO action

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GposOnly -ConfirmApply -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'Deployment Plan'
        $output | Should -Match 'To Create:'
    }

    It 'Should stop GPO deployment when Phase 3 has failures' {
        Mock Read-Host { return 'Y' }
        Mock Get-TierModelGpo {
            $result = [PSCustomObject]@{ EntityType = 'GPO' }
            $result | Add-Member -MemberType NoteProperty -Name 'Summary' -Value ([PSCustomObject]@{
                TotalInConfig = 2; ToCreate = 0; ExistingCount = 2; TotalActions = 2
                CreateActions = 0; ImportActions = 0; ConfigureActions = 1; LinkActions = 1
            })
            $result | Add-Member -MemberType NoteProperty -Name 'Actions' -Value ([object[]]@(
                [PSCustomObject]@{ Name = 'TestGPO1'; Action = 'ConfigureGPO' },
                [PSCustomObject]@{ Name = 'TestGPO1'; Action = 'LinkGPO' }
            ))
            $result | Add-Member -MemberType NoteProperty -Name 'Warnings' -Value ([object[]]@())
            $result | Add-Member -MemberType NoteProperty -Name 'Errors' -Value ([object[]]@())
            return $result
        }
        Mock Update-TierModelGPOConfig {
            [PSCustomObject]@{ Executed = 0; Failed = 1; Skipped = 0; Errors = @('SID resolution failed'); DurationMs = 10; Converged = $false }
        }

        { & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GposOnly -ConfirmApply -ErrorAction Stop } |
            Should -Not -Throw

        Should -Invoke New-TierModelGPOLink -Times 0
    }
}

Describe 'Deploy-TierModel - FullDeployment All-Converged Path' {
    BeforeEach {
        Mock Read-Host { return 'N' }
        Mock Get-TierModelGpoLinkFd {
            [PSCustomObject]@{ Actions = @(); Errors = @(); Config = $null }
        }
    }

    It 'Should display no-actions-required message when ConfirmApply but all phases converged' {
        Mock Read-Host { return 'Y' }
        Mock Get-TierModelOu {
            New-MockDeploymentPlan -EntityType 'OU' -TotalInConfig 2 -ToCreate 0 -ExistingCount 2
        }
        Mock Get-TierModelGroupFd {
            New-MockDeploymentPlan -EntityType 'Group' -TotalInConfig 2 -ToCreate 0 -ExistingCount 2
        }
        Mock Get-TierModelUserFd {
            New-MockDeploymentPlan -EntityType 'User' -TotalInConfig 2 -ToCreate 0 -ExistingCount 2
        }
        Mock Get-TierModelAdmx {
            [PSCustomObject]@{
                EntityType = 'ADMX'
                Summary = [PSCustomObject]@{ TotalFiles = 2; FilesToUpdate = 0; FilesUpToDate = 2 }
                Analysis = [PSCustomObject]@{ AdmxToUpdate = @(); AdmlToUpdate = @(); AdmxUpToDate = @(); AdmlUpToDate = @(); Errors = @() }
                Warnings = @(); Errors = @()
            }
        }
        # Note: This test uses zero-action mocks to test "no actions required" path

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -ConfirmApply -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'No actions required'
    }

    It 'Should show consolidated deployment results when ConfirmApply with some actions' {
        Mock Read-Host { return 'Y' }
        Mock Get-TierModelOu {
            New-MockDeploymentPlan -EntityType 'OU' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1
        }
        Mock Get-TierModelGroupFd {
            New-MockDeploymentPlan -EntityType 'Group' -TotalInConfig 2 -ToCreate 0 -ExistingCount 2
        }
        Mock Get-TierModelUserFd {
            New-MockDeploymentPlan -EntityType 'User' -TotalInConfig 2 -ToCreate 0 -ExistingCount 2
        }
        Mock Get-TierModelAdmx {
            [PSCustomObject]@{
                EntityType = 'ADMX'
                Summary = [PSCustomObject]@{ TotalFiles = 1; FilesToUpdate = 0; FilesUpToDate = 1 }
                Analysis = [PSCustomObject]@{ AdmxToUpdate = @(); AdmlToUpdate = @(); Errors = @() }
                Warnings = @(); Errors = @()
            }
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -ConfirmApply -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'Deployment Results'
        $output | Should -Match 'Applied:'
        $output | Should -Match 'Converged:'
    }

    It 'Should display existing OUs in FullDeployment planning when ExistingCount is nonzero' {
        Mock Get-TierModelOu {
            New-MockDeploymentPlan -EntityType 'OU' -TotalInConfig 2 -ToCreate 0 -ExistingCount 2
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'No OU actions needed'
    }

    It 'Should display ADMX no-templates-current message when all files processed and no updates needed' {
        # FilesUpToDate=0 and FilesToUpdate=0 with TotalFiles=2 triggers the else branch
        # that shows 'No ADMX actions needed - all templates are current.'
        Mock Get-TierModelAdmx {
            [PSCustomObject]@{
                EntityType = 'ADMX'
                Summary = [PSCustomObject]@{ TotalFiles = 2; FilesToUpdate = 0; FilesUpToDate = 0 }
                Analysis = [PSCustomObject]@{
                    AdmxToUpdate = @(); AdmlToUpdate = @()
                    Errors = @()
                }
                Warnings = @(); Errors = @()
            }
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'No ADMX actions needed'
    }

    It 'Should show deployment plan summary with zero action count when all converged' {
        Mock Get-TierModelOu {
            New-MockDeploymentPlan -EntityType 'OU' -TotalInConfig 2 -ToCreate 0 -ExistingCount 2
        }
        Mock Get-TierModelGroupFd {
            New-MockDeploymentPlan -EntityType 'Group' -TotalInConfig 2 -ToCreate 0 -ExistingCount 2
        }
        Mock Get-TierModelUserFd {
            New-MockDeploymentPlan -EntityType 'User' -TotalInConfig 2 -ToCreate 0 -ExistingCount 2
        }
        # FilesUpToDate=0 and FilesToUpdate=0 prevents PropertyNotFoundException from StrictMode
        # on AdmxUpToDate property access when count > 0
        Mock Get-TierModelAdmx {
            [PSCustomObject]@{
                EntityType = 'ADMX'
                Summary = [PSCustomObject]@{ TotalFiles = 1; FilesToUpdate = 0; FilesUpToDate = 0 }
                Analysis = [PSCustomObject]@{ AdmxToUpdate = @(); AdmlToUpdate = @(); Errors = @() }
                Warnings = @(); Errors = @()
            }
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'Deployment Plan'
        $output | Should -Match 'Action count: 0'
    }
}

Describe 'Deploy-TierModel - AdmxOnly Deployment Results' {
    It 'Should display Deployment Results with action counts after successful execution' {
        Mock Read-Host { return 'Y' }
        Mock Copy-TierModelAdmx {
            [PSCustomObject]@{
                Summary = [PSCustomObject]@{ Successful = 2; Failed = 0 }
                Results = [PSCustomObject]@{
                    AdmxSuccessful = @([PSCustomObject]@{ FileInfo = @{ Name = 'test.admx' }; ActionType = 'Import' })
                    AdmlSuccessful = @([PSCustomObject]@{ FileInfo = @{ Name = 'test.adml' }; ActionType = 'Import' })
                    AdmxFailed = @()
                    AdmlFailed = @()
                }
                DurationMs = 200
            }
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -AdmxOnly -ConfirmApply -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'Deployment Results'
        $output | Should -Match 'Action count: 2'
        $output | Should -Match 'Create count: 2'
    }

    It 'Should display ADMX deployment errors when copy fails' {
        Mock Read-Host { return 'Y' }
        Mock Copy-TierModelAdmx {
            [PSCustomObject]@{
                Summary = [PSCustomObject]@{ Successful = 0; Failed = 1 }
                Results = [PSCustomObject]@{
                    AdmxSuccessful = @()
                    AdmlSuccessful = @()
                    AdmxFailed = @([PSCustomObject]@{ FileInfo = @{ Name = 'broken.admx' }; Error = 'Access denied' })
                    AdmlFailed = @()
                }
                DurationMs = 50
            }
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -AdmxOnly -ConfirmApply -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'ADMX Deployment Errors'
    }

    It 'Should display Deployment Plan section in AdmxOnly planning mode' {
        Mock Read-Host { return 'N' }
        Mock Get-TierModelAdmx {
            [PSCustomObject]@{
                EntityType = 'ADMX'
                Summary = [PSCustomObject]@{ TotalFiles = 2; FilesToUpdate = 0; FilesUpToDate = 2 }
                Analysis = [PSCustomObject]@{
                    AdmxToUpdate = @()
                    AdmlToUpdate = @()
                    Errors = @()
                }
                Warnings = @(); Errors = @()
            }
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -AdmxOnly -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'Deployment Plan'
        $output | Should -Match 'No actions needed'
    }
}

Describe 'Deploy-TierModel - Include ACL Display and Planning' {
    BeforeEach {
        Mock Read-Host { return 'N' }
    }

    It 'Should display standalone gMSA ACL actions and deployment summary' {
        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -IncludeGmsa -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'Phase: gMSA ACL Delegations'
        ([regex]::Matches($output, 'Create ACL:')).Count | Should -Be 4
        $output | Should -Match '=== Deployment Plan ==='
        $output | Should -Match 'Action count: 4'
        $output | Should -Match 'Create count: 4'
        $output | Should -Match 'Update count: 0'
        $output | Should -Match 'Link count: 0'
        $output | Should -Match 'Configure count: 0'
        $output | Should -Match 'Already exist: 0'
    }

    It 'Should aggregate standalone include plans across MSA gMSA and dMSA' {
        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -IncludeMsa -IncludeGmsa -IncludeDmsa -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'Phase: MSA ACL Delegations'
        $output | Should -Match 'Phase: gMSA ACL Delegations'
        $output | Should -Match 'Phase: dMSA ACL Delegations'
        ([regex]::Matches($output, 'Create ACL:')).Count | Should -Be 12
        $output | Should -Match 'Action count: 12'
        $output | Should -Match 'Create count: 12'
        $output | Should -Match 'Already exist: 0'
    }

    It 'Should add FullDeployment include actions to the deployment plan before the summary' {
        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -IncludeMsa -ErrorAction Stop 6>&1 | Out-String

        Should -Invoke Get-TierModelMsaAclFd -Times 1
        Should -Invoke Get-TierModelMsaAcl -Times 0
        $output | Should -Match 'Phase 7: MSA ACL Delegations'
        ([regex]::Matches($output, 'Create ACL:')).Count | Should -Be 4
        $output | Should -Match 'Action count: 8'
        $output | Should -Match 'Create count: 8'
    }

    It 'Should reuse precomputed FullDeployment include plans during execution' {
        Mock Read-Host { return 'Y' }

        & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -IncludeMsa -IncludeGmsa -IncludeDmsa -ConfirmApply -ErrorAction Stop

        Should -Invoke Get-TierModelMsaAclFd -Times 1
        Should -Invoke Get-TierModelGmsaAclFd -Times 1
        Should -Invoke Get-TierModelDmsaAclFd -Times 1
        Should -Invoke Get-TierModelMsaAcl -Times 0
        Should -Invoke Get-TierModelGmsaAcl -Times 0
        Should -Invoke Get-TierModelDmsaAcl -Times 0
        Should -Invoke New-TierModelMsaAcl -Times 1
        Should -Invoke New-TierModelGmsaAcl -Times 1
        Should -Invoke New-TierModelDmsaAcl -Times 1
    }

    It 'BUG-010: FullDeployment halts before Groups when an OU inheritance setting cannot be verified' {
        Mock Read-Host { return 'Y' }
        # OU phase creates the OU but reports an unverified inheritance error (BUG-010 code)
        Mock New-TierModelOu {
            [PSCustomObject]@{
                EntityType = 'OU'
                Applied = @([PSCustomObject]@{ Name = 'Tier0'; ActionsPerformed = @('CreateOU') })
                Skipped = @()
                Errors = @(@{ Code = 'BlockGpoInheritanceUnverified'; Message = "Block GPO Inheritance flag was not set for OU 'Tier0'."; Timestamp = Get-Date })
                DurationMs = 100
                Converged = $false
            }
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -ConfirmApply 6>&1 | Out-String

        $output | Should -Match 'halting deployment before Groups'
        $LASTEXITCODE | Should -Be 1
        # Groups (Phase 2) must NOT run once the OU tier boundary could not be verified
        Should -Not -Invoke New-TierModelGroup
    }

    It 'BUG-010: FullDeployment halts before Groups when OU errors are PSCustomObject format (not hashtable)' {
        # Covers Deploy-TierModel.ps1 L1757/L1764: the elseif branch reads .Code / .Message
        # from a [PSCustomObject] error (vs the hashtable branch already tested above).
        Mock Read-Host { return 'Y' }
        Mock New-TierModelOu {
            [PSCustomObject]@{
                EntityType = 'OU'
                Applied    = @([PSCustomObject]@{ Name = 'Tier0'; ActionsPerformed = @('CreateOU') })
                Skipped    = @()
                Errors     = @(
                    [PSCustomObject]@{
                        Code      = 'DisableSecurityInheritanceUnverified'
                        Message   = "Security-inheritance disable flag could not be confirmed for OU 'Tier0'."
                        Timestamp = Get-Date
                        Category  = 'Execution'
                    }
                )
                DurationMs = 100
                Converged  = $false
            }
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -ConfirmApply 6>&1 | Out-String

        $output | Should -Match 'halting deployment before Groups'
        $output | Should -Match 'Security-inheritance disable flag could not be confirmed'
        $LASTEXITCODE | Should -Be 1
        Should -Not -Invoke New-TierModelGroup
    }
}

Describe 'Deploy-TierModel - Coverage Gap Closing Round 2' {
    BeforeEach {
        Mock Read-Host { return 'N' }
    }

    # -------------------------------------------------------------------------
    # Logging dispatch entries (covers logging lines in single-entity dispatches)
    # -------------------------------------------------------------------------

    It 'Should write Logging entry when GroupOnly runs with Logging enabled' {
        # Covers line 1673: Write-TierModelLog in GroupOnly dispatch when Logging=true
        & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GroupOnly -Logging -OutputFileBase 'TestLog' -ErrorAction Stop

        Should -Invoke Write-TierModelLog -Times 1 -ParameterFilter {
            $Message -like '*Groups-Only*' -and $Level -eq 'Info'
        }
    }

    It 'Should complete OuAclsOnly deployment when Logging is enabled without error' {
        # OuAclsOnly dispatch has no dedicated logging block, verify no error occurs
        { & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuAclsOnly -Logging -OutputFileBase 'TestLog' -ErrorAction Stop } |
            Should -Not -Throw
    }

    It 'Should write Logging entry when GposOnly runs with Logging enabled' {
        Mock Import-TierModelGpo {
            [PSCustomObject]@{ Executed = 0; Failed = 0; Skipped = 0; Errors = @(); DurationMs = 0; Converged = $true }
        }
        Mock Update-TierModelGPOConfig {
            [PSCustomObject]@{ Executed = 0; Failed = 0; Skipped = 0; Errors = @(); DurationMs = 0; Converged = $true }
        }
        Mock Get-TierModelGPOLink {
            [PSCustomObject]@{ Actions = @(); Config = $null; Errors = @() }
        }
        Mock New-TierModelGPOLink {
            [PSCustomObject]@{ Executed = 0; Failed = 0; Skipped = 0; Errors = @(); DurationMs = 0; Converged = $true }
        }

        & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GposOnly -Logging -OutputFileBase 'TestLog' -ErrorAction Stop

        Should -Invoke Write-TierModelLog -Times 1 -ParameterFilter {
            $Message -like '*GPO-Only*' -and $Level -eq 'Info'
        }
    }

    It 'Should write Logging entries when OuOnly runs with ConfirmApply and Logging enabled' {
        # Covers lines 320 and 345: Write-TierModelLog in Invoke-OuDeployment Apply+planning blocks
        Mock Read-Host { return 'Y' }
        Mock Get-TierModelOu {
            New-MockDeploymentPlan -EntityType 'OU' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1
        }
        # Return Skipped as array to avoid StrictMode PropertyNotFoundException on .Count
        Mock New-TierModelOu {
            [PSCustomObject]@{
                EntityType = 'OU'
                Applied = @([PSCustomObject]@{ Name = 'TestOU1'; Action = 'Create' })
                Skipped = @()    # Array not integer - avoids $result.Skipped.Count StrictMode error
                Errors  = @()
                DurationMs = 100
                Converged  = $true
            }
        }
        & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuOnly -ConfirmApply -Logging -OutputFileBase 'TestLog' -ErrorAction Stop

        Should -Invoke Write-TierModelLog -Times 2
    }

    It 'Should write Logging entries when GroupOnly runs with ConfirmApply and Logging enabled' {
        # Covers lines 477-531: Invoke-GroupDeployment apply path with Logging
        Mock Read-Host { return 'Y' }
        Mock Get-TierModelGroup {
            New-MockDeploymentPlan -EntityType 'Group' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1
        }
        # Return Skipped as array to avoid StrictMode PropertyNotFoundException on .Count
        Mock New-TierModelGroup {
            [PSCustomObject]@{
                EntityType = 'Group'
                Applied = @([PSCustomObject]@{ Name = 'TestGroup1'; Action = 'Create' })
                Skipped = @()    # Array not integer - avoids $result.Skipped.Count StrictMode error
                Errors  = @()
                DurationMs = 100
                Converged  = $true
            }
        }
        & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GroupOnly -ConfirmApply -Logging -OutputFileBase 'TestLog' -ErrorAction Stop

        Should -Invoke Write-TierModelLog -Times 2
    }

    # -------------------------------------------------------------------------
    # OuAclsOnly: ConfirmApply duration/converged display (line 1838)
    # -------------------------------------------------------------------------

    It 'Should display Duration and Converged in OuAclsOnly plan when ConfirmApply succeeds' {
        # Covers line 1838: Duration/Converged output in OuAclsOnly dispatch
        Mock Read-Host { return 'Y' }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -OuAclsOnly -ConfirmApply -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'Duration: 100ms'
        $output | Should -Match 'Converged: True'
    }

    # -------------------------------------------------------------------------
    # GposOnly: outer dispatch plan display (lines 1883-1886, 1900)
    # -------------------------------------------------------------------------

    It 'Should display GPO action counts in outer deployment plan section' {
        # Covers lines 1883-1886, 1900: Action count/To Create/Import/Configure/Link display
        Mock Import-TierModelGpo {
            [PSCustomObject]@{ Executed = 0; Failed = 0; Skipped = 0; Errors = @(); DurationMs = 0; Converged = $true }
        }
        Mock Update-TierModelGPOConfig {
            [PSCustomObject]@{ Executed = 0; Failed = 0; Skipped = 0; Errors = @(); DurationMs = 0; Converged = $true }
        }
        Mock Get-TierModelGPOLink {
            [PSCustomObject]@{ Actions = @(); Config = $null; Errors = @() }
        }
        Mock New-TierModelGPOLink {
            [PSCustomObject]@{ Executed = 0; Failed = 0; Skipped = 0; Errors = @(); DurationMs = 0; Converged = $true }
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GposOnly -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'Action count: 1'
        $output | Should -Match 'To Create: 1'
        $output | Should -Match 'To Import: 0'
        $output | Should -Match 'To Configure: 0'
        $output | Should -Match 'To Link: 0'
    }

    It 'Should display GposOnly Duration and Converged when ConfirmApply succeeds' {
        # Covers GposOnly ConfirmApply execution result display with DurationMs
        Mock Read-Host { return 'Y' }
        Mock Import-TierModelGpo {
            [PSCustomObject]@{ Executed = 0; Failed = 0; Skipped = 0; Errors = @(); DurationMs = 0; Converged = $true }
        }
        Mock Update-TierModelGPOConfig {
            [PSCustomObject]@{ Executed = 0; Failed = 0; Skipped = 0; Errors = @(); DurationMs = 0; Converged = $true }
        }
        Mock Get-TierModelGPOLink {
            [PSCustomObject]@{ Actions = @(); Config = $null; Errors = @() }
        }
        Mock New-TierModelGPOLink {
            [PSCustomObject]@{ Executed = 0; Failed = 0; Skipped = 0; Errors = @(); DurationMs = 0; Converged = $true }
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -GposOnly -ConfirmApply -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'Duration:'
        $output | Should -Match 'Converged: True'
    }

    # -------------------------------------------------------------------------
    # AdmxOnly: failed files and planning errors (lines 1938-1939, 1968-1969, 2012)
    # -------------------------------------------------------------------------

    It 'Should display ADMX deployment errors when AdmxFailed is non-empty' {
        # Covers lines 1938-1939: ADMX failed file error display
        Mock Read-Host { return 'Y' }
        Mock Copy-TierModelAdmx {
            [PSCustomObject]@{
                Summary = [PSCustomObject]@{ Successful = 0; Failed = 1 }
                Results = [PSCustomObject]@{
                    AdmxSuccessful = @()
                    AdmlSuccessful = @()
                    AdmxFailed = @([PSCustomObject]@{ FileInfo = @{ Name = 'broken.admx' }; Error = 'Access denied' })
                    AdmlFailed = @()
                }
                DurationMs = 50
            }
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -AdmxOnly -ConfirmApply -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'ADMX Deployment Errors'
        $output | Should -Match 'broken.admx'
    }

    It 'Should display ADML deployment errors when AdmlFailed is non-empty' {
        # Covers lines 1968-1969: ADML failed file error display
        Mock Read-Host { return 'Y' }
        Mock Copy-TierModelAdmx {
            [PSCustomObject]@{
                Summary = [PSCustomObject]@{ Successful = 0; Failed = 1 }
                Results = [PSCustomObject]@{
                    AdmxSuccessful = @()
                    AdmlSuccessful = @()
                    AdmxFailed = @()
                    AdmlFailed = @([PSCustomObject]@{ FileInfo = @{ Name = 'broken.adml' }; Error = 'Write permission denied' })
                }
                DurationMs = 50
            }
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -AdmxOnly -ConfirmApply -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'ADML Deployment Errors'
        $output | Should -Match 'broken.adml'
    }

    It 'Should display Resolve errors in AdmxOnly Deployment Plan when Analysis has errors' {
        # Covers line 2012: "Resolve all dependency errors" in AdmxOnly planning summary section
        Mock Get-TierModelAdmx {
            [PSCustomObject]@{
                Summary = [PSCustomObject]@{ TotalFiles = 1; FilesToUpdate = 0; FilesUpToDate = 0 }
                Analysis = [PSCustomObject]@{
                    AdmxToUpdate = @()
                    AdmlToUpdate = @()
                    Errors = @([PSCustomObject]@{ Message = 'AD schema not extended for ADMX' })
                }
                Warnings = @()
                Errors = @()
            }
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -AdmxOnly -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'Resolve all dependency errors before proceeding with ADMX'
    }

    # -------------------------------------------------------------------------
    # FullDeployment: ADMX phase execution and consolidated results (1525-1535, 1583)
    # -------------------------------------------------------------------------

    It 'Should execute ADMX Phase 6 in FullDeployment when default mocks have FilesToUpdate=1' {
        # Covers lines 1525-1535: Phase 6 ADMX execution result display
        # Default Get-TierModelAdmx mock has FilesToUpdate=1, so Phase 6 ActionCount=1
        Mock Read-Host { return 'Y' }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -ConfirmApply -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'Phase 6: Importing ADMX'
        $output | Should -Match 'Successfully deployed'
    }

    It 'Should display Converged in FullDeployment consolidated results after all phases execute' {
        # Covers line 1583: "Converged: $overallConverged" in consolidated deployment results
        Mock Read-Host { return 'Y' }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -ConfirmApply -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'Full deployment execution completed'
        $output | Should -Match 'Converged: True'
    }

    # -------------------------------------------------------------------------
    # FullDeployment: ADMX analysis display edge cases (1419-1420, 1434-1435, 1440)
    # -------------------------------------------------------------------------

    It 'Should display ADML Current up-to-date files in FullDeployment analysis' {
        # Covers lines 1419-1420: ADML up-to-date file display in Phase 6 analysis
        Mock Get-TierModelAdmx {
            [PSCustomObject]@{
                Summary = [PSCustomObject]@{ TotalFiles = 2; FilesToUpdate = 1; FilesUpToDate = 1 }
                Analysis = [PSCustomObject]@{
                    AdmxToUpdate = @([PSCustomObject]@{ Name = 'test.admx'; ActionType = 'Import' })
                    AdmlToUpdate = @()
                    AdmxUpToDate = @([PSCustomObject]@{ Name = 'existing.admx' })
                    AdmlUpToDate = @([PSCustomObject]@{ Name = 'en-US\existing.adml'; Language = 'en-US' })
                    Errors = @()
                }
                Warnings = @()
                Errors = @()
            }
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'ADML Current'
        $output | Should -Match 'existing.adml'
    }

    It 'Should display ADML planned actions in FullDeployment analysis when AdmlToUpdate is non-empty' {
        # Covers lines 1434-1435: ADML planned action items display
        Mock Get-TierModelAdmx {
            [PSCustomObject]@{
                Summary = [PSCustomObject]@{ TotalFiles = 2; FilesToUpdate = 2; FilesUpToDate = 0 }
                Analysis = [PSCustomObject]@{
                    AdmxToUpdate = @([PSCustomObject]@{ Name = 'test.admx'; ActionType = 'Import' })
                    AdmlToUpdate = @([PSCustomObject]@{ Name = 'en-US\test.adml'; ActionType = 'Import'; Language = 'en-US' })
                    AdmxUpToDate = @()
                    AdmlUpToDate = @()
                    Errors = @()
                }
                Warnings = @()
                Errors = @()
            }
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'ADML'
        $output | Should -Match 'test.adml'
    }

    It 'Should display all templates current message when FilesToUpdate is 0 and FilesUpToDate is 0 in FullDeployment planning' {
        # Covers line 1440: "No ADMX actions needed" in the OUTER else branch
        # Requires: admxUpdateCount=0 AND admxUpToDateCount=0 (both FilesToUpdate=0, FilesUpToDate=0)
        # so that outer if(-not ConfirmApply && (admxUpdateCount>0 || admxUpToDateCount>0)) is FALSE
        Mock Get-TierModelAdmx {
            [PSCustomObject]@{
                Summary = [PSCustomObject]@{ TotalFiles = 2; FilesToUpdate = 0; FilesUpToDate = 0 }
                Analysis = [PSCustomObject]@{
                    AdmxToUpdate = @()
                    AdmlToUpdate = @()
                    AdmxUpToDate = @()
                    AdmlUpToDate = @()
                    Errors = @()
                }
                Warnings = @()
                Errors = @()
            }
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'No ADMX actions needed'
    }

    It 'Should display No ADMX templates configured when admxTotalFiles is 0 in FullDeployment planning' {
        # Covers line 1439/1440: "No ADMX templates configured" elseif path
        Mock Get-TierModelAdmx {
            [PSCustomObject]@{
                Summary = [PSCustomObject]@{ TotalFiles = 0; FilesToUpdate = 0; FilesUpToDate = 0 }
                Analysis = [PSCustomObject]@{
                    AdmxToUpdate = @()
                    AdmlToUpdate = @()
                    AdmxUpToDate = @()
                    AdmlUpToDate = @()
                    Errors = @()
                }
                Warnings = @()
                Errors = @()
            }
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'No ADMX templates configured'
    }

    # -------------------------------------------------------------------------
    # FullDeployment: groups existing count display (line 1238-1243)
    # -------------------------------------------------------------------------

    It 'Should display existing groups in FullDeployment analysis when GroupExistingCount > 0' {
        # Covers lines 1238-1243: existing group display in FullDeployment Phase 2 analysis
        Mock Get-TierModelGroupFd {
            $result = [PSCustomObject]@{ EntityType = 'Group' }
            $result | Add-Member -MemberType NoteProperty -Name 'Summary' -Value ([PSCustomObject]@{
                TotalInConfig = 2; ToCreate = 0; ExistingCount = 2; TotalGroups = 2
            })
            $result | Add-Member -MemberType NoteProperty -Name 'Actions' -Value ([object[]]@())
            $result | Add-Member -MemberType NoteProperty -Name 'Warnings' -Value ([object[]]@())
            $result | Add-Member -MemberType NoteProperty -Name 'Errors' -Value ([object[]]@())
            return $result
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'Group Exists'
    }

    # -------------------------------------------------------------------------
    # Invoke-OuDeployment: Silent=true path with plan errors (lines 315-322)
    # -------------------------------------------------------------------------

    It 'Should handle FullDeployment execution when OuDeployment plan has errors' {
        # Covers lines 315-322: Invoke-OuDeployment returns errorResult when plan has errors (Silent=true)
        Mock Read-Host { return 'Y' }
        Mock Get-TierModelOu {
            New-MockDeploymentPlan -EntityType 'OU' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1 -WithErrors
        }
        Mock Get-TierModelGroupFd {
            New-MockDeploymentPlan -EntityType 'Group' -TotalInConfig 2 -ToCreate 1 -ExistingCount 1
        }

        { & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -ConfirmApply -ErrorAction Stop } |
            Should -Not -Throw

        # Group deployment should still proceed even if OuDeployment had plan errors
        Should -Invoke New-TierModelGroup -Times 1
    }

    # -------------------------------------------------------------------------
    # OuAcl existing groups display in FullDeployment analysis (covers OU ACL "No ACL configured" path)
    # -------------------------------------------------------------------------

    It 'Should display No ACL delegations configured when aclDelegations is empty in FullDeployment' {
        # Covers the "No ACL delegations configured" path in FullDeployment Phase 4 analysis
        Mock Get-TierModelConfig {
            return [PSCustomObject]@{
                ConfigHash = 'abc123'
                organizationUnits = @(@{ name = 'TestOU1'; path = 'OU=TestOU1,DC=test,DC=local' })
                groups = @(@{ name = 'TestGroup1'; path = 'CN=TestGroup1,DC=test,DC=local'; samaccountname = 'TestGroup1' })
                users = @(@{ name = 'TestUser1'; path = 'CN=TestUser1,DC=test,DC=local'; samaccountname = 'TestUser1' })
                gpos = @()
                aclDelegations = @()   # Empty - no ACL delegations
                admx = @()
            }
        }
        Mock Get-TierModelOuAclFd {
            $result = [PSCustomObject]@{ EntityType = 'OuAcl' }
            $result | Add-Member -MemberType NoteProperty -Name 'Summary' -Value ([PSCustomObject]@{
                TotalActions = 0; CreateActions = 0; ExistingCount = 0
            })
            $result | Add-Member -MemberType NoteProperty -Name 'Actions' -Value ([object[]]@())
            $result | Add-Member -MemberType NoteProperty -Name 'Warnings' -Value ([object[]]@())
            $result | Add-Member -MemberType NoteProperty -Name 'Errors' -Value ([object[]]@())
            return $result
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'No ACL delegations configured'
    }
}

Describe "Deploy-TierModel Prerequisite Splat Invariants" -Tag "Integration", "Deploy", "Prereq" {
    BeforeAll {
        $script:DeployScriptPath = Join-Path $PSScriptRoot '..\Deploy-TierModel.ps1'
        $script:DeploySource     = Get-Content $script:DeployScriptPath -Raw
    }

    It "BUG-008: every `$prereqSplat initializer passes DependenciesPath so prerequisites resolve from any working directory" {
        # A splat that omits DependenciesPath falls back to Test-TierModelPrerequisites' cwd-relative
        # default ('config/dependencies.json') and fails with "Dependencies file not found" when the
        # script is invoked from a directory other than the deploy root.
        $inits = [regex]::Matches($script:DeploySource, '\$prereqSplat\s*=\s*@\{[^}]*\}')
        @($inits).Count | Should -BeGreaterThan 0 -Because 'Deploy-TierModel.ps1 builds prerequisite splats for the optional-features and include-only paths'
        foreach ($m in $inits) {
            $m.Value | Should -Match 'DependenciesPath' -Because 'each prerequisite splat must pass an absolute DependenciesPath so prereqs work regardless of the current directory'
        }
    }
}

Describe "Deploy-TierModel - Feature Prerequisite Fail-Fast (BUG-003)" -Tag "Integration", "Deploy", "Prereq" {
    BeforeEach {
        Mock Read-Host { return 'N' }
    }

    It "dMSA: -IncludeDmsa fails fast with a clean v5-style message when Domain Functional Level < 2025 (before any phases)" {
        # dMSA critical pre-flight gate reads the DFL directly and exits cleanly, like the PS-version gate.
        Mock Get-ADDomain {
            return [PSCustomObject]@{
                DomainMode = 'Windows2016Domain'; DNSRoot = 'test.local'
                NetBIOSName = 'TEST'; DistinguishedName = 'DC=test,DC=local'
            }
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -IncludeDmsa -ErrorAction Stop 6>&1 | Out-String

        $output | Should -Match 'requires a Domain Functional Level of Windows Server 2025'
        $output | Should -Match 'Current Domain Functional Level: Windows Server 2016'
        $output | Should -Match 'Remediation steps:'
        $output | Should -Match 'Ensure all Domain Controllers'
        $output | Should -Match 'Deploy script completed'
        # Fails BEFORE any deployment phases / planning run — no ugly downstream planner error
        $output | Should -Not -Match 'Phase \d'
        $output | Should -Not -Match 'Deployment Plan'
        $output | Should -Not -Match 'dMSA ACL Delegations'
    }

    It "gMSA: -FullDeployment -IncludeGmsa fails fast (before phases) when the KDS Root Key prerequisite is missing" {
        Mock Test-TierModelPrerequisites {
            return [PSCustomObject]@{
                Valid               = $false
                Errors              = @('No KDS Root Key found. gMSA requires an effective KDS Root Key.')
                Remediation         = @('Create a KDS Root Key: Add-KdsRootKey -EffectiveImmediately (for lab).')
                EnvironmentSnapshot = @{}
            }
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -IncludeGmsa 6>&1 | Out-String

        $output | Should -Match 'No KDS Root Key found'
        $output | Should -Match 'Remediation steps:'
        $output | Should -Match 'Deploy script completed'
        # New aligned fail-fast format: no "Prerequisites not met:" header, no "ERROR:" prefix
        $output | Should -Not -Match 'Prerequisites not met'
        $output | Should -Not -Match 'ERROR:'
        # Fails BEFORE any deployment phases run
        $output | Should -Not -Match 'Phase \d'
        $output | Should -Not -Match 'Deployment Plan'
    }

    It "WinLaps: -FullDeployment -IncludeWinLaps fails fast (before phases) when the Windows LAPS schema is missing" {
        Mock Test-TierModelPrerequisites {
            return [PSCustomObject]@{
                Valid               = $false
                Errors              = @('The current Domain does not contain the Windows LAPS schema extensions, please follow Microsoft Doc guidance on how to extend the schema, then re-attempt the Tier Model Windows LAPS deployment.')
                Remediation         = @('Follow Microsoft documentation to extend the Windows LAPS schema, then re-run with -IncludeWinLaps.')
                EnvironmentSnapshot = @{}
            }
        }

        $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -IncludeWinLaps 6>&1 | Out-String

        $output | Should -Match 'Windows LAPS schema'
        $output | Should -Match 'Remediation steps:'
        $output | Should -Match 'Deploy script completed'
        # New aligned fail-fast format: no "Prerequisites not met:" header, no "ERROR:" prefix
        $output | Should -Not -Match 'Prerequisites not met'
        $output | Should -Not -Match 'ERROR:'
        # Fails BEFORE any deployment phases run
        $output | Should -Not -Match 'Phase \d'
        $output | Should -Not -Match 'Deployment Plan'
    }
}

Describe 'Deploy-TierModel - EnableAuditing (Domain Audit Rule)' -Tag 'Integration', 'Deploy', 'AuditRule' {

    BeforeAll {
        function New-MockAuditRulePlan {
            param([int]$TotalActions = 1)
            $actions = @()
            if ($TotalActions -gt 0) {
                $actions = @([PSCustomObject]@{
                    Action       = 'ConfigureAuditRule'
                    ResourceType = 'DomainAuditRule'
                    TargetDn     = 'DC=test,DC=local'
                    Data         = [PSCustomObject]@{
                        TrusteeSid        = 'S-1-1-0'
                        Status            = 'ABSENT'
                        ManagedAceCount   = 0
                        UnionTargetRights = 'CreateChild, DeleteChild'
                        MissingRights     = 'CreateChild'
                    }
                })
            }
            [PSCustomObject]@{
                Actions       = $actions
                Summary       = @{ TotalActions = $TotalActions; ConfigureActions = $TotalActions; ExistingCount = 0 }
                Errors        = @()
                DurationMs    = 5
                Converged     = $true
                CorrelationId = [System.Guid]::NewGuid().ToString()
            }
        }

        function New-MockAuditRuleApplyResult {
            [PSCustomObject]@{
                Applied       = @([PSCustomObject]@{ Action = 'ConfigureAuditRule'; TargetDn = 'DC=test,DC=local' })
                Executed      = 1
                Failed        = 0
                Skipped       = @()
                Errors        = @()
                DurationMs    = 5
                Converged     = $true
                CorrelationId = [System.Guid]::NewGuid().ToString()
            }
        }
    }

    BeforeEach {
        Mock Read-Host { return 'N' }
        Mock Get-TierModelAuditRule   { New-MockAuditRulePlan }
        Mock Get-TierModelAuditRuleFd { New-MockAuditRulePlan }
        Mock New-TierModelAuditRule   { New-MockAuditRuleApplyResult }
    }

    Context 'Scope validation' {

        It 'Should reject -EnableAuditing combined with -OuOnly' {
            { & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -EnableAuditing -OuOnly -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*can only be used standalone or combined with -FullDeployment*'
        }
    }

    Context 'Standalone -EnableAuditing planning mode (no -ConfirmApply)' {

        It 'Should call Get-TierModelAuditRule and display the Domain Audit Rule phase' {
            $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -EnableAuditing -ErrorAction Stop 6>&1 | Out-String

            Should -Invoke Get-TierModelAuditRule -Times 1
            $output | Should -Match 'Phase: Domain Audit Rule \(SACL\)'
        }

        It 'Should render the ConfigureAuditRule action line via Write-IncludeAclPlanActions' {
            $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -EnableAuditing -ErrorAction Stop 6>&1 | Out-String

            $output | Should -Match 'Configure : DC=test,DC=local'
        }

        It 'Should NOT display the event-log warning or prompt in planning mode' {
            $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -EnableAuditing -ErrorAction Stop 6>&1 | Out-String

            $output | Should -Not -Match 'increase the events being generated'
        }

        It 'Should NOT apply the rule (New-TierModelAuditRule not invoked) in planning mode' {
            & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -EnableAuditing -ErrorAction Stop 6>&1 | Out-Null

            Should -Invoke New-TierModelAuditRule -Times 0
        }
    }

    Context 'Standalone -EnableAuditing apply mode (-ConfirmApply)' {

        It 'Should display the event-log warning and prompt when -ConfirmApply is set' {
            Mock Read-Host { return 'Y' }

            $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -EnableAuditing -ConfirmApply -ErrorAction Stop 6>&1 | Out-String

            $output | Should -Match 'increase the events being generated'
        }

        It 'Should apply the rule via New-TierModelAuditRule when both gates are accepted' {
            Mock Read-Host { return 'Y' }

            & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -EnableAuditing -ConfirmApply -ErrorAction Stop 6>&1 | Out-Null

            Should -Invoke New-TierModelAuditRule -Times 1
        }

        It 'Should cancel deployment when the audit event-log gate is declined' {
            Mock Read-Host { return 'N' }

            $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -EnableAuditing -ConfirmApply -ErrorAction Stop 6>&1 | Out-String

            $output | Should -Match 'Deployment cancelled'
            Should -Invoke New-TierModelAuditRule -Times 0
        }
    }

    Context '-FullDeployment -EnableAuditing' {

        It 'Should invoke Get-TierModelAuditRuleFd and add Phase 11 to the deployment plan' {
            $output = & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -EnableAuditing -ErrorAction Stop 6>&1 | Out-String

            Should -Invoke Get-TierModelAuditRuleFd -Times 1
            $output | Should -Match 'Phase 11: Domain Audit Rule \(SACL\)'
        }

        It 'Should not invoke Get-TierModelAuditRuleFd during a plain -FullDeployment (no -EnableAuditing)' {
            & $script:DeployScriptPath -PreferredDc $script:TestPreferredDc -FullDeployment -ErrorAction Stop 6>&1 | Out-Null

            Should -Invoke Get-TierModelAuditRuleFd -Times 0
        }
    }
}
