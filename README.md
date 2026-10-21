# Colmena · Quality & Knowledge

Herramienta propia para talleres en vivo: design thinking («Mejora de procesos», el de siempre) y, desde la v2.0, Definir competencias, Diagnóstico, Lluvia de ideas y Retrospectiva.

- **Participantes:** entran con un **QR desde su celular** y se registran (nombre, área, rol, etapas en las que participan y avatar).
- **Recorrido del taller:**
  1. **Check-in.**
  2. **Dolores:** cada quien los publica por etapa del proceso y herramienta.
  3. **Votación:** reparten sus votos entre los dolores.
  4. **Validación:** califican las mejoras que ya se habían identificado (quick wins), las reglas del nuevo flujo y cuánto tarda hoy cada etapa; proponen las mejoras que falten.
  5. **Ideas:** «¿Cómo podríamos…?» sobre los 3 dolores más votados, con apoyos.
- **Otros tipos de taller (v2.0):** mismas fases, mismo celular y misma consola; cambian las palabras, las preguntas y lo que te llevas al final.
- **Tú, como facilitador:** proyectas un **panel en vivo** con participantes, muro, ranking, tabla de quick wins, ideas por reto y un menú **Compartir** (Excel, CSV o PDF, por descarga o correo).

**Identidad:** imagotipo y logotipo de Quality & Knowledge, colores corporativos (azul `#278FD8`, marino `#01133B`), Montserrat para lectura y Bricolage Grotesque para títulos. Usa iconos planos propios (glifos SVG sobre un fondo suave) para estados de ánimo e indicadores. Los avatares son animales, y la abeja de Colmena acompaña al imagotipo de Quality & Knowledge en la portada y en el QR.

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
2. **SQL Editor → New query** → pega TODO `setup.sql` → **Run**. Al final sale una fila: `version = 2.3.2` y el mismo número en `tablas` y `con_seguridad` (todas las tablas con seguridad activa).
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
2. Al dar clic en **Crear y enviar invitación**, a la persona **le llega directo** un correo con diseño (Colmena + Quality & Knowledge) y el botón **Crear mi cuenta**. Lo envía la función `send-invite` por Resend (ver «Envío automático de invitaciones» abajo). Tienes **Vista previa**, **Reenviar** y **Copiar enlace**; si el envío falla, se abre **Enviarla yo desde mi correo** (copiar correo con diseño → abrir tu correo → pegar). El correo usa las imágenes de la carpeta `email/` del sitio publicado, así que esa carpeta debe estar en el repo.
3. La persona abre el enlace, crea su contraseña con **ese mismo correo** y activa su verificación en dos pasos. Al terminar ya ve su panel.

Cada invitación sirve **una sola vez**, **solo con ese correo** y **vence en 7 días**. Por seguridad el enlace se muestra solo al crearlo; si se pierde, crea otra (la nueva cancela la anterior). En **Invitaciones pendientes** puedes cancelarlas.

En **Equipo** también ves a todas las cuentas con cuántos talleres tiene cada una, y puedes:

- **Desactivar / Reactivar:** quien está desactivado ya no entra al panel ni ve sus talleres; sus talleres y lo capturado se conservan y tú los sigues viendo.
- **Hacer admin / Hacer facilitador.** Nadie puede cambiar su propia cuenta.

**Foto de perfil:** cada quien da clic en su nombre (arriba a la derecha) → **Subir foto**. Se recorta en cuadrado y se guarda ligera (~10 KB) en la base; aparece en el encabezado, en **Equipo** y en **Todos los talleres**. Nadie puede cambiar la foto de otra persona. Si ya tenías la v1.5 instalada, corre `migracion-v15-foto.sql` (o `setup.sql` completo).

En **Todos los talleres** filtras por facilitador o buscas por nombre o código. **Abrir** te lleva a los tuyos; **Ver** abre los ajenos en solo lectura (lo indica la etiqueta amarilla «Solo lectura · Nombre»).

### 7. Envío automático de invitaciones (Resend, una sola vez, ~15 min)

