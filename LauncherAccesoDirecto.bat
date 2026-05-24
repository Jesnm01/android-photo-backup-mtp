@echo off
:: Lanzador .bat para CopiaFotosMovil.ps1
:: Se puede colocar como ruta de un acceso directo
:: Para cambiar las rutas de copiado, modificar el archivo "EJECUTAR_COPIA.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "EJECUTAR_COPIA.ps1"
pause
