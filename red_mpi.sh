#!/bin/bash
# Helper para preparar, conectar y correr MPI entre varias maquinas en red (LAN o ZeroTier/Tailscale).
#
# Uso:
#   ./red_mpi.sh preparar
#   ./red_mpi.sh conectar <usuario@IP> [usuario2@IP2 ...]
#   ./red_mpi.sh correr [nocoord|coord] [ruta_imagen] [np]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="/tmp/tp_final"
SLOTS_POR_PC=2

uso() {
    echo "Uso:"
    echo "  $0 preparar"
    echo "      -> Prepara esta PC (dependencias, SSH, MTU ZeroTier, compila en $WORK_DIR)."
    echo "  $0 conectar <usuario@IP> [usuario2@IP2 ...]"
    echo "      -> Configura SSH sin clave, copia/compila en las otras PCs y arma $WORK_DIR/machinefile."
    echo "  $0 correr [nocoord|coord] [imagen] [np]"
    echo "      -> Corre el programa sobre las maquinas de $WORK_DIR/machinefile."
    echo ""
    echo "Ejemplo:"
    echo "  ./red_mpi.sh preparar"
    echo "  ./red_mpi.sh conectar usuario@10.1.112.129"
    echo "  ./red_mpi.sh correr nocoord imagenes/bloques_128.txt 4"
}

