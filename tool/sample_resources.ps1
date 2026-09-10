<#
.SYNOPSIS
  Samples CPU% and memory of the dashboard + Unity processes to a CSV, once a
  second, for the UI-smoothness and endurance/soak performance stages.

.DESCRIPTION
  Complements tool/ws_perf_test.dart (which measures the WebSocket pipeline) by
  watching the two processes themselves. Run it alongside a live/soak session and
  chart the CSV afterwards: a working-set that climbs and never settles over a
  long run is the leak signal; sustained high CPU explains UI jank.

  CPU% is (delta CPU-seconds) / (interval x logical cores) x 100, so 100% = one
  full core. It is blank on the first sample of each process (no baseline yet).

.EXAMPLE
  # 30-minute soak, both processes (Unity build + Flutter dashboard):
  powershell -ExecutionPolicy Bypass -File tool/sample_resources.ps1 -Seconds 1800

.EXAMPLE
  # Unity running in the editor instead of a build:
  ... -Names 'Unity','telehealth_dashboard'
#>
param(
  [string[]]$Names = @('Smart Game', 'Unity', 'telehealth_dashboard'),
  [int]$Seconds = 120,
  [int]$IntervalMs = 1000,
  [string]$Out = "resources_$(Get-Date -Format yyyyMMdd_HHmmss).csv"
)

$cores = [Environment]::ProcessorCount
"timestamp,elapsed_s,pid,name,cpu_pct,working_set_mb,private_mb" |
  Out-File -FilePath $Out -Encoding utf8

$prev = @{}
$start = Get-Date
$prevTime = $start
Write-Host "Sampling $($Names -join ', ') for $Seconds s -> $Out  ($cores cores)"

while (((Get-Date) - $start).TotalSeconds -lt $Seconds) {
  Start-Sleep -Milliseconds $IntervalMs
  $now = Get-Date
  $dt = ($now - $prevTime).TotalSeconds
  $prevTime = $now
  $elapsed = [math]::Round(($now - $start).TotalSeconds, 1)

  foreach ($n in $Names) {
    Get-Process -Name $n -ErrorAction SilentlyContinue | ForEach-Object {
      $p = $_
      $cpuNow = $p.TotalProcessorTime.TotalSeconds
      $cpuPct = ''
      if ($prev.ContainsKey($p.Id) -and $dt -gt 0) {
        $cpuPct = [math]::Round((($cpuNow - $prev[$p.Id]) / ($dt * $cores)) * 100, 1)
      }
      $prev[$p.Id] = $cpuNow
      $wsMb = [math]::Round($p.WorkingSet64 / 1MB, 1)
      $privMb = [math]::Round($p.PrivateMemorySize64 / 1MB, 1)
      ("{0},{1},{2},{3},{4},{5},{6}" -f `
          $now.ToString('HH:mm:ss'), $elapsed, $p.Id, $p.ProcessName, $cpuPct, $wsMb, $privMb) |
        Add-Content -Path $Out -Encoding utf8
    }
  }
}
Write-Host "Done. Wrote $Out"
