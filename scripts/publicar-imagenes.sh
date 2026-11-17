#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Construye y publica en Docker Hub las imagenes de los cuatro componentes,
#  para linux/amd64 (Play with Docker) y linux/arm64 (Mac con Apple Silicon).
#
#  Uso (desde foro-despliegue, con los repositorios uno al lado del otro):
#    docker login
#    ./scripts/publicar-imagenes.sh <usuario-dockerhub>
#
#  Cada imagen se etiqueta con su version y con "latest".
# ---------------------------------------------------------------------------
set -euo pipefail

USUARIO="${1:?Uso: $0 <usuario-dockerhub>}"
RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
PLATAFORMAS="${PLATAFORMAS:-linux/amd64,linux/arm64}"

# componente:version
COMPONENTES=(
  "foro-usuarios:2.0.0"
  "foro-temas:2.0.0"
  "foro-moderacion:1.0.1"
  "foro-web:1.0.0"
)

docker buildx inspect foro-multiarq >/dev/null 2>&1 || docker buildx create --name foro-multiarq --use
docker buildx use foro-multiarq

for c in "${COMPONENTES[@]}"; do
  nombre="${c%%:*}"; version="${c##*:}"
  echo "==> $USUARIO/$nombre:$version  ($PLATAFORMAS)"
  docker buildx build --platform "$PLATAFORMAS" \
    -t "$USUARIO/$nombre:$version" -t "$USUARIO/$nombre:latest" \
    --push "$RAIZ/$nombre"
done

echo
echo "Listo. Imagenes publicadas en https://hub.docker.com/u/$USUARIO"
