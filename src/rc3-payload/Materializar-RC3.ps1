[CmdletBinding()]
param(
    [string]$Destino = (Join-Path (Get-Location).Path 'RestauradorUniversal_v1.0.1_RC3.ps1'),
    [switch]$Forcar
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedSha256 = '18f3a9dbac5d332be1b6e7df37d04579a816b3850736590ac5d972db91c0c506'
$ExpectedGzipSha256 = 'd62cc8e71f5c37baebc9460b6a4ce47c11493b26ad3d2da0e46ab5bc8832b344'
$PayloadDir = $PSScriptRoot

if ((Test-Path -LiteralPath $Destino) -and -not $Forcar) {
    throw "Destination already exists: $Destino. Use -Forcar to replace it."
}

$Parts = @(
    Get-ChildItem -LiteralPath $PayloadDir -File -Filter 'payload.part*' -ErrorAction Stop |
        Sort-Object Name
)

if ($Parts.Count -ne 5) {
    throw "RC3 source package incomplete: expected 5 payload parts, found $($Parts.Count)."
}

$Base64 = [string]::Concat(@(
    $Parts | ForEach-Object {
        (Get-Content -LiteralPath $_.FullName -Raw -ErrorAction Stop).Trim()
    }
))

$Compressed = [Convert]::FromBase64String($Base64)
$Sha = [Security.Cryptography.SHA256]::Create()
try {
    $CompressedHash = -join ($Sha.ComputeHash($Compressed) | ForEach-Object { $_.ToString('x2') })
}
finally {
    $Sha.Dispose()
}

if ($CompressedHash -ne $ExpectedGzipSha256) {
    throw "Compressed RC3 payload integrity check failed. Expected $ExpectedGzipSha256; got $CompressedHash."
}

$Parent = Split-Path -Parent ([IO.Path]::GetFullPath($Destino))
if ($Parent) {
    New-Item -ItemType Directory -Path $Parent -Force | Out-Null
}

$Input = [IO.MemoryStream]::new($Compressed, $false)
$Gzip = [IO.Compression.GZipStream]::new($Input, [IO.Compression.CompressionMode]::Decompress)
$Output = [IO.File]::Create([IO.Path]::GetFullPath($Destino))
try {
    $Gzip.CopyTo($Output)
}
finally {
    $Output.Dispose()
    $Gzip.Dispose()
    $Input.Dispose()
}

$ActualSha256 = (Get-FileHash -LiteralPath $Destino -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
if ($ActualSha256 -ne $ExpectedSha256) {
    Remove-Item -LiteralPath $Destino -Force -ErrorAction SilentlyContinue
    throw "Materialized RC3 source integrity check failed. Expected $ExpectedSha256; got $ActualSha256."
}

Write-Host "RC3 source materialized and verified:" -ForegroundColor Green
Write-Host "  $Destino"
Write-Host "SHA-256: $ActualSha256"
