# foro-despliegue

Despliegue en **Docker Cloud** del *Sistema de Foros en Línea* (CuboClub):
las imágenes se publican en **Docker Hub** (Container Registry) y se ejecutan
con **Docker Compose** en **Play with Docker** (labs.play-with-docker.com), con
la base de datos en **Oracle Cloud**.

| Componente | Imagen | Puerto | Repositorio |
|---|---|---|---|
| Frontend Angular + nginx | `<usuario>/foro-web:1.0.0` | 80 | `foro-web` |
| Usuarios e inicio de sesión | `<usuario>/foro-usuarios:2.0.0` | 8081 | `foro-usuarios` |
| Foro: temas y comentarios | `<usuario>/foro-temas:2.0.0` | 8082 | `foro-temas` |
| Moderación | `<usuario>/foro-moderacion:1.0.1` | 8083 | `foro-moderacion` |

> El frontend y el backend **funcionan por separado** (así lo pide la
> actividad): el frontend usa sus propios arreglos en memoria y el backend se
> demuestra con Postman.

```
                    Docker Hub (Container Registry)
              foro-web · foro-usuarios · foro-temas · foro-moderacion
                                 │  docker compose pull
                                 ▼
 ┌───────────────── Play with Docker (instancia) ─────────────────┐
 │  foro-web :80   foro-usuarios :8081   foro-temas :8082          │
 │                                        ▲                        │
 │                 foro-moderacion :8083 ─┘ http://foro-temas:8082 │
 │                 ./wallet ──(solo lectura)──▶ /opt/oracle/wallet │
 └────────────────────────────────┬───────────────────────────────┘
                                  │ TLS 1522 (Wallet)
                                  ▼
                 Oracle Autonomous Database · esquema FORO
```

---

## 1. Publicar las imágenes (desde el computador de desarrollo)

Con los repositorios clonados uno al lado del otro (`foro-usuarios`,
`foro-temas`, `foro-moderacion`, `foro-web`, `foro-despliegue`):

```bash
docker login                                   # cuenta de Docker Hub
./scripts/publicar-imagenes.sh <usuario-dockerhub>
```

Construye cada imagen para **linux/amd64** (Play with Docker) y **linux/arm64**
(Mac con Apple Silicon) y la sube con su versión y `latest`. Los Dockerfile son
multi-etapa: compilan dentro de Docker, así que no hace falta Java ni Node en la
máquina que publica.

**El Wallet de Oracle no va en ninguna imagen** (`.dockerignore` lo excluye):
las imágenes pueden ser públicas sin exponer credenciales.

## 2. Preparar la base de datos (una vez)

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
> (*Autonomous Database ▸ FULLSTACK-3 ▸ Start*).

## 3. Desplegar en Play with Docker

1. Entra a <https://labs.play-with-docker.com>, inicia sesión con la cuenta de
   Docker Hub y pulsa **Start** → **+ ADD NEW INSTANCE**.
2. En la terminal de la instancia:

   ```bash
   git clone https://github.com/<usuario-github>/foro-despliegue.git
   cd foro-despliegue
   cp .env.example .env
   vi .env          # DOCKERHUB_USUARIO, ORACLE_PASSWORD, FORO_JWT_SECRETO
   ```

   `FORO_JWT_SECRETO` tiene que ser el mismo para los tres servicios (lo es: lo
   leen del mismo `.env`). Se puede generar con `openssl rand -base64 48`.

3. **Sube el Wallet**: arrastra el archivo `Wallet_FULLSTACK3.zip` desde el
   explorador de archivos hasta la terminal de Play with Docker; queda en el
   directorio actual. Muévelo a `foro-despliegue/` si hace falta.
4. Despliega:

   ```bash
   ./scripts/desplegar.sh
   ```

   Descomprime el Wallet en `wallet/`, le da permiso de lectura al usuario sin
   privilegios de los contenedores, baja las imágenes y las levanta.
5. Espera unos 40 segundos y comprueba:

   ```bash
   docker compose ps
   curl -s localhost:8081/api/estado      # "motor" : "Oracle Database 23ai ..."
   ```

6. **URL públicas**: arriba de la terminal aparecen los puertos publicados
   (`80`, `8081`, `8082`, `8083`). Cada uno abre una URL pública del tipo
   `http://ip172-18-0-XX-<sesion>-8081.direct.labs.play-with-docker.com`. Si un
   puerto no aparece, usa **OPEN PORT** y escríbelo.
   - El puerto **80** es el frontend.
   - Copia las URL de **8081, 8082 y 8083** en el entorno de Postman
     `foro-docker-cloud` (variables `urlUsuarios`, `urlForo`, `urlModeracion`) y
     corre la colección.

### Probar sin base de datos

Con `PERFIL=local` en `.env` los tres servicios usan H2 en memoria con los
mismos datos de ejemplo y no necesitan Wallet. Sirve para comprobar el
despliegue si Oracle está detenido; la demostración final va con
`PERFIL=oracle`.

### Comandos útiles

```bash
docker compose logs -f foro-moderacion     # logs de un servicio
docker compose restart foro-temas
docker compose down                        # detener todo
docker stats --no-stream                   # memoria de cada contenedor
```

## 4. Construir desde el código (sin Docker Hub)

```bash
docker compose -f docker-compose.yml -f docker-compose.build.yml up -d --build
```

## 5. Verificación realizada

Con las cuatro imágenes construidas desde el código y `PERFIL=local`
(ver [`docs/registros/01_verificacion_docker_compose.txt`](docs/registros/01_verificacion_docker_compose.txt)):

- Los cuatro contenedores levantan juntos; el frontend responde en el puerto 80
  y nginx devuelve la SPA en cualquier ruta (`/login`, `/temas/3`, `/admin/usuarios`).
- Los tres servicios Java corren como usuario sin privilegios (`uid=999(app)`).
- La colección de Postman completa (60 peticiones, 108 aserciones) pasa contra
  los contenedores, incluida la llamada de `foro-moderacion` a
  `http://foro-temas:8082` dentro de la red de Compose.
- Con `foro-temas` detenido, banear responde `503 Servicio no disponible`.

## 6. Variables (`.env`)

| Variable | Para qué |
|---|---|
| `DOCKERHUB_USUARIO` | Usuario de Docker Hub de las imágenes |
| `PERFIL` | `oracle` (entrega) o `local` (H2, sin base de datos) |
| `TNS_ALIAS` | Alias del `tnsnames.ora` del Wallet (`fullstack3_tp`) |
| `ORACLE_USER` / `ORACLE_PASSWORD` | Esquema `FORO` |
| `FORO_JWT_SECRETO` | Secreto compartido del JWT |
| `FORO_CORS_ORIGENES` | Orígenes permitidos por CORS |
| `VERSION_*` | Versión de cada imagen (por omisión, la de la entrega) |
