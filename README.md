# 🐌 Refugio de Caracoles ULTRA

Juego web con dos partes:

- **Frontend** (`index.html`): HTML + CSS + JS en un solo archivo, sin dependencias externas.
  Publicado como sitio estático en GitHub Pages.
- **Backend** (`supabase/schema.sql`): base de datos Postgres en [Supabase](https://supabase.com),
  con funciones SQL que hacen de API (registro/login/guardado de progreso). Sin servidor propio
  que mantener.

## Dónde vive cada cosa desplegada

- **Juego (frontend)** → GitHub Pages: `https://ineler15.github.io/refugio-de-caracoles/`
- **API + datos de usuarios (backend)** → proyecto de Supabase (URL y `anon key` guardados en
  `SUPABASE_URL` / `SUPABASE_ANON_KEY` dentro de `index.html`).

## Cómo funciona

`index.html` llama por `fetch` a las funciones RPC del proyecto de Supabase
(`POST {SUPABASE_URL}/rest/v1/rpc/<función>`), una por cada acción:

| Acción del frontend | Función SQL       | Qué hace                                                        |
|----------------------|-------------------|------------------------------------------------------------------|
| `register`           | `register_user`   | Crea un usuario nuevo (contraseña con hash bcrypt vía `pgcrypto`). |
| `login`              | `login_user`      | Valida credenciales y devuelve el progreso guardado.              |
| `load`               | `load_progress`   | Recupera el progreso guardado de un usuario.                      |
| `save`               | `save_progress`   | Guarda el progreso actual del usuario.                            |

Las tablas (`app_users`, `app_progress`) tienen **Row Level Security activado y sin políticas**:
el `anon key` público del frontend no puede leerlas ni escribirlas directamente. Todo el acceso
pasa por esas 4 funciones (`security definer`), que validan usuario/contraseña ellas mismas —
el mismo rol que cumplía `doPost` en la versión anterior con Google Apps Script.

> El `anon key` es público a propósito (así está pensado Supabase para apps de frontend); la
> seguridad real la da el diseño de RLS + funciones, no el secreto de esa clave.

## Configurar el backend (Supabase)

1. Crea una cuenta/proyecto en [supabase.com](https://supabase.com) (puedes entrar con GitHub).
2. Abre **SQL Editor** en el proyecto y pega/ejecuta todo el contenido de `supabase/schema.sql`
   (crea las tablas, las funciones y los permisos).
3. Ve a **Project Settings → API** y copia:
   - **Project URL** → pégalo en `SUPABASE_URL` en `index.html`.
   - **anon public key** → pégalo en `SUPABASE_ANON_KEY` en `index.html`.
4. Haz commit y push de `index.html` — GitHub Pages reconstruye solo en 1–2 minutos.

## Desplegar / actualizar el frontend (GitHub Pages)

Ya está activado en este repositorio (rama `main`, carpeta raíz). Para publicar cambios:

```bash
git add index.html
git commit -m "..."
git push
```

## Cambiar el esquema de la base de datos

Edita `supabase/schema.sql` y vuelve a pegarlo/ejecutarlo en el SQL Editor del proyecto
(los `create or replace function` y `create table if not exists` son seguros de re-ejecutar).

## Notas de seguridad

- Las contraseñas nunca se guardan en texto plano: se guardan con hash **bcrypt** (`pgcrypto`,
  `crypt()` + `gen_salt('bf')`).
- El repositorio es público (requisito de GitHub Pages en el plan gratuito), pero no contiene
  credenciales: el `anon key` de Supabase está diseñado para ser público, y el acceso real a los
  datos está controlado por RLS + las funciones SQL, no por mantener esa clave en secreto.
