# TierModel CI/CD Pipelines

## Overview

The TierModel project includes comprehensive CI/CD pipelines for both GitHub Actions and Azure DevOps. These pipelines provide automated testing, linting, security analysis, and artifact publishing to ensure code quality and reliability.

## Pipeline Features

### 🧪 Testing & Quality Assurance
- **Multi-version PowerShell testing** (5.1 and 7.4)
- **Comprehensive test coverage** with Pester
- **Code coverage reporting** with JaCoCo format
- **PowerShell linting** with PSScriptAnalyzer
- **Module validation** and import testing

### 🔒 Security Analysis
- **Security-focused linting** rules
- **Fail-on-critical-issues** configuration
- **Sensitive data detection** validation
- **Best practices enforcement**

### 📦 Build & Packaging
- **Module manifest validation**
- **Automated packaging** with metadata
- **Artifact publishing** for releases
- **Documentation generation** with PlatyPS

### 📊 Drift Detection & Monitoring  
- **Scheduled drift detection** (daily at 2 AM UTC)
- **Drift report artifacts** for trend analysis
- **Current state snapshots** for comparison
- **Error handling and reporting**

## GitHub Actions Pipeline

**Location**: `.github/workflows/ci.yml`

### Trigger Configuration
```yaml
on:
  push:
    branches: [ main, develop ]
  pull_request:  
    branches: [ main, develop ]
  schedule:
    # Daily drift detection at 2 AM UTC
    - cron: '0 2 * * *'
```

### Jobs Overview

#### 1. Linting (`lint`)
- Runs PSScriptAnalyzer with comprehensive rule set
- Checks Error, Warning, and Information severity levels
- Publishes results as CSV artifacts
- Fails build on Error-level issues

#### 2. Testing (`test`)  
- Matrix strategy: PowerShell 7.4 and 5.1
- Runs Pester tests with detailed output
- Generates code coverage reports
- Publishes test results in JUnit format

#### 3. Packaging (`package`)
- Validates module manifest and structure
- Tests module import functionality  
- Creates deployable module package
- Includes build metadata and Git information

#### 4. Security Analysis (`security`)
- Runs security-focused PSScriptAnalyzer rules
- Checks for credential handling issues
- Validates use of secure coding practices
- Fails build on critical security violations

#### 5. Drift Detection (`drift`)
- Runs on schedule and main branch pushes
- Tests drift detection against sample configurations
- Captures current state snapshots
- Publishes drift reports as artifacts

#### 6. Documentation (`docs`)
- Generates markdown help with PlatyPS
- Creates external help files
- Publishes documentation artifacts
- Runs only on main branch pushes

### Artifact Outputs

| Artifact | Content | Retention |
|----------|---------|-----------|
| `scriptanalyzer-results` | Linting results CSV | 30 days |
| `test-results-ps7.4` | Test results and coverage | 30 days |
| `test-results-ps5.1` | Test results and coverage | 30 days |
| `TierModel-Module` | Packaged module files | 90 days |
| `security-analysis` | Security scan results | 30 days |
| `drift-detection-reports` | Drift analysis JSON files | 30 days |
| `TierModel-Documentation` | Generated help files | 90 days |

### Usage Example

```bash
# Fork and clone the repository
git clone https://github.com/yourusername/TierModel.git
cd TierModel

# Create feature branch  
git checkout -b feature/new-functionality

# Make changes and commit
git add .
git commit -m "Add new functionality"

# Push to trigger CI pipeline
git push origin feature/new-functionality

# Create pull request - CI runs automatically
```

## Azure DevOps Pipeline

**Location**: `.azuredevops/azure-pipelines.yml`

### Trigger Configuration
```yaml
trigger:
  branches:
    include: [main, develop]
  paths:
    include: [TierModel/*, .azuredevops/*]

pr:
  branches:
    include: [main, develop]
    
schedules:
- cron: "0 2 * * *"
  branches:
    include: [main]
```

### Stages Overview

#### Stage 1: Lint
- **Job**: `ScriptAnalyzer`
- PSScriptAnalyzer execution with all severity levels
- Results published as pipeline artifacts
- Build fails on Error-level issues

#### Stage 2: Test
- **Job**: `PesterTests` (Matrix: PowerShell 7.x, 5.1)
- Pester test execution with code coverage
- Test results published to Azure DevOps Test Plans
- Coverage reports in JaCoCo format

#### Stage 3: Package
- **Job**: `ValidateAndPackage`  
- Module manifest validation
- Module import testing
- Package creation with build metadata
- Artifact publishing for deployment

