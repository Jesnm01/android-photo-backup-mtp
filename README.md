# Copia Fotos Móvil (MTP) a PC 📱💻

Un pequeño conjunto de scripts en PowerShell y Batch para automatizar la copia de seguridad de tus fotos y vídeos desde un móvil Android a tu PC usando un cable USB, sin necesidad de nubes de terceros y sin duplicar archivos.

## 🚀 Características
- **Copia Inteligente**: Solo copia las fotos nuevas que no estén ya en el PC.
- **Filtro de Basura**: Ignora automáticamente las cachés de Android (`Android/data`), carpetas ocultas (`.thumbnails`) y los medios de WhatsApp, para asegurar que la copia sea rápida y solo de tus fotos reales.
- **Preserva Álbumes**: La estructura de carpetas (álbumes) del móvil se mantiene idéntica en el PC.
- **Doble Copia de Seguridad**: Permite copiar simultáneamente a dos discos o ubicaciones diferentes.
- **Historial de Logs**: Cada ejecución genera un informe detallado en la carpeta `Logs/` para que puedas revisar qué se ha copiado.

## 📂 Estructura de Archivos
- `CopiaFotosMovil.ps1`: El "cerebro" en PowerShell. Contiene la lógica de conexión al teléfono vía MTP (Media Transfer Protocol), el filtrado y la copia recursiva.
- `EJECUTAR_COPIA.bat`: Un lanzador rápido. Hace doble clic en él para lanzar el script sin tener que abrir la consola ni pelear con los permisos de ejecución de PowerShell.
- `Logs/`: (Generada automáticamente) Carpeta donde se guardan los resúmenes de cada copia realizada.

## ⚙️ Uso
1. Conecta el móvil al PC mediante un cable USB.
2. Desbloquea el móvil. Aparecerá una notificación o pop-up preguntando cómo quieres usar la conexión USB.
3. Selecciona **"Transferencia de archivos"** (o MTP). *Importante: no elijas "Solo carga".*
4. Haz doble clic en el archivo `EJECUTAR_COPIA.bat` (o en el acceso directo del escritorio si lo tienes).
5. Sigue las breves instrucciones en pantalla (elegir dispositivo y confirmar).

## 🛠️ Personalización
Si abres `CopiaFotosMovil.ps1` con el Bloc de notas, verás arriba un bloque `$CONFIG = @{ ... }`. Ahí puedes cambiar fácilmente:
* `Destinations`: Las rutas de tu PC donde quieres que se guarden las fotos.
* `AllowedRootFolders`: Qué carpetas del móvil quieres que se examinen (por defecto `DCIM`, `Pictures`, `Movies`).
* `ExcludePaths`: Qué subcarpetas evitar a toda costa.

## ⚠️ Limitaciones
Dado que el protocolo nativo MTP de Windows es un poco antiguo, la fecha de modificación del archivo en Windows puede cambiar a la fecha actual del día en que se hizo la copia. Sin embargo, **los metadatos EXIF reales de las fotos (fecha de captura, ubicación, etc.) se mantienen completamente intactos** al 100%.
