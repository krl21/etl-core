#!/bin/bash

# =============================================================================
# Script para ejecutar los tests de pool de conexiones
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Pool Connection Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Verificar variables de entorno para PostgreSQL
check_pg_env_vars() {
    local missing=()
    
    [[ -z "$PG_HOST" ]] && missing+=("PG_HOST")
    [[ -z "$PG_DATABASE" ]] && missing+=("PG_DATABASE")
    [[ -z "$PG_USERNAME" ]] && missing+=("PG_USERNAME")
    [[ -z "$PG_PASSWORD" ]] && missing+=("PG_PASSWORD")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo ""
        echo "⚠️  Variables de entorno PostgreSQL faltantes:"
        for var in "${missing[@]}"; do
            echo "   • $var"
        done
        echo ""
        echo "Por favor configura las variables antes de ejecutar:"
        echo "   export PG_HOST=localhost"
        echo "   export PG_PORT=5432"
        echo "   export PG_DATABASE=tu_database"
        echo "   export PG_USERNAME=tu_usuario"
        echo "   export PG_PASSWORD=tu_password"
        echo ""
        return 1
    fi
    
    echo "✅ Variables PostgreSQL configuradas"
    echo "   • PG_HOST: $PG_HOST"
    echo "   • PG_PORT: ${PG_PORT:-5432}"
    echo "   • PG_DATABASE: $PG_DATABASE"
    echo "   • PG_USERNAME: $PG_USERNAME"
    return 0
}

# Verificar variables de entorno para BigQuery
check_bq_env_vars() {
    local missing=()
    
    [[ -z "$DNS" && -z "$DSN" ]] && missing+=("DNS o DSN")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo ""
        echo "⚠️  Variables de entorno BigQuery faltantes:"
        for var in "${missing[@]}"; do
            echo "   • $var"
        done
        echo ""
        echo "Por favor configura las variables antes de ejecutar:"
        echo "   export DNS=tu_dsn_odbc"
        echo "   export DATAMART_NEW_VEHICLES=tu_warehouse"
        echo ""
        return 1
    fi
    
    echo "✅ Variables BigQuery configuradas"
    echo "   • DNS/DSN: ${DNS:-$DSN}"
    echo "   • DATAMART: ${DATAMART_NEW_VEHICLES:-no configurado}"
    return 0
}

# Verificar variables según el tipo de test
check_env_vars() {
    local test_type="$1"
    
    case "$test_type" in
        pg|postgres|ALL)
            check_pg_env_vars || exit 1
            ;;
        bq|bigquery)
            check_bq_env_vars || exit 1
            ;;
        *)
            # Para tests individuales, detectar por nombre
            if [[ "$test_type" == *"bigquery"* ]]; then
                check_bq_env_vars || exit 1
            else
                check_pg_env_vars || exit 1
            fi
            ;;
    esac
}

# Menú de selección de test
select_test() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════"
    echo "Tests disponibles:"
    echo "═══════════════════════════════════════════════════════════════════════"
    echo ""
    echo "  📦 PostgreSQL:"
    echo "  1) pool_exhaustion      - Saturar pool PG y verificar espera"
    echo "  2) pool_recovery        - Cerrar conexión PG y verificar recuperación"
    echo ""
    echo "  📦 BigQuery:"
    echo "  3) pool_exhaustion  - Saturar pool BQ y verificar espera"
    echo "  4) pool_recovery    - Cerrar worker BQ y verificar recuperación"
    echo ""
    echo "  📦 Grupos:"
    echo "  p) Ejecutar todos los tests PostgreSQL"
    echo "  b) Ejecutar todos los tests BigQuery"
    echo "  a) Ejecutar TODOS los tests"
    echo ""
    echo "  q) Salir"
    echo ""
    read -p "Selecciona un test [1]: " choice
    
    case "${choice:-1}" in
        1)
            TEST_FILE="test/pool/pool_postgres_exhaustion_test.exs"
            TEST_TYPE="pg"
            ;;
        2)
            TEST_FILE="test/pool/pool_postgres_recovery_test.exs"
            TEST_TYPE="pg"
            ;;
        3)
            TEST_FILE="test/pool/pool_bigquery_exhaustion_test.exs"
            TEST_TYPE="bq"
            ;;
        4)
            TEST_FILE="test/pool/pool_bigquery_recovery_test.exs"
            TEST_TYPE="bq"
            ;;
        p|P)
            TEST_FILE="PG_ALL"
            TEST_TYPE="pg"
            ;;
        b|B)
            TEST_FILE="BQ_ALL"
            TEST_TYPE="bq"
            ;;
        a|A)
            TEST_FILE="ALL"
            TEST_TYPE="ALL"
            ;;
        q|Q)
            echo "Saliendo..."
            exit 0
            ;;
        *)
            echo "Opción no válida"
            exit 1
            ;;
    esac
}

# Ejecutar un test individual
run_single_test() {
    local test_file="$1"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🚀 Ejecutando: $test_file"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    mix run "$test_file"
}

# Ejecutar test seleccionado
run_test() {
    case "$TEST_FILE" in
        ALL)
            echo ""
            echo "🔄 Ejecutando TODOS los tests..."
            check_pg_env_vars || exit 1
            check_bq_env_vars || exit 1
            
            for test in test/pool/*.exs; do
                run_single_test "$test"
                echo ""
                echo "⏳ Esperando 2 segundos antes del siguiente test..."
                sleep 2
            done
            
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "✅ Todos los tests completados"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            ;;
        PG_ALL)
            echo ""
            echo "🔄 Ejecutando tests PostgreSQL..."
            
            for test in test/pool/pool_postgres_exhaustion_test.exs test/pool/pool_postgres_recovery_test.exs; do
                if [[ -f "$test" ]]; then
                    run_single_test "$test"
                    echo ""
                    echo "⏳ Esperando 2 segundos antes del siguiente test..."
                    sleep 2
                fi
            done
            
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "✅ Tests PostgreSQL completados"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            ;;
        BQ_ALL)
            echo ""
            echo "🔄 Ejecutando tests BigQuery..."
            
            for test in test/pool/pool_bigquery_exhaustion_test.exs test/pool/pool_bigquery_recovery_test.exs; do
                if [[ -f "$test" ]]; then
                    run_single_test "$test"
                    echo ""
                    echo "⏳ Esperando 2 segundos antes del siguiente test..."
                    sleep 2
                fi
            done
            
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "✅ Tests BigQuery completados"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            ;;
        *)
            run_single_test "$TEST_FILE"
            ;;
    esac
}

# Main
main() {
    if [[ -n "$1" ]]; then
        # Si se pasa un argumento, ejecutar ese test directamente
        TEST_FILE="test/pool/$1"
        if [[ ! -f "$TEST_FILE" ]]; then
            echo "❌ Archivo no encontrado: $TEST_FILE"
            exit 1
        fi
        # Detectar tipo de test por nombre
        if [[ "$1" == *"bigquery"* ]]; then
            TEST_TYPE="bq"
        else
            TEST_TYPE="pg"
        fi
        check_env_vars "$TEST_TYPE"
    else
        select_test
        check_env_vars "$TEST_TYPE"
    fi
    
    run_test
}

main "$@"

