param(
    [string]$PastaRaiz = "",
    [string]$Recursivo = "",
    [string]$NomePastaSaida = "_PROCESSADOS_1080P_ESTABILIZADOS",
    [switch]$AutoConfirmar,
    [switch]$DesligarAoFinal,
    [switch]$Forcar,
    [switch]$SemReducaoRuidoAudio,
    [switch]$SemEstabilizacao,
    [switch]$SemIntelQSV,
    [switch]$PreferirIntelQSV,
    [switch]$SemBenchmarkPreVfr,
    [switch]$SemTelemetriaGpuProcesso,
    [switch]$SemPreservarDatasSistemaArquivos,
    [switch]$SomenteMetadados,

    [ValidateRange(1,5)]
    [int]$BenchmarkGpuRepeticoes = 3,

    [ValidateRange(6,120)]
    [int]$BenchmarkGpuFrames = 24,

    [ValidateRange(1,30)]
    [int]$BenchmarkGpuWarmupFrames = 6,

    [ValidateRange(0.0,50.0)]
    [double]$MargemQsvPct = 10.0,

    [string]$FfmpegPath = "",
    [string]$FfprobePath = "",

    [ValidateRange(1.0,8.0)]
    [double]$AmostrasPillarPorSegundo = 4.0,

    [ValidateRange(240,960)]
    [int]$LarguraDiagnostico = 480,

    [ValidateRange(0.01,0.30)]
    [double]$LimitePreto = 0.10,

    [ValidateRange(1.0,15.0)]
    [double]$BarraMinimaPct = 3.0,

    [ValidateRange(0.25,15.0)]
    [double]$DuracaoMinPillarSeg = 1.0,

    [ValidateRange(0.25,5.0)]
    [double]$MaxGapPillarSeg = 0.75,

    [ValidateRange(0.5,5.0)]
    [double]$JanelaRefinoSeg = 1.5,

    [ValidateRange(1,10)]
    [int]$FramesConfirmacao = 3,

    [ValidateRange(1,30)]
    [int]$SmoothingEstabilizacao = 5,

    [ValidateRange(5,50)]
    [int]$BlurSigma = 18,

    [ValidateRange(320,960)]
    [int]$BlurBaseWidth = 480,

    [ValidateRange(3,60)]
    [int]$IntervaloStatusSeg = 8


)

# Captura os parâmetros do SCRIPT antes de entrar em funções.
# Em PowerShell, $PSBoundParameters dentro de Build-RelaunchArguments
# pertence à própria função e não contém os parâmetros do script.
$ScriptLaunchBoundParameters = @{}

foreach ($launchKey in $PSBoundParameters.Keys) {
    $ScriptLaunchBoundParameters[$launchKey] =
        $PSBoundParameters[$launchKey]
}

# =====================================================================
# BOOTSTRAP POWERSHELL 7
# =====================================================================
# Este bloco permanece compatível com Windows PowerShell 5.1 para que o
# próprio script consiga localizar/instalar PowerShell 7 e relançar-se.

$RequiredPowerShellVersion =
    New-Object System.Version 7,6,4

function Test-BootstrapYes {
    param([string]$Answer)

    if ([string]::IsNullOrWhiteSpace($Answer)) {
        return $false
    }

    $v =
        $Answer.Trim().ToLowerInvariant()

    return @("s","sim","y","yes") -contains $v
}

function Get-PwshVersion {
    param([string]$PwshExe)

    if (
        [string]::IsNullOrWhiteSpace($PwshExe) -or
        -not (
            Test-Path `
                -LiteralPath $PwshExe `
                -PathType Leaf
        )
    ) {
        return $null
    }

    try {
        $versionText =
            & $PwshExe `
                -NoLogo `
                -NoProfile `
                -NonInteractive `
                -Command `
                '$PSVersionTable.PSVersion.ToString()' `
                2>$null |
            Select-Object -First 1

        if (
            [string]::IsNullOrWhiteSpace(
                [string]$versionText
            )
        ) {
            return $null
        }

        return (
            New-Object `
                System.Version `
                ([string]$versionText).Trim()
        )
    }
    catch {
        return $null
    }
}

function Get-PwshCandidates {
    $items =
        New-Object `
            System.Collections.Generic.List[string]

    try {
        $cmd =
            Get-Command `
                pwsh.exe `
                -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($cmd -and $cmd.Source) {
            $items.Add([string]$cmd.Source)
        }
    }
    catch {}

    if ($env:ProgramFiles) {
        $items.Add(
            (
                Join-Path `
                    $env:ProgramFiles `
                    "PowerShell\7\pwsh.exe"
            )
        )
    }

    if ($env:LOCALAPPDATA) {
        $items.Add(
            (
                Join-Path `
                    $env:LOCALAPPDATA `
                    "Microsoft\WindowsApps\pwsh.exe"
            )
        )
    }

    try {
        $appxPackages =
            @(
                Get-AppxPackage `
                    -Name "Microsoft.PowerShell" `
                    -ErrorAction SilentlyContinue |
                Sort-Object Version -Descending
            )

        foreach ($pkg in $appxPackages) {
            if ($pkg -and $pkg.InstallLocation) {
                $items.Add(
                    (
                        Join-Path `
                            $pkg.InstallLocation `
                            "pwsh.exe"
                    )
                )
            }
        }
    }
    catch {}

    $unique = @()
    $seen = @{}

    foreach ($item in $items) {
        if (
            [string]::IsNullOrWhiteSpace(
                [string]$item
            )
        ) {
            continue
        }

        $key =
            ([string]$item).ToLowerInvariant()

        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $unique += [string]$item
        }
    }

    return @($unique)
}

function Find-CompatiblePwsh {
    param(
        [System.Version]$MinimumVersion
    )

    $found = @()

    foreach ($candidate in @(Get-PwshCandidates)) {
        $version =
            Get-PwshVersion `
                -PwshExe $candidate

        if ($version) {
            $found +=
                [pscustomobject]@{
                    Path = $candidate
                    Version = $version
                }

            if ($version -ge $MinimumVersion) {
                return [pscustomobject]@{
                    Compatible = $true
                    Path = $candidate
                    Version = $version
                    Found = @($found)
                }
            }
        }
    }

    return [pscustomobject]@{
        Compatible = $false
        Path = ""
        Version = $null
        Found = @($found)
    }
}

function Build-RelaunchArguments {
    $launch =
        New-Object `
            System.Collections.Generic.List[string]

    $launch.Add("-NoLogo")
    $launch.Add("-NoProfile")
    $launch.Add("-ExecutionPolicy")
    $launch.Add("Bypass")
    $launch.Add("-File")
    $launch.Add($PSCommandPath)

    foreach ($key in $ScriptLaunchBoundParameters.Keys) {
        $value =
            $ScriptLaunchBoundParameters[$key]

        if (
            $value -is
            [Management.Automation.SwitchParameter]
        ) {
            if ($value.IsPresent) {
                $launch.Add("-" + $key)
            }

            continue
        }

        $launch.Add("-" + $key)
        $launch.Add([string]$value)
    }

    return [string[]]$launch
}

function Relaunch-InPwsh {
    param(
        [string]$PwshExe,
        [System.Version]$Version
    )

    Write-Host ""
    Write-Host (
        "PowerShell compatível localizado: {0}" -f `
            $PwshExe
    ) -ForegroundColor Green

    Write-Host (
        "Versão: {0}" -f `
            $Version
    ) -ForegroundColor Green

    Write-Host (
        "Relançando automaticamente este script no PowerShell {0}..." -f `
            $Version
    ) -ForegroundColor Cyan

    Write-Host ""

    $relaunchArgs =
        Build-RelaunchArguments

    & $PwshExe @relaunchArgs

    $childExitCode =
        $LASTEXITCODE

    if ($null -eq $childExitCode) {
        $childExitCode = 0
    }

    exit $childExitCode
}

$currentEdition =
    [string]$PSVersionTable.PSEdition

$currentVersion =
    $PSVersionTable.PSVersion

$currentIsCompatible = (
    ($currentEdition -eq "Core") -and
    ($currentVersion -ge $RequiredPowerShellVersion)
)

if (-not $currentIsCompatible) {
    Write-Host ""
    Write-Host "============================================================" `
        -ForegroundColor Yellow
    Write-Host " VALIDACAO DO POWERSHELL" `
        -ForegroundColor Yellow
    Write-Host "============================================================" `
        -ForegroundColor Yellow

    Write-Host (
        "Shell atual: {0} {1}" -f `
            $currentEdition,
            $currentVersion
    )

    Write-Host (
        "Requisito: PowerShell {0} ou superior (PSEdition Core)." -f `
            $RequiredPowerShellVersion
    )

    Write-Host ""
    Write-Host (
        "Tentando localizar uma instalação compatível do pwsh.exe..."
    ) -ForegroundColor Cyan

    $pwsh =
        Find-CompatiblePwsh `
            -MinimumVersion $RequiredPowerShellVersion

    if ($pwsh.Compatible) {
        Relaunch-InPwsh `
            -PwshExe $pwsh.Path `
            -Version $pwsh.Version
    }

    Write-Host ""
    Write-Host (
        "ERRO: não foi possível acionar PowerShell {0} ou superior." -f `
            $RequiredPowerShellVersion
    ) -ForegroundColor Red

    if (@($pwsh.Found).Count -gt 0) {
        Write-Host ""
        Write-Host "Instalações do PowerShell 7 encontradas:" `
            -ForegroundColor Yellow

        foreach ($candidate in @($pwsh.Found)) {
            Write-Host (
                "  {0}  ->  {1}" -f `
                    $candidate.Version,
                    $candidate.Path
            )
        }

        Write-Host ""
        Write-Host (
            "As versões acima são inferiores ao mínimo exigido."
        ) -ForegroundColor Yellow
    }
    else {
        Write-Host ""
        Write-Host (
            "Nenhuma instalação utilizável de pwsh.exe foi encontrada."
        ) -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host (
        "Este restaurador requer PowerShell {0}+ antes de mapear ou processar vídeos." -f `
            $RequiredPowerShellVersion
    ) -ForegroundColor Yellow

    $installAnswer =
        Read-Host `
            "Deseja instalar/atualizar o PowerShell agora via WinGet? [S/N]"

    if (-not (Test-BootstrapYes $installAnswer)) {
        Write-Host ""
        Write-Host (
            "Instalação recusada. O processamento NÃO será iniciado."
        ) -ForegroundColor Red

        Write-Host (
            "Instale PowerShell {0} ou superior e execute novamente este script." -f `
                $RequiredPowerShellVersion
        ) -ForegroundColor Yellow

        exit 20
    }

    $wingetCmd = $null

    try {
        $wingetCmd =
            Get-Command `
                winget.exe `
                -ErrorAction SilentlyContinue |
            Select-Object -First 1
    }
    catch {}

    if (
        -not $wingetCmd -or
        -not $wingetCmd.Source
    ) {
        Write-Host ""
        Write-Host (
            "ERRO: WinGet não foi localizado; a instalação automática não pode continuar."
        ) -ForegroundColor Red

        Write-Host (
            "Instale PowerShell {0}+ manualmente e execute novamente o script." -f `
                $RequiredPowerShellVersion
        ) -ForegroundColor Yellow

        exit 21
    }

    $wingetExe =
        [string]$wingetCmd.Source

    Write-Host ""
    Write-Host (
        "WinGet localizado: {0}" -f `
            $wingetExe
    )

    Write-Host (
        "Consultando o pacote Microsoft.PowerShell..."
    ) -ForegroundColor Cyan

    $listText =
        & $wingetExe `
            list `
            --id Microsoft.PowerShell `
            --exact `
            --source winget `
            --accept-source-agreements `
            2>&1 |
        Out-String

    $listExit =
        $LASTEXITCODE

    $packageInstalled = (
        ($listExit -eq 0) -and
        (
            $listText -match
            'Microsoft\.PowerShell'
        )
    )

    if ($packageInstalled) {
        Write-Host (
            "PowerShell 7 já existe. Tentando atualizar para a versão estável mais recente..."
        ) -ForegroundColor Cyan

        & $wingetExe `
            upgrade `
            --id Microsoft.PowerShell `
            --exact `
            --source winget `
            --accept-package-agreements `
            --accept-source-agreements

        $installExit =
            $LASTEXITCODE

        if ($installExit -ne 0) {
            Write-Host ""
            Write-Host (
                "Upgrade retornou código {0}; tentando install como fallback..." -f `
                    $installExit
            ) -ForegroundColor Yellow

            & $wingetExe `
                install `
                --id Microsoft.PowerShell `
                --exact `
                --source winget `
                --accept-package-agreements `
                --accept-source-agreements

            $installExit =
                $LASTEXITCODE
        }
    }
    else {
        Write-Host (
            "PowerShell 7 não consta como instalado via WinGet. Iniciando instalação..."
        ) -ForegroundColor Cyan

        & $wingetExe `
            install `
            --id Microsoft.PowerShell `
            --exact `
            --source winget `
            --accept-package-agreements `
            --accept-source-agreements

        $installExit =
            $LASTEXITCODE
    }

    if ($installExit -ne 0) {
        Write-Host ""
        Write-Host (
            "ERRO: WinGet não concluiu a instalação/atualização. Código: {0}" -f `
                $installExit
        ) -ForegroundColor Red

        Write-Host (
            "Nenhum vídeo foi processado."
        ) -ForegroundColor Red

        exit 22
    }

    Write-Host ""
    Write-Host (
        "Instalação/atualização concluída pelo WinGet."
    ) -ForegroundColor Green

    Write-Host (
        "Validando novamente o pwsh.exe..."
    ) -ForegroundColor Cyan

    Start-Sleep -Seconds 2

    $pwshAfterInstall =
        Find-CompatiblePwsh `
            -MinimumVersion $RequiredPowerShellVersion

    if (-not $pwshAfterInstall.Compatible) {
        Write-Host ""
        Write-Host (
            "ERRO: a instalação terminou, mas PowerShell {0}+ ainda não pôde ser acionado." -f `
                $RequiredPowerShellVersion
        ) -ForegroundColor Red

        if (@($pwshAfterInstall.Found).Count -gt 0) {
            Write-Host ""
            Write-Host "Versões encontradas:" `
                -ForegroundColor Yellow

            foreach ($candidate in @($pwshAfterInstall.Found)) {
                Write-Host (
                    "  {0}  ->  {1}" -f `
                        $candidate.Version,
                        $candidate.Path
                )
            }
        }

        Write-Host ""
        Write-Host (
            "Feche este terminal, abra novamente e execute o script."
        ) -ForegroundColor Yellow

        Write-Host (
            'Para conferir manualmente: pwsh -NoProfile -Command "$PSVersionTable"'
        ) -ForegroundColor Yellow

        exit 23
    }

    Relaunch-InPwsh `
        -PwshExe $pwshAfterInstall.Path `
        -Version $pwshAfterInstall.Version
}

Write-Host ""
Write-Host (
    "PowerShell validado: {0} {1} (requisito >= {2})." -f `
        $PSVersionTable.PSEdition,
        $PSVersionTable.PSVersion,
        $RequiredPowerShellVersion
) -ForegroundColor Green

$ErrorActionPreference = "Continue"

$Inv = [Globalization.CultureInfo]::InvariantCulture

# =====================================================================
# 00 - UTILIDADES
# =====================================================================

function Fmt-Inv {
    param([double]$N, [string]$Format = "0.######")
    return $N.ToString($Format, $Inv)
}

function Test-Sim {
    param([string]$Resposta)

    if ([string]::IsNullOrWhiteSpace($Resposta)) {
        return $false
    }

    $r = $Resposta.Trim().ToLowerInvariant()

    return @(
        "s","sim","y","yes","1","true"
    ) -contains $r
}

function To-Timecode {
    param([double]$Seconds)

    if ($Seconds -lt 0) {
        $Seconds = 0
    }

    $ts =
        [TimeSpan]::FromSeconds($Seconds)

    return "{0:00}:{1:00}:{2:00}.{3:000}" -f `
        [math]::Floor($ts.TotalHours),
        $ts.Minutes,
        $ts.Seconds,
        $ts.Milliseconds
}

function To-ShortTime {
    param([double]$Seconds)

    if ($Seconds -lt 0) {
        $Seconds = 0
    }

    $ts =
        [TimeSpan]::FromSeconds($Seconds)

    if ($ts.TotalHours -ge 1) {
        return "{0:00}:{1:00}:{2:00}" -f `
            [math]::Floor($ts.TotalHours),
            $ts.Minutes,
            $ts.Seconds
    }

    return "{0:00}:{1:00}" -f `
        [math]::Floor($ts.TotalMinutes),
        $ts.Seconds
}

function Median {
    param([double[]]$Values)

    if (-not $Values -or $Values.Count -eq 0) {
        return 0.0
    }

    $a = @($Values | Sort-Object)
    $n = $a.Count

    if (($n % 2) -eq 1) {
        return [double]$a[
            [int][math]::Floor($n / 2)
        ]
    }

    return (
        [double]$a[$n/2 - 1] +
        [double]$a[$n/2]
    ) / 2.0
}

function Percentile {
    param(
        [double[]]$Values,
        [double]$P
    )

    if (-not $Values -or $Values.Count -eq 0) {
        return 0.0
    }

    $a = @($Values | Sort-Object)

    if ($a.Count -eq 1) {
        return [double]$a[0]
    }

    $idx =
        ($P / 100.0) *
        ($a.Count - 1)

    $lo = [int][math]::Floor($idx)
    $hi = [int][math]::Ceiling($idx)

    if ($lo -eq $hi) {
        return [double]$a[$lo]
    }

    $frac = $idx - $lo

    return (
        [double]$a[$lo] *
        (1.0 - $frac)
    ) +
    (
        [double]$a[$hi] *
        $frac
    )
}

function Round-Up-Even {
    param([double]$N)

    $v =
        [int][math]::Ceiling($N)

    if (($v % 2) -ne 0) {
        $v++
    }

    return $v
}

function Sanitize-Name {
    param([string]$Name)

    $invalid =
        [IO.Path]::GetInvalidFileNameChars()

    $out = $Name

    foreach ($c in $invalid) {
        $out =
            $out.Replace(
                [string]$c,
                "_"
            )
    }

    if ($out.Length -gt 90) {
        $out =
            $out.Substring(0,90)
    }

    return $out
}

function Get-RelativePathSimple {
    param(
        [string]$Base,
        [string]$FullPath
    )

    $b =
        $Base.TrimEnd("\","/")

    if (
        $FullPath.StartsWith(
            $b,
            [StringComparison]::OrdinalIgnoreCase
        )
    ) {
        return $FullPath.
            Substring($b.Length).
            TrimStart("\","/")
    }

    return [IO.Path]::GetFileName($FullPath)
}

function Resolve-ExecutablePath {
    param(
        [string]$Name,
        [string]$ExplicitPath = "",
        [string]$SiblingOf = ""
    )

    if (
        -not [string]::IsNullOrWhiteSpace($ExplicitPath)
    ) {
        if (
            Test-Path `
                -LiteralPath $ExplicitPath `
                -PathType Leaf
        ) {
            return (
                Resolve-Path `
                    -LiteralPath $ExplicitPath
            ).Path
        }

        throw "Executavel informado nao existe: $ExplicitPath"
    }

    if (
        -not [string]::IsNullOrWhiteSpace($SiblingOf)
    ) {
        try {
            $dir =
                Split-Path -Parent $SiblingOf

            $candidate =
                Join-Path $dir $Name

            if (
                Test-Path `
                    -LiteralPath $candidate `
                    -PathType Leaf
            ) {
                return (
                    Resolve-Path `
                        -LiteralPath $candidate
                ).Path
            }
        } catch {}
    }

    try {
        $cmd =
            Get-Command `
                $Name `
                -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if (
            $cmd -and
            $cmd.Source -and
            (
                Test-Path `
                    -LiteralPath $cmd.Source `
                    -PathType Leaf
            )
        ) {
            return $cmd.Source
        }
    } catch {}

    try {
        $where =
            & where.exe $Name 2>$null |
            Select-Object -First 1

        if (
            $where -and
            (
                Test-Path `
                    -LiteralPath $where `
                    -PathType Leaf
            )
        ) {
            return (
                Resolve-Path `
                    -LiteralPath $where
            ).Path
        }
    } catch {}

    $candidates = @()

    if ($env:LOCALAPPDATA) {
        $candidates +=
            Join-Path `
                $env:LOCALAPPDATA `
                "Microsoft\WinGet\Links\$Name"

        $candidates +=
            Join-Path `
                $env:LOCALAPPDATA `
                "Programs\ffmpeg\bin\$Name"
    }

    if ($env:ProgramFiles) {
        $candidates +=
            Join-Path `
                $env:ProgramFiles `
                "ffmpeg\bin\$Name"
    }

    if (${env:ProgramFiles(x86)}) {
        $candidates +=
            Join-Path `
                ${env:ProgramFiles(x86)} `
                "ffmpeg\bin\$Name"
    }

    $candidates += @(
        "C:\ffmpeg\bin\$Name",
        "C:\tools\ffmpeg\bin\$Name",
        "C:\ProgramData\chocolatey\bin\$Name",
        "C:\ProgramData\chocolatey\lib\ffmpeg\tools\ffmpeg\bin\$Name"
    )

    foreach ($candidate in $candidates) {
        if (
            Test-Path `
                -LiteralPath $candidate `
                -PathType Leaf
        ) {
            return (
                Resolve-Path `
                    -LiteralPath $candidate
            ).Path
        }
    }

    if ($env:LOCALAPPDATA) {
        $winget =
            Join-Path `
                $env:LOCALAPPDATA `
                "Microsoft\WinGet\Packages"

        if (
            Test-Path `
                -LiteralPath $winget `
                -PathType Container
        ) {
            try {
                $match =
                    Get-ChildItem `
                        -LiteralPath $winget `
                        -Directory `
                        -ErrorAction SilentlyContinue |
                    Where-Object {
                        $_.Name -match '(?i)ffmpeg'
                    } |
                    ForEach-Object {
                        Get-ChildItem `
                            -LiteralPath $_.FullName `
                            -Recurse `
                            -File `
                            -Filter $Name `
                            -ErrorAction SilentlyContinue |
                        Select-Object -First 1
                    } |
                    Where-Object { $_ } |
                    Select-Object -First 1

                if ($match) {
                    return $match.FullName
                }
            } catch {}
        }
    }

    return $null
}

function Quote-WinArg {
    param([string]$Arg)

    if ($null -eq $Arg) {
        return '""'
    }

    if ($Arg -notmatch '[\s"]') {
        return $Arg
    }

    return '"' +
        ($Arg -replace '"','\"') +
        '"'
}

function Join-ArgString {
    param([string[]]$CommandArgs)

    return (
        (
            $CommandArgs |
            ForEach-Object {
                Quote-WinArg $_
            }
        ) -join " "
    )
}

function Parse-Fps {
    param([string]$Rate)

    if (
        [string]::IsNullOrWhiteSpace($Rate)
    ) {
        return 0.0
    }

    if (
        $Rate -match
        '^(?<n>[0-9]+)\/(?<d>[0-9]+)$'
    ) {
        $n =
            [double]$Matches["n"]

        $d =
            [double]$Matches["d"]

        if ($d -gt 0) {
            return $n / $d
        }
    }

    $v = 0.0

    if (
        [double]::TryParse(
            $Rate,
            [Globalization.NumberStyles]::Float,
            $Inv,
            [ref]$v
        )
    ) {
        return $v
    }

    return 0.0
}

function Nearest-CommonFps {
    param([double]$Fps)

    $common = @(
        23.976023976,
        24.0,
        25.0,
        29.97002997,
        30.0,
        50.0,
        59.94005994,
        60.0
    )

    $best = $common[0]
    $dist =
        [math]::Abs(
            $Fps - $best
        )

    foreach ($c in $common) {
        $d =
            [math]::Abs(
                $Fps - $c
            )

        if ($d -lt $dist) {
            $best = $c
            $dist = $d
        }
    }

    return $best
}

function Get-NvidiaStats {
    try {
        $line =
            & nvidia-smi `
                "--query-gpu=utilization.gpu,utilization.encoder,utilization.decoder,temperature.gpu,memory.used,memory.total" `
                "--format=csv,noheader,nounits" `
                2>$null |
            Select-Object -First 1

        if (-not $line) {
            return $null
        }

        $p = @(
            $line -split "," |
            ForEach-Object {
                $_.Trim()
            }
        )

        if ($p.Count -lt 6) {
            return $null
        }

        return [pscustomobject]@{
            Gpu = [int]$p[0]
            Enc = [int]$p[1]
            Dec = [int]$p[2]
            Temp = [int]$p[3]
            Vram = [int]$p[4]
            VramTotal = [int]$p[5]
        }
    } catch {
        return $null
    }
}

function Get-ProcessGpuEngineStats {
    param([int]$ProcessId)

    if (
        $SemTelemetriaGpuProcesso -or
        $script:GpuPerfCountersUnavailable
    ) {
        return $null
    }

    try {
        $pattern =
            "(?i)pid_" +
            [regex]::Escape([string]$ProcessId) +
            "(?:_|$)"

        $engines =
            @(
                Get-CimInstance `
                    -ClassName `
                        Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine `
                    -ErrorAction Stop |
                Where-Object {
                    [string]$_.Name -match $pattern
                }
            )

        if ($engines.Count -eq 0) {
            return $null
        }

        $dec = 0.0
        $enc = 0.0
        $compute = 0.0
        $threeD = 0.0

        foreach ($e in $engines) {
            $u = 0.0

            try {
                $u =
                    [double]$e.UtilizationPercentage
            } catch {}

            $name =
                [string]$e.Name

            if ($name -match '(?i)engtype_VideoDecode') {
                $dec += $u
            }
            elseif ($name -match '(?i)engtype_VideoEncode') {
                $enc += $u
            }
            elseif ($name -match '(?i)engtype_Compute') {
                $compute += $u
            }
            elseif ($name -match '(?i)engtype_3D') {
                $threeD += $u
            }
        }

        return [pscustomobject]@{
            Decode =
                [math]::Min(
                    100.0,
                    $dec
                )
            Encode =
                [math]::Min(
                    100.0,
                    $enc
                )
            Compute =
                [math]::Min(
                    100.0,
                    $compute
                )
            ThreeD =
                [math]::Min(
                    100.0,
                    $threeD
                )
        }
    }
    catch {
        $script:GpuPerfCountersUnavailable = $true
        return $null
    }
}

