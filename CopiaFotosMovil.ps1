#Requires -Version 5.1
<#
.SYNOPSIS
    CopiaFotosMovil.ps1 - Copia fotos del movil Android al PC via USB
.DESCRIPTION
    Conecta con el movil a traves de USB (protocolo MTP), navega por las
    carpetas especificadas preservando la estructura de albumes, y copia 
    los archivos de foto/video nuevos a dos destinos en el PC.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string[]]$Destinos = @("C:\Respaldo_Fotos"),
    [Parameter(Mandatory=$false)]
    [switch]$Auto,
    [Parameter(Mandatory=$false)]
    [int]$DeviceIndex = 1,
    [Parameter(Mandatory=$false)]
    [int]$StorageIndex = 1,
    [Parameter(Mandatory=$false)]
    [switch]$NoPause,
    [Parameter(Mandatory=$false)]
    [switch]$ShowSkipped
)

<# if ($Destinos.Count -eq 1 -and $Destinos[0] -match ';') {
    $Destinos = $Destinos[0] -split ';'
} #>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"
$SCRIPT_VERSION = "1.0.0"

# Crear una unica instancia COM reutilizable
$global:ShellApp = New-Object -ComObject Shell.Application

# ====================================================================
# CONFIGURACION
# ====================================================================
$CONFIG = @{
    Destinations = $Destinos
    
    # Solo copiaremos archivos con estas extensiones
    Extensions = @(
        '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tiff', '.tif',
        '.mp4', '.mov', '.avi', '.3gp', '.mkv', '.wmv', '.m4v',
        '.heic', '.heif', '.webp', '.raw', '.dng', '.cr2', '.nef', '.arw'
    )
    
    # Carpetas en la raiz del movil que SI queremos escanear. 
    AllowedRootFolders = @(
        'DCIM',
        'Pictures',
        'Movies'
    )

    # Exclusiones especificas para saltarnos carpetas basura o caches y WhatsApp
    ExcludePaths = @(
        'Android',
        'Android\data',
        'WhatsApp',
        'Pictures\.thumbnails'
    )

    CopyTimeoutSeconds = 300
    StableSizeChecksRequired = 2
    StableSizeCheckIntervalMs = 250
    ShowSkipped = [bool]$ShowSkipped
    LogPath = "$PSScriptRoot\Logs\log_copia_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
}

# Estado global
$Stats = @{
    Copied = 0
    Skipped = 0
    Errors = 0
    Folders = 0
    BytesCopied = 0
    PerDestination = @{}
}
foreach ($dest in $CONFIG.Destinations) {
    $Stats.PerDestination[$dest] = @{ Copied = 0; Skipped = 0; Errors = 0 }
}

# Crear la subcarpeta de logs si no existe
$logDir = Split-Path -Parent $CONFIG.LogPath
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# ====================================================================
# FUNCIONES
# ====================================================================

function Write-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  ======================================================" -ForegroundColor Cyan
    Write-Host "      COPIA DE FOTOS MOVIL -> PC                        " -ForegroundColor Cyan
    Write-Host "      Filtro inteligente - Preserva albumes             " -ForegroundColor Cyan
    Write-Host "  ======================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Color = "White",
        [string]$Icon = " "
    )
    $timestamp = Get-Date -Format "HH:mm:ss"
    $line = "  $Icon [$timestamp] $Message"
    Write-Host $line -ForegroundColor $Color
    
    # Escribir al log INMEDIATAMENTE por si se corta el script
    try {
        $line | Out-File -FilePath $CONFIG.LogPath -Encoding UTF8 -Append
    } catch {}
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "  -- $Title " -ForegroundColor DarkGray
    Write-Host ""
}

function Get-SafeFolderName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return "Dispositivo_Desconocido" }
    $safe = $Name
    foreach ($c in [System.IO.Path]::GetInvalidFileNameChars()) {
        $safe = $safe.Replace($c, '_')
    }
    $safe = $safe.Trim()
    if ([string]::IsNullOrWhiteSpace($safe)) { return "Dispositivo_Desconocido" }
    return $safe
}