preparar_local() {
    echo "==> [1/4] Verificando paquetes necesarios..."
    FALTA_PAQ=0
    for CMD in gcc mpicc mpiexec sshd; do
        if ! command -v "$CMD" >/dev/null 2>&1; then
            FALTA_PAQ=1
        fi
    done
    if [ "$FALTA_PAQ" -eq 1 ] || ! echo '#include <mpi.h>' | mpicc -E - >/dev/null 2>&1; then
        echo "Instalando build-essential, openmpi y openssh (puede pedir clave de sudo)..."
        sudo apt update
        sudo apt install -y build-essential openmpi-bin libopenmpi-dev openssh-server openssh-client
    else
        echo "Paquetes OK."
    fi

    echo "==> [2/4] Activando servicio SSH..."
    if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files 2>/dev/null | grep -q '^ssh\.service'; then
        sudo systemctl enable --now ssh >/dev/null 2>&1 || sudo service ssh start
    else
        sudo service ssh start || true
    fi
    if command -v ufw >/dev/null 2>&1 && sudo -n ufw status 2>/dev/null | grep -q "Status: active"; then
        sudo ufw allow ssh >/dev/null || true
    fi

    echo "==> [3/4] Ajustando MTU si hay interfaz ZeroTier (evita cuelgues en SSH/MPI)..."
    for IFACE in $(ip -o link show | awk -F': ' '{print $2}' | grep '^zt' || true); do
        CUR_MTU=$(cat "/sys/class/net/$IFACE/mtu" 2>/dev/null || echo 1500)
        if [ "$CUR_MTU" -gt 1280 ]; then
            echo "Bajando MTU de $IFACE ($CUR_MTU -> 1280)..."
            sudo ip link set dev "$IFACE" mtu 1280
        else
            echo "MTU de $IFACE ya esta en $CUR_MTU."
        fi
    done

    echo "==> [4/4] Preparando y compilando en $WORK_DIR..."
    if [ "$SCRIPT_DIR" != "$WORK_DIR" ]; then
        mkdir -p "$WORK_DIR"
        cp -f "$SCRIPT_DIR"/Makefile "$SCRIPT_DIR"/*.c "$SCRIPT_DIR"/*.h \
              "$SCRIPT_DIR"/machinefile "$SCRIPT_DIR"/*.sh "$WORK_DIR"/ 2>/dev/null || true
        rm -rf "$WORK_DIR/imagenes"
        cp -r "$SCRIPT_DIR/imagenes" "$WORK_DIR/imagenes"
    fi

    make -C "$WORK_DIR" clean >/dev/null
    make -C "$WORK_DIR" all

    echo ""
    echo "Listo en esta PC. Tu usuario e IPs disponibles son:"
    USER_LOCAL="$(whoami)"
    for IP in $(hostname -I); do
        echo "  $USER_LOCAL@$IP"
    done
}

asegurar_llave_ssh() {
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh

    if [ -f ~/.ssh/id_ed25519.pub ]; then
        echo ~/.ssh/id_ed25519.pub
    elif [ -f ~/.ssh/id_rsa.pub ]; then
        echo ~/.ssh/id_rsa.pub
    else
        ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519 >/dev/null
        echo ~/.ssh/id_ed25519.pub
    fi
}

asegurar_ssh_config_host() {
    local IP="$1"
    touch ~/.ssh/config
    chmod 600 ~/.ssh/config
    if ! grep -qE "^Host[[:space:]]+$IP([[:space:]]|$)" ~/.ssh/config; then
        printf '\nHost %s\n    KexAlgorithms curve25519-sha256\n' "$IP" >> ~/.ssh/config
    fi
}

conectar_nodos() {
    if [ "$#" -lt 1 ]; then
        echo "Error: indica al menos un nodo remoto (ej: mocco@10.1.112.129)."
        uso
        exit 1
    fi

    preparar_local

    local PUB_KEY
    PUB_KEY="$(asegurar_llave_ssh)"
    echo ""
    echo "==> Usando llave SSH: $PUB_KEY"

    local MF="$WORK_DIR/machinefile"
    {
        echo "# Generado por red_mpi.sh"
        echo "localhost slots=$SLOTS_POR_PC"
    } > "$MF"

    local TOTAL_SLOTS="$SLOTS_POR_PC"

    for DEST in "$@"; do
        local IP="${DEST#*@}"

        echo ""
        echo "==> Configurando nodo remoto: $DEST"
        if ! ping -c 2 -W 2 "$IP" >/dev/null 2>&1; then
            echo "ERROR: No responde el ping a $IP."
            echo "Chequea que la otra PC este prendida, conectada a la red/ZeroTier y autorizada."
            exit 1
        fi

        asegurar_ssh_config_host "$IP"

        if ! ssh -o BatchMode=yes -o ConnectTimeout=4 "$DEST" true 2>/dev/null; then
            echo "Copiando llave SSH a $DEST (si pide confirmacion escribi 'yes' y luego su clave):"
            ssh-copy-id -i "$PUB_KEY" "$DEST"
        else
            echo "Acceso SSH sin clave ya configurado."
        fi

        echo "Sincronizando $WORK_DIR y compilando en $DEST..."
        ssh "$DEST" "mkdir -p $WORK_DIR"
        scp -q -r "$WORK_DIR"/Makefile "$WORK_DIR"/*.c "$WORK_DIR"/*.h \
                  "$WORK_DIR"/imagenes "$DEST:$WORK_DIR/"
        ssh "$DEST" "make -C $WORK_DIR clean >/dev/null && make -C $WORK_DIR all"

        echo "$DEST slots=$SLOTS_POR_PC" >> "$MF"
        TOTAL_SLOTS=$((TOTAL_SLOTS + SLOTS_POR_PC))
    done

    echo ""
    echo "==> machinefile armado ($MF):"
    cat "$MF"

    echo ""
    echo "==> Probando ejecucion distribuida con hostname (-np $TOTAL_SLOTS):"
    correr_mpi_cmd "$TOTAL_SLOTS" hostname
}

detectar_mca_red() {
    local MF="$WORK_DIR/machinefile"
    local PRIMERA_IP
    PRIMERA_IP=$(grep -vE '^\s*(#|$|localhost)' "$MF" | head -n 1 | awk '{print $1}')
    PRIMERA_IP="${PRIMERA_IP#*@}"

    if [ -z "$PRIMERA_IP" ]; then
        echo ""
        return
    fi

    local DEV
    DEV=$(ip route get "$PRIMERA_IP" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}')
    if [ -z "$DEV" ]; then
        echo ""
        return
    fi

    if [[ "$DEV" == tailscale* ]]; then
        echo "--mca btl_tcp_if_include $DEV --mca oob_tcp_if_include $DEV"
        return
    fi

    local SUBRED
    SUBRED=$(ip route show dev "$DEV" proto kernel 2>/dev/null | awk '{print $1; exit}')
    if [ -n "$SUBRED" ]; then
        echo "--mca btl_tcp_if_include $SUBRED --mca oob_tcp_if_include $SUBRED"
    else
        echo ""
    fi
}

correr_mpi_cmd() {
    local NP="$1"
    shift
    local MCA_FLAGS
    MCA_FLAGS="$(detectar_mca_red)"

    cd "$WORK_DIR"
    # shellcheck disable=SC2086
    echo "+ mpiexec $MCA_FLAGS --hostfile $WORK_DIR/machinefile -np $NP $*"
    # shellcheck disable=SC2086
    mpiexec $MCA_FLAGS --hostfile "$WORK_DIR/machinefile" -np "$NP" "$@"
}

correr_programa() {
    local MODO="${1:-nocoord}"
    local IMAGEN="${2:-imagenes/bloques_128.txt}"
    local NP="$3"

    if [ ! -f "$WORK_DIR/machinefile" ]; then
        echo "Error: no existe $WORK_DIR/machinefile. Corre primero '$0 conectar <usuario@IP>'."
        exit 1
    fi

    local BIN
    case "$MODO" in
        nocoord) BIN="./region_labeling_nocoord" ;;
        coord)   BIN="./region_labeling_coord" ;;
        *)
            echo "Modo invalido: '$MODO'. Usa 'nocoord' o 'coord'."
            exit 1
            ;;
    esac

    if [ -z "$NP" ]; then
        NP=$(grep -vE '^\s*(#|$)' "$WORK_DIR/machinefile" | awk -F'slots=' '{s += ($2 ? $2 : 1)} END {print s}')
    fi

    correr_mpi_cmd "$NP" "$BIN" "$IMAGEN"
}

case "${1:-}" in
    preparar)
        preparar_local
        ;;
    conectar)
        shift
        conectar_nodos "$@"
        ;;
    correr)
        shift
        correr_programa "$@"
        ;;
    *)
        uso
        exit 1
        ;;
esac
