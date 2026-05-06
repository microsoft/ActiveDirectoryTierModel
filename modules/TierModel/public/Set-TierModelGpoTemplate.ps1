function Set-TierModelGpoTemplate {
    <#
    .SYNOPSIS
    Writes structured content back to GptTmpl.inf file.
    
    .DESCRIPTION
    Writes the modified template content back to the GptTmpl.inf file with atomic operation.
    Based on the GpoEditing.ps1.old Set-GpoTemplateContent function.
    
    .PARAMETER TemplateContent
    The template content object from Get-TierModelGpoTemplate with modifications.
    
    .PARAMETER BackupPath
    Optional path for backup of original file before modification.
    
    .PARAMETER CorrelationId
    Optional correlation ID for logging and tracking.
    
    .EXAMPLE
    Set-TierModelGpoTemplate -TemplateContent $template -BackupPath "C:\Backup\GptTmpl.inf.bak"
    
    .OUTPUTS
    None. Writes the modified content to the original file path.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [PSObject]$TemplateContent,
        
        [string]$BackupPath,
        
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )
    
    Write-TierModelLog -Level Info -Message "Writing GPO template" -Data @{
        FilePath = $TemplateContent.FilePath
        BackupPath = $BackupPath
        CorrelationId = $CorrelationId
    } | Out-Null
    
    if (-not $TemplateContent.Modified) {
        Write-TierModelLog -Level Info -Message "Template content not modified, skipping write" -Data @{
            CorrelationId = $CorrelationId
        } | Out-Null
        return
    }
    
    try {
        # Create backup if requested
        if ($BackupPath) {
            if ($PSCmdlet.ShouldProcess($TemplateContent.FilePath, "Create backup to $BackupPath")) {
                Copy-Item -LiteralPath $TemplateContent.FilePath -Destination $BackupPath -Force
                Write-TierModelLog -Level Info -Message "Created backup of GPO template" -Data @{
                    BackupPath = $BackupPath
                    CorrelationId = $CorrelationId
                } | Out-Null
            }
        }
        
        if ($PSCmdlet.ShouldProcess($TemplateContent.FilePath, "Write modified GPO template")) {
            # Generate new content
            $newLines = @()
            $processedSections = @{}
            
            # Process original lines, updating sections we have modifications for
            $currentSection = $null
            $skipToNextSection = $false
            
            foreach ($line in $TemplateContent.RawLines) {
                # Check for section header
                if ($line -match '^\s*\[([^\]]+)\]\s*$') {
                    $currentSection = $matches[1].Trim()
                    $skipToNextSection = $false
                    
                    # Add section header
                    $newLines += $line
                    
                    # If we have modifications for this section, add them
                    if ($TemplateContent.Sections.ContainsKey($currentSection)) {
                        $section = $TemplateContent.Sections[$currentSection]
                        
                        # Add all properties for this section
                        foreach ($key in $section.Lines.Keys) {
                            $value = $section.Lines[$key]
                            $newLines += "$key=$value"
                        }
                        
                        $processedSections[$currentSection] = $true
                        $skipToNextSection = $true
                    }
                    continue
                }
                
                # Skip original property lines if we're replacing the section
                if ($skipToNextSection -and $line -match '^\s*[^=]+\s*=') {
                    continue
                }
                
                # Keep other lines (comments, empty lines, etc.)
                if (-not ($line -match '^\s*[^=]+\s*=')) {
                    $newLines += $line
                }
            }
            
            # Add any new sections that weren't in the original file
            foreach ($sectionName in $TemplateContent.Sections.Keys) {
                if (-not $processedSections.ContainsKey($sectionName)) {
                    $newLines += ""
                    $newLines += "[$sectionName]"
                    
                    $section = $TemplateContent.Sections[$sectionName]
                    foreach ($key in $section.Lines.Keys) {
                        $value = $section.Lines[$key]
                        $newLines += "$key=$value"
                    }
                }
            }
            
            # Write file with Unicode encoding (atomic operation)
            $tempFile = "$($TemplateContent.FilePath).tmp"
            try {
                $newLines | Out-File -FilePath $tempFile -Encoding Unicode -Force
                Move-Item -Path $tempFile -Destination $TemplateContent.FilePath -Force
                
                Write-TierModelLog -Level Info -Message "GPO template written successfully" -Data @{
                    FilePath = $TemplateContent.FilePath
                    LineCount = $newLines.Count
                    CorrelationId = $CorrelationId
                } | Out-Null
                
            } catch {
                # Clean up temp file on error
                if (Test-Path $tempFile) {
                    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
                }
                throw
            }
        }
        
    } catch {
        Write-TierModelLog -Level Error -Message "Failed to write GPO template" -Data @{
            FilePath = $TemplateContent.FilePath
            Exception = $_.Exception.Message
            CorrelationId = $CorrelationId
        } | Out-Null
        
        throw "Failed to write GptTmpl.inf: $($_.Exception.Message)"
    }
}