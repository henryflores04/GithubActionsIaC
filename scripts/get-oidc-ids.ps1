# get-oidc-ids.ps1
#
# Obtiene el ID numerico del propietario y del repositorio de GitHub, que son
# necesarios para construir el subject OIDC con IDs inmutables:
#
#   repo:OWNER@OWNER_ID/REPO@REPO_ID:environment:dev
#
# Uso:
#   pwsh ./scripts/get-oidc-ids.ps1
#   pwsh ./scripts/get-oidc-ids.ps1 -Owner henryflores04 -Repo GithubActionsIaC
#
# No requiere autenticacion para repositorios publicos. Para repositorios
# privados, exporta un token antes de ejecutarlo:
#   $env:GITHUB_TOKEN = "ghp_..."

param(
    [string]$Owner = "henryflores04",
    [string]$Repo = "GithubActionsIaC"
)

$ErrorActionPreference = "Stop"

$url = "https://api.github.com/repos/$Owner/$Repo"
$headers = @{
    "Accept"     = "application/vnd.github+json"
    "User-Agent" = "get-oidc-ids"
}

if ($env:GITHUB_TOKEN) {
    $headers["Authorization"] = "Bearer $env:GITHUB_TOKEN"
}

Write-Host "Consultando $url ..." -ForegroundColor Cyan

try {
    $repo = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
} catch {
    Write-Host "No se pudo consultar el repositorio." -ForegroundColor Red
    Write-Host $_.Exception.Message
    Write-Host ""
    Write-Host "Si el repositorio es privado, define un token:" -ForegroundColor Yellow
    Write-Host '  $env:GITHUB_TOKEN = "ghp_..."' -ForegroundColor Yellow
    exit 1
}

$ownerId = $repo.owner.id
$repoId = $repo.id

Write-Host ""
Write-Host "Repositorio : $($repo.full_name)" -ForegroundColor Green
Write-Host "Owner       : $($repo.owner.login)"
Write-Host "OWNER_ID    : $ownerId"
Write-Host "REPO_ID     : $repoId"
Write-Host ""
Write-Host "Subject OIDC (IDs inmutables):" -ForegroundColor Cyan
Write-Host "  repo:$($repo.owner.login)@$ownerId/$($repo.name)@$repoId:environment:dev"
Write-Host ""
Write-Host "Subject OIDC (formato heredado):" -ForegroundColor Cyan
Write-Host "  repo:$($repo.owner.login)/$($repo.name):environment:dev"
Write-Host ""
Write-Host "Para bootstrap/terraform.tfvars:" -ForegroundColor Yellow
Write-Host "  github_owner_id = `"$ownerId`""
Write-Host "  github_repo_id  = `"$repoId`""
