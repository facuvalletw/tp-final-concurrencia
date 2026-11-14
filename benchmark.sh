#!/bin/bash
# Script para correr las pruebas de tiempo (secuencial vs MPI)

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

mkdir -p imagenes
if [ ! -f "generador_imagenes" ]; then
    gcc -Wall -Wextra -O2 generador_imagenes.c -o generador_imagenes
fi

echo "Generando imagenes de prueba..."
./generador_imagenes 1 64 imagenes/bloques_64.txt
./generador_imagenes 2 64 imagenes/checker_64.txt
./generador_imagenes 3 64 imagenes/espiral_64.txt
./generador_imagenes 4 64 imagenes/ruido_64.txt 0.35

./generador_imagenes 1 128 imagenes/bloques_128.txt
./generador_imagenes 2 128 imagenes/checker_128.txt
./generador_imagenes 3 128 imagenes/espiral_128.txt
./generador_imagenes 4 128 imagenes/ruido_128.txt 0.35

./generador_imagenes 1 256 imagenes/bloques_256.txt
./generador_imagenes 2 256 imagenes/checker_256.txt
./generador_imagenes 4 256 imagenes/ruido_256.txt 0.35

echo "Compilando..."
if ! command -v mpicc &> /dev/null || ! echo '#include <mpi.h>' | mpicc -E - &>/dev/null; then
    echo "Falta OpenMPI (libopenmpi-dev). Corriendo solo la version secuencial:"
    gcc -Wall -Wextra -O2 region_labeling_seq.c -o region_labeling_seq
    ./region_labeling_seq imagenes/bloques_64.txt
    ./region_labeling_seq imagenes/espiral_64.txt
    ./region_labeling_seq imagenes/bloques_128.txt
    exit 0
fi

make all

IMAGENES=("imagenes/bloques_64.txt" "imagenes/checker_64.txt" "imagenes/espiral_64.txt" "imagenes/bloques_128.txt" "imagenes/bloques_256.txt")

for IMG in "${IMAGENES[@]}"; do
    echo "--------------------------------------------------"
    echo "Imagen: $IMG"
    ./region_labeling_seq "$IMG"

    for P in 2 4; do
        mpiexec --oversubscribe -np $P ./region_labeling_coord "$IMG"
        mpiexec --oversubscribe -np $P ./region_labeling_nocoord "$IMG"
    done
done

echo "--------------------------------------------------"
echo "Pruebas terminadas."
