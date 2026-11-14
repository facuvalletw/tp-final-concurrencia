/*
 * TP Final - Introduccion a la Concurrencia (UNPSJB)
 * Tema 4: Procesamiento de imagenes - Etiquetado de regiones (MPI sin coordinador)
 *
 * Comentarios:
 * Version paralela descentralizada en MPI (sin proceso coordinador), segun Andrews (pp. 434-435).
 * - La grilla N x N se divide en franjas horizontales de N / P filas por proceso, con dos filas
 *   halo (arriba y abajo) intercambiadas mediante MPI_Sendrecv en cada iteracion.
 * - A diferencia de la version con coordinador, aca nadie centraliza la decision de corte:
 *   todos los procesos llaman a MPI_Allreduce(..., MPI_LOR, ...) para saber al mismo tiempo
 *   si alguno tuvo cambios en esa vuelta.
 * - Solo al principio y al final se usa rank 0 para leer el archivo y mostrar el resumen/tiempo.
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
            perror("Error reservando memoria");
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

    MPI_Scatter(labels_completas, celdas_locales, MPI_INT,
                &local_grid[1 * n], celdas_locales, MPI_INT,
                0, MPI_COMM_WORLD);

    int vecino_superior = (rank > 0) ? rank - 1 : MPI_PROC_NULL;
    int vecino_inferior = (rank < size - 1) ? rank + 1 : MPI_PROC_NULL;

    MPI_Barrier(MPI_COMM_WORLD);
    double t_inicio = MPI_Wtime();

    int iteraciones = 0;
    int cambio_global = 1;

    // bucle sin coordinador: todos saben si hay que seguir mediante MPI_Allreduce
    while (cambio_global) {
        iteraciones++;

        intercambiar_halos(local_grid, filas_locales, n, vecino_superior, vecino_inferior);

        int cambio_local = actualizar_etiquetas_locales(local_grid, temp_grid, filas_locales, n);

        // intercambiamos buffers para no hacer memcpy en cada vuelta
        int* aux = local_grid;
        local_grid = temp_grid;
        temp_grid = aux;

        // OR logico entre todos los procesos para ver si alguien tuvo cambios
        MPI_Allreduce(&cambio_local, &cambio_global, 1, MPI_INT, MPI_LOR, MPI_COMM_WORLD);

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
