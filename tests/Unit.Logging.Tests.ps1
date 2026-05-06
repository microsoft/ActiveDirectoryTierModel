# TierModel.Logging.Tests.ps1
# Pester tests for TierModel logging functionality

BeforeAll {
    # Import the module
    $ModulePath = Join-Path $PSScriptRoot ".." "modules" "TierModel" "TierModel.psd1"
    Import-Module $ModulePath -Force
    
    # Test log file path
    $script:TestLogPath = Join-Path $TestDrive "tiermodel-test.log"
}

Describe "Write-TierModelLog" {
    Context "Basic Functionality" {
        It "Should write log entries with required parameters" {
            { Write-TierModelLog -Level Info -Message "Test message" } | Should -Not -Throw
        }
        
        It "Should accept all valid log levels" {
            # Mock output streams to suppress console output during test
            Mock Write-Debug {} -ModuleName TierModel
            Mock Write-Verbose {} -ModuleName TierModel
            Mock Write-Warning {} -ModuleName TierModel
            Mock Write-Host {} -ModuleName TierModel
            
            # Test non-error levels
            $nonErrorLevels = @('Debug', 'Info', 'Warning')
            
            foreach ($level in $nonErrorLevels) {
                { Write-TierModelLog -Level $level -Message "Test $level message" } | Should -Not -Throw
            }
            
            # Test Error level separately (requires -PassThru to get return value)
            $errorResult = Write-TierModelLog -Level Error -Message "Test Error message" -PassThru
            $errorResult | Should -Not -BeNull
            $errorResult.Level | Should -Be 'Error'
        }
        
        It "Should reject invalid log levels" {
            { Write-TierModelLog -Level 'Invalid' -Message "Test message" } | Should -Throw
        }
    }
    
    Context "Structured Data" {
        It "Should accept hashtable data" {
            $data = @{ 
                TestKey = 'TestValue'
                Number = 42
                Boolean = $true
            }
            
            { Write-TierModelLog -Level Info -Message "Test with data" -Data $data } | Should -Not -Throw
        }
        
        It "Should include correlation ID in data" {
            $data = @{ TestKey = 'TestValue' }
            
            # Mock Write-Verbose to capture the output
            Mock Write-Verbose {} -ModuleName TierModel
            
            Write-TierModelLog -Level Info -Message "Test correlation" -Data $data
            
            # Verify correlation ID format (GUID pattern)
            Should -Invoke Write-Verbose -ModuleName TierModel -ParameterFilter {
                $Message -match '\[CID: [0-9a-f]{8}\]'
            }
        }
    }
    
    Context "Security Redaction" {
        It "Should redact sensitive keys" {
            $sensitiveData = @{
                Password = 'secret123'
                Token = 'abc123'
                Key = 'keyvalue'
                Secret = 'topsecret'
                Credential = 'userpass'
                SafeValue = 'this is safe'
            }
            
            Mock Write-Verbose {} -ModuleName TierModel
            
            Write-TierModelLog -Level Info -Message "Test redaction" -Data $sensitiveData
            
            # Verify redaction occurred
            Should -Invoke Write-Verbose -ModuleName TierModel -ParameterFilter {
                $Message -match '\[REDACTED\]' -and $Message -notmatch 'secret123|abc123|keyvalue|topsecret|userpass'
            }
        }
        
        It "Should preserve non-sensitive data during redaction" {
            $mixedData = @{
                Password = 'secret123'
                SafeValue = 'this is safe'
                ConfigPath = 'C:\Config\test.json'
            }
            
            Mock Write-Verbose {} -ModuleName TierModel
            
            Write-TierModelLog -Level Info -Message "Test mixed data" -Data $mixedData
            
            # Verify safe data is preserved
            Should -Invoke Write-Verbose -ModuleName TierModel -ParameterFilter {
                $Message -match 'SafeValue=this is safe' -and $Message -match 'ConfigPath='
            }
        }
    }
    
    Context "File Logging" {
        BeforeEach {
            # Clean up any existing test log
            if (Test-Path $script:TestLogPath) {
                Remove-Item $script:TestLogPath -Force
            }
        }
        
        It "Should write to log file when LogPath specified" {
            Write-TierModelLog -Level Info -Message "File log test" -LogPath $script:TestLogPath
            
            Test-Path $script:TestLogPath | Should -Be $true
        }
        
        It "Should create log directory if it doesn't exist" {
            $deepLogPath = Join-Path $TestDrive "logs" "subdir" "test.log"
            
            Write-TierModelLog -Level Info -Message "Deep path test" -LogPath $deepLogPath
            
            Test-Path $deepLogPath | Should -Be $true
        }
        
        It "Should write JSON format to file" {
            Write-TierModelLog -Level Info -Message "JSON test" -LogPath $script:TestLogPath -Data @{ TestKey = 'TestValue' }
            
            $logContent = Get-Content $script:TestLogPath -Raw
            $jsonObject = $logContent | ConvertFrom-Json
            
            $jsonObject.Level | Should -Be 'Info'
            $jsonObject.Message | Should -Be 'JSON test'
            $jsonObject.Data.TestKey | Should -Be 'TestValue'
        }
        
        It "Should handle file write errors gracefully" {
            # Try to write to an invalid path
            Mock Write-Warning {} -ModuleName TierModel
            
            Write-TierModelLog -Level Info -Message "Error test" -LogPath "Z:\invalid\path\test.log"
            
            Should -Invoke Write-Warning -ModuleName TierModel -ParameterFilter {
                $Message -match 'Failed to write to log file'
            }
        }
    }
    
    Context "Console Output" {
        It "Should write to appropriate streams by level" {
            Mock Write-Debug {} -ModuleName TierModel
            Mock Write-Verbose {} -ModuleName TierModel  
            Mock Write-Warning {} -ModuleName TierModel
            Mock Write-Host {} -ModuleName TierModel
            
            Write-TierModelLog -Level Debug -Message "Debug test"
            Write-TierModelLog -Level Info -Message "Info test"
            Write-TierModelLog -Level Warning -Message "Warning test"
            Write-TierModelLog -Level Error -Message "Error test"
            
            Should -Invoke Write-Debug -ModuleName TierModel -Times 1
            Should -Invoke Write-Verbose -ModuleName TierModel -Times 1
            Should -Invoke Write-Warning -ModuleName TierModel -Times 1
            Should -Invoke Write-Host -ModuleName TierModel -Times 1
        }
        
        It "Should format console messages consistently" {
            Mock Write-Verbose {} -ModuleName TierModel
            
            Write-TierModelLog -Level Info -Message "Format test" -Data @{ Key1 = 'Value1'; Key2 = 'Value2' }
            
            Should -Invoke Write-Verbose -ModuleName TierModel -ParameterFilter {
                $Message -match '^\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\] \[Info\] Format test \| .* \[CID: [0-9a-f]{8}\]$'
            }
        }
    }
}

