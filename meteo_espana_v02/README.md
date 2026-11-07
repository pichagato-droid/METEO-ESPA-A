# METEO ESPAÑA v0.2

Aplicación Flutter para Android, iOS, web y escritorio (base multiplataforma).

## Funciones implementadas en esta versión
- Tiempo actual real, previsión horaria de 24 horas y previsión de 7 días mediante Open-Meteo.
- Búsqueda de localidades españolas con geocodificación Open-Meteo.
- Ubicación opcional del dispositivo.
- Localidad seleccionada y favoritos persistentes.
- Radar de precipitación con mapa OpenStreetMap y mosaicos históricos RainViewer (si el servicio está disponible).
- Acceso a los avisos oficiales de AEMET.
- Atribuciones de las fuentes visibles en la aplicación.

## Fuentes y límites de uso
- Open-Meteo: API pública sin clave para uso no comercial, atribución CC BY 4.0 obligatoria. Para uso comercial/alto volumen hay que contratar el servicio apropiado.
- RainViewer: el API público de radar se ofrece para uso personal, educativo y pequeñas comunidades; sin SLA y con limitaciones. Antes de distribuir comercialmente la app, confirmar permiso/condiciones directamente con RainViewer. Se muestran imágenes de radar recientes, no nowcast.
- AEMET: los avisos se abren en la página oficial. La descarga e interpretación automática de avisos AEMET requiere clave API, integración backend, validación del esquema y gestión de límites; no se simula como si estuviera integrada.

## Ejecutar localmente
1. Instala Flutter SDK y Android Studio con Android SDK.
2. En la raíz:
   ```bash
   flutter create --platforms=android .
   flutter pub get
   flutter run
   ```
3. Para APK:
   ```bash
   flutter build apk --release
   ```
El APK se crea en `build/app/outputs/flutter-apk/app-release.apk`.

## Compilación automática del APK
Se incluye `.github/workflows/build-android.yml`. Sube el proyecto a un repositorio GitHub y ejecuta la acción **Build Android APK** desde la pestaña Actions. Al finalizar, descarga el artefacto `meteo-espana-release-apk`.

## Estado de publicación
El APK generado por GitHub Actions será un APK release no firmado con una clave de publicación propia. Para publicar en Google Play o distribuir actualizaciones con identidad estable, crea y protege tu keystore y configura la firma en GitHub Secrets. No compartas keystores ni contraseñas por chat.

## Pendiente para una edición comercial/publicación
- Integración automática de avisos AEMET en backend, con API key protegida.
- Confirmar licencias comerciales y SLA de proveedores de datos/mapas.
- Pruebas en varios Android físicos, accesibilidad, rendimiento y consumo de batería.
- Firma de producción, política de privacidad y ficha de Google Play.
- Compilación y prueba iOS en macOS con Xcode.
