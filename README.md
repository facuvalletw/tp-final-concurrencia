# TP Final - Etiquetado de Regiones con MPI

Trabajo Final de **Introducción a la Concurrencia** (UNPSJB - Facultad de Ingeniería, Sede Trelew).  
Tema 4: *Procesamiento de imágenes: Etiquetado de regiones* (Cap. 9 de Andrews, pp. 430–435).

---

## De qué se trata

Dada una matriz cuadrada de `N × N` con `0` (fondo) y `1` (píxel encendido), el programa busca todos los grupos de `1`s conectados (arriba, abajo, izquierda, derecha) y le asigna un número distinto a cada grupo.

Ejemplo con `imagenes/demo_8.txt` (8x8):

```text
Entrada (0 y 1):                 Salida (4 regiones):
0 0 0 0 0 0 0 0                    0   0   0   0   0   0   0   0
0 1 1 0 0 1 1 0                    0  19  19   0   0  23  23   0
0 1 1 0 0 0 1 0        ===>        0  19  19   0   0   0  23   0
0 0 0 0 0 0 0 0                    0   0   0   0   0   0   0   0
0 1 1 1 0 0 0 0                    0  52  52  52   0   0   0   0
0 0 0 1 0 1 1 0                    0   0   0  52   0  55  55   0
0 0 0 1 0 1 1 0                    0   0   0  52   0  55  55   0
0 0 0 0 0 0 0 0                    0   0   0   0   0   0   0   0
```

Hay 3 programas en C:
* `region_labeling_seq.c`: versión secuencial (1 proceso). Sirve para verificar la salida y como base para comparar tiempos.
* `region_labeling_coord.c`: versión paralela con MPI **con coordinador** (el proceso 0 recolecta el estado de cambios y decide cuándo finalizar).
* `region_labeling_nocoord.c`: versión paralela con MPI **sin coordinador** (todos los procesos se sincronizan directamente con `MPI_Allreduce`).

También se incluye `generador_imagenes.c` para armar matrices `.txt` de prueba y `benchmark.sh` para ejecutar varias pruebas seguidas.

---

## Instalación de dependencias (Linux y Windows)

El proyecto usa C y **OpenMPI** sobre Linux.

### En Linux (Ubuntu / Debian / Mint)
```bash
sudo apt update && sudo apt install -y build-essential openmpi-bin libopenmpi-dev openssh-server openssh-client
```
* `build-essential`: incluye `gcc` y `make`.
* `openmpi-bin` y `libopenmpi-dev`: incluyen `mpiexec`, `mpicc` y `mpi.h`.
* `openssh-server` y `openssh-client`: necesarios para lanzar procesos MPI por red entre varios equipos.

Para verificar que quedó instalado:
```bash
gcc --version
mpicc --version
mpiexec --version
```

### En Windows 10 / 11 (con WSL2)
En Windows nativo OpenMPI no es compatible directo con el `Makefile` del proyecto (Windows usa MS-MPI, con otras banderas y librerías). La alternativa más directa es usar **WSL2 (Ubuntu)** sin modificar el código:

1. Abrir **PowerShell como Administrador** y ejecutar:
   ```powershell
   wsl --install -d Ubuntu
   ```
   Si solicita reiniciar, reiniciar y completar la creación de usuario y contraseña en Ubuntu.
2. En la terminal de Ubuntu instalar los mismos paquetes que en Linux:
   ```bash
   sudo apt update && sudo apt install -y build-essential openmpi-bin libopenmpi-dev openssh-server openssh-client
   ```
3. Conviene clonar o ubicar el proyecto dentro de `/home/tu_usuario/` (en lugar de `/mnt/c/...`) para evitar problemas de permisos y rendimiento.
4. **Si un equipo con Windows participa en la ejecución distribuida en red:**
   * Opción recomendada: usar VirtualBox o VMware con Ubuntu configurando la red en modo **Adaptador Puente (Bridged)** para que obtenga una IP propia en la red local.
   * Alternativa en Windows 11 (22H2 o superior): crear `C:\Users\TU_USUARIO\.wslconfig` con:
     ```ini
     [wsl2]
     networkingMode=mirrored
     ```
     Luego ejecutar `wsl --shutdown` en PowerShell, abrir Ubuntu, iniciar SSH con `sudo service ssh start` y permitir el puerto 22 en el Firewall de Windows.

---

## Compilación

Dentro de la carpeta del proyecto:
```bash
make clean
make all
```
Conviene ejecutar `make clean` antes por si quedaron binarios compilados en otro sistema. Se generan: `generador_imagenes`, `region_labeling_seq`, `region_labeling_coord` y `region_labeling_nocoord`.

---

## Ejecución en un equipo (local)

### 1. Generar imágenes (opcional, ya hay ejemplos en `imagenes/`)
El formato de cada `.txt` es: en la primera línea el tamaño `N`, y debajo la matriz de `0`s y `1`s.

```bash
# ./generador_imagenes <patron> <N> <salida> [densidad]
# patron: 1=bloques, 2=tablero, 3=espiral, 4=ruido aleatorio
./generador_imagenes 1 64 imagenes/bloques_64.txt
./generador_imagenes 3 128 imagenes/espiral_128.txt
./generador_imagenes 4 256 imagenes/ruido_256.txt 0.35
```

