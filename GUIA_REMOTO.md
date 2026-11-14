# Ejecución distribuida de MPI entre equipos en redes distintas (VPN)

Cuando los equipos participantes están en redes domésticas separadas (distintos Wi-Fi o proveedores de internet), las IPs locales (`192.168.x.x`) no son alcanzables entre sí. Para conectarlos sin configurar port forwarding en el router, se puede armar una red virtual privada (VPN mesh) con **ZeroTier** o **Tailscale**.

> **Atajo con script (`red_mpi.sh`):** Una vez conectados a ZeroTier/Tailscale, en vez de hacer los pasos de SSH, MTU, `machinefile` y compilación a mano, pueden usar `./red_mpi.sh preparar` en todos los equipos y `./red_mpi.sh conectar usuario@IP` + `./red_mpi.sh correr` en el equipo que lanza la prueba. El script también instala una versión idéntica de OpenMPI (`5.0.11`) en `/tmp/tp_mpi` en cada equipo para evitar errores de `version mismatch` si usan distintas versiones de Ubuntu o Debian.

---

## Opción 1: ZeroTier

Permite que cada integrante use su propia cuenta gratuita y se una a una misma red mediante un ID.

1. **Crear la red (en un solo equipo):**
   * Ingresar a [my.zerotier.com](https://my.zerotier.com/), crear una cuenta y seleccionar **Create A Network**.
   * Copiar el **Network ID** (16 caracteres) para compartirlo con el grupo.

2. **Instalar y unirse (en cada equipo Linux / WSL2):**
   ```bash
   curl -s https://install.zerotier.com | sudo bash
   sudo zerotier-cli join TU_NETWORK_ID
   ```

3. **Autorizar los nodos:**
   * Quien creó la red entra al panel de ZeroTier, va a **Members** y habilita el casillero **Auth** de cada equipo conectado.
   * Con `ip -br a` cada integrante puede ver la IP virtual asignada (por ejemplo `10.147.20.x`) y el nombre de la interfaz (empieza con `zt`, por ejemplo `zt3j5abc12`).

---

## Opción 2: Tailscale

1. En cada equipo Linux:
   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   sudo tailscale up
   ```
2. Vincular los nodos a la misma red (misma cuenta o compartiendo máquinas desde el panel web).
3. Consultar la IP virtual con `tailscale ip -4` (rango `100.x.y.z`). La interfaz en Linux siempre se llama `tailscale0`.

---

## Ejecución de MPI sobre la VPN

Con todos los nodos conectados a ZeroTier o Tailscale:

1. **Verificar conectividad entre nodos:**
   ```bash
   ping -c 3 IP_VIRTUAL_OTRO_EQUIPO
   ```

2. **Preparar SSH y la ruta del proyecto (igual que en red local, ver [README.md](./README.md)):**
   * Tener el servicio SSH activo (`sudo systemctl enable --now ssh`) y el proyecto compilado en exactamente la misma ruta en todos los equipos (por ejemplo `/tmp/tp_final`).
   * Desde el equipo principal:
     ```bash
     ssh-copy-id usuario_otro_equipo@IP_VIRTUAL_OTRO_EQUIPO
     ssh usuario_otro_equipo@IP_VIRTUAL_OTRO_EQUIPO hostname
     ```

3. **Actualizar `machinefile` con las IPs de la VPN:**
   ```text
   lucas@10.147.20.10 slots=2
   juan@10.147.20.11 slots=2
   ```

4. **Lanzar `mpiexec` indicando la interfaz o subred de la VPN:**  
   Si no se especifica, OpenMPI intenta usar las IPs locales de cada casa (`192.168.x.x`) y la comunicación queda colgada.

   * **Con Tailscale** (mismo nombre de interfaz `tailscale0` en todos los nodos):
     ```bash
     mpiexec --mca btl_tcp_if_include tailscale0 --mca oob_tcp_if_include tailscale0 --hostfile machinefile -np 4 ./region_labeling_nocoord imagenes/bloques_128.txt
     ```
   * **Con ZeroTier** (usando el prefijo de subred de la VPN, visible con `ip -br a`):
     ```bash
     mpiexec --mca btl_tcp_if_include 10.147.20.0/24 --mca oob_tcp_if_include 10.147.20.0/24 --hostfile machinefile -np 4 ./region_labeling_nocoord imagenes/bloques_128.txt
     ```

---

## Consideración sobre tiempos y latencia

* A través de internet la latencia entre nodos es mucho mayor que en una LAN o Wi-Fi local.
* Sirve para validar la ejecución distribuida entre distintos equipos (conviene probar con `bloques_64.txt` o `bloques_128.txt`, que convergen en pocas iteraciones), pero las mediciones de speedup para el informe conviene tomarlas en red local o en un mismo equipo para evitar que el ping de internet afecte los resultados.
