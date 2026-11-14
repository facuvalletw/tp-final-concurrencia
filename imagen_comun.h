#ifndef IMAGEN_COMUN_H
#define IMAGEN_COMUN_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static inline void parsear_flags(int argc, char* argv[], int* paso_a_paso, int* verbose) {
    *paso_a_paso = 0;
    *verbose = 0;
    for (int a = 2; a < argc; a++) {
        if (strcmp(argv[a], "-p") == 0) *paso_a_paso = 1;
        if (strcmp(argv[a], "-v") == 0) *verbose = 1;
    }
}

// lee la dimension N (> 0) y los valores 0/1 de la matriz desde un archivo
static inline int* leer_imagen(const char* ruta, int* n_out) {
    FILE* f = fopen(ruta, "r");
    if (!f) {
        perror("Error al abrir archivo de imagen");
        return NULL;
    }

    int n = 0;
    if (fscanf(f, "%d", &n) != 1 || n <= 0) {
        fprintf(stderr, "Error: dimension N invalida en '%s'.\n", ruta);
        fclose(f);
        return NULL;
    }

    int* mat = (int*)malloc((size_t)n * n * sizeof(int));
    if (!mat) {
        perror("Error de memoria al leer imagen");
        fclose(f);
        return NULL;
    }

    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            if (fscanf(f, "%d", &mat[i * n + j]) != 1) {
                fprintf(stderr, "Error leyendo celda (%d, %d)\n", i, j);
                free(mat);
                fclose(f);
                return NULL;
            }
        }
    }

    fclose(f);
    *n_out = n;
    return mat;
}

// asigna una etiqueta inicial unica (i * n + j + 1) a cada 1 y 0 al fondo
static inline void inicializar_etiquetas(const int* imagen, int* labels, int n) {
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            labels[i * n + j] = (imagen[i * n + j] == 1) ? (i * n + j + 1) : 0;
        }
    }
}

static inline void imprimir_grilla(const int* mat, int n) {
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            printf("%3d ", mat[i * n + j]);
        }
        printf("\n");
    }
    printf("\n");
}

static inline int contar_regiones(const int* labels, int n) {
    char* presente = (char*)calloc((size_t)n * n + 1, sizeof(char));
    if (!presente) return -1;

    int total = 0;
    for (int i = 0; i < n * n; i++) {
        int l = labels[i];
        if (l > 0 && !presente[l]) {
            presente[l] = 1;
            total++;
        }
    }
    free(presente);
    return total;
}

#endif
