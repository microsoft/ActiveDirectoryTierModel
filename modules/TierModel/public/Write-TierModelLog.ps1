function Write-TierModelLog {
    <#
    .SYNOPSIS
    Writes structured log entries with correlation ID for TierModel operations.
    
    .DESCRIPTION
    Provides structured logging with consistent format, correlation ID tracking,
    and optional redaction of sensitive data. Supports multiple log levels
    and automatic time stamping.
    
    .PARAMETER Level
    Log level: Debug, Info, Warning, Error
    
    .PARAMETER Message
    Primary log message (human readable)
    
    .PARAMETER Data
    Optional hashtable of structured data to log (will be converted to JSON)
    
    .PARAMETER LogPath
    Optional override for log file path. Defaults to module logging location.
    
    .PARAMETER PassThru
    Return the structured log entry for testing/inspection.
    
    .EXAMPLE
    Write-TierModelLog -Level Info -Message "Starting deployment" -Data @{ Scope = "FullDeployment"; PreferredDc = "dc01.contoso.com" }
    
    .EXAMPLE
    $logEntry = Write-TierModelLog -Level Warning -Message "Configuration issue detected" -PassThru
    
    .OUTPUTS
    PSCustomObject (only when -PassThru is specified)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Debug', 'Info', 'Warning', 'Error')]
        [string]$Level,
        
        [Parameter(Mandatory)]
        [string]$Message,
        
        [Parameter()]
        [hashtable]$Data = @{},
        
        [Parameter()]
        [string]$LogPath,
        
        [Parameter()]
        [switch]$PassThru
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffZ'
    $correlationId = if ($script:CorrelationId) { $script:CorrelationId } else { [Guid]::NewGuid().ToString() }
    
    # Add correlation ID to data if not already present
    if (-not $Data.ContainsKey('CorrelationId')) {
        $Data['CorrelationId'] = $correlationId
    }
    
    # Redaction placeholder (FR-024: ensure no secrets logged)
    $sanitizedData = $Data.Clone()
    $sensitiveKeys = @('Password', 'Secret', 'Token', 'Key', 'Credential')
    foreach ($key in $sensitiveKeys) {
        if ($sanitizedData.ContainsKey($key)) {
            $sanitizedData[$key] = '[REDACTED]'
        }
    }
    
    # Create structured log entry
    $logEntry = [PSCustomObject]@{
        Timestamp = $timestamp
        Level = $Level
        Message = $Message
        Data = $sanitizedData
        CorrelationId = $correlationId
    }
    
    # Human-readable format for console
    $consoleMessage = "[$timestamp] [$Level] $Message"
    if ($sanitizedData.Count -gt 1) {  # More than just CorrelationId
        $dataString = ($sanitizedData.GetEnumerator() | Where-Object { $_.Key -ne 'CorrelationId' } | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', '
        if ($dataString) {
            $consoleMessage += " | $dataString"
        }
    }
    $consoleMessage += " [CID: $($correlationId.Substring(0,8))]"
    
    # Output to appropriate stream
    switch ($Level) {
        'Debug' { Write-Debug $consoleMessage }
        'Info' { Write-Verbose $consoleMessage }
        'Warning' { Write-Warning $consoleMessage }
        'Error' { 
            # Write to host instead of Write-Error to avoid ErrorRecord objects in pipeline
            Write-Host $consoleMessage -ForegroundColor Red
        }
    }
    
    # File logging (if LogPath specified or module logging enabled)
    if ($LogPath -or $script:LoggingEnabled) {
        $logFile = if ($LogPath) { $LogPath } else { $script:DefaultLogPath }
        
        if ($logFile) {
            try {
                # Ensure directory exists.
                # -WhatIf:$false is load-bearing, for the same reason as the Add-Content below:
                # this is log apparatus, not a previewed change. Without it, a -WhatIf run whose
                # log directory does not already exist has this New-Item suppressed and the
                # Add-Content below throws. This creates a LOG directory only - it is not, and
                # must never become, a write to Active Directory.
                $logDir = Split-Path $logFile -Parent
                if (-not (Test-Path $logDir)) {
                    New-Item -Path $logDir -ItemType Directory -Force -WhatIf:$false | Out-Null
                }
                
                # Append JSON log entry.
                # -WhatIf:$false is load-bearing here. Callers such as Deploy-TierModel.ps1 are
                # [CmdletBinding(SupportsShouldProcess)], so under -WhatIf the inherited
                # $WhatIfPreference suppresses this Add-Content - the ONLY write in this function -
                # and suppression does not throw, so the catch below never fires. The log is the
                # apparatus that RECORDS the preview, not part of the change being previewed.
                #
                # Scope is deliberately this call only. Do NOT set $WhatIfPreference here and do
                # NOT put -WhatIf:$false anywhere near an AD or GroupPolicy cmdlet - that would
                # make -WhatIf perform real directory writes.
                $jsonEntry = $logEntry | ConvertTo-Json -Compress
                Add-Content -Path $logFile -Value $jsonEntry -Encoding UTF8 -WhatIf:$false
            } catch {
                Write-Warning "Failed to write to log file '$logFile': $($_.Exception.Message)"
            }
        }
    }
    
    # Return the structured log entry for testing/inspection only if requested
    if ($PassThru) {
        return $logEntry
    }
}