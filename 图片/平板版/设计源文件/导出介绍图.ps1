$ErrorActionPreference = 'Stop'
$imageRoot = Split-Path $PSScriptRoot -Parent
$projectRoot = (Resolve-Path (Join-Path $imageRoot '..\..')).Path
$renderRoot = Join-Path $projectRoot '.tooling\tablet-posters-render'
New-Item -ItemType Directory -Path $renderRoot -Force | Out-Null
$browserPath = @('C:\Program Files\Google\Chrome\Application\chrome.exe','C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe') | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (!$browserPath) { throw '需要 Chrome 或 Edge 导出图片。' }
# 所有成图使用严格3:2比例；最后生成总览，确保引用的是当前六张成图。
Add-Type -AssemblyName System.Drawing
$sources = Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.html' | Sort-Object @{Expression = { $_.BaseName.StartsWith('00-') }}, Name
foreach ($source in $sources) {
 $outputPath = Join-Path $imageRoot ($source.BaseName + '.png')
 $size = '2880,1920'
 $browserArguments = @('--headless=new','--disable-gpu','--hide-scrollbars','--disable-background-networking','--no-first-run','--no-default-browser-check','--force-color-profile=srgb','--force-device-scale-factor=1',('--window-size=' + $size),'--virtual-time-budget=2000',('--user-data-dir="' + (Join-Path $renderRoot 'profile') + '"'),('--screenshot="' + $outputPath + '"'),([Uri]$source.FullName).AbsoluteUri)
 $process = Start-Process -FilePath $browserPath -ArgumentList $browserArguments -WindowStyle Hidden -Wait -PassThru -RedirectStandardError (Join-Path $renderRoot ($source.BaseName + '.log'))
 if ($process.ExitCode -ne 0 -or !(Test-Path -LiteralPath $outputPath)) { throw ('导出失败：' + $source.Name) }
 $bitmap = [System.Drawing.Image]::FromFile($outputPath)
 try {
  if ($bitmap.Width -lt 1920 -or $bitmap.Height -lt 1280 -or $bitmap.Width * 2 -ne $bitmap.Height * 3) {
   throw ('图片尺寸或3:2比例不符合要求：' + $source.Name)
  }
 } finally { $bitmap.Dispose() }
 if ((Get-Item -LiteralPath $outputPath).Length -ge 5000000) { throw ('PNG达到5MB上限：' + $source.Name) }
 Write-Output $outputPath
}
