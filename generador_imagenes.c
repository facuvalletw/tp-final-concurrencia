/*
 * TP Final - Introduccion a la Concurrencia (UNPSJB)
 * Generador de matrices binarias N x N (0s y 1s) para probar el etiquetado de regiones.
 *
 * Compilacion:
 *   gcc -Wall -Wextra -O2 generador_imagenes.c -o generador_imagenes
 *
 * Uso:
 *   ./generador_imagenes <patron> <N> <archivo_salida> [densidad]
 *   patrones: 1=bloques, 2=tablero, 3=espiral, 4=ruido aleatorio
 */

#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <string.h>

void generar_bloques_aislados(int* mat, int n) {
    memset(mat, 0, n * n * sizeof(int));
    int bloque_tam = n / 8;
    if (bloque_tam < 2) bloque_tam = 2;

    for (int bi = 1; bi < 8; bi += 2) {
        for (int bj = 1; bj < 8; bj += 2) {
            int start_r = bi * (n / 8);
            int start_c = bj * (n / 8);
            for (int r = start_r; r < start_r + bloque_tam && r < n; r++) {
                for (int c = start_c; c < start_c + bloque_tam && c < n; c++) {
                    mat[r * n + c] = 1;
                }
            }
        }
    }
}

void generar_checkerboard(int* mat, int n) {
    int paso = n / 16;
    if (paso < 1) paso = 1;

    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            int block_i = i / paso;
            int block_j = j / paso;
            mat[i * n + j] = ((block_i + block_j) % 2 == 0) ? 1 : 0;
        }
    }
}

void generar_espiral(int* mat, int n) {
    memset(mat, 0, n * n * sizeof(int));
    int paso = 4;
    for (int capa = 2; capa < n / 2; capa += paso) {
        for (int j = capa; j < n - capa; j++) mat[capa * n + j] = 1;
        for (int i = capa; i < n - capa; i++) mat[i * n + (n - 1 - capa)] = 1;
        for (int j = capa; j < n - capa; j++) mat[(n - 1 - capa) * n + j] = 1;
        for (int i = capa + paso; i < n - capa; i++) mat[i * n + capa] = 1;
    }
}

void generar_ruido(int* mat, int n, double densidad) {
    srand(12345); // semilla fija para poder comparar los distintos programas sobre la misma imagen
    for (int i = 0; i < n * n; i++) {
        double r = (double)rand() / (double)RAND_MAX;
        mat[i] = (r < densidad) ? 1 : 0;
    }
}

int main(int argc, char* argv[]) {
    if (argc < 4) {
        printf("Uso: %s <patron: 1=bloques, 2=checkerboard, 3=espiral, 4=ruido> <N> <archivo_salida> [densidad_si_ruido]\n", argv[0]);
        return 1;
    }

    int patron = atoi(argv[1]);
    int n = atoi(argv[2]);
    char* archivo = argv[3];
    double densidad = (argc >= 5) ? atof(argv[4]) : 0.35;

    if (n <= 0) {
        fprintf(stderr, "Error: N debe ser mayor a 0.\n");
        return 1;
    }

    int* mat = (int*)malloc(n * n * sizeof(int));
    if (!mat) {
        perror("Error asignando memoria para la imagen");
        return 1;
    }

    switch (patron) {
        case 1:
            generar_bloques_aislados(mat, n);
            break;
        case 2:
            generar_checkerboard(mat, n);
            break;
        case 3:
            generar_espiral(mat, n);
            break;
        case 4:
            generar_ruido(mat, n, densidad);
            break;
        default:
            generar_ruido(mat, n, densidad);
            break;
    }

    FILE* f = fopen(archivo, "w");
    if (!f) {
        perror("Error abriendo archivo de salida");
        free(mat);
        return 1;
    }

    // Escribimos N en la primera linea
    fprintf(f, "%d\n", n);
    // Luego los valores de la matriz
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            fprintf(f, "%d ", mat[i * n + j]);
        }
        fprintf(f, "\n");
    }

    fclose(f);
    free(mat);

    printf("Imagen de %dx%d (patron %d) guardada exitosamente en '%s'.\n", n, n, patron, archivo);
    return 0;
}
