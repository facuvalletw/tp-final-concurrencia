#ifndef MPI_COMUN_H
#define MPI_COMUN_H

#include <mpi.h>
#include "imagen_comun.h"

// intercambia filas borde (halos) con los vecinos de arriba y abajo sin deadlock
static inline void intercambiar_halos(int* grid, int filas_locales, int n,
                                      int vecino_arriba, int vecino_abajo) {
    MPI_Sendrecv(&grid[1 * n], n, MPI_INT, vecino_arriba, 0,
                 &grid[0 * n], n, MPI_INT, vecino_arriba, 0,
                 MPI_COMM_WORLD, MPI_STATUS_IGNORE);

    MPI_Sendrecv(&grid[filas_locales * n], n, MPI_INT, vecino_abajo, 0,
                 &grid[(filas_locales + 1) * n], n, MPI_INT, vecino_abajo, 0,
                 MPI_COMM_WORLD, MPI_STATUS_IGNORE);
}

// calcula una vuelta local guardando el resultado en temp (evita memcpy extra)
static inline int actualizar_etiquetas_locales(const int* grid, int* temp,
                                               int filas_locales, int n) {
    int cambio_local = 0;

    for (int i = 1; i <= filas_locales; i++) {
        for (int j = 0; j < n; j++) {
            int idx = i * n + j;
            int val = grid[idx];
            if (val == 0) {
                temp[idx] = 0;
                continue;
            }

            int max_val = val;
            if (grid[(i - 1) * n + j] > max_val) max_val = grid[(i - 1) * n + j];
            if (grid[(i + 1) * n + j] > max_val) max_val = grid[(i + 1) * n + j];
            if (j > 0 && grid[i * n + (j - 1)] > max_val) max_val = grid[i * n + (j - 1)];
            if (j < n - 1 && grid[i * n + (j + 1)] > max_val) max_val = grid[i * n + (j + 1)];

            temp[idx] = max_val;
            if (max_val > val) {
                cambio_local = 1;
            }
        }
    }

    return cambio_local;
}

#endif
