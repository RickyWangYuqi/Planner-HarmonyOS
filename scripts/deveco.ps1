# 保留 -p 等 Hvigor/CLI 原生参数，不启用 PowerShell 高级参数绑定。
$CliArguments = @($args)

$ErrorActionPreference = 'Stop'
$projectDirectory = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$toolDirectory = Join-Path $projectDirectory '.tooling'
$devecoCommand = (Get-Command devecocli.cmd -ErrorAction Stop).Source
$nodeCommand = (Get-Command node.exe -ErrorAction Stop).Source
$cliEntry = Join-Path (Split-Path $devecoCommand) 'node_modules\@deveco\deveco-cli\cli.js'
$studioPath = $env:DEVECO_CLI_STUDIO_PATH
if (-not $studioPath) { $studioPath = $env:DEVECO_HOME }
if (-not $studioPath -and (Test-Path -LiteralPath 'D:\Software\DevEco Studio\product-info.json')) {
  $studioPath = 'D:\Software\DevEco Studio'
}
if (-not $CliArguments -or $CliArguments.Count -eq 0) { $CliArguments = @('--help') }

# 工具专用缓存放进项目，不修改用户配置或登录状态。
$environmentOverrides = @{
  DEVECO_CLI_DATA_DIR = (Join-Path $toolDirectory 'deveco-cli')
  DEVECO_CLI_DISABLE_TELEMETRY = '1'
  DEVECO_CLI_DISABLE_UPDATE = 'all'
  HVIGOR_USER_HOME = (Join-Path $toolDirectory 'hvigor')
  PLANER_CLI_LOG_DIRECTORY = (Join-Path $toolDirectory 'deveco-logs')
}
if ($studioPath) {
  $environmentOverrides['DEVECO_CLI_STUDIO_PATH'] = $studioPath
  $environmentOverrides['DEVECO_SDK_HOME'] = Join-Path $studioPath 'sdk'
  if ($CliArguments[0] -eq 'hvigor') {
    $environmentOverrides['JAVA_HOME'] = Join-Path $studioPath 'jbr'
    $environmentOverrides['PATH'] = (Join-Path $studioPath 'jbr\bin') + [IO.Path]::PathSeparator + $env:PATH
  }
}
$originalEnvironment = @{}
foreach ($environmentName in $environmentOverrides.Keys) {
  $originalEnvironment[$environmentName] = [Environment]::GetEnvironmentVariable($environmentName, 'Process')
  [Environment]::SetEnvironmentVariable($environmentName, $environmentOverrides[$environmentName], 'Process')
}
New-Item -ItemType Directory -Path $toolDirectory -Force | Out-Null
Push-Location $projectDirectory
try {
  if ($CliArguments[0] -eq 'hvigor') {
    if (-not $studioPath) { throw '运行 Hvigor 需设置 DEVECO_CLI_STUDIO_PATH。' }
    $hvigorArguments = @($CliArguments | Select-Object -Skip 1)
    & (Join-Path $studioPath 'tools\node\node.exe') (Join-Path $studioPath 'tools\hvigor\bin\hvigorw.js') @hvigorArguments
  } else {
    & $nodeCommand --require (Join-Path $PSScriptRoot 'cli-log-redirect.cjs') $cliEntry @CliArguments
  }
  $commandExitCode = $LASTEXITCODE
} finally {
  Pop-Location
  foreach ($environmentName in $originalEnvironment.Keys) {
    [Environment]::SetEnvironmentVariable($environmentName, $originalEnvironment[$environmentName], 'Process')
  }
}
exit $commandExitCode