function Pause-IfNeeded {
    param([string]$Message = "  Pulsa Enter para salir")
    if (-not $NoPause) {
        Read-Host $Message | Out-Null
    }
}

function Get-MTPDevices {
    # Usamos COM Shell.Application para acceder al entorno virtual de MTP
    $myComputer = $global:ShellApp.Namespace(0x11)
    
    $devices = [System.Collections.Generic.List[object]]::new()
    
    foreach ($item in $myComputer.Items()) {
        try {
            $path = $item.Path
            $isNormalDrive = ($path -match '^[A-Za-z]:\\$') -or ($path -match '^[A-Za-z]:$')
            $isSystemItem  = ($path -eq "") -or ($null -eq $path)
            
            if (-not $isNormalDrive -and -not $isSystemItem -and $item.IsFolder) {
                $subfolder = $item.GetFolder()
                if ($null -ne $subfolder) {
                    $devices.Add($item) | Out-Null
                }
            }
        }
        catch { }
    }
    
    return $devices
}

function Select-FromList {
    param(
        [string]$Prompt,
        [array]$Items,
        [scriptblock]$GetLabel = { param($x) $x.Name },
        [switch]$AutoSelect,
        [int]$PreferredIndex = 1
    )

    if ($Items.Count -eq 1) { return $Items[0] }

    if ($AutoSelect) {
        $idx = [Math]::Max(0, [Math]::Min($Items.Count - 1, $PreferredIndex - 1))
        $label = & $GetLabel $Items[$idx]
        Write-Log "Auto seleccion: [$($idx + 1)] $label" "DarkGray" "AUTO"
        return $Items[$idx]
    }

    Write-Host ""
    Write-Host "  $Prompt" -ForegroundColor Yellow
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $label = & $GetLabel $Items[$i]
        Write-Host "    [$($i + 1)]  $label" -ForegroundColor White
    }

    $idx = -1
    do {
        $raw = Read-Host "  Tu eleccion (1-$($Items.Count))"
        if ($raw -match '^\d+$') {
            $idx = [int]$raw - 1
        }
    } while ($idx -lt 0 -or $idx -ge $Items.Count)

    return $Items[$idx]
}

function Get-MTPItemSize {
    param([object]$MTPItem)
    $size = $null
    try { $size = $MTPItem.ExtendedProperty('System.Size') } catch {}
    if ($null -eq $size -or $size -eq '') {
        try { $size = $MTPItem.Size } catch {}
    }
    if ($null -eq $size -or $size -eq '') { return $null }
    try { return [int64]$size } catch { return $null }
}

function Get-MTPItemDateModified {
    param([object]$MTPItem)
    $date = $null
    try { $date = $MTPItem.ExtendedProperty('System.DateModified') } catch {}
    if ($null -eq $date -or $date -eq '') {
        try { $date = $MTPItem.ModifyDate } catch {}
    }
    if ($null -eq $date -or $date -eq '') { return $null }
    try { return [datetime]$date } catch { return $null }
}

function Test-DestinationHasSameFile {
    param(
        [object]$MTPItem,
        [string]$DestinationFile
    )
    if (-not (Test-Path $DestinationFile)) { return $false }
    try {
        $destInfo = Get-Item -LiteralPath $DestinationFile -ErrorAction Stop
    } catch {
        return $false
    }

    # Regla principal para backups incrementales por MTP:
    # si el tamaño coincide, tratamos el archivo como duplicado aunque la fecha difiera.
    $srcSize = Get-MTPItemSize -MTPItem $MTPItem
    if ($null -ne $srcSize) {
        return ($destInfo.Length -eq $srcSize)
    }

    # Fallback cuando MTP no expone tamaño fiable.
    $srcDate = Get-MTPItemDateModified -MTPItem $MTPItem
    if ($null -ne $srcDate) {
        $delta = [Math]::Abs(($destInfo.LastWriteTime - $srcDate).TotalSeconds)
        return ($delta -le 3)
    }

    # Ultimo fallback: existe con mismo nombre/ruta -> se considera duplicado.
    return $true
}

