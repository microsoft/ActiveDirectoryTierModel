# Helper functions for prerequisite test assertions
# Tags: Helper,Prereq

function Assert-PrereqResultStructure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Result,
        [Parameter()][string]$Context = 'Generic'
    )

    # Basic shape assertions
    $Result | Should -Not -BeNull -Because "Prereq result should not be null ($Context)"
    $Result.Valid | Should -BeOfType [bool] -Because "Valid should be boolean ($Context)"
    # Don't use pipeline for array type checking - it unrolls the array
    Should -ActualValue $Result.Errors -BeOfType [array] -Because "Errors should be array ($Context)"
    Should -ActualValue $Result.Remediation -BeOfType [array] -Because "Remediation should be array ($Context)"
    $Result.EnvironmentSnapshot | Should -BeOfType [psobject] -Because "EnvironmentSnapshot should be object ($Context)"

    # Common expected keys (soft assertions)
    foreach ($key in 'PowerShellVersion','IsElevated','PreferredDcReachable') {
        if ($Result.EnvironmentSnapshot.PSObject.Properties.Name -contains $key) {
            $Result.EnvironmentSnapshot.$key | Should -Not -BeNullOrEmpty -Because "Snapshot key $key should be populated ($Context)"
        }
    }
}

# Export function for testing (only if running as module)
if (Get-Command Export-ModuleMember -ErrorAction SilentlyContinue) {
    try { Export-ModuleMember -Function Assert-PrereqResultStructure } catch { }
}