function Get-RamPct {
    try {
        $os =
            Get-CimInstance `
                Win32_OperatingSystem

        $total =
            [double]$os.TotalVisibleMemorySize

        $free =
            [double]$os.FreePhysicalMemory

        if ($total -le 0) {
            return $null
        }

        return 100.0 *
            (($total - $free) / $total)
    } catch {
        return $null
    }
}

# =====================================================================
# 01 - FFPROBE / INVENTÁRIO
# =====================================================================

function Get-MediaInfo {
    param([string]$File)

    $json =
        & $script:FfprobeExe `
            -v error `
            -show_streams `
            -show_format `
            -of json `
            "$File" `
            2>$null |
        Out-String

    if (
        $LASTEXITCODE -ne 0 -or
        [string]::IsNullOrWhiteSpace($json)
    ) {
        return $null
    }

    try {
        $o =
            $json |
            ConvertFrom-Json
    }
    catch {
        return $null
    }

    $v =
        @(
            $o.streams |
            Where-Object {
                $_.codec_type -eq "video"
            }
        ) |
        Select-Object -First 1

    if (-not $v) {
        return $null
    }

    $a =
        @(
            $o.streams |
            Where-Object {
                $_.codec_type -eq "audio"
            }
        ) |
        Select-Object -First 1

    $duration = 0.0

    [void][double]::TryParse(
        [string]$o.format.duration,
        [Globalization.NumberStyles]::Float,
        $Inv,
        [ref]$duration
    )

    $avgText =
        [string]$v.avg_frame_rate

    $rText =
        [string]$v.r_frame_rate

    $avgFps =
        Parse-Fps $avgText

    $rFps =
        Parse-Fps $rText

    if ($avgFps -le 0) {
        $avgFps = $rFps
    }

    if ($rFps -le 0) {
        $rFps = $avgFps
    }

    $vfr = $false

    if (
        $avgFps -gt 0 -and
        $rFps -gt 0
    ) {
        $diff =
            [math]::Abs(
                $avgFps -
                $rFps
            ) /
            [math]::Max(
                $avgFps,
                $rFps
            )

        if ($diff -gt 0.005) {
            $vfr = $true
        }
    }

    $frameCount = 0L

    if (
        -not [string]::IsNullOrWhiteSpace(
            [string]$v.nb_frames
        )
    ) {
        [void][long]::TryParse(
            [string]$v.nb_frames,
            [ref]$frameCount
        )
    }

    if (
        $frameCount -le 0 -and
        $duration -gt 0 -and
        $avgFps -gt 0
    ) {
        $frameCount =
            [long][math]::Round(
                $duration * $avgFps
            )
    }

    $bitRate = 0L

    [void][long]::TryParse(
        [string]$o.format.bit_rate,
        [ref]$bitRate
    )

    return [pscustomobject]@{
        Width = [int]$v.width
        Height = [int]$v.height
        Duration = $duration
        VideoCodec = [string]$v.codec_name
        PixelFormat = [string]$v.pix_fmt
        AvgFrameRate = $avgText
        RealFrameRate = $rText
        AvgFps = $avgFps
        RealFps = $rFps
        FrameCount = $frameCount
        IsVfr = $vfr
        BitRate = $bitRate
        HasAudio = [bool]($null -ne $a)
        AudioCodec =
            if ($a) {
                [string]$a.codec_name
            }
            else {
                ""
            }
        AudioRate =
            if ($a) {
                [int]$a.sample_rate
            }
            else {
                0
            }
        AudioChannels =
            if ($a) {
                [int]$a.channels
            }
            else {
                0
            }
    }
}

function Convert-ToArchiveDateCandidate {
    param(
        [string]$Raw,
        [string]$Source,
        [string]$Confidence,
        [bool]$Embedded
    )

    if ([string]::IsNullOrWhiteSpace($Raw)) {
        return $null
    }

    $value =
        $Raw.Trim().
        Trim('"').
        Trim("'")

    # Exige ao menos precisão de dia.
    # Não converte "2007" isolado em 01/01/2007.
    if (
        $value -notmatch '(?<!\d)(19|20)\d{2}[-/:]\d{1,2}[-/:]\d{1,2}(?!\d)' -and
        $value -notmatch '(?<!\d)(19|20)\d{6}(?!\d)'
    ) {
        return $null
    }

    # Formato EXIF/RIFF comum:
    # yyyy:MM:dd HH:mm:ss -> yyyy-MM-dd HH:mm:ss
    if (
        $value -match '^(?<y>\d{4}):(?<m>\d{2}):(?<d>\d{2})(?<rest>.*)$'
    ) {
        $value =
            "{0}-{1}-{2}{3}" -f `
                $Matches["y"],
                $Matches["m"],
                $Matches["d"],
                $Matches["rest"]
    }

    $hasExplicitZone =
        $value -match '(?i)(Z|[+-]\d{2}:?\d{2})\s*$'

    $sortDate = $null
    $metadataValue = ""
    $displayValue = ""

    if ($hasExplicitZone) {
        $dto =
            [DateTimeOffset]::MinValue

        $ok =
            [DateTimeOffset]::TryParse(
                $value,
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::AllowWhiteSpaces,
                [ref]$dto
            )

        if (-not $ok) {
            $ok =
                [DateTimeOffset]::TryParse(
                    $value,
                    [Globalization.CultureInfo]::CurrentCulture,
                    [Globalization.DateTimeStyles]::AllowWhiteSpaces,
                    [ref]$dto
                )
        }

        if (-not $ok) {
            return $null
        }

        if (
            $dto.Year -lt 1980 -or
            $dto.Year -gt ((Get-Date).Year + 1)
        ) {
            return $null
        }

        $sortDate =
            $dto.UtcDateTime

        $metadataValue =
            $dto.ToString(
                "yyyy-MM-ddTHH:mm:sszzz",
                [Globalization.CultureInfo]::InvariantCulture
            )

        $displayValue =
            $dto.ToString(
                "yyyy-MM-dd HH:mm:ss zzz",
                [Globalization.CultureInfo]::InvariantCulture
            )
    }
    else {
        $dt =
            [datetime]::MinValue

        $ok =
            [datetime]::TryParse(
                $value,
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::AllowWhiteSpaces,
                [ref]$dt
            )

        if (-not $ok) {
            $ok =
                [datetime]::TryParse(
                    $value,
                    [Globalization.CultureInfo]::CurrentCulture,
                    [Globalization.DateTimeStyles]::AllowWhiteSpaces,
                    [ref]$dt
                )
        }

        if (-not $ok) {
            return $null
        }

        if (
            $dt.Year -lt 1980 -or
            $dt.Year -gt ((Get-Date).Year + 1)
        ) {
            return $null
        }

        $sortDate =
            [datetime]::SpecifyKind(
                $dt,
                [DateTimeKind]::Unspecified
            )

        # Sem fuso no original -> não inventar um fuso.
        $metadataValue =
            $dt.ToString(
                "yyyy-MM-ddTHH:mm:ss",
                [Globalization.CultureInfo]::InvariantCulture
            )

        $displayValue =
            $dt.ToString(
                "yyyy-MM-dd HH:mm:ss",
                [Globalization.CultureInfo]::InvariantCulture
            )
    }

    return [pscustomobject]@{
        Raw = $Raw
        Source = $Source
        Confidence = $Confidence
        Embedded = $Embedded
        SortDate = $sortDate
        MetadataValue = $metadataValue
        DisplayValue = $displayValue
        DateOnly =
            $sortDate.ToString(
                "yyyy-MM-dd",
                [Globalization.CultureInfo]::InvariantCulture
            )
        Year = [int]$sortDate.Year
    }
}

function Get-ArchiveYearHints {
    param([string]$File)

    $years = @()

    foreach (
        $m in [regex]::Matches(
            $File,
            '(?<!\d)(19\d{2}|20\d{2})(?!\d)'
        )
    ) {
        $y = 0

        if (
            [int]::TryParse(
                [string]$m.Value,
                [ref]$y
            )
        ) {
            if (
                $y -ge 1980 -and
                $y -le ((Get-Date).Year + 1)
            ) {
                $years += $y
            }
        }
    }

    return @(
        $years |
        Sort-Object -Unique
    )
}