function Wait-ForStableFile {
    param(
        [string]$FilePath,
        [int]$TimeoutSeconds,
        [int]$StableChecksRequired,
        [int]$CheckIntervalMs
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $stableChecks = 0
    $lastSize = -1

    while ((Get-Date) -lt $deadline) {
        if (Test-Path $FilePath) {
            try {
                $currentSize = (Get-Item -LiteralPath $FilePath -ErrorAction Stop).Length
                if ($currentSize -gt 0 -and $currentSize -eq $lastSize) {
                    $stableChecks++
                    if ($stableChecks -ge $StableChecksRequired) { return $true }
                } else {
                    $stableChecks = 0
                    $lastSize = $currentSize
                }
            } catch {
                $stableChecks = 0
            }
        }
        Start-Sleep -Milliseconds $CheckIntervalMs
    }
    return $false
}

function Wait-ForFileWithExpectedSize {
    param(
        [string]$FilePath,
        [int64]$ExpectedSize,
        [int]$TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path $FilePath) {
            try {
                $size = (Get-Item -LiteralPath $FilePath -ErrorAction Stop).Length
                if ($size -eq $ExpectedSize) {
                    return $true
                }
            } catch {}
        }
        Start-Sleep -Milliseconds 100
    }
    return $false
}

function Copy-FileFromMTP {
    # Copia un archivo desde el movil al PC usando la API de Windows Explorer
    # Esto preserva el contenido del archivo tal cual (incluyendo metadatos EXIF)
    param(
        [object]$MTPItem,
        [string]$DestinationDir,
        [string]$DestinationFile
    )

    if (-not (Test-Path $DestinationDir)) {
        New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
    }

    $destShell = $global:ShellApp.Namespace($DestinationDir)
    
    # Opciones de copia: 4=sin ventana, 16=si a todo, 1024=sin errores de UI
    $destShell.CopyHere($MTPItem, 4 + 16 + 1024)
    $srcSize = Get-MTPItemSize -MTPItem $MTPItem
    if ($null -ne $srcSize) {
        return (Wait-ForFileWithExpectedSize -FilePath $DestinationFile -ExpectedSize $srcSize -TimeoutSeconds $CONFIG.CopyTimeoutSeconds)
    }

    return (Wait-ForStableFile -FilePath $DestinationFile -TimeoutSeconds $CONFIG.CopyTimeoutSeconds -StableChecksRequired $CONFIG.StableSizeChecksRequired -CheckIntervalMs $CONFIG.StableSizeCheckIntervalMs)
}

function Should-ExcludePath {
    param([string]$Path)
    foreach ($excl in $CONFIG.ExcludePaths) {
        if ($Path -eq $excl -or $Path -like "$excl\*") {
            return $true
        }
    }
    return $false
}

