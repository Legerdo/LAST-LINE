# Runs Codex CLI's built-in image_gen tool with a prompt stored in art_src/prompts/<Name>.txt.
# Usage: powershell -File tools/gen_image.ps1 -Name facilities_a [-Inputs a.png,b.png]
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$Model = "gpt-6-sol",
    [string[]]$Inputs
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$artDir = Join-Path $root 'art_src'
$promptFile = Join-Path $artDir "prompts\$Name.txt"
# Prompts are stored on multiple lines for readability; Codex receives a single line.
$prompt = ((Get-Content -LiteralPath $promptFile -Encoding UTF8) -join ' ').Trim()
$codexJs = Join-Path $env:APPDATA 'npm\node_modules\@openai\codex\bin\codex.js'
$cliArgs = @($codexJs, 'exec', '--skip-git-repo-check', '-s', 'workspace-write', '-m', $Model, $prompt)
if ($Inputs) { $cliArgs += '-i'; $cliArgs += $Inputs }
Push-Location $artDir
try { & node @cliArgs } finally { Pop-Location }
