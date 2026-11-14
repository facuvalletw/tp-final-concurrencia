/*
 * TP Final - Introduccion a la Concurrencia (UNPSJB)
 * Tema 4: Procesamiento de imagenes - Etiquetado de regiones (MPI con coordinador)
 *
 * Comentarios:
 * Version paralela en MPI usando un proceso coordinador (rank 0), segun Andrews (pp. 432-434).
 * - La grilla N x N se reparte por franjas horizontales entre los P procesos (N / P filas c/u).
 * - Cada proceso reserva (filas_locales + 2) * N enteros para tener dos filas extra (halos):
 *   la fila 0 guarda la fila borde del vecino de arriba y la fila (filas_locales + 1) la del de abajo.
 * - En cada iteracion se intercambian halos con MPI_Sendrecv para evitar deadlocks.
 * - Despues cada proceso actualiza sus celdas y manda si tuvo cambios (0 o 1) al rank 0
 *   con MPI_Reduce. El coordinador suma los cambios y avisa por MPI_Bcast si siguen o terminan.
 * - Al finalizar, rank 0 junta todas las franjas con MPI_Gather.
 */

#include <stdio.h>
#include <stdlib.h>
#include <mpi.h>

#include "mpi_comun.h"

int main(int argc, char* argv[]) {
    int rank, size;
    int n = 0;
    int* imagen_completa = NULL;
    int* labels_completas = NULL;

    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    if (argc < 2) {
        if (rank == 0) {
            printf("Uso: mpiexec -np <procesos> %s <archivo_imagen.txt> [-p] [-v]\n", argv[0]);
        }
        MPI_Finalize();
        return 1;
    }

    int paso_a_paso = 0;
    int verbose = 0;
    parsear_flags(argc, argv, &paso_a_paso, &verbose);

    // rank 0 lee la imagen e inicializa las etiquetas
    if (rank == 0) {
        imagen_completa = leer_imagen(argv[1], &n);
        if (!imagen_completa) {
            MPI_Abort(MPI_COMM_WORLD, 1);
        }
        if (n % size != 0) {
            printf("Error: Dimension N (%d) no es divisible por la cantidad de procesos (%d).\n", n, size);
            free(imagen_completa);
            MPI_Abort(MPI_COMM_WORLD, 1);
        }

        labels_completas = (int*)malloc((size_t)n * n * sizeof(int));
        if (!labels_completas) {
            perror("Error reservando memoria en coordinador");
            free(imagen_completa);
            MPI_Abort(MPI_COMM_WORLD, 1);
        }
        inicializar_etiquetas(imagen_completa, labels_completas, n);
    }

    MPI_Bcast(&n, 1, MPI_INT, 0, MPI_COMM_WORLD);

    int filas_locales = n / size;
    int filas_con_halo = filas_locales + 2;
    int celdas_locales = filas_locales * n;
    int* local_grid = (int*)calloc((size_t)filas_con_halo * n, sizeof(int));
    int* temp_grid = (int*)calloc((size_t)filas_con_halo * n, sizeof(int));
    if (!local_grid || !temp_grid) {
        perror("Error reservando memoria local");
        free(local_grid);
        free(temp_grid);
        MPI_Abort(MPI_COMM_WORLD, 1);
    }

    // el coordinador reparte las franjas a partir de la fila 1 (la 0 es el halo superior)
    MPI_Scatter(labels_completas, celdas_locales, MPI_INT,
                &local_grid[1 * n], celdas_locales, MPI_INT,
                0, MPI_COMM_WORLD);

    int vecino_superior = (rank > 0) ? rank - 1 : MPI_PROC_NULL;
    int vecino_inferior = (rank < size - 1) ? rank + 1 : MPI_PROC_NULL;

    MPI_Barrier(MPI_COMM_WORLD);
    double t_inicio = MPI_Wtime();

    int iteraciones = 0;
    int continuar = 1;

    while (continuar) {
        iteraciones++;

        intercambiar_halos(local_grid, filas_locales, n, vecino_superior, vecino_inferior);

        int cambio_local = actualizar_etiquetas_locales(local_grid, temp_grid, filas_locales, n);

        // intercambiamos buffers para no hacer memcpy en cada vuelta
        int* aux = local_grid;
        local_grid = temp_grid;
        temp_grid = aux;

        // el coordinador junta los avisos de cambio y decide si sigue el bucle
        int cambio_global = 0;
        MPI_Reduce(&cambio_local, &cambio_global, 1, MPI_INT, MPI_SUM, 0, MPI_COMM_WORLD);

        if (rank == 0) {
            continuar = (cambio_global > 0);
        }
        MPI_Bcast(&continuar, 1, MPI_INT, 0, MPI_COMM_WORLD);

        if (paso_a_paso && n <= 32) {
            MPI_Gather(&local_grid[1 * n], celdas_locales, MPI_INT,
                       labels_completas, celdas_locales, MPI_INT,
                       0, MPI_COMM_WORLD);
            if (rank == 0) {
                printf("Iteracion %d:\n", iteraciones);
                imprimir_grilla(labels_completas, n);
            }
        }
    }

    // juntamos la matriz final en el proceso 0
    MPI_Gather(&local_grid[1 * n], celdas_locales, MPI_INT,
               labels_completas, celdas_locales, MPI_INT,
               0, MPI_COMM_WORLD);

    MPI_Barrier(MPI_COMM_WORLD);
    double t_fin = MPI_Wtime();
    double tiempo_total = t_fin - t_inicio;

    if (rank == 0) {
        int regiones = contar_regiones(labels_completas, n);

        if (verbose && n <= 32 && !paso_a_paso) {
            printf("Grilla final:\n");
            imprimir_grilla(labels_completas, n);
        }

        printf("Dimension de grilla: %d x %d | Procesos: %d\n", n, n, size);
        printf("Iteraciones hasta converger: %d\n", iteraciones);
        printf("Regiones conexas encontradas: %d\n", regiones);
        printf("Tiempo de ejecucion MPI: %.6f seg\n", tiempo_total);

        free(imagen_completa);
        free(labels_completas);
    }

    free(local_grid);
    free(temp_grid);

    MPI_Finalize();
    return 0;
}
