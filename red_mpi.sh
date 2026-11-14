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
MPI_PREFIX="/tmp/tp_mpi"
OPENMPI_VER="5.0.11"
SLOTS_POR_PC=2

uso() {
    echo "Uso:"
    echo "  $0 preparar"
    echo "      -> Prepara esta PC (dependencias, SSH, MTU ZeroTier, OpenMPI $OPENMPI_VER en $MPI_PREFIX y compila en $WORK_DIR)."
    echo "  $0 conectar <usuario@IP> [usuario2@IP2 ...]"
    echo "      -> Configura SSH sin clave, sincroniza $WORK_DIR y OpenMPI $OPENMPI_VER en las otras PCs y arma $WORK_DIR/machinefile."
    echo "  $0 correr [nocoord|coord] [imagen] [np]"
    echo "      -> Corre el programa sobre las maquinas de $WORK_DIR/machinefile."
    echo ""
    echo "Ejemplo:"
    echo "  ./red_mpi.sh preparar"
    echo "  ./red_mpi.sh conectar usuario@10.1.112.129"
    echo "  ./red_mpi.sh correr nocoord imagenes/bloques_128.txt 4"
}

instalar_openmpi_portable() {
    if [ -x "$MPI_PREFIX/bin/mpicc" ] && [ -x "$MPI_PREFIX/bin/mpiexec" ]; then
        echo "OpenMPI portable ($OPENMPI_VER) ya instalado en $MPI_PREFIX."
        return
    fi

    local ARCH MAMBA_ARCH
    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64)  MAMBA_ARCH="linux-64" ;;
        aarch64) MAMBA_ARCH="linux-aarch64" ;;
        *)
            echo "ERROR: arquitectura no soportada para OpenMPI portable: $ARCH"
            exit 1
            ;;
    esac

    local TOOLS_DIR="/tmp/tp_mpi_tools"
    mkdir -p "$TOOLS_DIR"
    if [ ! -x "$TOOLS_DIR/bin/micromamba" ]; then
        echo "Descargando micromamba..."
        curl -Ls "https://micro.mamba.pm/api/micromamba/$MAMBA_ARCH/latest" | tar -xj -C "$TOOLS_DIR" bin/micromamba
    fi

    echo "Instalando OpenMPI $OPENMPI_VER identico en $MPI_PREFIX (no requiere sudo)..."
    "$TOOLS_DIR/bin/micromamba" create -y -q -p "$MPI_PREFIX" -c conda-forge "openmpi=$OPENMPI_VER"
}

preparar_local() {
    echo "==> [1/5] Verificando paquetes base..."
    local FALTA_PAQ=0
    for CMD in gcc make curl tar bzip2 sshd; do
        if ! command -v "$CMD" >/dev/null 2>&1; then
            FALTA_PAQ=1
        fi
    done
    if [ "$FALTA_PAQ" -eq 1 ]; then
        echo "Instalando build-essential, curl, bzip2 y openssh (puede pedir clave de sudo)..."
        sudo apt update
        sudo apt install -y build-essential curl bzip2 openssh-server openssh-client
    else
        echo "Paquetes OK."
    fi

    echo "==> [2/5] Activando servicio SSH..."
    if pgrep -x sshd >/dev/null 2>&1 || systemctl is-active --quiet ssh 2>/dev/null; then
        echo "Servicio SSH ya activo."
    elif command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files 2>/dev/null | grep -q '^ssh\.service'; then
        sudo systemctl enable --now ssh >/dev/null 2>&1 || sudo service ssh start
    else
        sudo service ssh start || true
    fi
    if command -v ufw >/dev/null 2>&1 && sudo -n ufw status 2>/dev/null | grep -q "Status: active"; then
        sudo ufw allow ssh >/dev/null || true
    fi

    echo "==> [3/5] Ajustando MTU si hay interfaz ZeroTier (evita cuelgues en SSH/MPI)..."
    for IFACE in $(ip -o link show | awk -F': ' '{print $2}' | grep '^zt' || true); do
        CUR_MTU=$(cat "/sys/class/net/$IFACE/mtu" 2>/dev/null || echo 1500)
        if [ "$CUR_MTU" -gt 1150 ]; then
            echo "Bajando MTU de $IFACE ($CUR_MTU -> 1150)..."
            sudo ip link set dev "$IFACE" mtu 1150
        else
            echo "MTU de $IFACE ya esta en $CUR_MTU."
        fi
    done

    echo "==> [4/5] Verificando OpenMPI $OPENMPI_VER comun en $MPI_PREFIX..."
    instalar_openmpi_portable

    echo "==> [5/5] Preparando y compilando en $WORK_DIR..."
    if [ "$SCRIPT_DIR" != "$WORK_DIR" ]; then
        mkdir -p "$WORK_DIR"
        cp -f "$SCRIPT_DIR"/Makefile "$SCRIPT_DIR"/*.c "$SCRIPT_DIR"/*.h \
              "$SCRIPT_DIR"/machinefile "$SCRIPT_DIR"/*.sh "$WORK_DIR"/ 2>/dev/null || true
        rm -rf "$WORK_DIR/imagenes"
        cp -r "$SCRIPT_DIR/imagenes" "$WORK_DIR/imagenes"
    fi

    OMPI_CC=gcc make -C "$WORK_DIR" clean >/dev/null
    OMPI_CC=gcc make -C "$WORK_DIR" CC="$MPI_PREFIX/bin/mpicc" all

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

        echo "Sincronizando $WORK_DIR, OpenMPI $OPENMPI_VER y compilando en $DEST..."
        ssh "$DEST" "mkdir -p $WORK_DIR"
        scp -q -r "$WORK_DIR"/Makefile "$WORK_DIR"/*.c "$WORK_DIR"/*.h \
                  "$WORK_DIR"/*.sh "$WORK_DIR"/imagenes "$DEST:$WORK_DIR/"
        ssh "$DEST" "chmod +x $WORK_DIR/red_mpi.sh && $WORK_DIR/red_mpi.sh _instalar_mpi && OMPI_CC=gcc make -C $WORK_DIR clean >/dev/null && OMPI_CC=gcc make -C $WORK_DIR CC=$MPI_PREFIX/bin/mpicc all"

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

    if [ ! -x "$MPI_PREFIX/bin/mpiexec" ]; then
        echo "Error: falta $MPI_PREFIX/bin/mpiexec. Corre primero '$0 preparar'."
        exit 1
    fi

    cd "$WORK_DIR"
    # shellcheck disable=SC2086
    echo "+ $MPI_PREFIX/bin/mpiexec --prefix $MPI_PREFIX --mca pml ob1 --mca btl tcp,sm,self $MCA_FLAGS --hostfile $WORK_DIR/machinefile -np $NP $*"
    # shellcheck disable=SC2086
    "$MPI_PREFIX/bin/mpiexec" --prefix "$MPI_PREFIX" --mca pml ob1 --mca btl tcp,sm,self $MCA_FLAGS --hostfile "$WORK_DIR/machinefile" -np "$NP" "$@"
}

correr_programa() {
    local MODO="${1:-nocoord}"
    local IMAGEN="${2:-imagenes/bloques_128.txt}"
    local NP="${3:-}"

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
    _instalar_mpi)
        instalar_openmpi_portable
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
