<#
.SYNOPSIS
Unit tests for TierModel.psm1 inline functions.

.DESCRIPTION
Comprehensive Pester v5 tests for the functions defined directly inside TierModel.psm1:
  - Get-TierModelConfigHash  (private — accessed via InModuleScope)
  - Get-TierModel             (exported)
  - Test-TierModelConfig      (exported — FromPath and FromConfig parameter sets)
  - Get-TierModelPlan         (exported)
  - New-TierModel             (private — via InModuleScope)
  - Set-TierModel             (private — via InModuleScope)
  - Test-TierModelDrift       (private — via InModuleScope)

.NOTES
Tags: Unit, TierModelModule
Coverage target: TierModel.psm1

Scope notes:
  * FullDeployment + FromPath throws because tiermodel.schema.json has no 'admx' property
    but Set-StrictMode -Version Latest causes $schema.properties.admx to throw.
  * Use OuOnly scope (or FromConfig) for tests that must avoid the ADMX schema lookup.
  * Deep validation (GPO modes, denyApplyGroups, ADMX paths, OU parent-child) is always
    outside the FromPath schema block, so FromConfig reaches it safely.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    $script:ModuleRoot   = Join-Path $PSScriptRoot '..' 'modules' 'TierModel'
    $script:ManifestPath = Join-Path $script:ModuleRoot 'TierModel.psd1'
    $script:ConfigDir    = Join-Path $PSScriptRoot '..' 'config'
    $script:SchemaPath   = Join-Path $script:ConfigDir 'tiermodel.schema.json'
    $script:EmptyConfig  = Join-Path $PSScriptRoot 'testdata' 'test-empty.json'
    $script:UnitConfig   = Join-Path $script:ConfigDir 'tiermodel.unittest.json'

    Remove-Module TierModel -Force -ErrorAction SilentlyContinue
    Import-Module $script:ManifestPath -Force

    # Silence module-internal logging throughout all tests
    Mock Write-TierModelLog { } -ModuleName TierModel
}

