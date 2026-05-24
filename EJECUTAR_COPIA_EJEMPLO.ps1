# EJEMPLO DE LANZADOR
# Renombra este archivo a "EJECUTAR_COPIA.ps1" e introduce tus propias rutas en la linea de abajo

$destinos = @(
    "C:\MiCopiaFotos",
    "D:\OtraCopiaFotos"
)

& "$PSScriptRoot\CopiaFotosMovil.ps1" -Destinos $destinos

# Para uso automatico (sin preguntas):
# & "$PSScriptRoot\CopiaFotosMovil.ps1" -Destinos $destinos -Auto -DeviceIndex 1 -StorageIndex 1 -NoPause
