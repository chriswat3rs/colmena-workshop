# Colmena 🐝

Herramienta propia para workshops de design thinking en vivo. Los participantes entran con un **QR desde su celular** y hacen un onboarding rápido (nombre, área, puesto, avatar). Luego responden un **check-in**, publican sus **dolores** por etapa del proceso y **votan** repartiendo su miel. Tú, como facilitador, proyectas un **panel en vivo** con participantes, muro de tarjetas, ranking y exportación a CSV.

Todo es **un solo archivo** (`index.html`) más una base de datos gratuita en Supabase, **con autenticación**: tu cuenta está protegida con segundo factor y cada participante solo accede a lo suyo.

---

## Puesta en marcha (una sola vez, ~20 min)

### 1. Base de datos

1. En [supabase.com](https://supabase.com) crea un proyecto (plan gratuito).
2. **SQL Editor → New query** → pega TODO `setup.sql` → **Run**. Al final verás 5 tablas con `rls = true`.
   - Se puede correr las veces que quieras. Si tenías la v1 (con PIN), la reemplaza sola.

### 2. Autenticación (en el panel de Supabase)

1. **Authentication → Sign In / Providers** → activa **Allow anonymous sign-ins** → Save.
   Así los participantes entran sin crear cuenta.
2. **Authentication → Rate Limits** → sube **anonymous users** a ~300 por hora → Save.
   Toda la sala comparte el mismo internet (misma IP) y el límite por defecto es de 30 por hora.
3. **Authentication → Users → Add user → Create new user**. Pon tu correo y una contraseña larga, marca **Auto Confirm User** y da clic en **Create user**.

### 3. Conecta la app

En `index.html`, bloque `CONFIG` (al inicio del código), pega los datos del botón **Connect** de Supabase (pestaña `.env.local`):

```js
SUPABASE_URL: "https://xxxx.supabase.co",
SUPABASE_ANON_KEY: "sb_publishable_...",
```

Usa la llave **publishable**. Nunca pongas la **secret** en la página.

### 4. Publícala en GitHub Pages

1. Crea un repo nuevo `colmena-workshop` (público) y sube `index.html`, `setup.sql` y `README.md`.
2. Ve a **Settings → Pages**, elige Branch `main` y carpeta `/ (root)`, y da **Save**.
3. En 1–2 min vive en `https://TU-USUARIO.github.io/colmena-workshop/`.

### 5. Tu primer acceso

1. Abre `…/colmena-workshop/#admin` y entra con tu correo y contraseña.
2. Te pedirá **activar la verificación en dos pasos**. Escanea el QR con Microsoft Authenticator o Google Authenticator y escribe el código de 6 dígitos.
3. **La primera cuenta que activa su segundo factor queda como facilitador.** Ninguna otra cuenta puede auto-asignarse después.

Desde entonces, cada vez que entres te pedirá contraseña + código de tu app.

---

## Cómo se usa en la sala

1. En tu laptop abre `#admin`, entra y crea un taller con la plantilla **Lockton · Actua** o la genérica.
2. Con **QR para entrar** proyectas el código. La gente escanea y hace su onboarding desde el celular.
3. Tú llevas el ritmo con la barra de fases: **Lobby → Check-in → Dolores → Votación → Resultados → Cierre**. Las pantallas de todos cambian solas.
4. **Exportar CSV** descarga participantes y tarjetas con votos, autor, área y hora.
5. Al terminar, exporta y usa **Borrar taller** para no guardar datos del cliente más tiempo del necesario.

Trucos:

- **Mostrar autores** enciende o apaga los nombres en el muro proyectado.
- El código de 6 caracteres funciona sin QR: la persona entra a la liga y lo escribe.
- **Tus talleres** lista todos tus talleres para reabrirlos otro día.

---

## Seguridad: qué protege y cómo

Todas las reglas viven **en la base de datos** (políticas RLS en `setup.sql`), no en la página. Aunque alguien modifique el código o llame a la API directamente, la base solo entrega lo permitido.

| Quién | Qué puede hacer |
|---|---|
| Sin iniciar sesión (solo con la llave pública) | Nada. Toda lectura da "no autorizado". |
| Participante (anónimo) | Buscar un taller por código, unirse, ver y editar **solo su** registro. Publicar tarjetas en la fase Dolores, ver las tarjetas del taller **sin autor**, votar hasta su tope (validado en el servidor) y ver totales en Resultados. |
| Tu cuenta sin el código 2FA | Nada (aunque alguien robe tu contraseña). |
| Tu cuenta con 2FA | Crear, ver, controlar, exportar y borrar **tus** talleres. |
| Cualquier otra cuenta | Nada: no puede volverse facilitador ni ver talleres ajenos. |

Verificado con 47 pruebas de ataque directas contra la API (leer datos ajenos, suplantar, cambiar fases, votar de más, etc.): todas bloqueadas.

Límites que conviene conocer:

- Alguien que adivine un código de taller activo podría unirse como participante más. Hay ~887 millones de combinaciones, y puedes borrar o cerrar el taller al terminar.
- No captures datos sensibles (salarios, información personal de empleados) en las tarjetas.

### Tareas de mantenimiento (SQL Editor)

Agregar otro facilitador (primero créalo en Authentication → Users):

```sql
insert into ws_admins (user_id, email)
select id, email from auth.users where email = 'correo@empresa.com';
```

Si perdiste tu celular, reinicia tu segundo factor. Al entrar de nuevo te pedirá activarlo con un QR nuevo:

```sql
delete from auth.mfa_factors
where user_id = (select id from auth.users where email = 'tu-correo@empresa.com');
```

---

## Estructura

| Archivo | Qué es |
|---|---|
| `index.html` | Toda la app: participante (móvil) + panel del facilitador. Incluye la librería de Supabase y el generador de QR, sin depender de CDNs. |
| `setup.sql` | Esquema, reglas de seguridad y tiempo real (re-ejecutable). |
| `README.md` | Esta guía. |

Sin `SUPABASE_URL`, la app corre en **modo demo**: todo funciona en tu navegador y sin cuentas, útil para enseñarla o probar cambios.
