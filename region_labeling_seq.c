/*
 * TP Final - Introduccion a la Concurrencia (UNPSJB)
 * Tema 4: Procesamiento de imagenes - Etiquetado de regiones (version secuencial)
 *
 * Comentarios:
 * Basado en el algoritmo de latido (heartbeat) del cap. 9 de Andrews (pp. 430-435).
 * - Se lee una matriz cuadrada N x N de 0s (apagado) y 1s (encendido) desde un archivo.
 * - Al inicio, cada celda en 1 recibe una etiqueta unica: i * n + j + 1 (las de 0 quedan en 0).
 * - En cada iteracion, cada celda encendida mira sus 4 vecinos (arriba, abajo, izq, der)
 *   y se queda con la etiqueta mas grande.
 * - Cuando pasa una vuelta entera sin que cambie ninguna celda, el algoritmo termina.
 * - Esta version secuencial sirve para verificar que las versiones MPI den el mismo resultado
 *   y para tomar el tiempo base (T_seq) al calcular speedup.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "imagen_comun.h"

static int actualizar_secuencial(const int* cur, int* next, int n) {
    int hubo_cambio = 0;

    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            int idx = i * n + j;
            int val = cur[idx];
            if (val == 0) {
                next[idx] = 0;
                continue;
            }

            int max_label = val;
            if (i > 0 && cur[(i - 1) * n + j] > max_label) max_label = cur[(i - 1) * n + j];
            if (i < n - 1 && cur[(i + 1) * n + j] > max_label) max_label = cur[(i + 1) * n + j];
            if (j > 0 && cur[i * n + (j - 1)] > max_label) max_label = cur[i * n + (j - 1)];
            if (j < n - 1 && cur[i * n + (j + 1)] > max_label) max_label = cur[i * n + (j + 1)];

            next[idx] = max_label;
            if (max_label > val) {
                hubo_cambio = 1;
            }
        }
    }

    return hubo_cambio;
}

// propaga etiquetas alternando punteros hasta que no haya cambios
static int etiquetar_regiones_secuencial(int* labels, int n, int paso_a_paso, int* iteraciones_out) {
    int* temp = (int*)malloc((size_t)n * n * sizeof(int));
    if (!temp) {
        perror("Error reservando memoria temporal");
        return -1;
    }

    int* cur = labels;
    int* next = temp;
    int iteraciones = 0;
    int hubo_cambio = 1;

    if (paso_a_paso && n <= 32) {
        printf("Grilla inicial:\n");
        imprimir_grilla(cur, n);
    }

    while (hubo_cambio) {
        iteraciones++;
        hubo_cambio = actualizar_secuencial(cur, next, n);

        int* aux = cur;
        cur = next;
        next = aux;

        if (paso_a_paso && n <= 32) {
            printf("Iteracion %d:\n", iteraciones);
            imprimir_grilla(cur, n);
        }
    }

    if (cur != labels) {
        memcpy(labels, cur, (size_t)n * n * sizeof(int));
    }

    free(temp);
    *iteraciones_out = iteraciones;
    return 0;
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        printf("Uso: %s <archivo_imagen.txt> [-p] [-v]\n", argv[0]);
        return 1;
    }

    int paso_a_paso = 0;
    int verbose = 0;
    parsear_flags(argc, argv, &paso_a_paso, &verbose);

    int n = 0;
    int* imagen = leer_imagen(argv[1], &n);
    if (!imagen) return 1;

    int* labels = (int*)malloc((size_t)n * n * sizeof(int));
    if (!labels) {
        perror("Error reservando memoria para etiquetas");
        free(imagen);
        return 1;
    }

    inicializar_etiquetas(imagen, labels, n);

    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);

    int iteraciones = 0;
    if (etiquetar_regiones_secuencial(labels, n, paso_a_paso, &iteraciones) != 0) {
        free(imagen);
        free(labels);
        return 1;
    }

    clock_gettime(CLOCK_MONOTONIC, &end);
    double tiempo = (end.tv_sec - start.tv_sec) + (end.tv_nsec - start.tv_nsec) / 1e9;

    int regiones = contar_regiones(labels, n);

    if (verbose && n <= 32 && !paso_a_paso) {
        printf("Grilla final:\n");
        imprimir_grilla(labels, n);
    }

    printf("Dimension de grilla: %d x %d\n", n, n);
    printf("Iteraciones hasta converger: %d\n", iteraciones);
    printf("Regiones conexas encontradas: %d\n", regiones);
    printf("Tiempo de ejecucion: %.6f seg\n", tiempo);

    free(imagen);
    free(labels);
    return 0;
}