function Get-OriginalDateInfo {
    param([string]$File)

    $fi =
        Get-Item `
            -LiteralPath $File `
            -ErrorAction Stop

    $embedded = @()
    $probeJson = ""

    try {
        $probeJson =
            & $script:FfprobeExe `
                -v error `
                -show_format `
                -show_streams `
                -of json `
                "$File" `
                2>$null |
            Out-String
    }
    catch {
        $probeJson = ""
    }

    if (
        -not [string]::IsNullOrWhiteSpace(
            $probeJson
        )
    ) {
        try {
            $po =
                $probeJson |
                ConvertFrom-Json

            $tagGroups = @()

            if (
                $null -ne $po.format -and
                $null -ne $po.format.tags
            ) {
                $tagGroups += [pscustomobject]@{
                    Prefix = "FFprobe:format"
                    Tags = $po.format.tags
                }
            }

            $streamIndex = 0

            foreach ($stream in @($po.streams)) {
                if ($null -ne $stream.tags) {
                    $tagGroups += [pscustomobject]@{
                        Prefix =
                            "FFprobe:stream{0}:{1}" -f `
                                $streamIndex,
                                ([string]$stream.codec_type)
                        Tags = $stream.tags
                    }
                }

                $streamIndex++
            }

            foreach ($g in $tagGroups) {
                foreach (
                    $prop in $g.Tags.PSObject.Properties
                ) {
                    $key =
                        [string]$prop.Name

                    if (
                        $key -notmatch
                        '(?i)(creation|created|date|time|record|shoot|taken|original)'
                    ) {
                        continue
                    }

                    $candidate =
                        Convert-ToArchiveDateCandidate `
                            -Raw ([string]$prop.Value) `
                            -Source ("{0}.{1}" -f $g.Prefix,$key) `
                            -Confidence "ALTA" `
                            -Embedded $true

                    if ($null -ne $candidate) {
                        $embedded += $candidate
                    }
                }
            }
        }
        catch {}
    }

    $fsCandidates = @()

    $fsCreation =
        [pscustomobject]@{
            Raw =
                $fi.CreationTimeUtc.ToString(
                    "o",
                    [Globalization.CultureInfo]::InvariantCulture
                )
            Source = "Filesystem:CreationTimeUtc"
            Confidence = "MEDIA"
            Embedded = $false
            SortDate = $fi.CreationTimeUtc
            MetadataValue =
                $fi.CreationTimeUtc.ToString(
                    "yyyy-MM-ddTHH:mm:ss.fff'Z'",
                    [Globalization.CultureInfo]::InvariantCulture
                )
            DisplayValue =
                $fi.CreationTimeUtc.ToString(
                    "yyyy-MM-dd HH:mm:ss 'UTC'",
                    [Globalization.CultureInfo]::InvariantCulture
                )
            DateOnly =
                $fi.CreationTimeUtc.ToString(
                    "yyyy-MM-dd",
                    [Globalization.CultureInfo]::InvariantCulture
                )
            Year = $fi.CreationTimeUtc.Year
        }

    $fsWrite =
        [pscustomobject]@{
            Raw =
                $fi.LastWriteTimeUtc.ToString(
                    "o",
                    [Globalization.CultureInfo]::InvariantCulture
                )
            Source = "Filesystem:LastWriteTimeUtc"
            Confidence = "MEDIA"
            Embedded = $false
            SortDate = $fi.LastWriteTimeUtc
            MetadataValue =
                $fi.LastWriteTimeUtc.ToString(
                    "yyyy-MM-ddTHH:mm:ss.fff'Z'",
                    [Globalization.CultureInfo]::InvariantCulture
                )
            DisplayValue =
                $fi.LastWriteTimeUtc.ToString(
                    "yyyy-MM-dd HH:mm:ss 'UTC'",
                    [Globalization.CultureInfo]::InvariantCulture
                )
            DateOnly =
                $fi.LastWriteTimeUtc.ToString(
                    "yyyy-MM-dd",
                    [Globalization.CultureInfo]::InvariantCulture
                )
            Year = $fi.LastWriteTimeUtc.Year
        }

    if (
        $fsCreation.Year -ge 1980 -and
        $fsCreation.Year -le ((Get-Date).Year + 1)
    ) {
        $fsCandidates += $fsCreation
    }

    if (
        $fsWrite.Year -ge 1980 -and
        $fsWrite.Year -le ((Get-Date).Year + 1)
    ) {
        $fsCandidates += $fsWrite
    }

    $yearHints =
        @(Get-ArchiveYearHints $File)

    $chosen = $null
    $status = ""
    $warning = ""

    if ($embedded.Count -gt 0) {
        $chosen =
            @(
                $embedded |
                Sort-Object SortDate
            )[0]

        $status = "DATA_EMBUTIDA"
    }
    elseif ($fsCandidates.Count -gt 0) {
        $oldestFs =
            @(
                $fsCandidates |
                Sort-Object SortDate
            )[0]

        $yearCompatible = $true

        if ($yearHints.Count -gt 0) {
            $yearCompatible = $false

            foreach ($hint in $yearHints) {
                if (
                    [math]::Abs(
                        [int]$oldestFs.Year -
                        [int]$hint
                    ) -le 1
                ) {
                    $yearCompatible = $true
                    break
                }
            }
        }

        if ($yearCompatible) {
            $chosen = $oldestFs
            $status = "DATA_FILESYSTEM"
        }
        else {
            $status = "SEM_DATA_CONFIAVEL"

            $warning =
                "Datas filesystem não combinam com ano(s) do caminho: {0}." -f `
                    (
                        $yearHints -join ","
                    )
        }
    }
    else {
        $status = "SEM_DATA"
    }

    $embeddedSummary =
        @(
            $embedded |
            ForEach-Object {
                "{0}={1}" -f `
                    $_.Source,
                    $_.Raw
            }
        ) -join " | "

    $fsSummary =
        @(
            $fsCandidates |
            ForEach-Object {
                "{0}={1}" -f `
                    $_.Source,
                    $_.Raw
            }
        ) -join " | "

    return [pscustomobject]@{
        HasCanonicalDate =
            [bool]($null -ne $chosen)

        CanonicalDisplay =
            if ($null -ne $chosen) {
                $chosen.DisplayValue
            }
            else {
                ""
            }

        CanonicalMetadata =
            if ($null -ne $chosen) {
                $chosen.MetadataValue
            }
            else {
                ""
            }

        CanonicalDate =
            if ($null -ne $chosen) {
                $chosen.DateOnly
            }
            else {
                ""
            }

        CanonicalYear =
            if ($null -ne $chosen) {
                [int]$chosen.Year
            }
            else {
                0
            }

        Source =
            if ($null -ne $chosen) {
                $chosen.Source
            }
            else {
                ""
            }

        Confidence =
            if ($null -ne $chosen) {
                $chosen.Confidence
            }
            else {
                ""
            }

        Status = $status
        Warning = $warning

        YearHints =
            $yearHints -join ","

        EmbeddedCandidates =
            $embeddedSummary

        FileSystemCandidates =
            $fsSummary

        OriginalCreationTimeUtc =
            $fi.CreationTimeUtc

        OriginalLastWriteTimeUtc =
            $fi.LastWriteTimeUtc

        OriginalCreationTimeUtcText =
            $fi.CreationTimeUtc.ToString(
                "o",
                [Globalization.CultureInfo]::InvariantCulture
            )

        OriginalLastWriteTimeUtcText =
            $fi.LastWriteTimeUtc.ToString(
                "o",
                [Globalization.CultureInfo]::InvariantCulture
            )
    }
}

function Get-ArchiveMetadataArgs {
    param(
        [object]$DateInfo,
        [datetime]$RestorationTimeUtc
    )

    $argsOut = @()

    $argsOut += @(
        "-metadata",
        (
            "restoration_time={0}" -f `
                $RestorationTimeUtc.ToString(
                    "yyyy-MM-ddTHH:mm:ss.fff'Z'",
                    [Globalization.CultureInfo]::InvariantCulture
                )
        )
    )

    if ($null -ne $DateInfo) {
        $argsOut += @(
            "-metadata",
            (
                "original_date_status={0}" -f `
                    $DateInfo.Status
            ),
            "-metadata",
            (
                "original_file_creation_time_utc={0}" -f `
                    $DateInfo.OriginalCreationTimeUtcText
            ),
            "-metadata",
            (
                "original_file_last_write_time_utc={0}" -f `
                    $DateInfo.OriginalLastWriteTimeUtcText
            )
        )

        if (
            -not [string]::IsNullOrWhiteSpace(
                [string]$DateInfo.YearHints
            )
        ) {
            $argsOut += @(
                "-metadata",
                (
                    "archive_year_hint={0}" -f `
                        $DateInfo.YearHints
                )
            )
        }

        if ($DateInfo.HasCanonicalDate) {
            $argsOut += @(
                "-metadata",
                (
                    "creation_time={0}" -f `
                        $DateInfo.CanonicalMetadata
                ),
                "-metadata",
                (
                    "date={0}" -f `
                        $DateInfo.CanonicalDate
                ),
                "-metadata",
                (
                    "original_capture_time={0}" -f `
                        $DateInfo.CanonicalMetadata
                ),
                "-metadata",
                (
                    "original_date_source={0}" -f `
                        $DateInfo.Source
                ),
                "-metadata",
                (
                    "original_date_confidence={0}" -f `
                        $DateInfo.Confidence
                )
            )
        }
    }

    return @($argsOut)
}

function Test-ArchiveMetadata {
    param(
        [string]$File,
        [object]$DateInfo
    )

    $metaJson =
        & $script:FfprobeExe `
            -v error `
            -show_entries `
                format_tags=creation_time,date,original_capture_time,original_date_source,original_date_confidence,original_date_status,archive_year_hint,restoration_time,original_file_creation_time_utc,original_file_last_write_time_utc `
            -of json `
            "$File" `
            2>$null |
        Out-String

    if (
        $LASTEXITCODE -ne 0 -or
        [string]::IsNullOrWhiteSpace(
            $metaJson
        )
    ) {
        return $false
    }

    try {
        $mo =
            $metaJson |
            ConvertFrom-Json

        $tags =
            $mo.format.tags

        if ($null -eq $tags) {
            return $false
        }

        if (
            [string]::IsNullOrWhiteSpace(
                [string]$tags.restoration_time
            )
        ) {
            return $false
        }

        if (
            $null -ne $DateInfo -and
            $DateInfo.HasCanonicalDate
        ) {
            if (
                [string]::IsNullOrWhiteSpace(
                    [string]$tags.original_capture_time
                )
            ) {
                return $false
            }

            if (
                [string]$tags.original_capture_time -notlike
                "$($DateInfo.CanonicalDate)*"
            ) {
                return $false
            }

            if (
                [string]::IsNullOrWhiteSpace(
                    [string]$tags.original_date_source
                )
            ) {
                return $false
            }
        }

        return $true
    }
    catch {
        return $false
    }
}

function Set-ArchiveFilesystemTimes {
    param(
        [string]$FinalFile,
        [object]$DateInfo
    )

    if (
        $SemPreservarDatasSistemaArquivos -or
        $null -eq $DateInfo
    ) {
        return
    }

    try {
        $fi =
            Get-Item `
                -LiteralPath $FinalFile `
                -ErrorAction Stop

        # Espelha os timestamps do ORIGINAL, em vez de inventar que
        # a Data Original Canônica é necessariamente a criação NTFS.
        $fi.CreationTimeUtc =
            $DateInfo.OriginalCreationTimeUtc

        $fi.LastWriteTimeUtc =
            $DateInfo.OriginalLastWriteTimeUtc
    }
    catch {
        Write-Host (
            "       AVISO: não foi possível preservar timestamps do sistema de arquivos: {0}" -f `
                $_.Exception.Message
        ) -ForegroundColor DarkYellow
    }
}

function Rewrite-ExistingFinalMetadata {
    param(
        [string]$OriginalFile,
        [string]$FinalFile,
        [object]$DateInfo,
        [string]$LogFile
    )

    if (
        -not (
            Test-Path `
                -LiteralPath $FinalFile `
                -PathType Leaf
        )
    ) {
        return [pscustomobject]@{
            Status = "FINAL_NAO_ENCONTRADO"
            File = $FinalFile
        }
    }

    $before =
        Get-MediaInfo $FinalFile

    if (-not $before) {
        throw (
            "Master existente não pôde ser lido: {0}" -f `
                $FinalFile
        )
    }

    $finalDir =
        Split-Path `
            -Parent $FinalFile

    $temp =
        Join-Path `
            $finalDir `
            (
                [IO.Path]::GetFileNameWithoutExtension(
                    $FinalFile
                ) +
                ".metadata_v163.tmp.mp4"
            )

    $backup =
        Join-Path `
            $finalDir `
            (
                [IO.Path]::GetFileName(
                    $FinalFile
                ) +
                ".metadata_v163.bak"
            )

    Remove-Item `
        -LiteralPath $temp `
        -Force `
        -ErrorAction SilentlyContinue

    Remove-Item `
        -LiteralPath $backup `
        -Force `
        -ErrorAction SilentlyContinue

    $existingFi =
        Get-Item `
            -LiteralPath $FinalFile

    $restorationUtc =
        $existingFi.CreationTimeUtc

    $metaArgs =
        Get-ArchiveMetadataArgs `
            -DateInfo $DateInfo `
            -RestorationTimeUtc $restorationUtc

    $args =
        @(
            "-hide_banner",
            "-loglevel","warning",
            "-i",$FinalFile,
            "-i",$OriginalFile,
            "-map","0:v:0",
            "-map","0:a?",
            "-c","copy",
            "-map_metadata","1",
            "-map_chapters","1"
        )

    $args += $metaArgs

    $args += @(
        "-movflags","+faststart+use_metadata_tags",
        "-y",$temp
    )

    & $script:FfmpegExe @args `
        2> $LogFile |
        Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw (
            "Remux apenas-metadados falhou: {0}" -f `
                $LogFile
        )
    }

    $after =
        Get-MediaInfo $temp

    if (-not $after) {
        throw "ffprobe não conseguiu ler o remux de metadados."
    }

    if (
        $after.FrameCount -ne
        $before.FrameCount
    ) {
        throw (
            "Remux de metadados alterou frame count: antes {0}; depois {1}." -f `
                $before.FrameCount,
                $after.FrameCount
        )
    }

    if (
        $after.Width -ne $before.Width -or
        $after.Height -ne $before.Height
    ) {
        throw "Remux de metadados alterou a resolução."
    }

    if (
        -not (
            Test-ArchiveMetadata `
                -File $temp `
                -DateInfo $DateInfo
        )
    ) {
        throw "Validação dos metadados arquivísticos falhou."
    }

    try {
        Move-Item `
            -LiteralPath $FinalFile `
            -Destination $backup `
            -Force

        Move-Item `
            -LiteralPath $temp `
            -Destination $FinalFile `
            -Force

        Set-ArchiveFilesystemTimes `
            -FinalFile $FinalFile `
            -DateInfo $DateInfo

        Remove-Item `
            -LiteralPath $backup `
            -Force `
            -ErrorAction SilentlyContinue
    }
    catch {
        if (
            -not (
                Test-Path `
                    -LiteralPath $FinalFile
            ) -and
            (
                Test-Path `
                    -LiteralPath $backup
            )
        ) {
            Move-Item `
                -LiteralPath $backup `
                -Destination $FinalFile `
                -Force `
                -ErrorAction SilentlyContinue
        }

        throw
    }

    return [pscustomobject]@{
        Status = "OK"
        File = $FinalFile
        FrameCount = $after.FrameCount
        DataOriginal =
            if ($DateInfo.HasCanonicalDate) {
                $DateInfo.CanonicalDisplay
            }
            else {
                ""
            }
        FonteData =
            $DateInfo.Source
    }
}


function Get-VideoCandidates {
    param(
        [string]$Root,
        [bool]$Recursive,
        [string]$ExcludedRoot
    )

    $exts = @(
        ".mp4",".mov",".mkv",".avi",".m4v",
        ".mts",".m2ts",".ts",".wmv",".webm",
        ".mpg",".mpeg",".mpe",".3gp",".3g2",
        ".flv",".vob",".asf",".ogv",".mxf",
        ".dv",".mpv",".mod",".tod",".vro"
    )

    $gciArgs = @{
        LiteralPath = $Root
        File = $true
        ErrorAction = "SilentlyContinue"
    }

    if ($Recursive) {
        $gciArgs["Recurse"] = $true
    }

    $files =
        Get-ChildItem @gciArgs

    $excluded =
        $ExcludedRoot.
        TrimEnd("\","/")

    return @(
        $files |
        Where-Object {
            $f = $_

            $underOutput =
                $f.FullName.StartsWith(
                    $excluded + "\",
                    [StringComparison]::OrdinalIgnoreCase
                ) -or
                (
                    $f.FullName.Equals(
                        $excluded,
                        [StringComparison]::OrdinalIgnoreCase
                    )
                )

            (-not $underOutput) -and
            (
                $exts -contains
                $f.Extension.ToLowerInvariant()
            )
        } |
        Sort-Object FullName
    )
}

# =====================================================================
# 02 - PROCESS WRAPPER / PROGRESSO
# =====================================================================

function Read-FfmpegProgress {
    param([string]$ProgressFile)

    if (
        -not (
            Test-Path `
                -LiteralPath $ProgressFile
        )
    ) {
        return $null
    }

    try {
        $lines = @(
            Get-Content `
                -LiteralPath $ProgressFile `
                -Tail 100 `
                -ErrorAction SilentlyContinue
        )

        if ($lines.Count -eq 0) {
            return $null
        }

        $outUs = $null
        $speed = $null

        for (
            $i = $lines.Count - 1;
            $i -ge 0;
            $i--
        ) {
            $line =
                [string]$lines[$i]

            if (
                $null -eq $speed -and
                $line -like "speed=*"
            ) {
                $sv =
                    $line.
                    Substring(6).
                    Trim().
                    TrimEnd("x")

                $tmp = 0.0

                if (
                    [double]::TryParse(
                        $sv,
                        [Globalization.NumberStyles]::Float,
                        $Inv,
                        [ref]$tmp
                    )
                ) {
                    $speed = $tmp
                }
            }

            if ($null -eq $outUs) {
                if (
                    $line -like "out_time_us=*"
                ) {
                    $raw =
                        $line.
                        Substring(12).
                        Trim()

                    $tmp64 = 0L

                    if (
                        [long]::TryParse(
                            $raw,
                            [ref]$tmp64
                        )
                    ) {
                        $outUs = $tmp64
                    }
                }
                elseif (
                    $line -like "out_time_ms=*"
                ) {
                    $raw =
                        $line.
                        Substring(12).
                        Trim()

                    $tmp64 = 0L

                    if (
                        [long]::TryParse(
                            $raw,
                            [ref]$tmp64
                        )
                    ) {
                        $outUs = $tmp64
                    }
                }
            }

            if (
                $null -ne $outUs -and
                $null -ne $speed
            ) {
                break
            }
        }

        if ($null -eq $outUs) {
            return $null
        }

        return [pscustomobject]@{
            Seconds =
                [double]$outUs /
                1000000.0

            Speed = $speed
        }
    }
    catch {
        return $null
    }
}

function Invoke-FfmpegProgress {
    param(
        [string[]]$CommandArgs,
        [string]$Stage,
        [string]$VideoId,
        [double]$Duration,
        [string]$ProgressFile,
        [string]$StdErrLog,
        [string]$WorkingDirectory,
        [string]$ExpectedOutput = ""
    )

    Remove-Item `
        -LiteralPath $ProgressFile `
        -Force `
        -ErrorAction SilentlyContinue

    Remove-Item `
        -LiteralPath $StdErrLog `
        -Force `
        -ErrorAction SilentlyContinue

    $full =
        New-Object `
            System.Collections.Generic.List[string]

    $full.Add("-progress")
    $full.Add($ProgressFile)

    foreach ($a in $CommandArgs) {
        if (
            $null -ne $a -and
            -not [string]::IsNullOrWhiteSpace(
                [string]$a
            )
        ) {
            $full.Add([string]$a)
        }
    }

    $argString =
        Join-ArgString `
            -CommandArgs ([string[]]$full)

    if (
        [string]::IsNullOrWhiteSpace(
            $argString
        )
    ) {
        throw "ArgumentList FFmpeg vazio."
    }

    $proc =
        Start-Process `
            -FilePath $script:FfmpegExe `
            -ArgumentList $argString `
            -RedirectStandardError $StdErrLog `
            -WorkingDirectory $WorkingDirectory `
            -PassThru `
            -NoNewWindow

    $lastCpu = 0.0
    $lastClock = Get-Date
    $first = $true

    while (-not $proc.HasExited) {
        Start-Sleep `
            -Seconds $IntervaloStatusSeg

        $proc.Refresh()

        $now = Get-Date

        $dt =
            [math]::Max(
                0.25,
                ($now - $lastClock).TotalSeconds
            )

        $cpuCores = 0.0

        try {
            $cpuTotal =
                $proc.
                TotalProcessorTime.
                TotalSeconds

            if (
                -not $first -and
                $cpuTotal -ge $lastCpu
            ) {
                $cpuCores =
                    ($cpuTotal - $lastCpu) /
                    $dt
            }

            $lastCpu = $cpuTotal
        } catch {}

        $pg =
            Read-FfmpegProgress `
                $ProgressFile

        $sec = 0.0
        $speed = $null

        if ($pg) {
            $sec =
                [math]::Min(
                    $Duration,
                    [double]$pg.Seconds
                )

            $speed = $pg.Speed
        }

        $pct =
            if ($Duration -gt 0) {
                [math]::Min(
                    99.9,
                    100.0 *
                    $sec /
                    $Duration
                )
            }
            else {
                0.0
            }

        $speedText =
            if (
                $speed -and
                $speed -gt 0
            ) {
                "{0:N2}x" -f $speed
            }
            else {
                "--"
            }

        $eta = "--:--"

        if (
            $speed -and
            $speed -gt 0.01 -and
            $Duration -gt $sec
        ) {
            $eta =
                (Get-Date).
                AddSeconds(
                    ($Duration - $sec) /
                    $speed
                ).
                ToString("HH:mm")
        }

        $gpu =
            Get-NvidiaStats

        $procGpu =
            Get-ProcessGpuEngineStats `
                -ProcessId $proc.Id

        $ram =
            Get-RamPct

        $gpuText =
            if ($gpu) {
                "RTX G{0}% E{1}% D{2}% {3}C VRAM {4}/{5}MB" -f `
                    $gpu.Gpu,
                    $gpu.Enc,
                    $gpu.Dec,
                    $gpu.Temp,
                    $gpu.Vram,
                    $gpu.VramTotal
            }
            else {
                "RTX --"
            }

        $procGpuText =
            if ($procGpu) {
                $decodeTag =
                    if ($script:DecodeBackend -eq "QSV") {
                        "QSV-D"
                    }
                    elseif ($script:DecodeBackend -eq "CUDA") {
                        "CUDA-D"
                    }
                    else {
                        "D"
                    }

                "{0} {1:N0}% VENC {2:N0}% 3D {3:N0}%" -f `
                    $decodeTag,
                    $procGpu.Decode,
                    $procGpu.Encode,
                    $procGpu.ThreeD
            }
            else {
                "PROC-GPU --"
            }

        $ramText =
            if ($null -ne $ram) {
                "RAM {0:N0}%" -f $ram
            }
            else {
                "RAM --"
            }

        Write-Host (
            "{0:HH:mm:ss} | {1} {2,-18} | {3,5:N1}% | {4}/{5} | speed {6} | ETA~ {7} | CPU {8:N1}c | {9} | {10} | {11}" -f `
                $now,
                $VideoId,
                $Stage,
                $pct,
                (To-ShortTime $sec),
                (To-ShortTime $Duration),
                $speedText,
                $eta,
                $cpuCores,
                $gpuText,
                $procGpuText,
                $ramText
        )

        $lastClock = $now
        $first = $false
    }

    $proc.WaitForExit()

    $exitCodeAvailable = $false
    $exit = 0

    try {
        $exit =
            [int]$proc.ExitCode

        $exitCodeAvailable = $true
    } catch {}

    $progressEnded = $false

    if (
        Test-Path `
            -LiteralPath $ProgressFile
    ) {
        $progressEnded =
            [bool](
                Select-String `
                    -LiteralPath $ProgressFile `
                    -Pattern '^progress=end\s*$' `
                    -Quiet `
                    -ErrorAction SilentlyContinue
            )
    }

    if (
        $exitCodeAvailable -and
        $exit -ne 0
    ) {
        return $exit
    }

    if (-not $progressEnded) {
        if (-not $exitCodeAvailable) {
            return 9100
        }

        return 9101
    }

    if (
        -not [string]::IsNullOrWhiteSpace(
            $ExpectedOutput
        )
    ) {
        if (
            -not (
                Test-Path `
                    -LiteralPath $ExpectedOutput `
                    -PathType Leaf
            )
        ) {
            return 9102
        }

        try {
            $fi =
                Get-Item `
                    -LiteralPath $ExpectedOutput

            # V1.6.1+: 64 KB não é um limiar válido para toda mídia.
            # AACs muito curtos podem ser menores que isso e ainda serem
            # perfeitamente válidos.
            if ($fi.Length -lt 1KB) {
                return 9103
            }

            $probeText =
                & $script:FfprobeExe `
                    -v error `
                    -show_entries format=format_name,duration `
                    -of default=noprint_wrappers=1 `
                    "$ExpectedOutput" `
                    2>$null |
                Out-String

            if (
                $LASTEXITCODE -ne 0 -or
                [string]::IsNullOrWhiteSpace($probeText)
            ) {
                return 9104
            }

            if (
                $probeText -notmatch '(?m)^format_name=.+$'
            ) {
                return 9104
            }

            $durationLine =
                @(
                    $probeText -split "`r?`n" |
                    Where-Object {
                        $_ -match '^duration='
                    }
                ) |
                Select-Object -First 1

            if (
                -not [string]::IsNullOrWhiteSpace(
                    [string]$durationLine
                )
            ) {
                $durationText =
                    ([string]$durationLine).Substring(
                        ([string]$durationLine).IndexOf("=") + 1
                    )

                $durationValue = 0.0

                if (
                    [double]::TryParse(
                        $durationText,
                        [Globalization.NumberStyles]::Float,
                        [Globalization.CultureInfo]::InvariantCulture,
                        [ref]$durationValue
                    )
                ) {
                    if ($durationValue -le 0.0) {
                        return 9105
                    }
                }
            }
        }
        catch {
            return 9104
        }
    }

    if (-not $exitCodeAvailable) {
        Write-Warning (
            "FFmpeg terminou com progress=end, mas o ExitCode não ficou disponível. Saída aceita provisoriamente; a validação do estágio continua."
        )
    }

    return 0
}

# =====================================================================
# 03 - GPU / CODEC
# =====================================================================

function Get-EncodeSettings {
    param([object]$Info)

    $sourceMbps =
        if ($Info.BitRate -gt 0) {
            $Info.BitRate /
            1000000.0
        }
        else {
            0.0
        }

    $target =
        if ($sourceMbps -gt 0) {
            [math]::Max(
                12.0,
                [math]::Min(
                    28.0,
                    $sourceMbps * 1.35
                )
            )
        }
        else {
            16.0
        }

    $max =
        [math]::Min(
            40.0,
            $target * 1.5
        )

    $buf =
        [math]::Min(
            56.0,
            $target * 2.0
        )

    return [pscustomobject]@{
        Target =
            (Fmt-Inv $target "0.0") + "M"

        MaxRate =
            (Fmt-Inv $max "0.0") + "M"

        BufSize =
            (Fmt-Inv $buf "0.0") + "M"
    }
}

function Get-EncoderArgs {
    param([object]$EncodeSettings)

    if ($script:UseGpuEncode) {
        return @(
            "-c:v","h264_nvenc",
            "-preset","p5",
            "-tune","hq",
            "-rc","vbr",
            "-cq","18",
            "-b:v",$EncodeSettings.Target,
            "-maxrate",$EncodeSettings.MaxRate,
            "-bufsize",$EncodeSettings.BufSize,
            "-profile:v","high",
            "-level:v","4.1",
            "-g","120",
            "-bf","2",
            "-pix_fmt","yuv420p"
        )
    }

    return @(
        "-c:v","libx264",
        "-preset","medium",
        "-crf","18",
        "-profile:v","high",
        "-level:v","4.1",
        "-pix_fmt","yuv420p"
    )
}

function Get-QsvDecoderName {
    param([string]$Codec)

    switch (([string]$Codec).Trim().ToLowerInvariant()) {
        "h264"       { return "h264_qsv" }
        "hevc"       { return "hevc_qsv" }
        "mpeg2video" { return "mpeg2_qsv" }
        "mjpeg"      { return "mjpeg_qsv" }
        "vp8"        { return "vp8_qsv" }
        "vp9"        { return "vp9_qsv" }
        "av1"        { return "av1_qsv" }
        "vc1"        { return "vc1_qsv" }
        default      { return "" }
    }
}

function Test-QsvDecoderPresent {
    param([string]$Decoder)

    if (
        [string]::IsNullOrWhiteSpace($Decoder) -or
        [string]::IsNullOrWhiteSpace([string]$script:QsvDecodersText)
    ) {
        return $false
    }

    return (
        $script:QsvDecodersText -match
        ("(?m)\b" + [regex]::Escape($Decoder) + "\b")
    )
}

function Get-DecodeArgs {
    if ($script:DecodeBackend -eq "CUDA") {
        return @(
            "-hwaccel","cuda",
            "-hwaccel_output_format","cuda"
        )
    }

    if ($script:DecodeBackend -eq "QSV") {
        return @(
            "-init_hw_device",
                "qsv=iqsv:hw,child_device_type=d3d11va",
            "-filter_hw_device","iqsv",
            "-hwaccel","qsv",
            "-hwaccel_device","iqsv",
            "-hwaccel_output_format","qsv",
            "-c:v",$script:QsvDecoder
        )
    }

    return @()
}

function Get-CpuEntryFilter {
    if (
        $script:DecodeBackend -eq "CUDA" -or
        $script:DecodeBackend -eq "QSV"
    ) {
        return "hwdownload,format=nv12"
    }

    return "format=yuv420p"
}

function Get-LastLogReason {
    param([string]$Log)

    if (-not (Test-Path -LiteralPath $Log)) {
        return ""
    }

    try {
        return (
            @(
                Get-Content `
                    -LiteralPath $Log `
                    -Tail 4 `
                    -ErrorAction SilentlyContinue
            ) -join " | "
        )
    }
    catch {
        return ""
    }
}

function Get-MedianDouble {
    param([double[]]$Values)

    $v =
        @(
            $Values |
            Where-Object {
                -not [double]::IsNaN($_) -and
                -not [double]::IsInfinity($_)
            } |
            Sort-Object
        )

    if ($v.Count -eq 0) {
        return [double]::PositiveInfinity
    }

    $mid =
        [int][math]::Floor(
            $v.Count / 2.0
        )

    if (($v.Count % 2) -eq 1) {
        return [double]$v[$mid]
    }

    return (
        (
            [double]$v[$mid - 1] +
            [double]$v[$mid]
        ) / 2.0
    )
}

