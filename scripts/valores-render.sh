#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Genera, a partir del Wallet de Oracle descomprimido, los dos valores que
#  Render necesita para conectarse a la base sin montar archivos:
#
#    ORACLE_JDBC_URL  descriptor completo de conexion (no necesita tnsnames.ora)
#    JAVA_OPTS        incluye -Doracle.net.wallet_location=data:;base64,...
#                     (el cwallet.sso codificado: el driver lo lee en memoria)
#
#  Uso:
#    ./scripts/valores-render.sh ~/.oracle/wallets/FULLSTACK3 [alias_tns]
#
#  Escribe los valores en la salida estandar para pegarlos en el grupo de
#  variables "foro-oracle" de Render. Son secretos: no los guardes en el repo.
# ---------------------------------------------------------------------------
set -euo pipefail

WALLET="${1:?Uso: $0 <carpeta-del-wallet> [alias_tns]}"
ALIAS="${2:-fullstack3_tp}"

[ -f "$WALLET/cwallet.sso" ] || { echo "No encuentro $WALLET/cwallet.sso" >&2; exit 1; }
[ -f "$WALLET/tnsnames.ora" ] || { echo "No encuentro $WALLET/tnsnames.ora" >&2; exit 1; }

DESCRIPTOR="$(grep -i "^${ALIAS}[[:space:]]*=" "$WALLET/tnsnames.ora" | sed -E 's/^[^=]*=[[:space:]]*//')"
[ -n "$DESCRIPTOR" ] || { echo "El alias $ALIAS no esta en tnsnames.ora" >&2; exit 1; }

WALLET_B64="$(base64 < "$WALLET/cwallet.sso" | tr -d '\n')"

echo "ORACLE_JDBC_URL=jdbc:oracle:thin:@${DESCRIPTOR}"
echo
echo "JAVA_OPTS=-XX:MaxRAMPercentage=60 -Doracle.net.wallet_location=data:;base64,${WALLET_B64}"