#### Stage 4: Security
- **Job**: `SecurityScan`
- Security-focused PSScriptAnalyzer rules
- Critical issue detection and build failure
- Security results as pipeline artifacts

#### Stage 5: Drift Detection
- **Job**: `DriftAnalysis`
- Scheduled and main branch execution
- Drift detection against test configurations
- State snapshots and error handling
- Comprehensive reporting artifacts

#### Stage 6: Documentation  
- **Job**: `GenerateDocs`
- PlatyPS documentation generation
- Main branch only execution
- Documentation artifact publishing

### Pipeline Variables

```yaml
variables:
  POWERSHELL_TELEMETRY_OPTOUT: 1
  ModulePath: 'TierModel/Modules/TierModel'
```

### Artifact Outputs

| Artifact | Content | Description |
|----------|---------|-------------|
| `ScriptAnalyzer-Results` | Linting CSV | Code quality analysis |
| `TierModel-Module` | Module package | Deployable module files |
| `Security-Analysis` | Security CSV | Security scan results |
| `Drift-Detection-Reports` | JSON reports | Drift analysis data |
| `TierModel-Documentation` | Markdown docs | Generated help files |

## Local CI Testing

### Prerequisites
```powershell
# Install required modules
Set-PSRepository PSGallery -InstallationPolicy Trusted
Install-Module -Name PSScriptAnalyzer -Force
Install-Module -Name Pester -Force -MinimumVersion 5.0.0
Install-Module -Name PlatyPS -Force
```

### Run Linting Locally
```powershell
# Navigate to project root
cd C:\Path\To\TierModel

# Run PSScriptAnalyzer
$results = Invoke-ScriptAnalyzer -Path "TierModel/Modules/TierModel" -Recurse -Severity @('Error', 'Warning', 'Information')

# Display results
$results | Format-Table Severity, RuleName, ScriptName, Line, Message -AutoSize

# Check for errors (CI fails on errors)
$errors = $results | Where-Object { $_.Severity -eq 'Error' }
if ($errors.Count -gt 0) {
    Write-Error "Found $($errors.Count) error(s)"
}
```

### Run Tests Locally
```powershell
# Configure Pester
$config = New-PesterConfiguration
$config.Run.Path = "TierModel/tests"
$config.Output.Verbosity = 'Detailed'
$config.TestResult.Enabled = $true
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = "TierModel/Modules/TierModel/*.psm1"

# Execute tests
$result = Invoke-Pester -Configuration $config

# Display summary
Write-Host "Tests: $($result.PassedCount) passed, $($result.FailedCount) failed"
```

### Run Security Analysis
```powershell
# Security-focused rules
$securityRules = @(
    'PSAvoidUsingPlainTextForPassword'
    'PSAvoidUsingUserNameAndPasswordParams'
    'PSUsePSCredentialType'
    'PSAvoidGlobalVars'
    'PSUseShouldProcessForStateChangingFunctions'
)

$securityResults = Invoke-ScriptAnalyzer -Path "TierModel/Modules/TierModel" -Recurse -IncludeRule $securityRules

if ($securityResults) {
    $securityResults | Format-Table Severity, RuleName, Message -AutoSize
    
    $criticalIssues = $securityResults | Where-Object { $_.Severity -eq 'Error' }
    if ($criticalIssues.Count -gt 0) {
        Write-Error "Found $($criticalIssues.Count) critical security issue(s)"
    }
} else {
    Write-Host "No security issues found" -ForegroundColor Green
}
```

## Configuration Management

### Customizing Pipelines

#### GitHub Actions Customization

Edit `.github/workflows/ci.yml`:

```yaml
# Modify PowerShell versions
strategy:
  matrix:
    powershell-version: ['7.4', '5.1', '7.2']  # Add 7.2

# Change artifact retention
retention-days: 60  # Increase from 30 days

# Add custom test parameters
- name: Run Custom Tests
  run: |
    Invoke-Pester -Path "Tests/Custom" -Tag "Integration"
```

#### Azure DevOps Customization

Edit `.azuredevops/azure-pipelines.yml`:

```yaml  
# Add custom variables
variables:
  CustomTestPath: 'Tests/Custom'
  ArtifactRetention: 60

# Modify agent pool
pool:
  name: 'Custom-Pool'  # Use custom agent pool
  vmImage: 'windows-2022'  # Or specific VM image
```

### Environment-Specific Configuration

#### Development Environment
```powershell
# Disable drift detection on feature branches
if: github.ref != 'refs/heads/main' && github.event_name != 'schedule'
```

