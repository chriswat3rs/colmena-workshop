# Colmena · Quality & Knowledge

Herramienta propia para workshops de design thinking en vivo.

- **Participantes:** entran con un **QR desde su celular** y se registran (nombre, área, rol, etapas en las que participan y avatar).
- **Recorrido del taller:**
  1. **Check-in.**
  2. **Dolores:** cada quien los publica por etapa del proceso y herramienta.
  3. **Votación:** reparten sus votos entre los dolores.
  4. **Validación:** califican las mejoras que ya se habían identificado (quick wins), las reglas del nuevo flujo y cuánto tarda hoy cada etapa; proponen las mejoras que falten.
  5. **Ideas:** «¿Cómo podríamos…?» sobre los 3 dolores más votados, con apoyos.
- **Tú, como facilitador:** proyectas un **panel en vivo** con participantes, muro, ranking, tabla de quick wins, ideas por reto y un menú **Compartir** (Excel, CSV o PDF, por descarga o correo).

**Identidad:** imagotipo y logotipo de Quality & Knowledge, colores corporativos (azul `#278FD8`, marino `#01133B`), tipografía Montserrat y modo claro. Usa iconos planos propios (glifos SVG sobre un fondo suave) para estados de ánimo e indicadores. Los avatares son animales, y la abeja de Colmena acompaña al imagotipo de Quality & Knowledge en la portada y en el QR.

Todo es **un solo archivo** (`index.html`) más una base de datos gratuita en Supabase, **con autenticación**: tu cuenta está protegida con segundo factor y cada participante solo accede a lo suyo.

**Roles (v1.5):** hay dos tipos de cuenta en el panel.

| Rol | Qué puede hacer |
|---|---|
| **Admin** | Crea y opera sus propios talleres. Ve **todos** los talleres del equipo en **solo lectura** (panel, resultados, Presentar y Compartir/exportar), pero no cambia fases, no borra ni muestra el QR de talleres ajenos. Invita personas, las activa/desactiva y cambia su rol. |
| **Facilitador** | Crea y opera **solo sus** talleres. No ve los de nadie más ni la sección Equipo. |

La primera cuenta que activó su segundo factor queda como **admin**. Las demás entran **solo por invitación**.

---

## Puesta en marcha (una sola vez, ~20 min)

### 1. Base de datos

