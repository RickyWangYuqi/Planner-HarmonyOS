$layout = & (Join-Path $PSScriptRoot 'deveco.ps1') ui layout --format json
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$tree = $layout | ConvertFrom-Json
function Show-Nodes($nodes) {
  foreach ($node in $nodes) {
    if ($node.text -or $node.type -in 'Button','TextArea','TextInput','Toggle','Slider') {
      '{0}|{1}|{2}|{3}|{4}' -f $node.type,$node.id,$node.text,($node.bounds -join ','),$node.clickable
    }
    if ($node.children) { Show-Nodes $node.children }
  }
}
Show-Nodes $tree