function Invoke-CudaDecodeTrial {
    param(
        [string]$File,
        [string]$Log,
        [int]$TestW,
        [int]$TestH,
        [int]$Frames,
        [string]$Label
    )

    Add-Content `
        -LiteralPath $Log `
        -Value (
            "`r`n===== {0} | {1} frames =====" -f `
                $Label,
                $Frames
        ) `
        -Encoding UTF8

    $sw =
        [Diagnostics.Stopwatch]::StartNew()

    & $script:FfmpegExe `
        -hide_banner `
        -loglevel error `
        -hwaccel cuda `
        -hwaccel_output_format cuda `
        -i "$File" `
        -map 0:v:0 `
        -frames:v $Frames `
        -an `
        -vf (
            "scale_cuda=${TestW}:${TestH}," +
            "hwdownload,format=nv12"
        ) `
        -f null `
        NUL `
        2>> $Log |
        Out-Null

    $exit = $LASTEXITCODE
    $sw.Stop()

    return [pscustomobject]@{
        Ok = ($exit -eq 0)
        ExitCode = $exit
        ElapsedMs =
            [double]$sw.Elapsed.TotalMilliseconds
    }
}

function Invoke-QsvDecodeTrial {
    param(
        [string]$File,
        [string]$Decoder,
        [string]$Log,
        [int]$TestW,
        [int]$TestH,
        [int]$Frames,
        [string]$Label
    )

    Add-Content `
        -LiteralPath $Log `
        -Value (
            "`r`n===== {0} | {1} frames | {2} =====" -f `
                $Label,
                $Frames,
                $Decoder
        ) `
        -Encoding UTF8

    $sw =
        [Diagnostics.Stopwatch]::StartNew()

    & $script:FfmpegExe `
        -hide_banner `
        -loglevel error `
        -init_hw_device `
            "qsv=iqsv:hw,child_device_type=d3d11va" `
        -filter_hw_device iqsv `
        -hwaccel qsv `
        -hwaccel_device iqsv `
        -hwaccel_output_format qsv `
        -c:v $Decoder `
        -i "$File" `
        -map 0:v:0 `
        -frames:v $Frames `
        -an `
        -vf (
            "scale_qsv=w=${TestW}:h=${TestH}," +
            "hwdownload,format=nv12"
        ) `
        -f null `
        NUL `
        2>> $Log |
        Out-Null

    $exit = $LASTEXITCODE
    $sw.Stop()

    return [pscustomobject]@{
        Ok = ($exit -eq 0)
        ExitCode = $exit
        ElapsedMs =
            [double]$sw.Elapsed.TotalMilliseconds
    }
}

function Invoke-CudaDecodeBenchmark {
    param(
        [string]$File,
        [string]$Log,
        [int]$TestW,
        [int]$TestH,
        [int]$WarmupFrames,
        [int]$MeasureFrames
    )

    Remove-Item `
        -LiteralPath $Log `
        -Force `
        -ErrorAction SilentlyContinue

    $warm =
        Invoke-CudaDecodeTrial `
            -File $File `
            -Log $Log `
            -TestW $TestW `
            -TestH $TestH `
            -Frames $WarmupFrames `
            -Label "WARMUP"

    if (-not $warm.Ok) {
        return [pscustomobject]@{
            Backend = "CUDA"
            Ok = $false
            ExitCode = $warm.ExitCode
            MedianMs = [double]::PositiveInfinity
            Runs = @()
            Decoder = "auto/NVDEC"
            Log = $Log
            SkipReason = "warm-up falhou"
        }
    }

    $runs = @()
    $lastExit = 0

    for (
        $i = 1;
        $i -le $BenchmarkGpuRepeticoes;
        $i++
    ) {
        $trial =
            Invoke-CudaDecodeTrial `
                -File $File `
                -Log $Log `
                -TestW $TestW `
                -TestH $TestH `
                -Frames $MeasureFrames `
                -Label ("MEDICAO_{0}" -f $i)

        $lastExit =
            $trial.ExitCode

        if (-not $trial.Ok) {
            return [pscustomobject]@{
                Backend = "CUDA"
                Ok = $false
                ExitCode = $lastExit
                MedianMs = [double]::PositiveInfinity
                Runs = @($runs)
                Decoder = "auto/NVDEC"
                Log = $Log
                SkipReason = "medição instável"
            }
        }

        $runs +=
            [double]$trial.ElapsedMs
    }

    return [pscustomobject]@{
        Backend = "CUDA"
        Ok = $true
        ExitCode = 0
        MedianMs =
            Get-MedianDouble `
                -Values ([double[]]$runs)
        Runs = @($runs)
        Decoder = "auto/NVDEC"
        Log = $Log
        SkipReason = ""
    }
}

function Invoke-QsvDecodeBenchmark {
    param(
        [string]$File,
        [object]$Info,
        [string]$Log,
        [int]$TestW,
        [int]$TestH,
        [int]$WarmupFrames,
        [int]$MeasureFrames
    )

    $decoder =
        Get-QsvDecoderName $Info.VideoCodec

    if (
        $SemIntelQSV -or
        -not $script:QsvBuildAvailable -or
        -not (
            Test-QsvDecoderPresent $decoder
        )
    ) {
        $reason =
            if ($SemIntelQSV) {
                "desativado por -SemIntelQSV"
            }
            elseif (-not $script:QsvBuildAvailable) {
                "QSV não disponível neste build/driver"
            }
            else {
                "decoder QSV não disponível para este codec"
            }

        return [pscustomobject]@{
            Backend = "QSV"
            Ok = $false
            ExitCode = 9201
            MedianMs = [double]::PositiveInfinity
            Runs = @()
            Decoder = $decoder
            Log = $Log
            SkipReason = $reason
        }
    }

    Remove-Item `
        -LiteralPath $Log `
        -Force `
        -ErrorAction SilentlyContinue

    $warm =
        Invoke-QsvDecodeTrial `
            -File $File `
            -Decoder $decoder `
            -Log $Log `
            -TestW $TestW `
            -TestH $TestH `
            -Frames $WarmupFrames `
            -Label "WARMUP"

    if (-not $warm.Ok) {
        return [pscustomobject]@{
            Backend = "QSV"
            Ok = $false
            ExitCode = $warm.ExitCode
            MedianMs = [double]::PositiveInfinity
            Runs = @()
            Decoder = $decoder
            Log = $Log
            SkipReason = "warm-up falhou"
        }
    }

    $runs = @()
    $lastExit = 0

    for (
        $i = 1;
        $i -le $BenchmarkGpuRepeticoes;
        $i++
    ) {
        $trial =
            Invoke-QsvDecodeTrial `
                -File $File `
                -Decoder $decoder `
                -Log $Log `
                -TestW $TestW `
                -TestH $TestH `
                -Frames $MeasureFrames `
                -Label ("MEDICAO_{0}" -f $i)

        $lastExit =
            $trial.ExitCode

        if (-not $trial.Ok) {
            return [pscustomobject]@{
                Backend = "QSV"
                Ok = $false
                ExitCode = $lastExit
                MedianMs = [double]::PositiveInfinity
                Runs = @($runs)
                Decoder = $decoder
                Log = $Log
                SkipReason = "medição instável"
            }
        }

        $runs +=
            [double]$trial.ElapsedMs
    }

    return [pscustomobject]@{
        Backend = "QSV"
        Ok = $true
        ExitCode = 0
        MedianMs =
            Get-MedianDouble `
                -Values ([double[]]$runs)
        Runs = @($runs)
        Decoder = $decoder
        Log = $Log
        SkipReason = ""
    }
}

function Format-BenchmarkRuns {
    param([object[]]$Runs)

    if ($null -eq $Runs -or $Runs.Count -eq 0) {
        return ""
    }

    return (
        @(
            $Runs |
            ForEach-Object {
                "{0:N0}" -f [double]$_
            }
        ) -join "|"
    )
}

function Add-GpuBenchmarkRecord {
    param(
        [string]$VideoId,
        [string]$StageName,
        [string]$File,
        [object]$Info,
        [int]$MeasureFrames,
        [object]$Cuda,
        [object]$Qsv,
        [string]$Chosen,
        [string]$Reason
    )

    if (
        [string]::IsNullOrWhiteSpace(
            [string]$script:GpuBenchmarkCsv
        )
    ) {
        return
    }

    $row =
        [pscustomobject]@{
            Data =
                Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Id = $VideoId
            Etapa = $StageName
            Arquivo = $File
            Codec = $Info.VideoCodec
            Resolucao =
                "{0}x{1}" -f `
                    $Info.Width,
                    $Info.Height
            FramesMedicao = $MeasureFrames
            Repeticoes = $BenchmarkGpuRepeticoes
            NvidiaOK = $Cuda.Ok
            NvidiaMedianaMs =
                if ($Cuda.Ok) {
                    [math]::Round(
                        [double]$Cuda.MedianMs,
                        1
                    )
                }
                else {
                    ""
                }
            NvidiaRunsMs =
                Format-BenchmarkRuns $Cuda.Runs
            IntelOK = $Qsv.Ok
            IntelDecoder = $Qsv.Decoder
            IntelMedianaMs =
                if ($Qsv.Ok) {
                    [math]::Round(
                        [double]$Qsv.MedianMs,
                        1
                    )
                }
                else {
                    ""
                }
            IntelRunsMs =
                Format-BenchmarkRuns $Qsv.Runs
            Escolhido = $Chosen
            Motivo = $Reason
        }

    if (
        Test-Path `
            -LiteralPath $script:GpuBenchmarkCsv
    ) {
        $row |
            Export-Csv `
                -LiteralPath $script:GpuBenchmarkCsv `
                -NoTypeInformation `
                -Encoding UTF8 `
                -Delimiter ";" `
                -Append
    }
    else {
        $row |
            Export-Csv `
                -LiteralPath $script:GpuBenchmarkCsv `
                -NoTypeInformation `
                -Encoding UTF8 `
                -Delimiter ";"
    }
}

function Test-GpuDecodeForFile {
    param(
        [string]$VideoId,
        [string]$File,
        [object]$Info,
        [string]$WorkDir,
        [string]$StageName = "TRABALHO"
    )

    $script:UseGpuDecode = $false
    $script:UseQsvDecode = $false
    $script:DecodeBackend = "CPU"
    $script:QsvDecoder = ""

    $testW =
        [int][math]::Min(
            320,
            [int]$Info.Width
        )

    $testW =
        [int](
            [math]::Floor(
                $testW / 2.0
            ) * 2
        )

    if ($testW -lt 2) {
        $testW = 2
    }

    $testH =
        [int](
            [math]::Round(
                (
                    $testW *
                    $Info.Height /
                    [double]$Info.Width
                ) / 2.0
            ) * 2
        )

    if ($testH -lt 2) {
        $testH = 2
    }

    $availableFrames =
        [long]$Info.FrameCount

    $measureFrames =
        $BenchmarkGpuFrames

    $warmupFrames =
        $BenchmarkGpuWarmupFrames

    if ($availableFrames -gt 0) {
        $measureFrames =
            [int][math]::Max(
                1,
                [math]::Min(
                    $BenchmarkGpuFrames,
                    $availableFrames
                )
            )

        $warmupFrames =
            [int][math]::Max(
                1,
                [math]::Min(
                    $BenchmarkGpuWarmupFrames,
                    $availableFrames
                )
            )
    }

    $stageSafe =
        (
            $StageName -replace
                '[^A-Za-z0-9_-]',
                '_'
        )

    $cudaLog =
        Join-Path `
            $WorkDir `
            ("00_GPU_BENCH_{0}_NVIDIA.log" -f $stageSafe)

    $qsvLog =
        Join-Path `
            $WorkDir `
            ("00_GPU_BENCH_{0}_INTEL_QSV.log" -f $stageSafe)

    Write-Host (
        "       Benchmark decode {0}: warm-up {1}f + {2}x{3}f por backend." -f `
            $StageName,
            $warmupFrames,
            $BenchmarkGpuRepeticoes,
            $measureFrames
    ) -ForegroundColor DarkCyan

    $cuda =
        Invoke-CudaDecodeBenchmark `
            -File $File `
            -Log $cudaLog `
            -TestW $testW `
            -TestH $testH `
            -WarmupFrames $warmupFrames `
            -MeasureFrames $measureFrames

    $qsv =
        Invoke-QsvDecodeBenchmark `
            -File $File `
            -Info $Info `
            -Log $qsvLog `
            -TestW $testW `
            -TestH $testH `
            -WarmupFrames $warmupFrames `
            -MeasureFrames $measureFrames

    if ($cuda.Ok) {
        Write-Host (
            "       NVIDIA NVDEC/CUDA: mediana {0:N0} ms [{1}]." -f `
                $cuda.MedianMs,
                (Format-BenchmarkRuns $cuda.Runs)
        ) -ForegroundColor Green
    }
    else {
        Write-Host (
            "       NVIDIA NVDEC/CUDA: indisponível/instável (exit {0}; {1})." -f `
                $cuda.ExitCode,
                $cuda.SkipReason
        ) -ForegroundColor Yellow
    }

    if ($qsv.Ok) {
        Write-Host (
            "       Intel QSV/{0}: mediana {1:N0} ms [{2}]." -f `
                $qsv.Decoder,
                $qsv.MedianMs,
                (Format-BenchmarkRuns $qsv.Runs)
        ) -ForegroundColor Green
    }
    else {
        $why =
            if (
                -not [string]::IsNullOrWhiteSpace(
                    [string]$qsv.SkipReason
                )
            ) {
                $qsv.SkipReason
            }
            else {
                "exit $($qsv.ExitCode)"
            }

        Write-Host (
            "       Intel QSV: indisponível/instável ({0})." -f `
                $why
        ) -ForegroundColor DarkYellow
    }

    $chosen = "CPU"
    $reason = "nenhum backend GPU passou no benchmark"

    if ($PreferirIntelQSV -and $qsv.Ok) {
        $chosen = "QSV"
        $reason = "-PreferirIntelQSV ativo"
    }
    elseif ($cuda.Ok -and $qsv.Ok) {
        $qsvThreshold =
            $cuda.MedianMs *
            (
                1.0 -
                ($MargemQsvPct / 100.0)
            )

        if ($qsv.MedianMs -lt $qsvThreshold) {
            $chosen = "QSV"
            $reason =
                "QSV foi pelo menos $MargemQsvPct% mais rápida na mediana"
        }
        else {
            $chosen = "CUDA"
            $reason =
                "CUDA venceu ou ficou dentro da margem de estabilidade"
        }
    }
    elseif ($cuda.Ok) {
        $chosen = "CUDA"
        $reason = "somente CUDA passou"
    }
    elseif ($qsv.Ok) {
        $chosen = "QSV"
        $reason = "somente QSV passou"
    }

    $encoderName =
        if ($script:UseGpuEncode) {
            "NVIDIA NVENC"
        }
        else {
            "libx264"
        }

    if ($chosen -eq "QSV") {
        $script:UseGpuDecode = $true
        $script:UseQsvDecode = $true
        $script:DecodeBackend = "QSV"
        $script:QsvDecoder = $qsv.Decoder

        Write-Host (
            "       ROTA ESCOLHIDA: Intel QSV ({0}) -> filtros CPU -> {1}. {2}" -f `
                $script:QsvDecoder,
                $encoderName,
                $reason
        ) -ForegroundColor Green
    }
    elseif ($chosen -eq "CUDA") {
        $script:UseGpuDecode = $true
        $script:UseQsvDecode = $false
        $script:DecodeBackend = "CUDA"
        $script:QsvDecoder = ""

        Write-Host (
            "       ROTA ESCOLHIDA: NVIDIA NVDEC/CUDA -> filtros CPU -> {0}. {1}" -f `
                $encoderName,
                $reason
        ) -ForegroundColor Green
    }
    else {
        $script:UseGpuDecode = $false
        $script:UseQsvDecode = $false
        $script:DecodeBackend = "CPU"
        $script:QsvDecoder = ""

        Write-Host (
            "       ROTA ESCOLHIDA: CPU decode -> filtros CPU -> {0}. {1}" -f `
                $encoderName,
                $reason
        ) -ForegroundColor Yellow
    }

    Add-GpuBenchmarkRecord `
        -VideoId $VideoId `
        -StageName $StageName `
        -File $File `
        -Info $Info `
        -MeasureFrames $measureFrames `
        -Cuda $cuda `
        -Qsv $qsv `
        -Chosen $chosen `
        -Reason $reason

    return [pscustomobject]@{
        Chosen = $chosen
        Reason = $reason
        Cuda = $cuda
        Qsv = $qsv
        MeasureFrames = $measureFrames
        Stage = $StageName
    }
}

function Invoke-VfrNormalizationAttempt {
    param(
        [string]$VideoId,
        [string]$Source,
        [object]$Info,
        [string]$WorkDir,
        [string]$Output,
        [double]$TargetFps,
        [string]$BackendLabel
    )

    $enc =
        Get-EncodeSettings $Info

    $args = @(
        "-hide_banner",
        "-nostats",
        "-loglevel","warning"
    )

    $args +=
        Get-DecodeArgs

    $args += @(
        "-i",$Source,
        "-map","0:v:0",
        "-map","0:a?"
    )

    $vf =
        if (
            $script:DecodeBackend -eq "CUDA" -or
            $script:DecodeBackend -eq "QSV"
        ) {
            (
                (Get-CpuEntryFilter) +
                ",fps=" +
                (Fmt-Inv $TargetFps)
            )
        }
        else {
            "fps=" + (Fmt-Inv $TargetFps)
        }

    $args += @(
        "-vf",$vf,
        "-c:a","copy",
        "-r",
            (Fmt-Inv $TargetFps)
    )

    $args +=
        Get-EncoderArgs $enc

    $args += @(
        "-movflags","+faststart",
        "-y",$Output
    )

    $safeBackend =
        (
            $BackendLabel -replace
                '[^A-Za-z0-9_-]',
                '_'
        )

    $progress =
        Join-Path `
            $WorkDir `
            ("00_NORMALIZADO_{0}_progress.txt" -f $safeBackend)

    $log =
        Join-Path `
            $WorkDir `
            ("00_NORMALIZADO_{0}.log" -f $safeBackend)

    $exit =
        Invoke-FfmpegProgress `
            -CommandArgs $args `
            -Stage (
                "NORMALIZA_VFR_{0}" -f `
                    $BackendLabel
            ) `
            -VideoId $VideoId `
            -Duration $Info.Duration `
            -ProgressFile $progress `
            -StdErrLog $log `
            -WorkingDirectory $WorkDir `
            -ExpectedOutput $Output

    return [pscustomobject]@{
        ExitCode = $exit
        Log = $log
        Backend = $BackendLabel
    }
}

function Normalize-VfrIfNeeded {
    param(
        [string]$VideoId,
        [string]$Source,
        [object]$Info,
        [string]$WorkDir
    )

    if (-not $Info.IsVfr) {
        return [pscustomobject]@{
            File = $Source
            Info = $Info
            Normalized = $false
            NormalizationBackend = "N/A"
        }
    }

    $out =
        Join-Path `
            $WorkDir `
            "00_NORMALIZADO_CFR.mp4"

    $done =
        Join-Path `
            $WorkDir `
            "00_NORMALIZADO_CFR.done"

    if (
        (-not $Forcar) -and
        (Test-Path -LiteralPath $done) -and
        (Test-Path -LiteralPath $out)
    ) {
        $newInfo =
            Get-MediaInfo $out

        return [pscustomobject]@{
            File = $out
            Info = $newInfo
            Normalized = $true
            NormalizationBackend = "CHECKPOINT"
        }
    }

    $targetFps =
        Nearest-CommonFps $Info.AvgFps

    Write-Host (
        "  [0/8] Fonte VFR detectada. Normalizando para CFR {0:N3} fps." -f `
            $targetFps
    ) -ForegroundColor Yellow

    $normalizationEncoder =
        if ($script:UseGpuEncode) {
            "NVIDIA NVENC"
        }
        else {
            "libx264"
        }

    Write-Host (
        "       Decode da normalização: {0}; encode: {1}." -f `
            $script:DecodeBackend,
            $normalizationEncoder
    ) -ForegroundColor DarkCyan

    Remove-Item `
        -LiteralPath $out `
        -Force `
        -ErrorAction SilentlyContinue

    $attempt =
        Invoke-VfrNormalizationAttempt `
            -VideoId $VideoId `
            -Source $Source `
            -Info $Info `
            -WorkDir $WorkDir `
            -Output $out `
            -TargetFps $targetFps `
            -BackendLabel $script:DecodeBackend

    $normalizationBackend =
        $script:DecodeBackend

    if (
        $attempt.ExitCode -ne 0 -and
        $script:DecodeBackend -ne "CPU"
    ) {
        Write-Host (
            "       AVISO: normalização com {0} falhou (exit {1}). Repetindo somente esta etapa com decode CPU." -f `
                $script:DecodeBackend,
                $attempt.ExitCode
        ) -ForegroundColor Yellow

        $script:UseGpuDecode = $false
        $script:UseQsvDecode = $false
        $script:DecodeBackend = "CPU"
        $script:QsvDecoder = ""

        Remove-Item `
            -LiteralPath $out `
            -Force `
            -ErrorAction SilentlyContinue

        $attempt =
            Invoke-VfrNormalizationAttempt `
                -VideoId $VideoId `
                -Source $Source `
                -Info $Info `
                -WorkDir $WorkDir `
                -Output $out `
                -TargetFps $targetFps `
                -BackendLabel "CPU_FALLBACK"

        $normalizationBackend =
            "CPU_FALLBACK"
    }

    if ($attempt.ExitCode -ne 0) {
        throw (
            "Normalização VFR falhou (exit {0}): {1}" -f `
                $attempt.ExitCode,
                $attempt.Log
        )
    }

    New-Item `
        -ItemType File `
        -Path $done `
        -Force |
        Out-Null

    $newInfo =
        Get-MediaInfo $out

    return [pscustomobject]@{
        File = $out
        Info = $newInfo
        Normalized = $true
        NormalizationBackend = $normalizationBackend
    }
}

# =====================================================================
# 05 - CROPDETECT / PILLARBOX
# =====================================================================

function Flush-CropMetaFrame {
    param(
        [System.Collections.ArrayList]$Samples,
        [hashtable]$Frame
    )

    if (
        -not $Frame.ContainsKey("T")
    ) {
        return
    }

    foreach ($k in @("w","h","x","y")) {
        if (
            -not $Frame.ContainsKey($k)
        ) {
            return
        }
    }

    [void]$Samples.Add(
        [pscustomobject]@{
            T = [double]$Frame["T"]
            MetaFrame =
                [int]$Frame["Frame"]
            W = [int]$Frame["w"]
            H = [int]$Frame["h"]
            X = [int]$Frame["x"]
            Y = [int]$Frame["y"]
        }
    )
}

function Parse-CropMetadata {
    param(
        [string]$MetadataFile,
        [double]$TimeOffset = 0.0
    )

    $samples =
        New-Object `
            System.Collections.ArrayList

    if (
        -not (
            Test-Path `
                -LiteralPath $MetadataFile
        )
    ) {
        return @()
    }

    $frame = @{}

    Get-Content `
        -LiteralPath $MetadataFile `
        -ReadCount 2000 |
        ForEach-Object {

        foreach ($lineRaw in $_) {
            $line =
                [string]$lineRaw

            $fm =
                [regex]::Match(
                    $line,
                    '^frame:(?<f>[0-9]+)\s+pts:\S+\s+pts_time:(?<t>-?[0-9]+(?:\.[0-9]+)?)'
                )

            if ($fm.Success) {
                Flush-CropMetaFrame `
                    -Samples $samples `
                    -Frame $frame

                $frame = @{}

                $t = 0.0

                [void][double]::TryParse(
                    $fm.Groups["t"].Value,
                    [Globalization.NumberStyles]::Float,
                    $Inv,
                    [ref]$t
                )

                $frame["T"] =
                    $t +
                    $TimeOffset

                $frame["Frame"] =
                    [int]$fm.Groups["f"].Value

                continue
            }

            $km =
                [regex]::Match(
                    $line,
                    '^lavfi\.cropdetect\.(?<k>w|h|x|y)=(?<v>-?[0-9]+)'
                )

            if ($km.Success) {
                $frame[
                    $km.Groups["k"].Value
                ] =
                    [int]$km.Groups["v"].Value
            }
        }
    }

    Flush-CropMetaFrame `
        -Samples $samples `
        -Frame $frame

    return @(
        $samples |
        Sort-Object T
    )
}

function Classify-PillarSamples {
    param(
        [object[]]$Raw,
        [int]$ScanW,
        [int]$ScanH
    )

    $minBar =
        $ScanW *
        ($BarraMinimaPct / 100.0)

    $minH =
        $ScanH * 0.94

    $out = @()

    foreach ($s in $Raw) {
        $left =
            [math]::Max(
                0,
                [int]$s.X
            )

        $right =
            [math]::Max(
                0,
                $ScanW -
                (
                    [int]$s.X +
                    [int]$s.W
                )
            )

        $asymPct =
            100.0 *
            [math]::Abs(
                $left -
                $right
            ) /
            $ScanW

        $pillar = (
            ($left -ge $minBar) -and
            ($right -ge $minBar) -and
            ([int]$s.H -ge $minH) -and
            ($asymPct -le 8.0)
        )

        $out += [pscustomobject]@{
            T = [double]$s.T
            W = [int]$s.W
            H = [int]$s.H
            X = [int]$s.X
            Y = [int]$s.Y
            Left = $left
            Right = $right
            Pillar = $pillar
        }
    }

    return @($out)
}

function Build-CoarsePillarIntervals {
    param(
        [object[]]$Samples,
        [int]$SourceW,
        [int]$ScanW,
        [double]$Duration
    )

    $hits = @(
        $Samples |
        Where-Object {
            $_.Pillar
        } |
        Sort-Object T
    )

    if ($hits.Count -eq 0) {
        return @()
    }

    $clusters = @()
    $current = @()

    foreach ($h in $hits) {
        if ($current.Count -eq 0) {
            $current = @($h)
            continue
        }

        $prev =
            $current[-1]

        $gap =
            [double]$h.T -
            [double]$prev.T

        $geomJump =
            100.0 *
            [math]::Abs(
                [double]$h.W -
                [double]$prev.W
            ) /
            $ScanW

        if (
            $gap -le $MaxGapPillarSeg -and
            $geomJump -le 8.0
        ) {
            $current += $h
        }
        else {
            $clusters += ,@($current)
            $current = @($h)
        }
    }

    if ($current.Count -gt 0) {
        $clusters += ,@($current)
    }

    $halfSample =
        0.5 /
        $AmostrasPillarPorSegundo

    $scaleX =
        $SourceW /
        [double]$ScanW

    $out = @()

    foreach ($cRaw in $clusters) {
        $c = @($cRaw)

        if ($c.Count -lt 2) {
            continue
        }

        $start =
            [math]::Max(
                0.0,
                [double]$c[0].T -
                $halfSample
            )

        $end =
            [math]::Min(
                $Duration,
                [double]$c[-1].T +
                $halfSample
            )

        if (
            ($end - $start) -lt
            $DuracaoMinPillarSeg
        ) {
            continue
        }

        $inside = @(
            $Samples |
            Where-Object {
                [double]$_.T -ge $start -and
                [double]$_.T -le $end
            }
        )

        $clusterMedW =
            Median (
                [double[]]@(
                    $c |
                    ForEach-Object {
                        [double]$_.W
                    }
                )
            )

        $compatible =
            @(
                $inside |
                Where-Object {
                    $_.Pillar -and
                    (
                        [math]::Abs(
                            [double]$_.W -
                            $clusterMedW
                        ) -le
                        ($ScanW * 0.08)
                    )
                }
            )

        if ($compatible.Count -eq 0) {
            continue
        }

        $density =
            100.0 *
            $compatible.Count /
            [math]::Max(
                1,
                $inside.Count
            )

        $leftVals =
            [double[]]@(
                $compatible |
                ForEach-Object {
                    [double]$_.Left
                }
            )

        $rightVals =
            [double[]]@(
                $compatible |
                ForEach-Object {
                    [double]$_.Right
                }
            )

        $widthVals =
            [double[]]@(
                $compatible |
                ForEach-Object {
                    [double]$_.W
                }
            )

        $medLeft =
            Median $leftVals

        $medRight =
            Median $rightVals

        $medW =
            Median $widthVals

        $p10W =
            Percentile $widthVals 10

        $p90W =
            Percentile $widthVals 90

        $spread =
            if ($medW -gt 0) {
                100.0 *
                ($p90W - $p10W) /
                $medW
            }
            else {
                999.0
            }

        $aspect =
            if ($compatible[0].H -gt 0) {
                $medW /
                (
                    Median (
                        [double[]]@(
                            $compatible |
                            ForEach-Object {
                                [double]$_.H
                            }
                        )
                    )
                )
            }
            else {
                0.0
            }

        $accepted = (
            ($density -ge 80.0) -and
            ($spread -le 8.0) -and
            ($aspect -ge 0.40) -and
            ($aspect -le 1.60)
        )

        if (-not $accepted) {
            continue
        }

        $p95Left =
            Percentile $leftVals 95

        $p95Right =
            Percentile $rightVals 95

        $cropSide =
            Round-Up-Even (
                (
                    [math]::Max(
                        $p95Left,
                        $p95Right
                    ) *
                    $scaleX
                ) +
                4
            )

        $maxCrop =
            [int][math]::Floor(
                $SourceW * 0.42
            )

        if ($cropSide -gt $maxCrop) {
            $cropSide =
                Round-Up-Even $maxCrop
        }

        $out += [pscustomobject]@{
            InicioSeg = $start
            FimSeg = $end
            Aspecto = $aspect
            CropSidePx = $cropSide
            DensityPct =
                [math]::Round(
                    $density,
                    1
                )
        }
    }

    return @($out)
}

function Invoke-CoarsePillarScan {
    param(
        [string]$VideoId,
        [string]$File,
        [object]$Info,
        [string]$WorkDir
    )

    $json =
        Join-Path `
            $WorkDir `
            "01_PILLAR_COARSE.json"

    $done =
        Join-Path `
            $WorkDir `
            "01_PILLAR_COARSE.done"

    if (
        (-not $Forcar) -and
        (Test-Path -LiteralPath $done) -and
        (Test-Path -LiteralPath $json)
    ) {
        Write-Host `
            "  [2/8] Pillarbox coarse: checkpoint existente." `
            -ForegroundColor DarkGreen

        return (
            Get-Content `
                -LiteralPath $json `
                -Raw |
            ConvertFrom-Json
        )
    }

    # Diagnóstico não deve ampliar fontes pequenas apenas para detectar
    # barras. Um vídeo 320x240 será analisado em ~320x240, não 480x360.
    $scanW =
        [int][math]::Min(
            $LarguraDiagnostico,
            [int]$Info.Width
        )

    $scanW =
        [int](
            [math]::Floor(
                $scanW / 2.0
            ) * 2
        )

    if ($scanW -lt 2) {
        $scanW = 2
    }

    $scanH =
        [int](
            [math]::Round(
                (
                    $scanW *
                    $Info.Height /
                    [double]$Info.Width
                ) / 2.0
            ) * 2
        )

    if ($scanH -lt 2) {
        $scanH = 2
    }

    $metaName =
        "01_cropmeta.txt"

    $meta =
        Join-Path `
            $WorkDir `
            $metaName

    $filter =
        Join-Path `
            $WorkDir `
            "01_crop_filter.txt"

    $entry =
        Get-CpuEntryFilter

    if ($script:DecodeBackend -eq "CUDA") {
        $vf =
            "scale_cuda=${scanW}:${scanH}," +
            "hwdownload,format=nv12," +
            "fps=" +
            (Fmt-Inv $AmostrasPillarPorSegundo) +
            "," +
            "cropdetect=limit=" +
            (Fmt-Inv $LimitePreto) +
            ":round=2:reset=1:skip=0," +
            "metadata=mode=print:file=$metaName"
    }
    elseif ($script:DecodeBackend -eq "QSV") {
        $vf =
            "scale_qsv=w=${scanW}:h=${scanH}," +
            "hwdownload,format=nv12," +
            "fps=" +
            (Fmt-Inv $AmostrasPillarPorSegundo) +
            "," +
            "cropdetect=limit=" +
            (Fmt-Inv $LimitePreto) +
            ":round=2:reset=1:skip=0," +
            "metadata=mode=print:file=$metaName"
    }
    else {
        $vf =
            "scale=${scanW}:${scanH}:flags=fast_bilinear," +
            "fps=" +
            (Fmt-Inv $AmostrasPillarPorSegundo) +
            "," +
            "cropdetect=limit=" +
            (Fmt-Inv $LimitePreto) +
            ":round=2:reset=1:skip=0," +
            "metadata=mode=print:file=$metaName"
    }

    $vf |
        Set-Content `
            -LiteralPath $filter `
            -Encoding ASCII

    Write-Host (
        "  [2/8] Varredura pillarbox: {0} fps analíticos, grade {1}x{2}." -f `
            $AmostrasPillarPorSegundo,
            $scanW,
            $scanH
    ) -ForegroundColor Cyan

    $args = @(
        "-hide_banner",
        "-nostats",
        "-loglevel","warning"
    )

    $args +=
        Get-DecodeArgs

    $args += @(
        "-i",$File,
        "-map","0:v:0",
        "-an",
        "-sn",
        "-dn",
        "-/filter_complex",$filter,
        "-map","0:v:0",
        "-f","null",
        "NUL"
    )

    # O filter acima é simples; para evitar ambiguidades de map,
    # usamos -vf se o arquivo for refeito abaixo.
    $args = @(
        "-hide_banner",
        "-nostats",
        "-loglevel","warning"
    )

    $args +=
        Get-DecodeArgs

    $args += @(
        "-i",$File,
        "-map","0:v:0",
        "-an",
        "-sn",
        "-dn",
        "-vf",$vf,
        "-f","null",
        "NUL"
    )

    $progress =
        Join-Path `
            $WorkDir `
            "01_PILLAR_progress.txt"

    $log =
        Join-Path `
            $WorkDir `
            "01_PILLAR.log"

    Remove-Item `
        -LiteralPath $meta `
        -Force `
        -ErrorAction SilentlyContinue

    $exit =
        Invoke-FfmpegProgress `
            -CommandArgs $args `
            -Stage "PILLAR_SCAN" `
            -VideoId $VideoId `
            -Duration $Info.Duration `
            -ProgressFile $progress `
            -StdErrLog $log `
            -WorkingDirectory $WorkDir

    if ($exit -ne 0) {
        throw (
            "Pillar scan falhou (exit {0}): {1}" -f `
                $exit,
                $log
        )
    }

    $raw =
        Parse-CropMetadata $meta

    $samples =
        Classify-PillarSamples `
            -Raw $raw `
            -ScanW $scanW `
            -ScanH $scanH

    $intervals =
        Build-CoarsePillarIntervals `
            -Samples $samples `
            -SourceW $Info.Width `
            -ScanW $scanW `
            -Duration $Info.Duration

    $result =
        [pscustomobject]@{
            ScanW = $scanW
            ScanH = $scanH
            Count = $intervals.Count
            Intervals = @($intervals)
        }

    $result |
        ConvertTo-Json -Depth 8 |
        Set-Content `
            -LiteralPath $json `
            -Encoding UTF8

    New-Item `
        -ItemType File `
        -Path $done `
        -Force |
        Out-Null

    Write-Host (
        "       Pillarbox persistente localizado em {0} intervalo(s)." -f `
            $result.Count
    ) -ForegroundColor Green

    return $result
}

function Invoke-BoundaryScan {
    param(
        [string]$VideoId,
        [string]$File,
        [object]$Info,
        [object]$Interval,
        [double]$Center,
        [string]$Kind,
        [int]$BoundaryIndex,
        [string]$WorkDir,
        [int]$ScanW,
        [int]$ScanH
    )

    $windowStart =
        [math]::Max(
            0.0,
            $Center -
            $JanelaRefinoSeg
        )

    $windowEnd =
        [math]::Min(
            $Info.Duration,
            $Center +
            $JanelaRefinoSeg
        )

    $windowDur =
        [math]::Max(
            0.2,
            $windowEnd -
            $windowStart
        )

    $metaName =
        "02_boundary_{0:000}_{1}.txt" -f `
            $BoundaryIndex,
            $Kind

    $meta =
        Join-Path `
            $WorkDir `
            $metaName

    Remove-Item `
        -LiteralPath $meta `
        -Force `
        -ErrorAction SilentlyContinue

    if ($script:DecodeBackend -eq "CUDA") {
        $vf =
            "scale_cuda=${ScanW}:${ScanH}," +
            "hwdownload,format=nv12," +
            "setpts=PTS-STARTPTS," +
            "cropdetect=limit=" +
            (Fmt-Inv $LimitePreto) +
            ":round=2:reset=1:skip=0," +
            "metadata=mode=print:file=$metaName"
    }
    elseif ($script:DecodeBackend -eq "QSV") {
        $vf =
            "scale_qsv=w=${ScanW}:h=${ScanH}," +
            "hwdownload,format=nv12," +
            "setpts=PTS-STARTPTS," +
            "cropdetect=limit=" +
            (Fmt-Inv $LimitePreto) +
            ":round=2:reset=1:skip=0," +
            "metadata=mode=print:file=$metaName"
    }
    else {
        $vf =
            "scale=${ScanW}:${ScanH}:flags=fast_bilinear," +
            "setpts=PTS-STARTPTS," +
            "cropdetect=limit=" +
            (Fmt-Inv $LimitePreto) +
            ":round=2:reset=1:skip=0," +
            "metadata=mode=print:file=$metaName"
    }

    $args = @(
        "-hide_banner",
        "-nostats",
        "-loglevel","warning",
        "-ss",(Fmt-Inv $windowStart)
    )

    $args +=
        Get-DecodeArgs

    $args += @(
        "-i",$File,
        "-t",(Fmt-Inv $windowDur),
        "-map","0:v:0",
        "-an",
        "-sn",
        "-dn",
        "-vf",$vf,
        "-f","null",
        "NUL"
    )

    $progress =
        Join-Path `
            $WorkDir `
            ("02_boundary_{0:000}_{1}_progress.txt" -f `
                $BoundaryIndex,
                $Kind)

    $log =
        Join-Path `
            $WorkDir `
            ("02_boundary_{0:000}_{1}.log" -f `
                $BoundaryIndex,
                $Kind)

    $exit =
        Invoke-FfmpegProgress `
            -CommandArgs $args `
            -Stage ("BOUNDARY_" + $Kind) `
            -VideoId $VideoId `
            -Duration $windowDur `
            -ProgressFile $progress `
            -StdErrLog $log `
            -WorkingDirectory $WorkDir

    if ($exit -ne 0) {
        throw (
            "Refino de borda falhou: {0}" -f `
                $log
        )
    }

    return @(
        Parse-CropMetadata `
            -MetadataFile $meta `
            -TimeOffset $windowStart
    )
}

function Test-MatchingPillarGeometry {
    param(
        [object]$Sample,
        [object]$Interval,
        [int]$ScanW,
        [int]$ScanH
    )

    $left =
        [math]::Max(
            0,
            [int]$Sample.X
        )

    $right =
        [math]::Max(
            0,
            $ScanW -
            (
                [int]$Sample.X +
                [int]$Sample.W
            )
        )

    $minBar =
        $ScanW *
        ($BarraMinimaPct / 100.0)

    $heightOk =
        [int]$Sample.H -ge
        ($ScanH * 0.94)

    $asymPct =
        100.0 *
        [math]::Abs(
            $left -
            $right
        ) /
        $ScanW

    $aspect =
        if ([int]$Sample.H -gt 0) {
            [double]$Sample.W /
            [double]$Sample.H
        }
        else {
            0.0
        }

    $expected =
        [double]$Interval.Aspecto

    $tol =
        [math]::Max(
            0.06,
            $expected * 0.08
        )

    return (
        ($left -ge $minBar) -and
        ($right -ge $minBar) -and
        $heightOk -and
        ($asymPct -le 8.0) -and
        (
            [math]::Abs(
                $aspect -
                $expected
            ) -le $tol
        )
    )
}

function Find-ExactStart {
    param(
        [object[]]$Samples,
        [object]$Interval,
        [object]$Info,
        [int]$ScanW,
        [int]$ScanH
    )

    if (
        [double]$Interval.InicioSeg -le
        $JanelaRefinoSeg
    ) {
        $firstSamples =
            @(
                $Samples |
                Sort-Object T |
                Select-Object `
                    -First $FramesConfirmacao
            )

        if (
            $firstSamples.Count -eq
            $FramesConfirmacao
        ) {
            $allMatch = $true

            foreach ($s in $firstSamples) {
                if (
                    -not (
                        Test-MatchingPillarGeometry `
                            -Sample $s `
                            -Interval $Interval `
                            -ScanW $ScanW `
                            -ScanH $ScanH
                    )
                ) {
                    $allMatch = $false
                    break
                }
            }

            if ($allMatch) {
                return [pscustomobject]@{
                    Frame = 0L
                    T = 0.0
                    Status = "FILE_START"
                }
            }
        }
    }

    $srt =
        @(
            $Samples |
            Sort-Object T
        )

    $flags = @()

    foreach ($s in $srt) {
        $flags +=
            [bool](
                Test-MatchingPillarGeometry `
                    -Sample $s `
                    -Interval $Interval `
                    -ScanW $ScanW `
                    -ScanH $ScanH
            )
    }

    for (
        $i = 1;
        $i -le
        ($flags.Count - $FramesConfirmacao);
        $i++
    ) {
        if ($flags[$i - 1]) {
            continue
        }

        $ok = $true

        for (
            $j = 0;
            $j -lt $FramesConfirmacao;
            $j++
        ) {
            if (-not $flags[$i + $j]) {
                $ok = $false
                break
            }
        }

        if ($ok) {
            $t =
                [double]$srt[$i].T

            return [pscustomobject]@{
                Frame =
                    [long][math]::Round(
                        $t *
                        $Info.AvgFps
                    )

                T = $t
                Status = "FRAME_EXATO"
            }
        }
    }

    return $null
}

function Find-ExactEnd {
    param(
        [object[]]$Samples,
        [object]$Interval,
        [object]$Info,
        [int]$ScanW,
        [int]$ScanH
    )

    $srt =
        @(
            $Samples |
            Sort-Object T
        )

    $flags = @()

    foreach ($s in $srt) {
        $flags +=
            [bool](
                Test-MatchingPillarGeometry `
                    -Sample $s `
                    -Interval $Interval `
                    -ScanW $ScanW `
                    -ScanH $ScanH
            )
    }

    for (
        $i = 1;
        $i -le
        ($flags.Count - $FramesConfirmacao);
        $i++
    ) {
        if (-not $flags[$i - 1]) {
            continue
        }

        $ok = $true

        for (
            $j = 0;
            $j -lt $FramesConfirmacao;
            $j++
        ) {
            if ($flags[$i + $j]) {
                $ok = $false
                break
            }
        }

        if ($ok) {
            $t =
                [double]$srt[$i].T

            return [pscustomobject]@{
                Frame =
                    [long][math]::Round(
                        $t *
                        $Info.AvgFps
                    )

                T = $t
                Status = "FRAME_EXATO"
            }
        }
    }

    if (
        [double]$Interval.FimSeg -ge
        (
            $Info.Duration -
            $JanelaRefinoSeg
        )
    ) {
        $tail =
            @(
                $srt |
                Select-Object `
                    -Last $FramesConfirmacao
            )

        if (
            $tail.Count -eq
            $FramesConfirmacao
        ) {
            $allMatch = $true

            foreach ($s in $tail) {
                if (
                    -not (
                        Test-MatchingPillarGeometry `
                            -Sample $s `
                            -Interval $Interval `
                            -ScanW $ScanW `
                            -ScanH $ScanH
                    )
                ) {
                    $allMatch = $false
                    break
                }
            }

            if ($allMatch) {
                return [pscustomobject]@{
                    Frame =
                        [long]$Info.FrameCount

                    T =
                        [double]$Info.Duration

                    Status = "FILE_END"
                }
            }
        }
    }

    return $null
}

function Invoke-ExactPillarRefine {
    param(
        [string]$VideoId,
        [string]$File,
        [object]$Info,
        [object]$Coarse,
        [string]$WorkDir
    )

    $json =
        Join-Path `
            $WorkDir `
            "02_PILLAR_EXATO.json"

    $csv =
        Join-Path `
            $WorkDir `
            "02_PILLAR_EXATO.csv"

    $done =
        Join-Path `
            $WorkDir `
            "02_PILLAR_EXATO.done"

    if (
        (-not $Forcar) -and
        (Test-Path -LiteralPath $done) -and
        (Test-Path -LiteralPath $json)
    ) {
        Write-Host `
            "  [3/8] Refino frame-exato: checkpoint existente." `
            -ForegroundColor DarkGreen

        return (
            Get-Content `
                -LiteralPath $json `
                -Raw |
            ConvertFrom-Json
        )
    }

    if ([int]$Coarse.Count -eq 0) {
        $empty =
            [pscustomobject]@{
                Count = 0
                Review = 0
                Intervals = @()
            }

        $empty |
            ConvertTo-Json -Depth 8 |
            Set-Content `
                -LiteralPath $json `
                -Encoding UTF8

        "" |
            Set-Content `
                -LiteralPath $csv `
                -Encoding UTF8

        New-Item `
            -ItemType File `
            -Path $done `
            -Force |
            Out-Null

        Write-Host `
            "  [3/8] Nenhum pillarbox baked-in para refinar." `
            -ForegroundColor Green

        return $empty
    }

    Write-Host (
        "  [3/8] Refinando {0} intervalo(s) nas bordas, em todos os frames nativos ({1:N3} fps)." -f `
            $Coarse.Count,
            $Info.AvgFps
    ) -ForegroundColor Cyan

    $out = @()
    $idx = 0

    foreach ($iv in @($Coarse.Intervals)) {
        $idx++

        Write-Host (
            "       Intervalo {0}/{1}: coarse {2} -> {3} | crop aprox. {4}px/lado" -f `
                $idx,
                $Coarse.Count,
                (To-Timecode $iv.InicioSeg),
                (To-Timecode $iv.FimSeg),
                $iv.CropSidePx
        )

        $startSamples =
            Invoke-BoundaryScan `
                -VideoId $VideoId `
                -File $File `
                -Info $Info `
                -Interval $iv `
                -Center ([double]$iv.InicioSeg) `
                -Kind "START" `
                -BoundaryIndex $idx `
                -WorkDir $WorkDir `
                -ScanW $Coarse.ScanW `
                -ScanH $Coarse.ScanH

        $endSamples =
            Invoke-BoundaryScan `
                -VideoId $VideoId `
                -File $File `
                -Info $Info `
                -Interval $iv `
                -Center ([double]$iv.FimSeg) `
                -Kind "END" `
                -BoundaryIndex $idx `
                -WorkDir $WorkDir `
                -ScanW $Coarse.ScanW `
                -ScanH $Coarse.ScanH

        $start =
            Find-ExactStart `
                -Samples $startSamples `
                -Interval $iv `
                -Info $Info `
                -ScanW $Coarse.ScanW `
                -ScanH $Coarse.ScanH

        $end =
            Find-ExactEnd `
                -Samples $endSamples `
                -Interval $iv `
                -Info $Info `
                -ScanW $Coarse.ScanW `
                -ScanH $Coarse.ScanH

        $apply = $false
        $status = "REVISAR_BORDA"

        $startFrame = $null
        $endFrame = $null

        if ($start -and $end) {
            $startFrame =
                [long]$start.Frame

            $endFrame =
                [long]$end.Frame

            if (
                $startFrame -ge 0 -and
                $endFrame -gt $startFrame -and
                $endFrame -le $Info.FrameCount
            ) {
                $allowedStart =
                    @(
                        "FRAME_EXATO",
                        "FILE_START"
                    ) -contains
                    $start.Status

                $allowedEnd =
                    @(
                        "FRAME_EXATO",
                        "FILE_END"
                    ) -contains
                    $end.Status

                if (
                    $allowedStart -and
                    $allowedEnd
                ) {
                    $apply = $true

                    $status =
                        "$($start.Status)/$($end.Status)"
                }
            }
        }

        $out += [pscustomobject]@{
            Index = $idx
            StartFrame = $startFrame
            EndFrame = $endFrame
            LastPillarFrame =
                if ($null -ne $endFrame) {
                    [long]$endFrame - 1
                }
                else {
                    $null
                }
            StartSec =
                if ($null -ne $startFrame) {
                    [double]$startFrame /
                    $Info.AvgFps
                }
                else {
                    [double]$iv.InicioSeg
                }
            EndSec =
                if ($null -ne $endFrame) {
                    [double]$endFrame /
                    $Info.AvgFps
                }
                else {
                    [double]$iv.FimSeg
                }
            CropSidePx =
                [int]$iv.CropSidePx
            Aspecto =
                [double]$iv.Aspecto
            Apply = $apply
            Status = $status
        }
    }

    $sorted =
        @(
            $out |
            Sort-Object StartFrame
        )

    for (
        $i = 1;
        $i -lt $sorted.Count;
        $i++
    ) {
        $a =
            $sorted[$i - 1]

        $b =
            $sorted[$i]

        if (
            $a.Apply -and
            $b.Apply -and
            [long]$b.StartFrame -lt
            [long]$a.EndFrame
        ) {
            $a.Apply = $false
            $b.Apply = $false

            $a.Status =
                "REVISAR_SOBREPOSICAO"

            $b.Status =
                "REVISAR_SOBREPOSICAO"
        }
    }

    $sorted |
        Select-Object `
            Index,
            StartFrame,
            EndFrame,
            LastPillarFrame,
            StartSec,
            EndSec,
            CropSidePx,
            Aspecto,
            Apply,
            Status |
        Export-Csv `
            -LiteralPath $csv `
            -NoTypeInformation `
            -Encoding UTF8 `
            -Delimiter ";"

    $result =
        [pscustomobject]@{
            Count =
                @(
                    $sorted |
                    Where-Object {
                        $_.Apply
                    }
                ).Count

            Review =
                @(
                    $sorted |
                    Where-Object {
                        -not $_.Apply
                    }
                ).Count

            Intervals =
                @($sorted)
        }

    $result |
        ConvertTo-Json -Depth 8 |
        Set-Content `
            -LiteralPath $json `
            -Encoding UTF8

    New-Item `
        -ItemType File `
        -Path $done `
        -Force |
        Out-Null

    Write-Host (
        "       Refino concluído: {0} intervalo(s) frame-exatos; {1} para revisão." -f `
            $result.Count,
            $result.Review
    ) -ForegroundColor Green

    foreach (
        $iv in @(
            $result.Intervals |
            Where-Object {
                $_.Apply
            }
        )
    ) {
        Write-Host (
            "       frames {0}-{1} | {2} -> {3} | crop {4}px" -f `
                $iv.StartFrame,
                $iv.LastPillarFrame,
                (To-Timecode $iv.StartSec),
                (To-Timecode $iv.EndSec),
                $iv.CropSidePx
        ) -ForegroundColor DarkGreen
    }

    return $result
}

# =====================================================================
# 06 - PLANO DE SEGMENTOS
# =====================================================================

function Build-SegmentPlan {
    param(
        [object]$Exact,
        [object]$Info
    )

    $pillars =
        @(
            $Exact.Intervals |
            Where-Object {
                $_.Apply
            } |
            Sort-Object StartFrame
        )

    $segments = @()
    $cursor = 0L
    $index = 0

    foreach ($iv in $pillars) {
        $start =
            [long]$iv.StartFrame

        $end =
            [long]$iv.EndFrame

        if ($start -gt $cursor) {
            $index++

            $segments += [pscustomobject]@{
                Index = $index
                Type = "NORMAL"
                StartFrame = $cursor
                EndFrame = $start
                FrameCount =
                    $start -
                    $cursor
                CropSidePx = 0
            }
        }

        if ($end -gt $start) {
            $index++

            $segments += [pscustomobject]@{
                Index = $index
                Type = "PILLAR"
                StartFrame = $start
                EndFrame = $end
                FrameCount =
                    $end -
                    $start
                CropSidePx =
                    [int]$iv.CropSidePx
            }
        }

        $cursor =
            [math]::Max(
                $cursor,
                $end
            )
    }

    if ($cursor -lt $Info.FrameCount) {
        $index++

        $segments += [pscustomobject]@{
            Index = $index
            Type = "NORMAL"
            StartFrame = $cursor
            EndFrame =
                [long]$Info.FrameCount
            FrameCount =
                [long]$Info.FrameCount -
                $cursor
            CropSidePx = 0
        }
    }

    if ($segments.Count -eq 0) {
        $segments += [pscustomobject]@{
            Index = 1
            Type = "NORMAL"
            StartFrame = 0L
            EndFrame =
                [long]$Info.FrameCount
            FrameCount =
                [long]$Info.FrameCount
            CropSidePx = 0
        }
    }

    return @(
        $segments |
        Where-Object {
            [long]$_.FrameCount -gt 0
        }
    )
}

# =====================================================================
# 07 - ESTABILIZAÇÃO / RENDER 1080P
# =====================================================================

function Get-SegmentFrameCount {
    param([string]$File)

    $text =
        & $script:FfprobeExe `
            -v error `
            -select_streams v:0 `
            -show_entries `
                stream=nb_frames `
            -of `
                default=nokey=1:noprint_wrappers=1 `
            "$File" `
            2>$null |
        Select-Object -First 1

    $count = 0L

    [void][long]::TryParse(
        [string]$text,
        [ref]$count
    )

    return $count
}


function Get-ExactDecodedFrameCount {
    param(
        [string]$VideoId,
        [string]$File,
        [object]$Info,
        [string]$WorkDir
    )

    $countFile =
        Join-Path `
            $WorkDir `
            "00_FRAMECOUNT_EXATO.txt"

    $doneFile =
        Join-Path `
            $WorkDir `
            "00_FRAMECOUNT_EXATO.done"

    if (
        (-not $Forcar) -and
        (Test-Path -LiteralPath $doneFile) -and
        (Test-Path -LiteralPath $countFile)
    ) {
        $cachedText =
            Get-Content `
                -LiteralPath $countFile `
                -Raw `
                -ErrorAction SilentlyContinue

        $cached = 0L

        if (
            [long]::TryParse(
                ([string]$cachedText).Trim(),
                [ref]$cached
            ) -and
            $cached -gt 0
        ) {
            Write-Host (
                "       Frame census: checkpoint exato = {0} frames." -f `
                    $cached
            ) -ForegroundColor DarkGreen

            return $cached
        }
    }

    Write-Host (
        "       Contando frames efetivamente decodificados com ffprobe -count_frames..."
    ) -ForegroundColor DarkCyan

    $countText =
        & $script:FfprobeExe `
            -v error `
            -select_streams v:0 `
            -count_frames `
            -show_entries `
                stream=nb_read_frames `
            -of `
                default=nokey=1:noprint_wrappers=1 `
            "$File" `
            2> (
                Join-Path `
                    $WorkDir `
                    "00_FRAMECOUNT_EXATO.log"
            ) |
        Select-Object -First 1

    $count = 0L

    $ok =
        [long]::TryParse(
            ([string]$countText).Trim(),
            [ref]$count
        )

    if (
        -not $ok -or
        $count -le 0
    ) {
        Write-Host (
            "       AVISO: ffprobe -count_frames não retornou contagem utilizável."
        ) -ForegroundColor Yellow

        Write-Host (
            "       Fallback: usando frame count informado/estimado pela fonte = {0}." -f `
                $Info.FrameCount
        ) -ForegroundColor Yellow

        return [long]$Info.FrameCount
    }

    [string]$count |
        Set-Content `
            -LiteralPath $countFile `
            -Encoding ASCII

    New-Item `
        -ItemType File `
        -Path $doneFile `
        -Force |
        Out-Null

    if (
        [long]$Info.FrameCount -ne
        $count
    ) {
        Write-Host (
            "       CORREÇÃO DE TIMELINE: metadado indicava {0} frames; decoder contou {1}." -f `
                $Info.FrameCount,
                $count
        ) -ForegroundColor Yellow
    }
    else {
        Write-Host (
            "       Frame census confirmado: {0} frames." -f `
                $count
        ) -ForegroundColor Green
    }

    return $count
}

function Invoke-StabilizationDetect {
    param(
        [string]$VideoId,
        [string]$File,
        [object]$Info,
        [object]$Segment,
        [string]$SegmentDir
    )

    if ($SemEstabilizacao) {
        return ""
    }

    $minFrames =
        [long][math]::Max(
            15,
            [math]::Round(
                $Info.AvgFps * 0.5
            )
        )

    if (
        [long]$Segment.FrameCount -lt
        $minFrames
    ) {
        Write-Host `
            "       Estabilização omitida: segmento muito curto." `
            -ForegroundColor DarkYellow

        return ""
    }

    $trfName =
        "{0:000}.trf" -f
        $Segment.Index

    $trf =
        Join-Path `
            $SegmentDir `
            $trfName

    $done =
        Join-Path `
            $SegmentDir `
            ("{0:000}_STAB_DETECT.done" -f `
                $Segment.Index)

    if (
        (-not $Forcar) -and
        (Test-Path -LiteralPath $done) -and
        (Test-Path -LiteralPath $trf)
    ) {
        return $trfName
    }

    $start =
        [double]$Segment.StartFrame /
        $Info.AvgFps

    $entry =
        Get-CpuEntryFilter

    $crop =
        if (
            $Segment.Type -eq "PILLAR" -and
            $Segment.CropSidePx -gt 0
        ) {
            $cw =
                $Info.Width -
                (2 * $Segment.CropSidePx)

            ",crop=${cw}:$($Info.Height):$($Segment.CropSidePx):0"
        }
        else {
            ""
        }

    $vf =
        $entry +
        $crop +
        ",vidstabdetect=" +
        "shakiness=5:" +
        "accuracy=12:" +
        "stepsize=6:" +
        "mincontrast=0.20:" +
        "result=$trfName"

    $args = @(
        "-hide_banner",
        "-nostats",
        "-loglevel","warning",
        "-ss",(Fmt-Inv $start)
    )

    $args +=
        Get-DecodeArgs

    $args += @(
        "-i",$File,
        "-frames:v",
            ([string][long]$Segment.FrameCount),
        "-an",
        "-vf",$vf,
        "-f","null",
        "NUL"
    )

    $progress =
        Join-Path `
            $SegmentDir `
            ("{0:000}_STAB_progress.txt" -f `
                $Segment.Index)

    $log =
        Join-Path `
            $SegmentDir `
            ("{0:000}_STAB.log" -f `
                $Segment.Index)

    $duration =
        [double]$Segment.FrameCount /
        $Info.AvgFps

    $exit =
        Invoke-FfmpegProgress `
            -CommandArgs $args `
            -Stage (
                "STAB_DETECT_{0:000}" -f
                $Segment.Index
            ) `
            -VideoId $VideoId `
            -Duration $duration `
            -ProgressFile $progress `
            -StdErrLog $log `
            -WorkingDirectory $SegmentDir

    if ($exit -ne 0) {
        throw (
            "vidstabdetect segmento {0} falhou: {1}" -f `
                $Segment.Index,
                $log
        )
    }

    New-Item `
        -ItemType File `
        -Path $done `
        -Force |
        Out-Null

    return $trfName
}

function Build-RenderFilter {
    param(
        [object]$Info,
        [object]$Segment,
        [string]$TrfName,
        [string]$FilterFile
    )

    $entry =
        Get-CpuEntryFilter

    $parts = @($entry)

    if (
        $Segment.Type -eq "PILLAR" -and
        $Segment.CropSidePx -gt 0
    ) {
        $cw =
            $Info.Width -
            (2 * $Segment.CropSidePx)

        $parts +=
            "crop=${cw}:$($Info.Height):$($Segment.CropSidePx):0"
    }

    if (
        -not $SemEstabilizacao -and
        -not [string]::IsNullOrWhiteSpace(
            $TrfName
        )
    ) {
        $parts += (
            "vidstabtransform=" +
            "input=${TrfName}:" +
            "smoothing=${SmoothingEstabilizacao}:" +
            "maxshift=12:" +
            "maxangle=0.015:" +
            "crop=black:" +
            "optzoom=1:" +
            "interpol=bilinear"
        )
    }

    $prefix =
        ($parts -join ",")

    $blurW =
        Round-Up-Even $BlurBaseWidth

    $blurH =
        Round-Up-Even (
            $blurW *
            1080.0 /
            1920.0
        )

    $graph =
        "[0:v]" +
        $prefix +
        ",setsar=1,split=2[fgsrc][bgsrc];" +
        "[fgsrc]" +
        "scale=1920:1080:" +
        "force_original_aspect_ratio=decrease:" +
        "flags=lanczos," +
        "unsharp=5:5:0.20:3:3:0.0[fg];" +
        "[bgsrc]" +
        "scale=${blurW}:${blurH}:" +
        "force_original_aspect_ratio=increase:" +
        "flags=fast_bilinear," +
        "crop=${blurW}:${blurH}," +
        "gblur=sigma=${BlurSigma}:steps=2," +
        "eq=brightness=-0.06:saturation=0.85," +
        "scale=1920:1080:flags=bilinear[bg];" +
        "[bg][fg]" +
        "overlay=(W-w)/2:(H-h)/2:" +
        "shortest=0:" +
        "eof_action=repeat:" +
        "repeatlast=1," +
        "format=yuv420p[vout]"

    $graph |
        Set-Content `
            -LiteralPath $FilterFile `
            -Encoding ASCII
}

function Render-Segments {
    param(
        [string]$VideoId,
        [string]$File,
        [object]$Info,
        [object[]]$Segments,
        [string]$WorkDir
    )

    $segDir =
        Join-Path `
            $WorkDir `
            "SEGMENTOS"

    New-Item `
        -ItemType Directory `
        -Path $segDir `
        -Force |
        Out-Null

    $enc =
        Get-EncodeSettings $Info

    $rows = @()

    foreach ($seg in $Segments) {
        $n =
            [int]$seg.Index

        $out =
            Join-Path `
                $segDir `
                (
                    "{0:000}_{1}_{2}_{3}.mp4" -f `
                        $n,
                        $seg.Type,
                        $seg.StartFrame,
                        $seg.EndFrame
                )

        $done =
            Join-Path `
                $segDir `
                ("{0:000}_RENDER.done" -f $n)

        if (
            (-not $Forcar) -and
            (Test-Path -LiteralPath $done) -and
            (Test-Path -LiteralPath $out)
        ) {
            $fc =
                Get-SegmentFrameCount $out

            if (
                $fc -eq
                [long]$seg.FrameCount
            ) {
                Write-Host (
                    "       Segmento {0:000}: checkpoint render OK ({1} frames)." -f `
                        $n,
                        $fc
                ) -ForegroundColor DarkGreen

                $rows += [pscustomobject]@{
                    Index = $n
                    Type = $seg.Type
                    StartFrame =
                        $seg.StartFrame
                    EndFrame =
                        $seg.EndFrame
                    FrameCount =
                        $seg.FrameCount
                    CropSidePx =
                        $seg.CropSidePx
                    File = $out
                }

                continue
            }
        }

        Write-Host (
            "       Segmento {0:000}/{1:000}: {2} | frames {3}-{4} | {5}" -f `
                $n,
                $Segments.Count,
                $seg.Type,
                $seg.StartFrame,
                ($seg.EndFrame - 1),
                (
                    To-ShortTime (
                        [double]$seg.FrameCount /
                        $Info.AvgFps
                    )
                )
        ) -ForegroundColor Cyan

        $trfName =
            Invoke-StabilizationDetect `
                -VideoId $VideoId `
                -File $File `
                -Info $Info `
                -Segment $seg `
                -SegmentDir $segDir

        $filter =
            Join-Path `
                $segDir `
                ("{0:000}_RENDER_FILTER.txt" -f $n)

        Build-RenderFilter `
            -Info $Info `
            -Segment $seg `
            -TrfName $trfName `
            -FilterFile $filter

        $start =
            [double]$seg.StartFrame /
            $Info.AvgFps

        $duration =
            [double]$seg.FrameCount /
            $Info.AvgFps

        $args = @(
            "-hide_banner",
            "-nostats",
            "-loglevel","warning",
            "-ss",(Fmt-Inv $start)
        )

        $args +=
            Get-DecodeArgs

        $args += @(
            "-i",$File,
            "-/filter_complex",$filter,
            "-map","[vout]",
            "-frames:v",
                ([string][long]$seg.FrameCount),
            "-an",
            "-sn",
            "-dn"
        )

        $args +=
            Get-EncoderArgs $enc

        $args += @(
            "-fps_mode","passthrough",
            "-movflags","+faststart",
            "-y",$out
        )

        $progress =
            Join-Path `
                $segDir `
                ("{0:000}_RENDER_progress.txt" -f $n)

        $log =
            Join-Path `
                $segDir `
                ("{0:000}_RENDER.log" -f $n)

        $exit =
            Invoke-FfmpegProgress `
                -CommandArgs $args `
                -Stage (
                    "RENDER_{0:000}" -f $n
                ) `
                -VideoId $VideoId `
                -Duration $duration `
                -ProgressFile $progress `
                -StdErrLog $log `
                -WorkingDirectory $segDir `
                -ExpectedOutput $out

        if ($exit -ne 0) {
            throw (
                "Render segmento {0} falhou (exit {1}): {2}" -f `
                    $n,
                    $exit,
                    $log
            )
        }

        $fc =
            Get-SegmentFrameCount $out

        if (
            $fc -ne
            [long]$seg.FrameCount
        ) {
            $decodedOutText =
                & $script:FfprobeExe `
                    -v error `
                    -select_streams v:0 `
                    -count_frames `
                    -show_entries `
                        stream=nb_read_frames `
                    -of `
                        default=nokey=1:noprint_wrappers=1 `
                    "$out" `
                    2>$null |
                Select-Object -First 1

            $decodedOut = 0L

            [void][long]::TryParse(
                ([string]$decodedOutText).Trim(),
                [ref]$decodedOut
            )

            throw (
                "Segmento {0}: esperado {1} frames; nb_frames={2}; decoded_frames={3}. A V1.4 não aceita diferença silenciosa." -f `
                    $n,
                    $seg.FrameCount,
                    $fc,
                    $decodedOut
            )
        }

        New-Item `
            -ItemType File `
            -Path $done `
            -Force |
            Out-Null

        $rows += [pscustomobject]@{
            Index = $n
            Type = $seg.Type
            StartFrame =
                $seg.StartFrame
            EndFrame =
                $seg.EndFrame
            FrameCount =
                $seg.FrameCount
            CropSidePx =
                $seg.CropSidePx
            File = $out
        }
    }

    $rows |
        Export-Csv `
            -LiteralPath (
                Join-Path `
                    $WorkDir `
                    "04_SEGMENTOS.csv"
            ) `
            -NoTypeInformation `
            -Encoding UTF8 `
            -Delimiter ";"

    return @($rows)
}

# =====================================================================
# 08 - CONCAT VIDEO
# =====================================================================

function Write-ConcatList {
    param(
        [object[]]$Rows,
        [string]$File
    )

    $listDir =
        Split-Path `
            -Parent $File

    $lines = @()

    foreach ($r in $Rows) {
        $absolute =
            [IO.Path]::GetFullPath(
                [string]$r.File
            )

        $relative =
            [IO.Path]::GetRelativePath(
                $listDir,
                $absolute
            )

        $relative =
            $relative.Replace("\","/")

        if (
            [IO.Path]::IsPathRooted($relative) -or
            $relative -eq ".." -or
            $relative.StartsWith("../")
        ) {
            throw (
                "Segmento fora da árvore de concat: {0}" -f `
                    $absolute
            )
        }

        if ($relative -match '[^\x00-\x7F]') {
            throw (
                "Nome relativo de segmento contém Unicode inesperado: {0}" -f `
                    $relative
            )
        }

        $relative =
            $relative.Replace("'","'\''")

        $lines +=
            "file '$relative'"
    }

    $lines |
        Set-Content `
            -LiteralPath $File `
            -Encoding ASCII
}

function Concat-Video {
    param(
        [string]$VideoId,
        [object[]]$Rows,
        [object]$Info,
        [string]$WorkDir
    )

    $out =
        Join-Path `
            $WorkDir `
            "05_VIDEO_CONCAT.mp4"

    $done =
        Join-Path `
            $WorkDir `
            "05_VIDEO_CONCAT.done"

    if (
        (-not $Forcar) -and
        (Test-Path -LiteralPath $done) -and
        (Test-Path -LiteralPath $out)
    ) {
        return $out
    }

    $list =
        Join-Path `
            $WorkDir `
            "05_concat.txt"

    Write-ConcatList `
        -Rows $Rows `
        -File $list

    Write-Host `
        "  [6/8] Remontando os segmentos de vídeo por stream-copy." `
        -ForegroundColor Cyan

    $log =
        Join-Path `
            $WorkDir `
            "05_CONCAT.log"

    & $script:FfmpegExe `
        -hide_banner `
        -loglevel warning `
        -f concat `
        -safe 0 `
        -i "$list" `
        -map 0:v:0 `
        -an `
        -c:v copy `
        -movflags +faststart `
        -y "$out" `
        2> $log |
        Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "Concat falhou: $log"
    }

    $fc =
        Get-SegmentFrameCount $out

    if (
        $fc -ne
        [long]$Info.FrameCount
    ) {
        throw (
            "Concat alterou frame count: esperado {0}; obtido {1}." -f `
                $Info.FrameCount,
                $fc
        )
    }

    New-Item `
        -ItemType File `
        -Path $done `
        -Force |
        Out-Null

    return $out
}

# =====================================================================
# 09 - ÁUDIO
# =====================================================================

function Extract-LoudnormJson {
    param([string]$LogFile)

    if (
        -not (
            Test-Path `
                -LiteralPath $LogFile
        )
    ) {
        return $null
    }

    $text =
        Get-Content `
            -LiteralPath $LogFile `
            -Raw

    $matches =
        [regex]::Matches(
            $text,
            '\{[\s\S]*?"input_i"[\s\S]*?"target_offset"[\s\S]*?\}'
        )

    if ($matches.Count -eq 0) {
        return $null
    }

    $jsonText =
        $matches[
            $matches.Count - 1
        ].Value

    try {
        return (
            $jsonText |
            ConvertFrom-Json
        )
    }
    catch {
        return $null
    }
}

function Process-Audio {
    param(
        [string]$VideoId,
        [string]$File,
        [object]$Info,
        [string]$WorkDir
    )

    if (-not $Info.HasAudio) {
        Write-Host `
            "  [7/8] Fonte sem áudio. Etapa de áudio ignorada." `
            -ForegroundColor Yellow

        return ""
    }

    $out =
        Join-Path `
            $WorkDir `
            "06_AUDIO_PROCESSADO.m4a"

    $done =
        Join-Path `
            $WorkDir `
            "06_AUDIO_PROCESSADO.done"

    if (
        (-not $Forcar) -and
        (Test-Path -LiteralPath $done) -and
        (Test-Path -LiteralPath $out)
    ) {
        Write-Host `
            "  [7/8] Áudio: checkpoint existente." `
            -ForegroundColor DarkGreen

        return $out
    }

    Write-Host `
        "  [7/8] Áudio: medindo loudness completo antes da correção." `
        -ForegroundColor Cyan

    $measureLog =
        Join-Path `
            $WorkDir `
            "06_AUDIO_LOUDNORM_MEDICAO.log"

    $noise =
        if ($SemReducaoRuidoAudio) {
            ""
        }
        else {
            "afftdn=nr=4:nf=-55:tn=1:gs=8,"
        }

    $measureFilter =
        $noise +
        "loudnorm=" +
        "I=-16:" +
        "LRA=12:" +
        "TP=-1.5:" +
        "print_format=json"

    & $script:FfmpegExe `
        -hide_banner `
        -nostats `
        -i "$File" `
        -map "0:a:0" `
        -vn `
        -af "$measureFilter" `
        -f null `
        NUL `
        2> $measureLog |
        Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw (
            "Medição loudnorm falhou: {0}" -f `
                $measureLog
        )
    }

    $m =
        Extract-LoudnormJson `
            $measureLog

    if (-not $m) {
        throw (
            "Não foi possível extrair JSON loudnorm: {0}" -f `
                $measureLog
        )
    }

    $inputI =
        [string]$m.input_i

    $inputLra =
        [string]$m.input_lra

    $inputTp =
        [string]$m.input_tp

    $inputThresh =
        [string]$m.input_thresh

    $offset =
        [string]$m.target_offset

    Write-Host (
        "       Medição: I {0} LUFS | LRA {1} | TP {2} dBTP | offset {3}" -f `
            $inputI,
            $inputLra,
            $inputTp,
            $offset
    )

    $finalFilter =
        $noise +
        "loudnorm=" +
        "I=-16:" +
        "LRA=12:" +
        "TP=-1.5:" +
        "measured_I=${inputI}:" +
        "measured_LRA=${inputLra}:" +
        "measured_TP=${inputTp}:" +
        "measured_thresh=${inputThresh}:" +
        "offset=${offset}:" +
        "linear=true:" +
        "print_format=summary"

    $audioBitrate =
        if ($Info.AudioChannels -gt 2) {
            "384k"
        }
        else {
            "192k"
        }

    $progress =
        Join-Path `
            $WorkDir `
            "06_AUDIO_progress.txt"

    $log =
        Join-Path `
            $WorkDir `
            "06_AUDIO_PROCESSADO.log"

    $args = @(
        "-hide_banner",
        "-nostats",
        "-loglevel","warning",
        "-i",$File,
        "-map","0:a:0",
        "-vn",
        "-af",$finalFilter,
        "-c:a","aac",
        "-b:a",$audioBitrate,
        "-ar","48000",
        "-y",$out
    )

    $exit =
        Invoke-FfmpegProgress `
            -CommandArgs $args `
            -Stage "AUDIO_FINAL" `
            -VideoId $VideoId `
            -Duration $Info.Duration `
            -ProgressFile $progress `
            -StdErrLog $log `
            -WorkingDirectory $WorkDir `
            -ExpectedOutput $out

    if ($exit -ne 0) {
        throw (
            "Processamento de áudio falhou (exit {0}): {1}" -f `
                $exit,
                $log
        )
    }

    New-Item `
        -ItemType File `
        -Path $done `
        -Force |
        Out-Null

    return $out
}

# =====================================================================
# 10 - MUX / VERIFICAÇÃO
# =====================================================================

function Mux-Final {
    param(
        [string]$VideoId,
        [string]$VideoOnly,
        [string]$AudioFile,
        [string]$OriginalFile,
        [object]$Info,
        [object]$DateInfo,
        [string]$FinalFile,
        [string]$WorkDir
    )

    $done =
        Join-Path `
            $WorkDir `
            "07_FINAL.done"

    $metadataDone =
        Join-Path `
            $WorkDir `
            "07_METADATA_ARCHIVE_V163.done"

    if (
        (-not $Forcar) -and
        (Test-Path -LiteralPath $done) -and
        (Test-Path -LiteralPath $metadataDone) -and
        (Test-Path -LiteralPath $FinalFile)
    ) {
        return $FinalFile
    }

    $finalDir =
        Split-Path `
            -Parent $FinalFile

    New-Item `
        -ItemType Directory `
        -Path $finalDir `
        -Force |
        Out-Null

    Remove-Item `
        -LiteralPath $FinalFile `
        -Force `
        -ErrorAction SilentlyContinue

    Write-Host `
        "  [8/8] Mux final + metadados arquivísticos + faststart." `
        -ForegroundColor Cyan

    Write-Host `
        "       Vídeo é autoritativo no mux; sem -shortest." `
        -ForegroundColor DarkCyan

    if (
        $null -ne $DateInfo -and
        $DateInfo.HasCanonicalDate
    ) {
        Write-Host (
            "       Data Original Canônica: {0} | fonte {1} | confiança {2}." -f `
                $DateInfo.CanonicalDisplay,
                $DateInfo.Source,
                $DateInfo.Confidence
        ) -ForegroundColor Green
    }
    elseif ($null -ne $DateInfo) {
        Write-Host (
            "       Data Original Canônica não definida: {0}" -f `
                $DateInfo.Status
        ) -ForegroundColor DarkYellow

        if (
            -not [string]::IsNullOrWhiteSpace(
                [string]$DateInfo.Warning
            )
        ) {
            Write-Host (
                "       {0}" -f `
                    $DateInfo.Warning
            ) -ForegroundColor DarkYellow
        }
    }

    $log =
        Join-Path `
            $WorkDir `
            "07_MUX_FINAL.log"

    $restorationUtc =
        (Get-Date).ToUniversalTime()

    $metaArgs =
        Get-ArchiveMetadataArgs `
            -DateInfo $DateInfo `
            -RestorationTimeUtc $restorationUtc

    $args =
        @(
            "-hide_banner",
            "-loglevel","warning",
            "-i",$VideoOnly
        )

    if (
        -not [string]::IsNullOrWhiteSpace(
            $AudioFile
        )
    ) {
        $args += @(
            "-i",$AudioFile,
            "-i",$OriginalFile,
            "-map","0:v:0",
            "-map","1:a:0",
            "-c:v","copy",
            "-c:a","copy",
            "-map_metadata","2",
            "-map_chapters","2"
        )
    }
    else {
        $args += @(
            "-i",$OriginalFile,
            "-map","0:v:0",
            "-c:v","copy",
            "-an",
            "-map_metadata","1",
            "-map_chapters","1"
        )
    }

    $args += $metaArgs

    $args += @(
        "-movflags","+faststart+use_metadata_tags",
        "-y",$FinalFile
    )

    & $script:FfmpegExe @args `
        2> $log |
        Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw (
            "Mux final falhou: {0}" -f `
                $log
        )
    }

    $finalInfo =
        Get-MediaInfo $FinalFile

    if (-not $finalInfo) {
        throw "ffprobe não conseguiu ler o master final."
    }

    if (
        $finalInfo.Width -ne 1920 -or
        $finalInfo.Height -ne 1080
    ) {
        throw (
            "Master final não é 1920x1080: {0}x{1}" -f `
                $finalInfo.Width,
                $finalInfo.Height
        )
    }

    if (
        $finalInfo.FrameCount -ne
        $Info.FrameCount
    ) {
        throw (
            "Frame count final divergente: esperado {0}; obtido {1}." -f `
                $Info.FrameCount,
                $finalInfo.FrameCount
        )
    }

    if (
        -not (
            Test-ArchiveMetadata `
                -File $FinalFile `
                -DateInfo $DateInfo
        )
    ) {
        throw (
            "Metadados arquivísticos não passaram na validação pós-mux."
        )
    }

    $smokeLog =
        Join-Path `
            $WorkDir `
            "07_SMOKE_DECODE.log"

    $positions = @(
        1.0,
        [math]::Max(
            1.0,
            $finalInfo.Duration / 2.0
        ),
        [math]::Max(
            0.0,
            $finalInfo.Duration - 4.0
        )
    )

    foreach ($pos in $positions) {
        & $script:FfmpegExe `
            -hide_banner `
            -loglevel error `
            -xerror `
            -ss (Fmt-Inv $pos) `
            -i "$FinalFile" `
            -t 2 `
            -map 0:v:0 `
            -an `
            -f null `
            NUL `
            2>> $smokeLog |
            Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw (
                "Smoke decode falhou em {0}: {1}" -f `
                    (To-Timecode $pos),
                    $smokeLog
            )
        }
    }

    Set-ArchiveFilesystemTimes `
        -FinalFile $FinalFile `
        -DateInfo $DateInfo

    New-Item `
        -ItemType File `
        -Path $done `
        -Force |
        Out-Null

    New-Item `
        -ItemType File `
        -Path $metadataDone `
        -Force |
        Out-Null

    return $FinalFile
}

# =====================================================================
# 11 - ENTRADA INTERATIVA
# =====================================================================

Write-Host ""
Write-Host "============================================================" `
    -ForegroundColor Cyan
Write-Host " RESTAURADOR UNIVERSAL DE VIDEOS V1.6.3 - SMART DUAL GPU / ARCHIVE DATE METADATA / 1080P / STAB / PILLAR BLUR" `
    -ForegroundColor Cyan
Write-Host "============================================================" `
    -ForegroundColor Cyan
Write-Host ""

if (
    [string]::IsNullOrWhiteSpace(
        $PastaRaiz
    )
) {
    $PastaRaiz =
        Read-Host `
            "Pasta raiz a analisar [Enter = pasta atual]"

    if (
        [string]::IsNullOrWhiteSpace(
            $PastaRaiz
        )
    ) {
        $PastaRaiz = "."
    }
}

if (
    -not (
        Test-Path `
            -LiteralPath $PastaRaiz `
            -PathType Container
    )
) {
    throw "Pasta não encontrada: $PastaRaiz"
}

$PastaRaiz =
    (
        Resolve-Path `
            -LiteralPath $PastaRaiz
    ).Path

if (
    [string]::IsNullOrWhiteSpace(
        $Recursivo
    )
) {
    $resp =
        Read-Host `
            "Procurar vídeos também em todos os subdiretórios? [S/N]"

    $Recursive =
        Test-Sim $resp
}
else {
    $Recursive =
        Test-Sim $Recursivo
}

$OutputRoot =
    Join-Path `
        $PastaRaiz `
        $NomePastaSaida

Write-Host ""

$subpastasText =
    if ($Recursive) {
        "SIM"
    }
    else {
        "NÃO"
    }

Write-Host "Pasta raiz:   $PastaRaiz"
Write-Host (
    "Subpastas:     {0}" -f `
        $subpastasText
)
Write-Host "Saída:         $OutputRoot"
Write-Host ""
Write-Host (
    "IMPORTANTE: a pasta de saída será EXCLUÍDA de futuras varreduras."
) -ForegroundColor Yellow
Write-Host ""

# =====================================================================
# 12 - FERRAMENTAS
# =====================================================================

$script:FfmpegExe =
    Resolve-ExecutablePath `
        -Name "ffmpeg.exe" `
        -ExplicitPath $FfmpegPath

if (-not $script:FfmpegExe) {
    throw "ffmpeg.exe não localizado."
}

$script:FfprobeExe =
    Resolve-ExecutablePath `
        -Name "ffprobe.exe" `
        -ExplicitPath $FfprobePath `
        -SiblingOf $script:FfmpegExe

if (-not $script:FfprobeExe) {
    throw "ffprobe.exe não localizado."
}

Write-Host "FFmpeg:  $script:FfmpegExe"
Write-Host "FFprobe: $script:FfprobeExe"

& $script:FfmpegExe -version 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "FFmpeg falhou no autoteste."
}

& $script:FfprobeExe -version 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "FFprobe falhou no autoteste."
}

