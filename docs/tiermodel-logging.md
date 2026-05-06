# TierModel Logging System

## Overview

The TierModel module includes a comprehensive structured logging system designed for enterprise environments. Logging is controlled via the `-Logging` switch in the `Deploy-TierModel.ps1` script. When enabled, deployment operations are logged with correlation IDs, security redaction, and multiple output formats.

## Deployment Logging vs. Audit Reporting

**Deployment Logging (`Deploy-TierModel.ps1`)**
- Controlled by the `-Logging` switch
- Records deployment execution details, progress, and results
- Uses `Write-TierModelLog` function for structured JSON logging
- Logs stored in files specified by `-LogPath` parameter
- Purpose: Track what changes were made during deployment

**Audit Reporting (`Audit-TierModel.ps1`)**
- Controlled by the `-OutputFormat` parameter (Text, Json, Html, NUnitXml)
- Generates compliance and drift detection reports
- Does NOT use the logging system
- Reports stored in directory specified by `-LogPath` parameter
- Purpose: Document current state compliance vs. desired configuration

For audit reporting documentation, see [Drift Detection Details](drift-detection-details.md).

## Features

### Structured Logging
- **JSON Format**: Machine-readable log entries for analysis
- **Correlation IDs**: Track operations across multiple function calls
- **Security Redaction**: Automatically redact sensitive data (passwords, tokens, secrets)
- **Multiple Severity Levels**: Debug, Info, Warning, Error
- **Consistent Timestamps**: ISO 8601 format with millisecond precision

### Output Destinations
- **Console**: Human-readable format with color coding by severity
- **File**: JSON format for log aggregation and analysis
- **CI/CD Integration**: Automatic artifact publishing in pipelines

## Usage

### Enabling Logging in Deployment

Logging is controlled by the `Deploy-TierModel.ps1` script using the `-Logging` switch:

```powershell
# Deploy with logging enabled to current directory
.\Deploy-TierModel.ps1 -PreferredDc "DC01.contoso.com" -OuOnly -ConfirmApply -Logging

# Deploy with logging to specific directory
.\Deploy-TierModel.ps1 -PreferredDc "DC01.contoso.com" -FullDeployment -ConfirmApply -Logging -LogPath "C:\Logs\TierModel"

# Deploy with custom log filename base
.\Deploy-TierModel.ps1 -PreferredDc "DC01.contoso.com" -OuOnly -ConfirmApply -Logging -LogPath "C:\Logs" -OutputFileBase "Deploy-Aug2024"
```

The deployment script will log:
- Deployment initiation and parameters
- Prerequisites validation results
- Per-component deployment progress (OUs, Groups, Users, etc.)
- Action execution details and results
- Summary statistics and completion status

**Note**: The `Audit-TierModel.ps1` script generates audit reports but does not use the logging system. Use `-OutputFormat` and `-LogPath` parameters for audit report generation.

### Direct Function Usage (Advanced)

For custom scripts or automation, you can call `Write-TierModelLog` directly:

```powershell
# Import the module
Import-Module TierModel

# Basic log entry
Write-TierModelLog -Level Info -Message "Operation completed successfully"

# Log with structured data
Write-TierModelLog -Level Warning -Message "Configuration validation warning" -Data @{
    ConfigPath = "C:\Config\tiermodel.json"
    WarningCount = 3
    ValidationTime = "2.5s"
}

# Error logging
Write-TierModelLog -Level Error -Message "Deployment failed" -Data @{
    ActionId = "CreateGroup-001"
    ErrorType = "AccessDenied"
    TargetDN = "CN=TierAdmins,OU=Groups,DC=contoso,DC=com"
}

# Specify custom log file path
Write-TierModelLog -Level Info -Message "Custom log location" -LogPath "C:\CustomLogs\debug.log"
```

## Log Entry Format

### Console Format
```
[2024-01-15T10:30:45.123Z] [Info] Starting TierModel plan generation | ConfigPath=config/tiermodel.json, ActionCount=15 [CID: a1b2c3d4]
```

