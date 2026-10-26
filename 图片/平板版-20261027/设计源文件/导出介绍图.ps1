$ErrorActionPreference = 'Stop'
$imageRoot = Split-Path $PSScriptRoot -Parent
$projectRoot = Split-Path (Split-Path $imageRoot -Parent) -Parent
$renderRoot = Join-Path $projectRoot '.tooling\tablet-posters-20261027-render'
$browserCandidates = @('C:\Program Files\Google\Chrome\Application\chrome.exe', 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe')
$browserPath = $browserCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (!$browserPath) { throw '需要安装 Chrome 或 Edge 以导出图片。' }

function Get-PngInfo([string]$Path) {
  $bytes = [IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -lt 24 -or (($bytes[0..7] -join ',') -ne '137,80,78,71,13,10,26,10')) { throw ('不是有效的 PNG：' + $Path) }
  [byte[]]$widthBytes = $bytes[16..19]; [Array]::Reverse($widthBytes)
  [byte[]]$heightBytes = $bytes[20..23]; [Array]::Reverse($heightBytes)
  [pscustomobject]@{ width = [BitConverter]::ToUInt32($widthBytes, 0); height = [BitConverter]::ToUInt32($heightBytes, 0); bytes = $bytes.Length }
}

# 先检查本次截图和比例，全部到齐后才开始导出，避免生成缺图占位符。
$layout = Get-Content -LiteralPath (Join-Path $PSScriptRoot '排版配置.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if (@($layout.posters).Count -ne 8) { throw '排版配置必须包含 8 张介绍图。' }
$sourceChecks = foreach ($poster in $layout.posters) {
  $screenshotPath = Join-Path (Join-Path $imageRoot '原始截图') $poster.screenshot
  if (!(Test-Path -LiteralPath $screenshotPath)) { throw ('缺少本次真机截图：' + $poster.screenshot) }
  $info = Get-PngInfo $screenshotPath
  if ($info.width -ne $poster.expectedScreenshotSize[0] -or $info.height -ne $poster.expectedScreenshotSize[1]) { throw ('截图尺寸与排版不一致：' + $poster.screenshot + '；请核对裁切和排版配置。') }
  [pscustomobject]@{ file = $poster.screenshot; width = $info.width; height = $info.height; sha256 = (Get-FileHash -LiteralPath $screenshotPath -Algorithm SHA256).Hash }
}

New-Item -ItemType Directory -Path $renderRoot -Force | Out-Null
# 独立 profile、隐藏进程；先导出八张单图，最后导出引用成品的总览。
$sources = @($layout.posters | ForEach-Object { Get-Item -LiteralPath (Join-Path $PSScriptRoot ($_.name + '.html')) })
$sources += Get-Item -LiteralPath (Join-Path $PSScriptRoot '00-总览.html')
$checks = foreach ($source in $sources) {
  $outputPath = Join-Path $imageRoot ($source.BaseName + '.png')
  $browserArguments = @('--headless=new', '--disable-gpu', '--hide-scrollbars', '--disable-background-networking', '--no-first-run', '--no-default-browser-check', '--force-color-profile=srgb', '--force-device-scale-factor=1', '--window-size=2880,1920', '--virtual-time-budget=2000', ('--user-data-dir="' + (Join-Path $renderRoot 'profile') + '"'), ('--screenshot="' + $outputPath + '"'), ([Uri]$source.FullName).AbsoluteUri)
  $process = Start-Process -FilePath $browserPath -ArgumentList $browserArguments -WindowStyle Hidden -Wait -PassThru -RedirectStandardError (Join-Path $renderRoot ($source.BaseName + '-error.log')) -RedirectStandardOutput (Join-Path $renderRoot ($source.BaseName + '-output.log'))
  if ($process.ExitCode -ne 0 -or !(Test-Path -LiteralPath $outputPath)) { throw ('图片导出失败：' + $source.Name) }
  $info = Get-PngInfo $outputPath
  if ($info.width -ne 2880 -or $info.height -ne 1920) { throw ('成品必须严格为 2880×1920：' + $source.Name) }
  if ($info.bytes -ge 5000000) { throw ('成品超过单张小于 5,000,000 字节的限制：' + $source.Name + '，实际 ' + $info.bytes + ' 字节。') }
  Write-Host $outputPath
  [pscustomobject]@{ file = ($source.BaseName + '.png'); width = $info.width; height = $info.height; bytes = $info.bytes; sha256 = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash }
}
[pscustomobject]@{ exportedAt = (Get-Date).ToString('o'); screenshotChecks = $sourceChecks; outputChecks = $checks } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $PSScriptRoot '导出校验.json') -Encoding UTF8
Write-Output ('已导出并校验 ' + $checks.Count + ' 张 PNG，尺寸均为 2880×1920，单张均小于 5,000,000 字节。')
