# EJEMPLO DE LANZADOR
# Renombra este archivo a "EJECUTAR_COPIA.bat" e introduce tus propias rutas en la linea de abajo

$destinos = @(
    "C:\MiCopiaFotos",
    "D:\OtraCopiaFotos"
)

& "$PSScriptRoot\CopiaFotosMovil.ps1" -Destinos $destinos