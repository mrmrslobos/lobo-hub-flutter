$patterns = @(
  '^\s*final authProvider = context\.read<AuthProvider>\(\);\s*$',
  '^\s*final syncProvider = context\.read<SyncProvider>\(\);\s*$',
  '^\s*final authProvider = context\.watch<AuthProvider>\(\);\s*$',
  '^\s*final syncProvider = context\.watch<SyncProvider>\(\);\s*$'
)

Get-ChildItem -Path "lib" -Filter "*.dart" -Recurse | ForEach-Object {
  $lines = Get-Content $_.FullName
  $out = New-Object System.Collections.ArrayList
  $i = 0
  while ($i -lt $lines.Count) {
    $line = $lines[$i]
    $matched = $false
    foreach ($p in $patterns) {
      if ($line -match $p) {
        [void]$out.Add($line)
        $i++
        while ($i -lt $lines.Count -and ($lines[$i] -match $p)) { $i++ }
        $matched = $true
        break
      }
    }
    if (-not $matched) {
      [void]$out.Add($line)
      $i++
    }
  }
  $newText = ($out -join "`n") + "`n"
  $oldText = [IO.File]::ReadAllText($_.FullName)
  if ($newText -ne $oldText) {
    [IO.File]::WriteAllText($_.FullName, $newText)
    Write-Host "deduped $($_.FullName)"
  }
}
