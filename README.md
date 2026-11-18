# foro-despliegue

Despliegue en la nube del *Sistema de Foros en Línea* (CuboClub): los cuatro
componentes corren como **contenedores Docker en Render** (render.com),
construidos con el Dockerfile multi-etapa de cada repositorio, con la base de
datos en **Oracle Cloud**.

| Componente | Repositorio | Versión | Puerto del contenedor |
|---|---|---|---|
| Frontend Angular + nginx | [`foro-web`](https://github.com/ralow-uc/foro-web) | 1.0.1 | 80 |
| Usuarios e inicio de sesión | [`foro-usuarios`](https://github.com/ralow-uc/foro-usuarios) | 2.0.0 | 8081 |
| Foro: temas y comentarios | [`foro-temas`](https://github.com/ralow-uc/foro-temas) | 2.0.0 | 8082 |
| Moderación | [`foro-moderacion`](https://github.com/ralow-uc/foro-moderacion) | 1.0.1 | 8083 |

> El frontend y el backend **funcionan por separado** (así lo pide la
> actividad): el frontend usa sus propios arreglos en memoria y el backend se
> demuestra con Postman.

```
   GitHub (un repositorio por componente, rama main)
        │  Render clona y construye cada Dockerfile
        ▼
 ┌──────────────────────────── Render ─────────────────────────────┐
 │  foro-web        https://foro-web-….onrender.com                │
 │  foro-usuarios   https://foro-usuarios-….onrender.com           │
 │  foro-temas      https://foro-temas-….onrender.com   ◀──┐       │
 │  foro-moderacion https://foro-moderacion-….onrender.com ─┘ HTTPS │
 │  grupo de variables "foro-oracle": URL, usuario, contraseña,    │
 │  Wallet (base64) y secreto del JWT, compartidos por los tres    │
 └───────────────────────────────┬─────────────────────────────────┘
                                 │ TLS 1522 (Wallet en memoria)
                                 ▼
                Oracle Autonomous Database · esquema FORO
```

Todo el despliegue está descrito como código en [`render.yaml`](render.yaml)
(*Blueprint* de Render): los cuatro servicios, su repositorio, plan, región,
*health check* y variables.

---

## 1. Preparar la base de datos (una vez)

Desde `foro-temas`, antes de desplegar su v2.0.0:

```bash
./scripts/sql.sh foro scripts/03_moderacion_de_contenido.sql
```

Desde `foro-moderacion`:

```bash
./scripts/sql.sh foro scripts/01_crear_tablas.sql
./scripts/sql.sh foro scripts/02_datos_iniciales.sql
```

> Una Autonomous Database Always Free **se detiene sola tras 7 días sin uso**.
> Si los servicios no conectan (`ORA-12514`), iníciala en la consola de OCI
> (*Autonomous Database ▸ FULLSTACK-3 ▸ Iniciar*).

## 2. Desplegar en Render

### El Wallet sin archivos

Render no permite montar una carpeta en el contenedor, así que el Wallet no se
monta: el driver JDBC de Oracle acepta el `cwallet.sso` **codificado en base64**
en la propiedad `oracle.net.wallet_location=data:;base64,…` y lo usa en
memoria. Con el descriptor completo de conexión en la URL tampoco hace falta
`tnsnames.ora`. Ninguno de los cuatro Dockerfile cambia y **el Wallet nunca
entra a una imagen ni a un repositorio**: vive solo como variable secreta en
Render.

Los dos valores se generan con:

```bash
./scripts/valores-render.sh ~/.oracle/wallets/FULLSTACK3
```

### Pasos

1. En <https://dashboard.render.com> → **New** → **Blueprint** → repositorio
   público `https://github.com/ralow-uc/foro-despliegue`.
2. Render lee `render.yaml` y pide los valores marcados `sync: false`:

   | Variable | Valor |
   |---|---|
   | `ORACLE_JDBC_URL` | primera línea de `valores-render.sh` |
   | `JAVA_OPTS` | segunda línea de `valores-render.sh` |
   | `ORACLE_PASSWORD` | contraseña del esquema `FORO` |
   | `FORO_TEMAS_URL` | URL pública de `foro-temas` (se completa después del primer despliegue) |

   `FORO_JWT_SECRETO` lo genera Render al azar (`generateValue`) dentro del
   grupo `foro-oracle`, así que los tres servicios comparten el mismo.
3. **Apply**: Render construye las cuatro imágenes y las publica, cada una con
   su URL HTTPS.
4. Comprueba cada servicio: `GET /api/estado` tiene que decir
   `"motor" : "Oracle AI Database 26ai …"`.

### Plan gratuito

Los servicios gratuitos de Render **se duermen tras 15 minutos sin tráfico** y
la primera petición después tarda en responder (un microservicio Spring Boot
puede demorar un par de minutos en despertar). Antes de una demostración, abre
`/api/estado` de los tres y el frontend, y espera a que respondan.

## 3. Ejecutar en local con Docker Compose

Con los repositorios clonados uno al lado del otro (`foro-usuarios`,
`foro-temas`, `foro-moderacion`, `foro-web`, `foro-despliegue`):

```bash
cp .env.example .env && vi .env    # ORACLE_PASSWORD, FORO_JWT_SECRETO
# Wallet de Oracle descomprimido en ./wallet (está en .gitignore)
docker compose up -d --build
docker compose ps
curl -s localhost:8081/api/estado
```

Con `PERFIL=local` en `.env` los tres servicios usan H2 en memoria con los
mismos datos de ejemplo y no necesitan Wallet.

```bash
docker compose logs -f foro-moderacion     # logs de un servicio
docker compose down                        # detener todo
```

## 4. Verificación realizada en local

Con las cuatro imágenes construidas desde el código
(ver [`docs/registros/01_verificacion_docker_compose.txt`](docs/registros/01_verificacion_docker_compose.txt)):

- Los cuatro contenedores levantan juntos; el frontend responde en el puerto 80
  y nginx devuelve la SPA en cualquier ruta (`/login`, `/temas/3`, `/admin/usuarios`).
- Los tres servicios Java corren como usuario sin privilegios (`uid=999(app)`).
- La colección de Postman completa (60 peticiones, 108 aserciones) pasa contra
  los contenedores, con H2 y también con **Oracle Cloud** (dos corridas
  seguidas), incluida la llamada de `foro-moderacion` a `foro-temas`.
- Con `foro-temas` detenido, banear responde `503 Servicio no disponible`.
- Un contenedor sin el Wallet montado conecta a Oracle usando solo
  `ORACLE_JDBC_URL` y `JAVA_OPTS` de `valores-render.sh` (la configuración de
  Render).

## 5. Variables

| Variable | Dónde | Para qué |
|---|---|---|
| `SPRING_PROFILES_ACTIVE` | Render (grupo) | `oracle` |
| `ORACLE_JDBC_URL` | Render (grupo) | Descriptor de conexión de `fullstack3_tp` |
| `ORACLE_USER` / `ORACLE_PASSWORD` | Render (grupo) · `.env` | Esquema `FORO` |
| `JAVA_OPTS` | Render (grupo) | Memoria de la JVM y Wallet en base64 |
| `FORO_JWT_SECRETO` | Render (grupo, generado) · `.env` | Secreto compartido del JWT |
| `PORT` | Render (por servicio) | Puerto en que escucha el contenedor |
| `FORO_TEMAS_URL` | Render (`foro-moderacion`) | URL pública de `foro-temas` |
| `PERFIL`, `TNS_ALIAS` | `.env` | Solo para la ejecución local |
