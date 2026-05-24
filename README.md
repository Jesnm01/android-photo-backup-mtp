# Copia Fotos Móvil (MTP) a PC

Script en PowerShell para hacer copias incrementales de fotos y vídeos desde Android por USB (MTP), preservando carpetas y evitando duplicados típicos.

## Qué hace bien este script
- Copia incremental: evita recopiados cuando el archivo ya existe y coincide.
- Preserva estructura: mantiene tu organización (`DCIM`, `Pictures`, etc.).
- Filtra basura: excluye rutas no deseadas (`Android`, `WhatsApp`, `.thumbnails`, etc.).
- Multi-destino: copia en una misma ejecución a varios discos o rutas.
- Separa por móvil: crea subcarpeta por dispositivo dentro de cada destino para no mezclar móviles.
- Log persistente: va escribiendo durante todo el proceso.
- Benchmark siempre activo: muestra y registra `MB copiados`, `Archivos/min` y `MB/s aprox`.

## Estructura
- `CopiaFotosMovil.ps1`: script principal.
- `EJECUTAR_COPIA.ps1`: lanzador con tus rutas privadas.
- `EJECUTAR_COPIA_EJEMPLO.ps1`: plantilla.
- `LauncherAccesoDirecto.bat`: lanzador por doble clic.
- `Logs/`: se crea automáticamente.

## Flujo de uso recomendado
1. Conecta el móvil por USB.
2. Desbloquéalo y elige modo **Transferencia de archivos (MTP)**.
3. Ejecuta `LauncherAccesoDirecto.bat` o `EJECUTAR_COPIA.ps1`.
4. En modo interactivo, elige dispositivo, almacenamiento y confirma.

## Parámetros del script
`CopiaFotosMovil.ps1` acepta:
- `-Destinos <string[]>`: rutas base de copia.
- `-Auto`: evita preguntas; selecciona por índice.
- `-DeviceIndex <int>`: dispositivo a usar en `-Auto` (base 1).
- `-StorageIndex <int>`: almacenamiento a usar en `-Auto` (base 1).
- `-NoPause`: no espera Enter al finalizar.
- `-ShowSkipped`: muestra cada archivo omitido por duplicado.

La versión visible del script está en la variable `$SCRIPT_VERSION` dentro de `CopiaFotosMovil.ps1` y se imprime al inicio de cada ejecución y en el log.

Ejemplo automático:

```powershell
& "$PSScriptRoot\CopiaFotosMovil.ps1" `
  -Destinos @("C:\BackupFotos","D:\BackupFotos") `
  -Auto -DeviceIndex 1 -StorageIndex 1 -NoPause
```

## Duplicados y conflictos
- Regla principal: si en destino existe archivo con mismo nombre/ruta relativa y mismo tamaño, se considera duplicado.
- Si MTP no da tamaño fiable, se usa fallback por fecha.
- Esto reduce al mínimo los popups de conflicto nativos de Windows en ejecuciones periódicas.

## Separación por dispositivo
Dentro de cada destino se crea una carpeta con el nombre del móvil (saneado para Windows).

Ejemplo:
- Destino base: `D:\FotosRespaldo`
- Dispositivo: `Pixel_8`
- Ruta final: `D:\FotosRespaldo\Pixel_8\DCIM\Camera\...`

## Si se interrumpe a mitad
- Los archivos ya copiados se mantienen.
- El log ya escrito se mantiene (se escribe línea a línea).
- Puede faltar solo el resumen final si se corta antes de terminar.

## Configuración interna útil
En el bloque `$CONFIG` del script:
- `AllowedRootFolders`: carpetas raíz del móvil a escanear.
- `ExcludePaths`: rutas a excluir.
- `Extensions`: extensiones permitidas.
- `CopyTimeoutSeconds`: timeout por archivo.

## Mejoras futuras sugeridas
- Modo `-DryRun` (simulación sin copiar).
- Exportar resumen CSV o JSON de cada ejecución.
- Reintentos automáticos para fallos puntuales de MTP.
- Integración con Programador de tareas de Windows para ejecución periódica.

## Limitaciones de MTP
- MTP en Windows no siempre expone metadatos de forma consistente.
- El rendimiento depende mucho de cable, puerto USB y tamaño medio de archivo.
- EXIF interno de fotos se conserva, aunque Windows pueda mostrar fechas de modificación distintas.