$filtersText =
    & $script:FfmpegExe `
        -hide_banner `
        -filters `
        2>&1 |
    Out-String

if (
    -not $SemEstabilizacao -and
    (
        $filtersText -notmatch
        'vidstabdetect' -or
        $filtersText -notmatch
        'vidstabtransform'
    )
) {
    throw (
        "Este FFmpeg não possui libvidstab. Use build full ou rode com -SemEstabilizacao."
    )
}

$script:UseGpuEncode = $false
$script:UseGpuDecode = $false
$script:UseQsvDecode = $false
$script:DecodeBackend = "CPU"
$script:QsvDecoder = ""
$script:QsvBuildAvailable = $false
$script:QsvDecodersText = ""
$script:GpuPerfCountersUnavailable = $false
$script:GpuBenchmarkCsv = ""

try {
    $gpuNames =
        @(
            Get-CimInstance `
                Win32_VideoController `
                -ErrorAction Stop |
            Select-Object -ExpandProperty Name
        )

    if ($gpuNames.Count -gt 0) {
        Write-Host "GPUs detectadas pelo Windows:" -ForegroundColor Cyan

        foreach ($gpuName in $gpuNames) {
            Write-Host (
                "  - {0}" -f `
                    $gpuName
            )
        }
    }
}
catch {}

