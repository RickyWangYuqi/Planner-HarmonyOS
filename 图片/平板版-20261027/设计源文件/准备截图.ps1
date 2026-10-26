$ErrorActionPreference = 'Stop'
$imageRoot = Split-Path $PSScriptRoot -Parent
$projectRoot = Split-Path (Split-Path $imageRoot -Parent) -Parent
$captureRoot = Join-Path $projectRoot '.tooling\store-tablet-20261027'
$workRoot = Join-Path $projectRoot '.tooling\tablet-posters-20261027-viewport'
$outputRoot = Join-Path $imageRoot '原始截图'

# 只处理本轮列出的八张演示界面；不遍历其他截图，也不操作设备。
$names = @(
  '01-双栏日程',
  '02-周期打卡',
  '03-自动接续',
  '04-打卡回顾',
  '05-分组与进度',
  '06-未来安排',
  '07-个性设置',
  '08-深色主题'
)
$browserCandidates = @('C:\Program Files\Google\Chrome\Application\chrome.exe', 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe')
$browserPath = $browserCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (!$browserPath) { throw '需要安装 Chrome 或 Edge 以准备截图。' }

function Get-PngInfo([string]$Path) {
  $bytes = [IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -lt 24 -or (($bytes[0..7] -join ',') -ne '137,80,78,71,13,10,26,10')) { throw ('不是有效的 PNG：' + $Path) }
  [byte[]]$widthBytes = $bytes[16..19]; [Array]::Reverse($widthBytes)
  [byte[]]$heightBytes = $bytes[20..23]; [Array]::Reverse($heightBytes)
  [pscustomobject]@{ width = [BitConverter]::ToUInt32($widthBytes, 0); height = [BitConverter]::ToUInt32($heightBytes, 0); bytes = $bytes.Length }
}

# 全部通过尺寸检查后才导出，避免使用未完成或不匹配的拍摄素材。
$sourceChecks = foreach ($name in $names) {
  $inputPath = Join-Path $captureRoot ($name + '-full.png')
  if (!(Test-Path -LiteralPath $inputPath)) { throw ('缺少本次全屏截图：' + $name + '-full.png') }
  $info = Get-PngInfo $inputPath
  if ($info.width -ne 2800 -or $info.height -ne 1840) { throw ('全屏截图必须为 2800×1840：' + $name) }
  [pscustomobject]@{ file = ($name + '-full.png'); width = $info.width; height = $info.height; sha256 = (Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash }
}

New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
$checks = foreach ($name in $names) {
  $inputPath = Join-Path $captureRoot ($name + '-full.png')
  $outputPath = Join-Path $outputRoot ($name + '.png')
  $htmlPath = Join-Path $workRoot ($name + '-viewport.html')
  $imageUri = [System.Net.WebUtility]::HtmlEncode(([Uri]$inputPath).AbsoluteUri)
  # 原图保持 2800×1840；窗口仅展示纵向 [88,1777)，无缩放、滤镜或界面重绘。
  $html = @"
<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=2800, initial-scale=1"><title>序笺平板截图 · $name</title>
<style>
*{box-sizing:border-box}html,body{margin:0;padding:0;width:2800px;height:1689px;overflow:hidden;background:transparent}
.viewport{position:relative;width:2800px;height:1689px;overflow:hidden}
img{position:absolute;left:0;top:-88px;display:block;width:2800px;height:1840px;max-width:none;max-height:none}
</style></head><body><main class="viewport"><img src="$imageUri" width="2800" height="1840" loading="eager" decoding="sync" alt=""></main></body></html>
"@
  [IO.File]::WriteAllText($htmlPath, $html, $utf8WithoutBom)
  $browserArguments = @('--headless=new', '--disable-gpu', '--hide-scrollbars', '--disable-background-networking', '--no-first-run', '--no-default-browser-check', '--force-color-profile=srgb', '--force-device-scale-factor=1', '--window-size=2800,1689', '--virtual-time-budget=2000', ('--user-data-dir="' + (Join-Path $workRoot 'profile') + '"'), ('--screenshot="' + $outputPath + '"'), ([Uri]$htmlPath).AbsoluteUri)
  $startedAt = Get-Date
  $process = Start-Process -FilePath $browserPath -ArgumentList $browserArguments -WindowStyle Hidden -Wait -PassThru -RedirectStandardError (Join-Path $workRoot ($name + '-error.log')) -RedirectStandardOutput (Join-Path $workRoot ($name + '-output.log'))
  if ($process.ExitCode -ne 0 -or !(Test-Path -LiteralPath $outputPath)) { throw ('应用视口导出失败：' + $name) }
  if ((Get-Item -LiteralPath $outputPath).LastWriteTime -lt $startedAt) { throw ('本次未生成新截图：' + $name) }
  $info = Get-PngInfo $outputPath
  if ($info.width -ne 2800 -or $info.height -ne 1689) { throw ('应用区域尺寸必须为 2800×1689：' + $name) }
  Write-Host $outputPath
  [pscustomobject]@{ file = ($name + '.png'); width = $info.width; height = $info.height; bytes = $info.bytes; cropBox = @(0,88,2800,1777); sha256 = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash }
}
[pscustomobject]@{ preparedAt = (Get-Date).ToString('o'); method = '原尺寸图片固定 HTML 视口导出，top=-88px'; sourceChecks = $sourceChecks; outputChecks = $checks } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $PSScriptRoot '截图准备校验.json') -Encoding UTF8
Write-Output ('已准备 ' + $checks.Count + ' 张 2800×1689 应用区域截图，去除顶部 88px 与底部 63px。')
