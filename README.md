# VersoVivo

App Flutter (web + Android + iPhone) para generar un versiculo diario segun tu tema, con entrada por texto o voz, lectura en voz alta y botones para compartir.

## Caracteristicas

- UI responsive con estilo premium.
- Pregunta principal: `Sobre que quieres que trate el versiculo de hoy?`
- Entrada por texto y por microfono.
- Lectura de versiculo con TTS.
- Seleccion de versiculo de aproximadamente 30 palabras segun tema detectado.
- Botones de compartir:
  - `Comparte la app con tus amig@s`
  - `Comparte este versiculo con tus amigos`
- Iconos completos para Android, iOS y web (incluye favicon).

## Comandos

### 1) Ver cambios en local (hot reload)

```powershell
.\tools\previsualizar.ps1
```

### 2) Publicar preproduccion bajo demanda

```powershell
.\tools\actualizar-preproduccion.ps1 -Mensaje "deploy(pre): ajustes de UI"
```

### 3) Publicar produccion bajo demanda

```powershell
.\tools\actualizar-produccion.ps1 -Mensaje "deploy(prod): release estable"
```

## Flujo recomendado

1. Trabajas localmente con `previsualizar.ps1` y haces todos los cambios que quieras sin desplegar cada guardado.
2. Cuando quieres revisar online, ejecutas `actualizar-preproduccion.ps1`.
3. Cuando ya esta aprobado, cambias a `main` y ejecutas `actualizar-produccion.ps1`.

## Siempre online aunque apagues la compu

Para que la web quede activa 24/7:

1. Crea el proyecto en Cloudflare Pages con nombre `verso-vivo`.
2. En GitHub, agrega secretos del repo:
   - `CLOUDFLARE_API_TOKEN`
   - `CLOUDFLARE_ACCOUNT_ID`
3. El workflow `.github/workflows/deploy-web.yml` hace el build y deploy automatico en cada push a `preproduccion` o `main`.

## Notas

- Actualiza los links de tiendas en `lib/main.dart` cuando publiques en Play Store y App Store.
- Si el repo aun no tiene git remoto, configura `origin` antes de ejecutar scripts de deploy.