### File Format (JSON)
```json
{
  "Timestamp": "2024-01-15T10:30:45.123Z",
  "Level": "Info", 
  "Message": "Starting TierModel plan generation",
  "Data": {
    "ConfigPath": "config/tiermodel.json",
    "ActionCount": 15,
    "CorrelationId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
  },
  "CorrelationId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
```

## Security Features

### Automatic Redaction

Sensitive data is automatically redacted from log entries:

```powershell
$userData = @{
    Name = "ServiceAccount"
    Password = "SuperSecret123"  # Will be redacted
    Department = "IT"            # Will be preserved
    Token = "abc123xyz"          # Will be redacted
}

Write-TierModelLog -Level Info -Message "Creating user" -Data $userData
# Output: [Info] Creating user | Name=ServiceAccount, Password=[REDACTED], Department=IT, Token=[REDACTED]
```

**Redacted Keys**: Password, Secret, Token, Key, Credential (case-insensitive)

### Correlation ID Tracking

Each operation gets a unique correlation ID that's included in all related log entries:

```powershell
# Starting deployment
Get-TierModelPlan -Path "config/tiermodel.json"
# Logs: [CID: a1b2c3d4] Starting TierModel plan generation
# Logs: [CID: a1b2c3d4] Action plan generation completed
```

## CI/CD Integration

### GitHub Actions

The logging system integrates with CI pipelines to capture and publish logs as artifacts:

```yaml
- name: Deploy TierModel with Logging
  run: |
    .\TierModel\Deploy-TierModel.ps1 `
      -PreferredDc "${{ secrets.DC_HOSTNAME }}" `
      -FullDeployment `
      -ConfirmApply `
      -Logging `
      -LogPath "ci-logs" `
      -OutputFileBase "tiermodel-deployment"
    
- name: Upload Deployment Logs
  uses: actions/upload-artifact@v4
  if: always()
  with:
    name: deployment-logs
    path: ci-logs/
```

### Azure DevOps

```yaml
- task: PowerShell@2
  displayName: 'Deploy TierModel with Logging'
  inputs:
    filePath: 'TierModel/Deploy-TierModel.ps1'
    arguments: >
      -PreferredDc "$(DC_HOSTNAME)"
      -FullDeployment
      -ConfirmApply
      -Logging
      -LogPath "$(Agent.TempDirectory)/tiermodel-logs"
      -OutputFileBase "tiermodel-deployment"
      
- task: PublishPipelineArtifact@1
  condition: always()
  displayName: 'Publish Deployment Logs'
  inputs:
    targetPath: '$(Agent.TempDirectory)/tiermodel-logs'
    artifact: 'TierModel-Deployment-Logs'
```

## Log Analysis

### PowerShell Analysis

```powershell
# Read and parse log file
$logs = Get-Content "C:\Logs\TierModel\tiermodel.log" | ForEach-Object { $_ | ConvertFrom-Json }

# Filter by correlation ID
$operationLogs = $logs | Where-Object { $_.CorrelationId -eq "a1b2c3d4-e5f6-7890-abcd-ef1234567890" }

# Group by log level
$logsByLevel = $logs | Group-Object Level

# Find errors in last 24 hours
$recentErrors = $logs | Where-Object { 
    $_.Level -eq "Error" -and 
    [DateTime]::Parse($_.Timestamp) -gt (Get-Date).AddDays(-1) 
}
```

### Log Aggregation Tools

The JSON format is compatible with popular log aggregation systems:

- **ELK Stack**: Logstash can parse the JSON format directly
- **Splunk**: JSON format enables rich field extraction
- **Azure Monitor**: Compatible with Log Analytics workspace ingestion
- **PowerBI**: JSON format can be imported for dashboard creation

## Troubleshooting

### Common Issues

**File Permission Errors**
```powershell
# Check if log directory is writable
$logDir = Split-Path $script:DefaultLogPath -Parent
Test-Path $logDir -PathType Container
(Get-Acl $logDir).Access | Where-Object { $_.IdentityReference -eq $env:USERNAME }
```