function Invoke-RecursiveCopy {
    # Navega por el almacenamiento y filtra las carpetas que no queremos
    param(
        [object]$SourceFolder,
        [string]$RelativePath = ""
    )

    $items = $null
    try {
        $items = @($SourceFolder.Items())
    }
    catch {
        Write-Log "No se pudo leer la carpeta: '$RelativePath'" "DarkGray" "!"
        return
    }

    foreach ($item in $items) {
        $itemName    = $item.Name
        $itemRelPath = if ($RelativePath) { "$RelativePath\$itemName" } else { $itemName }

        if ($itemName -eq ".thumbnails") { continue }

        if ($item.IsFolder) {
            # Filtro 1: Carpetas raiz permitidas (solo evaluado en el nivel 0)
            if ($RelativePath -eq "" -and $itemName -notin $CONFIG.AllowedRootFolders) {
                continue
            }

            # Filtro 2: Carpetas ocultas o del sistema de Android (.thumbnails, .trash, etc)
            if ($itemName.StartsWith(".")) {
                continue
            }

            # Filtro 3: Rutas basura conocidas (como Android\data)
            if (Should-ExcludePath -Path $itemRelPath) { continue }

            $Stats.Folders++
            Write-Log "DIR  $itemRelPath" "DarkCyan"

            try {
                Invoke-RecursiveCopy -SourceFolder $item.GetFolder() -RelativePath $itemRelPath
            }
            catch {
                Write-Log "Error en carpeta '$itemRelPath': $_" "Red" "X"
            }
        }
        else {
            # Filtro 1: archivos de papelera Android (.trashed-*)
            if ($itemName -match '^(?:\.trashed-|trashed-|\.trash|\.recycle)') {
                continue
            }

            # Es un archivo. Comprobamos la extension
            $ext = [System.IO.Path]::GetExtension($itemName).ToLower()
            if ($ext -notin $CONFIG.Extensions) { continue }

            $copiedToAtLeastOne = $false
            $existsInAll        = $true

            foreach ($destRoot in $CONFIG.Destinations) {
                $deviceDestRoot = Join-Path $destRoot $script:DeviceFolderName
                $destDir  = if ($RelativePath) { Join-Path $deviceDestRoot $RelativePath } else { $deviceDestRoot }
                $destFile = Join-Path $destDir $itemName

                if (Test-DestinationHasSameFile -MTPItem $item -DestinationFile $destFile) {
                    $Stats.PerDestination[$destRoot].Skipped++
                    if ($CONFIG.ShowSkipped) {
                        Write-Log "    >>   $itemRelPath  (ya existe y coincide en $destFile)" "DarkGray"
                    }
                }
                else {
                    $existsInAll = $false
                    try {
                        $ok = Copy-FileFromMTP -MTPItem $item -DestinationDir $destDir -DestinationFile $destFile

                        if ($ok) {
                            $copiedToAtLeastOne = $true
                            $Stats.PerDestination[$destRoot].Copied++
                            $srcSize = Get-MTPItemSize -MTPItem $item
                            if ($null -ne $srcSize) {
                                $Stats.BytesCopied += $srcSize
                            }
                            Write-Log "    OK  $itemRelPath  ->  $deviceDestRoot" "Green"
                        }
                        else {
                            $Stats.Errors++
                            $Stats.PerDestination[$destRoot].Errors++
                            Write-Log "    FAIL  Timeout o copia inestable: $itemRelPath" "Red"
                        }
                    }
                    catch {
                        $Stats.Errors++
                        $Stats.PerDestination[$destRoot].Errors++
                        Write-Log "    FAIL  Error al copiar '$itemRelPath': $_" "Red"
                    }
                }
            }

            if ($copiedToAtLeastOne) { $Stats.Copied++ }
            elseif ($existsInAll)    { $Stats.Skipped++ }
        }
    }
}

# ====================================================================
# PROGRAMA PRINCIPAL
# ====================================================================

Write-Banner
Write-Log "Inicio de la copia" "Cyan" "INFO"
Write-Log "Version del script: v$SCRIPT_VERSION" "DarkGray" "INFO"
if ($Auto) {
    Write-Log "Modo automatico habilitado (sin preguntas)" "DarkGray" "AUTO"
}

Write-Section "Verificando destinos"
$destinosOk = $true
foreach ($dest in $CONFIG.Destinations) {
    if (-not (Test-Path $dest)) {
        try {
            New-Item -ItemType Directory -Path $dest -Force | Out-Null
            Write-Log "Creada carpeta: $dest" "Yellow" "DIR"
        }
        catch {
            Write-Log "No se pudo crear: $dest" "Red" "FAIL"
            $destinosOk = $false
        }
    }
    else {
        Write-Log "OK: $dest" "Green" "OK"
    }
}

