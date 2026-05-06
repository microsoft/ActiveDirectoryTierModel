function Get-TierModelGpoTemplate {
    <#
    .SYNOPSIS
    Parses GptTmpl.inf file content into structured object.
    
    .DESCRIPTION
    Reads and parses a GptTmpl.inf file, returning structured data for editing.
    Based on the GpoEditing.ps1.old Get-GpoTemplateContent function.
    
    .PARAMETER Path
    Path to the GptTmpl.inf file to parse.
    
    .PARAMETER CorrelationId
    Optional correlation ID for logging and tracking.
    
    .EXAMPLE
    $template = Get-TierModelGpoTemplate -Path "C:\GPO\{GUID}\Machine\Microsoft\Windows NT\SecEdit\GptTmpl.inf"
    
    .OUTPUTS
    PSCustomObject with parsed GptTmpl.inf structure including sections, properties, and metadata.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [string]$CorrelationId = [System.Guid]::NewGuid().ToString()
    )
    
    Write-TierModelLog -Level Info -Message "Parsing GPO template" -Data @{
        Path = $Path
        CorrelationId = $CorrelationId
    } | Out-Null
    
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "GptTmpl.inf file not found: $Path"
    }
    
    $content = @{
        Sections = @{}
        RawLines = @()
        FilePath = $Path
        Encoding = 'Unicode'
        Modified = $false
    }
    
    try {
        # Read file with Unicode encoding (standard for GptTmpl.inf)
        $lines = Get-Content -LiteralPath $Path -Encoding Unicode
        $content.RawLines = $lines
        
        $currentSection = $null
        $lineNumber = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            $trimmedLine = $line.Trim()
            
            # Skip empty lines and comments
            if ([string]::IsNullOrEmpty($trimmedLine) -or $trimmedLine.StartsWith(';')) {
                continue
            }
            
            # Check for section header
            if ($trimmedLine -match '^\[([^\]]+)\]$') {
                $currentSection = $matches[1]
                
                if (-not $content.Sections.ContainsKey($currentSection)) {
                    $content.Sections[$currentSection] = @{
                        Name = $currentSection
                        Lines = @{}
                        RawLines = @()
                        StartLine = $lineNumber
                    }
                }
                continue
            }
            
            # Parse property lines (Key=Value)
            if ($trimmedLine -match '^([^=]+)=(.*)$') {
                if ($currentSection) {
                    $key = $matches[1].Trim()
                    $value = $matches[2].Trim()
                    
                    $content.Sections[$currentSection].Lines[$key] = $value
                    $content.Sections[$currentSection].RawLines += $line
                } else {
                    Write-Warning "Found property outside of section at line $lineNumber`: $trimmedLine"
                }
                continue
            }
            
            # Handle other content
            if ($currentSection) {
                $content.Sections[$currentSection].RawLines += $line
            }
        }
        
        Write-TierModelLog -Level Info -Message "GPO template parsed successfully" -Data @{
            Path = $Path
            SectionCount = $content.Sections.Count
            CorrelationId = $CorrelationId
        } | Out-Null
        
        return [PSCustomObject]$content
        
    } catch {
        Write-TierModelLog -Level Error -Message "Failed to parse GPO template" -Data @{
            Path = $Path
            Exception = $_.Exception.Message
            CorrelationId = $CorrelationId
        } | Out-Null
        
        throw "Failed to parse GptTmpl.inf: $($_.Exception.Message)"
    }
}