$hwaccelsText =
    & $script:FfmpegExe `
        -hide_banner `
        -hwaccels `
        2>&1 |
    Out-String

$script:QsvDecodersText =
    & $script:FfmpegExe `
        -hide_banner `
        -decoders `
        2>&1 |
    Out-String

if (
    -not $SemIntelQSV -and
    $hwaccelsText -match '(?m)^qsv\s*$'
) {
    $script:QsvBuildAvailable = $true
}

$selfTestDir =
    Join-Path `
        $env:TEMP `
        "video_restaurador_selftest"

New-Item `
    -ItemType Directory `
    -Path $selfTestDir `
    -Force |
    Out-Null

$selfOut =
    Join-Path `
        $selfTestDir `
        "gpu_test.mp4"

Remove-Item `
    -LiteralPath $selfOut `
    -Force `
    -ErrorAction SilentlyContinue

& $script:FfmpegExe `
    -hide_banner `
    -loglevel error `
    -f lavfi `
    -i "testsrc2=size=640x360:rate=30" `
    -t 1 `
    -c:v h264_nvenc `
    -preset p1 `
    -y "$selfOut" `
    2>$null |
    Out-Null

if (
    $LASTEXITCODE -eq 0 -and
    (
        Test-Path `
            -LiteralPath $selfOut
    )
) {
    $script:UseGpuEncode = $true
}