### 2. Correr los programas
Banderas opcionales:
* `-v`: imprime la grilla final (solo si `N <= 32`).
* `-p`: imprime iteración por iteración (solo si `N <= 32`).

```bash
# Secuencial
./region_labeling_seq imagenes/demo_8.txt -v
./region_labeling_seq imagenes/demo_8.txt -p

# MPI con coordinador (4 procesos)
mpiexec --oversubscribe -np 4 ./region_labeling_coord imagenes/demo_8.txt -v

# MPI sin coordinador (4 procesos)
mpiexec --oversubscribe -np 4 ./region_labeling_nocoord imagenes/demo_8.txt -v
```
`--oversubscribe` permite lanzar más procesos que núcleos físicos en pruebas locales.

**Importante:** `N` tiene que ser divisible por `-np`. Por ejemplo, `demo_8.txt` (`N=8`) funciona con `-np 2`, `4` u `8`, pero falla con `-np 3`.

Para correr la batería de pruebas de tiempo completa:
```bash
./benchmark.sh
```

---

## Ejecución distribuida en múltiples equipos (red local)

Para correr comunicando procesos entre 2 o más máquinas por LAN o Wi-Fi:

> **Opción rápida con script:** pueden automatizar todo el setup (dependencias, SSH, ruta `/tmp/tp_final`, `machinefile` y corrida) ejecutando `./red_mpi.sh preparar` en cada equipo y `./red_mpi.sh conectar usuario@IP` seguido de `./red_mpi.sh correr` desde el equipo que lanza `mpiexec`. Debajo está el detalle manual paso a paso.

### 1. Preparar todos los equipos
1. Conectarlos a la misma red local (mismo Wi-Fi, cable de red o punto de acceso compartido).
2. Tener instalados los paquetes de OpenMPI + SSH y compilado el proyecto (`make clean && make all`).
3. Activar el servicio SSH:
   ```bash
   sudo systemctl enable --now ssh
   ```
   Si está activo el firewall (`ufw`), habilitar SSH con `sudo ufw allow ssh`.
4. Anotar usuario e IP de cada máquina:
   ```bash
   whoami
   hostname -I
   ```
5. **Ubicar el proyecto en exactamente la misma ruta en todas las máquinas.**  
   Si cada equipo tiene un nombre de usuario distinto, una opción práctica es copiar la carpeta a `/tmp/tp_final` en todos y compilar ahí:
   ```bash
   cp -r /ruta/al/proyecto /tmp/tp_final
   cd /tmp/tp_final && make clean && make all
   ```

### 2. Configurar SSH sin contraseña (desde el nodo principal)
En la máquina desde la que se va a lanzar `mpiexec`:
```bash
ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
ssh-copy-id usuario_otro_equipo@IP_OTRO_EQUIPO
```
Probar la conexión manualmente antes de usar MPI para aceptar el fingerprint y confirmar que no pide clave:
```bash
ssh usuario_otro_equipo@IP_OTRO_EQUIPO hostname
```

### 3. Editar `machinefile` y ejecutar
En `machinefile`, indicar los equipos y la cantidad de procesos (`slots`) de cada uno:
```text
lucas@192.168.1.101 slots=2
juan@192.168.1.102 slots=2
```
*(Si todos los equipos tienen el mismo usuario, alcanza con indicar la IP).*

Se puede verificar primero con `hostname` que los procesos se distribuyen entre los equipos:
```bash
mpiexec --hostfile machinefile -np 4 hostname
```

Luego ejecutar el etiquetado:
```bash
mpiexec --hostfile machinefile -np 4 ./region_labeling_nocoord imagenes/bloques_128.txt
mpiexec --hostfile machinefile -np 4 ./region_labeling_coord imagenes/bloques_128.txt
```

### Posibles errores en red
* **El comando queda colgado sin avanzar:** ocurre cuando algún equipo tiene interfaces virtuales de Docker, VirtualBox o una VPN y OpenMPI intenta comunicarse por ahí. Consultar el nombre de la interfaz Wi-Fi o Ethernet con `ip -br a` (ej. `wlp2s0` o `eth0`) y especificarla con `--mca`:
  ```bash
  mpiexec --mca btl_tcp_if_include wlp2s0 --mca oob_tcp_if_include wlp2s0 --hostfile machinefile -np 4 ./region_labeling_nocoord imagenes/bloques_128.txt
  ```
* **`No such file or directory`:** falta compilar en la máquina remota o la carpeta no está en exactamente la misma ruta en todos los nodos.
* **`Permission denied`:** falta `ssh-copy-id` o no coincide el usuario configurado en `machinefile`.
* **`Connection refused`:** en el equipo remoto no está activo el servicio `ssh`.
* **`There are not enough slots available`:** el valor de `-np` supera la suma de `slots` del `machinefile`.

---

## Documentación del TP
* [INFORME_TECNICO.md](./INFORME_TECNICO.md): explicación del problema, algoritmo y comparación de soluciones.
* [GUIA_REMOTO.md](./GUIA_REMOTO.md): ejecución distribuida entre equipos en redes distintas (ZeroTier / Tailscale).
