param(
  [string]$Mensaje = "deploy(preproduccion): actualizacion manual"
)

$ErrorActionPreference = 'Stop'

if (!(Test-Path .git)) {
  git init -b main
}

$originConfigured = git remote | Select-String '^origin$'
if (-not $originConfigured) {
  throw 'No existe remoto origin. Configuralo con: git remote add origin <url>'
}

git add -A
git commit --allow-empty -m $Mensaje
git push -u origin HEAD:preproduccion

Write-Host "Preproduccion publicada en la rama remota preproduccion."

