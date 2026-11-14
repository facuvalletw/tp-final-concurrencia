# Trabajo Final: Etiquetado de Regiones con MPI

**Materia:** Introducción a la Concurrencia (UNPSJB - Sede Trelew)  
**Docentes:** Lic. Marcelo Eleazar Gómez, Lic. Gastón Mura  
**Bibliografía:** Gregory R. Andrews, *Foundations of Multithreaded, Parallel and Distributed Programming*, Cap. 9 ("Heartbeat Algorithms: Image Processing: Region Labeling"), pp. 430–435.

---

## 1. El problema: Etiquetado de Regiones

El etiquetado de regiones (*Region Labeling* o *Connected Component Labeling*) consiste en identificar las componentes conexas de una imagen binaria.

La imagen se representa con una matriz cuadrada de enteros de tamaño `N × N`:
* `0`: píxel apagado (fondo).
* `1`: píxel encendido (parte de una región/objeto).

Usamos **4-conectividad** (Andrews, pág. 430): dos píxeles en `1` están conectados si son vecinos ortogonales (arriba, abajo, izquierda o derecha). Para una celda `(i, j)`, sus vecinos son:

```text
V₄(i, j) = { (i - 1, j), (i + 1, j), (i, j - 1), (i, j + 1) }
```

Al terminar el algoritmo, todos los píxeles de una misma componente conexa tienen que quedar con el mismo número entero de etiqueta, y regiones separadas deben quedar con etiquetas distintas.

---

## 2. Algoritmo de Latido (Heartbeat)

Para resolverlo sin memoria compartida se usa el algoritmo iterativo de propagación de etiquetas visto en el Cap. 9 de Andrews:

1. **Inicialización:**  
   Cada celda apagada (`0`) queda en `0`, y cada celda encendida (`1`) recibe una etiqueta inicial única calculada con su posición lineal:
   ```text
   label[i][j] = i · N + j + 1    si imagen[i][j] = 1
   label[i][j] = 0                si imagen[i][j] = 0
   ```
2. **Paso iterativo (latido):**  
   En cada vuelta `k`, cada celda distinta de `0` compara su etiqueta con las de sus 4 vecinos y se queda con la mayor:
   ```text
   label^(k+1)[i][j] = max( label^(k)[i][j], max_{(u, v) ∈ V₄(i, j)} label^(k)[u][v] )
   ```
3. **Condición de parada:**  
   Se repite hasta que en una vuelta completa no cambie ninguna celda de toda la matriz. En ese punto, la etiqueta más grande de cada isla ya se propagó a todos sus píxeles.

---

## 3. Cómo se paralelizó con MPI

Para distribuir el trabajo entre `P` procesos en MPI, la matriz `N × N` se parte en **franjas horizontales** de `B = N / P` filas por proceso.

```text
       Matriz Global (N x N)                Buffer local de cada proceso
 +-------------------------------+
 | Proceso 0 (Filas 0 a B-1)     |  ---> [ Fila 0: Halo superior (vecino rank-1) ]
 +-------------------------------+       [ Filas 1..B: Datos propios del proceso ]
 | Proceso 1 (Filas B a 2B-1)    |       [ Fila B+1: Halo inferior (vecino rank+1)]
 +-------------------------------+
 |              ...              |
 +-------------------------------+
 | Proceso P-1 (Filas N-B a N-1) |
 +-------------------------------+
```

### Filas fantasma (Halos) e intercambio con `MPI_Sendrecv`
Para actualizar su primera y última fila propia, cada proceso necesita leer la fila vecina que está en otro proceso. Por eso reserva `(B + 2) × N` enteros: las filas `1` a `B` son su franja real, la fila `0` guarda el borde del proceso `rank - 1` y la fila `B + 1` el borde de `rank + 1`.

En cada iteración se intercambian esas filas borde usando `MPI_Sendrecv`:

