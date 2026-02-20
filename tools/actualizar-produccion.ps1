param(
  [string]$Mensaje = "deploy(produccion): actualizacion manual"
)

$ErrorActionPreference = 'Stop'

if (!(Test-Path .git)) {
  throw 'Este proyecto aun no esta inicializado con git.'
}

$originConfigured = git remote | Select-String '^origin$'
if (-not $originConfigured) {
  throw 'No existe remoto origin. Configuralo con: git remote add origin <url>'
}

$currentBranch = (git rev-parse --abbrev-ref HEAD).Trim()
if ($currentBranch -ne 'main') {
  throw "Estas en '$currentBranch'. Cambia a main para publicar produccion."
}

git add -A
git commit --allow-empty -m $Mensaje
git push origin main

Write-Host 'Produccion publicada en main.'

