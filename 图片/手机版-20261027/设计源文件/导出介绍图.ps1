$ErrorActionPreference = 'Stop'
$imageRoot = Split-Path $PSScriptRoot -Parent
$projectRoot = Split-Path (Split-Path $imageRoot -Parent) -Parent
$renderRoot = Join-Path $projectRoot '.tooling\phone-posters-20261027-render'
New-Item -ItemType Directory -Path $renderRoot -Force | Out-Null
$browserCandidates = @('C:\Program Files\Google\Chrome\Application\chrome.exe','C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe')
$browserPath = $browserCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (!$browserPath) { throw '需要安装 Chrome 或 Edge 以导出图片。' }
# 开始前核对全部原图，避免输出带缺图占位符的成品。
$layout = Get-Content -LiteralPath (Join-Path $PSScriptRoot '排版配置.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($item in $layout) {
  $images = if ($item.screenshot) { @($item.screenshot) } else { @($item.screenshots) }
  foreach ($name in $images) {
    if (!(Test-Path -LiteralPath (Join-Path (Join-Path $imageRoot '原始截图') $name))) { throw ('缺少原始截图：' + $name) }
  }
}
# 先导出八张竖版，再导出引用成品的总览；不修改或操作手机。
$sources = Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.html' | Sort-Object @{ Expression = { $_.BaseName.StartsWith('00-') } }, Name
foreach ($source in $sources) {
  $outputPath = Join-Path $imageRoot ($source.BaseName + '.png')
  $size = if ($source.BaseName.StartsWith('00-')) { '2560,1440' } else { '1440,2560' }
  $browserArguments = @('--headless=new','--disable-gpu','--hide-scrollbars','--disable-background-networking','--no-first-run','--no-default-browser-check','--force-color-profile=srgb','--force-device-scale-factor=1',('--window-size=' + $size),'--virtual-time-budget=2000',('--user-data-dir="' + (Join-Path $renderRoot 'profile') + '"'),('--screenshot="' + $outputPath + '"'),([Uri]$source.FullName).AbsoluteUri)
  $process = Start-Process -FilePath $browserPath -ArgumentList $browserArguments -WindowStyle Hidden -Wait -PassThru -RedirectStandardError (Join-Path $renderRoot ($source.BaseName + '-error.log')) -RedirectStandardOutput (Join-Path $renderRoot ($source.BaseName + '-output.log'))
  if ($process.ExitCode -ne 0 -or !(Test-Path -LiteralPath $outputPath)) { throw ('图片导出失败：' + $source.Name) }
  Write-Output $outputPath
}
# 读取 PNG 文件头核对尺寸并记录摘要，无须重新编码图片。
$checks = foreach ($source in $sources) {
  $outputPath = Join-Path $imageRoot ($source.BaseName + '.png')
  $bytes = [IO.File]::ReadAllBytes($outputPath)
  $widthBytes = $bytes[16..19]; [Array]::Reverse($widthBytes)
  $heightBytes = $bytes[20..23]; [Array]::Reverse($heightBytes)
  $width = [BitConverter]::ToUInt32($widthBytes, 0)
  $height = [BitConverter]::ToUInt32($heightBytes, 0)
  $expected = if ($source.BaseName.StartsWith('00-')) { @(2560,1440) } else { @(1440,2560) }
  if ($width -ne $expected[0] -or $height -ne $expected[1]) { throw ('尺寸校验失败：' + $source.Name) }
  [pscustomobject]@{ file = ($source.BaseName + '.png'); width = $width; height = $height; bytes = $bytes.Length; sha256 = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash }
}
$checks | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $PSScriptRoot '导出校验.json') -Encoding UTF8
