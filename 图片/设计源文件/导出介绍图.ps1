$ErrorActionPreference = 'Stop'
$imageRoot = Split-Path $PSScriptRoot -Parent
$projectRoot = Split-Path $imageRoot -Parent
$renderRoot = Join-Path $projectRoot '.tooling\store-assets-render'
New-Item -ItemType Directory -Path $renderRoot -Force | Out-Null
$browserCandidates = @('C:\Program Files\Google\Chrome\Application\chrome.exe','C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe')
$browserPath = $browserCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (!$browserPath) { throw '需要安装 Chrome 或 Edge 以导出图片。' }
# 总览必须最后导出，保证引用的是本轮更新后的六张竖版。
$sources = Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.html' | Sort-Object @{ Expression = { $_.BaseName.StartsWith('00-') } }, Name
foreach ($source in $sources) {
  $outputPath = Join-Path $imageRoot ($source.BaseName + '.png')
  $size = if ($source.BaseName.StartsWith('00-')) { '1920,1080' } else { '1440,2560' }
  $browserArguments = @('--headless=new','--disable-gpu','--hide-scrollbars','--disable-background-networking','--no-first-run','--no-default-browser-check','--force-color-profile=srgb','--force-device-scale-factor=1',('--window-size=' + $size),'--virtual-time-budget=2000',('--user-data-dir="' + (Join-Path $renderRoot 'profile') + '"'),('--screenshot="' + $outputPath + '"'),([Uri]$source.FullName).AbsoluteUri)
  $process = Start-Process -FilePath $browserPath -ArgumentList $browserArguments -WindowStyle Hidden -Wait -PassThru -RedirectStandardError (Join-Path $renderRoot ($source.BaseName + '-error.log')) -RedirectStandardOutput (Join-Path $renderRoot ($source.BaseName + '-output.log'))
  if ($process.ExitCode -ne 0 -or !(Test-Path -LiteralPath $outputPath)) { throw ('图片导出失败：' + $source.Name) }
  Write-Output $outputPath
}
