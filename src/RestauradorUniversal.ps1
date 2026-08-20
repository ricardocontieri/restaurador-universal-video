# Universal Video Restorer 1.0.1-RC3
# Integrity launcher for the exact RC3 source package.
# The restored source is SHA-256 verified before execution.
# License: MIT. See repository LICENSE.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedSha256 = '18f3a9dbac5d332be1b6e7df37d04579a816b3850736590ac5d972db91c0c506'
$PayloadDir = Join-Path $PSScriptRoot 'rc3-payload'

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
$TempRoot = Join-Path ([IO.Path]::GetTempPath()) 'universal-video-restorer'
$TempSource = Join-Path $TempRoot 'RestauradorUniversal_v1.0.1_RC3.ps1'

New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null

$Reuse = $false
if (Test-Path -LiteralPath $TempSource -PathType Leaf) {
    try {
        $ExistingHash = (Get-FileHash -LiteralPath $TempSource -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        $Reuse = ($ExistingHash -eq $ExpectedSha256)
    }
    catch {
        $Reuse = $false
    }
}

if (-not $Reuse) {
    $Input = [IO.MemoryStream]::new($Compressed, $false)
    $Gzip = [IO.Compression.GZipStream]::new($Input, [IO.Compression.CompressionMode]::Decompress)
    $Output = [IO.File]::Create($TempSource)
    try {
        $Gzip.CopyTo($Output)
    }
    finally {
        $Output.Dispose()
        $Gzip.Dispose()
        $Input.Dispose()
    }
}

$ActualSha256 = (Get-FileHash -LiteralPath $TempSource -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
if ($ActualSha256 -ne $ExpectedSha256) {
    Remove-Item -LiteralPath $TempSource -Force -ErrorAction SilentlyContinue
    throw "RC3 source integrity check failed. Expected $ExpectedSha256; got $ActualSha256."
}

# Preserve the caller's original tokenized arguments. The reconstructed RC3
# receives them normally and performs its own PowerShell/bootstrap validation.
& $TempSource @args

if ($null -ne $LASTEXITCODE) {
    exit $LASTEXITCODE
}