1. En [supabase.com](https://supabase.com) crea un proyecto (plan gratuito).
2. **SQL Editor → New query** → pega TODO `setup.sql` → **Run**. Al final verás 8 tablas con `rls = true`.
   - Se puede correr las veces que quieras. Si tenías la v1 (con PIN), la reemplaza sola.
   - Si tenías la v1.1, la actualiza **sin borrar** tu cuenta, tus talleres ni lo capturado.

### 2. Autenticación (en el panel de Supabase)

1. **Authentication → Sign In / Providers** → activa **Allow anonymous sign-ins** → Save.
   Así los participantes entran sin crear cuenta.
   - En la misma pantalla (sección **Email**, v1.5): deja encendido **Allow new users to sign up** y **apaga Confirm email** → Save.
     Así tus invitados crean su cuenta desde la app sin esperar un correo (el correo gratuito de Supabase solo llega a miembros de tu organización en Supabase). Registrarse sin una invitación válida no da ningún permiso.
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
3. **La primera cuenta que activa su segundo factor queda como admin.** Ninguna otra cuenta puede auto-asignarse después: las demás necesitan una invitación.

Desde entonces, cada vez que entres te pedirá contraseña + código de tu app.

### 6. Invita a tus facilitadores (v1.5)

1. En el panel, pestaña **Equipo** → **Invitar a alguien**: nombre (opcional), correo y rol (**Facilitador** o **Admin**) → **Crear invitación**.
2. Copia el enlace o usa **Enviar por correo** (abre tu correo con el mensaje y los pasos listos).
3. La persona abre el enlace, crea su contraseña con **ese mismo correo** y activa su verificación en dos pasos. Al terminar ya ve su panel.

Cada invitación sirve **una sola vez**, **solo con ese correo** y **vence en 7 días**. Por seguridad el enlace se muestra solo al crearlo; si se pierde, crea otra (la nueva cancela la anterior). En **Invitaciones pendientes** puedes cancelarlas.

En **Equipo** también ves a todas las cuentas con cuántos talleres tiene cada una, y puedes:

- **Desactivar / Reactivar:** quien está desactivado ya no entra al panel ni ve sus talleres; sus talleres y lo capturado se conservan y tú los sigues viendo.
- **Hacer admin / Hacer facilitador.** Nadie puede cambiar su propia cuenta.

En **Todos los talleres** filtras por facilitador o buscas por nombre o código. **Abrir** te lleva a los tuyos; **Ver** abre los ajenos en solo lectura (lo indica la etiqueta amarilla «Solo lectura · Nombre»).

---

## Cómo se usa en la sala

1. En tu laptop abre `#admin`, entra y crea un taller con la plantilla **Lockton · Actua** o la genérica.
2. Con **QR para entrar** proyectas el código. La gente escanea y hace su registro desde el celular.
3. Tú llevas el ritmo con la barra de fases. Nada avanza solo: las pantallas de todos cambian cuando das clic.

| Fase | En el celular | En el panel proyectado |
|---|---|---|
| 1. Lobby | Registro: nombre, área, rol, etapas, avatar; mapa del proceso con sus etapas marcadas | Tabla de quién entró (con rol y etapas) |
| 2. Check-in | Ánimo y expectativa | Misma tabla con respuestas |
| 3. Dolores | Tarjetas con etapa, actividad y herramienta (opcionales) y qué tanto duele; «No tengo más por ahora» cuando termina | Muro en vivo agrupado por etapa |
| 4. Votación | Reparte sus votos (tope validado en el servidor); al usar el último queda listo | Ranking en vivo |
| 5. Validación | Tres pasos: quick wins (Mucho / Algo / Poco / No aplica), reglas del nuevo flujo (Ayuda / Me da igual / Estorba / No me toca) y tiempos por etapa (4 rangos); primero lo de sus etapas; al final propone mejoras nuevas | Filas por quick win (mucho · algo · poco) con índice 0–100, reglas en barras divergentes, tiempos en tira de proceso, propuestas nuevas |
| 6. Ideas | «¿Cómo podríamos…?» para los 3 dolores más votados; apoya hasta 3 ideas ajenas; «Terminé con Ideas» | Ideas por reto con un hexágono por apoyo |
| 7. Resultados | Top de dolores, ideas, quick wins, reglas y tiempos; nota de cierre | Titular (el dolor más votado + 4 datos clave) y cinco secciones numeradas; contexto plegado; botón **Presentar** (pantalla completa, una sección por pantalla, flechas o clicker, Esc para salir) |
| 8. Cierre | Agradecimiento | Igual que Resultados |

**Orientación en el celular (v1.4).** Arriba siempre se ve «Actividad N de 5 · Nombre», los 5 segmentos y el estado (En curso / Listo ✓). Al abrir una actividad aparece un aviso de qué hacer. Cuando alguien termina, ve «X de N ya terminaron» y qué sigue; tú ves lo mismo en la barra de fases («X de N listos con …») para decidir cuándo avanzar. Lo que escriben se guarda como borrador en el celular: si cambias de fase antes de que lo publiquen, se les avisa y pueden copiarlo.

**Pocos datos.** Con menos de 3 personas votando o calificando, el panel muestra conteos y unidades (hexágonos) en lugar de índices, porcentajes o barras al 100 %, y declara los empates en vez de coronar un ganador.

4. **Compartir** (arriba a la derecha) arma los resultados en el formato que elijas:
   - **Excel (.xlsx):** una hoja por tabla (Taller, Participantes, Etapas por participante, Dolores, Votos, Validación · respuestas, Validación · resumen, Ideas, Apoyos, Quick wins propuestos, Resumen por etapa) más una hoja «Léeme» con el diccionario de cada columna. Encabezado fijo, filtros y formato de tabla para tablas dinámicas.
   - **CSV (.zip):** las mismas tablas, un CSV por tabla (UTF-8, coma, punto decimal, fechas `AAAA-MM-DD HH:MM:SS`, 1/0 para sí/no), con `LEEME.txt` y `00_diccionario.csv`.
   - **PDF:** reporte con gráficas (titular, dolores, ideas, quick wins, reglas, tiempos y contexto).
   - **Por correo:** en celulares y Mac con Safari abre el menú de compartir con el archivo adjunto; en los demás equipos descarga el archivo y abre tu correo con el mensaje listo para adjuntarlo.
   - **Anonimizar participantes** cambia los nombres por P01, P02… (útil para enviarlo al cliente).
   - Los IDs (P01, D01, I01, QW-01…) permiten cruzar las tablas. El PDF usa `jspdf.umd.min.js` (jsPDF, licencia MIT, en la raíz del repo) y solo se descarga al pedir un PDF.
5. Al terminar, exporta y usa **Borrar taller** para no guardar datos del cliente más tiempo del necesario.

### Configurar un taller (formulario «Crear taller nuevo»)

- **Áreas** y **Etapas del proceso**: una por línea.
- En **Perfil, herramientas y quick wins**:
  - **Roles**: uno por línea (vacío = el participante escribe su puesto).
  - **Herramientas por etapa**: `Etapa | herramienta 1, herramienta 2`. La etapa debe escribirse igual que en la lista de etapas. Siempre se agregan «Correo / Teams», «Excel propio» y «Otra».
  - **Listas a validar**: `Etapa | texto`, uno por línea, en secciones `## Quick wins` (QW-01…), `## Reglas` (RG-01…) y `## Tiempos` (TM-01…). Se numeran solos.
  - **Actividades por etapa** (opcional): `Etapa | actividad; actividad`. Cada dolor puede señalar la actividad exacta.
  - **Pregunta de ideas** y **apoyos por persona**.
- La plantilla **Lockton · Actua** ya trae las 8 etapas, herramientas y 19 quick wins de la lámina «Proceso de Valuación Actuarial» del cliente.

Trucos:

- **Mostrar autores** enciende o apaga los nombres en el muro proyectado.
- El código de 6 caracteres funciona sin QR: la persona entra a la liga y lo escribe.
- **Tus talleres** lista todos tus talleres para reabrirlos otro día. Si eres admin, **Todos los talleres** muestra también los del equipo.

---

## Seguridad: qué protege y cómo

Todas las reglas viven **en la base de datos** (políticas RLS en `setup.sql`), no en la página. Aunque alguien modifique el código o llame a la API directamente, la base solo entrega lo permitido.

| Quién | Qué puede hacer |
|---|---|
| Sin iniciar sesión (solo con la llave pública) | Nada. Toda lectura da "no autorizado". |
| Participante (anónimo) | Buscar un taller por código, unirse, ver y editar **solo su** registro. Publicar tarjetas en la fase Dolores, ver las tarjetas del taller **sin autor** y votar hasta su tope (validado en el servidor). Calificar quick wins solo en su fase, ver solo sus propias calificaciones y proponer mejoras que solo ve el facilitador. En Ideas: publicar ideas para los retos y apoyar hasta su tope (no las propias). Los totales se ven solo en Resultados. |
| Tu cuenta sin el código 2FA | Nada (aunque alguien robe tu contraseña). |
| Facilitador con 2FA | Crear, ver, controlar, exportar y borrar **sus** talleres. No ve talleres, cuentas ni invitaciones de nadie más. |
| Admin con 2FA | Lo mismo con sus talleres, más **ver y exportar** (sin modificar) los talleres de todos, y administrar cuentas e invitaciones. |
| Cuenta desactivada | Nada. |
| Cualquier otra cuenta | Nada: sin una invitación válida para **su** correo no puede volverse facilitador ni ver talleres. |

Verificado con 96 pruebas de ataque directas contra la API: leer datos ajenos, suplantar, cambiar fases, votar de más, calificar o proponer fuera de fase, apoyar la idea propia o pasarse del tope, etc. Todas bloqueadas.

v1.5: 67 pruebas más de roles e invitaciones (un facilitador no ve talleres ajenos ni con el código, el admin no puede cambiar ni borrar talleres ajenos, invitaciones usadas, vencidas, canceladas o con otro correo rechazadas, nadie se sube de rol editando la tabla, cuentas desactivadas sin acceso). Todas correctas.

Límites que conviene conocer:

- Alguien que adivine un código de taller activo podría unirse como participante más. Hay ~887 millones de combinaciones, y puedes borrar o cerrar el taller al terminar.
- No captures datos sensibles (salarios, información personal de empleados) en las tarjetas.

### Actualizar desde una versión anterior

`setup.sql` se puede volver a correr completo sin perder datos (todo es `if not exists` / `create or replace`). Si vienes de v1.3, basta con correr el bloque marcado **v1.4** (columna `done_phases` y función `ws_phase_progress`).

**De v1.4 a v1.5 (roles):** corre `setup.sql` completo otra vez. Tu cuenta (la primera facilitadora) pasa sola a **admin** y tus talleres se conservan. Luego haz el ajuste de **Confirm email** del paso 2 y sube el nuevo `index.html`.

### Tareas de mantenimiento (SQL Editor)

Agregar facilitadores: usa **Equipo → Invitar a alguien** en el panel (ya no hace falta SQL).

Si te quedaste sin ningún admin activo, recupera el rol desde el SQL Editor:

```sql
update ws_admins set role = 'admin', active = true
where email = 'tu-correo@empresa.com';
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
| `setup.sql` | Esquema, reglas de seguridad y tiempo real (re-ejecutable; actualiza versiones anteriores sin borrar datos). |
| `README.md` | Esta guía. |

Sin `SUPABASE_URL`, la app corre en **modo demo**: todo funciona en tu navegador y sin cuentas, útil para enseñarla o probar cambios.