Remove-Item `
    -LiteralPath $selfOut `
    -Force `
    -ErrorAction SilentlyContinue

if ($script:UseGpuEncode) {
    Write-Host `
        "Encode: NVIDIA NVENC disponível e será a rota preferencial." `
        -ForegroundColor Green
}
else {
    Write-Host `
        "Encode: NVIDIA NVENC indisponível; saída seguirá em CPU/libx264." `
        -ForegroundColor Yellow
}

if ($script:QsvBuildAvailable) {
    Write-Host `
        "Decode adicional: Intel Quick Sync/QSV disponível; será testado por arquivo." `
        -ForegroundColor Green
}
elseif ($SemIntelQSV) {
    Write-Host `
        "Decode Intel QSV desativado por -SemIntelQSV." `
        -ForegroundColor DarkYellow
}
else {
    Write-Host `
        "Decode Intel QSV não foi detectado neste build/driver; CUDA/CPU continuam disponíveis." `
        -ForegroundColor Yellow
}

if ($PreferirIntelQSV) {
    Write-Host `
        "Política: QSV será escolhido sempre que passar no autoteste do arquivo." `
        -ForegroundColor Cyan
}
else {
    Write-Host `
        "Política Auto V1.6: warm-up + mediana de múltiplas medições; QSV entra se superar CUDA pela margem configurada ou se CUDA falhar." `
        -ForegroundColor Cyan
}

# =====================================================================
# 13 - MAPA DOS VÍDEOS
# =====================================================================

Write-Host ""
Write-Host "============================================================" `
    -ForegroundColor Cyan
Write-Host " ETAPA A - MAPEAMENTO DOS ARQUIVOS" `
    -ForegroundColor Cyan
Write-Host "============================================================" `
    -ForegroundColor Cyan

$candidates =
    Get-VideoCandidates `
        -Root $PastaRaiz `
        -Recursive $Recursive `
        -ExcludedRoot $OutputRoot

Write-Host (
    "Arquivos com extensões de vídeo encontrados: {0}" -f `
        $candidates.Count
)

$inventory = @()
$counter = 0

