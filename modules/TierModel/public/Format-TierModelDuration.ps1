<#
.SYNOPSIS
    Formats a duration in milliseconds into a human-readable string.

.DESCRIPTION
    Converts a raw milliseconds value into a human-readable duration string using
    four output tiers:
        '<1ms'  — sub-millisecond or zero (never-zero floor guarantee)
        'Xms'   — 1 ms through 999 ms
        'Xs'    — 1 second through 59 seconds
        'Xm Ys' — 1 minute and above

    All tiers use Math.Floor exclusively to avoid rounding artifacts. The final
    (>=60 s) tier uses explicit floor-based integer arithmetic rather than
    [TimeSpan]::TotalMinutes to prevent banker's rounding on the minute component.

.PARAMETER Milliseconds
    Duration in milliseconds as a [double]. Accepts both [int] and [double]
    DurationMs values returned by module cmdlets. Expected input domain is
    finite, non-negative milliseconds.

.OUTPUTS
    [string] Human-readable duration string.

.NOTES
    Expected input domain is finite, non-negative milliseconds.

.EXAMPLE
    Format-TierModelDuration -Milliseconds 0
    Returns '<1ms'

.EXAMPLE
    Format-TierModelDuration -Milliseconds 2254.1343
    Returns '2s'

.EXAMPLE
    Format-TierModelDuration -Milliseconds 140000
    Returns '2m 20s'
#>
function Format-TierModelDuration {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [double]$Milliseconds
    )

    # Sub-1ms floor — covers 0, negatives, and sub-ms values.
    # Must run before any [int] cast so 0.4ms cannot truncate to 0 and render as "0ms".
    if ($Milliseconds -lt 1.0) { return '<1ms' }

    # Sub-second: integer milliseconds.
    if ($Milliseconds -lt 1000.0) {
        return '{0}ms' -f [int][Math]::Floor($Milliseconds)
    }

    # Sub-minute: whole seconds.
    if ($Milliseconds -lt 60000.0) {
        return '{0}s' -f [int][Math]::Floor($Milliseconds / 1000.0)
    }

    # One minute or more: floor-based integer arithmetic.
    # [TimeSpan]::TotalMinutes fed into [int] uses banker's rounding and is non-monotonic
    # (e.g. 90000ms → "2m 30s" instead of "1m 30s"). Explicit floor math is correct.
    $totalSeconds = [long][Math]::Floor($Milliseconds / 1000.0)
    $minutes      = [long][Math]::Floor($totalSeconds / 60.0)
    $seconds      = [int]($totalSeconds % 60)
    return '{0}m {1}s' -f $minutes, $seconds
}