```c
MPI_Sendrecv(&local_grid[1 * n], n, MPI_INT, vecino_superior, 0,
             &local_grid[0 * n], n, MPI_INT, vecino_superior, 0,
             MPI_COMM_WORLD, MPI_STATUS_IGNORE);

MPI_Sendrecv(&local_grid[filas_locales * n], n, MPI_INT, vecino_inferior, 0,
             &local_grid[(filas_locales + 1) * n], n, MPI_INT, vecino_inferior, 0,
             MPI_COMM_WORLD, MPI_STATUS_IGNORE);
```

Usar `MPI_Sendrecv` evita interbloqueos (*deadlocks*) si dos vecinos envían al mismo tiempo. En los bordes de la imagen (`rank == 0` arriba y `rank == size - 1` abajo) se pasa `MPI_PROC_NULL`, que no envía ni recibe nada.

---

## 4. Las dos soluciones MPI

La consigna pide implementar una versión con proceso coordinador y otra sin coordinador.

### 4.1. Con proceso coordinador (`region_labeling_coord.c`)
Sigue el esquema maestro/trabajador (Andrews, pp. 432–434):
* Al principio el proceso `0` lee la imagen, inicializa etiquetas y reparte las franjas con `MPI_Scatter`.
* En cada iteración, después de intercambiar halos y actualizar sus celdas, cada proceso guarda `cambio_local` (`1` si modificó alguna celda, `0` si no).
* Todos mandan su bandera al `rank 0` con `MPI_Reduce(..., MPI_SUM, 0, ...)`.
* El proceso `0` evalúa si `cambio_global > 0` y avisa a todos con `MPI_Bcast` si hay que seguir o cortar.
* Al terminar, `rank 0` junta las franjas finales con `MPI_Gather`.

Es simple de seguir, pero hace **dos comunicaciones colectivas por iteración** (`Reduce` + `Bcast`) pasando siempre por el proceso `0`.

### 4.2. Sin proceso coordinador (`region_labeling_nocoord.c`)
Sigue el esquema descentralizado (Andrews, pp. 434–435):
* Ningún proceso decide por los demás durante el bucle.
* Después de actualizar su franja, todos los procesos ejecutan juntos:
  ```c
  MPI_Allreduce(&cambio_local, &cambio_global, 1, MPI_INT, MPI_LOR, MPI_COMM_WORLD);
  ```
* Con ese único llamado (OR lógico distribuido), todos los procesos quedan enterados al mismo tiempo de si alguno tuvo cambios, con menor latencia que hacer `MPI_Reduce` seguido de `MPI_Bcast` (complejidad `O(log P)`).

*(Nota: al inicio y al final se sigue usando `rank 0` solo para leer el archivo `.txt` de disco y mostrar los resultados por consola).*

---

## 5. Medición de rendimiento y pruebas

Para comparar las soluciones se usan:
* `T_seq`: tiempo de ejecución de la versión secuencial (`region_labeling_seq`).
* `T_p`: tiempo de pared medido con `MPI_Wtime()` usando `P` procesos.
* **Speedup:** `S_p = T_seq / T_p`
* **Eficiencia:** `E_p = S_p / P = T_seq / (P · T_p)`

### Cómputo vs. comunicación
Cada proceso calcula sobre `O(N² / P)` celdas por vuelta, pero solo manda `O(N)` enteros en los bordes. Por eso:
* En imágenes chicas (`N = 64`), el tiempo de mandar mensajes pesa bastante respecto al cálculo.
* En imágenes más grandes (`N ≥ 256`), la proporción cómputo/comunicación (`N / P`) mejora y se aprovecha mucho mejor el paralelismo.
* También influye el patrón de la imagen (creadas con `generador_imagenes.c`): en bloques aislados converge en pocas vueltas, mientras que en una espiral larga la etiqueta tiene que recorrer toda la forma y requiere muchas iteraciones, donde se nota más la ventaja de usar `MPI_Allreduce` (sin coordinador).

Para ver los comandos de compilación, ejecución local y ejecución en red con `machinefile`, ver [README.md](./README.md).