foreach ($file in $candidates) {
    $counter++

    Write-Host (
        "[MAP {0}/{1}] Validando: {2}" -f `
            $counter,
            $candidates.Count,
            (
                Get-RelativePathSimple `
                    -Base $PastaRaiz `
                    -FullPath $file.FullName
            )
    )

    $info =
        Get-MediaInfo $file.FullName

    if (-not $info) {
        Write-Host `
            "          Ignorado: FFprobe não identificou stream de vídeo." `
            -ForegroundColor DarkYellow
        continue
    }

    $rel =
        Get-RelativePathSimple `
            -Base $PastaRaiz `
            -FullPath $file.FullName

    $dateInfo =
        Get-OriginalDateInfo `
            -File $file.FullName

    $inventory += [pscustomobject]@{
        Id =
            "{0:000}" -f
            ($inventory.Count + 1)

        Arquivo =
            $file.FullName

        Relativo =
            $rel

        Nome =
            $file.Name

        DataOriginal =
            if ($dateInfo.HasCanonicalDate) {
                $dateInfo.CanonicalDisplay
            }
            else {
                ""
            }

        FonteDataOriginal =
            $dateInfo.Source

        StatusDataOriginal =
            $dateInfo.Status

        ConfiancaDataOriginal =
            $dateInfo.Confidence

        AnoHint =
            $dateInfo.YearHints

        DateInfo =
            $dateInfo

        Resolucao =
            "$($info.Width)x$($info.Height)"

        FPS =
            [math]::Round(
                $info.AvgFps,
                3
            )

        VFR =
            $info.IsVfr

        Duracao =
            To-Timecode $info.Duration

        Codec =
            $info.VideoCodec

        Audio =
            if ($info.HasAudio) {
                "$($info.AudioCodec) / $($info.AudioRate)Hz / $($info.AudioChannels)ch"
            }
            else {
                "SEM AUDIO"
            }

        GB =
            [math]::Round(
                $file.Length /
                1GB,
                2
            )

        Info =
            $info
    }
}

New-Item `
    -ItemType Directory `
    -Path $OutputRoot `
    -Force |
    Out-Null

$mapCsv =
    Join-Path `
        $OutputRoot `
        "MAPA_VIDEOS_IDENTIFICADOS.csv"

$inventory |
    Select-Object `
        Id,
        Relativo,
        DataOriginal,
        FonteDataOriginal,
        StatusDataOriginal,
        ConfiancaDataOriginal,
        AnoHint,
        Resolucao,
        FPS,
        VFR,
        Duracao,
        Codec,
        Audio,
        GB |
    Export-Csv `
        -LiteralPath $mapCsv `
        -NoTypeInformation `
        -Encoding UTF8 `
        -Delimiter ";"


$metadataCsv =
    Join-Path `
        $OutputRoot `
        "METADADOS_DATAS.csv"

$inventory |
    ForEach-Object {
        [pscustomobject]@{
            Id = $_.Id
            Relativo = $_.Relativo
            DataOriginal = $_.DataOriginal
            FonteDataOriginal = $_.FonteDataOriginal
            StatusDataOriginal = $_.StatusDataOriginal
            ConfiancaDataOriginal = $_.ConfiancaDataOriginal
            AnoHint = $_.AnoHint
            EmbeddedCandidates =
                $_.DateInfo.EmbeddedCandidates
            FileSystemCandidates =
                $_.DateInfo.FileSystemCandidates
            OriginalCreationTimeUtc =
                $_.DateInfo.OriginalCreationTimeUtcText
            OriginalLastWriteTimeUtc =
                $_.DateInfo.OriginalLastWriteTimeUtcText
            Aviso =
                $_.DateInfo.Warning
        }
    } |
    Export-Csv `
        -LiteralPath $metadataCsv `
        -NoTypeInformation `
        -Encoding UTF8 `
        -Delimiter ";"

Write-Host ""
Write-Host "============================================================"
Write-Host (
    "VIDEOS VALIDOS IDENTIFICADOS: {0}" -f `
        $inventory.Count
) -ForegroundColor Green
Write-Host "============================================================"

if ($inventory.Count -eq 0) {
    Write-Host "Nenhum vídeo para processar."
    exit 0
}

$inventory |
    Select-Object `
        Id,
        Relativo,
        DataOriginal,
        FonteDataOriginal,
        StatusDataOriginal,
        ConfiancaDataOriginal,
        AnoHint,
        Resolucao,
        FPS,
        VFR,
        Duracao,
        Codec,
        Audio,
        GB |
    Format-Table `
        -AutoSize `
        -Wrap

Write-Host ""
Write-Host "Mapa gravado em:"
Write-Host "  $mapCsv"
Write-Host "Metadados/datas:"
Write-Host "  $metadataCsv"
Write-Host ""

if ($SomenteMetadados) {
    Write-Host "MODO SOMENTE METADADOS:" -ForegroundColor Cyan
    Write-Host "  - não reencoda vídeo;"
    Write-Host "  - não reprocesa áudio;"
    Write-Host "  - remuxa por stream-copy;"
    Write-Host "  - preserva/normaliza datas e metadados arquivísticos;"
    Write-Host "  - valida que frame count e resolução não mudaram;"
}
else {
    Write-Host "O processamento planejado para CADA vídeo será:" `
        -ForegroundColor Cyan
    Write-Host "  1. benchmark GPU na fonte quando VFR; normalizar CFR pela melhor rota disponível;"
Write-Host "  2. localizar pillarboxes baked-in;"
Write-Host "  3. refinar cada troca em frame nativo;"
Write-Host "  4. dividir a timeline nos frames exatos;"
Write-Host "  5. estabilizar cada segmento com vidstab;"
Write-Host "  6. compor 1920x1080 com foreground preservado + fundo blur;"
Write-Host "  7. medir e corrigir loudness; redução leve de ruído;"
    Write-Host "  8. remontar, muxar, verificar frame count, metadados e smoke-decode;"
}

Write-Host ""
Write-Host (
    "Originais NÃO serão sobrescritos."
) -ForegroundColor Yellow
Write-Host (
    "Resultados ficarão somente em: $OutputRoot"
) -ForegroundColor Yellow
Write-Host ""

if (-not $AutoConfirmar) {
    $confirm =
        Read-Host `
            "CONFIRMA o processamento de TODOS os vídeos acima? [S/N]"

    if (-not (Test-Sim $confirm)) {
        Write-Host ""
        Write-Host `
            "Processamento cancelado pelo usuário. O mapa foi preservado." `
            -ForegroundColor Yellow
        exit 0
    }
}

Write-Host ""
Write-Host `
    "CONFIRMADO. A partir daqui o pipeline seguirá de forma autônoma." `
    -ForegroundColor Green
Write-Host ""

# =====================================================================
# 14 - PROCESSAMENTO
# =====================================================================

if ($SomenteMetadados) {
    $finalRoot =
        Join-Path `
            $OutputRoot `
            "FINAL"

    $metaResults = @()
    $metaErrors = @()

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " ATUALIZAÇÃO ARQUIVÍSTICA DOS MASTERS EXISTENTES" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan

    foreach ($item in $inventory) {
        $safeName =
            Sanitize-Name (
                [IO.Path]::GetFileNameWithoutExtension(
                    [string]$item.Nome
                )
            )

        $relDir =
            Split-Path `
                -Parent `
                ([string]$item.Relativo)

        $destDir =
            if (
                [string]::IsNullOrWhiteSpace(
                    $relDir
                )
            ) {
                $finalRoot
            }
            else {
                Join-Path `
                    $finalRoot `
                    $relDir
            }

        $finalFile =
            Join-Path `
                $destDir `
                (
                    $safeName +
                    "_1080P_ESTABILIZADO.mp4"
                )

        $metaLog =
            Join-Path `
                $OutputRoot `
                (
                    "METADATA_ONLY_{0}.log" -f `
                        $item.Id
                )

        try {
            Write-Host (
                "[META {0}/{1}] {2}" -f `
                    $item.Id,
                    $inventory.Count,
                    $item.Relativo
            ) -ForegroundColor Cyan

            $mr =
                Rewrite-ExistingFinalMetadata `
                    -OriginalFile $item.Arquivo `
                    -FinalFile $finalFile `
                    -DateInfo $item.DateInfo `
                    -LogFile $metaLog

            $metaResults += [pscustomobject]@{
                Id = $item.Id
                Relativo = $item.Relativo
                Status = $mr.Status
                DataOriginal =
                    $item.DataOriginal
                FonteDataOriginal =
                    $item.FonteDataOriginal
                Final = $finalFile
            }

            if ($mr.Status -eq "OK") {
                Write-Host (
                    "       OK | Data {0} | {1}" -f `
                        (
                            if (
                                [string]::IsNullOrWhiteSpace(
                                    [string]$item.DataOriginal
                                )
                            ) {
                                "não definida"
                            }
                            else {
                                $item.DataOriginal
                            }
                        ),
                        $item.StatusDataOriginal
                ) -ForegroundColor Green
            }
            else {
                Write-Host (
                    "       {0}" -f `
                        $mr.Status
                ) -ForegroundColor DarkYellow
            }
        }
        catch {
            $metaErrors +=
                "{0}: {1}" -f `
                    $item.Id,
                    $_.Exception.Message

            $metaResults += [pscustomobject]@{
                Id = $item.Id
                Relativo = $item.Relativo
                Status = "ERRO"
                DataOriginal =
                    $item.DataOriginal
                FonteDataOriginal =
                    $item.FonteDataOriginal
                Final = $finalFile
            }

            Write-Host (
                "       ERRO: {0}" -f `
                    $_.Exception.Message
            ) -ForegroundColor Red
        }
    }

    $metaReport =
        Join-Path `
            $OutputRoot `
            "RELATORIO_ATUALIZACAO_METADADOS.csv"

    $metaResults |
        Export-Csv `
            -LiteralPath $metaReport `
            -NoTypeInformation `
            -Encoding UTF8 `
            -Delimiter ";"

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan

    if ($metaErrors.Count -eq 0) {
        Write-Host "METADADOS ATUALIZADOS SEM ERROS" -ForegroundColor Green
    }
    else {
        Write-Host (
            "METADADOS CONCLUÍDOS COM {0} ERRO(S)" -f `
                $metaErrors.Count
        ) -ForegroundColor Red
    }

    Write-Host "Relatório: $metaReport"
    Write-Host "Datas:     $metadataCsv"

    exit (
        if ($metaErrors.Count -eq 0) {
            0
        }
        else {
            1
        }
    )
}

$workRoot =
    Join-Path `
        $OutputRoot `
        "_WORK"

$finalRoot =
    Join-Path `
        $OutputRoot `
        "FINAL"

New-Item `
    -ItemType Directory `
    -Path $workRoot `
    -Force |
    Out-Null

New-Item `
    -ItemType Directory `
    -Path $finalRoot `
    -Force |
    Out-Null

$results = @()
$errors = @()
$videoIndex = 0

$script:GpuBenchmarkCsv =
    Join-Path `
        $OutputRoot `
        "BENCHMARK_GPU.csv"

Remove-Item `
    -LiteralPath $script:GpuBenchmarkCsv `
    -Force `
    -ErrorAction SilentlyContinue

foreach ($item in $inventory) {
    $videoIndex++

    $id =
        [string]$item.Id

    $source =
        [string]$item.Arquivo

    $sourceInfo =
        $item.Info

    $safeName =
        Sanitize-Name (
            [IO.Path]::GetFileNameWithoutExtension(
                [string]$item.Nome
            )
        )

    $workDir =
        Join-Path `
            $workRoot `
            "${id}_${safeName}"

    New-Item `
        -ItemType Directory `
        -Path $workDir `
        -Force |
        Out-Null

    $relDir =
        Split-Path `
            -Parent `
            ([string]$item.Relativo)

    $destDir =
        if (
            [string]::IsNullOrWhiteSpace(
                $relDir
            )
        ) {
            $finalRoot
        }
        else {
            Join-Path `
                $finalRoot `
                $relDir
        }

    $finalFile =
        Join-Path `
            $destDir `
            (
                $safeName +
                "_1080P_ESTABILIZADO.mp4"
            )

    $started = Get-Date

    Write-Host "============================================================" `
        -ForegroundColor Cyan
    Write-Host (
        "VIDEO {0}/{1} [{2}] - {3}" -f `
            $videoIndex,
            $inventory.Count,
            $id,
            $item.Relativo
    ) -ForegroundColor Cyan
    Write-Host "============================================================" `
        -ForegroundColor Cyan
    Write-Host (
        "Original: {0} | {1} fps | {2} | {3}" -f `
            $item.Resolucao,
            $item.FPS,
            $item.Duracao,
            $item.Audio
    )
    Write-Host (
        "Destino:  {0}" -f `
            $finalFile
    )
    Write-Host ""

    try {
        Write-Host `
            "  [1/8] Preparando fonte de trabalho." `
            -ForegroundColor Cyan

        # Reset por vídeo para impedir que uma rota escolhida no
        # arquivo anterior vaze para uma normalização que não foi benchmarkada.
        $script:UseGpuDecode = $false
        $script:UseQsvDecode = $false
        $script:DecodeBackend = "CPU"
        $script:QsvDecoder = ""

        $normalizedOut =
            Join-Path `
                $workDir `
                "00_NORMALIZADO_CFR.mp4"

        $normalizedDone =
            Join-Path `
                $workDir `
                "00_NORMALIZADO_CFR.done"

        $normalizationCheckpoint =
            (
                (-not $Forcar) -and
                (Test-Path -LiteralPath $normalizedOut) -and
                (Test-Path -LiteralPath $normalizedDone)
            )

        $sourceBenchmark = $null

        if (
            $sourceInfo.IsVfr -and
            -not $SemBenchmarkPreVfr -and
            -not $normalizationCheckpoint
        ) {
            Write-Host (
                "       [GPU PRE-VFR] Benchmarkando a FONTE ORIGINAL antes da normalização."
            ) -ForegroundColor Cyan

            $sourceBenchmark =
                Test-GpuDecodeForFile `
                    -VideoId $id `
                    -File $source `
                    -Info $sourceInfo `
                    -WorkDir $workDir `
                    -StageName "ORIGINAL_PRE_VFR"
        }
        elseif (
            $sourceInfo.IsVfr -and
            $normalizationCheckpoint
        ) {
            Write-Host (
                "       [GPU PRE-VFR] Pulado: normalização CFR já possui checkpoint."
            ) -ForegroundColor DarkGreen
        }
        elseif (
            $sourceInfo.IsVfr -and
            $SemBenchmarkPreVfr
        ) {
            Write-Host (
                "       [GPU PRE-VFR] Desativado por -SemBenchmarkPreVfr; normalização começa com decode CPU."
            ) -ForegroundColor DarkYellow
        }

        $working =
            Normalize-VfrIfNeeded `
                -VideoId $id `
                -Source $source `
                -Info $sourceInfo `
                -WorkDir $workDir

        $file =
            [string]$working.File

        $info =
            $working.Info

        if (
            $info.FrameCount -le 0 -or
            $info.AvgFps -le 0
        ) {
            throw "Fonte de trabalho sem frame count/FPS confiável."
        }

        if ($working.Normalized) {
            Write-Host (
                "       Fonte CFR de trabalho: {0:N3} fps | {1} frames | normalização via {2}." -f `
                    $info.AvgFps,
                    $info.FrameCount,
                    $working.NormalizationBackend
            ) -ForegroundColor Green

            [void](
                Test-GpuDecodeForFile `
                    -VideoId $id `
                    -File $file `
                    -Info $info `
                    -WorkDir $workDir `
                    -StageName "CFR_POS_NORMALIZACAO"
            )
        }
        else {
            Write-Host (
                "       Fonte já adequada: CFR aproximado {0:N3} fps | {1} frames." -f `
                    $info.AvgFps,
                    $info.FrameCount
            ) -ForegroundColor Green

            [void](
                Test-GpuDecodeForFile `
                    -VideoId $id `
                    -File $file `
                    -Info $info `
                    -WorkDir $workDir `
                    -StageName "FONTE_CFR"
            )
        }

        $exactFrameCount =
            Get-ExactDecodedFrameCount `
                -VideoId $id `
                -File $file `
                -Info $info `
                -WorkDir $workDir

        if (
            $exactFrameCount -gt 0 -and
            $exactFrameCount -ne
            [long]$info.FrameCount
        ) {
            $info.FrameCount =
                [long]$exactFrameCount

            Write-Host (
                "       Timeline de trabalho ajustada para {0} frames." -f `
                    $info.FrameCount
            ) -ForegroundColor Green
        }

        $coarse =
            Invoke-CoarsePillarScan `
                -VideoId $id `
                -File $file `
                -Info $info `
                -WorkDir $workDir

        $exact =
            Invoke-ExactPillarRefine `
                -VideoId $id `
                -File $file `
                -Info $info `
                -Coarse $coarse `
                -WorkDir $workDir

        Write-Host `
            "  [4/8] Construindo plano de timeline por número de frame." `
            -ForegroundColor Cyan

        $segments =
            Build-SegmentPlan `
                -Exact $exact `
                -Info $info

        $pillarSegments =
            @(
                $segments |
                Where-Object {
                    $_.Type -eq "PILLAR"
                }
            ).Count

        Write-Host (
            "       Plano: {0} segmento(s), dos quais {1} com pillarbox baked-in." -f `
                $segments.Count,
                $pillarSegments
        ) -ForegroundColor Green

        $segments |
            Export-Csv `
                -LiteralPath (
                    Join-Path `
                        $workDir `
                        "03_PLANO_SEGMENTOS.csv"
                ) `
                -NoTypeInformation `
                -Encoding UTF8 `
                -Delimiter ";"

        Write-Host `
            "  [5/8] Estabilização + render 1920x1080 por segmento." `
            -ForegroundColor Cyan

        Write-Host (
            "       Segmentos 16:9 cobrirão todo o quadro; 4:3/vertical/wide receberão background blur automaticamente."
        )
        Write-Host (
            "       Em pillarbox baked-in, as barras pretas são removidas antes do vidstab."
        )

        $rendered =
            Render-Segments `
                -VideoId $id `
                -File $file `
                -Info $info `
                -Segments $segments `
                -WorkDir $workDir

        $videoOnly =
            Concat-Video `
                -VideoId $id `
                -Rows $rendered `
                -Info $info `
                -WorkDir $workDir

        $audio =
            Process-Audio `
                -VideoId $id `
                -File $file `
                -Info $info `
                -WorkDir $workDir

        $final =
            Mux-Final `
                -VideoId $id `
                -VideoOnly $videoOnly `
                -AudioFile $audio `
                -OriginalFile $source `
                -Info $info `
                -DateInfo $item.DateInfo `
                -FinalFile $finalFile `
                -WorkDir $workDir

        $elapsed =
            ((Get-Date) - $started).
            TotalMinutes

        $fi =
            Get-Item `
                -LiteralPath $final

        $results += [pscustomobject]@{
            Id = $id
            Arquivo =
                $item.Relativo
            Status = "OK"
            DataOriginal =
                $item.DataOriginal
            FonteDataOriginal =
                $item.FonteDataOriginal
            StatusDataOriginal =
                $item.StatusDataOriginal
            PillarCoarse =
                $coarse.Count
            PillarExato =
                $exact.Count
            PillarRevisar =
                $exact.Review
            Segmentos =
                $segments.Count
            Duracao =
                $item.Duracao
            TempoMin =
                [math]::Round(
                    $elapsed,
                    1
                )
            SaidaGB =
                [math]::Round(
                    $fi.Length /
                    1GB,
                    2
                )
            Saida =
                $final
        }

        Write-Host ""
        Write-Host (
            "  [OK] {0} concluído em {1:N1} min | saída {2:N2} GB" -f `
                $id,
                $elapsed,
                ($fi.Length / 1GB)
        ) -ForegroundColor Green
    }
    catch {
        $msg =
            $_.Exception.Message

        $detail =
            Join-Path `
                $workDir `
                "ERRO_DETALHADO.txt"

        @(
            "ID: $id"
            "ARQUIVO: $source"
            "DATA: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            ""
            "MENSAGEM:"
            $msg
            ""
            "POSITION:"
            $_.InvocationInfo.PositionMessage
            ""
            "STACK:"
            $_.ScriptStackTrace
            ""
            "EXCEPTION:"
            ($_ | Out-String)
        ) |
            Set-Content `
                -LiteralPath $detail `
                -Encoding UTF8

        $errors +=
            "${id}: $msg"

        $results += [pscustomobject]@{
            Id = $id
            Arquivo =
                $item.Relativo
            Status = "ERRO"
            DataOriginal =
                $item.DataOriginal
            FonteDataOriginal =
                $item.FonteDataOriginal
            StatusDataOriginal =
                $item.StatusDataOriginal
            PillarCoarse = ""
            PillarExato = ""
            PillarRevisar = ""
            Segmentos = ""
            Duracao =
                $item.Duracao
            TempoMin =
                [math]::Round(
                    ((Get-Date) - $started).
                    TotalMinutes,
                    1
                )
            SaidaGB = ""
            Saida = ""
        }

        Write-Host ""
        Write-Host (
            "  [ERRO] {0}" -f `
                $msg
        ) -ForegroundColor Red

        Write-Host (
            "  Detalhes: {0}" -f `
                $detail
        ) -ForegroundColor DarkRed

        Write-Host `
            "  O pipeline continuará para o próximo vídeo." `
            -ForegroundColor Yellow
    }

    Write-Host ""
}

# =====================================================================
# 15 - RELATÓRIO FINAL
# =====================================================================

$report =
    Join-Path `
        $OutputRoot `
        "RELATORIO_EXECUCAO.csv"

$results |
    Export-Csv `
        -LiteralPath $report `
        -NoTypeInformation `
        -Encoding UTF8 `
        -Delimiter ";"

$summary =
    Join-Path `
        $OutputRoot `
        "RESUMO_EXECUCAO.txt"

$lines = @(
    "RESTAURADOR UNIVERSAL DE VIDEOS"
    "1080P + ESTABILIZACAO + PILLAR BLUR + AUDIO"
    ""
    "Gerado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "Pasta raiz: $PastaRaiz"
    "Recursivo: $Recursive"
    "Saida: $OutputRoot"
    ""
    "Videos mapeados: $($inventory.Count)"
    "Sucessos: $(@($results | Where-Object {$_.Status -eq 'OK'}).Count)"
    "Erros: $($errors.Count)"
    ""
    "Politica:"
    "- originais nunca sobrescritos"
    "- pasta de saida excluida das futuras varreduras"
    "- VFR: benchmark opcional na fonte ORIGINAL antes da normalizacao; rota GPU escolhida pode acelerar a conversao CFR"
    "- apos normalizacao, novo benchmark decide a melhor rota para o pipeline principal"
    "- benchmark GPU: warm-up + mediana de $BenchmarkGpuRepeticoes medicoes de ate $BenchmarkGpuFrames frames"
    "- margem QSV configurada: $MargemQsvPct%"
    "- frame count autoritativo obtido por ffprobe -count_frames"
    "- decode adaptativo por arquivo: NVIDIA NVDEC/CUDA, Intel Quick Sync/QSV ou CPU"
    "- QSV pode fazer downscale do diagnóstico na Intel antes do hwdownload"
    "- encode final prefere NVIDIA NVENC; libx264 permanece fallback"
    "- pillarbox coarse em $AmostrasPillarPorSegundo fps"
    "- bordas refinadas em todos os frames nativos"
    "- barras removidas antes do vidstab"
    "- render final 1920x1080"
    "- foreground preserva aspect ratio"
    "- background blur preenche areas livres"
    "- loudnorm alvo -16 LUFS / LRA 12 / TP -1.5 dBTP"
    "- audio AAC 48kHz; 192k stereo / 384k multicanal"
    "- concat usa caminhos relativos ASCII, inclusive quando a pasta pai contem Unicode"
    "- progress=end + arquivo valido pode recuperar ExitCode ausente; validacoes continuam obrigatorias"
    "- telemetria por processo tenta mostrar QSV-D/CUDA-D e VideoEncode via contadores do Windows"
    "- BENCHMARK_GPU.csv registra as medicoes e a rota escolhida"
    "- Data Original Canonica: prefere datas embutidas; usa filesystem apenas quando plausivel"
    "- anos encontrados no caminho funcionam como sanity-check, nunca como data inventada"
    "- MP4 final grava creation_time/date/original_capture_time quando existe data confiavel"
    "- MP4 final grava restoration_time e proveniencia da data"
    "- timestamps CreationTime/LastWriteTime do master espelham o ORIGINAL, salvo -SemPreservarDatasSistemaArquivos"
    "- METADADOS_DATAS.csv registra candidatos, fonte, confianca e avisos"
    "- modo -SomenteMetadados atualiza masters existentes por stream-copy, sem re-render"
    "- checkpoints e resume"
    ""
)

foreach ($r in $results) {
    $lines += (
        "{0} | {1} | {2} | pillar exato {3} | segmentos {4} | {5}" -f `
            $r.Id,
            $r.Status,
            $r.Arquivo,
            $r.PillarExato,
            $r.Segmentos,
            $r.Saida
    )
}

if ($errors.Count -gt 0) {
    $lines += ""
    $lines += "ERROS:"
    $lines += $errors
}

$lines |
    Set-Content `
        -LiteralPath $summary `
        -Encoding UTF8

Write-Host "============================================================" `
    -ForegroundColor Cyan

if ($errors.Count -eq 0) {
    Write-Host "CONCLUIDO SEM ERROS" `
        -ForegroundColor Green
}
else {
    Write-Host (
        "CONCLUIDO COM {0} ERRO(S)" -f `
            $errors.Count
    ) -ForegroundColor Red
}

Write-Host "============================================================" `
    -ForegroundColor Cyan
Write-Host "Mapa:      $mapCsv"
Write-Host "Relatorio: $report"
Write-Host "Resumo:    $summary"
Write-Host "Finais:    $finalRoot"
Write-Host "GPU Bench: $script:GpuBenchmarkCsv"
Write-Host "Datas:     $metadataCsv"

if ($DesligarAoFinal) {
    if ($errors.Count -eq 0) {
        Write-Host ""
        Write-Host `
            "Desligamento solicitado: Windows será desligado em 60 segundos." `
            -ForegroundColor Yellow

        shutdown.exe /s /t 60
    }
    else {
        Write-Host ""
        Write-Host `
            "Desligamento NÃO executado porque houve erros." `
            -ForegroundColor Yellow
    }
}