#### Production Environment  
```powershell
# Enable additional security scans
- name: Production Security Scan
  if: github.ref == 'refs/heads/main'
  run: |
    # Additional security validation with strict rules
    $securityResults = Invoke-ScriptAnalyzer -Path "TierModel/Modules/TierModel" -Recurse -Severity Error
    if ($securityResults) { exit 1 }
```

## Monitoring & Alerts

### GitHub Actions Monitoring

#### Workflow Status Badges
```markdown
![CI Status](https://github.com/username/TierModel/workflows/TierModel%20CI/badge.svg)
![Security](https://github.com/username/TierModel/workflows/Security/badge.svg)
```

#### Notification Configuration
```yaml
# Add Slack notifications
- name: Notify Slack
  if: failure()
  uses: 8398a7/action-slack@v3
  with:
    status: ${{ job.status }}
    webhook_url: ${{ secrets.SLACK_WEBHOOK }}
```

### Azure DevOps Monitoring

#### Service Hooks
Configure service hooks in Azure DevOps:
- **Build completed**: Send to Teams/Slack
- **Build failed**: Send email notification
- **Security issues**: Create work item

#### Dashboard Configuration
Create Azure DevOps dashboard widgets:
- Build success rate
- Test pass rate  
- Code coverage trends
- Security scan results

## Troubleshooting

### Common Issues

#### PowerShell Version Conflicts
```powershell
# Check PowerShell version in CI
Write-Host "PowerShell version: $($PSVersionTable.PSVersion)"
Write-Host "Edition: $($PSVersionTable.PSEdition)"
```

#### Module Import Failures
```powershell
# Verbose module import for debugging
Import-Module "./TierModel.psm1" -Force -Verbose
Get-Module TierModel -ListAvailable
```

#### Test Failures in CI
```yaml
# Enable verbose test output
- name: Run Tests with Debug
  run: |
    $VerbosePreference = 'Continue'
    $DebugPreference = 'Continue'
    Invoke-Pester -Path "Tests/" -Output Detailed
```

#### Artifact Upload Issues
```yaml
# Check artifact paths exist
- name: Debug Artifacts
  run: |
    Get-ChildItem -Path "." -Recurse -Filter "*.xml" | Select-Object FullName
    Test-Path "./test-results.xml"
```

### Performance Optimization

#### Parallel Testing
```yaml
# GitHub Actions parallel jobs by test tags
strategy:
  matrix:
    test-tag: [Unit, Integration, Audit, Deploy]
steps:
  - name: Run Tagged Tests
    run: |
      $config = New-PesterConfiguration
      $config.Run.Path = "TierModel/tests"
      $config.Filter.Tag = "${{ matrix.test-tag }}"
      Invoke-Pester -Configuration $config
```

#### Caching Dependencies
```yaml
# Cache PowerShell modules
- name: Cache PowerShell Modules
  uses: actions/cache@v3
  with:
    path: ~/.local/share/powershell/Modules
    key: ${{ runner.os }}-psmodules-${{ hashFiles('**/dependencies.json') }}
```

## Best Practices

### Pipeline Design
1. **Fail fast**: Run linting before tests
2. **Parallel execution**: Independent jobs run simultaneously
3. **Artifact management**: Appropriate retention periods
4. **Security first**: Security scans in every pipeline

### Code Quality
1. **Consistent formatting**: Use PSScriptAnalyzer formatting rules
2. **Test coverage**: Maintain > 80% code coverage
3. **Security validation**: Regular security rule updates
4. **Documentation**: Keep pipeline docs updated

### Deployment Strategy  
1. **Branch protection**: Require CI success for main branch
2. **Review requirements**: Mandate code reviews for PRs
3. **Staged deployment**: Dev → Test → Prod progression
4. **Rollback capability**: Maintain deployment artifacts

### Monitoring & Alerting
1. **Proactive monitoring**: Set up failure notifications
2. **Trend analysis**: Track metrics over time  
3. **Performance tracking**: Monitor pipeline execution time
4. **Security alerts**: Immediate notification of security issues

## Summary

The TierModel CI/CD pipelines provide comprehensive testing, security analysis, and artifact management for reliable deployments. All tests are passing, code coverage exceeds targets, and security validation is integrated throughout the pipeline.

For additional documentation, see:
- Test Coverage Roadmap: `tests/TestCoverageRoadmap.md` (in repository)
- [Quick Deployment Guide](quick-deployment-guide.md)
- [Detailed Deployment Guide](detailed-deployment-guide.md)
- [Deployment Methodology](deployment-methodology.md)
