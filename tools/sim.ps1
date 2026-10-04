# Runs the headless balance harness for several personas in parallel and prints a summary.
# usage: powershell -File tools/sim.ps1 -Runs 40 -Meta none -Tag base
param(
    [int]$Runs = 30,
    [string]$Meta = "none",
    [string]$Tag = "run",
    [string]$Personas = "safe,aggressive,economy,greedy,random,turtle,farmer,stall",
    [string]$Fight = "1"
)
$root = Split-Path -Parent $PSScriptRoot
$godot = "C:\Users\K\AppData\Local\Programs\Godot\bin\godot_console.exe"
$outDir = Join-Path $root "sim\out"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$jobs = @()
foreach ($p in $Personas.Split(",")) {
    $out = "sim/out/$Tag-$Meta-$p.jsonl"
    $jobs += Start-Process -FilePath $godot -ArgumentList @("--headless", "--path", "`"$root`"", "--script", "res://sim/runner.gd", "--", "--persona=$p", "--runs=$Runs", "--meta=$Meta", "--out=$out", "--fight=$Fight") -NoNewWindow -PassThru -RedirectStandardOutput (Join-Path $outDir "$Tag-$Meta-$p.log") -RedirectStandardError (Join-Path $outDir "$Tag-$Meta-$p.err")
}
$jobs | Wait-Process
python (Join-Path $root "tools\analyze.py") (Join-Path $outDir "$Tag-$Meta-*.jsonl")
