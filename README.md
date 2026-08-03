# 🐌 Refugio de Caracoles ULTRA

Juego web con dos partes:

- **Frontend** (`index.html`): HTML + CSS + JS en un solo archivo, sin dependencias externas.
  Se juega directamente desde el navegador y habla con el backend por `fetch`.
- **Backend** (`Code.gs`, Google Apps Script): API para registro/login y guardado del progreso
  de cada usuario como JSON en una carpeta de Google Drive.

El frontend no usa `google.script.run` (la API que solo funciona embebida dentro de Apps
Script) sino `fetch()` directo contra la URL pública del backend desplegado. Por eso `index.html`
es un archivo estático normal que se puede alojar en cualquier sitio — incluido **GitHub Pages**
— sin depender de que Apps Script lo sirva.

## Estructura del proyecto

| Archivo      | Rol                                                                                   |
|--------------|----------------------------------------------------------------------------------------|
| `Code.gs`    | Backend (Apps Script). Expone la API (`doPost`) para registro/login y guardado de progreso; `doGet` sirve además el juego como vía alternativa. |
| `index.html` | Frontend completo del juego, publicado en GitHub Pages y también servido por `doGet`.   |

## Dónde vive cada cosa desplegada

- **Juego (frontend)** → GitHub Pages: `https://ineler15.github.io/refugio-de-caracoles/`
- **API + datos de usuarios (backend)** → Google Apps Script (URL `/exec` propia, guardada en
  `APPS_SCRIPT_URL` dentro de `index.html`) + una carpeta de Google Drive (`FOLDER_ID` en
  `Code.gs`).

GitHub Pages **solo sirve archivos estáticos**: no puede ejecutar `Code.gs` (usa `DriveApp`,
`LockService`, etc., exclusivos de Apps Script). Por eso el backend sigue — y debe seguir —
desplegado en Apps Script; GitHub Pages únicamente aloja el HTML/JS que llama a ese backend.

## Cómo funciona

- **`doPost`**: API usada por `index.html` (vía `fetch`, con `Content-Type: text/plain` para
  evitar el preflight `OPTIONS` que Apps Script no maneja) con las acciones:
  - `register` — crea un usuario nuevo (contraseña guardada como hash SHA-256 con salt único).
  - `login` — valida credenciales y devuelve el progreso guardado.
  - `load` — recupera el progreso guardado de un usuario.
  - `save` — guarda el progreso actual del usuario.
- Los datos (`usuarios.json` y `progreso.json`) se guardan en una carpeta de **Google Drive**,
  identificada por `FOLDER_ID` en `Code.gs`.
- **`doGet`**: devuelve `index.html` como vía alternativa para abrir el juego directamente desde
  la URL del despliegue de Apps Script (útil si GitHub Pages no estuviera disponible).

## Desplegar / actualizar el frontend (GitHub Pages)

Ya está activado en este repositorio (rama `main`, carpeta raíz). Para publicar cambios:

```bash
git add index.html
git commit -m "..."
git push
```

GitHub Pages reconstruye el sitio automáticamente en 1–2 minutos tras cada push a `main`.

## Desplegar / actualizar el backend (Google Apps Script)

`Code.gs` (y opcionalmente `index.html`, si quieres que `doGet` sirva la versión más reciente)
se llevan a Apps Script por separado — un push a GitHub **no** actualiza el backend. Dos formas:

### Opción A — Copiar y pegar manualmente

1. Entra a [script.google.com](https://script.google.com) y abre el proyecto existente del
   Refugio de Caracoles (o crea uno nuevo).
2. Copia el contenido de `Code.gs` al archivo de script del proyecto.
3. Si también quieres actualizar la copia servida por `doGet`, pega el contenido de
   `index.html` en el archivo HTML del proyecto llamado **`index`** (Apps Script no distingue
   mayúsculas/minúsculas al crearlo, pero debe llamarse igual a como lo referencia `doGet`).
4. Verifica que `FOLDER_ID` apunte a la carpeta de Drive correcta para guardar `usuarios.json`
   y `progreso.json`.
5. **Implementar → Nueva implementación → Aplicación web**:
   - Ejecutar como: *Yo (tu cuenta)*.
   - Quién tiene acceso: según lo que necesites (p. ej. *Cualquier usuario*).
6. Si la URL de despliegue cambiara, actualiza `APPS_SCRIPT_URL` en `index.html`.

### Opción B — Usando `clasp` (CLI oficial de Apps Script)

```bash
npm install -g @google/clasp
clasp login
clasp create --type webapp --title "Refugio de Caracoles ULTRA"   # solo la primera vez
# o, si ya existe un proyecto: clasp clone <scriptId>
clasp push      # sube Code.gs e index.html al proyecto de Apps Script
clasp deploy    # crea/actualiza el despliegue como aplicación web
```

> El archivo `.clasp.json` (que guarda el `scriptId` de tu proyecto) está excluido del
> repositorio vía `.gitignore`, porque es específico de cada cuenta/proyecto de Google.

## Notas de seguridad

- Las contraseñas nunca se guardan en texto plano: se guarda un hash SHA-256 con una sal (salt)
  única por usuario.
- El repositorio es público (requisito de GitHub Pages en el plan gratuito), pero no contiene
  credenciales: `FOLDER_ID` es solo un identificador de carpeta de Drive y no otorga acceso por
  sí solo — el control real de acceso lo dan los permisos de la carpeta en Drive.