AfterAll {
    Remove-Module TierModel -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Get-TierModelConfigHash  (private helper — tested via InModuleScope)
# =============================================================================
Describe 'Get-TierModelConfigHash' -Tag 'Unit', 'TierModelModule', 'ConfigHash' {

    It 'returns a 64-character hex SHA-256 string for a valid file' {
        $hash = InModuleScope TierModel -Parameters @{ p = $script:EmptyConfig } {
            param($p)
            Get-TierModelConfigHash -Path $p
        }
        $hash | Should -Match '^[0-9a-f]{64}$'
    }

    It 'produces a deterministic hash for the same file' {
        $h1 = InModuleScope TierModel -Parameters @{ p = $script:EmptyConfig } {
            param($p) Get-TierModelConfigHash -Path $p
        }
        $h2 = InModuleScope TierModel -Parameters @{ p = $script:EmptyConfig } {
            param($p) Get-TierModelConfigHash -Path $p
        }
        $h1 | Should -Be $h2
    }

    It 'throws when the file does not exist' {
        $missing = 'C:\DoesNotExist\non-existent-config.json'
        {
            InModuleScope TierModel -Parameters @{ p = $missing } {
                param($p)
                Get-TierModelConfigHash -Path $p
            }
        } | Should -Throw '*Config file not found*'
    }
}

# =============================================================================
# Get-TierModel  (exported)
# =============================================================================
Describe 'Get-TierModel' -Tag 'Unit', 'TierModelModule', 'GetTierModel' {

    It 'parses JSON and returns a PSCustomObject with a version property' {
        $result = Get-TierModel -Path $script:EmptyConfig
        $result | Should -Not -BeNullOrEmpty
        $result.version | Should -Be '1.0.0'
    }

    It 'returns an object where empty collections have zero items' {
        $result = Get-TierModel -Path $script:EmptyConfig
        @($result.organizationUnits).Count | Should -Be 0
        @($result.groups).Count            | Should -Be 0
    }

    It 'returns the raw JSON string when -Raw is specified' {
        $result = Get-TierModel -Path $script:EmptyConfig -Raw
        $result | Should -BeOfType 'string'
        $result | Should -Match '"version"'
        $result | Should -Match '"organizationUnits"'
    }

    It 'parses a config with content and reflects counts' {
        $result = Get-TierModel -Path $script:UnitConfig
        $result.organizationUnits.Count | Should -BeGreaterThan 0
        $result.groups.Count            | Should -BeGreaterThan 0
    }
}

# =============================================================================
# Test-TierModelConfig  (exported)
# =============================================================================
Describe 'Test-TierModelConfig' -Tag 'Unit', 'TierModelModule', 'TestTierModelConfig' {

    # ── FromPath error paths ─────────────────────────────────────────────────

    Context 'FromPath — config file not found' {
        It 'throws when the config path does not exist' {
            $missing = 'C:\DoesNotExist\config.json'
            { Test-TierModelConfig -Path $missing -SchemaPath $script:SchemaPath } |
                Should -Throw '*Config file not found*'
        }
    }

    Context 'FromPath — schema file not found' {
        It 'throws when the schema path does not exist' {
            { Test-TierModelConfig -Path $script:EmptyConfig -SchemaPath 'C:\NoSchema\schema.json' } |
                Should -Throw '*Schema file not found*'
        }
    }

    Context 'FromPath — invalid JSON' {
        BeforeAll {
            $script:InvalidJsonFile = Join-Path $env:TEMP "tm-invalid-json-$([guid]::NewGuid()).json"
            'this is { not : valid json ;;' | Set-Content $script:InvalidJsonFile
        }
        AfterAll {
            Remove-Item $script:InvalidJsonFile -Force -ErrorAction SilentlyContinue
        }

        It 'returns Valid=$false and an error describing the JSON failure' {
            $result = Test-TierModelConfig -Path $script:InvalidJsonFile -SchemaPath $script:SchemaPath
            $result.Valid               | Should -Be $false
            ($result.Errors -join ' ')  | Should -Match 'Invalid JSON'
        }
    }

    # ── FromPath happy path — empty config, OuOnly scope ────────────────────
    # NOTE: FullDeployment + FromPath throws because tiermodel.schema.json has no
    # 'admx' in properties — StrictMode causes $schema.properties.admx to throw.
    # OuOnly skips the ADMX schema lookup so the happy path works correctly.

    Context 'FromPath — valid empty config, OuOnly scope' {
        BeforeAll {
            $script:EmptyResult = Test-TierModelConfig -Path $script:EmptyConfig -SchemaPath $script:SchemaPath -Scope OuOnly
        }

        It 'returns Valid=$true' {
            $script:EmptyResult.Valid | Should -Be $true
        }

        It 'Errors array is empty' {
            $script:EmptyResult.Errors.Count | Should -Be 0
        }

        It 'returns a CorrelationId GUID' {
            $script:EmptyResult.CorrelationId | Should -Match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        }

        It 'returns Path and SchemaPath' {
            $script:EmptyResult.Path       | Should -Be $script:EmptyConfig
            $script:EmptyResult.SchemaPath | Should -Be $script:SchemaPath
        }

        It 'returns a Timestamp' {
            $script:EmptyResult.Timestamp | Should -Not -BeNullOrEmpty
        }

        It 'returns a ConfigHash (64-char hex)' {
            $script:EmptyResult.ConfigHash | Should -Match '^[0-9a-f]{64}$'
        }

        It 'returns a ValidationDetails object' {
            $script:EmptyResult.ValidationDetails | Should -Not -BeNullOrEmpty
        }
    }

    # ── -Raw flag ─────────────────────────────────────────────────────────────
    # Uses OuOnly scope to avoid the ADMX schema property issue with FullDeployment.

    Context 'FromPath — -Raw flag' {
        It 'returns a JSON string containing Valid and ConfigHash when -Raw is specified' {
            $result = Test-TierModelConfig -Path $script:EmptyConfig -SchemaPath $script:SchemaPath -Scope OuOnly -Raw
            $result | Should -BeOfType 'string'
            $result | Should -Match '"Valid"'
            $result | Should -Match '"ConfigHash"'
        }
    }

    # ── Scope-based validation ────────────────────────────────────────────────
    # All scopes exercised with FromPath. OuOnly/GroupsOnly/UsersOnly/OuAclsOnly are safe.
    # ImportAdmxOnly would also trigger the ADMX schema lookup and throw, so we use
    # FromConfig for that scope in the ADMX section below.

    Context 'Scope-based validation' {
        It 'OuOnly scope — validates and returns Valid=$true for empty config' {
            $result = Test-TierModelConfig -Path $script:EmptyConfig -SchemaPath $script:SchemaPath -Scope OuOnly
            $result.Valid | Should -Be $true
            $result.ValidationDetails.InvalidGpoModes | Should -Be 0
        }

        It 'GroupsOnly scope — validates and returns a result' {
            $result = Test-TierModelConfig -Path $script:EmptyConfig -SchemaPath $script:SchemaPath -Scope GroupsOnly
            $result | Should -Not -BeNullOrEmpty
        }

        It 'UsersOnly scope — validates and returns a result' {
            $result = Test-TierModelConfig -Path $script:EmptyConfig -SchemaPath $script:SchemaPath -Scope UsersOnly
            $result | Should -Not -BeNullOrEmpty
        }

        It 'OuAclsOnly scope — validates and returns a result' {
            $result = Test-TierModelConfig -Path $script:EmptyConfig -SchemaPath $script:SchemaPath -Scope OuAclsOnly
            $result | Should -Not -BeNullOrEmpty
        }
    }

    # ── Missing required top-level property ──────────────────────────────────
    # Uses OuOnly scope — schema.required check always runs but the problematic
    # ADMX schema lookup is only triggered for FullDeployment/ImportAdmxOnly.

    Context 'FromPath — missing required top-level property (gpos)' {
        BeforeAll {
            $script:MissingPropFile = Join-Path $env:TEMP "tm-missingprop-$([guid]::NewGuid()).json"
            @{ version = '1.0.0'; organizationUnits = @(); groups = @(); users = @() } |
                ConvertTo-Json -Depth 5 | Set-Content $script:MissingPropFile
        }
        AfterAll {
            Remove-Item $script:MissingPropFile -Force -ErrorAction SilentlyContinue
        }

        It 'returns Valid=$false with a "Missing required top-level property" error' {
            $result = Test-TierModelConfig -Path $script:MissingPropFile -SchemaPath $script:SchemaPath -Scope OuOnly
            $result.Valid | Should -Be $false
            ($result.Errors -join ' ') | Should -Match 'Missing required top-level'
        }
    }

    # ── Invalid version pattern ───────────────────────────────────────────────

    Context 'FromPath — invalid version pattern' {
        BeforeAll {
            $script:BadVersionFile = Join-Path $env:TEMP "tm-badver-$([guid]::NewGuid()).json"
            @{
                version           = 'not-semver'
                organizationUnits = @()
                groups            = @()
                users             = @()
                gpos              = @()
            } | ConvertTo-Json -Depth 5 | Set-Content $script:BadVersionFile
        }
        AfterAll {
            Remove-Item $script:BadVersionFile -Force -ErrorAction SilentlyContinue
        }

        It 'returns Valid=$false and a semantic-pattern error' {
            $result = Test-TierModelConfig -Path $script:BadVersionFile -SchemaPath $script:SchemaPath -Scope OuOnly
            $result.Valid | Should -Be $false
            ($result.Errors -join ' ') | Should -Match 'does not match semantic pattern'
        }
    }

    # ── GPO mode deep validation ──────────────────────────────────────────────
    # Uses FromConfig to bypass the FromPath schema block (which throws for ADMX).
    # GPO mode deep validation is outside the schema block and runs for FullDeployment.

    Context 'GPO mode validation' {

        It 'accepts createAndImport and createImportAndConfigure modes' {
            $cfg = [PSCustomObject]@{
                gpos = @(
                    [PSCustomObject]@{ name = 'GPO1'; mode = 'createAndImport' }
                    [PSCustomObject]@{ name = 'GPO2'; mode = 'createImportAndConfigure' }
                )
            }
            $result = Test-TierModelConfig -Config $cfg -Scope FullDeployment
            $result.Valid | Should -Be $true
            $result.ValidationDetails.ValidGpoModes   | Should -Be 2
            $result.ValidationDetails.InvalidGpoModes | Should -Be 0
        }

        It 'returns an error for an invalid GPO mode' {
            $cfg = [PSCustomObject]@{
                gpos = @( [PSCustomObject]@{ name = 'BadGPO'; mode = 'badMode' } )
            }
            $result = Test-TierModelConfig -Config $cfg -Scope FullDeployment
            $result.Valid | Should -Be $false
            ($result.Errors -join ' ')                | Should -Match 'invalid mode'
            $result.ValidationDetails.InvalidGpoModes | Should -BeGreaterThan 0
        }

        It 'returns an error when mode property is absent' {
            $cfg = [PSCustomObject]@{
                gpos = @( [PSCustomObject]@{ name = 'NoModeGPO' } )
            }
            $result = Test-TierModelConfig -Config $cfg -Scope FullDeployment
            $result.Valid | Should -Be $false
            ($result.Errors -join ' ') | Should -Match "missing required 'mode'"
        }

        It 'OuOnly scope skips GPO mode validation (InvalidGpoModes stays 0)' {
            $cfg = [PSCustomObject]@{
                gpos = @( [PSCustomObject]@{ name = 'BadGPO'; mode = 'badMode' } )
            }
            $result = Test-TierModelConfig -Config $cfg -Scope OuOnly
            $result.ValidationDetails.InvalidGpoModes | Should -Be 0
        }
    }

    # ── DenyApplyGroups reference validation ──────────────────────────────────

    Context 'DenyApplyGroups reference validation' {

        It 'warns when denyApplyGroup references a group not in config' {
            $cfg = [PSCustomObject]@{
                groups = @( [PSCustomObject]@{ name = 'ExistingGroup'; scope = 'Global' } )
                gpos   = @(
                    [PSCustomObject]@{
                        name            = 'TestGPO'
                        mode            = 'createAndImport'
                        denyApplyGroups = @('ExistingGroup', 'NonExistentGroup')
                    }
                )
            }
            $result = Test-TierModelConfig -Config $cfg -Scope FullDeployment
            $result.Warnings.Count | Should -BeGreaterThan 0
            ($result.Warnings -join ' ') | Should -Match 'NonExistentGroup'
        }

        It 'counts valid and invalid denyApplyGroup references' {
            $cfg = [PSCustomObject]@{
                groups = @( [PSCustomObject]@{ name = 'ExistingGroup'; scope = 'Global' } )
                gpos   = @(
                    [PSCustomObject]@{
                        name            = 'TestGPO'
                        mode            = 'createAndImport'
                        denyApplyGroups = @('ExistingGroup', 'NonExistentGroup')
                    }
                )
            }
            $result = Test-TierModelConfig -Config $cfg -Scope FullDeployment
            $result.ValidationDetails.ValidDenyApplyGroups   | Should -Be 1
            $result.ValidationDetails.InvalidDenyApplyGroups | Should -Be 1
        }
    }

    # ── ADMX path validation ──────────────────────────────────────────────────
    # All ADMX tests use FromConfig + ImportAdmxOnly.
    # ImportAdmxOnly + FromPath would hit $schema.properties.admx (not in schema) and throw.
    # ImportAdmxOnly + FromConfig skips the schema block entirely and runs only deep validation.

    Context 'ADMX path validation — non-existent path' {

        It 'adds an error when the ADMX source path does not exist' {
            $cfg = [PSCustomObject]@{
                admx = @( [PSCustomObject]@{ path = 'C:\NonExistentAdmxPath\DoesNotExist'; language = 'en-US' } )
            }
            $result = Test-TierModelConfig -Config $cfg -Scope ImportAdmxOnly
            $result.Valid | Should -Be $false
            ($result.Errors -join ' ')                   | Should -Match 'does not exist'
            $result.ValidationDetails.InvalidAdmxPaths   | Should -BeGreaterThan 0
        }

        It 'adds an error when an ADMX entry has no path property' {
            $cfg = [PSCustomObject]@{
                admx = @( [PSCustomObject]@{ language = 'en-US' } )
            }
            $result = Test-TierModelConfig -Config $cfg -Scope ImportAdmxOnly
            $result.Valid | Should -Be $false
            ($result.Errors -join ' ') | Should -Match "missing required 'path'"
        }

        It 'OuOnly scope skips ADMX validation (InvalidAdmxPaths stays 0)' {
            $cfg = [PSCustomObject]@{
                admx = @( [PSCustomObject]@{ path = 'C:\NonExistentAdmxPath'; language = 'en-US' } )
            }
            $result = Test-TierModelConfig -Config $cfg -Scope OuOnly
            $result.ValidationDetails.InvalidAdmxPaths | Should -Be 0
        }
    }

    Context 'ADMX path validation — real temporary directories' {
        BeforeAll {
            # Valid: directory exists, has .admx file, has en-US subfolder with .adml
            $script:TempAdmxDir = Join-Path $env:TEMP "tm-admxdir-$([guid]::NewGuid())"
            New-Item -ItemType Directory $script:TempAdmxDir -Force | Out-Null
            New-Item -ItemType File      (Join-Path $script:TempAdmxDir 'test.admx') -Force | Out-Null
            $script:TempLocaleDir = Join-Path $script:TempAdmxDir 'en-US'
            New-Item -ItemType Directory $script:TempLocaleDir -Force | Out-Null
            New-Item -ItemType File      (Join-Path $script:TempLocaleDir 'test.adml') -Force | Out-Null

            # No .admx files: use the en-US subdirectory (contains only .adml)
            # No locale folder: separate dir with .admx but no en-US subfolder
            $script:TempAdmxNoLocale = Join-Path $env:TEMP "tm-admxnolocale-$([guid]::NewGuid())"
            New-Item -ItemType Directory $script:TempAdmxNoLocale -Force | Out-Null
            New-Item -ItemType File      (Join-Path $script:TempAdmxNoLocale 'test.admx') -Force | Out-Null
        }
        AfterAll {
            Remove-Item $script:TempAdmxDir      -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $script:TempAdmxNoLocale -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'counts a valid ADMX path when .admx files and locale folder are present' {
            $cfg = [PSCustomObject]@{
                admx = @( [PSCustomObject]@{ path = $script:TempAdmxDir; language = 'en-US' } )
            }
            $result = Test-TierModelConfig -Config $cfg -Scope ImportAdmxOnly
            $result.ValidationDetails.ValidAdmxPaths   | Should -Be 1
            $result.ValidationDetails.InvalidAdmxPaths | Should -Be 0
        }

        It 'adds a warning when the ADMX directory has no .admx files' {
            $cfg = [PSCustomObject]@{
                admx = @( [PSCustomObject]@{ path = $script:TempLocaleDir; language = 'en-US' } )
            }
            $result = Test-TierModelConfig -Config $cfg -Scope ImportAdmxOnly
            $result.Warnings.Count | Should -BeGreaterThan 0
            ($result.Warnings -join ' ') | Should -Match 'no .admx files'
        }

        It 'adds a warning when the locale subfolder is missing' {
            $cfg = [PSCustomObject]@{
                admx = @( [PSCustomObject]@{ path = $script:TempAdmxNoLocale; language = 'en-US' } )
            }
            $result = Test-TierModelConfig -Config $cfg -Scope ImportAdmxOnly
            $result.Warnings.Count | Should -BeGreaterThan 0
            ($result.Warnings -join ' ') | Should -Match 'missing default locale'
        }
    }

    # ── OU parent-child relationship validation ──────────────────────────────
    # Uses FromConfig — always outside the schema block so always runs.

    Context 'OU parent-child relationship validation' {

        It 'warns when an OU references a parent path not defined in config' {
            $cfg = [PSCustomObject]@{
                organizationUnits = @(
                    [PSCustomObject]@{ name = 'ChildOU'; path = 'OU=ChildOU,OU=ParentOU,DC=test,DC=local' }
                )
            }
            $result = Test-TierModelConfig -Config $cfg -Scope OuOnly
            $result.Warnings.Count | Should -BeGreaterThan 0
            ($result.Warnings -join ' ') | Should -Match 'not defined in configuration'
        }

        It 'no parent-undefined warning when all parents are in config' {
            $cfg = [PSCustomObject]@{
                organizationUnits = @(
                    [PSCustomObject]@{ name = 'ParentOU'; path = 'OU=ParentOU,DC=test,DC=local' }
                    [PSCustomObject]@{ name = 'ChildOU';  path = 'OU=ChildOU,OU=ParentOU,DC=test,DC=local' }
                )
            }
            $result = Test-TierModelConfig -Config $cfg -Scope OuOnly
            $parentWarnings = @($result.Warnings | Where-Object { $_ -match 'not defined in configuration' })
            $parentWarnings.Count | Should -Be 0
        }
    }

    # ── FromConfig parameter set ──────────────────────────────────────────────

    Context 'FromConfig parameter set' {
        It 'accepts a PSCustomObject config without requiring file paths' {
            $cfg = [PSCustomObject]@{
                version           = '1.0.0'
                organizationUnits = @()
                groups            = @()
                users             = @()
                gpos              = @()
            }
            $result = Test-TierModelConfig -Config $cfg -Scope FullDeployment
            $result              | Should -Not -BeNullOrEmpty
            $result.CorrelationId | Should -Not -BeNullOrEmpty
        }

        It 'result object has Errors and Warnings properties' {
            $cfg = [PSCustomObject]@{ version = '1.0.0' }
            $result = Test-TierModelConfig -Config $cfg
            $result.PSObject.Properties.Name | Should -Contain 'Errors'
            $result.PSObject.Properties.Name | Should -Contain 'Warnings'
        }

        It 'does not add ConfigHash, Path, or SchemaPath for FromConfig invocations' {
            $cfg = [PSCustomObject]@{ version = '1.0.0' }
            $result = Test-TierModelConfig -Config $cfg
            $result.PSObject.Properties.Name | Should -Not -Contain 'ConfigHash'
            $result.PSObject.Properties.Name | Should -Not -Contain 'Path'
        }

        It 'validates GPO modes from a PSCustomObject config' {
            $cfg = [PSCustomObject]@{
                gpos = @( [PSCustomObject]@{ name = 'G1'; mode = 'createAndImport' } )
            }
            $result = Test-TierModelConfig -Config $cfg -Scope FullDeployment
            $result.ValidationDetails.ValidGpoModes | Should -Be 1
        }
    }

    # ── FromPath — array item missing required sub-property ──────────────────
    # Exercises the _validateArrayItems inner loop (items with missing required fields).

    Context 'FromPath — array item missing required sub-property' {
        BeforeAll {
            # Group item has 'name' but is missing required 'scope'.
            # Using GroupsOnly scope; organizationUnits is empty so the OU
            # parent-child check is skipped (avoids StrictMode crash on $ou.path).
            $script:MissingSubPropFile = Join-Path $env:TEMP "tm-missingsubprop-$([guid]::NewGuid()).json"
            @{
                version           = '1.0.0'
                organizationUnits = @()
                groups            = @( @{ name = 'TestGroup' } )
                users             = @()
                gpos              = @()
            } | ConvertTo-Json -Depth 5 | Set-Content $script:MissingSubPropFile
        }
        AfterAll {
            Remove-Item $script:MissingSubPropFile -Force -ErrorAction SilentlyContinue
        }

        It 'returns Valid=$false and an error naming the missing sub-property' {
            $result = Test-TierModelConfig -Path $script:MissingSubPropFile -SchemaPath $script:SchemaPath -Scope GroupsOnly
            $result.Valid | Should -Be $false
            ($result.Errors -join ' ') | Should -Match "missing required property 'scope'"
        }
    }

    # ── FromPath — version property absent ───────────────────────────────────
    # Covers the else-null branch when config has no 'version' property.

    Context 'FromPath — version property absent in config' {
        BeforeAll {
            $script:NoVersionFile = Join-Path $env:TEMP "tm-noversion-$([guid]::NewGuid()).json"
            @{
                organizationUnits = @()
                groups            = @()
                users             = @()
                gpos              = @()
            } | ConvertTo-Json -Depth 5 | Set-Content $script:NoVersionFile
        }
        AfterAll {
            Remove-Item $script:NoVersionFile -Force -ErrorAction SilentlyContinue
        }

        It 'returns Valid=$false when version property is absent (Missing required top-level)' {
            $result = Test-TierModelConfig -Path $script:NoVersionFile -SchemaPath $script:SchemaPath -Scope OuOnly
            $result.Valid | Should -Be $false
            ($result.Errors -join ' ') | Should -Match 'version'
        }
    }

    # ── GPO mode validation — hashtable config ───────────────────────────────
    # Covers if ($gpo -is [hashtable]) / if ($config -is [hashtable]) branches in
    # deep validation.  Pass a plain hashtable as -Config.

    Context 'GPO mode validation — hashtable config' {

        It 'accepts a valid mode in a hashtable GPO' {
            $cfg = @{ gpos = @( @{ name = 'HT-GPO1'; mode = 'createAndImport' } ) }
            $result = Test-TierModelConfig -Config $cfg -Scope FullDeployment
            $result.ValidationDetails.ValidGpoModes   | Should -Be 1
            $result.ValidationDetails.InvalidGpoModes | Should -Be 0
        }

        It 'detects an invalid mode in a hashtable GPO' {
            $cfg = @{ gpos = @( @{ name = 'HT-BadGPO'; mode = 'badMode' } ) }
            $result = Test-TierModelConfig -Config $cfg -Scope FullDeployment
            $result.Valid | Should -Be $false
            $result.ValidationDetails.InvalidGpoModes | Should -BeGreaterThan 0
        }

        It 'detects a missing mode in a hashtable GPO' {
            $cfg = @{ gpos = @( @{ name = 'HT-NoModeGPO' } ) }
            $result = Test-TierModelConfig -Config $cfg -Scope FullDeployment
            $result.Valid | Should -Be $false
            ($result.Errors -join ' ') | Should -Match "missing required 'mode'"
        }

        It 'returns Unknown GPO name when PSCustomObject GPO has no name property' {
            # The 'Unknown GPO' fallback text is in the PSObject branch (not hashtable).
            # Pass a PSCustomObject without a 'name' property to hit that branch.
            $cfg = [PSCustomObject]@{ gpos = @( [PSCustomObject]@{ mode = 'badMode' } ) }
            $result = Test-TierModelConfig -Config $cfg -Scope FullDeployment
            $result.Valid | Should -Be $false
            ($result.Errors -join ' ') | Should -Match 'Unknown GPO'
        }

        It 'returns $null for the gpos key when hashtable config has no gpos entry' {
            # Covers else-null branch: `if ($config.ContainsKey("gpos")) { ... } else { $null }`
            $cfg = @{ groups = @( @{ name = 'G1'; scope = 'Global' } ) }   # no 'gpos' key
            $result = Test-TierModelConfig -Config $cfg -Scope FullDeployment
            # No GPO-related errors — gpos defaults to null/empty
            $result.ValidationDetails.InvalidGpoModes | Should -Be 0
        }
    }

    # ── DenyApplyGroups validation — hashtable config ────────────────────────

    Context 'DenyApplyGroups reference validation — hashtable config' {

        It 'validates denyApplyGroups when GPO and groups are hashtables' {
            $cfg = @{
                groups = @( @{ name = 'HT-Group1'; scope = 'Global' } )
                gpos   = @( @{ name = 'HT-GPO1'; mode = 'createAndImport'; denyApplyGroups = @('HT-Group1', 'NonExistent') } )
            }
            $result = Test-TierModelConfig -Config $cfg -Scope FullDeployment
            $result.ValidationDetails.ValidDenyApplyGroups   | Should -Be 1
            $result.ValidationDetails.InvalidDenyApplyGroups | Should -Be 1
        }

        It 'includes the GPO name (from hashtable) in the denyApplyGroups warning' {
            $cfg = @{
                groups = @()
                gpos   = @( @{ name = 'HT-GPO1'; mode = 'createAndImport'; denyApplyGroups = @('Missing') } )
            }
            $result = Test-TierModelConfig -Config $cfg -Scope FullDeployment
            ($result.Warnings -join ' ') | Should -Match 'HT-GPO1'
        }

        It 'uses Unknown GPO name when PSCustomObject GPO with denyApplyGroups has no name property' {
            # Covers the "else { 'Unknown GPO' }" branch in the denyApplyGroups GPO name lookup
            $cfg = [PSCustomObject]@{
                gpos = @(
                    [PSCustomObject]@{ mode = 'createAndImport'; denyApplyGroups = @('Missing') }
                )
            }
            $result = Test-TierModelConfig -Config $cfg -Scope FullDeployment
            ($result.Warnings -join ' ') | Should -Match 'Unknown GPO'
        }
    }

    # ── ADMX path validation — hashtable admx entries ────────────────────────
    # Covers if ($admxEntry -is [hashtable]) / if ($config -is [hashtable]) ADMX
    # branches.  All use FromConfig + ImportAdmxOnly.

    Context 'ADMX path validation — hashtable admx entries' {

        It 'rejects non-existent path in a hashtable ADMX entry' {
            $cfg = @{ admx = @( @{ path = 'C:\NonExistentAdmxPath\Hash'; language = 'en-US' } ) }
            $result = Test-TierModelConfig -Config $cfg -Scope ImportAdmxOnly
            $result.Valid | Should -Be $false
            $result.ValidationDetails.InvalidAdmxPaths | Should -BeGreaterThan 0
        }

        It 'rejects a hashtable ADMX entry that has no path key' {
            $cfg = @{ admx = @( @{ language = 'en-US' } ) }
            $result = Test-TierModelConfig -Config $cfg -Scope ImportAdmxOnly
            $result.Valid | Should -Be $false
            ($result.Errors -join ' ') | Should -Match "missing required 'path'"
        }

        It 'uses default en-US language when hashtable ADMX entry omits language key' {
            $tmp = Join-Path $env:TEMP "tm-htadmx-nolang-$([guid]::NewGuid())"
            try {
                New-Item -ItemType Directory $tmp -Force | Out-Null
                New-Item -ItemType File (Join-Path $tmp 'test.admx') -Force | Out-Null
                # No en-US subfolder -> locale warning with default language
                $cfg = @{ admx = @( @{ path = $tmp } ) }
                $result = Test-TierModelConfig -Config $cfg -Scope ImportAdmxOnly
                ($result.Warnings -join ' ') | Should -Match 'missing default locale'
            } finally {
                Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'counts a valid hashtable ADMX entry with admx files and locale folder' {
            $tmp = Join-Path $env:TEMP "tm-htadmx-valid-$([guid]::NewGuid())"
            try {
                New-Item -ItemType Directory $tmp -Force | Out-Null
                New-Item -ItemType File (Join-Path $tmp 'test.admx') -Force | Out-Null
                New-Item -ItemType Directory (Join-Path $tmp 'en-US') -Force | Out-Null
                $cfg = @{ admx = @( @{ path = $tmp; language = 'en-US' } ) }
                $result = Test-TierModelConfig -Config $cfg -Scope ImportAdmxOnly
                $result.ValidationDetails.ValidAdmxPaths   | Should -Be 1
                $result.ValidationDetails.InvalidAdmxPaths | Should -Be 0
            } finally {
                Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'ADMX path validation — PSCustomObject admx entry without language property' {
        # Covers the else-"en-US" branch when a PSObject ADMX entry has no 'language' property.

        It 'defaults to en-US language when PSCustomObject ADMX entry omits language property' {
            $tmp = Join-Path $env:TEMP "tm-psadmx-nolang-$([guid]::NewGuid())"
            try {
                New-Item -ItemType Directory $tmp -Force | Out-Null
                New-Item -ItemType File (Join-Path $tmp 'test.admx') -Force | Out-Null
                # No en-US subfolder -> locale warning with default language
                $cfg = [PSCustomObject]@{
                    admx = @( [PSCustomObject]@{ path = $tmp } )   # PSObject, no language property
                }
                $result = Test-TierModelConfig -Config $cfg -Scope ImportAdmxOnly
                ($result.Warnings -join ' ') | Should -Match 'missing default locale'
            } finally {
                Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # ── OU parent-child validation — hashtable config ────────────────────────
    # Covers the if ($config -is [hashtable]) branch in OU parent-child validation.

    Context 'OU parent-child validation — hashtable config' {

        It 'warns when a hashtable OU config references an undefined parent path' {
            $cfg = @{
                organizationUnits = @(
                    @{ name = 'HT-Child'; path = 'OU=HT-Child,OU=HT-Parent,DC=test,DC=local' }
                )
            }
            $result = Test-TierModelConfig -Config $cfg -Scope OuOnly
            $result.Warnings.Count | Should -BeGreaterThan 0
            ($result.Warnings -join ' ') | Should -Match 'not defined in configuration'
        }
    }
}

# =============================================================================
# Get-TierModelPlan  (exported)
# =============================================================================
Describe 'Get-TierModelPlan' -Tag 'Unit', 'TierModelModule', 'GetTierModelPlan' {

    Context 'Plan structure — empty config' {
        BeforeAll {
            $script:EmptyPlan = Get-TierModelPlan -Path $script:EmptyConfig
        }

        It 'returns a non-null plan object' {
            $script:EmptyPlan | Should -Not -BeNullOrEmpty
        }

        It 'has a Timestamp property' {
            $script:EmptyPlan.Timestamp | Should -Not -BeNullOrEmpty
        }

        It 'PlanHash ends with :empty for a no-action plan' {
            $script:EmptyPlan.PlanHash | Should -Match ':empty$'
        }

        It 'has a CorrelationId property' {
            $script:EmptyPlan.CorrelationId | Should -Not -BeNullOrEmpty
        }

        It 'AllActions, Adds, Updates, Links are Object arrays' {
            $script:EmptyPlan.AllActions.GetType().FullName | Should -Be 'System.Object[]'
            $script:EmptyPlan.Adds.GetType().FullName       | Should -Be 'System.Object[]'
            $script:EmptyPlan.Updates.GetType().FullName    | Should -Be 'System.Object[]'
            $script:EmptyPlan.Links.GetType().FullName      | Should -Be 'System.Object[]'
        }

        It 'ConfigHash is $null when -IncludeHashes is not specified' {
            $script:EmptyPlan.ConfigHash | Should -BeNullOrEmpty
        }

        It 'all counts are zero for empty config' {
            $script:EmptyPlan.OrganizationUnitsCount | Should -Be 0
            $script:EmptyPlan.GroupsCount            | Should -Be 0
            $script:EmptyPlan.UsersCount             | Should -Be 0
            $script:EmptyPlan.GposCount              | Should -Be 0
            $script:EmptyPlan.AdmxCount              | Should -Be 0
        }

        It 'ModelVersion matches the config version field' {
            $script:EmptyPlan.ModelVersion | Should -Be '1.0.0'
        }
    }

    Context '-IncludeHashes flag' {
        It 'populates ConfigHash with a 64-char hex SHA-256 when -IncludeHashes' {
            $plan = Get-TierModelPlan -Path $script:EmptyConfig -IncludeHashes
            $plan.ConfigHash | Should -Match '^[0-9a-f]{64}$'
        }

        It 'ConfigHash is deterministic across calls' {
            $h1 = (Get-TierModelPlan -Path $script:EmptyConfig -IncludeHashes).ConfigHash
            $h2 = (Get-TierModelPlan -Path $script:EmptyConfig -IncludeHashes).ConfigHash
            $h1 | Should -Be $h2
        }
    }

    Context 'Count properties reflect the loaded model' {
        It 'OrganizationUnitsCount matches OUs in config' {
            $plan = Get-TierModelPlan -Path $script:UnitConfig
            $plan.OrganizationUnitsCount | Should -BeGreaterThan 0
        }

        It 'GroupsCount matches groups in config' {
            $plan = Get-TierModelPlan -Path $script:UnitConfig
            $plan.GroupsCount | Should -BeGreaterThan 0
        }

        It 'UsersCount matches users in config' {
            $plan = Get-TierModelPlan -Path $script:UnitConfig
            $plan.UsersCount | Should -BeGreaterThan 0
        }

        It 'GposCount matches GPOs in config' {
            $plan = Get-TierModelPlan -Path $script:UnitConfig
            $plan.GposCount | Should -BeGreaterThan 0
        }
    }

    Context 'Plan hash and collection properties' {
        It 'ActionWarnings and ActionErrors are arrays' {
            $plan = Get-TierModelPlan -Path $script:EmptyConfig
            @($plan.ActionWarnings).GetType().Name | Should -Match 'Object\[\]'
            @($plan.ActionErrors).GetType().Name   | Should -Match 'Object\[\]'
        }

        It 'DriftFindings is an array' {
            $plan = Get-TierModelPlan -Path $script:EmptyConfig
            @($plan.DriftFindings).GetType().Name | Should -Match 'Object\[\]'
        }
    }
}

# =============================================================================
# New-TierModel  (private — accessed via InModuleScope)
# =============================================================================
Describe 'New-TierModel' -Tag 'Unit', 'TierModelModule', 'NewTierModel' {

    Context 'Prerequisites failure — normal mode' {
        BeforeAll {
            Mock Test-TierModelPrerequisites -ModuleName TierModel {
                return [PSCustomObject]@{
                    Valid       = $false
                    Errors      = @('Domain controller unreachable')
                    Remediation = @('Check network connectivity')
                }
            }
        }

        It 'returns Applied=$false with PrerequisitesFailed=$true' {
            # -ErrorAction SilentlyContinue overrides the module-level Stop preference so
            # Write-Error becomes non-terminating and the function reaches its return statement.
            $result = InModuleScope TierModel -Parameters @{ cfg = $script:EmptyConfig } {
                param($cfg)
                New-TierModel -Path $cfg -PreferredDc 'dc01.test.local' -ErrorAction SilentlyContinue
            }
            $result.Applied             | Should -Be $false
            $result.PrerequisitesFailed | Should -Be $true
            $result.Plan                | Should -BeNullOrEmpty
        }

        It 'PrerequisitesResult contains the failure details' {
            $result = InModuleScope TierModel -Parameters @{ cfg = $script:EmptyConfig } {
                param($cfg)
                New-TierModel -Path $cfg -PreferredDc 'dc01.test.local' -ErrorAction SilentlyContinue
            }
            $result.PrerequisitesResult      | Should -Not -BeNullOrEmpty
            $result.PrerequisitesResult.Valid | Should -Be $false
        }
    }

    Context 'Prerequisites failure — WhatIf mode' {
        BeforeAll {
            Mock Test-TierModelPrerequisites -ModuleName TierModel {
                return [PSCustomObject]@{
                    Valid       = $false
                    Errors      = @('DC not reachable')
                    Remediation = @('Fix network')
                }
            }
        }

        It 'returns Applied=$false PrerequisitesFailed=$true in WhatIf mode' {
            $result = InModuleScope TierModel -Parameters @{ cfg = $script:EmptyConfig } {
                param($cfg)
                New-TierModel -Path $cfg -PreferredDc 'dc01.test.local' -WhatIf
            }
            $result.Applied             | Should -Be $false
            $result.PrerequisitesFailed | Should -Be $true
        }
    }

    Context 'Prerequisites pass — WhatIf mode' {
        BeforeAll {
            Mock Test-TierModelPrerequisites -ModuleName TierModel {
                return [PSCustomObject]@{ Valid = $true; Errors = @(); Remediation = @() }
            }
        }

        It 'returns Applied=$false and WhatIf=$true' {
            $result = InModuleScope TierModel -Parameters @{ cfg = $script:EmptyConfig } {
                param($cfg)
                New-TierModel -Path $cfg -PreferredDc 'dc01.test.local' -WhatIf
            }
            $result.Applied | Should -Be $false
            $result.WhatIf  | Should -Be $true
        }

        It 'plan is populated; Adds and Links properties exist' {
            $result = InModuleScope TierModel -Parameters @{ cfg = $script:EmptyConfig } {
                param($cfg)
                New-TierModel -Path $cfg -PreferredDc 'dc01.test.local' -WhatIf
            }
            $result.Plan | Should -Not -BeNullOrEmpty
            # Adds and Links are @() for an empty config — verify they exist as properties
            $result.PSObject.Properties.Name | Should -Contain 'Adds'
            $result.PSObject.Properties.Name | Should -Contain 'Links'
        }

        It 'PrerequisitesPassed=$true' {
            $result = InModuleScope TierModel -Parameters @{ cfg = $script:EmptyConfig } {
                param($cfg)
                New-TierModel -Path $cfg -PreferredDc 'dc01.test.local' -WhatIf
            }
            $result.PrerequisitesPassed | Should -Be $true
        }
    }

    Context 'Prerequisites pass — safety gate (no ConfirmApply)' {
        BeforeAll {
            Mock Test-TierModelPrerequisites -ModuleName TierModel {
                return [PSCustomObject]@{ Valid = $true; Errors = @(); Remediation = @() }
            }
        }

        It 'throws when ConfirmApply is not provided' {
            {
                InModuleScope TierModel -Parameters @{ cfg = $script:EmptyConfig } {
                    param($cfg)
                    New-TierModel -Path $cfg -PreferredDc 'dc01.test.local'
                }
            } | Should -Throw '*ConfirmApply*'
        }
    }

    Context 'Prerequisites pass — ConfirmApply' {
        BeforeAll {
            Mock Test-TierModelPrerequisites -ModuleName TierModel {
                return [PSCustomObject]@{ Valid = $true; Errors = @(); Remediation = @() }
            }
        }

        It 'returns Applied=$true' {
            $result = InModuleScope TierModel -Parameters @{ cfg = $script:EmptyConfig } {
                param($cfg)
                New-TierModel -Path $cfg -PreferredDc 'dc01.test.local' -ConfirmApply
            }
            $result.Applied | Should -Be $true
        }

        It 'PrerequisitesPassed=$true and Plan is populated' {
            $result = InModuleScope TierModel -Parameters @{ cfg = $script:EmptyConfig } {
                param($cfg)
                New-TierModel -Path $cfg -PreferredDc 'dc01.test.local' -ConfirmApply
            }
            $result.PrerequisitesPassed | Should -Be $true
            $result.Plan                | Should -Not -BeNullOrEmpty
        }
    }

    # ── Prerequisites returns array (pipeline decontamination) ───────────────
    # Covers the `if ($prereqResult -is [array])` decontamination branch.

    Context 'Prerequisites returns array — pipeline decontamination' {
        BeforeAll {
            # Two-element array bypasses PowerShell's single-element unwrapping.
            # The Where-Object + Select-Object -Last 1 decontamination discards the
            # first (invalid) element and keeps the second (valid) one.
            Mock Test-TierModelPrerequisites -ModuleName TierModel {
                return @(
                    [PSCustomObject]@{ Valid = $false; Errors = @('noise'); Remediation = @() }
                    [PSCustomObject]@{ Valid = $true;  Errors = @();        Remediation = @() }
                )
            }
        }

        It 'handles an array-wrapped prerequisite result in WhatIf mode' {
            $result = InModuleScope TierModel -Parameters @{ cfg = $script:EmptyConfig } {
                param($cfg)
                New-TierModel -Path $cfg -PreferredDc 'dc01.test.local' -WhatIf
            }
            $result.PrerequisitesPassed | Should -Be $true
            $result.WhatIf              | Should -Be $true
        }
    }
}

# =============================================================================
# Set-TierModel  (private — accessed via InModuleScope)
# =============================================================================
Describe 'Set-TierModel' -Tag 'Unit', 'TierModelModule', 'SetTierModel' {

    Context 'Prerequisites failure — normal mode' {
        BeforeAll {
            Mock Test-TierModelPrerequisites -ModuleName TierModel {
                return [PSCustomObject]@{
                    Valid       = $false
                    Errors      = @('DC not contactable')
                    Remediation = @('Verify DC name')
                }
            }
        }

        It 'returns Converged=$false with PrerequisitesFailed=$true' {
            # Same as New-TierModel: Write-Error stops execution unless -ErrorAction SilentlyContinue
            $result = InModuleScope TierModel -Parameters @{ cfg = $script:EmptyConfig } {
                param($cfg)
                Set-TierModel -Path $cfg -PreferredDc 'dc01.test.local' -ErrorAction SilentlyContinue
            }
            $result.Converged           | Should -Be $false
            $result.PrerequisitesFailed | Should -Be $true
        }

        It 'Plan is null on prerequisite failure' {
            $result = InModuleScope TierModel -Parameters @{ cfg = $script:EmptyConfig } {
                param($cfg)
                Set-TierModel -Path $cfg -PreferredDc 'dc01.test.local' -ErrorAction SilentlyContinue
            }
            $result.Plan | Should -BeNullOrEmpty
        }
    }

    Context 'Prerequisites failure — WhatIf mode' {
        BeforeAll {
            Mock Test-TierModelPrerequisites -ModuleName TierModel {
                return [PSCustomObject]@{
                    Valid       = $false
                    Errors      = @('No DC')
                    Remediation = @('Fix it')
                }
            }
        }

        It 'returns Converged=$false PrerequisitesFailed=$true in WhatIf mode' {
            $result = InModuleScope TierModel -Parameters @{ cfg = $script:EmptyConfig } {
                param($cfg)
                Set-TierModel -Path $cfg -PreferredDc 'dc01.test.local' -WhatIf
            }
            $result.Converged           | Should -Be $false
            $result.PrerequisitesFailed | Should -Be $true
        }
    }

    Context 'Prerequisites pass — WhatIf mode' {
        BeforeAll {
            Mock Test-TierModelPrerequisites -ModuleName TierModel {
                return [PSCustomObject]@{ Valid = $true; Errors = @(); Remediation = @() }
            }
        }

        It 'returns Converged=$false WhatIf=$true with plan' {
            $result = InModuleScope TierModel -Parameters @{ cfg = $script:EmptyConfig } {
                param($cfg)
                Set-TierModel -Path $cfg -PreferredDc 'dc01.test.local' -WhatIf
            }
            $result.Converged | Should -Be $false
            $result.WhatIf    | Should -Be $true
            $result.Plan      | Should -Not -BeNullOrEmpty
        }

        It 'PrerequisitesPassed=$true' {
            $result = InModuleScope TierModel -Parameters @{ cfg = $script:EmptyConfig } {
                param($cfg)
                Set-TierModel -Path $cfg -PreferredDc 'dc01.test.local' -WhatIf
            }
            $result.PrerequisitesPassed | Should -Be $true
        }

        It 'plan Adds and Links properties exist' {
            $result = InModuleScope TierModel -Parameters @{ cfg = $script:EmptyConfig } {
                param($cfg)
                Set-TierModel -Path $cfg -PreferredDc 'dc01.test.local' -WhatIf
            }
            # Adds and Links are @() for an empty config — verify the properties exist
            $result.PSObject.Properties.Name | Should -Contain 'Adds'
            $result.PSObject.Properties.Name | Should -Contain 'Links'
        }
    }

    Context 'Prerequisites pass — safety gate (no ConfirmApply)' {
        BeforeAll {
            Mock Test-TierModelPrerequisites -ModuleName TierModel {
                return [PSCustomObject]@{ Valid = $true; Errors = @(); Remediation = @() }
            }
        }

        It 'throws when ConfirmApply is not provided' {
            {
                InModuleScope TierModel -Parameters @{ cfg = $script:EmptyConfig } {
                    param($cfg)
                    Set-TierModel -Path $cfg -PreferredDc 'dc01.test.local'
                }
            } | Should -Throw '*ConfirmApply*'
        }
    }

    Context 'Prerequisites pass — ConfirmApply with empty (already-converged) plan' {
        BeforeAll {
            Mock Test-TierModelPrerequisites -ModuleName TierModel {
                return [PSCustomObject]@{ Valid = $true; Errors = @(); Remediation = @() }
            }
        }

        It 'returns Converged=$true AlreadyConverged=$true for an empty action plan' {
            $result = InModuleScope TierModel -Parameters @{ cfg = $script:EmptyConfig } {
                param($cfg)
                Set-TierModel -Path $cfg -PreferredDc 'dc01.test.local' -ConfirmApply
            }
            $result.Converged        | Should -Be $true
            $result.AlreadyConverged | Should -Be $true
        }

        It 'ExecutionResult.Success=$true for already-converged system' {
            $result = InModuleScope TierModel -Parameters @{ cfg = $script:EmptyConfig } {
                param($cfg)
                Set-TierModel -Path $cfg -PreferredDc 'dc01.test.local' -ConfirmApply
            }
            $result.ExecutionResult.Success | Should -Be $true
        }

        It 'Plan is populated and has a PlanHash' {
            $result = InModuleScope TierModel -Parameters @{ cfg = $script:EmptyConfig } {
                param($cfg)
                Set-TierModel -Path $cfg -PreferredDc 'dc01.test.local' -ConfirmApply
            }
            $result.Plan          | Should -Not -BeNullOrEmpty
            $result.Plan.PlanHash | Should -Not -BeNullOrEmpty
        }

        It 'PrerequisitesPassed=$true' {
            $result = InModuleScope TierModel -Parameters @{ cfg = $script:EmptyConfig } {
                param($cfg)
                Set-TierModel -Path $cfg -PreferredDc 'dc01.test.local' -ConfirmApply
            }
            $result.PrerequisitesPassed | Should -Be $true
        }
    }

    # ── Prerequisites returns array (pipeline decontamination) ───────────────
    # Covers the `if ($prereqResult -is [array])` decontamination branch.

    Context 'Prerequisites returns array — pipeline decontamination' {
        BeforeAll {
            Mock Test-TierModelPrerequisites -ModuleName TierModel {
                return @(
                    [PSCustomObject]@{ Valid = $false; Errors = @('noise'); Remediation = @() }
                    [PSCustomObject]@{ Valid = $true;  Errors = @();        Remediation = @() }
                )
            }
        }

        It 'handles an array-wrapped prerequisite result in WhatIf mode' {
            $result = InModuleScope TierModel -Parameters @{ cfg = $script:EmptyConfig } {
                param($cfg)
                Set-TierModel -Path $cfg -PreferredDc 'dc01.test.local' -WhatIf
            }
            $result.PrerequisitesPassed | Should -Be $true
            $result.WhatIf              | Should -Be $true
        }
    }
}

# =============================================================================
# Test-TierModelDrift  (private — accessed via InModuleScope)
# =============================================================================
Describe 'Test-TierModelDrift' -Tag 'Unit', 'TierModelModule', 'TestTierModelDrift' {

    Context 'Default object return — empty config' {
        BeforeAll {
            $script:DriftReport = InModuleScope TierModel -Parameters @{ cfg = $script:EmptyConfig } {
                param($cfg)
                Test-TierModelDrift -Path $cfg
            }
        }

        It 'returns DriftDetected=$false for a config with no drift findings' {
            $script:DriftReport.DriftDetected | Should -Be $false
        }

        It 'Findings is an empty array' {
            $script:DriftReport.Findings.Count | Should -Be 0
        }

        It 'ConfigHash is populated' {
            $script:DriftReport.ConfigHash | Should -Not -BeNullOrEmpty
        }

        It 'Generated timestamp is present' {
            $script:DriftReport.Generated | Should -Not -BeNullOrEmpty
        }
    }

    Context '-Raw flag' {
        It 'returns a JSON string containing DriftDetected and Findings when -Raw' {
            $result = InModuleScope TierModel -Parameters @{ cfg = $script:EmptyConfig } {
                param($cfg)
                Test-TierModelDrift -Path $cfg -Raw
            }
            $result | Should -BeOfType 'string'
            $result | Should -Match '"DriftDetected"'
            $result | Should -Match '"Findings"'
            $result | Should -Match '"ConfigHash"'
        }
    }
}
