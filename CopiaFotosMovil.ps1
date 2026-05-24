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
    [string[]]$Destinos = @("C:\Respaldo_Fotos")
)

<# if ($Destinos.Count -eq 1 -and $Destinos[0] -match ';') {
    $Destinos = $Destinos[0] -split ';'
} #>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

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
        'WhatsApp',
        'Pictures\.thumbnails'
    )

    CopyTimeoutSeconds = 300
    ShowSkipped = $false
    LogPath = "$PSScriptRoot\Logs\log_copia_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
}

# Estado global
$Stats = @{ Copied = 0; Skipped = 0; Errors = 0; Folders = 0 }

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
        [scriptblock]$GetLabel = { param($x) $x.Name }
    )

    if ($Items.Count -eq 1) { return $Items[0] }

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

function Copy-FileFromMTP {
    # Copia un archivo desde el movil al PC usando la API de Windows Explorer
    # Esto preserva el contenido del archivo tal cual (incluyendo metadatos EXIF)
    param(
        [object]$MTPItem,
        [string]$DestinationDir
    )

    $fileName = $MTPItem.Name
    $destFile  = Join-Path $DestinationDir $fileName

    if (-not (Test-Path $DestinationDir)) {
        New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
    }

    $destShell = $global:ShellApp.Namespace($DestinationDir)
    
    # Opciones de copia: 4=sin ventana, 16=si a todo, 1024=sin errores de UI
    $destShell.CopyHere($MTPItem, 4 + 16 + 1024)

    # Esperamos a que el archivo aparezca, ya que CopyHere es asincrono
    $timeout = $CONFIG.CopyTimeoutSeconds
    $elapsed = 0
    while (-not (Test-Path $destFile) -and $elapsed -lt $timeout) {
        Start-Sleep -Milliseconds 500
        $elapsed += 0.5
    }

    return (Test-Path $destFile)
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
            $skip = $false
            foreach ($excl in $CONFIG.ExcludePaths) {
                if ($itemRelPath -eq $excl -or $itemRelPath -like "$excl\*") {
                    $skip = $true; break
                }
            }
            if ($skip) { continue }

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
                $destDir  = if ($RelativePath) { Join-Path $destRoot $RelativePath } else { $destRoot }
                $destFile = Join-Path $destDir $itemName

                # Deteccion de duplicados basica (por nombre de archivo)
                if (Test-Path $destFile) {
                    if ($CONFIG.ShowSkipped) {
                        Write-Log "    >>   $itemRelPath  (ya existe en $destFile)" "DarkGray"
                    }
                }
                else {
                    $existsInAll = $false
                    try {
                        $ok = Copy-FileFromMTP -MTPItem $item -DestinationDir $destDir

                        if ($ok) {
                            $copiedToAtLeastOne = $true
                            Write-Log "    OK  $itemRelPath  ->  $destFile" "Green"
                        }
                        else {
                            $Stats.Errors++
                            Write-Log "    FAIL  Timeout copiando: $itemRelPath" "Red"
                        }
                    }
                    catch {
                        $Stats.Errors++
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
    Read-Host "  Pulsa Enter para salir"
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
    Read-Host "  Pulsa Enter para salir"
    exit 1
}

$device = Select-FromList -Prompt "Selecciona el dispositivo:" -Items $devices
Write-Host ""
Write-Log "Dispositivo seleccionado: $($device.Name)" "Green" "DEV"

$deviceFolder = $device.GetFolder()
$storages = @($deviceFolder.Items() | Where-Object { $_.IsFolder })

if ($storages.Count -eq 0) {
    Write-Log "No se encontro almacenamiento en el dispositivo." "Red" "FAIL"
    Read-Host "  Pulsa Enter para salir"
    exit 1
}

$storage = Select-FromList -Prompt "Selecciona el almacenamiento:" -Items $storages
Write-Log "Almacenamiento: $($storage.Name)" "Green" "DEV"

Write-Host ""
Write-Host "  ------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "  Listo para copiar a:" -ForegroundColor DarkGray
foreach ($dest in $CONFIG.Destinations) {
    $short = $dest.Substring(0, [Math]::Min($dest.Length, 50))
    Write-Host "  -> $short" -ForegroundColor White
}
Write-Host "  ------------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

$confirm = Read-Host "  Empezamos? (S/N)"
if ($confirm -notmatch '^[SsYy]') {
    Write-Log "Cancelado por el usuario." "Yellow" "INFO"
    exit 0
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
try { $logResumen | Out-File -FilePath $CONFIG.LogPath -Encoding UTF8 -Append } catch {}

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

Read-Host "  Pulsa Enter para salir"