if (-not $destinosOk) {
    Write-Host ""
    Write-Log "Hay destinos inaccesibles. Comprueba los discos." "Red" "FAIL"
    Pause-IfNeeded
    exit 1
}

Write-Section "Buscando movil"
Write-Log "Escaneando dispositivos conectados por USB..." "Yellow" "..."
Write-Log "El movil debe estar en modo 'Transferencia de archivos (MTP)'" "DarkGray" "..."
Write-Host ""

$devices = @(Get-MTPDevices)

if ($devices.Count -eq 0) {
    Write-Host ""
    Write-Log "No se encontro ningun dispositivo movil." "Red" "FAIL"
    Pause-IfNeeded
    exit 1
}

$device = Select-FromList -Prompt "Selecciona el dispositivo:" -Items $devices -AutoSelect:$Auto -PreferredIndex $DeviceIndex
Write-Host ""
Write-Log "Dispositivo seleccionado: $($device.Name)" "Green" "DEV"
$script:DeviceFolderName = Get-SafeFolderName -Name $device.Name
Write-Log "Subcarpeta por dispositivo: $script:DeviceFolderName" "DarkGray" "DEV"

$deviceFolder = $device.GetFolder()
$storages = @($deviceFolder.Items() | Where-Object { $_.IsFolder })

if ($storages.Count -eq 0) {
    Write-Log "No se encontro almacenamiento en el dispositivo." "Red" "FAIL"
    Pause-IfNeeded
    exit 1
}

$storage = Select-FromList -Prompt "Selecciona el almacenamiento:" -Items $storages -AutoSelect:$Auto -PreferredIndex $StorageIndex
Write-Log "Almacenamiento: $($storage.Name)" "Green" "DEV"

Write-Host ""
Write-Host "  ------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "  Listo para copiar a:" -ForegroundColor DarkGray
foreach ($dest in $CONFIG.Destinations) {
    $deviceDestRoot = Join-Path $dest $script:DeviceFolderName
    $short = $deviceDestRoot.Substring(0, [Math]::Min($deviceDestRoot.Length, 70))
    Write-Host "  -> $short" -ForegroundColor White
}
Write-Host "  ------------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

if (-not $Auto) {
    $confirm = Read-Host "  Empezamos? (S/N)"
    if ($confirm -notmatch '^[SsYy]') {
        Write-Log "Cancelado por el usuario." "Yellow" "INFO"
        exit 0
    }
}
else {
    Write-Log "Confirmacion omitida por modo automatico." "DarkGray" "AUTO"
}

Write-Section "Copiando archivos"
$startTime = Get-Date

try {
    Invoke-RecursiveCopy -SourceFolder $storage.GetFolder() -RelativePath ""
}
catch {
    Write-Log "Error inesperado durante la copia: $_" "Red" "FAIL"
}

$duration    = (Get-Date) - $startTime
$durationStr = "{0}m {1}s" -f [int]$duration.TotalMinutes, $duration.Seconds
$totalMB = [Math]::Round(($Stats.BytesCopied / 1MB), 2)
$filesPerMin = if ($duration.TotalMinutes -gt 0) { [Math]::Round(($Stats.Copied / $duration.TotalMinutes), 2) } else { 0 }
$mbPerSec = if ($duration.TotalSeconds -gt 0) { [Math]::Round(($Stats.BytesCopied / 1MB) / $duration.TotalSeconds, 2) } else { 0 }