1. **Resend:** crea tu cuenta en [resend.com](https://resend.com) (gratis hasta 3,000 correos al mes).
2. **Dominio:** Resend → **Domains → Add domain** con el dominio de QK (p. ej. `qacg.com`). Resend te da 3 registros (MX, TXT/SPF y DKIM): pídeselos a quien administra el DNS del dominio. Cuando salga **Verified**, ya puedes enviar a cualquier correo.
3. **Llave:** Resend → **API Keys → Create API key** (permiso *Sending access*). Cópiala (empieza con `re_`).
4. **Función en Supabase:** **Edge Functions → Deploy a new function → Via Editor**, nombre `send-invite`, pega todo `supabase/functions/send-invite/index.ts` y da **Deploy**. Deja activado **Verify JWT**.
5. **Secretos:** **Edge Functions → Secrets → Add new secret**:
   - `RESEND_API_KEY` = la llave `re_…`
   - `INVITE_FROM` = `Colmena · Quality & Knowledge <colmena@qacg.com>` (con tu dominio verificado)
6. Prueba: en **Equipo** invita a un correo tuyo. Debe decir «Invitación enviada».

La función solo envía si quien la llama es **admin con segundo factor** y el destinatario tiene una **invitación vigente**: no sirve para mandar correos a cualquiera. Las respuestas al correo llegan a quien invitó (reply-to).

### 8. Centro de notificaciones (v1.6)

La **campana** (arriba a la derecha, también dentro del panel del taller) muestra cuántos avisos tienes sin leer. Al abrirla: pestañas **No leídas / Todas**, agrupadas en *Hoy · Esta semana · Antes*, cada aviso con su botón de acción y **Marcar todo como leído**. Si llega uno con la app abierta, aparece un aviso discreto y el contador sube solo.

| Para | Aviso | Canal |
|---|---|---|
| Admin | Alguien aceptó tu invitación | App + correo |
| Admin | Una invitación vence mañana / venció sin usarse | App |
| Admin | Un facilitador creó / cerró un taller | App |
| Todos | Cambió tu rol · reactivaron tu acceso | App + correo |
| Todos | Bienvenida al activar la cuenta | App |
| Facilitador | Todos terminaron la actividad en curso | App |
| Facilitador | Un taller lleva 30 días cerrado (exporta y borra) | App + correo |

- Los avisos los crea la **base de datos** (disparadores + una revisión diaria a las 9:00 de CDMX): nadie puede inventarlos y llegan aunque la app esté cerrada. Se borran solos a los 90 días.
- Los correos salen de una **bandeja de salida** que la función `send-notifications` envía cada 5 minutos (con reintentos) usando los mismos secretos que las invitaciones.
- Cada quien apaga los correos que no quiera en **su perfil → Correos de avisos**.
- Instalación: corre `migracion-v16-notificaciones.sql` (o `setup.sql` completo), despliega `supabase/functions/send-notifications` con **Verify JWT apagado** (la llama la tarea programada; solo envía lo que ya está en la bandeja, a su destinatario).

### 9. Inicio, perfil y creador paso a paso (v1.7)

- **Inicio** (pestaña por defecto): saludo según la hora, **Ahora mismo** (talleres en curso con participantes y avance, con «Ir al taller»), **Acciones rápidas** y **Pendientes** (invitaciones por vencer, talleres cerrados con 30 días, avisos sin leer). Cuando no hay nada pendiente, dice «Todo al día».
- **Mis talleres:** tarjetas con fase, participantes, dolores e ideas, y el botón **Crear taller**.
- **Crear taller** es paso a paso: Cuéntanos del taller (la IA propone) o **copiar un taller anterior** → Datos → Participantes (áreas y roles como chips: escribe y Enter) → Proceso (cada etapa se abre para poner herramientas y actividades; se reordenan con las flechas) → Validación e ideas (quick wins, reglas y tiempos con su etapa) → Preguntas → **Resumen** con «Editar» por sección. Lo capturado se guarda como **borrador** en el navegador: si sales, lo retomas desde Mis talleres.
- **Perfil:** clic en tu nombre → **Editar nombre y puesto**. El nombre aparece en el saludo, en Equipo y en los avisos del equipo.
- Instalación: corre `migracion-v17-inicio.sql` (o `setup.sql` completo).

---

### 10. Sugerir un taller con IA (v1.9, opcional)

En el creador de talleres, paso **Plantilla**, aparece la tarjeta **Sugerir con IA**: el facilitador escribe 2–3 líneas (cliente, proceso, qué duele) y en 10–20 segundos recibe un borrador completo —nombre, áreas, roles, etapas con actividades y herramientas, quick wins, reglas, tiempos y preguntas— cargado en el wizard como **borrador editable**. Nada se crea solo.

Para activarlo (una sola vez):

1. Crea una llave en [console.anthropic.com](https://console.anthropic.com) → *API keys* (empieza con `sk-ant-`). La API se cobra por uso y **aparte** de la suscripción de Claude: con el modelo Haiku, cada sugerencia usa ~1,000 tokens de entrada y ~1,800 de salida (≈ 1 centavo de dólar; 100 talleres ≈ 1 USD). En la consola pon un **límite mensual de gasto** (Settings → Limits), por ejemplo 5 USD, para que nunca pase de ahí.
2. Supabase → **Edge Functions** → *Deploy a new function* → nombre `suggest-workshop` → pega `supabase/functions/suggest-workshop/index.ts` → **Deploy**. En la función, apaga *Verify JWT with legacy secret* (la función valida la sesión por sí misma, igual que `send-invite`).
3. Supabase → **Edge Functions → Secrets**: agrega `ANTHROPIC_API_KEY` con tu llave. Opcionales: `AI_MODEL` (por omisión `claude-haiku-4-5-20251001`, el más barato) y `AI_MAX_TOKENS` (tope de la respuesta, por omisión 2500).
4. Recarga Colmena: la tarjeta aparece sola. Sin llave, la tarjeta no se muestra y todo sigue igual.

Seguridad: la llave vive solo en Supabase; la función responde únicamente a facilitadores o admins activos (revisa la sesión con `ws_me()`), limita el texto a 800 caracteres y normaliza la respuesta de la IA (etapas inexistentes fuera, listas acotadas) antes de devolverla.

### 11. Colmena como app en el celular (v1.10)

Colmena se puede **instalar como app** (PWA) sin pasar por App Store ni Google Play: ícono de abeja en la pantalla de inicio, pantalla completa y apertura rápida. Los participantes **no necesitan instalar nada**: siguen entrando con el QR desde el navegador.

- **iPhone:** abrir Colmena en **Safari** → **Compartir** → **Agregar a inicio**.
- **Android:** en Chrome aparece **Instalar** en la tarjeta de Inicio (o menú ⋮ → *Instalar app*).
- **Computadora:** en Inicio hay un QR para abrir Colmena en el celular; en Chrome/Edge también sale **Instalar aquí**.
- La tarjeta se puede cerrar con la ✕; después la opción queda en tu perfil (*App en tu celular*).
- Sin internet, la app abre la última versión guardada y muestra el aviso «Sin conexión». Los datos siempre se leen en vivo de Supabase (nunca se guardan en el teléfono).
- Archivos en la raíz del repo: `manifest.json` (nombre, colores, íconos y accesos directos *Crear taller* / *Mis talleres*), `sw.js` (se genera con `build.py`) y la carpeta `icons/`.

### 12. Entrar con Face ID / Touch ID / huella (v1.11)

En vez de contraseña + código de 6 dígitos, cada facilitador puede entrar **de un toque** con Face ID (iPhone), Touch ID (Mac) o su huella (Android). Usa las *passkeys* de Supabase (en beta desde mayo de 2026).

- **Activar (una vez por dispositivo):** entra con correo, contraseña y código → en Inicio aparece **Entra con Face ID la próxima vez → Activar** (o en tu perfil → *Entrar con Face ID*).
- **Entrar:** en la pantalla de inicio de sesión, **Entrar con Face ID**.
- **Seguridad:** Face ID cuenta como acceso completo solo con llaves que aprobaste estando con tu código. Si apareciera una llave que no aprobaste, Face ID deja de funcionar y tu perfil te avisa (*Es mía: aprobar* / *No la reconozco: apagar*). Si pierdes el teléfono: entra con tu código desde otro equipo → perfil → **Apagar**.
- Instalación: corre `migracion-v111-faceid.sql` y en Supabase → **Authentication → Passkeys** activa passkeys con *Relying Party ID* = `colmena.work`, nombre `Colmena` y origen `https://colmena.work` (desde el 12 oct 2026; antes `chriswat3rs.github.io`).

## Cómo se usa en la sala

1. En tu laptop abre `#admin`, entra y crea un taller: cuéntale a la IA el proceso y lo que duele, o ármalo a mano.
2. Con **QR para entrar** proyectas el código. La gente escanea y hace su registro desde el celular.
3. Tú llevas el ritmo con la barra de fases. Nada avanza solo: las pantallas de todos cambian cuando das clic.

| Fase | En el celular | En el panel proyectado |
|---|---|---|
| 1. Lobby | Registro: nombre, área, rol, etapas, avatar; mapa del proceso con sus etapas marcadas | Tarjeta **Entrar al taller** (QR, código y liga), tarjetas de quién entró (rol, área, etapas) y mezcla de áreas en la sala |
| 2. Check-in | Ánimo y expectativa | Ánimo del equipo (barras por estado), expectativas en sus palabras y a quién le falta el check-in |
| 3. Dolores | Tarjetas con etapa, actividad y herramienta (opcionales) y qué tanto duele; «No tengo más por ahora» cuando termina | Dolores por etapa (barras horizontales con el nombre completo de cada etapa) y muro en vivo por etapa; la intensidad va como etiqueta de color en cada tarjeta |
| 4. Votación | Reparte sus votos (tope validado en el servidor); al usar el último queda listo | Ranking en vivo (los primeros marcados como Reto 1, 2, 3) y **Quién ya votó** con un hexágono por voto; el muro queda plegado abajo |
| 5. Validación | Tres pasos: quick wins (Mucho / Algo / Poco / No aplica), reglas del nuevo flujo (Ayuda / Me da igual / Estorba / No me toca) y tiempos por etapa (4 rangos); primero lo de sus etapas; al final propone mejoras nuevas | Pestañas **Quick wins · Reglas · Tiempos · Propuestas** (una lista a la vez, con una nota que explica cómo leer cada gráfica): filas por quick win con índice 0–100, reglas en barras divergentes, tiempos en tira de proceso, propuestas nuevas |
| 6. Ideas | «¿Cómo podríamos…?» para los 3 dolores más votados; apoya hasta 3 ideas ajenas; «Terminé con Ideas» | Una columna por reto (votos, ideas y apoyos), un hexágono por apoyo y la idea más apoyada resaltada |
| 7. Resultados | Top de dolores, ideas, quick wins, reglas y tiempos; nota de cierre | Titular (el dolor más votado + 4 datos clave) y cinco secciones numeradas; contexto plegado; botón **Presentar** (pantalla completa, una sección por pantalla, flechas o clicker, Esc para salir) |
| 8. Cierre | Agradecimiento | Aviso de taller cerrado + lo mismo que Resultados (con barra de secciones y botones **Presentar** y **Compartir** siempre a la mano) |

**Foco de la fase (v1.8).** En el panel del facilitador, arriba de cada fase en vivo hay una tarjeta que dice qué está haciendo la sala, cuántos ya terminaron (con las caritas de quienes van listos), los 3–5 datos que importan en esa fase y el botón **Abrir <siguiente fase>**. Los seis indicadores que antes ocupaban la parte de arriba desaparecieron: cada fase muestra solo lo suyo.

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

`setup.sql` se puede volver a correr completo sin perder datos (todo es `if not exists` / `create or replace`). **Es el estado actual (v2.3.2):** lo arma `tools/arma_setup.py` con la base v1.26 y cada migración nueva, así que correrlo nunca regresa funciones a una versión vieja. La base guarda su versión (`ws_schema_version`): un `setup.sql` más viejo o una migración de `migraciones-anteriores/` se detienen con un aviso y no cambian nada. Para una base que ya existe basta con correr, en orden, las migraciones que aún le falten.

**De v1.4 a v1.5 (roles):** corre `setup.sql` completo otra vez. Tu cuenta (la primera facilitadora) pasa sola a **admin** y tus talleres se conservan. Luego haz el ajuste de **Confirm email** del paso 2 y sube el nuevo `index.html`.

### Tareas de mantenimiento (SQL Editor)

Agregar facilitadores: usa **Equipo → Invitar a alguien** en el panel (ya no hace falta SQL).

Si te quedaste sin ningún admin activo, recupera el rol desde el SQL Editor:

```sql
update ws_admins set role = 'admin', active = true
where email = 'tu-correo@empresa.com';
```

Si alguien del equipo perdió su celular, un admin usa **Equipo → Reiniciar acceso** (v1.12): le llega un correo para activar Face ID o su app de nuevo. Si el único admin eres tú y perdiste tu celular, reinicia tu segundo factor con SQL. Al entrar de nuevo te pedirá activarlo con un QR nuevo:

```sql
delete from auth.mfa_factors
where user_id = (select id from auth.users where email = 'tu-correo@empresa.com');
```

---

## Estructura

| Archivo | Qué es |
|---|---|
| `index.html` | Toda la app: participante (móvil) + panel del facilitador. Incluye la librería de Supabase y el generador de QR, sin depender de CDNs. |
| `setup.sql` | Estado actual de la base (v2.3.2): esquema, reglas de seguridad, tiempo real y analítica privada. Re-ejecutable y sin borrar datos. Se arma con `python3 tools/arma_setup.py`; no se edita a mano. |
| `migracion-v210-seguridad.sql` | v2.1: lo que corres en una base que ya existe (permisos del participante, candado de votos, versión de la base). |
| `migracion-v220-lobby-edit.sql` | v2.2: bloquea en PostgreSQL la configuración al entrar la primera persona o iniciar el taller. Incluye protección atómica ante entradas y ediciones simultáneas. |
| `migracion-v230-analitica.sql` | v2.3: telemetría privada, RPC de ingesta y consulta admin, agregados diarios y retención de 90 días. |
| `migracion-v231-ultimo-acceso.sql` | v2.3.1: último acceso de cada integrante, visible únicamente para admin en Equipo. |
| `migracion-v232-mapa-interacciones.sql` | v2.3.2: mapa privado de interacciones por acción, audiencia, pantalla y dispositivo. |
| `migraciones-anteriores/` | Las migraciones de antes y el `setup.sql` anterior (`setup-base-v126.sql`). Ya están dentro de `setup.sql`; cada una se detiene sola en una base versionada actual. |
| `tools/arma_setup.py` | Arma `setup.sql` juntando la base y las migraciones en orden (`--guardias` pone la guardia a las archivadas). |
| `pruebas/` | Pruebas de base de datos (`sql/probar_sql.py`), de pantallas (`navegador/`) y de seguridad (`seguridad/`). Ver `pruebas/LEEME.md`. |
| `README.md` | Esta guía. |
| `email/` | Logos del correo de invitación (Colmena + Quality & Knowledge). Se publican junto con `index.html`. |
| `supabase/functions/send-invite/index.ts` | Función que envía la invitación (Gmail o Resend). |
| `supabase/functions/send-notifications/index.ts` | Función que envía los correos del centro de notificaciones. |
| `manifest.json`, `sw.js`, `icons/` | App instalable (v1.10): manifiesto, service worker e íconos. |
| `supabase/functions/suggest-workshop/index.ts` | Función que pide a la IA un borrador de taller (v1.9, opcional). |
| `migraciones-anteriores/migracion-v16-notificaciones.sql` | Instala el centro de notificaciones sobre la v1.5. |
| `migraciones-anteriores/migracion-v17-inicio.sql` | Inicio, perfil editable y datos del dashboard sobre la v1.6. |
| `supabase/functions/account/index.ts` | v1.12: aceptar invitación sin contraseña, «Entrar sin contraseña» (enlace por correo) y «Reiniciar acceso». |
| `migraciones-anteriores/migracion-v113-borradores.sql` | v1.13: borradores del creador guardados en tu cuenta (tabla ws_drafts, solo los ve su dueño). |
| `migraciones-anteriores/migracion-v112-acceso-ia.sql` | v1.12: invitaciones con estado y reenvío, alta con Face ID, reinicio de acceso, «caso» del taller y límite diario de IA. |
| `tools/escala.py`, `tools/px2rem.py` | v1.14: el armado duplica los cortes de pantalla para letra Grande / Muy grande; `px2rem` fue la conversión única de px a rem. |
| `migraciones-anteriores/migracion-v115-talleres-grandes.sql` | v1.15: «pulso» de los celulares (una consulta mínima en lugar de tiempo real) e índices para talleres de hasta ~200 personas. |
| `migraciones-anteriores/migracion-v117-eliminar-usuarios.sql` | v1.17: eliminar a alguien del equipo; sus talleres, borradores y lo capturado pasan al admin que lo elimina. |
| `tools/springs.py` | v1.18: genera los resortes (`--spring-*`, `--dur-*`) con física real; `python3 tools/springs.py --write` actualiza `src/prefix.html`. |
| `migraciones-anteriores/migracion-v200-tipos.sql` | v2.0: tipo de taller, minutos y reloj por fase, «Juntar parecidas» (grupos de tarjetas) y avisos con las palabras de cada tipo. |

## v1.12 · Acceso sin contraseñas y creador con IA

**Alta de facilitadores.** El correo de invitación trae «Aceptar invitación». Al abrirlo, la persona elige **Face ID / huella** (recomendado: un toque, sin contraseña ni código) o **app autenticadora** (Microsoft/Google). En Microsoft Authenticator debe elegir «Otra cuenta (Google, Facebook, etc.)», no «Cuenta profesional o educativa»: esa opción no lee el QR. En el celular, el botón «Agregar a mi app autenticadora» abre la app directo, sin escanear.

**Invitaciones vencidas.** En Equipo cada invitación muestra Vigente / Vence hoy / Vencida con **Reenviar** (código nuevo por 7 días; la anterior deja de servir). En Inicio, «Reenviar» actúa en el mismo lugar. Si el invitado abre un enlace vencido, puede tocar «Pedir una nueva» y te llega un aviso.

**Olvidé mi contraseña / entrar sin contraseña.** En la pantalla de entrada, «Entrar sin contraseña» manda un enlace de un solo uso (vence en 1 hora, máximo 3 por hora). El enlace no se salta el segundo paso: después se confirma con Face ID o el código. Ya dentro, en tu perfil puedes crear o cambiar tu contraseña.

**Perdió su teléfono.** Equipo → **Reiniciar acceso**: borra su Face ID y su app, y le manda un correo para activarlos de nuevo (7 días). Sus talleres no se tocan.

**Creador con IA.** El paso 1 es «Cuéntanos del taller» (cliente, proceso, qué duele, objetivo, personas y duración). La IA propone el taller completo y el código decide los números (votos, retos, tiempos). En la propuesta hay advertencias («cosas para revisar»), aviso si algún dolor no quedó cubierto, «Ajustar con una instrucción» y «Otra propuesta» (5 por borrador; 30 por persona al día). Sin IA disponible, «Armar a mano» usa lo que escribiste.

**Entrar en computadora (Mac y Windows, v1.12.1).** Funciona igual en Chrome, Edge, Safari y Firefox:
- **Mac:** «Entrar con Touch ID». Si tu llave está en tu iPhone, toca el botón y elige «Usar un teléfono o tableta».
- **Windows:** «Entrar con Windows Hello» (PIN, huella o cara del equipo). Si tu llave está en el celular, elige «Usar un teléfono o tableta» y escanea el QR; la computadora necesita Bluetooth encendido.
- **Primera vez en una computadora:** entra con tu teléfono (QR) o con tu correo + código, y en Inicio toca «Activa Touch ID / Windows Hello en esta computadora». Si tu cuenta tiene app autenticadora, Supabase pide el código de 6 dígitos antes de agregar la llave (por seguridad); Colmena lo pide ahí mismo.
- **Recomendación para cada facilitador:** Face ID/huella en el celular + app autenticadora de respaldo. Así nunca se queda fuera si cambia de equipo.

**Tus talleres en Inicio (v1.13).** Inicio muestra una tabla con todos tus talleres y borradores: filtros **Todos · En curso · Por iniciar · Borradores · Finalizados**, búsqueda por nombre o código y orden por nombre, participantes o fecha. El menú **⋯** de cada fila permite abrir (o continuar el borrador), **Duplicar** (crea un borrador con la misma configuración, sin datos de la sala), copiar el código y **Eliminar** (con confirmación; si el taller está en curso lo advierte). Los borradores del creador se guardan solos en tu cuenta, así que los ves desde cualquier dispositivo. Instalación: correr `migracion-v113-borradores.sql`.

**Pasos para activarla (una vez):**
1. SQL Editor → correr `migracion-v112-acceso-ia.sql`.
2. Edge Functions → crear la función `account` con `supabase/functions/account/index.ts` (apaga «Verify JWT with legacy secret»). Usa los mismos secretos de correo que `send-invite`.
3. Edge Functions → actualizar `suggest-workshop` con el archivo nuevo.
4. Publicar `index.html`, `sw.js` en GitHub Pages.

Sin `SUPABASE_URL`, la app corre en **modo demo**: todo funciona en tu navegador y sin cuentas, útil para enseñarla o probar cambios.

## v1.14 · Accesibilidad: tamaño de texto, alto contraste y menos animaciones

**Dónde está.** Facilitador: tu foto (arriba a la derecha) → **Accesibilidad**. Participante: botón **Aa** en la parte de arriba de cada pantalla. Se guarda en ese dispositivo (no en la cuenta), así que cada persona lo ajusta en su celular o compu.

| Ajuste | Qué hace |
|---|---|
| Tamaño de texto: Normal / Grande / Muy grande | Todo crece en proporción (100 %, 112.5 %, 125 %): letras, espacios, íconos y botones. |
| Alto contraste | Textos grises más oscuros, bordes marcados (≥ 3:1), enlaces subrayados y foco más visible. Se activa solo si el sistema lo pide. |
| Reducir animaciones | Quita movimientos y transiciones. Se activa solo si el sistema lo pide. |

**Por qué rem.** La tipografía, espaciados, íconos, botones y anchos de tarjetas y paneles están en `rem` (1 rem = 16 px con el tamaño normal, así que el diseño se ve idéntico). Bordes, sombras, radios, posiciones y los códigos QR se quedan en px. Los cortes de pantalla (media queries) no entienden de rem, así que al armar `index.html` cada corte se duplica escalado ×1.125 y ×1.25 para Grande y Muy grande: el diseño compacto entra antes y nada se encima. Al «Proyectar» resultados se usa siempre el tamaño normal (la sala manda).

**Cambio de encabezado.** «Cerrar sesión» ya no está en la barra superior: está al final de tu perfil (en celular y en computadora).

## v1.15 · Talleres grandes (hasta ~200 personas en el plan gratis)

**Qué cambió.** Los celulares ya no abren conexión en tiempo real. Cada 6–8 segundos (al azar, para no llegar todos juntos) hacen una sola consulta mínima: en qué actividad va el taller, si cambió algo de su configuración y cuántos compañeros ya terminaron. Con la pantalla apagada no preguntan, y si algo falla esperan cada vez más (hasta 30 s) para no saturar. En Ideas, la lista se actualiza cada ~12 s pidiendo solo las ideas nuevas. Tu panel sigue en tiempo real, pero se actualiza como máximo cada 2.5 s y solo pide lo que cambió.

**Qué notarás.** Cuando cambias de actividad, los celulares pasan a la siguiente en unos segundos (no al instante). Tu panel se siente igual.

**Prueba local (200 personas simuladas, mismas reglas de seguridad):** antes ~220 consultas por segundo a la base, ahora ~30; cada pulso tarda ~2 ms. Ya no se usan las 200 conexiones en vivo ni el tope de 100 avisos por segundo del plan gratis.

**Antes de un taller grande (una sola vez, en Supabase → Authentication → Rate Limits):**

| Límite | Valor normal | Ponlo en |
|---|---|---|
| Usuarios anónimos (por hora, por red) | 30 | 500 |
| Renovación de sesión (cada 5 min, por red) | 150 | 1000 |

Sin esto, si muchas personas comparten la misma red (oficina, Wi-Fi del evento), después de las primeras 30 el resto no puede entrar con el QR.

**El día anterior** abre Colmena (tu panel) para que el plan gratis no pause el proyecto por inactividad.


## v1.16 · Primer taller más claro, IA más confiable e invitaciones de un solo uso

**Experiencia del facilitador**

- **Recorrido de primera vez** (6 pasos): aparece solo a quien entra sin talleres ni borradores y lo acompaña en su primer taller (Inicio → Cuéntanos → Revisa y crea → Panel en vivo). Se salta con «Saltar recorrido» o Esc y se repite en **Perfil → Ayuda → Ver recorrido otra vez**. A quien ya tiene talleres se le ofrece una vez «¿Nuevo en Colmena?». Se recuerda por cuenta en cada dispositivo (localStorage `colmena_tour_v1_<uid>`).
- **«Así será tu taller»** en Revisa y crea: los 6 momentos de la sala (Check-in, Dolores, Votación, Validación, Ideas, Resultados) con lo que usa cada uno, minutos sugeridos según la duración elegida y «Editar» que lleva a su pestaña.
- **Textos sin jerga:** «¿De qué se trata tu taller?», «¿Qué problemas tiene hoy ese proceso?», objetivos en lenguaje llano, «Reglas obligatorias», «Votos para ideas», «Sala de espera» en lugar de «Lobby», «Tu siguiente paso» en la tarjeta de la sala, errores que dicen qué falta.
- **Saltar o regresar de fase pide confirmación** («¿Mover a la sala a…?»). Abrir la siguiente fase no pregunta.
- Inicio: el subtítulo usa el mismo criterio que los filtros (en curso / por iniciar) y el estado vacío explica los 3 pasos.

**Confiabilidad y seguridad**

- **IA:** una falla de red al verificar la cuenta ya no se muestra como «Solo facilitadores activos…»: la función reintenta una vez, responde 503 «No pudimos verificar tu cuenta, intenta de nuevo» y deja el detalle en Logs. La página vuelve a preguntar si hay IA cada vez que abres «Crear taller».
- **Invitaciones de un solo uso:** una invitación ya canjeada no vuelve a dar acceso ni reactiva a quien desactivaste; al desactivar a alguien se cancelan sus invitaciones pendientes.
- Se quitaron referencias a clientes anteriores en panel, resultados y exportaciones.

**Instalación (en este orden, sin talleres en curso)**

1. Supabase → SQL Editor: corre `migracion-v116-invitaciones.sql`.
2. Supabase → Edge Functions: actualiza `account` y `suggest-workshop` con los archivos de `supabase/functions/` (Deploy). No hay secretos nuevos.
3. Sube `index.html` y `sw.js` a GitHub Pages.

## v1.17 · Escritorio ordenado, esqueletos de carga y animaciones

- **Barra lateral en escritorio** (desde 1024 px): marca, Inicio, Mis talleres y, para admin, Todos los talleres y Equipo; abajo Notificaciones y tu perfil. En celular y tableta sigue la barra de arriba. El contenido usa el ancho disponible (máx. 90rem).
- **Inicio en dos columnas:** encabezado compacto con un solo botón principal («Crear taller»), franja de 4 indicadores (En curso, Por iniciar, Borradores, Participantes del mes), «Tus talleres» como tabla principal y a la derecha «Ahora mismo», «Pendientes» y «Último taller cerrado». Se quitaron «Acciones rápidas» (repetía los botones) y la tarjeta «Todo al día» (ahora es una línea).
- **Mismo encabezado en todas las vistas** (título, contexto y acciones a la derecha). Equipo en dos columnas (invitar + lista). Crear taller aprovecha el ancho (panel lateral fijo en «Cuéntanos», agenda y detalle lado a lado en «Revisa y crea»).
- **Sistema visual:** escala tipográfica por rol (`--fs-*`), radios de 8–12 px, una sola tarjeta (borde sutil, sin sombras), marino sólido solo para el botón principal.
- **Esqueletos de carga** con la forma del contenido en Inicio, Mis talleres, Todos, Equipo y Perfil (con `aria-busy` y texto para lector de pantalla).
- **Microanimaciones:** entrada escalonada al cambiar de vista, hover de filas, botones con presión, indicador de la barra lateral que se desliza, conteo de indicadores la primera vez, toasts y diálogos suaves. Todo se apaga con «Reducir animaciones» o la preferencia del sistema.
- Requiere navegadores de 2023 en adelante (Chrome 111+, Safari 16.2+) para container queries y `color-mix`; en anteriores funciona con estilos más simples.

## v1.17 · Eliminar usuarios

**Qué hace.** En **Equipo**, las cuentas desactivadas muestran **Eliminar** junto a «Reactivar» (primero se desactiva, después se elimina). Al confirmar:

- Sus talleres, borradores y todo lo capturado **se conservan y pasan a tu nombre** (el admin que la elimina). Si participó en algún taller con su cuenta del panel, eso también pasa a ti.
- Las invitaciones pendientes para su correo se cancelan; las que ella mandó y siguen pendientes pasan a ti.
- **Se borran su cuenta y su acceso.** No se puede deshacer: si vuelve, invítala de nuevo.

Solo lo puede hacer un admin activo (con Face ID o código), nunca sobre su propia cuenta, y la base exige que la cuenta ya esté desactivada. El orden importa: primero la base pasa todo a tu nombre y la saca del equipo (`ws_admin_remove_member`, con tu sesión) y solo si eso salió bien la función `account` borra la cuenta (sus talleres se borrarían en cascada con ella). Si ese último paso falla, la persona igual ya no tiene acceso; el detalle queda en **Edge Functions → account → Logs** y la cuenta se puede borrar a mano en **Authentication → Users**.

**Instalación (en este orden)**

1. Supabase → SQL Editor: corre `migracion-v117-eliminar-usuarios.sql` (al final debe salir 1 fila con `seguridad`, `authenticated` = true y `anon` = false).
2. Supabase → Edge Functions: actualiza `account` con `supabase/functions/account/index.ts` (Deploy). No hay secretos nuevos.
3. Sube `index.html` y `sw.js` a GitHub Pages.

## v1.17 · Modo oscuro

**Dónde está.** Igual que el resto de Accesibilidad: facilitador → tu foto → **Accesibilidad → Tema**; participante → botón **Aa**. Tres opciones: **Sistema** (por defecto: sigue al celular o la compu y cambia al momento si el sistema cambia), **Claro** y **Oscuro**. Se guarda en ese dispositivo (`colmena_a11y.th`).

**Cómo funciona.** Un script en `<head>` pone la clase `dark` en `<html>` antes de pintar (no hay destello blanco) y ajusta el color de la barra del navegador (`theme-color`). Todo el color sale de tokens en `:root` (en claro valen lo mismo que antes, así que el modo claro no cambia) y `html.dark` los redefine: fondo `#0C1424` < tarjeta `#121C2F` < menús y diálogos `#18243B`, tinta `#E7ECF4`, azul de texto `#7CBDF3` y botón principal azul claro `#86C3F5` con texto marino. Con **Alto contraste** encima, `html.hc.dark` aclara aún más textos, líneas y acentos.

**Lo que se queda en claro a propósito.** Los exportables (PDF y Excel), los correos de invitación, los códigos QR (siempre sobre placa blanca; en oscuro con margen extra para que el celular los lea) y el logo de Quality & Knowledge (sobre placa blanca porque sus letras son oscuras).

**Reglas para código nuevo.** No escribas colores fijos: usa un token (`--card`, `--elev`, `--ink-2`, `--line`, `--accent-strong`, `--ok-soft`/`--ok-ink`, `--warn-*`, `--danger-*`, `--on-primary`…). Si hace falta uno nuevo, decláralo en `:root` con su valor en claro y en `html.dark` con el de oscuro (y en `html.hc.dark` si es texto). Sombras y velos: `rgb(var(--sh) / .18)` y `rgb(var(--scrim) / .45)`. Texto sobre el botón principal: `var(--on-primary)`; sobre rellenos de acento: `var(--on-accent)`.

## v1.17 · Instalación (todo junto, sin talleres en curso)

1. Supabase → SQL Editor: corre `migracion-v117-eliminar-usuarios.sql`.
2. Supabase → Edge Functions → `account`: pega `supabase/functions/account/index.ts` y **Deploy**. `suggest-workshop` no cambia. No hay secretos nuevos.
3. Sube `index.html` y `sw.js` a GitHub Pages. La app instalada se actualiza sola al abrirla.

## v1.18 · Movimiento con «feeling de app» (Figma Smart Animate / Motion)

**Resortes.** Cuatro presets de Figma con física real (masa 1), generados por `tools/springs.py` como funciones CSS `linear()` con su duración de asentamiento: **Gentle** (rigidez 100, amortiguación 15 · 780 ms), **Quick** (300, 20 · 570 ms), **Bouncy** (600, 15 · 840 ms) y **Slow** (80, 20 · 1220 ms). Tokens: `--spring-quick` + `--dur-quick`, etc. (sin `linear()` hay curvas cúbicas de respaldo). En JS son los mismos: el script escribe también la tabla `SPRINGS` de `src/app1.js` que usa `Motion` para Web Animations. La duración incluye la cola del resorte: lo que se percibe termina en ~300 ms. Regla: **Quick** para casi toda la interfaz, **Gentle** para pantallas y hojas, **Bouncy** solo en cosas chicas (palomitas, insignias, perillas, hexágonos de voto), **Slow** casi nunca. Salidas: menús y diálogos se van en ~140 ms con `--ease-exit` (no rebotan); las hojas bajan con Gentle y los avisos con Quick.

**Qué se mueve.**
- **Entre pantallas** (View Transitions): secciones del facilitador, pasos del creador (adelante desliza a la izquierda, atrás a la derecha), fase del panel y pantallas del participante. La barra lateral/superior no se mueve. Al abrir un taller desde la tabla, «Ahora mismo» o «Todos», su nombre se transforma en el título del panel, y al volver regresa a su fila. Solo cuando la persona navega: el redibujo del panel (cada 2.5 s), el sondeo del celular y las recargas de datos nunca disparan una transición.
- **Datos en vivo** (`Motion.morph`): el panel se redibuja con llaves (`data-k`): lo que no cambió se queda tal cual (sin parpadeo, sin perder foco ni reiniciar animaciones). Solo se anima lo afectado: números que se cuentan (`data-n`), barras que crecen desde su ancho anterior, tarjetas nuevas con «pop» y listas que se reacomodan (FLIP). Si nada cambió, nada se mueve.
- **Componentes:** diálogos, menús ⋯, avisos, perfil y QR entran desde su botón y salen animados; hojas del celular (la de «Aa», menús y la tarjeta del recorrido) suben y bajan con Gentle (la de «Aa» y la de compartir también se cierran arrastrando la cabecera hacia abajo); los filtros, el rol en Equipo, Tema/Tamaño de texto y la barra lateral tienen un indicador que se desliza; los `<details>` abren y cierran con altura animada; esqueleto → contenido con fundido cruzado; el recorrido viaja de un objetivo al siguiente; la tarjeta publicada viaja del campo de texto a «Tus tarjetas».
- **Rendimiento:** solo `transform`/`opacity` (propiedades individuales `translate`/`scale`), escalonado máximo de 6, nada en listas de más de 40. Excepciones puntuales: el ancho del indicador de los segmentados, la altura al expandir/colapsar, el recorte del recorrido y los botones con «Eliminando…».

**Accesibilidad.** Con «Reducir animaciones» o la preferencia del sistema todo es instantáneo (también lo de JS y las transiciones de pantalla; se revisa en cada llamada y, si se activa a media animación, todo termina al momento). Si el JS falla nada queda invisible. Durante una transición de pantalla la página no recibe toques: tocar la termina al instante y el toque llega a su botón.

**Navegadores.** View Transitions de mismo documento: Chrome/Edge 111+, Safari 18+, Firefox 144+. Sin ellas, cada vista entra con la animación escalonada de v1.17. `linear()`: Chrome 113+, Safari 17.2+, Firefox 112+ (si no, curvas cúbicas). Altura de `<details>` con `::details-content`: Chrome 131+ (si no, se anima con JS).

**Pruebas.** Prueba de movimiento (`motion.mjs`, junto a las de modo oscuro): 8 s de redibujos sin cambios = 0 animaciones y 0 transiciones; un voto anima solo ranking, quién votó y números; navegar usa transición con elemento compartido; con «Reducir animaciones» y con `prefers-reduced-motion`, 0 de todo.

## v1.19 · Encabezado, Notificaciones, Ajustes y menú de Equipo

- **Encabezado superior** (arriba a la derecha): botón de modo oscuro (luna/sol), campana con contador y tu avatar. La barra lateral queda solo con la navegación.
- **Notificaciones** es una vista propia (la abre la campana): filtro Todas / Sin leer, «Marcar todo como leído» y la acción de cada aviso.
- **Ajustes** es una vista propia (avatar → Ajustes): Perfil, Acceso, Ayuda, Correos de avisos y Accesibilidad. El avatar abre un menú corto: Ajustes, Ver recorrido y Cerrar sesión.
- **Modo oscuro**: un botón de luna/sol en el encabezado (y junto a «Aa» en el celular del participante). Sin elección sigue al sistema; al tocarlo se guarda en ese dispositivo. Ya no está dentro de Accesibilidad.
- **Indicadores en tarjetas** (Inicio y Todos los talleres): una tarjeta por dato con ícono, etiqueta, número y contexto.
- **Equipo con menú ⋯**: cada fila muestra nombre, rol, talleres y estado; las acciones (rol, reiniciar acceso, desactivar/reactivar y eliminar) están en el menú. Las invitaciones también.

**Instalación:** solo subir `index.html` y `sw.js` a GitHub Pages. No hay cambios en Supabase.

## v1.20 · Ancho completo y breadcrumbs

- **Todo el ancho de la pantalla**: el contenido ya no se queda en una columna centrada; Inicio, Todos, Equipo, Ajustes, Crear taller y el panel en vivo usan el ancho disponible con el mismo margen lateral que el encabezado.
- **Breadcrumbs (ruta)**: en escritorio, a la izquierda del encabezado (por ejemplo «Inicio › Mis talleres › Crear taller › Cuéntanos»); en celular, arriba del título en Crear taller, Notificaciones y Ajustes. En el panel en vivo, «Mis talleres › Fase» arriba del nombre del taller (el primer nivel regresa a tus talleres).

**Instalación:** solo subir `index.html` y `sw.js`.


## v1.21 · Uso de IA: tokens por taller, pausa y tope por persona

- **Vista «Uso de IA»** (barra lateral; en celular, pestaña «IA»): tokens usados, costo estimado (Claude Haiku 4.5, US$1 entrada / US$5 salida por millón), propuestas y personas; columnas apiladas de tokens por día y dona por persona (admin) o por tipo de uso (facilitador); tabla «Por taller» que incluye borradores. Periodo: este mes, 90 días o 12 meses. Las gráficas usan Chart.js 4.4.1 (MIT, incluido en el archivo) con tooltip en HTML que siempre queda encima.
- **Límites por persona (solo admin)**: pausar la IA de alguien o ponerle tope de tokens al mes (20k, 50k, 100k, 250k u otro). También desde Equipo → ⋯ → «Límite de IA». Al llegar al tope, el facilitador ve un aviso y arma el taller a mano hasta el mes siguiente. El límite de 30 propuestas al día sigue.
- **Registro**: cada propuesta guarda quién, borrador, taller (al crearlo), modelo y tokens de entrada y salida. El historial se guarda 400 días. El facilitador solo ve lo suyo.
- Al usar la IA, el aviso dice cuántos tokens usó y cuánto lleva del mes.

**Instalación (en este orden):**
1. Supabase → SQL Editor → pegar `migracion-v121-uso-ia.sql` → Run (al final deben salir 6 funciones con seguridad = true).
2. Supabase → Edge Functions → `suggest-workshop` → Code → pegar `supabase/functions/suggest-workshop/index.ts` → Deploy updates.
3. GitHub: subir `index.html` y `sw.js`.

El uso anterior a la v1.21 no tiene tokens guardados: la vista empieza a llenarse con las propuestas nuevas.

## v1.22 · Inicio como tablero

- **Ahora mismo**: tarjetas de cada sala abierta con su fase, de quién es y cuántos van listos (barra de avance). Al lado, **Pendientes** (máximo 3 a la vista, «Ver N más»).
- **Cómo van tus talleres** (admin: todo el equipo; facilitador: lo suyo), con periodo Este mes / 90 días / Todo:
  - 4 indicadores con minigráfica de 6 meses y cambio contra el periodo anterior: talleres realizados, personas escuchadas, % que terminó todo el recorrido (tocó «Terminé» en Ideas) y dolores → retos.
  - Personas escuchadas por mes (línea), ¿en qué fase se pierde la sala? (columnas, con la fase que más pierde en rojo y una sugerencia), ánimo al llegar (dona divergente, con el área que llega más cargada), dónde duele más (radar de dolores por área contra el periodo anterior), mejoras rápidas con más respaldo (anillos con el índice 0–100 de Resultados) y uso de IA por tipo.
  - Últimos resultados: lo más votado de cada taller que llegó a Resultados, con su consenso.
- Todas las gráficas tienen tooltip en HTML encima de todo y se vuelven a pintar al cambiar a modo oscuro. La tabla de talleres vive en «Mis talleres»; quien aún no tiene talleres ve el Inicio de siempre con el recorrido.

**Instalación:** Supabase → SQL Editor → pegar `migracion-v122-inicio.sql` → Run (al final sale `ws_home_stats` con seguridad = true). Después subir `index.html` y `sw.js` a GitHub. No hay funciones que desplegar.

## v1.23 · Fases «Panal»: jerarquía, ilustraciones animadas y resumen con IA

- **Una sola estructura en las 8 fases**: banda azul marino con el número de fase en un hexágono, título grande, *qué hacer ahora*, botón principal en miel, el último movimiento de la sala y una ilustración animada por fase (SVG, sin librerías; con «Reducir animaciones» se quedan quietas). Debajo, 4 indicadores montados sobre la banda y el contenido en columna principal + carril.
- **La sala como panal**: cada persona es una celda que se llena de miel al tocar «Terminé» (con más de 21 personas, 20 celdas de 5% cada una).
- **Miel solo para lo que importa**: avance, ganadores (retos, primer lugar, idea líder) y el botón principal. Los datos siguen en azul. Títulos y números en Bricolage Grotesque.
- **Stepper de panal**: fase hecha en miel, la actual en azul marino con pulso.
- **Muro de dolores**: una etapa a la vez, filtro «Duelen mucho», intensidad en hexágonos y las tarjetas nuevas llegan con brillo.
- **Resultados**: el dolor más votado y 4 datos clave arriba, **resumen con IA** (lo propone la IA con los números del taller; tú lo editas o lo vuelves a generar) y **hallazgos** calculados con su evidencia (consenso o votos repartidos, dónde se concentra, mejora más clara, fricción, tiempos y participación). La presentación suma las diapositivas de Resumen y Hallazgos.
- **Inicio y Uso de IA** con la misma banda e indicadores.

**Instalación:**
1. Supabase → SQL Editor → pegar `migracion-v123-resumen.sql` → Run (al final salen las columnas `summary` y `summary_at`).
2. Supabase → Edge Functions → `suggest-workshop` → pegar el código nuevo → Deploy updates (agrega la acción `summary`; usa el mismo tope y pausa de IA de cada persona).
3. Subir `index.html` y `sw.js` a GitHub.

## v1.24 · Mis talleres, Todos los talleres y Equipo con la identidad «Panal»

- **Misma banda en todas las vistas**: Mis talleres, Todos los talleres y Equipo estrenan la banda azul marino con ilustración animada propia (el panal que se llena, las colmenas del equipo conectadas, las abejas que orbitan la colmena) y 4 indicadores montados sobre la banda.
  - Mis talleres: en curso (cuántos van listos), personas escuchadas, aportes (dolores + ideas) y borradores con propuesta lista. «Crear taller» es el botón miel.
  - Todos los talleres: talleres (este mes y cerrados), en curso, facilitadores y cuentas con acceso. El filtro por facilitador ahora son chips con su avatar.
  - Equipo: cuentas con acceso, admins, facilitadores e invitaciones (avisa las que vencen en menos de 24 h). «Invitar a alguien» lleva al formulario.
- **Filtros por estado** como control segmentado (el mismo de «Todas / Duelen mucho» y del periodo en Uso de IA). Código del taller en etiqueta y renglones más aireados.
- **Encabezado superior arreglado**: al hacer scroll ya no crece ni se redondea (una clase chocaba con la de las tarjetas de calificación); se queda fijo, de 56 px, con breadcrumb, tema, campana y avatar centrados.

**Instalación:** solo subir `index.html` y `sw.js` a GitHub. No hay SQL ni funciones.

## v1.25 · Celular del participante «Panal», la sala en vivo e Inicio como colmena en vivo

- **Participante en celular con la misma identidad**: cada actividad abre con su portada azul marino (dibujo animado, pregunta y la sala en vivo). Bienvenida con las 5 actividades, sala de espera con tu tarjeta, resultados y cierre con su banda. Botón principal en miel; selección en azul marino; votos y apoyos en hexágonos de miel.
- **La sala en vivo** (solo conteos, sin nombres ni consultas extra): un panal anónimo que se llena de miel cuando alguien toca «Terminé» y un contador «8/15» siempre visible arriba.
- **Al tocar «Terminé»**: tarjeta de espera con el panal grande, cuántas personas faltan («Esperando a 7 personas») y qué sigue; cuando toda la sala termina, lo dice.
- **Quien facilita abre la siguiente actividad**: en cada celular aparece una portada animada («Votación · Tienes 5 votos») que se cierra sola; si alguien no había terminado, le confirma que lo que envió quedó guardado.
- **Aviso suave a quien va atrás**: una vez por actividad (después de 20 s), cuando 7 de cada 10 ya terminaron o solo falta esa persona.
- **Inicio = la colmena en vivo**: la banda muestra hasta 4 salas abiertas como celdas que se llenan de miel con quienes ya terminaron (tócalas para entrar). Los pendientes viven en la misma banda y solo aparecen si existen; desaparecen la tarjeta «Ahora mismo» y el texto «Todo al día».

**Instalación:** solo subir `index.html` y `sw.js` a GitHub. No hay SQL ni funciones.

## v1.26 · Facilitadores entran con contraseña y «¿Olvidaste tu contraseña?»

- **Facilitador = correo y contraseña** (o Face ID, opcional). Ya no se le pide el código de 6 dígitos ni la app autenticadora. Solo ve y opera sus propios talleres, igual que antes.
- **Admin sin cambios**: contraseña o Face ID, y su segundo paso (código de la app o Face ID aprobado).
- **Reglas de la contraseña** (página y servidor): al menos 8 caracteres, una mayúscula, una minúscula y un número; símbolos opcionales; hasta 72. Se rechazan las obvias (123456, «colmena», el nombre de tu correo). Se pueden pegar desde un gestor. Las reglas se palomean en vivo.
- **«¿Olvidaste tu contraseña?»**: llega un enlace para crear una nueva. Sirve una sola vez y vence en 1 hora; siempre se muestra el mismo mensaje (no revela si el correo tiene cuenta); reenviar a los 60 s. Al guardar puedes cerrar la sesión en tus otros dispositivos.
- **Enlace vencido o usado**: pantalla propia con el correo ya escrito para pedir otro en un toque.
- **Invitación de facilitador**: al aceptarla, crea su contraseña y entra. Las invitaciones de admin siguen con Face ID o app.
- **Equipo → ⋯ → Reiniciar acceso** a un facilitador: su contraseña y su Face ID dejan de servir y le llega un enlace para crear una nueva (72 horas).
- Se quita «Entrar sin contraseña» de la pantalla de entrada (lo cubre «¿La olvidaste?»).
- **Resumen con IA: una sola regla.** Se genera **una vez por taller terminado** (Resultados o Cierre). Ya no lo frenan la pausa, el tope mensual ni el límite diario de propuestas (sus tokens sí aparecen en Uso de IA). Se pide confirmar antes; después se puede editar, pero no volver a generar. El servidor guarda el resumen en el taller.
- **IA sin saldo**: si la cuenta de Anthropic se queda sin crédito, la propuesta y el resumen con IA lo dicen claro («La IA de Colmena se quedó sin saldo…») en lugar de «No pudimos escribir el resumen».

**Instalación (en este orden):**
1. Supabase → SQL Editor → pegar `migracion-v126-contrasenas.sql` → Run. Deben salir 4 renglones con `ok = true`.
2. Supabase → Edge Functions → `account` → pegar `supabase/functions/account/index.ts` → Deploy updates. Igual con `suggest-workshop` (`supabase/functions/suggest-workshop/index.ts`).
3. Supabase → Authentication → Sign In / Providers → Email → *Password requirements*: mínimo **8** y *Lowercase, uppercase letters and digits*. (*Leaked password protection* solo existe en el plan Pro.)
4. Subir `index.html` y `sw.js` a GitHub.

## v1.27 · Participante en tablet y computadora

El celular (menos de 720 px) se queda igual. En pantallas más grandes:

- **Computadora y tablet horizontal (900 px o más)**: una barra arriba a todo lo ancho con el nombre del taller, las 5 actividades y el estado; la actividad al centro y un **carril a la derecha** con la sala (panal y cuántas personas ya terminaron), tu avance y **la acción que termina cada actividad, siempre en el mismo lugar**. Desde 1100 px el carril es más ancho y se ven los nombres de todas las actividades.
- **Tablet vertical (720–899 px)**: el mismo contenido acomodado y la acción en una **barra baja de 64 px** (antes medía de 110 a 175 px y tapaba contenido), con la sala a la izquierda.
- **Bienvenida**: el taller y «Lo que vas a hacer» en dos columnas; el texto ya no dice «desde tu celular».
- **Registro en 2 pasos** («Cuéntanos quién eres» y «Tu parte del proceso») con vista previa de cómo apareces en el muro. En celular siguen los 5 pasos.
- **Sala de espera**: las etapas del proceso en tarjetas y la agenda de las 5 actividades.
- **Check-in**: las 5 opciones en una fila.
- **Dolores**: escribes a la izquierda y ves tus tarjetas a la derecha. **Enter publica** (Shift + Enter = salto de línea) y se queda elegida la última etapa. «No tengo más por ahora» es la acción principal.
- **Votación** en cuadrícula, con **filtro por etapa** y «Tus votos» en el carril.
- **Validación como tabla**: una fila por mejora y una columna por respuesta; los pasos (Mejoras rápidas, Reglas, Tiempos) se ven como pestañas con su avance. Se quita «Siguiente sin contestar».
- **Ideas**: desde 1100 px los retos lado a lado, cada uno con su campo y sus ideas; en tablet, pestañas por reto.
- **Resultados**: los 3 dolores más votados como podio y «Tus aportes» en el carril. **Cierre** con lo que aportaste.
- La portada de cada actividad sale como ventana centrada.
- Si giras la tablet o cambias el tamaño de la ventana, la pantalla se acomoda sola sin perder lo que escribiste. Los cortes siguen al tamaño de texto (Accesibilidad).
- Accesibilidad: 0 problemas (axe, WCAG 2 AA) en 44 pantallas, claro y oscuro.

**Instalación:** solo subir `index.html` y `sw.js` a GitHub. No hay SQL ni funciones.

## Dominio propio · colmena.work (12 oct 2026)

Colmena vive en **https://colmena.work**. La dirección vieja (`chriswat3rs.github.io/colmena-workshop/`) redirige sola, con el mismo código de taller.

- **GoDaddy (DNS):** 4 registros A → `185.199.108.153`, `185.199.109.153`, `185.199.110.153`, `185.199.111.153`; `www` CNAME → `chriswat3rs.github.io`; un TXT de verificación de GitHub.
- **GitHub → Settings → Pages:** Custom domain `colmena.work`, *Enforce HTTPS* activado. GitHub guarda el archivo `CNAME` en el repo: no lo borres.
- **Supabase → Edge Functions → Secrets:** `SITE_URL` = `https://colmena.work/` (los enlaces de los correos).
- **Supabase → Authentication → Passkeys:** Relying Party ID `colmena.work`, origen `https://colmena.work`. Las llaves de Face ID creadas en la dirección vieja ya no sirven: cada facilitador entra una vez con correo, contraseña y código y vuelve a activar Face ID.
- **Renovación:** el dominio se renueva cada año en GoDaddy.

## v1.28 · Creador sin trabas (12 oct 2026)

Respuesta a la prioridad alta del feedback de facilitadores (errores al crear y etapas que no aplican). Solo front: subir `index.html` y `sw.js`.

- **Nombre que siempre cabe:** «Armar a mano» y las copias recortan el nombre (la base acepta 1–160); contador y aviso en el campo. Era la causa del error `ws_sessions_name_check`.
- **Errores claros:** ningún error de base de datos se muestra tal cual; se dice qué dato revisar.
- **Obligatorio / opcional:** cada campo del creador lo dice. «Para crear falta…» lleva a la sección donde se arregla.
- **Sin reglas rígidas:** ya no se pide «verbo + objeto» ni herramientas en cada etapa.
- **Validación opcional:** interruptor «Incluir Validación». Sin nada que calificar, el taller se la salta en el panel, los celulares, la agenda y los resultados; sus minutos se reparten.
- **Problemas que pasan a Ideas:** de 1 a 6 (antes lo decidía el sistema). Con más de 3, el participante los ve en pestañas.
- **Sin «Industria»:** Colmena es para cualquier equipo; «Cuéntanos» ya no lo pide.

## v2.0 · Tipos de taller, «Juntar parecidas» y tiempo por fase (13 oct 2026)

Respuesta al feedback de facilitadores: que Colmena sirva para más que design thinking sin volverse más difícil. «Mejora de procesos» sigue siendo el taller por defecto y se crea igual que siempre. Los tipos nuevos se viven igual en la sala (mismas fases, mismo celular, misma consola): cambian las palabras, las preguntas y lo que te llevas al final. Incluye la v1.28. Plan gratis de Supabase.

**Publicar (en este orden, cuando no haya un taller en vivo):**
1. Supabase → SQL Editor → New query → pega todo `migracion-v200-tipos.sql` → **Run**. Al final sale una fila: `tipo_y_reloj = 5`, `grupos = 2`, `funciones = 9`. Se puede correr dos veces sin problema.
2. Supabase → Edge Functions → `suggest-workshop` → pega `supabase/functions/suggest-workshop/index.ts` → **Deploy updates**. Así el resumen con IA usa las palabras de cada tipo y llega en puntos con etiqueta.
3. GitHub → sube `index.html` y `sw.js` (Add file → Upload files → Commit changes).

**Qué hay nuevo:**
- **Tipo de taller en «Cuéntanos»:** arriba del formulario aparece «Mejora de procesos · El de siempre» con **Cambiar tipo**. Los otros cuatro: **Definir competencias, Diagnóstico, Lluvia de ideas y Retrospectiva**. Cada uno pide solo lo que necesita (por ejemplo, el rol que se quiere definir) y «Armar mi taller» lo arma al instante, sin IA: preguntas, agenda y minutos listos para revisar en «Revisa y crea».
- **Mismas fases, otras palabras:** Check-in → Dolores / Comportamientos / Lo que vivimos / Ideas / Qué pasó → Votación → Ideas / Cómo se ve / Qué haríamos / Cómo la hacemos / Acciones → Resultados. El celular, la consola, los avisos, Inicio, el Excel y el PDF usan las palabras de cada tipo. Diagnóstico y Retrospectiva clasifican cada tarjeta por categoría (Funciona / Estorba; Funcionó / No funcionó / Aprendimos), y las categorías se pueden cambiar al crear.
- **«Juntar parecidas»** (todos los tipos, también Mejora de procesos): en la fase de tarjetas, quien facilita elige las que dicen lo mismo y las junta en un grupo con nombre. La sala vota el grupo como una sola opción. Se puede renombrar, agregar tarjetas o sacarlas; en el celular se ve «Ver lo que juntó».
- **Tiempo por fase:** cada fase trae sus minutos sugeridos (se ajustan al crear). En la banda de la consola se ve «13:57 restantes» con +1 min, +5 min y Pausa / Reanudar. Usa la hora del servidor: todos ven lo mismo.
- **Resultados por tipo:** ranking de lo elegido, la segunda parte con sus apoyos, hallazgos y resumen con IA. Excel y PDF con las hojas y secciones de cada tipo (por ejemplo: Competencias, Comportamientos, Votos, Cómo se ve y Apoyos).
- **Celular del participante completo:** lo que antes solo se veía en computadora ahora también está en celular y tablet: la bienvenida y la sala de espera dicen qué harás en cada actividad; la votación tiene filtro por etapa (o categoría) y «Mis votos»; Resultados y Cierre muestran «Lo que aportaste». «Respuestas en Validación» ya no aparece si el taller no tuvo Validación.
- **Los talleres de antes no cambian:** quedan como «Mejora de procesos».
- **Resumen con IA completo y con formato:** una línea de contexto y hasta cuatro puntos con etiqueta («Lo más votado», «Dónde duele»…) a todo el ancho del panel; cuatro puntos van en dos columnas. Botón **Copiar**: copia el título del taller y el resumen, y al pegar en correo, Word o Docs conserva negritas y viñetas. Los resúmenes que ya existían también se ven en puntos.
- **Taller cerrado:** quien abre el enlace de un taller que ya terminó ve «Este taller ya terminó», un agradecimiento y que lo que respondió la sala quedó guardado. Si el código no existe: «No encontramos este taller», con un campo para escribir el código.
- **Sin portada «Soy facilitador / Soy participante»:** colmena.work abre directo el acceso de quien facilita. Los participantes entran como siempre, con el QR o el enlace del taller (`?s=CÓDIGO`).
- **Contraste:** los indicadores de Inicio (▲ / ▼ contra el mes anterior) ya pasan el mínimo de accesibilidad.
- **Pruebas:** consola de los tipos nuevos 35/35 en computadora y celular, simulación de sala 8/8, recorrido de Mejora de procesos sin errores; 32 de base de datos; recorrido de cada tipo en celular, tablet y computadora, en claro y oscuro; Mejora de procesos sin cambios; 0 problemas de accesibilidad (axe, WCAG 2 AA) en 88 pantallas y en las 64 del recorrido del participante (celular, tablet y computadora).

**Más adelante:** Planeación y Toma de decisiones.

## v2.0.1 · Arreglo de seguridad y dos errores (13 oct 2026)

Sale de la revisión de código y de experiencia del 13 oct. Solo cambia la página: no lleva SQL ni cambios en funciones.

**Publicar (cuando no haya un taller en vivo):** GitHub → sube `index.html` y `sw.js` (Add file → Upload files → Commit changes).

**Qué arregla:**
- **Seguridad:** lo que escribe un participante (por ejemplo, un área con «Otra…», una etapa o el texto de una tarjeta) ya no puede ejecutarse en la consola de quien facilita: los indicadores de la consola lo muestran como texto.
- **Tipo equivocado:** si cambias de tipo después de armar el taller, «Revisa y crea» se bloquea en la barra de pasos y dice «Arma tu taller otra vez». Antes se podía crear el tipo anterior.
- **Datos del celular:** el aviso de «versión nueva» pregunta por `sw.js` (2 KB) en lugar de bajar la página completa cada 90 s, y solo avisa si lo publicado es más nuevo.
- **Pruebas:** consola de los tipos 35/35 en computadora y celular, simulación de sala 8/8, recorridos de Mejora de procesos sin errores, accesibilidad sin problemas en 64 pantallas y las pruebas de seguridad del revisor sin ninguna ejecución.

Carpeta: raíz = v2.0.1; `versiones/v2.0` = la anterior, para regresar.

## v2.2 · Creador multimétodo y edición segura en lobby (19 oct 2026)

El creador converge los cinco métodos en **Objetivo → Contexto → Revisa y abre**, autogenera la configuración válida y permite ajustar una sala mientras siga vacía en lobby.

**Publicar (solo después de aprobación explícita y cuando no haya un taller en vivo):**
1. Si la base aún no está en v2.1, corre primero `migracion-v210-seguridad.sql`.
2. Supabase → SQL Editor → pega `migracion-v220-lobby-edit.sql` → **Run**. La fila final debe decir `candados = 2`, `version = 2.2`. Se puede repetir sin cambiar el esquema.
3. Después sube `index.html` y `sw.js`. La interfaz nueva conserva su comprobación anticipada y PostgreSQL aplica el bloqueo definitivo.

**Qué protege la v2.2:**
- La configuración solo cambia en `lobby`, siendo propietario y antes de la primera entrada.
- La primera entrada marca la sala como bloqueada dentro de la misma transacción.
- Una entrada y una edición simultáneas se serializan: si la entrada termina primero, la edición se rechaza sin cambios parciales.
- Cambiar de fase, usar el reloj, cerrar y editar el resumen siguen disponibles cuando corresponde.
- Las salas existentes con participantes quedan bloqueadas automáticamente al aplicar la migración.

**Pruebas:** PostgreSQL 16 desechable, **87/87** pruebas de comportamiento; `setup.sql` y la migración son idempotentes; el esquema armado desde cero coincide con el camino de producción; 16 migraciones archivadas se detienen sin alterar la base; carreras reales de votos, apoyos y entrada contra edición respetan sus límites.

Desplegada en `https://colmena.work` y Supabase el 20 oct 2026.

## v2.3 · Analítica privada de producto (20 oct 2026)

Nueva sección **Analítica**, visible únicamente para cuentas con rol Admin y acceso fuerte. Mide recorridos y señales de fricción de facilitadores y participantes sin capturar respuestas, nombres, correos, códigos ni texto escrito.

**Publicar (requiere aprobación separada):**
1. Supabase → SQL Editor → pega `migracion-v230-analitica.sql` → **Run**. La fila final debe decir `funciones = 3`, `version = 2.3`.
2. Después publica `index.html` y `sw.js`.

**Qué incluye:**
- Embudos del creador y del participante; errores, validaciones, reintentos y clics repetidos.
- Filtros de 7, 30 y 90 días, y por taller.
- Comparación por taller, celular/tableta/computadora, navegador y app instalada/web.
- RPC de entrada con lista cerrada de eventos y propiedades; las tablas no tienen lectura ni escritura directa desde el navegador.
- Solo `ws_analytics()` devuelve agregados y exige rol Admin. Los facilitadores pueden enviar sus propios eventos, pero no consultarlos.
- Detalle técnico por 90 días; una tarea diaria conserva conteos agregados y elimina el detalle vencido.
- La telemetría falla silenciosamente: nunca bloquea entrar, responder, facilitar ni crear un taller.

Desplegada en `https://colmena.work` y Supabase el 20 oct 2026.

## v2.3.1 · Último acceso del equipo (20 oct 2026)

En **Equipo**, cada cuenta muestra `Último acceso hace…` o `Nunca ha entrado`. La fecha usa el dato más reciente entre el último inicio de sesión de Supabase y la última apertura técnica de Colmena; al pasar el cursor se ve la fecha y hora exactas.

- Solo un Admin con acceso fuerte puede consultar las fechas mediante `ws_team_activity()`.
- No se conceden permisos sobre `auth.users` ni se muestran eventos, IP, respuestas o actividad de participantes.
- Si la RPC aún no está instalada, Equipo sigue funcionando y muestra `Nunca ha entrado` en lugar de bloquear la vista.

**Publicar:** corre `migracion-v231-ultimo-acceso.sql`; debe devolver `funciones = 1`, `version = 2.3.1`. Después publica `index.html` y `sw.js`.

Desplegada en `https://colmena.work` y Supabase el 20 oct 2026.

## v2.3.2 · Mapa privado de interacciones (20 oct 2026)

**Analítica** incorpora un mapa de calor semántico que muestra qué acciones se intentan con mayor frecuencia, con **Participantes** como vista inicial y filtros separados para Facilitación, Creador y dispositivo.

- Participantes: registro, selección de avatar/etapa, check-in, publicación de tarjetas, votos, calificaciones, propuestas y apoyos.
- Facilitación: QR, avance de fases, reloj, edición, presentación, exportación y resumen.
- Creador: objetivo, avance/retroceso, IA, preparación y apertura del taller.
- El mapa usa nombres técnicos de un catálogo cerrado. No captura coordenadas, texto visible, respuestas ni identificadores de tarjetas/personas.
- Solo `ws_interaction_map()` devuelve agregados y exige rol Admin; las tablas continúan sin permisos directos para el navegador.
- Los filtros de taller y dispositivo usan el componente desplegable propio de Colmena —no el selector predeterminado del navegador— con teclado, foco y chevron centrado.

**Pruebas:** PostgreSQL 16 desechable, **116/116** pruebas de comportamiento; sintaxis JavaScript correcta; vista responsiva a 390 px sin desbordamiento; Lighthouse 100/100/100.

**Publicar:** corre `migracion-v232-mapa-interacciones.sql`; debe devolver `funciones = 2`, `version = 2.3.2`. Después publica `index.html` y `sw.js`.

Desplegada en `https://colmena.work` y Supabase el 20 oct 2026.

## v2.1 · Seguridad y datos + arreglos rápidos al crear (13 oct 2026)

Paquetes A y B de la revisión del 13 oct. Incluye la v2.0.1. Plan gratis de Supabase.

**Publicar (en este orden, cuando no haya un taller en vivo):**
1. Supabase → SQL Editor → New query → pega todo `migracion-v210-seguridad.sql` → **Run**. Al final sale una fila: `columnas = 9`, `candados = 2`, `version = 2.1`. Se puede correr dos veces sin problema.
2. GitHub → sube `index.html` y `sw.js` (Add file → Upload files → Commit changes).

No hay funciones que desplegar. La página nueva también funciona si el SQL todavía no se corre, y la anterior funciona con el SQL nuevo.

**A · Seguridad y datos**
- **El participante solo cambia lo suyo:** su perfil, su check-in y su avance. Ya no puede pasarse a otro taller ni marcar como terminada una actividad que todavía no empieza (si quien facilita regresa a una actividad anterior, lo ya marcado se queda). Las etapas que elige deben ser del taller.
- **Nombre, apellido, área y puesto sin < ni >:** el celular los quita al escribir y la base ya no los acepta. Lo mismo al agregar áreas y roles en el creador.
- **Candado de votos y apoyos:** dos toques al mismo tiempo ya no rebasan el tope (antes, 8 puntos con un tope de 5).
- **«Terminé» que no se guarda:** el celular avisa «No se pudo guardar. Revisa tu conexión e intenta de nuevo.», regresa a como estaba y el botón sigue ahí. Mientras guarda, el botón se desactiva.
- **`setup.sql` = estado actual y versión de la base:** ver «Actualizar desde una versión anterior». Las migraciones de antes viven en `migraciones-anteriores/`.
- **Todo en la carpeta:** SQL, funciones, pruebas de base de datos, de pantallas y de seguridad (`pruebas/`). Falta el repositorio privado con historial.

**B · Arreglos rápidos al crear**
- **Palabras de quien facilita:** sin «quick wins», «apoyos», «pasan a» ni códigos QW-01 / RG-01 / TM-01. Por ejemplo: «Mejoras rápidas», «Votos para apoyar propuestas», «¿Cuántos problemas trabajarán en Ideas?», «Pedir a la sala que califique mejoras».
- **Tipo de taller:** sin «El de siempre» ni «Design Thinking»; el botón dice «Elegir otro tipo» y abajo se nombran los otros cuatro.
- **Botón miel fijo abajo** en «Cuéntanos» («Generar propuesta» / «Armar mi taller») y en «Revisa y crea» («Crear y ver el QR»), con la consecuencia de crear junto al botón y legible.
- **Errores junto al campo:** borde rojo y mensaje debajo, para lectores de pantalla también; se borran en cuanto el dato ya sirve (también al agregar áreas). Las listas (áreas, roles, categorías, herramientas) tienen botón **Agregar**.
- **La pregunta principal, lo primero en «Revisa y crea»:** grande y editable ahí mismo; la agenda la muestra en el momento 2. En la pestaña Preguntas se llama «Pregunta principal», sin «opcional».
- **Sala de espera:** mientras no entra nadie, el botón miel es «Proyectar QR» y la sala dice «SALA ABIERTA»; con la primera persona, el miel pasa a «Abrir Check-in». Arriba, «Proyectar QR» (antes «QR para entrar»).
- **Ejemplos de oficina** (Grupo Alfa, Contratación, vacantes) en lugar de la aseguradora y los «talleres» mecánicos.
- **Borrador a la vista:** en el Inicio con tablero aparece en Pendientes «Tienes un taller sin crear» con **Seguir**; «Propuesta lista» depende de si hay propuesta, no del paso.
- **Detalles:** migas «Inicio › Crear taller › Paso 2 de 2: Revisa y crea» y el menú marca Inicio; los minutos sugeridos suman exactamente la duración; «1 área»; la pregunta de Retrospectiva «Piensa en «…»: ¿qué pasó?»; el recorrido explica el tipo de taller y al cerrarlo la página regresa arriba.
- **Armar a mano:** las herramientas ya no saltan de una etapa a otra al escribir nombres; una etapa sin nombre todavía no lleva herramientas, y dos etapas con el mismo nombre se marcan y no dejan crear.

**Pruebas:** base de datos 70/70 en un Postgres local que simula Supabase; `setup.sql` arma la misma base que el camino de producción y se puede volver a correr sin cambiar nada; las 16 migraciones anteriores se detienen solas; dos votos o dos apoyos al mismo tiempo ya no rebasan el tope (`python3 pruebas/sql/probar_sql.py`). Arreglos del creador 36/36 en computadora y celular; «Terminé» sin conexión, < y > en el perfil y herramientas por etapa 14/14; crear cada tipo 92/92 (computadora y celular); creador v1.28 22/22; consola 35/35; celular 14/14; copia de prueba 8/8; cambiar de tipo no crea el anterior; seguridad: 0 ejecuciones en las pruebas del revisor; accesibilidad (axe, WCAG 2 AA): 0 problemas en 40 pantallas, claro y oscuro, 1440 y 390 px. Palabras del sistema visibles al crear: de 45 a 0.

Carpeta: raíz = v2.2; `versiones/v2.0.1` conserva la última copia archivada anterior.
