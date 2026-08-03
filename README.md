# 🐌 Refugio de Caracoles ULTRA

Juego web implementado como **Google Apps Script Web App**: un "backend + frontend" que corre
sobre la infraestructura de Google (sin necesidad de hosting propio).

## Estructura del proyecto

| Archivo     | Rol                                                                                   |
|-------------|----------------------------------------------------------------------------------------|
| `Code.gs`   | Backend (Apps Script). Sirve el HTML (`doGet`) y expone una API (`doPost`) para registro/login y guardado de progreso de cada usuario como JSON en Google Drive. |
| `Index.html`| Frontend completo del juego (HTML + CSS + JS en un solo archivo), servido por `doGet`.  |

## Cómo funciona

- **`doGet`**: devuelve `Index.html` como la página del juego, para poder abrirla directamente
  desde la URL del despliegue.
- **`doPost`**: API usada por el propio HTML (vía `fetch`) con las acciones:
  - `register` — crea un usuario nuevo (contraseña guardada como hash SHA-256 con salt único).
  - `login` — valida credenciales y devuelve el progreso guardado.
  - `load` — recupera el progreso guardado de un usuario.
  - `save` — guarda el progreso actual del usuario.
- Los datos (`usuarios.json` y `progreso.json`) se guardan en una carpeta de **Google Drive**,
  identificada por `FOLDER_ID` en `Code.gs`.

## Desplegar / actualizar en Google Apps Script

Este repositorio contiene el código fuente; el despliegue en sí ocurre en Google Apps Script.
Hay dos formas de llevar estos archivos allá:

### Opción A — Copiar y pegar manualmente

1. Entra a [script.google.com](https://script.google.com) y crea un proyecto nuevo (o abre el
   proyecto existente del Refugio de Caracoles).
2. Copia el contenido de `Code.gs` al archivo de script del proyecto.
3. Crea un archivo HTML llamado **`Index`** (así, sin extensión, Apps Script la añade solo) y
   pega el contenido de `Index.html`.
4. Verifica que `FOLDER_ID` apunte a la carpeta de Drive correcta para guardar `usuarios.json`
   y `progreso.json`.
5. **Implementar → Nueva implementación → Aplicación web**:
   - Ejecutar como: *Yo (tu cuenta)*.
   - Quién tiene acceso: según lo que necesites (p. ej. *Cualquier usuario*).
6. Copia la URL de la implementación: esa es la URL del juego.

### Opción B — Usando `clasp` (CLI oficial de Apps Script)

```bash
npm install -g @google/clasp
clasp login
clasp create --type webapp --title "Refugio de Caracoles ULTRA"   # solo la primera vez
# o, si ya existe un proyecto: clasp clone <scriptId>
clasp push      # sube Code.gs e Index.html al proyecto de Apps Script
clasp deploy    # crea/actualiza el despliegue como aplicación web
```

> El archivo `.clasp.json` (que guarda el `scriptId` de tu proyecto) está excluido del
> repositorio vía `.gitignore`, porque es específico de cada cuenta/proyecto de Google.

## Notas de seguridad

- Las contraseñas nunca se guardan en texto plano: se guarda un hash SHA-256 con una sal (salt)
  única por usuario.
- `FOLDER_ID` identifica la carpeta de Drive donde se guardan los datos de los usuarios; este
  repositorio es **privado** porque ese valor, junto con el resto del código, da contexto sobre
  dónde vive esa información.
