#!/bin/bash

# Función para imprimir y ejecutar un comando
run_command() {
    echo "Ejecutando: $1"
    eval "$1"
    echo " "
}

# Función para manejar conflictos durante el merge
merge_with_conflict_handling() {
    echo "Ejecutando: git merge development"
    git merge development

    # Verificar si hay conflictos
    if [[ $(git diff --name-only --diff-filter=U) ]]; then
        echo "¡Hay conflictos que resolver!"
        echo "Por favor, resuelve los conflictos manualmente y luego marca los archivos como resueltos con 'git add'."
        echo "Cuando hayas terminado, presiona Enter para continuar..."
        read  # Espera a que el usuario presione Enter
    fi
}

# Hacer push a la rama actual
run_command "git push"

# Cambiar a la rama master
run_command "git checkout master"

# Fusionar la rama development en master con manejo de conflictos
merge_with_conflict_handling

# Hacer push a master
run_command "git push"

# # Obtener la versión mayor actual usando git-semver y hacer push de la etiqueta
# run_command "git push origin \$(git semver major)"

# Cambiar de nuevo a la rama development
run_command "git checkout development"

# Hacer push de la rama development al remoto de GitHub
run_command "git push github development"

# Hacer push de la rama master al remoto de GitHub
run_command "git push github master"

echo "¡Proceso completado!"