**Large Log Files**
```powershell
# Rotate logs manually
$logFile = $script:DefaultLogPath
if ((Get-Item $logFile).Length -gt 10MB) {
    $rotatedFile = $logFile -replace '\.log$', "-$(Get-Date -Format 'yyyyMMdd').log"
    Move-Item $logFile $rotatedFile
}
```

**Missing Correlation IDs**
Correlation IDs are automatically generated. If missing, check:
- Module import completed successfully
- Script-level variables are initialized
- No conflicting module imports

### Debug Logging

Enable verbose logging for troubleshooting:

```powershell
$VerbosePreference = 'Continue'
$DebugPreference = 'Continue'

# All Write-TierModelLog calls with Debug level will now appear
Write-TierModelLog -Level Debug -Message "Detailed debug information"
```

## Best Practices

### Logging Guidelines

1. **Use appropriate log levels**:
   - **Debug**: Detailed diagnostic information
   - **Info**: General information about operation progress
   - **Warning**: Something unexpected but recoverable occurred
   - **Error**: An error occurred that prevented operation completion

2. **Include context data**:
   ```powershell
   Write-TierModelLog -Level Info -Message "Action executed" -Data @{
       ActionType = "CreateGroup"
       Target = "CN=Admins,OU=Groups,DC=contoso,DC=com"
       ExecutionTime = "1.2s"
   }
   ```

3. **Avoid logging sensitive information**:
   - The system automatically redacts known sensitive keys
   - Avoid including credentials in custom data fields
   - Use generic identifiers rather than actual passwords/secrets

4. **Log operation boundaries**:
   ```powershell
   Write-TierModelLog -Level Info -Message "Starting user creation batch"
   # ... user creation logic ...
   Write-TierModelLog -Level Info -Message "User creation batch completed"
   ```

### Performance Considerations

- File logging has minimal performance impact (< 1ms per entry)
- JSON serialization is optimized for small to medium data objects
- Log rotation should be implemented for long-running systems
- Consider disabling Debug level logging in production environments

## Configuration Reference

### Deployment Script Parameters

The `Deploy-TierModel.ps1` script provides the following logging-related parameters:

| Parameter | Type | Description |
|-----------|------|-------------|
| -Logging | Switch | Enables file logging for the deployment operation |
| -LogPath | String | Directory path where log files will be created (default: current directory) |
| -OutputFileBase | String | Base filename for log files without extension or timestamp |

### Module Variables (Advanced)

For custom scripts calling `Write-TierModelLog` directly, these module-level variables can be configured:

```powershell
# Enable/disable file logging (used by Write-TierModelLog)
$script:LoggingEnabled = $true/$false

# Default log file path (used when LogPath not specified)
$script:DefaultLogPath = "C:\Logs\TierModel\tiermodel.log"

# Session correlation ID (automatically generated)
$script:CorrelationId = "00000000-0000-0000-0000-000000000000"
```

**Note**: In typical usage, you should use the `Deploy-TierModel.ps1` script's `-Logging` switch rather than directly manipulating these variables.

### Log Levels

| Level | Usage | Console Stream | File Logging |
|-------|--------|----------------|--------------|
| Debug | Diagnostic details | Write-Debug | Always logged |
| Info | General information | Write-Verbose | Always logged |
| Warning | Recoverable issues | Write-Warning | Always logged |
| Error | Operation failures | Write-Error | Always logged |

### Redacted Data Keys

The following keys are automatically redacted (case-insensitive):
- Password
- Secret  
- Token
- Key
- Credential

Additional keys can be added by modifying the `$sensitiveKeys` array in the `Write-TierModelLog` function.

## Related Documentation

For additional documentation, see:
- [Drift Detection Details](drift-detection-details.md) - Audit reporting and compliance checking
- [Deployment Methodology](deployment-methodology.md) - Comprehensive deployment strategy
- [CI/CD Integration](ci-cd.md) - Automated testing and deployment pipelines