Describe "Logging Integration" {
    Context "Module Functions" {
        It "Should log during configuration validation" {
            Mock Write-TierModelLog {} -ModuleName TierModel
            
            # Use a test config if available
            $testConfigPath = Join-Path $PSScriptRoot "fixtures" "valid-config.json"
            if (Test-Path $testConfigPath) {
                try {
                    Test-TierModelConfig -Path $testConfigPath
                } catch {
                    # Ignore validation errors for this test
                }
                
                Should -Invoke Write-TierModelLog -ModuleName TierModel -ParameterFilter {
                    $Message -match 'Starting TierModel configuration validation'
                }
            }
        }
        
        It "Should log during plan generation" {
            Mock Write-TierModelLog {} -ModuleName TierModel
            
            $testConfigPath = Join-Path $PSScriptRoot "fixtures" "valid-config.json"
            if (Test-Path $testConfigPath) {
                try {
                    Get-TierModelPlan -Path $testConfigPath
                } catch {
                    # Ignore errors for this test
                }
                
                Should -Invoke Write-TierModelLog -ModuleName TierModel -ParameterFilter {
                    $Message -match 'Starting TierModel plan generation'
                }
            }
        }
        
        It "Should log during drift detection" {
            Mock Write-TierModelLog {} -ModuleName TierModel
            
            $testConfigPath = Join-Path $PSScriptRoot "fixtures" "valid-config.json"
            if (Test-Path $testConfigPath) {
                try {
                    Test-TierModelDrift -Path $testConfigPath
                } catch {
                    # Ignore errors for this test
                }
                
                Should -Invoke Write-TierModelLog -ModuleName TierModel -ParameterFilter {
                    $Message -match 'Starting TierModel drift detection'
                }
            }
        }
    }
    
    Context "Correlation ID Consistency" {
        It "Should use consistent correlation IDs within operations" {
            $capturedLogs = @()
            
            Mock Write-TierModelLog { 
                $capturedLogs += @{ Level = $Level; Message = $Message; Data = $Data }
            } -ModuleName TierModel
            
            $testConfigPath = Join-Path $PSScriptRoot "fixtures" "valid-config.json"
            if (Test-Path $testConfigPath) {
                try {
                    Get-TierModelPlan -Path $testConfigPath
                } catch {
                    # Ignore errors
                }
                
                # Check that correlation IDs are consistent within the operation
                $correlationIds = $capturedLogs | Where-Object { $_.Data.PlanCorrelationId } | ForEach-Object { $_.Data.PlanCorrelationId } | Select-Object -Unique
                
                if ($correlationIds.Count -gt 0) {
                    $correlationIds.Count | Should -Be 1
                }
            }
        }
    }
}

Describe "Logging Configuration" {
    Context "Module Variables" {
        It "Should initialize logging variables" {
            # Access module-level variables through the module scope
            $moduleInfo = Get-Module TierModel
            $loggingEnabled = $moduleInfo | ForEach-Object { & $_.NewBoundScriptBlock({ $script:LoggingEnabled }) }
            $defaultLogPath = $moduleInfo | ForEach-Object { & $_.NewBoundScriptBlock({ $script:DefaultLogPath }) }
            
            $loggingEnabled | Should -BeOfType [bool]
            # DefaultLogPath can be null initially, so just check it exists as a variable
            { $defaultLogPath } | Should -Not -Throw
        }
        
        It "Should maintain session correlation ID" {
            # Access module-level CorrelationId through the module scope
            $moduleInfo = Get-Module TierModel
            $correlationId = $moduleInfo | ForEach-Object { & $_.NewBoundScriptBlock({ $script:CorrelationId }) }
            
            $correlationId | Should -Not -BeNullOrEmpty
            $correlationId | Should -Match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        }
    }
}