Write-Host ""
Write-Host "  ======================================================" -ForegroundColor Cyan
Write-Host "                    RESUMEN FINAL                       " -ForegroundColor Cyan
Write-Host "  ======================================================" -ForegroundColor Cyan
Write-Host ("      Copiados:         {0,-20}" -f $Stats.Copied) -ForegroundColor Green
Write-Host ("      Ya existian:      {0,-20}" -f $Stats.Skipped) -ForegroundColor Yellow
Write-Host ("      Carpetas:         {0,-20}" -f $Stats.Folders) -ForegroundColor Cyan
$errColor = if ($Stats.Errors -gt 0) { "Red" } else { "DarkGray" }
Write-Host ("      Errores:          {0,-20}" -f $Stats.Errors) -ForegroundColor $errColor
Write-Host ("      Tiempo total:     {0,-20}" -f $durationStr) -ForegroundColor White
Write-Host "  ======================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "  -- Benchmark" -ForegroundColor DarkGray
Write-Host ("      MB copiados:      {0}" -f $totalMB) -ForegroundColor White
Write-Host ("      Archivos/min:     {0}" -f $filesPerMin) -ForegroundColor White
Write-Host ("      MB/s aprox:       {0}" -f $mbPerSec) -ForegroundColor White
Write-Host ""
Write-Host "  -- Resumen por destino" -ForegroundColor DarkGray
foreach ($dest in $CONFIG.Destinations) {
    $d = $Stats.PerDestination[$dest]
    Write-Host "  $dest" -ForegroundColor White
    Write-Host ("      Copiados:    {0}" -f $d.Copied) -ForegroundColor Green
    Write-Host ("      Ya existian: {0}" -f $d.Skipped) -ForegroundColor Yellow
    $dc = if ($d.Errors -gt 0) { "Red" } else { "DarkGray" }
    Write-Host ("      Errores:     {0}" -f $d.Errors) -ForegroundColor $dc
}

$logResumen = @"

  ======================================================
                    RESUMEN FINAL                       
  ======================================================
      Copiados:         $($Stats.Copied)
      Ya existian:      $($Stats.Skipped)
      Carpetas:         $($Stats.Folders)
      Errores:          $($Stats.Errors)
      Tiempo total:     $durationStr
  ======================================================
"@
try {
    $logResumen | Out-File -FilePath $CONFIG.LogPath -Encoding UTF8 -Append
    "  Benchmark:" | Out-File -FilePath $CONFIG.LogPath -Encoding UTF8 -Append
    "      MB copiados:      $totalMB" | Out-File -FilePath $CONFIG.LogPath -Encoding UTF8 -Append
    "      Archivos/min:     $filesPerMin" | Out-File -FilePath $CONFIG.LogPath -Encoding UTF8 -Append
    "      MB/s aprox:       $mbPerSec" | Out-File -FilePath $CONFIG.LogPath -Encoding UTF8 -Append
    "  Resumen por destino:" | Out-File -FilePath $CONFIG.LogPath -Encoding UTF8 -Append
    foreach ($dest in $CONFIG.Destinations) {
        $d = $Stats.PerDestination[$dest]
        "  - $dest" | Out-File -FilePath $CONFIG.LogPath -Encoding UTF8 -Append
        "      Copiados:    $($d.Copied)" | Out-File -FilePath $CONFIG.LogPath -Encoding UTF8 -Append
        "      Ya existian: $($d.Skipped)" | Out-File -FilePath $CONFIG.LogPath -Encoding UTF8 -Append
        "      Errores:     $($d.Errors)" | Out-File -FilePath $CONFIG.LogPath -Encoding UTF8 -Append
    }
} catch {}

Write-Log "=== COPIA FINALIZADA. TIEMPO: $durationStr ===" "Cyan" "INFO"

if ($Stats.Errors -gt 0) {
    Write-Host "  ATENCION: Algunos archivos no se copiaron. Revisa el log." -ForegroundColor Yellow
}

Write-Host "  Log guardado en: $($CONFIG.LogPath)" -ForegroundColor DarkGray
Write-Host ""

# Liberar correctamente el objeto COM
try {
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($global:ShellApp) | Out-Null
    $global:ShellApp = $null

    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}
catch {}

Pause-IfNeeded
